import SwiftUI
import EmblemCore

struct FlashcardsView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let block: Flashcards
    @State private var flipped: Set<Int> = []

    var body: some View {
        if !block.cards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if let title = block.title, !title.isEmpty {
                    Text(title)
                        .font(Theme.cardTitle())
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, Theme.contentMargin)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(block.cards.enumerated()), id: \.offset) { index, card in
                            flashcard(index, card)
                                .containerRelativeFrame(.horizontal) { width, _ in
                                    width - Theme.contentMargin * 2
                                }
                        }
                    }
                    .padding(.horizontal, Theme.contentMargin)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
                .scrollBounceBehavior(.basedOnSize)
                .scrollClipDisabled()
            }
        }
    }

    private func flashcard(_ index: Int, _ card: Flashcards.Card) -> some View {
        let isFlipped = flipped.contains(index)
        let counter = "\(index + 1)/\(block.cards.count)"
        return Button {
            guard blockInteraction.allowsActivation else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(duration: 0.4, bounce: 0)) {
                if isFlipped { flipped.remove(index) } else { flipped.insert(index) }
            }
        } label: {
            ZStack {
                face(counter, card.front, ink: Theme.ink, muted: Theme.inkSecondary, fill: Theme.chip)
                    .modifier(FlipFace(progress: isFlipped ? 1 : 0, isBack: false, reduceMotion: reduceMotion))
                face(counter, card.back, ink: Theme.onAccent, muted: Theme.onAccent.opacity(0.55), fill: Theme.accentDark)
                    .modifier(FlipFace(progress: isFlipped ? 1 : 0, isBack: true, reduceMotion: reduceMotion))
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.pressable)
        .blockActivationControl()
        .accessibilityIdentifier("flashcard-\(index)")
        .accessibilityLabel(card.front)
        .accessibilityValue(isFlipped ? card.back : "Answer hidden")
        .accessibilityHint(isFlipped ? "Hides the answer" : "Reveals the answer")
    }

    private func face(_ counter: String, _ text: String, ink: Color, muted: Color, fill: Color) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(ink)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
            .padding(24)
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .overlay(alignment: .topLeading) {
                Text(counter)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(muted)
                    .padding(16)
            }
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

private struct FlipFace: AnimatableModifier {
    var progress: Double
    let isBack: Bool
    let reduceMotion: Bool

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let rotation = isBack ? -180 + 180 * progress : 180 * progress
        let opacity = reduceMotion
            ? (isBack ? progress : 1 - progress)
            : (isBack == (progress >= 0.5) ? 1 : 0)

        content
            .rotation3DEffect(.degrees(reduceMotion ? 0 : rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .opacity(opacity)
    }
}
