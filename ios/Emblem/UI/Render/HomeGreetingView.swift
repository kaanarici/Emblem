import SwiftUI
import EmblemCore

struct HomeGreetingView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let block: TextBlock
    let body_: AttributedString
    @Environment(\.renderedPage) private var renderedPage
    @Environment(\.performAction) private var performAction

    private var styledGreeting: AttributedString {
        var text = body_
        for run in text.runs {
            let strong = run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            text[run.range].font = Theme.greeting(strong: strong)
        }
        return text
    }

    private var nextEventActions: [Action] {
        guard let blocks = renderedPage?.visibleBlocks else { return [] }
        return blocks.compactMap { pageBlock -> [Action]? in
            guard case .mediaRowList(let list) = pageBlock,
                  list.id == "next-event-actions" else { return nil }
            return list.rows.compactMap(\.action)
        }.first ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(styledGreeting)
                .lineSpacing(0.4)
                .tracking(Theme.greetingTracking)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("home-greeting")

            if !nextEventActions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(nextEventActions, id: \.self) { action in
                        Button {
                            guard blockInteraction.allowsActivation else { return }
                            performAction(action)
                        } label: {
                            Text(action.label)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 15)
                                .frame(height: 44)
                                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .blockActivationControl()
                        .buttonStyle(.pressable)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.surfaceRim.opacity(0.7), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                        .accessibilityIdentifier("home-next-event-\(action.label.lowercased())")
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.homeMargin)
    }
}
