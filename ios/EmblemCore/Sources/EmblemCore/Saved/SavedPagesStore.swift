import CryptoKit
import Foundation
import Observation

public struct SavedPage: Codable, Identifiable {
    public let snapshot: Snapshot
    let savedAt: Date
    private let localSnapshot: Bool?
    private(set) var categoryOverride: SavedPagePresentation?
    var isLocalSnapshot: Bool { localSnapshot == true }

    public init(snapshot: Snapshot, savedAt: Date, localSnapshot: Bool? = nil) {
        self.snapshot = snapshot
        self.savedAt = savedAt
        self.localSnapshot = localSnapshot
        categoryOverride = nil
    }

    func categorized(_ category: SavedPagePresentation) -> Self {
        var result = self
        result.categoryOverride = category
        return result
    }

    public var id: String { snapshot.pageKey }
    public var pageKey: String { snapshot.pageKey }
    var title: String { snapshot.displayTitle }
    var prompt: String { snapshot.prompt }
    var conversationKey: String? { snapshot.conversationKey }
    var image: ImageSpec? { presentation.cover?.image }
    var imageURL: String? { presentation.cover?.imageURL }

    public struct Snapshot: Codable {
        struct SourcePreview: Codable {
            let parentPageKey: String
            let sourceCardKey: String
            let conversationKey: String?
            let card: CardCarousel.Card
        }
        let pageKey: String
        let previousPageKey: String?
        public let parentPageKey: String?
        public let sourceCardKey: String?
        public let conversationKey: String?
        let prompt: String
        let meta: PageMeta?
        let activities: [SourceActivity]
        let sources: [CitationSource]
        let answers: [String: String]
        let sourcePreview: SourcePreview?
        private let content: [SavedBlock]

        var blocks: [Block] { content.map(\.block) }

        @MainActor
        init(page: GeneratedPage) {
            self.init(page: page, blocks: page.blocks, meta: page.meta)
        }

        @MainActor
        init(visiblePage page: GeneratedPage) {
            self.init(page: page, blocks: page.visibleBlocks, meta: page.presentationMeta)
        }

        @MainActor
        private init(page: GeneratedPage, blocks: [Block], meta: PageMeta?) {
            pageKey = page.pageKey
            previousPageKey = page.previousPageKey
            parentPageKey = page.parentPageKey
            sourceCardKey = page.sourceCardKey
            conversationKey = page.conversationKey
            prompt = page.prompt
            self.meta = meta
            activities = page.activities
            sources = page.sources
            answers = page.answers
            if let source = page.expansionSource,
               source.parentPageKey == page.parentPageKey,
               source.sourceCardKey == page.sourceCardKey,
               source.parentPageKey != page.pageKey,
               source.card.conversation == nil, source.card.automation == nil {
                sourcePreview = SourcePreview(parentPageKey: source.parentPageKey,
                    sourceCardKey: source.sourceCardKey, conversationKey: page.conversationKey, card: source.card)
            } else {
                sourcePreview = nil
            }
            content = blocks.compactMap { block in
                if case .unknown = block { return nil }
                return SavedBlock(block: block)
            }
        }
    }

    @MainActor
    public func makePage() -> GeneratedPage {
        let page = GeneratedPage(
            prompt: snapshot.prompt,
            conversationKey: snapshot.conversationKey,
            pageKey: snapshot.pageKey,
            previousPageKey: snapshot.previousPageKey,
            parentPageKey: snapshot.parentPageKey,
            sourceCardKey: snapshot.sourceCardKey)
        if isLocalSnapshot {
            page.installLocalSavedPresentation(blocks: snapshot.blocks, meta: snapshot.meta)
        } else {
            page.meta = snapshot.meta
            page.blocks = snapshot.blocks.filter { if case .unknown = $0 { false } else { true } }
        }
        page.activities = snapshot.activities
        page.sources = snapshot.sources
        page.answers = snapshot.answers
        page.isExpansion = snapshot.parentPageKey != nil && snapshot.sourceCardKey != nil
        if let card = snapshot.selectedSourceCard, let parent = snapshot.parentPageKey,
           let source = snapshot.sourceCardKey {
            page.expansionSource = PageExpansionSource(parentPageID: page.id,
                parentPageKey: parent, sourceCardKey: source, card: card)
        }
        page.isStreaming = false
        page.markRevealsPresented()
        page.origin = .server
        return page
    }
}

@Observable @MainActor
public final class SavedPagesStore {
    public static let shared = SavedPagesStore()

    public enum Failure: LocalizedError, Equatable {
        case unavailable, invalidPage, staleScope, invalidArchive, invalidEntity, invalidEntityDetail, missingEntity

        public var errorDescription: String? {
            switch self {
            case .unavailable: "Saved pages aren't available on this device."
            case .invalidPage: "Wait for this page to finish before saving it."
            case .staleScope: "Your account changed. Open the page again before saving it."
            case .invalidArchive: "Your saved pages couldn't be read."
            case .invalidEntity: "This card cannot be saved. Open the finished response and try again."
            case .invalidEntityDetail: "The completed detail does not belong to this saved card."
            case .missingEntity: "This saved card is no longer available."
            }
        }
    }

    private struct Archive: Codable {
        let version: Int
        let scope: String
        let pages: [SavedPage]
        let entities: [SavedEntity]

        private enum CodingKeys: String, CodingKey { case version, scope, pages, entities }

        init(scope: String, pages: [SavedPage], entities: [SavedEntity]) {
            version = pages.contains(where: \.isLocalSnapshot) ? 3 : 2
            self.scope = scope
            self.pages = pages
            self.entities = entities
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version)
            scope = try c.decode(String.self, forKey: .scope)
            pages = try c.decode([SavedPage].self, forKey: .pages)
            switch version {
            case 1:
                guard !c.contains(.entities) else { throw Failure.invalidArchive }
                entities = []
            case 2, 3: entities = try c.decode([SavedEntity].self, forKey: .entities)
            default: throw Failure.invalidArchive
            }
            guard version == 3 || !pages.contains(where: \.isLocalSnapshot) else {
                throw Failure.invalidArchive
            }
        }
    }

    private(set) var items: [SavedPage] = []
    public private(set) var entities: [SavedEntity] = []

    public var shelfEntries: [SavedShelfEntry] {
        let entitySelections = Set(entities.map { $0.origin.selectionKey })
        var pageSelections = Set<SavedSelectionKey>()
        let pages = items.sorted { $0.savedAt > $1.savedAt }.filter { page in
            guard let key = page.snapshot.selectionKey else { return true }
            return !entitySelections.contains(key) && pageSelections.insert(key).inserted
        }
        return (pages.map(SavedShelfEntry.page) + entities.map(SavedShelfEntry.entity)).sorted {
            if $0.savedAt != $1.savedAt { return $0.savedAt > $1.savedAt }
            return $0.id < $1.id
        }
    }
    private(set) var ownerID: String?
    public private(set) var scopeID = UUID()
    public private(set) var errorMessage: String?
    private let directory: URL?
    private var needsReload = true
    @ObservationIgnored private var organizationTask: Task<Void, Never>?
    @ObservationIgnored private var organizationRun: UUID?
    @ObservationIgnored private var organizationAttempted: Set<String> = []

    init(
        directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appending(path: "SavedPages", directoryHint: .isDirectory),
        ownerID: String? = nil
    ) {
        self.directory = directory
        self.ownerID = ownerID
        do { try reload() } catch { errorMessage = error.localizedDescription }
    }

    public func contains(pageKey: String) -> Bool {
        items.contains { $0.pageKey == pageKey } || entities.contains { $0.detail?.pageKey == pageKey }
    }

    public func contains(_ page: GeneratedPage) -> Bool {
        contains(pageKey: page.pageKey) || page.savedSelectionKey.map(containsSelection(key:)) == true
    }

    public func containsSelection(origin: SavedEntity.Origin) -> Bool {
        containsSelection(key: origin.selectionKey)
    }

    public func permitsLocalAction(on page: GeneratedPage, entityID: UUID?, expectedScope: UUID) -> Bool {
        guard expectedScope == scopeID, !needsReload else { return false }
        if let entityID {
            guard let entity = entities.first(where: { $0.id == entityID }) else { return false }
            return entity.detail?.pageKey == page.pageKey || entity.origin.selectionKey == page.savedSelectionKey
        }
        return items.contains { $0.pageKey == page.pageKey }
    }

    private func containsSelection(key: SavedSelectionKey) -> Bool {
        entities.contains { $0.origin.selectionKey == key } || items.contains { $0.snapshot.selectionKey == key }
    }

    public func remove(_ page: GeneratedPage, expectedScope: UUID) throws {
        try checkScope(expectedScope)
        if needsReload { try reload() }
        let key = page.savedSelectionKey ?? items.first(where: { $0.pageKey == page.pageKey })?.snapshot.selectionKey
            ?? entities.first(where: { $0.detail?.pageKey == page.pageKey })?.origin.selectionKey
        if let key {
            try removeSelection(key: key)
        } else {
            try remove(pageKey: page.pageKey, expectedScope: expectedScope)
        }
    }

    public func removeSelection(origin: SavedEntity.Origin, expectedScope: UUID) throws {
        try checkScope(expectedScope)
        if needsReload { try reload() }
        try removeSelection(key: origin.selectionKey)
    }

    private func removeSelection(key: SavedSelectionKey) throws {
        let nextPages = items.filter { $0.snapshot.selectionKey != key }
        let nextEntities = entities.filter { $0.origin.selectionKey != key }
        guard nextPages.count != items.count || nextEntities.count != entities.count else { return }
        try commit(nextPages, entities: nextEntities)
    }

    public func requestOrganization(retryUncategorized: Bool = false) {
        guard organizationRun == nil else { return }
        if retryUncategorized { organizationAttempted = [] }
        let run = UUID(), scope = scopeID
        organizationRun = run
        organizationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.organizationRun == run {
                    self.organizationRun = nil
                    self.organizationTask = nil
                }
            }
            while !Task.isCancelled && self.scopeID == scope {
                let candidates = self.shelfEntries.filter {
                    $0.categoryKey == "general" && !self.organizationAttempted.contains($0.id)
                }.prefix(20)
                guard !candidates.isEmpty else { return }
                let request = self.organizationRequest(entries: Array(candidates))
                self.organizationAttempted.formUnion(request.items.map(\.id))
                do {
                    let response = try await SavedOrganization.classify(request)
                    try self.applyOrganization(response, for: request, expectedScope: scope)
                } catch {
                    return
                }
            }
        }
    }

    func organizationRequest(entries: [SavedShelfEntry]? = nil) -> SavedOrganization.Request {
        let entries = entries ?? Array(shelfEntries.filter { $0.categoryKey == "general" }.prefix(20))
        var keys = Set<String>()
        let categories = shelfEntries.filter { $0.categoryKey != "general" }.compactMap { entry -> SavedOrganization.Category? in
            guard keys.insert(entry.categoryKey).inserted else { return nil }
            return .init(key: entry.categoryKey, title: entry.categoryTitle)
        }
        return .init(items: entries.map(\.organizationItem), categories: Array(categories.prefix(40)))
    }

    func applyOrganization(_ response: SavedOrganization.Response, for request: SavedOrganization.Request,
                           expectedScope: UUID) throws {
        try checkScope(expectedScope)
        if needsReload { try reload() }
        guard Set(response.assignments.map(\.id)).count == response.assignments.count,
              Set(response.assignments.map(\.id)) == Set(request.items.map(\.id)) else { throw Failure.invalidPage }
        guard Set(request.categories.map(\.key)).count == request.categories.count else { throw Failure.invalidPage }
        var known = Dictionary(uniqueKeysWithValues: request.categories.map { ($0.key, $0.title) })
        for entry in shelfEntries where entry.categoryKey != "general" {
            if let title = known[entry.categoryKey], title != entry.categoryTitle { throw Failure.invalidPage }
            known[entry.categoryKey] = entry.categoryTitle
        }
        var proposed: [String: SavedPagePresentation] = [:]
        for assignment in response.assignments {
            guard known[assignment.categoryKey].map({ $0 == assignment.categoryTitle }) ?? true else { throw Failure.invalidPage }
            let category = try SavedPagePresentation(categoryKey: assignment.categoryKey, categoryTitle: assignment.categoryTitle)
            if category.categoryKey != "general" { proposed[assignment.id] = category }
        }
        let current = Dictionary(uniqueKeysWithValues: shelfEntries.map { ($0.id, $0) })
        let eligible = Set(request.items.filter {
            current[$0.id]?.categoryKey == "general" && current[$0.id]?.organizationItem == $0
        }.map(\.id))
        var changed = false
        let pages = items.map { page in
            let id = SavedShelfEntry.page(page).id
            guard eligible.contains(id), let category = proposed[id] else { return page }
            changed = true
            return page.categorized(category)
        }
        let nextEntities = entities.map { entity in
            let id = SavedShelfEntry.entity(entity).id
            guard eligible.contains(id), let category = proposed[id] else { return entity }
            changed = true
            return entity.categorized(category)
        }
        if changed { try commit(pages, entities: nextEntities) }
    }

    @discardableResult
    public func save(_ page: GeneratedPage, expectedScope: UUID? = nil) throws -> SavedPage {
        try checkScope(expectedScope)
        guard !page.isStreaming else { throw Failure.invalidPage }
        return try saveSnapshot(page)
    }

    @discardableResult
    public func saveVisibleSnapshot(_ page: GeneratedPage, expectedScope: UUID) throws -> SavedPage {
        try checkScope(expectedScope)
        guard page.visibleBlocks.contains(where: {
            switch $0 {
            case .pageMeta, .unknown: false
            case .text(let text): !text.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            default: true
            }
        }) else { throw Failure.invalidPage }
        return try saveSnapshot(page, visible: true)
    }

    private func saveSnapshot(_ page: GeneratedPage, visible: Bool = false) throws -> SavedPage {
        let blocks = visible ? page.visibleBlocks : page.blocks
        guard !page.isHome, !page.pageKey.isEmpty,
              blocks.contains(where: {
                  switch $0 { case .unknown, .pageMeta: false; default: true }
              }) else { throw Failure.invalidPage }
        if needsReload { try reload() }
        var next = items
        let index = next.firstIndex { $0.pageKey == page.pageKey }
        let snapshot = visible ? SavedPage.Snapshot(visiblePage: page) : SavedPage.Snapshot(page: page)
        var saved = SavedPage(snapshot: snapshot, savedAt: index.map { next[$0].savedAt } ?? Date(),
                              localSnapshot: visible ? true : nil)
        if let index, let category = next[index].categoryOverride { saved = saved.categorized(category) }
        if let index { next[index] = saved } else { next.insert(saved, at: 0) }
        try commit(next)
        return saved
    }

    public func remove(pageKey: String, expectedScope: UUID? = nil) throws {
        try checkScope(expectedScope)
        if needsReload { try reload() }
        if let key = items.first(where: { $0.pageKey == pageKey })?.snapshot.selectionKey
            ?? entities.first(where: { $0.detail?.pageKey == pageKey })?.origin.selectionKey {
            try removeSelection(key: key)
            return
        }
        guard contains(pageKey: pageKey) else { return }
        try commit(items.filter { $0.pageKey != pageKey })
    }

    func entity(for origin: SavedEntity.Origin, expectedScope: UUID) throws -> SavedEntity? {
        try checkScope(expectedScope)
        if needsReload { try reload() }
        return entities.first { $0.origin == origin }
    }

    public func retainedPage(for origin: SavedEntity.Origin, expectedScope: UUID) throws -> SavedPage? {
        try checkScope(expectedScope)
        if needsReload { try reload() }
        return items.filter { $0.snapshot.selectionKey == origin.selectionKey }
            .max { $0.savedAt < $1.savedAt }
    }

    public func removeSelection(card: CardCarousel.Card, blockID: String, from parent: GeneratedPage,
                         interaction: BlockInteraction, expectedScope: UUID) throws {
        try checkScope(expectedScope)
        guard interaction.allowsStoreMutation else { throw Failure.invalidEntity }
        let selection = try SavedEntity.capture(card: card, blockID: blockID, parent: parent)
        guard interaction.allowsStoreMutation else { throw Failure.invalidEntity }
        if let existing = try entity(for: selection.origin, expectedScope: expectedScope) {
            guard existing.origin == selection.origin else { throw Failure.invalidEntity }
        }
        try removeSelection(origin: selection.origin, expectedScope: expectedScope)
    }

    @discardableResult
    public func saveEntity(card: CardCarousel.Card, blockID: String, from parent: GeneratedPage,
                    interaction: BlockInteraction, expectedScope: UUID,
                    detail: SavedEntity.CompletedDetail? = nil) throws -> SavedEntity {
        try checkScope(expectedScope)
        if let detail { try checkScope(detail.saveScopeID) }
        guard interaction.allowsStoreMutation else { throw Failure.invalidEntity }
        let candidate = try SavedEntity.capture(card: card, blockID: blockID, parent: parent)
        if needsReload { try reload() }
        var next = entities
        let index = next.firstIndex { $0.origin.key == candidate.origin.key }
        let saved: SavedEntity
        if let index {
            guard next[index].origin == candidate.origin, next[index].card == candidate.card else {
                throw Failure.invalidEntity
            }
            guard let detail else { return next[index] }
            saved = try next[index].attaching(detail)
            next[index] = saved
        } else {
            saved = try detail.map { try candidate.attaching($0) } ?? candidate
            next.insert(saved, at: 0)
        }
        try commit(items, entities: next)
        return saved
    }

    public func removeEntity(id: UUID, expectedScope: UUID) throws {
        try checkScope(expectedScope)
        if needsReload { try reload() }
        guard let entity = entities.first(where: { $0.id == id }) else { return }
        try removeSelection(key: entity.origin.selectionKey)
    }

    @discardableResult
    public func attachCompletedDetail(_ detail: SavedEntity.CompletedDetail, to id: UUID,
                               expectedScope: UUID) throws -> SavedEntity {
        try checkScope(expectedScope)
        try checkScope(detail.saveScopeID)
        if needsReload { try reload() }
        guard let index = entities.firstIndex(where: { $0.id == id }) else { throw Failure.missingEntity }
        var next = entities
        next[index] = try next[index].attaching(detail)
        try commit(items, entities: next)
        return next[index]
    }

    public func switchOwner(to ownerID: String?) throws {
        guard self.ownerID != ownerID else {
            if needsReload { try reload() }
            return
        }
        self.ownerID = ownerID
        organizationTask?.cancel()
        organizationTask = nil
        organizationRun = nil
        organizationAttempted = []
        scopeID = UUID()
        items = []
        entities = []
        needsReload = true
        errorMessage = nil
        try reload()
    }

    public func erase(ownerID: String?) throws {
        if self.ownerID == ownerID {
            organizationTask?.cancel()
            organizationTask = nil
            organizationRun = nil
            organizationAttempted = []
            scopeID = UUID()
            items = []
            entities = []
            needsReload = true
        }
        do {
            let url = try fileURL(ownerID: ownerID)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            if self.ownerID == ownerID { needsReload = false }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func reload() throws {
        do {
            let url = try fileURL(ownerID: ownerID)
            let data: Data
            do { data = try Data(contentsOf: url) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                items = []
                entities = []
                needsReload = false
                errorMessage = nil
                return
            }
            let archive = try JSONDecoder().decode(Archive.self, from: data)
            guard archive.scope == scope(for: ownerID),
                  Set(archive.pages.map(\.pageKey)).count == archive.pages.count,
                  archive.pages.allSatisfy({ !$0.pageKey.isEmpty }),
                  Set(archive.entities.map(\.id)).count == archive.entities.count,
                  Set(archive.entities.map { $0.origin.key }).count == archive.entities.count,
                  archive.entities.allSatisfy(\.isValidArchiveRecord) else {
                throw Failure.invalidArchive
            }
            items = archive.pages
            entities = archive.entities
            needsReload = false
            errorMessage = nil
        } catch {
            needsReload = true
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func commit(_ pages: [SavedPage], entities nextEntities: [SavedEntity]? = nil) throws {
        do {
            let url = try fileURL(ownerID: ownerID)
            let nextEntities = nextEntities ?? entities
            let data = try JSONEncoder().encode(Archive(scope: scope(for: ownerID), pages: pages, entities: nextEntities))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            items = pages
            entities = nextEntities
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func checkScope(_ expected: UUID?) throws {
        if let expected, expected != scopeID { throw Failure.staleScope }
    }

    private func fileURL(ownerID: String?) throws -> URL {
        guard let directory else { throw Failure.unavailable }
        return directory.appending(path: "\(scope(for: ownerID)).json", directoryHint: .notDirectory)
    }

    private func scope(for ownerID: String?) -> String {
        let key = ownerID.map { "user:\($0)" } ?? "guest"
        return SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private struct SavedBlock: Codable {
    let block: Block
    private enum CodingKeys: String, CodingKey { case type }

    init(block: Block) { self.block = block }
    init(from decoder: Decoder) throws { block = try Block(from: decoder) }

    func encode(to encoder: Encoder) throws {
        let kind: String
        let payload: any Encodable
        switch block {
        case .pageMeta(let value): (kind, payload) = ("pageMeta", value)
        case .runStamp(let value): (kind, payload) = ("runStamp", value)
        case .quiz(let value): (kind, payload) = ("quiz", value)
        case .flashcards(let value): (kind, payload) = ("flashcards", value)
        case .chart(let value): (kind, payload) = ("chart", value)
        case .diagram(let value): (kind, payload) = ("diagram", value)
        case .whatIf(let value): (kind, payload) = ("whatIf", value)
        case .text(let value): (kind, payload) = ("text", value)
        case .writing(let value): (kind, payload) = ("writing", value)
        case .hero(let value): (kind, payload) = ("hero", value)
        case .titleBlock(let value): (kind, payload) = ("titleBlock", value)
        case .sectionHeader(let value): (kind, payload) = ("sectionHeader", value)
        case .cardCarousel(let value): (kind, payload) = ("cardCarousel", value)
        case .featureList(let value): (kind, payload) = ("featureList", value)
        case .quote(let value): (kind, payload) = ("quote", value)
        case .ratingRow(let value): (kind, payload) = ("ratingRow", value)
        case .mediaRowList(let value): (kind, payload) = ("mediaRowList", value)
        case .spotList(let value): (kind, payload) = ("spotList", value)
        case .factList(let value): (kind, payload) = ("factList", value)
        case .chipRow(let value): (kind, payload) = ("chipRow", value)
        case .statRow(let value): (kind, payload) = ("statRow", value)
        case .itemGrid(let value): (kind, payload) = ("itemGrid", value)
        case .stepCarousel(let value): (kind, payload) = ("stepCarousel", value)
        case .listBlock(let value): (kind, payload) = ("listBlock", value)
        case .comparisonTable(let value): (kind, payload) = ("comparisonTable", value)
        case .sideBySide(let value): (kind, payload) = ("sideBySide", value)
        case .oneAgainstMany(let value): (kind, payload) = ("oneAgainstMany", value)
        case .reviewSummary(let value): (kind, payload) = ("reviewSummary", value)
        case .timeline(let value): (kind, payload) = ("timeline", value)
        case .questionList(let value): (kind, payload) = ("questionList", value)
        case .map(let value): (kind, payload) = ("map", value)
        case .route(let value): (kind, payload) = ("route", value)
        case .weather(let value): (kind, payload) = ("weather", value)
        case .photoGrid(let value): (kind, payload) = ("photoGrid", value)
        case .timeAsk(let value): (kind, payload) = ("timeAsk", value)
        case .eventCard(let value): (kind, payload) = ("eventCard", value)
        case .music(let value): (kind, payload) = ("music", value)
        case .reminders(let value): (kind, payload) = ("reminders", value)
        case .contact(let value): (kind, payload) = ("contact", value)
        case .homeControl(let value): (kind, payload) = ("homeControl", value)
        case .unknown:
            throw SavedPagesStore.Failure.invalidPage
        }
        try payload.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
    }
}
