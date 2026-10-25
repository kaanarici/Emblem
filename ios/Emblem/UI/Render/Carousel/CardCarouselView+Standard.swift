import SwiftUI
import EmblemCore

extension CardCarouselView {
    var standardRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(keyedCards) { keyed in
                    let card = keyed.card
                    standardCard(card)
                        .containerRelativeFrame(.horizontal) { length, _ in
                            let content = length - standardMargin * 2
                            return isLargeStandard ? content * 0.75 : (content - 12) / 2
                        }
                        .id(keyed.id)
                        .transition(cardTransition)
                }
            }
            .padding(.horizontal, standardMargin)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollBounceBehavior(.basedOnSize)
        .scrollClipDisabled()
        .animation(.smooth(duration: 0.22), value: keyedCards.map(\.id))
    }

    private var isLargeStandard: Bool {
        block.cards.contains { $0.meta != nil || $0.strap != nil }
    }

    var standardGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  alignment: .leading, spacing: 22) {
            ForEach(keyedCards) { keyed in
                let card = keyed.card
                standardCard(card)
                    .id(keyed.id)
            }
        }
        .padding(.horizontal, standardMargin)
    }

    private var standardArtworkAspect: CGFloat {
        let portrait = block.cards.filter { $0.image?.aspect == .portrait || $0.image?.kind == .poster }.count
        let square = block.cards.filter { $0.image?.aspect == .square }.count
        let landscape = block.cards.count - portrait - square
        if portrait > max(square, landscape) { return 2 / 3 }
        if square > landscape { return 1 }
        let hasMedia = block.cards.contains { peer in
            if let image = peer.image { return image.kind != .object }
            return peer.imageURL.flatMap(URL.init(string:)) != nil
        }
        guard hasMedia else { return standardWidth / 110 }
        return isLargeStandard ? 3 / 2 : 4 / 3
    }

    private func standardCard(_ card: CardCarousel.Card) -> some View {
        let aspect = standardArtworkAspect
        let large = isLargeStandard
        return Button {
            guard blockInteraction.allowsStoreMutation else { return }
            cardAction(card)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .aspectRatio(aspect, contentMode: .fit)
                    .overlay {
                        CardArtworkView(card: card, maxPixelSize: large || aspect < 1 ? 1_200 : 800)
                    }
                    .overlay(alignment: .topLeading) {
                        if let tag = card.tag {
                            ArtworkQualitativeBadge(text: tag, cardRadius: large ? 20 : 12)
                                .padding(ArtworkQualitativeBadge.inset(cardRadius: large ? 20 : 12))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: large ? 20 : 12, style: .continuous))
                    .modifier(MediaArtworkShadow())

                VStack(alignment: .leading, spacing: 0) {
                    Text(card.title)
                        .font(.system(size: large ? 16 : 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    if let caption = card.caption {
                        Text(caption)
                            .font(.system(size: 14))
                            .lineSpacing(max(0, 18 - UIFont.systemFont(ofSize: 14).lineHeight))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(large ? 2 : 3)
                            .truncationMode(.tail)
                            .padding(.top, large ? 8 : 5)
                    }
                    if let meta = card.meta {
                        Text(meta)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                            .padding(.top, 5)
                    }
                    if let strap = card.strap {
                        Text(strap)
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .padding(.top, 8)
                    }
                }
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 4)
                .padding(.top, 13)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .blockStoreMutationControl()
        .buttonStyle(.pressable)
        .modifier(CardZoomSource(id: sourceTransitionID(for: card), namespace: expansionNamespace))
        .modifier(CardMenu(card: card))
    }
}
