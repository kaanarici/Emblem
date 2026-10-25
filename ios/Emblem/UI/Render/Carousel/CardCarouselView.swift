import SwiftUI
import EmblemCore

struct ArtworkQualitativeBadge: View {
    let text: String
    var cardRadius: CGFloat = 20
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    static func inset(cardRadius: CGFloat) -> CGFloat { cardRadius >= 20 ? 10 : 6 }

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: max(6, cardRadius - Self.inset(cardRadius: cardRadius)), style: .continuous)
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background {
                if reduceTransparency {
                    shape.fill(Color(red: 0.20, green: 0.23, blue: 0.28))
                } else {
                    shape.fill(.ultraThinMaterial)
                        .overlay {
                            shape.fill(Color(red: 0.16, green: 0.20, blue: 0.26).opacity(0.45))
                        }
                }
            }
            .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
            .environment(\.colorScheme, .dark)
    }
}

struct CardCarouselView: View {
    @Environment(\.blockInteraction) var blockInteraction
    let block: CardCarousel
    @Environment(\.performAction) var performAction
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.renderedPage) var renderedPage
    @Environment(\.expansionNamespace) var expansionNamespace

    @State var pagedSelectedCardID: String?
    @State var listCardPanned = false

    let cardWidth: CGFloat = 165
    let ideaCardWidth: CGFloat = 260
    let featureCardWidth: CGFloat = 252
    let posterWidth: CGFloat = 220
    let posterMargin: CGFloat = 28
    let standardWidth: CGFloat = 186
    let standardMargin: CGFloat = 28

    private var isManagedRail: Bool {
        block.cards.contains { $0.conversation != nil || $0.automation != nil }
    }

    var isIdeaRail: Bool { block.id == "ideas" }

    private var usesPosterPresentation: Bool {
        block.presentation == .poster && !isManagedRail && !isIdeaRail
    }

    private var usesStandardPresentation: Bool {
        block.presentation == .standard && !isManagedRail && !isIdeaRail
    }

    private var usesPagedPresentation: Bool {
        block.presentation == .paged && !isManagedRail && !isIdeaRail
    }

    var isFeatureRail: Bool {
        !isManagedRail && !isIdeaRail && block.cards.count <= 4 &&
            block.cards.allSatisfy { card in
                card.image != nil || card.imageURL.flatMap(URL.init(string:)) != nil
            }
    }

    var railCardWidth: CGFloat { isFeatureRail ? featureCardWidth : cardWidth }

    private var isGrid: Bool {
        block.layout == .grid && !isManagedRail && !isIdeaRail && block.cards.count > 1
    }

    var body: some View {
        if block.presentation == .hotelRail && !isManagedRail && !isIdeaRail {
            hotelRail
        } else if block.presentation == .hotelList && !isManagedRail && !isIdeaRail {
            hotelList
        } else if block.presentation == .roomGrid && !isManagedRail && !isIdeaRail {
            roomGrid
        } else if block.presentation == .roomList && !isManagedRail && !isIdeaRail {
            roomList
        } else if usesPagedPresentation {
            pagedRail
        } else if usesPosterPresentation {
            if isGrid {
                posterGrid
            } else {
                posterRail
            }
        } else if usesStandardPresentation {
            if isGrid {
                standardGrid
            } else {
                standardRail
            }
        } else if isGrid {
            gridWall
        } else if block.cards.count == 1, let card = block.cards.first, !isManagedRail {
            singleCard(card)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: isIdeaRail ? 8 : 14) {
                    ForEach(keyedCards) { keyed in
                        let card = keyed.card
                        carouselCard(card)
                            .id(keyed.id)
                            .transition(cardTransition)
                    }
                }
                .padding(.horizontal, renderedPage?.isHome == true ? Theme.homeMargin : Theme.contentMargin)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollBounceBehavior(.basedOnSize)
            .scrollClipDisabled()
            .animation(.smooth(duration: 0.22), value: keyedCards.map(\.id))
        }
    }
    @Environment(ConversationStore.self) var store
}
