import SwiftUI
import UIKit
import EmblemCore

struct ResponseNavigationMark: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let t = max(0, min(1, progress))
        func point(_ x: CGFloat, _ y: CGFloat, _ toX: CGFloat, _ toY: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (x + (toX - x) * t) * rect.width / 24,
                    y: rect.minY + (y + (toY - y) * t) * rect.height / 24)
        }
        var path = Path()
        path.move(to: point(4, 5, 6, 6.00085))
        path.addLine(to: point(16, 5, 17.9992, 18))
        path.move(to: point(4, 12, 12, 12))
        path.addLine(to: point(20, 12, 12, 12))
        path.move(to: point(4, 19, 18, 6))
        path.addLine(to: point(12, 19, 6.00081, 17.9992))
        return path
    }
}

struct ResponseWindowSafeArea: UIViewRepresentable {
    var updateTop: (CGFloat) -> Void
    var updateCornerRadius: (CGFloat) -> Void = { _ in }

    func makeUIView(context: Context) -> SafeAreaView {
        let view = SafeAreaView()
        view.isUserInteractionEnabled = false
        view.updateTop = updateTop
        view.updateCornerRadius = updateCornerRadius
        return view
    }

    func updateUIView(_ view: SafeAreaView, context: Context) {
        view.updateTop = updateTop
        view.updateCornerRadius = updateCornerRadius
        view.report()
    }

    final class SafeAreaView: UIView {
        var updateTop: ((CGFloat) -> Void)?
        var updateCornerRadius: ((CGFloat) -> Void)?
        private var reported: CGFloat?
        private var reportedRadius: CGFloat?
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); report() }
        override func layoutSubviews() { super.layoutSubviews(); report() }
        func report() {
            guard let window else { return }
            if window.safeAreaInsets.top != reported {
                let inset = window.safeAreaInsets.top
                reported = inset
                DispatchQueue.main.async { [weak self] in self?.updateTop?(inset) }
            }
            guard reportedRadius == nil else { return }
            let probe = UIView(frame: window.bounds)
            probe.isHidden = true
            probe.cornerConfiguration = .corners(radius: .containerConcentric())
            window.insertSubview(probe, at: 0)
            probe.layoutIfNeeded()
            let radius = probe.effectiveRadius(corner: .topLeft)
            probe.removeFromSuperview()
            guard radius > 0 else { return }
            reportedRadius = radius
            DispatchQueue.main.async { [weak self] in self?.updateCornerRadius?(radius) }
        }
    }
}
