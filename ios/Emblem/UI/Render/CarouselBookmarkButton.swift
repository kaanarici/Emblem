import SwiftUI
import EmblemCore

private struct SavedItemDidSaveKey: EnvironmentKey {
    static let defaultValue: (@MainActor (SavedEntity) -> Void)? = nil
}

extension EnvironmentValues {
    var savedItemDidSave: (@MainActor (SavedEntity) -> Void)? {
        get { self[SavedItemDidSaveKey.self] }
        set { self[SavedItemDidSaveKey.self] = newValue }
    }
}

struct CarouselBookmarkButton: View {
    let card: CardCarousel.Card
    let blockID: String
    let presentation: CardCarousel.Presentation

    @Environment(\.renderedPage) private var renderedPage
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(\.savedItemDidSave) private var savedItemDidSave
    @State private var savedPages = SavedPagesStore.shared
    @State private var isPending = false
    @State private var bookmarkTaps = 0
    @State private var errorMessage: String?

    private var sourceCardKey: String {
        PageExpansionSource.cardKey(blockID: blockID, card: card)
    }

    private var isSaved: Bool {
        guard let page = renderedPage else { return false }
        return savedPages.containsSelection(origin: SavedEntity.Origin(
            parentPageKey: page.pageKey, conversationKey: page.conversationKey,
            blockID: blockID, sourceCardKey: sourceCardKey))
    }

    static func glyphSize(_ presentation: CardCarousel.Presentation) -> CGFloat {
        presentation == .paged ? 28 : presentation == .poster ? 24 : 20
    }

    static func hitSize(_ presentation: CardCarousel.Presentation) -> CGFloat {
        presentation == .paged ? 52 : presentation == .poster ? 48 : 36
    }

    @ViewBuilder
    var body: some View {
        if let page = renderedPage, !page.isHome {
            Button(action: toggleBookmark) {
                CardBadgeGlyph(
                    isOn: isSaved,
                    size: Self.glyphSize(presentation),
                    isPaged: presentation == .paged)
                    .foregroundStyle(.white)
                    .frame(width: Self.hitSize(presentation), height: Self.hitSize(presentation))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .blockStoreMutationControl()
            .sensoryFeedback(trigger: bookmarkTaps) { _, _ in isSaved ? EmblemHaptic.saved : EmblemHaptic.removed }
            .disabled(isPending || blockInteraction == nil)
            .accessibilityLabel(isSaved ? "Remove \(card.title) from Saves" : "Save \(card.title)")
            .accessibilityValue(isSaved ? "Saved" : "Not saved")
            .accessibilityIdentifier("carousel-bookmark:\(page.pageKey):\(blockID):\(sourceCardKey)")
            .alert("Couldn't update Saves", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
            .onChange(of: savedPages.scopeID) { _, _ in errorMessage = nil }
        }
    }

    private func toggleBookmark() {
        guard !isPending, let page = renderedPage, !page.isHome, let interaction = blockInteraction,
              interaction.allowsStoreMutation else { return }
        let scope = savedPages.scopeID
        isPending = true
        defer { isPending = false }
        do {
            if let added = try Self.toggle(card: card, blockID: blockID, from: page,
                                           interaction: interaction, store: savedPages, expectedScope: scope) {
                savedItemDidSave?(added)
            }
            bookmarkTaps += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    static func toggle(card: CardCarousel.Card, blockID: String, from page: GeneratedPage,
                       interaction: BlockInteraction, store: SavedPagesStore,
                       expectedScope: UUID) throws -> SavedEntity? {
        guard interaction.allowsStoreMutation else { throw SavedPagesStore.Failure.invalidEntity }
        let origin = SavedEntity.Origin(
            parentPageKey: page.pageKey, conversationKey: page.conversationKey,
            blockID: blockID, sourceCardKey: PageExpansionSource.cardKey(blockID: blockID, card: card))
        if store.containsSelection(origin: origin) {
            try store.removeSelection(card: card, blockID: blockID, from: page,
                                      interaction: interaction, expectedScope: expectedScope)
            return nil
        }
        return try store.saveEntity(card: card, blockID: blockID, from: page,
                                    interaction: interaction, expectedScope: expectedScope)
    }
}

struct CarouselPinButton: View {
    let conversation: String
    let title: String
    let tint: Color

    @Environment(ConversationStore.self) private var store
    @Environment(\.blockInteraction) private var blockInteraction
    @State private var history = ConversationHistory.shared

    private var isPinned: Bool {
        history.summary(for: conversation)?.isPinned == true
    }

    var body: some View {
        Button {
            guard isPinned, blockInteraction.allowsStoreMutation else { return }
            store.setConversationPinned(key: conversation, pinned: false)
        } label: {
            CardBadgeGlyph(mark: .pin, isOn: isPinned, size: CarouselBookmarkButton.glyphSize(.standard), tint: tint)
                .transaction(value: isPinned) { $0.animation = nil }
                .frame(width: CarouselBookmarkButton.hitSize(.standard), height: CarouselBookmarkButton.hitSize(.standard))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .blockStoreMutationControl()
        .sensoryFeedback(EmblemHaptic.removed, trigger: isPinned) { old, new in old && !new }
        .opacity(isPinned ? 1 : 0)
        .allowsHitTesting(isPinned)
        .accessibilityHidden(!isPinned)
        .accessibilityLabel("Unpin \(title)")
        .accessibilityIdentifier("home-unpin-\(conversation)")
    }
}

private struct CompactWhiteCardBookmarkOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 4, y: 17.472432))
        path.addLine(to: CGPoint(x: 4, y: 9.90238995))
        path.addCurve(to: CGPoint(x: 5.17157, y: 3.8827971), control1: CGPoint(x: 4, y: 6.5778564), control2: CGPoint(x: 4, y: 4.9155942))
        path.addCurve(to: CGPoint(x: 12, y: 2.85), control1: CGPoint(x: 6.34315, y: 2.85), control2: CGPoint(x: 8.22876, y: 2.85))
        path.addCurve(to: CGPoint(x: 18.8284, y: 3.8827971), control1: CGPoint(x: 15.7712, y: 2.85), control2: CGPoint(x: 17.6569, y: 2.85))
        path.addCurve(to: CGPoint(x: 20, y: 9.90238995), control1: CGPoint(x: 20, y: 4.9155942), control2: CGPoint(x: 20, y: 6.5778564))
        path.addLine(to: CGPoint(x: 20, y: 17.472432))
        path.addCurve(to: CGPoint(x: 19.2272, y: 21.0148545), control1: CGPoint(x: 20, y: 19.5823305), control2: CGPoint(x: 20, y: 20.637234))
        path.addCurve(to: CGPoint(x: 13.59, y: 17.271896), control1: CGPoint(x: 17.7305, y: 21.746031), control2: CGPoint(x: 14.9232, y: 18.006458))
        path.addCurve(to: CGPoint(x: 12, y: 16.63286), control1: CGPoint(x: 12.8168, y: 16.845872), control2: CGPoint(x: 12.4302, y: 16.63286))
        path.addCurve(to: CGPoint(x: 10.41, y: 17.271896), control1: CGPoint(x: 11.5698, y: 16.63286), control2: CGPoint(x: 11.1832, y: 16.845872))
        path.addCurve(to: CGPoint(x: 4.77285, y: 21.0148545), control1: CGPoint(x: 9.0768, y: 18.006458), control2: CGPoint(x: 6.26947, y: 21.746031))
        path.addCurve(to: CGPoint(x: 4, y: 17.472432), control1: CGPoint(x: 4, y: 20.637234), control2: CGPoint(x: 4, y: 19.5823305))
        path.closeSubpath()
        let scale = min(rect.width, rect.height) / 24
        return path.applying(CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - 12 * scale, ty: rect.midY - 12 * scale))
    }
}

private struct CardBadgeGlyph: View {
    enum Mark { case bookmark, pin }

    var mark = Mark.bookmark
    let isOn: Bool
    let size: CGFloat
    var isPaged = false
    var tint = Color.white

    private var shape: WhiteCardBookmarkShape {
        WhiteCardBookmarkShape(verticalCompression: isPaged ? 0.99 : 1)
    }

    var body: some View {
        Group {
            switch mark {
            case .bookmark:
                shape
                    .fill(.black.opacity(0.2))
                    .overlay {
                        shape
                            .fill(tint.opacity(isOn ? 0.95 : 0))
                    }
                    .overlay {
                        shape
                            .stroke(tint, style: StrokeStyle(lineWidth: isPaged ? 2.1 : 1.25 * size / 20, lineCap: .round, lineJoin: .round))
                    }
            case .pin:
                Image(systemName: "pin.fill")
                    .foregroundStyle(.black.opacity(0.2))
                    .overlay { Image(systemName: "pin.fill").foregroundStyle(tint.opacity(isOn ? 0.95 : 0)) }
                    .overlay { Image(systemName: "pin").foregroundStyle(tint) }
                    .font(.system(size: size * 0.75))
                    .rotationEffect(.degrees(45))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct WhiteCardBookmarkShape: Shape {
    let verticalCompression: CGFloat

    func path(in rect: CGRect) -> Path {
        let base = CompactWhiteCardBookmarkOutline().path(in: CGRect(x: 0, y: 0, width: 24, height: 24))
        let profile = CGAffineTransform(a: 1, b: 0, c: 0, d: verticalCompression, tx: 0, ty: 12 * (1 - verticalCompression))
        let scale = min(rect.width, rect.height) / 24
        let placement = CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - 12 * scale, ty: rect.midY - 12 * scale)
        return base.applying(profile).applying(placement)
    }
}
