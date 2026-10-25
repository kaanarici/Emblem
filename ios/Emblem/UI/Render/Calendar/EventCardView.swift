import SwiftUI
import EmblemCore

struct EventCardView: View {
    let block: EventCard

    private func card(for event: EventCard.Event) -> CardCarousel.Card {
        CardCarousel.Card(
            image: nil,
            imageURL: nil,
            icon: event.icon,
            title: event.title,
            caption: event.timeRange,
            meta: block.dayLabel,
            prompt: event.prompt ?? "Tell me more about my calendar event " +
                "\"\(event.title)\" on \(block.dayLabel) (\(event.timeRange))" +
                (event.place.map { $0.isEmpty ? "" : " at \($0)" } ?? "") + ".")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(block.dayLabel)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 8)

            VStack(spacing: 10) {
                ForEach(Array(block.events.enumerated()), id: \.offset) { _, event in
                    HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.timeRange)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.inkSecondary)
                                Text(event.title)
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                            }
                            Spacer(minLength: 10)
                            IconView(icon: event.icon, size: 40)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .modifier(ExpandsIntoSubpage(card: card(for: event), blockID: block.id, elevation: .flat(18)))
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .cardBackground(radius: 24)
        .padding(.horizontal, Theme.contentMargin)
    }
}
