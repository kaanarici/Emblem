import MapKit
import SwiftUI
import UIKit

struct SidebarDismissSurface: UIViewRepresentable {
    let onTap: () -> Void
    let onPanChanged: (CGFloat) -> Void
    let onPanEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap))
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SidebarDismissSurface

        init(parent: SidebarDismissSurface) {
            self.parent = parent
        }

        @objc func handleTap() {
            parent.onTap()
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view).x
            switch recognizer.state {
            case .began, .changed:
                parent.onPanChanged(translation)
            case .ended:
                parent.onPanEnded(translation, recognizer.velocity(in: recognizer.view).x)
            case .cancelled, .failed:
                parent.onPanEnded(0, 0)
            default:
                break
            }
        }
    }
}

struct SidebarOpeningPanGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        let translation = max(0, recognizer.translation(in: recognizer.view).x)
        switch recognizer.state {
        case .began, .changed:
            onChanged(translation)
        case .ended:
            recognizer.cancelsTouchesInView = false
            onEnded(translation, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            recognizer.cancelsTouchesInView = false
            onEnded(0, 0)
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var touch: UITouch?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            let begins = velocity.x > 0 && abs(velocity.x) > abs(velocity.y)
            pan.cancelsTouchesInView = begins
            if begins, let touch {
                for other in touch.gestureRecognizers ?? []
                where other !== pan && other.isEnabled && !(other.view is UIScrollView)
                    && !(other is UIScreenEdgePanGestureRecognizer) {
                    other.isEnabled = false
                    other.isEnabled = true
                }
            }
            return begins
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UIControl { return false }
                if let scrollView = current as? UIScrollView {
                    let horizontalOverflow = scrollView.contentSize.width - scrollView.bounds.width
                    if scrollView.alwaysBounceHorizontal || horizontalOverflow > 1 {
                        return false
                    }
                }
                view = current.superview
            }
            self.touch = touch
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

struct ExpansionZoomTransition: ViewModifier {
    let sourceID: String?
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if let sourceID, !reduceMotion {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

struct WindowEdgeGestures: UIViewRepresentable {
    let leftEnabled: () -> Bool
    let rightEnabled: () -> Bool
    let onLeft: () -> Void
    let onRight: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIView {
        let probe = UIView()
        probe.isUserInteractionEnabled = false
        return probe
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            coordinator?.installIfNeeded(from: view)
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: WindowEdgeGestures
        private var recognizer: UIPanGestureRecognizer?
        private weak var window: UIWindow?
        private var activeEdge: UIRectEdge?

        private static let edgeWidth: CGFloat = 30

        init(parent: WindowEdgeGestures) {
            self.parent = parent
        }

        func installIfNeeded(from view: UIView) {
            guard recognizer == nil, let window = view.window else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle))
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            window.addGestureRecognizer(pan)
            recognizer = pan
            self.window = window
        }

        func uninstall() {
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
        }

        @objc private func handle(_ pan: UIPanGestureRecognizer) {
            if pan.state == .ended || pan.state == .cancelled || pan.state == .failed {
                pan.cancelsTouchesInView = false
            }
            guard pan.state == .ended, let edge = activeEdge else {
                if pan.state == .cancelled || pan.state == .failed { activeEdge = nil }
                return
            }
            let direction: CGFloat = edge == .left ? 1 : -1
            let translation = pan.translation(in: pan.view).x * direction
            let velocity = pan.velocity(in: pan.view).x * direction
            activeEdge = nil
            if translation > 70 || velocity > 420 {
                edge == .left ? parent.onLeft() : parent.onRight()
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let edge = activeEdge else { return false }
            let velocity = pan.velocity(in: pan.view)
            guard abs(velocity.x) > abs(velocity.y) else { return false }
            let begins = edge == .left ? velocity.x > 0 : velocity.x < 0
            pan.cancelsTouchesInView = begins
            return begins
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let window else { return false }
            let x = touch.location(in: window).x
            let edge: UIRectEdge
            if x <= Self.edgeWidth, parent.leftEnabled() {
                edge = .left
            } else if x >= window.bounds.width - Self.edgeWidth, parent.rightEnabled() {
                edge = .right
            } else {
                return false
            }

            var candidate = touch.view
            while let current = candidate {
                if current is UIControl { return false }
                if current is MKMapView { return false }
                if let scrollView = current as? UIScrollView {
                    let overflow = scrollView.contentSize.width - scrollView.bounds.width
                    if scrollView.alwaysBounceHorizontal || overflow > 1 { return false }
                }
                candidate = current.superview
            }
            activeEdge = edge
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
