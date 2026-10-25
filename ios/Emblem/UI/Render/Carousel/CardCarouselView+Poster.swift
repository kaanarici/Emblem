import SwiftUI
import EmblemCore

extension CardCarouselView {
    var posterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(keyedCards) { keyed in
                    let card = keyed.card
                    posterCard(card, width: posterWidth)
                        .id(keyed.id)
                        .transition(cardTransition)
                }
            }
            .padding(.horizontal, posterMargin)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollBounceBehavior(.basedOnSize)
        .scrollClipDisabled()
        .animation(.smooth(duration: 0.22), value: keyedCards.map(\.id))
    }

    var posterGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  alignment: .leading, spacing: 22) {
            ForEach(keyedCards) { keyed in
                let card = keyed.card
                posterCard(card, width: nil)
                    .id(keyed.id)
            }
        }
        .padding(.horizontal, posterMargin)
    }

    private func posterCard(_ card: CardCarousel.Card, width: CGFloat?) -> some View {
        Button {
            guard blockInteraction.allowsStoreMutation else { return }
            cardAction(card)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay {
                        CardArtworkView(card: card, maxPixelSize: 1_200)
                            .modifier(PosterArtworkTreatment())
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(card.title)
                                .font(.system(size: 16, weight: .semibold))
                                .lineLimit(2)
                            if let meta = card.meta {
                                Text(meta)
                                    .font(.system(size: 14))
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .padding(12)
                    }
                    .overlay(alignment: .topLeading) {
                        if let tag = card.tag {
                            ArtworkQualitativeBadge(text: tag)
                                .padding(ArtworkQualitativeBadge.inset(cardRadius: 20))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .modifier(MediaArtworkShadow())

                if let caption = card.caption {
                    Text(caption)
                        .font(.system(size: 14))
                        .lineSpacing(max(0, 18 - UIFont.systemFont(ofSize: 14).lineHeight))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 4)
                }
                if let strap = card.strap {
                    Text(strap)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .blockStoreMutationControl()
        .buttonStyle(.pressable)
        .modifier(CardZoomSource(id: sourceTransitionID(for: card), namespace: expansionNamespace))
        .modifier(CardMenu(card: card))
        .overlay(alignment: .topTrailing) {
            CarouselBookmarkButton(card: card, blockID: block.id, presentation: .poster)
        }
    }
}
