import SwiftUI
import EmblemCore

extension CardCarouselView {
    struct KeyedCard: Identifiable {
        let id: String
        let card: CardCarousel.Card
    }

    var keyedCards: [KeyedCard] {
        let keys = block.renderKeys(positional: renderedPage.map { !$0.isHome } ?? false)
        return zip(keys, block.cards).map { KeyedCard(id: $0, card: $1) }
    }

    private var pagedActiveCardID: String? {
        let keys = keyedCards.map(\.id)
        if let pagedSelectedCardID, keys.contains(pagedSelectedCardID) {
            return pagedSelectedCardID
        }
        return keys.first
    }

    var pagedRail: some View {
        VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(keyedCards) { keyed in
                        let card = keyed.card
                        pagedCard(card)
                            .containerRelativeFrame(.horizontal)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content.scaleEffect(x: 1, y: 1 - 0.05 * CGFloat(abs(phase.value)))
                            }
                            .id(keyed.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 28, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $pagedSelectedCardID)
            .scrollBounceBehavior(.basedOnSize)
            .scrollClipDisabled()
            .onChange(of: keyedCards.map(\.id)) { _, ids in
                if let pagedSelectedCardID, !ids.contains(pagedSelectedCardID) {
                    self.pagedSelectedCardID = ids.first
                }
            }

            if block.cards.count > 1 {
                pagedIndicators
            }
        }
    }

    private var pagedIndicators: some View {
        let selectedID = pagedActiveCardID
        let selectedIndex = keyedCards.firstIndex(where: { $0.id == selectedID }) ?? 0
        return HStack(spacing: 4) {
            ForEach(keyedCards) { keyed in
                Capsule()
                    .fill(Color(.sRGB, white: keyed.id == selectedID ? 202.0 / 255.0 : 235.0 / 255.0, opacity: 1))
                    .frame(width: keyed.id == selectedID ? 68.0 / 3.0 : 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(selectedIndex + 1) of \(block.cards.count)")
        .accessibilityValue(keyedCards.first(where: { $0.id == selectedID })?.card.title ?? "")
    }

    private func pagedCard(_ card: CardCarousel.Card) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return Button {
            guard blockInteraction.allowsStoreMutation else { return }
            cardAction(card)
        } label: {
            VStack(spacing: 0) {
                Color.clear
                    .aspectRatio(32.0 / 33.0, contentMode: .fit)
                    .overlay {
                        CardArtworkView(card: card, maxPixelSize: 1_200)
                    }
                    .overlay(alignment: .topLeading) {
                        if let tag = card.tag {
                            ArtworkQualitativeBadge(text: tag, cardRadius: 28)
                                .padding(ArtworkQualitativeBadge.inset(cardRadius: 28))
                        }
                    }
                    .clipped()

                pagedCopy(card)
            }
            .background(Theme.surface)
            .clipShape(shape)
            .contentShape(.interaction, shape)
            .accessibilityElement(children: .combine)
        }
        .blockStoreMutationControl()
        .buttonStyle(.pressable)
        .modifier(CardZoomSource(id: sourceTransitionID(for: card), namespace: expansionNamespace))
        .modifier(CardMenu(card: card))
        .modifier(MediaArtworkShadow())
        .overlay(alignment: .topTrailing) {
            CarouselBookmarkButton(card: card, blockID: block.id, presentation: .paged)
        }
    }

    private func pagedCopy(_ card: CardCarousel.Card) -> some View {
        VStack(spacing: 0) {
            Text(card.title)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.7)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let meta = card.meta {
                Text(meta)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            if let caption = card.caption {
                Text(caption)
                    .font(.system(size: 16))
                    .lineSpacing(max(0, 22 - UIFont.systemFont(ofSize: 16).lineHeight))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }

            if let tags = card.tags, !tags.isEmpty {
                PagedTagFlow(spacing: 4) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                        Text(tag)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .frame(height: 22)
                            .background(Theme.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .padding(.top, 8)
            }

            if let strap = card.strap {
                Text(strap)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, minHeight: 184, alignment: .top)
    }

    private struct PagedTagFlow: Layout {
        let spacing: CGFloat

        private func rows(width: CGFloat, subviews: Subviews) -> [[CGSize]] {
            var rows: [[CGSize]] = [[]]
            var used: CGFloat = 0
            for subview in subviews {
                let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
                let gap = rows[rows.count - 1].isEmpty ? 0 : spacing
                if used + gap + size.width > width, !rows[rows.count - 1].isEmpty {
                    rows.append([])
                    used = 0
                }
                used += (rows[rows.count - 1].isEmpty ? 0 : spacing) + size.width
                rows[rows.count - 1].append(size)
            }
            return rows
        }

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let width: CGFloat
            if let proposed = proposal.width, proposed.isFinite {
                width = max(0, proposed)
            } else {
                width = subviews.reduce(CGFloat.zero) { $0 + $1.sizeThatFits(.unspecified).width }
                    + CGFloat(max(subviews.count - 1, 0)) * spacing
            }
            let rows = rows(width: width, subviews: subviews)
            let height = rows.reduce(CGFloat.zero) { $0 + ($1.map(\.height).max() ?? 0) }
                + CGFloat(max(rows.count - 1, 0)) * spacing
            return CGSize(width: width, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            var index = 0
            var y = bounds.minY
            for row in rows(width: bounds.width, subviews: subviews) {
                let rowWidth = row.reduce(CGFloat.zero) { $0 + $1.width } + CGFloat(max(row.count - 1, 0)) * spacing
                var x = bounds.midX - rowWidth / 2
                for size in row {
                    subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                    x += size.width + spacing
                    index += 1
                }
                y += (row.map(\.height).max() ?? 0) + spacing
            }
        }
    }
}
