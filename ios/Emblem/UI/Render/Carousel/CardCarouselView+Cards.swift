import SwiftUI
import EmblemCore

extension CardCarouselView {
    var cardTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.96, anchor: .leading))
    }

    func cardAction(_ card: CardCarousel.Card) {
        if isIdeaRail {
            performAction(Action(label: card.title, prompt: card.prompt ?? card.title))
            return
        }
        if card.conversation != nil || card.automation != nil {
            performAction(Action(
                label: card.title,
                conversation: card.conversation,
                openAutomation: card.automation, expansion: true))
        } else {
            guard let renderedPage else { return }
            store.openExpansion(card: card, blockID: block.id, from: renderedPage)
        }
    }

    @ViewBuilder
    func carouselCard(_ card: CardCarousel.Card) -> some View {
        if isIdeaRail {
            ideaCard(card)
        } else if card.conversation != nil || card.automation != nil {
            if block.id == "recent" {
                homeContinueCard(card)
                    .accessibilityIdentifier("home-recent-\(card.conversation ?? card.title)")
                    .overlay(alignment: .topTrailing) {
                        if let key = card.conversation {
                            CarouselPinButton(
                                conversation: key, title: card.title,
                                tint: isTextContinueCard(card) ? Theme.ink : .white)
                        }
                    }
            } else {
                managedCard(card)
            }
        } else {
            cardBody(card, width: railCardWidth, captionLines: 3, corner: 16) {
                cardImage(card)
                    .frame(width: railCardWidth, height: tileHeight(card))
            }
        }
    }

    var gridWall: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 14, alignment: .top),
                GridItem(.flexible(), spacing: 14, alignment: .top),
            ],
            alignment: .leading,
            spacing: 22
        ) {
            ForEach(keyedCards) { keyed in
                let card = keyed.card
                cardBody(card, width: nil, captionLines: 3, corner: 16) {
                    Color.clear
                        .aspectRatio(1.38, contentMode: .fit)
                        .overlay { cardImage(card) }
                }
                .id(keyed.id)
            }
        }
        .padding(.horizontal, Theme.contentMargin)
    }

    private func ideaCard(_ card: CardCarousel.Card) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            guard blockInteraction.allowsStoreMutation else { return }
            cardAction(card)
        } label: {
            HStack(spacing: 12) {
                ideaArtwork(card)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                Text(card.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineSpacing(1.3)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(width: ideaCardWidth, height: 80, alignment: .leading)
            .background(Theme.surface, in: shape)
            .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)
            .shadow(color: .black.opacity(0.09), radius: 12, y: 5)
            .contentShape(.interaction, shape)
        }
        .blockStoreMutationControl()
        .buttonStyle(.pressable)
        .textSelection(.disabled)
        .accessibilityLabel(card.title)
        .accessibilityIdentifier("home-idea-card")
    }

    @ViewBuilder
    private func ideaArtwork(_ card: CardCarousel.Card) -> some View {
        if card.imageURL != nil || (card.image != nil && card.image?.kind != .object) {
            CardArtworkView(card: card, maxPixelSize: 180)
        } else {
            ZStack {
                Theme.cardSoft
                if let icon = card.icon {
                    IconView(icon: icon, size: 40)
                }
            }
        }
    }

    private func managedCard(_ card: CardCarousel.Card) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button {
            guard blockInteraction.allowsStoreMutation else { return }
            cardAction(card)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                cardImage(card)
                    .frame(width: cardWidth, height: 108)
                    .clipped()
                VStack(alignment: .leading, spacing: 5) {
                    Text(card.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    if let caption = card.caption {
                        Text(caption)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
            }
            .frame(width: cardWidth)
            .background(Theme.surface, in: shape)
            .overlay(shape.stroke(.black.opacity(0.06), lineWidth: 0.5))
            .clipShape(shape)
            .contentShape(.interaction, shape)
            .contentShape(.contextMenuPreview, shape)
            .accessibilityElement(children: .combine)
        }
        .blockStoreMutationControl()
        .buttonStyle(.pressable)
        .textSelection(.disabled)
        .modifier(CardMenu(card: card))
    }

    @ViewBuilder
    private func homeContinueCard(_ card: CardCarousel.Card) -> some View {
        if isTextContinueCard(card) {
            textContinueCard(card)
        } else {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            Button {
                guard blockInteraction.allowsStoreMutation else { return }
                cardAction(card)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    CardArtworkView(card: card)
                        .frame(width: cardWidth, height: 214)
                        .clipped()

                    VStack(alignment: .leading, spacing: 5) {
                        Text(card.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                        if let caption = card.caption {
                            Text(caption)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 72)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, minHeight: 154, alignment: .bottomLeading)
                    .background(ProgressiveFrost())
                }
                .frame(width: cardWidth, height: 214)
                .clipShape(shape)
                .contentShape(.interaction, shape)
                .contentShape(.contextMenuPreview, shape)
                .accessibilityElement(children: .combine)
            }
            .blockStoreMutationControl()
            .buttonStyle(PressableStyle(hapticsEnabled: card.conversation == nil))
            .textSelection(.disabled)
            .modifier(CardMenu(card: card))
        }
    }

    private func textContinueCard(_ card: CardCarousel.Card) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button {
            guard blockInteraction.allowsStoreMutation else { return }
            cardAction(card)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let caption = card.caption {
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Text(card.title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let preview = card.preview {
                    Text(preview)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(width: cardWidth, height: 214, alignment: .topLeading)
            .background(Theme.surface, in: shape)
            .overlay(shape.stroke(.black.opacity(0.06), lineWidth: 0.5))
            .contentShape(.interaction, shape)
            .contentShape(.contextMenuPreview, shape)
            .accessibilityElement(children: .combine)
        }
        .blockStoreMutationControl()
        .buttonStyle(PressableStyle(hapticsEnabled: card.conversation == nil))
        .textSelection(.disabled)
        .modifier(CardMenu(card: card))
    }

    private func isTextContinueCard(_ card: CardCarousel.Card) -> Bool {
        card.image == nil && card.imageURL.flatMap(URL.init(string:)) == nil && card.icon == nil
    }

    func singleCard(_ card: CardCarousel.Card) -> some View {
        cardBody(card, width: nil, captionLines: nil, corner: 24) {
            cardImage(card)
                .aspectRatio(3 / 4, contentMode: .fit)
        }
        .padding(.horizontal, Theme.contentMargin)
    }

    @ViewBuilder
    private func cardBody(
        _ card: CardCarousel.Card,
        width: CGFloat?,
        captionLines: Int?,
        corner: CGFloat,
        @ViewBuilder image: () -> some View
    ) -> some View {
        Button {
            guard blockInteraction.allowsStoreMutation else { return }
            cardAction(card)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                image()
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if let tag = card.tag {
                            ArtworkQualitativeBadge(text: tag)
                                .padding(ArtworkQualitativeBadge.inset(cardRadius: 20))
                        }
                    }
                    .modifier(CardZoomSource(id: sourceTransitionID(for: card), namespace: expansionNamespace,
                                             elevation: .flat(corner)))
                Text(card.title)
                    .font(Theme.cardTitle())
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let caption = card.caption {
                    Text(caption)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(captionLines)
                        .multilineTextAlignment(.leading)
                }
                if let meta = card.meta {
                    Text(meta)
                        .font(Theme.caption())
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
                if let strap = card.strap {
                    Text(strap)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .blockStoreMutationControl()
        .buttonStyle(.pressable)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .modifier(CardMenu(card: card))
    }

    struct CardMenu: ViewModifier {
        @Environment(\.blockInteraction) var blockInteraction
        let card: CardCarousel.Card
        @Environment(\.performAction) var performAction
        @Environment(ConversationStore.self) var store

        func body(content: Content) -> some View {
            if let key = card.conversation, blockInteraction.allowsStoreMutation {
                content.contextMenu {
                    Button {
                        guard blockInteraction.allowsStoreMutation else { return }
                        performAction(Action(label: card.title, conversation: key))
                    } label: {
                        Label("Open", systemImage: "arrow.up.right")
                    }
                    .blockStoreMutationControl()
                    let pinned = ConversationHistory.shared.items.first { $0.key == key }?.isPinned == true
                    Button {
                        guard blockInteraction.allowsStoreMutation else { return }
                        store.setConversationPinned(key: key, pinned: !pinned)
                    } label: {
                        Label(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin")
                    }
                    .blockStoreMutationControl()
                    Button {
                        guard blockInteraction.allowsStoreMutation else { return }
                        store.archiveConversation(key: key)
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .blockStoreMutationControl()
                    Button(role: .destructive) {
                        guard blockInteraction.allowsStoreMutation else { return }
                        store.deleteConversation(key: key)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .blockStoreMutationControl()
                }
            } else {
                content
            }
        }
    }

    private var uniformTileHeight: CGFloat {
        if isFeatureRail { return featureCardWidth * 0.76 }
        let hasPhoto = block.cards.contains { card in
            if let image = card.image { return image.kind != .object }
            return card.imageURL.flatMap(URL.init(string:)) != nil
        }
        return hasPhoto ? cardWidth * 4 / 3 : 110
    }

    private func tileHeight(_ card: CardCarousel.Card) -> CGFloat {
        uniformTileHeight
    }

    @ViewBuilder
    private func cardImage(_ card: CardCarousel.Card) -> some View {
        CardArtworkView(card: card)
    }

    func sourceTransitionID(for card: CardCarousel.Card) -> String? {
        guard !isIdeaRail,
              card.conversation == nil,
              card.automation == nil,
              let renderedPage else { return nil }
        let sourceCardKey = PageExpansionSource.cardKey(blockID: block.id, card: card)
        return "\(renderedPage.id.uuidString):\(sourceCardKey)"
    }
}
