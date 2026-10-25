import SwiftUI
import EmblemCore

struct SpotListView: View {
    let block: SpotList

    var body: some View {
        VStack(spacing: 22) {
            ForEach(Array(block.spots.enumerated()), id: \.offset) { _, spot in
                spotRow(spot)
            }
        }
        .padding(.horizontal, Theme.contentMargin)
    }

    private func card(for spot: SpotList.Spot) -> CardCarousel.Card {
        CardCarousel.Card(
            image: spot.image,
            imageURL: spot.imageURL,
            icon: nil,
            title: spot.name,
            caption: spot.caption,
            meta: spot.meta,
            prompt: "Tell me more about \(spot.name).")
    }

    private func spotRow(_ spot: SpotList.Spot) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 10) {
                Color.clear
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .overlay {
                        RemoteImage(
                            spec: spot.image.targeting(.landscape),
                            url: spot.imageURL.flatMap(URL.init(string:)),
                            maxPixelSize: 900,
                            showsSkeleton: true)
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(spot.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if let rating = spot.rating {
                        HStack(spacing: 4) {
                            Text(rating)
                                .font(.system(size: 16, weight: .semibold))
                                .monospacedDigit()
                            Image(systemName: "rosette")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Theme.ink)
                    }
                }
                if let caption = spot.caption {
                    Text(caption)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let meta = spot.meta {
                    Text(meta)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .modifier(ExpandsIntoSubpage(card: card(for: spot), blockID: block.id))
    }
}
