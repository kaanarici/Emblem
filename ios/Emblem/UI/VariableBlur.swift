import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins
import QuartzCore

public enum VariableBlurDirection {
    case blurredTopClearBottom
    case blurredBottomClearTop
}

public struct VariableBlurView: UIViewRepresentable {
    public var maxBlurRadius: CGFloat = 8

    public var direction: VariableBlurDirection = .blurredTopClearBottom

    public var startOffset: CGFloat = 0.12

    public init(maxBlurRadius: CGFloat = 8, direction: VariableBlurDirection = .blurredTopClearBottom, startOffset: CGFloat = 0.12) {
        self.maxBlurRadius = maxBlurRadius
        self.direction = direction
        self.startOffset = startOffset
    }

    public func makeUIView(context: Context) -> VariableBlurUIView {
        VariableBlurUIView(maxBlurRadius: maxBlurRadius, direction: direction, startOffset: startOffset)
    }

    public func updateUIView(_ uiView: VariableBlurUIView, context: Context) {
    }
}

open class VariableBlurUIView: UIVisualEffectView {
    private var backdrop: CALayer?

    public init(maxBlurRadius: CGFloat = 8, direction: VariableBlurDirection = .blurredTopClearBottom, startOffset: CGFloat = 0.12, solidFraction: CGFloat = 0) {
        super.init(effect: UIBlurEffect(style: .regular))
        if !Self.forcesFallback, let filter = Self.variableBlurFilter(), let layer = subviews.first?.layer {
            filter.setValue(maxBlurRadius, forKey: "inputRadius")
            filter.setValue(Self.gradientImage(startOffset: startOffset, solidFraction: solidFraction, direction: direction),
                            forKey: "inputMaskImage")
            filter.setValue(true, forKey: "inputNormalizeEdges")
            layer.filters = [filter]
            for subview in subviews.dropFirst() { subview.alpha = 0 }
            backdrop = layer
        } else {
            effect = nil
            let blurredTop = direction == .blurredTopClearBottom
            let fade = LinearGradient(
                colors: [.black, .clear],
                startPoint: UnitPoint(x: 0.5, y: blurredTop ? solidFraction : 1 - solidFraction),
                endPoint: UnitPoint(x: 0.5, y: blurredTop ? 1 - startOffset : startOffset))
            let material = UIHostingConfiguration { Rectangle().fill(.ultraThinMaterial).mask(fade) }
                .margins(.all, 0).makeContentView()
            material.frame = contentView.bounds
            material.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.addSubview(material)
        }
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func didMoveToWindow() {
        guard let window, let backdrop else { return }
        backdrop.setValue(window.traitCollection.displayScale, forKey: "scale")
    }

    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    }

    private static var forcesFallback: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["EMBLEM_BLUR_FALLBACK"] != nil
        #else
        false
        #endif
    }

    private static func variableBlurFilter() -> NSObject? {
        let factory = NSSelectorFromString("filterWithType:")
        guard let type = NSClassFromString("CAFilter") as? NSObject.Type, type.responds(to: factory) else { return nil }
        return type.perform(factory, with: "variableBlur")?.takeUnretainedValue() as? NSObject
    }

    private static func gradientImage(startOffset: CGFloat, solidFraction: CGFloat, direction: VariableBlurDirection) -> CGImage {
        let side: CGFloat = 100
        let gradient = CIFilter.smoothLinearGradient()
        gradient.color0 = CIColor.black
        gradient.color1 = CIColor.clear
        gradient.point0 = CGPoint(x: 0, y: side * (1 - solidFraction))
        gradient.point1 = CGPoint(x: 0, y: startOffset * side)
        if case .blurredBottomClearTop = direction {
            gradient.point0.y = side * solidFraction
            gradient.point1.y = side - gradient.point1.y
        }
        return CIContext().createCGImage(gradient.outputImage!, from: CGRect(x: 0, y: 0, width: side, height: side))!
    }
}
