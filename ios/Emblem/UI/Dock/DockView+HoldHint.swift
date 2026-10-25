import SwiftUI

extension DockView {
    static let holdHintText = "Hold to speak"

    static let holdHintWidth: CGFloat = {
        let text = (holdHintText as NSString).size(withAttributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .kern: ShimmerText.tracking,
        ]).width
        return ceil(text) + 2 * 26
    }()

    var holdHintEligible: Bool {
        store.dockState == .idle && speech.phase == .idle && sidebarProgress == 0
            && !store.dockShowsGenerationStop && !store.isOpeningConversation
            && activeTrailingControl == nil && !accessibilitySuppressed
    }
}

struct HoldHintScheduler: ViewModifier {
    let dock: DockView

    func body(content: Content) -> some View {
        let eligible = dock.holdHintEligible
        content
            .task(id: "\(eligible)-\(dock.holdHint)") {
                guard eligible, !dock.holdHint else { return }
                while !Task.isCancelled {
                    let wait = dock.holdHintDelay - Date().timeIntervalSince(TouchActivity.shared.last)
                    if wait <= 0 { break }
                    try? await Task.sleep(for: .seconds(wait))
                }
                guard !Task.isCancelled, dock.holdHintEligible else { return }
                dock.holdHint = true
            }
            .onChange(of: dock.holdHint, initial: true) { _, shown in
                if shown {
                    TouchActivity.shared.onTouch = { dismiss() }
                } else {
                    TouchActivity.shared.onTouch = nil
                }
            }
            .onChange(of: eligible) { _, isEligible in
                if !isEligible { dock.holdHint = false }
            }
            .onChange(of: dock.speech.phase) { _, phase in
                if phase == .held { dock.holdHintDelay = 90 }
            }
    }

    private func dismiss() {
        TouchActivity.shared.onTouch = nil
        dock.holdHint = false
        dock.holdHintDelay = min(dock.holdHintDelay * 2.5, 120)
    }
}
