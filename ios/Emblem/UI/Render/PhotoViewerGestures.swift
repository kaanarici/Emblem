import SwiftUI
import UIKit

struct PhotoViewerGestures: UIViewRepresentable {
    let isActive: Bool
    let isZoomed: Bool
    var allowsDragDismissal = false
    let onMagnify: (CGFloat) -> Void
    let onMagnifyEnd: () -> Void
    let onPan: (CGSize) -> Void
    let onPanEnd: (CGSize) -> Void
    let onDoubleTap: () -> Void

    func makeUIView(context: Context) -> Capture { Capture() }

    func updateUIView(_ view: Capture, context: Context) {
        view.callbacks = self
    }

    final class Capture: UIView, UIGestureRecognizerDelegate {
        var callbacks: PhotoViewerGestures?
        private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))

        init() {
            super.init(frame: .zero)
            backgroundColor = .clear
            isAccessibilityElement = false
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(magnify(_:)))
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(tapTwice(_:)))
            doubleTap.numberOfTapsRequired = 2
            for recognizer in [pan, pinch, doubleTap] {
                recognizer.cancelsTouchesInView = false
                recognizer.delaysTouchesBegan = false
                addGestureRecognizer(recognizer)
            }
        }

        required init?(coder: NSCoder) { nil }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let callbacks, callbacks.isActive else { return false }
            guard gestureRecognizer === pan else { return true }
            if callbacks.isZoomed { return true }
            guard callbacks.allowsDragDismissal else { return false }
            let velocity = pan.velocity(in: self)
            return velocity.y > abs(velocity.x)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let callbacks else { return false }
            return callbacks.isActive && (callbacks.isZoomed || callbacks.allowsDragDismissal)
                && gestureRecognizer === pan && otherGestureRecognizer is UIPanGestureRecognizer
        }

        @objc private func drag(_ recognizer: UIPanGestureRecognizer) {
            guard let callbacks, callbacks.isActive else { return }
            let translation = recognizer.translation(in: self)
            let value = CGSize(width: translation.x, height: translation.y)
            switch recognizer.state {
            case .began, .changed: callbacks.onPan(value)
            case .ended, .cancelled: callbacks.onPanEnd(value)
            default: break
            }
        }

        @objc private func magnify(_ recognizer: UIPinchGestureRecognizer) {
            guard let callbacks, callbacks.isActive else { return }
            switch recognizer.state {
            case .began, .changed: callbacks.onMagnify(recognizer.scale)
            case .ended, .cancelled: callbacks.onMagnifyEnd()
            default: break
            }
        }

        @objc private func tapTwice(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let callbacks, callbacks.isActive else { return }
            callbacks.onDoubleTap()
        }
    }
}
