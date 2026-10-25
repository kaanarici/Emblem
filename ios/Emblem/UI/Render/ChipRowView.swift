import SwiftUI
import EmblemCore

struct ChipRowView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let block: ChipRow
    @Environment(\.performAction) private var performAction
    @Environment(ConversationStore.self) private var store
    @Environment(\.renderedPage) private var renderedPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arriving = false
    @State private var settledIcons: [ImageSpec?]?
    @State private var entrance = false
    @State private var appearedAt = Date()
    @State private var rowDelay = 0.38

    var body: some View {
        if block.role == .requiredChoice,
           let question = block.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !question.isEmpty {
            let icons = block.chips.compactMap(\.icon)
            RequiredChoiceView(
                id: block.id,
                question: question,
                options: block.chips.map(\.label),
                presentation: icons.count == block.chips.count ? .cards(icons) : .chips)
        } else if block.role == .followUp {
            VStack(spacing: 46) {
                if let title = block.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !title.isEmpty {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .modifier(FollowUpArrival(hidden: arriving, delay: 0.13, animated: entrance))
                }
                rows(gated: true)
            }
            .padding(.horizontal, Theme.homeMargin)
            .padding(.top, 48)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
            .onAppear {
                appearedAt = Date()
                if settledIcons == nil {
                    let stored = renderedPage?.settledFollowUpIcons[block.id]
                    settledIcons = stored?.count == block.chips.count
                        ? stored : FollowUpIconGate.settledFromCache(block.chips)
                    if let settledIcons { renderedPage?.settledFollowUpIcons[block.id] = settledIcons }
                }
                guard !reduceMotion, renderedPage?.claimFollowUpReveal() == true else { return }
                entrance = true
                arriving = true
                DispatchQueue.main.async { arriving = false }
            }
            .task(id: block.chips) {
                guard settledIcons == nil else { return }
                let settled = await FollowUpIconGate.settle(block.chips)
                guard !Task.isCancelled else { return }
                renderedPage?.settledFollowUpIcons[block.id] = settled
                rowDelay = max(0, 0.38 - Date().timeIntervalSince(appearedAt))
                settledIcons = settled
            }
        } else {
            rows(gated: false)
                .padding(.horizontal, Theme.contentMargin)
        }
    }

    private func chipIcon(at index: Int, gated: Bool) -> Icon? {
        guard gated, var icon = block.chips[index].icon else { return block.chips[index].icon }
        icon.image = settledIcons?.indices.contains(index) == true ? settledIcons?[index] : nil
        return icon
    }

    private func rows(gated: Bool) -> some View {
        VStack(spacing: 3) {
            ForEach(Array(block.chips.enumerated()), id: \.offset) { index, chip in
                Button {
                    guard blockInteraction.allowsStoreMutation else { return }
                    performAction(Action(label: chip.label, prompt: chip.prompt ?? chip.label))
                } label: {
                    HStack(spacing: 0) {
                        Text(chip.label)
                            .font(.system(size: 14))
                            .lineSpacing(1.5)
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Spacer(minLength: 10)
                        HStack(spacing: -9) {
                            if let icon = chipIcon(at: index, gated: gated) {
                                ZStack {
                                    Circle().fill(Theme.followUpDisc)
                                    IconView(icon: icon, size: 40)
                                }
                                .frame(width: 64, height: 64)
                            }
                            ZStack {
                                Circle().fill(Theme.followUpDisc).frame(width: 24, height: 24)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                            }
                            .frame(width: 30, height: 44)
                            .overlay {
                                Circle()
                                    .stroke(Theme.surface, lineWidth: 2)
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: index == 0 ? 18 : 6,
                            bottomLeadingRadius: index == block.chips.count - 1 ? 18 : 6,
                            bottomTrailingRadius: index == block.chips.count - 1 ? 18 : 6,
                            topTrailingRadius: index == 0 ? 18 : 6,
                            style: .continuous)
                            .fill(Theme.surface))
                    .contentShape(Rectangle())
                }
                .blockStoreMutationControl()
                .buttonStyle(.pressable)
                .accessibilityValue(chip.prompt ?? chip.label)
                .modifier(FollowUpArrival(
                    hidden: arriving || (gated && settledIcons == nil),
                    delay: rowDelay + Double(index) * 0.05,
                    animated: entrance))
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

private struct FollowUpArrival: ViewModifier {
    let hidden: Bool
    let delay: Double
    let animated: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .animation(hidden || !animated ? nil : .easeOut(duration: 0.22).delay(delay), value: hidden)
    }
}
