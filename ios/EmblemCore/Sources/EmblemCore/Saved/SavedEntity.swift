import Foundation

public struct SavedSelectionKey: Hashable {
    let parentPageKey: String
    let sourceCardKey: String
    let conversationKey: String?

    init?(pageKey: String, parent: String?, source: String?, conversation: String?, previous: String?) {
        guard let parent, let source, !parent.isEmpty, !source.isEmpty, pageKey != parent,
              previous == nil || previous == parent else { return nil }
        self.parentPageKey = parent
        self.sourceCardKey = source
        self.conversationKey = conversation
    }

    init(origin: SavedEntity.Origin) {
        parentPageKey = origin.parentPageKey
        sourceCardKey = origin.sourceCardKey
        conversationKey = origin.conversationKey
    }
}

extension SavedEntity.Origin {
    public var selectionKey: SavedSelectionKey { SavedSelectionKey(origin: self) }
}

extension GeneratedPage {
    var savedSelectionKey: SavedSelectionKey? {
        SavedSelectionKey(pageKey: pageKey, parent: parentPageKey, source: sourceCardKey,
                          conversation: conversationKey, previous: previousPageKey)
    }
}

public extension SavedPage.Snapshot {
    var selectionKey: SavedSelectionKey? {
        SavedSelectionKey(pageKey: pageKey, parent: parentPageKey, source: sourceCardKey,
                          conversation: conversationKey, previous: previousPageKey)
    }

    var selectedSourceCard: CardCarousel.Card? {
        guard selectionKey != nil, let preview = sourcePreview,
              preview.parentPageKey == parentPageKey, preview.sourceCardKey == sourceCardKey,
              preview.conversationKey == conversationKey, preview.card.conversation == nil,
              preview.card.automation == nil,
              !preview.card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return preview.card
    }
}

public struct SavedEntity: Codable, Identifiable {
    public enum Kind: String, Codable { case carousel }
    let kind: Kind
    public struct Origin: Codable, Hashable {
        public let parentPageKey: String
        public let conversationKey: String?
        let blockID: String
        public let sourceCardKey: String

        struct Key: Hashable {
            let parentPageKey: String
            let sourceCardKey: String
        }
        var key: Key { Key(parentPageKey: parentPageKey, sourceCardKey: sourceCardKey) }

        public init(parentPageKey: String, conversationKey: String?, blockID: String, sourceCardKey: String) {
            self.parentPageKey = parentPageKey
            self.conversationKey = conversationKey
            self.blockID = blockID
            self.sourceCardKey = sourceCardKey
        }
    }

    public let id: UUID
    public let savedAt: Date
    public let origin: Origin
    public let card: CardCarousel.Card
    let presentation: SavedPagePresentation
    private(set) var categoryOverride: SavedPagePresentation? = nil
    public private(set) var detail: SavedPage.Snapshot?

    func categorized(_ category: SavedPagePresentation) -> Self {
        var result = self
        result.categoryOverride = category
        return result
    }

    var resolvedCategory: SavedPagePresentation { categoryOverride ?? presentation }

    public struct CompletedDetail {
        public let snapshot: SavedPage.Snapshot
        let saveScopeID: UUID

        private init(_ impossible: Never) { switch impossible {} }

        #if canImport(UIKit)
        @MainActor
        public init(receipt: GenerationSession.CompletedPageReceipt, expectedScope: UUID) throws {
            guard receipt.saveScopeID == expectedScope else { throw SavedPagesStore.Failure.staleScope }
            let snapshot = receipt.snapshot
            guard receipt.requestID == snapshot.pageKey, !snapshot.pageKey.isEmpty,
                  let parent = snapshot.parentPageKey, SavedEntity.validKey(parent),
                  let source = snapshot.sourceCardKey, SavedEntity.validKey(source),
                  snapshot.pageKey != parent,
                  snapshot.previousPageKey == nil || snapshot.previousPageKey == parent,
                  Self.hasContent(snapshot.blocks) else {
                throw SavedPagesStore.Failure.invalidEntityDetail
            }
            self.snapshot = snapshot
            saveScopeID = receipt.saveScopeID
        }
        #endif

        fileprivate static func hasContent(_ blocks: [Block]) -> Bool {
            !blocks.contains(where: { $0.id == "generation-error" }) &&
            blocks.contains(where: {
                switch $0 { case .unknown, .pageMeta, .runStamp: false; default: true }
            })
        }
    }

    @MainActor
    static func capture(card: CardCarousel.Card, blockID: String, parent: GeneratedPage) throws -> Self {
        guard !parent.isHome, !parent.isStreaming,
              !parent.blocks.contains(where: { $0.id == "generation-error" }),
              validKey(parent.pageKey), validKey(blockID), blockID != "ideas" else {
            throw SavedPagesStore.Failure.invalidEntity
        }
        let matchingBlocks = parent.blocks.filter { $0.id == blockID }
        guard matchingBlocks.count == 1,
              case .cardCarousel(let carousel) = matchingBlocks[0],
              !carousel.cards.contains(where: { $0.conversation != nil || $0.automation != nil }),
              carousel.cards.filter({ $0.id == card.id }).count == 1,
              carousel.cards.contains(card), validCard(card) else {
            throw SavedPagesStore.Failure.invalidEntity
        }
        let metadata = parent.meta?.savePresentation?.validated(against: parent.blocks)
        let category = card.saveCategory.flatMap(SavedCategory.init(rawValue:))
        let presentation = try SavedPagePresentation(
            categoryKey: category?.rawValue ?? metadata?.categoryKey ?? SavedCategory.general.rawValue,
            categoryTitle: category?.title ?? metadata?.categoryTitle ?? SavedCategory.general.title)
        return Self(kind: .carousel, id: UUID(), savedAt: Date(),
                    origin: Origin(parentPageKey: parent.pageKey, conversationKey: parent.conversationKey,
                                   blockID: blockID, sourceCardKey: PageExpansionSource.cardKey(blockID: blockID, card: card)),
                    card: card, presentation: presentation, detail: nil)
    }

    func attaching(_ completed: CompletedDetail) throws -> Self {
        guard matchesDetail(completed.snapshot) else { throw SavedPagesStore.Failure.invalidEntityDetail }
        var result = self
        result.detail = completed.snapshot
        return result
    }

    public var isValidArchiveRecord: Bool {
        Self.validKey(origin.parentPageKey) && Self.validKey(origin.blockID) && origin.blockID != "ideas" &&
        Self.validCard(card) &&
        origin.sourceCardKey == PageExpansionSource.cardKey(blockID: origin.blockID, card: card) &&
        presentation.cover == nil && (detail.map(matchesDetail) ?? true)
    }

    public var cover: SavedPageCover? {
        SavedPageCover.first(in: [.cardCarousel(CardCarousel(id: origin.blockID, cards: [card]))])
    }

    private func matchesDetail(_ snapshot: SavedPage.Snapshot) -> Bool {
        !snapshot.pageKey.isEmpty && snapshot.pageKey != origin.parentPageKey &&
        snapshot.parentPageKey == origin.parentPageKey &&
        (snapshot.previousPageKey == nil || snapshot.previousPageKey == origin.parentPageKey) &&
        snapshot.sourceCardKey == origin.sourceCardKey &&
        snapshot.conversationKey == origin.conversationKey && CompletedDetail.hasContent(snapshot.blocks)
    }

    private static func validCard(_ card: CardCarousel.Card) -> Bool {
        card.conversation == nil && card.automation == nil &&
        !card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func validKey(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= 200
    }
}

public enum SavedShelfEntry: Identifiable {
    case page(SavedPage)
    case entity(SavedEntity)

    public var id: String {
        switch self {
        case .page(let page): "page:\(page.pageKey)"
        case .entity(let entity): "entity:\(entity.id.uuidString)"
        }
    }
    public var title: String {
        switch self { case .page(let page): page.title; case .entity(let entity): entity.card.title }
    }
    var savedAt: Date {
        switch self { case .page(let page): page.savedAt; case .entity(let entity): entity.savedAt }
    }
    public var categoryKey: String {
        switch self { case .page(let page): page.presentation.categoryKey; case .entity(let entity): entity.resolvedCategory.categoryKey }
    }
    public var categoryTitle: String {
        if categoryKey == "general" { return "Other" }
        return switch self { case .page(let page): page.presentation.categoryTitle; case .entity(let entity): entity.resolvedCategory.categoryTitle }
    }
    public var previewSubtitle: String? {
        switch self { case .page(let page): page.presentation.previewSubtitle; case .entity(let entity): entity.card.caption }
    }
    public var cover: SavedPageCover? {
        switch self { case .page(let page): page.presentation.cover; case .entity(let entity): entity.cover }
    }
}
