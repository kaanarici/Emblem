import SwiftUI
import EmblemCore

struct ListBlockView: View {
    let block: ListBlock

    private var showsCustomIcons: Bool {
        ListIconPolicy.showsIcons(block.items.map(\.icon))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Group {
                        if showsCustomIcons, let icon = item.icon {
                            IconView(icon: icon, size: 18, loadingSkeleton: true)
                        } else {
                            Image(systemName: block.style == .check ? "checkmark.circle" : "circle.fill")
                                .font(.system(size: block.style == .check ? 17 : 6))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .frame(width: 24)
                    Text(item.text)
                        .font(Theme.body())
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.textMargin)
    }
}

struct StatRowView: View {
    let block: StatRow

    private var hasAnyDelta: Bool { block.stats.contains { $0.delta != nil } }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(block.stats.enumerated()), id: \.offset) { _, stat in
                VStack(spacing: 6) {
                    Text(stat.value)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(stat.label)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(height: hasAnyDelta ? 32 : nil, alignment: .top)
                    if let delta = stat.delta {
                        HStack(spacing: 3) {
                            if let direction = stat.deltaDirection {
                                Image(systemName: direction == .up ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Text(delta)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(deltaTint(stat.deltaDirection))
                        .accessibilityLabel(deltaLabel(delta, direction: stat.deltaDirection))
                    } else if hasAnyDelta {
                        Text("–")
                            .font(.system(size: 13, weight: .semibold))
                            .opacity(0)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.vertical, 18)
                .cardBackground(radius: 18)
            }
        }
        .padding(.horizontal, Theme.contentMargin)
    }

    private func deltaTint(_ direction: StatRow.Stat.Direction?) -> Color {
        switch direction {
        case .up: Theme.positive
        case .down: Theme.negative
        case nil: Theme.inkSecondary
        }
    }

    private func deltaLabel(_ delta: String, direction: StatRow.Stat.Direction?) -> String {
        switch direction {
        case .up: "Increase, \(delta)"
        case .down: "Decrease, \(delta)"
        case nil: delta
        }
    }
}
