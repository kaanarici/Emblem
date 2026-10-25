import SwiftUI
import EmblemCore

struct TimelineView_: View {
    let block: Timeline
    private static let markerSize: CGFloat = 26
    private var railWidth: CGFloat {
        block.items.contains { $0.icon != nil } ? Self.markerSize : 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(block.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        if item.icon != nil {
                            IconView(icon: item.icon, size: Self.markerSize)
                                .frame(width: Self.markerSize, height: Self.markerSize)
                        } else {
                            Circle()
                                .fill(Theme.ink)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                        }
                        if index < block.items.count - 1 {
                            Rectangle()
                                .fill(Theme.inkSecondary.opacity(0.25))
                                .frame(width: 2)
                                .padding(.top, 7)
                                .padding(.bottom, 1)
                        }
                    }
                    .frame(width: railWidth)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.time)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .textCase(.uppercase)
                        Text(item.title)
                            .font(Theme.cardTitle())
                            .foregroundStyle(Theme.ink)
                        if let caption = item.caption {
                            Text(caption)
                                .font(Theme.caption())
                                .foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.bottom, index < block.items.count - 1 ? 24 : 0)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, Theme.textMargin)
    }
}
