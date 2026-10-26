import PhotosUI
import SwiftUI
import EmblemCore

extension DockView {
    static let micRadius = innerControlSize / 2
    static let micWidth: CGFloat = 96
    static let newPageWidth: CGFloat = 103

    var micShape: some View {
        AnodizedSurface(shape: RoundedRectangle(cornerRadius: Self.micRadius, style: .continuous))
    }

    static let lockDistance: CGFloat = 60

    @ViewBuilder
    var lockBadge: some View {
        if speech.phase == .held || speech.phase == .locked || lockReleasing {
            let locked = speech.phase == .locked
            let pull = locked ? 1 : min(1, lockPull / Self.lockDistance)
            Image(systemName: locked ? "lock.fill" : "lock.open")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(locked ? accent.glyph : Theme.inkSecondary)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp)))
                .frame(width: 36, height: 36)
                .background {
                    Circle().fill(Theme.card)
                    Circle().fill(accent.color).opacity(locked ? 1 : 0.35 * pull)
                }
                .scaleEffect(1 + 0.12 * pull * (locked ? 0 : 1))
                .offset(y: -52 - 10 * pull * (locked ? 0 : 1))
                .accessibilityIdentifier("voice-lock-status")
                .accessibilityLabel(locked ? "Recording locked" : "Slide up to lock")
                .transition(reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .scale(scale: 0.6).combined(with: .opacity)
                            .combined(with: .offset(y: 10))
                            .animation(.spring(duration: 0.34, bounce: 0.18)),
                        removal: .scale(scale: 0.4, anchor: .bottom).combined(with: .opacity)
                            .combined(with: .offset(y: 18))
                            .animation(.smooth(duration: 0.26))))
                .animation(.interactiveSpring(duration: 0.14, extraBounce: 0), value: lockPull)
                .animation(.spring(duration: 0.36, bounce: 0.3), value: speech.phase)
        }
    }

    func isQuestionContinue(_ control: DockTrailingControl?) -> Bool {
        guard case .action(let action) = control, action != ConversationStore.doneAction else { return false }
        return action == ConversationStore.continueAction
            || action == ConversationStore.nextAction
            || store.hasEditableQuestions
    }

    func isDone(_ control: DockTrailingControl?) -> Bool {
        guard case .action(let action) = control else { return false }
        return action == ConversationStore.doneAction
    }

    static let wideMicWidth: CGFloat = 73.4
    private static let questionPairSpacing: CGFloat = 6.6

    func pairSpacing(_ control: DockTrailingControl) -> CGFloat {
        isQuestionContinue(control) ? Self.questionPairSpacing : 4
    }

    func trailingWidth(_ control: DockTrailingControl) -> CGFloat {
        if isQuestionContinue(control) { return wideContinueWidth }
        if isDone(control) { return Self.innerControlSize }
        let text = (control.label as NSString).size(withAttributes: [
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)]).width
        return ceil(text) + 28
    }

    private var wideContinueWidth: CGFloat {
        let screen = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.width }.first ?? 440
        let ring = screen - 2 * 18 - 2 * 44 - 2 * 10
        return ring - 2 * Self.capsuleInset - Self.wideMicWidth - Self.questionPairSpacing
    }

    func trailingPill(_ control: DockTrailingControl) -> some View {
        Button {
            switch control {
            case .retry:
                store.retryCurrentGeneration()
            case .action(let action):
                if action == ConversationStore.doneAction, store.activeQuestion != nil {
                    store.confirmQuestion()
                } else if isQuestionContinue(control), store.requiredAnswersMissing {
                    missingAnswersNudges += 1
                    store.flagMissingAnswers()
                } else {
                    performAction(action)
                }
            }
        } label: {
            if isDone(control) {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent.glyph)
                    .frame(width: Self.innerControlSize, height: Self.innerControlSize)
                    .background(AnodizedSurface(shape: Circle()))
                    .contentShape(Circle())
            } else {
                Text(control.label)
                    .font(.system(size: isQuestionContinue(control) ? 14.3 : 17, weight: .semibold))
                    .foregroundStyle(accent.glyph)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: control.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.tail)
                    .padding(.horizontal, 14)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: isQuestionContinue(control) ? wideContinueWidth : nil)
                    .frame(height: Self.innerControlSize)
                    .background(AnodizedSurface(shape: Capsule()))
                    .contentShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(control == .retry ? "Retry response" : control.label)
        .accessibilityHint(control == .retry ? "Generates the failed response again" : "")
        .accessibilityIdentifier(control == .retry ? "generation-retry" : "dock-action")
    }
}
