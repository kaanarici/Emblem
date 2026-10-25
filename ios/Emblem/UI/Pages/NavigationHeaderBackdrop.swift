import SwiftUI
import UIKit

struct NavigationHeaderBackdrop: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    var visible: Bool
    var faded = false
    var deep = true

    func makeUIView(context: Context) -> Mount { Mount() }

    func updateUIView(_ view: Mount, context: Context) {
        view.backdrop.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        view.backdrop.isHidden = !visible
        view.backdrop.deep = deep
        let alpha: CGFloat = faded ? 0 : 1
        if view.backdrop.alpha != alpha {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                view.backdrop.alpha = alpha
            }
        }
        view.attach()
    }

    static func dismantleUIView(_ view: Mount, coordinator: ()) {
        view.backdrop.removeFromSuperview()
    }

    final class Mount: UIView {
        let backdrop = Backdrop()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attach()
        }

        func attach() {
            guard window != nil else { return }
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController,
                   let navigation = controller.navigationController {
                    let bar = navigation.navigationBar
                    if backdrop.superview !== navigation.view {
                        navigation.view.insertSubview(backdrop, belowSubview: bar)
                    }
                    let bottom = bar.convert(bar.bounds, to: navigation.view).maxY
                    backdrop.frame = CGRect(x: 0, y: 0, width: navigation.view.bounds.width, height: bottom + backdrop.reach)
                    return
                }
                responder = current.next
            }
        }
    }

    final class Backdrop: UIView {
        private var blur = VariableBlurUIView(maxBlurRadius: 4, startOffset: 0)
        private let wash = CAGradientLayer()

        var deep = true {
            didSet {
                guard deep != oldValue else { return }
                blur.removeFromSuperview()
                blur = VariableBlurUIView(maxBlurRadius: deep ? 4 : 8, startOffset: deep ? 0 : 0.12)
                insertSubview(blur, at: 0)
                if window != nil { blur.didMoveToWindow() }
                superview?.setNeedsLayout()
                setNeedsLayout()
            }
        }

        var reach: CGFloat { deep ? 36 : 28 }

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            accessibilityElementsHidden = true
            addSubview(blur)
            wash.locations = [0, 0.65, 1]
            layer.addSublayer(wash)
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            blur.frame = bounds
            let paper = UIColor(Theme.responsePaper).resolvedColor(with: traitCollection)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            wash.frame = bounds
            wash.colors = (deep ? [0.65, 0.38, 0] : [0, 0, 0]).map { paper.withAlphaComponent($0).cgColor }
            CATransaction.commit()
        }

        override var overrideUserInterfaceStyle: UIUserInterfaceStyle {
            didSet { setNeedsLayout() }
        }
    }
}
