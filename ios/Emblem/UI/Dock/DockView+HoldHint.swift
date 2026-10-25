import SwiftUI

extension DockView {
    static let holdHintText = "Hold to speak"

    static let holdHintWidth: CGFloat = {
        let text = (holdHintText as NSString).size(withAttributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .kern: ShimmerText.tracking,
        ]).width
        return ceil(text) + 16 + 8 + 2 * 24
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
        let touched = TouchActivity.shared.last
        content
            .task(id: "\(touched.timeIntervalSinceReferenceDate)-\(eligible)") {
                guard eligible, !dock.holdHint else { return }
                try? await Task.sleep(for: .seconds(dock.holdHintDelay))
                guard !Task.isCancelled, dock.holdHintEligible else { return }
                dock.holdHint = true
            }
            .onChange(of: touched) { _, _ in
                guard dock.holdHint else { return }
                dock.holdHint = false
                dock.holdHintDelay = min(dock.holdHintDelay * 2.5, 120)
            }
            .onChange(of: eligible) { _, isEligible in
                if !isEligible { dock.holdHint = false }
            }
            .onChange(of: dock.speech.phase) { _, phase in
                if phase == .held { dock.holdHintDelay = 90 }
            }
    }
}
