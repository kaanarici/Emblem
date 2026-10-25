import SwiftUI
import EmblemCore

extension CardCarouselView {
    var hotelRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(keyedCards) { keyed in
                    let card = keyed.card
                    hotelFamilyCard(card, width: 288, aspect: 3 / 2, style: .rail)
                        .id(keyed.id)
                        .transition(cardTransition)
                }
            }
            .padding(.horizontal, 28)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollBounceBehavior(.basedOnSize)
        .scrollClipDisabled()
        .animation(.smooth(duration: 0.22), value: keyedCards.map(\.id))
    }

    var hotelList: some View {
        LazyVStack(alignment: .leading, spacing: 40) {
            ForEach(keyedCards) { keyed in
                let card = keyed.card
                hotelFamilyCard(card, width: nil, aspect: 3 / 2, style: .hotel, bookmarkStyle: .paged)
                    .id(keyed.id)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
    }

    var roomGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                  alignment: .leading, spacing: 22) {
            ForEach(keyedCards) { keyed in
                let card = keyed.card
                hotelFamilyCard(card, width: nil, aspect: 1, style: .grid, bookmark: false)
                    .id(keyed.id)
            }
        }
        .padding(.horizontal, 28)
    }

    var roomList: some View {
        LazyVStack(alignment: .leading, spacing: 44) {
            ForEach(keyedCards) { keyed in
                let card = keyed.card
                hotelFamilyCard(card, width: nil, aspect: 3 / 2, style: .list)
                    .id(keyed.id)
            }
        }
        .padding(.horizontal, 28)
    }

    private enum HotelCardStyle {
        case rail, list, grid, hotel

        var titleSize: CGFloat { self == .grid ? 14 : self == .hotel ? 16 : 17 }
        var captionSize: CGFloat { self == .grid ? 14 : self == .rail ? 15 : self == .hotel ? 16 : 17 }
        var captionLineHeight: CGFloat { self == .grid ? 18 : self == .rail ? 19 : 22 }
        var metaSize: CGFloat { self == .grid || self == .hotel ? 14 : 15 }
        var artworkSpacing: CGFloat { self == .grid ? 8 : self == .rail ? 12 : 15 }
        var titleGap: CGFloat { self == .grid ? 14 / 3 : self == .rail ? 6 : 8 }
        var captionGap: CGFloat { self == .grid ? 8 : self == .rail ? 2 : 4 }
    }

    private func hotelFamilyCard(
        _ card: CardCarousel.Card, width: CGFloat?, aspect: CGFloat, style: HotelCardStyle,
        bookmark: Bool = true, bookmarkStyle: CardCarousel.Presentation = .standard
    ) -> some View {
        let centered = style == .grid
        let alignment: HorizontalAlignment = centered ? .center : .leading
        let textAlignment: TextAlignment = centered ? .center : .leading
        let fullWidth = style == .list || style == .hotel
        return Button {
            guard blockInteraction.allowsStoreMutation, !(fullWidth && listCardPanned) else { return }
            cardAction(card)
        } label: {
            VStack(alignment: alignment, spacing: style.artworkSpacing) {
                Color.clear
                    .aspectRatio(aspect, contentMode: .fit)
                    .overlay {
                        CardArtworkView(card: card, maxPixelSize: style == .list || style == .hotel ? 1_200 : 800)
                    }
                    .overlay(alignment: centered ? .bottomLeading : .topLeading) {
                        if let tag = card.tag {
                            ArtworkQualitativeBadge(text: tag)
                                .padding(ArtworkQualitativeBadge.inset(cardRadius: 20))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .modifier(MediaArtworkShadow())

                VStack(alignment: alignment, spacing: 0) {
                    Text(card.title)
                        .font(.system(size: style.titleSize, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.bottom, style.titleGap)
                    if let caption = card.caption {
                        Text(caption)
                            .font(.system(size: style.captionSize))
                            .lineSpacing(max(0, style.captionLineHeight
                                - UIFont.systemFont(ofSize: style.captionSize).lineHeight))
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(.bottom, style.captionGap)
                    }
                    if let meta = card.meta {
                        Text(meta)
                            .font(.system(size: style.metaSize))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    if let strap = card.strap {
                        Text(strap)
                            .font(.system(size: style == .hotel ? 16 : 17,
                                          weight: style == .list || style == .hotel ? .regular : .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.top, style == .hotel ? 7 : 8)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(textAlignment)
                .padding(.horizontal, 4)
            }
            .frame(width: width, alignment: centered ? .center : .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .blockStoreMutationControl()
        .buttonStyle(.pressable)
        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
            guard fullWidth, abs(value.translation.width) > abs(value.translation.height) else { return }
            listCardPanned = true
        }.onEnded { _ in
            DispatchQueue.main.async { listCardPanned = false }
        }, including: fullWidth ? .all : .subviews)
        .modifier(CardZoomSource(id: sourceTransitionID(for: card), namespace: expansionNamespace))
        .modifier(CardMenu(card: card))
        .overlay(alignment: .topTrailing) {
            if bookmark {
                CarouselBookmarkButton(card: card, blockID: block.id, presentation: bookmarkStyle)
            }
        }
    }
}
