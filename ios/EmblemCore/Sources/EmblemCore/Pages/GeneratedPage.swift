import Foundation
import Observation
import CryptoKit

public struct PageExpansionSource {
    public enum ContentStyle { case article, event }

    let parentPageID: UUID
    public let parentPageKey: String
    public let sourceCardKey: String
    public let card: CardCarousel.Card
    public var contentStyle: ContentStyle = .article
    public var calendarEvent: CalendarEventDetails?

    public var transitionID: String {
        "\(parentPageID.uuidString):\(sourceCardKey)"
    }

    public static func cardKey(blockID: String, card: CardCarousel.Card) -> String {
        let input = "\(blockID)\u{1F}\(card.id)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public init(parentPageID: UUID, parentPageKey: String, sourceCardKey: String, card: CardCarousel.Card,
                contentStyle: ContentStyle = .article, calendarEvent: CalendarEventDetails? = nil) {
        self.parentPageID = parentPageID
        self.parentPageKey = parentPageKey
        self.sourceCardKey = sourceCardKey
        self.card = card
        self.contentStyle = contentStyle
        self.calendarEvent = calendarEvent
    }
}

@Observable @MainActor
public final class GeneratedPage: Identifiable {
    public enum Origin: Sendable { case server, apple }

    public var origin: Origin = .server
    public var isReusableAppleTurn = false

    public static func appleContextPages(from pages: [GeneratedPage]) -> [GeneratedPage]? {
        let history = pages.filter { !$0.isHome }
        guard !history.contains(where: { $0.origin == .server }) else { return nil }
        return Array(history.filter(\.isReusableAppleTurn).suffix(3))
    }

    public let id: UUID
    public let runtimeReplacementAncestors: Set<UUID>
    public let pageKey: String
    public let previousPageKey: String?
    public let parentPageKey: String?
    public let sourceCardKey: String?
    public let prompt: String
    public let conversationKey: String?
    public var blocks: [Block] = []
    public var activities: [SourceActivity] = []
    public var sources: [CitationSource] = []
    public var meta: PageMeta?
    public var isStreaming = true

    private struct Presentation {
        let blocks: [Block]
        let meta: PageMeta?
        let stopped: Bool
        var draft: String?? = .none
    }
    private struct PreviewBinding {
        let runID: GenerationRunID
        let scopeID: UUID
        var revision = 0
        var attempt = 0
        var heldBlockCount = 0
    }
    private var previewBinding: PreviewBinding?
    private var provisionalPresentation: Presentation?
    private var localPresentation: Presentation?

    public var visibleBlocks: [Block] { provisionalPresentation?.blocks ?? localPresentation?.blocks ?? blocks }
    public var presentationMeta: PageMeta? {
        if let provisionalPresentation { return provisionalPresentation.meta }
        if let localPresentation { return localPresentation.meta }
        return meta
    }
    public func isStreamingDraft(_ blockID: String) -> Bool {
        guard let provisionalPresentation else { return false }
        if case .some(let draft) = provisionalPresentation.draft { return draft == blockID }
        return visibleBlocks.last?.id == blockID
    }
    public var hasProvisionalPresentation: Bool { provisionalPresentation != nil || localPresentation != nil }
    public var isPreviewing: Bool { provisionalPresentation != nil }
    public var presentedBlocks: [Block] {
        guard isPreviewing else { return visibleBlocks }
        var blocks = visibleBlocks
        while case .sectionHeader = blocks.last { blocks.removeLast() }
        return blocks
    }
    public var hasStoppedPresentation: Bool { localPresentation?.stopped == true }

    public func beginPagePreview(runID: GenerationRunID, scopeID: UUID, keepingVisible: Bool = false) {
        let held = keepingVisible ? provisionalPresentation : nil
        clearPagePresentation()
        previewBinding = PreviewBinding(
            runID: runID, scopeID: scopeID, heldBlockCount: held?.blocks.count ?? 0)
        provisionalPresentation = held
    }

    @discardableResult
    public func replacePagePreview(revision: Int, attempt: Int, blocks: [Block], draft: String?? = .none,
                            runID: GenerationRunID, scopeID: UUID) -> Bool {
        guard var binding = previewBinding, binding.runID == runID, binding.scopeID == scopeID,
              revision > binding.revision, revision <= 9_007_199_254_740_991,
              attempt >= max(1, binding.attempt), attempt <= 9_007_199_254_740_991 else { return false }
        let opensAttempt = attempt > binding.attempt
        binding.revision = revision; binding.attempt = attempt
        var presentation = blocks.isEmpty ? nil : Self.presentation(blocks, stopped: false)
        presentation?.draft = draft
        if (presentation?.blocks.count ?? 0) < binding.heldBlockCount {
            previewBinding = binding
            return true
        }
        binding.heldBlockCount = 0
        previewBinding = binding
        if blocks.isEmpty, opensAttempt { return true }
        provisionalPresentation = presentation
        return true
    }

    public func clearPagePresentation(preservingStopped: Bool = false) {
        previewBinding = nil
        provisionalPresentation = nil
        if !preservingStopped || localPresentation?.stopped != true { localPresentation = nil }
    }

    func freezePagePreviewForStop(runID: GenerationRunID, scopeID: UUID) {
        guard previewBinding?.runID == runID, previewBinding?.scopeID == scopeID else { return }
        if let provisionalPresentation {
            var frozen = provisionalPresentation.blocks
            if !frozen.isEmpty, !frozen.contains(where: { $0.id == "generation-cancelled" }) {
                frozen.append(.text(TextBlock(id: "generation-cancelled", body: "Stopped.", style: .footnote)))
            }
            var metadata = provisionalPresentation.meta
            metadata?.dockAction = nil
            localPresentation = Presentation(blocks: frozen, meta: metadata, stopped: true)
        }
        previewBinding = nil
        provisionalPresentation = nil
    }

    func installLocalSavedPresentation(blocks: [Block], meta: PageMeta?) {
        clearPagePresentation()
        localPresentation = Presentation(blocks: blocks.filter {
            switch $0 { case .pageMeta, .unknown: false; default: true }
        }, meta: meta, stopped: false)
    }

    private static func presentation(_ blocks: [Block], stopped: Bool) -> Presentation {
        let metadata = blocks.compactMap { if case .pageMeta(let value) = $0 { value } else { nil } }.first
        let content = blocks.filter { switch $0 { case .pageMeta, .unknown: false; default: true } }
        return Presentation(blocks: content, meta: metadata, stopped: stopped)
    }
    public var answers: [String: String] = [:]
    public var spokeIntro = false
    @ObservationIgnored private var presentedHighlightKeys: Set<String> = []

    public func hasPresentedHighlight(for block: TextBlock) -> Bool {
        let key = block.id + "\u{1F}" + (block.highlights ?? []).joined(separator: "\u{1F}")
        return presentedHighlightKeys.contains(key)
    }

    public func claimHighlightReveal(for block: TextBlock) -> Bool {
        let key = block.id + "\u{1F}" + (block.highlights ?? []).joined(separator: "\u{1F}")
        return presentedHighlightKeys.insert(key).inserted
    }

    @ObservationIgnored private var followUpsPresented = false
    @ObservationIgnored public var settledFollowUpIcons: [String: [ImageSpec?]] = [:]

    public func claimFollowUpReveal() -> Bool {
        defer { followUpsPresented = true }
        return !followUpsPresented
    }

    func markRevealsPresented() {
        followUpsPresented = true
        for case .text(let block) in blocks where !(block.highlights ?? []).isEmpty {
            _ = claimHighlightReveal(for: block)
        }
    }
    public var isExpansion = false
    public var chromeUnderlap = false
    public var expansionSource: PageExpansionSource?
    public let isHome: Bool

    public init(
        prompt: String,
        isHome: Bool = false,
        conversationKey: String? = nil,
        pageKey: String? = nil,
        previousPageKey: String? = nil,
        parentPageKey: String? = nil,
        sourceCardKey: String? = nil,
        runtimeReplacementAncestors: Set<UUID> = []
    ) {
        let id = UUID()
        self.id = id
        self.runtimeReplacementAncestors = runtimeReplacementAncestors
        self.pageKey = pageKey ?? id.uuidString
        self.previousPageKey = previousPageKey
        self.parentPageKey = parentPageKey
        self.sourceCardKey = sourceCardKey
        self.prompt = prompt
        self.isHome = isHome
        self.conversationKey = conversationKey
    }

    var title: String {
        meta?.title ?? prompt
    }

    public var contextSummary: String { summary(blocks: blocks, meta: meta) }
    public var visibleContextSummary: String {
        summary(blocks: visibleBlocks, meta: presentationMeta, includesImageQueries: false)
    }

    private func summary(blocks: [Block], meta: PageMeta?, includesImageQueries: Bool = true) -> String {
        var lines: [String] = ["[page: \(meta?.title ?? prompt)]"]
        let completedSources = activities
            .filter { $0.status == "succeeded" || $0.status == "empty" }
            .map(\.title)
        if !completedSources.isEmpty {
            lines.append("sources: " + Array(Set(completedSources)).sorted().joined(separator: ", "))
        }
        for block in blocks {
            switch block {
            case .quiz(let b):
                lines.append("quiz: " + b.questions.map {
                    let answer = $0.options.indices.contains($0.correctIndex)
                        ? $0.options[$0.correctIndex]
                        : "unknown"
                    return "\($0.question) (answer: \(answer))"
                }.joined(separator: "; "))
            case .flashcards(let b):
                lines.append("flashcards: " + b.cards.map { "\($0.front) → \($0.back)" }
                    .joined(separator: "; "))
            case .chart(let b):
                let series = b.series.map { series in
                    let points = series.points.map { "\($0.label): \($0.value)" }
                        .joined(separator: ", ")
                    return [series.name, points].compactMap { $0 }.joined(separator: ": ")
                }.joined(separator: "; ")
                lines.append("chart: \(b.title ?? b.kind.rawValue) (\(series))")
            case .diagram(let b):
                let edges = b.edges.map { edge in
                    let from = b.nodes.first { $0.id == edge.from }?.label ?? edge.from
                    let to = b.nodes.first { $0.id == edge.to }?.label ?? edge.to
                    return "\(from) → \(to)"
                }.joined(separator: ", ")
                lines.append("diagram: \(b.title ?? "") (\(edges))")
            case .whatIf(let b):
                lines.append("what-if: " + b.variables.map {
                    "\($0.label)=\($0.defaultValue)\($0.unit ?? "")"
                }.joined(separator: ", "))
            case .text(let b): lines.append(b.body)
            case .writing(let b):
                lines.append("drafts: " + b.drafts.map { "[\($0.label)]\n\($0.body)" }.joined(separator: "\n\n"))
            case .hero(let b):
                lines.append(includesImageQueries ? "hero subject: \(b.image.query)" : "Hero image")
            case .titleBlock(let b):
                lines.append([
                    "title: \(b.title)",
                    b.metaLine,
                    b.summary,
                    b.tags?.joined(separator: ", "),
                ].compactMap { $0 }.joined(separator: " · "))
            case .sectionHeader(let b): lines.append("section: \(b.title)")
            case .cardCarousel(let b):
                lines.append("cards: " + b.cards.map {
                    [$0.title, $0.caption].compactMap { $0 }.joined(separator: " · ")
                }.joined(separator: "; "))
            case .featureList(let b):
                lines.append("features: " + b.items.map {
                    [$0.title, $0.caption].compactMap { $0 }.joined(separator: " · ")
                }.joined(separator: "; "))
            case .quote(let b):
                lines.append("quote: \(b.text)\(b.attribution.map { " (\($0))" } ?? "")")
            case .ratingRow(let b): lines.append("rating: \(b.text)")
            case .mediaRowList(let b):
                lines.append("rows: " + b.rows.map {
                    [$0.title, $0.subtitle].compactMap { $0 }.joined(separator: " · ")
                }.joined(separator: "; "))
            case .factList(let b):
                lines.append("facts: " + b.facts.map { "\($0.label): \($0.value)" }
                    .joined(separator: "; "))
            case .statRow(let b):
                lines.append("stats: " + b.stats.map { "\($0.label): \($0.value)" }
                    .joined(separator: "; "))
            case .itemGrid(let b): lines.append("items: " + b.items.map { "\($0.title) (\($0.caption ?? ""))" }.joined(separator: ", "))
            case .stepCarousel(let b):
                lines.append("steps: " + b.steps.map {
                    [$0.title, $0.meta, $0.body].compactMap { $0 }.joined(separator: " · ")
                }.joined(separator: "; "))
            case .listBlock(let b):
                lines.append("list: " + b.items.map(\.text).joined(separator: "; "))
            case .questionList(let b): lines.append("questions: " + b.items.map { item in
                answers[item.question].map { "\(item.question) → \($0)" } ?? item.question
            }.joined(separator: "; "))
            case .comparisonTable(let b): lines.append("comparing: " + b.columns.joined(separator: " vs "))
            case .sideBySide(let b):
                let names = b.entities.map(\.name).joined(separator: " vs ")
                let rows = b.rows.map { row in
                    "\(row.label): \(row.values.map(\.text).joined(separator: " / "))"
                }.joined(separator: "; ")
                lines.append("comparison: \(names) · \(rows)")
            case .oneAgainstMany(let b):
                let contenders = [b.anchor.name] + b.challengers.map(\.name)
                lines.append("comparison: " + contenders.joined(separator: " vs ") +
                    " · " + b.rowLabels.joined(separator: ", "))
            case .timeline(let b):
                lines.append("timeline: " + b.items.map {
                    [$0.time, $0.title, $0.caption].compactMap { $0 }.joined(separator: " · ")
                }.joined(separator: "; "))
            case .reviewSummary(let b):
                let scores = b.sources?.map { "\($0.source): \($0.score)" }.joined(separator: ", ")
                let themes = b.themes.map { "\($0.title): \($0.summary)" }.joined(separator: "; ")
                lines.append([scores, themes].compactMap { $0 }.joined(separator: " · "))
            case .map(let b):
                lines.append("places: " + b.places.map {
                    [$0.name, $0.locality, $0.rating, $0.caption].compactMap { $0 }
                        .joined(separator: " · ")
                }.joined(separator: "; "))
            case .route(let b):
                lines.append("route: \(b.mode.rawValue) to \(b.destination.name)" +
                    (b.destination.locality.map { ", \($0)" } ?? ""))
            case .weather(let b):
                let current = "\(b.location): \(b.current.tempC)°C, \(b.current.condition.rawValue), high \(b.current.high)°, low \(b.current.low)°"
                let forecast = b.forecast.prefix(5).map {
                    "\($0.day): \($0.condition.rawValue), \($0.high)°/\($0.low)°"
                }.joined(separator: "; ")
                lines.append("weather: \(current). Forecast: \(forecast)")
            case .photoGrid(let b):
                if includesImageQueries {
                    lines.append("photos: " + b.images.map(\.query).joined(separator: ", "))
                } else {
                    lines.append("photos: \(b.images.count) images")
                }
            case .timeAsk(let b):
                if let picked = answers[b.question], !picked.isEmpty {
                    lines.append("question: \(b.question) → \(picked)")
                } else {
                    lines.append("question: \(b.question)")
                }
            case .eventCard(let b):
                lines.append("events: " + b.events.map { "\($0.timeRange) \($0.title)" }
                    .joined(separator: "; "))
            case .music(let b):
                lines.append("songs: " + b.tracks.map { "\($0.name) by \($0.artist)" }
                    .joined(separator: "; "))
            case .reminders(let b):
                lines.append("reminders card (\(b.scope.rawValue)\(b.list.map { ", \($0)" } ?? ""))")
            case .contact(let b):
                lines.append("contact card: \(b.name)")
            case .homeControl(let b):
                lines.append("home controls" + (b.q.map { ": \($0)" } ?? ""))
            default: break
            }
        }
        return lines.joined(separator: "\n").prefix(3000).description
    }
    private struct HistoryResponse: Decodable {
        struct Page: Decodable {
            var pageKey: String?
            var previousPageKey: String?
            var parentPageKey: String?
            var sourceCardKey: String?
            var prompt: String
            var title: String?
            var blocks: [Block]
            var activities: [SourceActivity]?
            var sources: [CitationSource]?
        }
        var pages: [Page]
        var nextCursor: String?
    }

    public static func decodeHistory(
        _ data: Data,
        conversationKey: String
    ) throws -> (pages: [GeneratedPage], olderCursor: String?) {
        let response = try JSONDecoder().decode(HistoryResponse.self, from: data)
        var pages: [GeneratedPage] = []
        for raw in response.pages {
            let page = GeneratedPage(
                prompt: raw.prompt,
                conversationKey: conversationKey,
                pageKey: raw.pageKey,
                previousPageKey: raw.previousPageKey,
                parentPageKey: raw.parentPageKey,
                sourceCardKey: raw.sourceCardKey)
            page.activities = raw.activities ?? []
            page.sources = raw.sources ?? []
            for block in raw.blocks {
                if case .pageMeta(let meta) = block {
                    page.meta = meta
                } else if case .unknown = block {
                    continue
                } else {
                    page.blocks.append(block)
                }
            }
            if let title = raw.title {
                var meta = page.meta ?? PageMeta(id: "restored", title: title)
                meta.title = title
                page.meta = meta
            }
            let hasTimePicker = page.blocks.contains { block in
                if case .timeAsk = block { return true }
                return false
            }
            if hasTimePicker,
               let prompt = page.meta?.dockAction?.prompt?.lowercased(),
               prompt.contains("calendar"), prompt.contains("add"),
               page.meta?.dockAction?.calendar == nil,
               var meta = page.meta {
                meta.dockAction = nil
                page.meta = meta
            }
            page.isStreaming = false
            page.markRevealsPresented()
            page.isExpansion = raw.parentPageKey != nil && raw.sourceCardKey != nil
            pages.append(page)
        }
        return (pages, response.nextCursor)
    }
}
