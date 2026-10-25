import Observation
import UIKit

@Observable @MainActor
final class KeyboardPresence {
    static let shared = KeyboardPresence()

    private(set) var isVisible = false
    private(set) var lastHeight: CGFloat = 336

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { note in
            let height = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height
            MainActor.assumeIsolated {
                KeyboardPresence.shared.isVisible = true
                if let height, height > 0 { KeyboardPresence.shared.lastHeight = height }
            }
        }
        center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { KeyboardPresence.shared.isVisible = false }
        }
    }
}
