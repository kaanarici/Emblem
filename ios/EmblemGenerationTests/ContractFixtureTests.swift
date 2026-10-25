import Foundation
import Testing
@testable import EmblemCore

@Suite @MainActor
struct ContractFixtureTests {
    private static let fixtures = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: "contracts/fixtures")

    private func data(_ name: String) throws -> Data {
        try Data(contentsOf: Self.fixtures.appending(path: name))
    }

    private func json(_ name: String) throws -> Any {
        try JSONSerialization.jsonObject(with: data(name))
    }

    private func events(_ name: String) throws -> [GenerationStream.Event] {
        var stream = GenerationStream()
        return try String(decoding: data(name), as: UTF8.self).split(separator: "\n")
            .compactMap { stream.consume(Data($0.utf8)) }
    }

    @Test func everyFixtureIsCovered() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.path).sorted()
        #expect(names == [
            "blocks.json", "conversations-archived.json", "conversations-first.json", "conversations-next.json",
            "generate-cancelled.ndjson", "generate-completed.ndjson", "generate-failed.ndjson",
            "generate-guest-limited.ndjson", "generate-guest.ndjson", "generate-replay.ndjson",
            "history-first.json", "history-next.json", "home.ndjson",
        ])
    }

    @Test func conversationPagesListPinnedFirstAndAppendInOrder() async throws {
        let first = try JSONDecoder().decode(ConversationPage.self, from: data("conversations-first.json"))
        let next = try JSONDecoder().decode(ConversationPage.self, from: data("conversations-next.json"))
        let archived = try JSONDecoder().decode(ConversationPage.self, from: data("conversations-archived.json"))
        var cursors: [String?] = []
        let history = ConversationHistory(cacheDirectory: nil, fetch: { scope, cursor in
            if scope == .archived { return archived }
            cursors.append(cursor)
            return cursor == nil ? first : next
        })
        await history.load()
        #expect(history.items.map(\.key) == ["lisbon", "lima", "oslo"])
        let lisbon = try #require(history.items.first)
        #expect(lisbon.title == "Our Lisbon trip")
        #expect(lisbon.isPinned && lisbon.pinnedAt == 1_792_937_280_000)
        #expect(lisbon.date == Date(timeIntervalSince1970: 1_792_936_920))
        #expect(lisbon.preview == "body-230")
        #expect(lisbon.artwork?.image?.kind == .photo)
        #expect(history.items.dropFirst().allSatisfy { !$0.isPinned && !$0.archived })
        await history.loadMore()
        #expect(history.items.map(\.key) == ["lisbon", "lima", "oslo", "kyoto"])
        #expect(cursors == [nil, first.nextCursor] && first.nextCursor != nil && next.nextCursor == nil)
        await history.load(.archived)
        #expect(history.items(.archived).map(\.key) == ["quito"])
        #expect(history.items(.archived).first?.archived == true)
    }

    @Test func historyPagesRestoreNewestFirstAndReachTheOldest() throws {
        let first = try GeneratedPage.decodeHistory(data("history-first.json"), conversationKey: "lisbon")
        let older = try GeneratedPage.decodeHistory(data("history-next.json"), conversationKey: "lisbon")
        let raw = try #require((try json("history-first.json") as? [String: Any])?["pages"] as? [[String: Any]])
        #expect(first.pages.map(\.pageKey) == ["request-lisbon-2", "request-lisbon-3"])
        #expect(first.pages.map { $0.meta?.title } == ["Alfama", "Tram 28"])
        #expect(first.pages[0].previousPageKey == "request-lisbon-1")
        #expect(first.pages[1].parentPageKey == "request-lisbon-2" && first.pages[1].sourceCardKey == "card-1")
        #expect(first.pages[1].isExpansion && !first.pages[0].isExpansion)
        for (page, row) in zip(first.pages, raw) {
            let blocks = try #require(row["blocks"] as? [[String: Any]]).filter { $0["type"] as? String != "pageMeta" }
            #expect(page.blocks.map(\.id) == blocks.compactMap { $0["id"] as? String })
            #expect(page.activities.count == 1 && page.sources.count == 1)
            #expect(!page.isStreaming)
        }
        #expect(first.olderCursor != nil)
        #expect(older.pages.map(\.pageKey) == ["request-lisbon-1"] && older.olderCursor == nil)
        let all = older.pages + first.pages
        let path = ConversationHistoryPath.indices(in: all.map {
            .init(key: $0.pageKey, previousKey: $0.previousPageKey ?? $0.parentPageKey, isExpansion: $0.isExpansion)
        })
        #expect(path.map { all[$0].pageKey } == ["request-lisbon-1", "request-lisbon-2"])
    }

    @Test func everyServerBlockDecodesAsItsOwnType() throws {
        let raw = try #require(try json("blocks.json") as? [[String: Any]])
        let blocks = try JSONDecoder().decode([Block].self, from: data("blocks.json"))
        #expect(blocks.count == raw.count && raw.count > 40)
        for (block, row) in zip(blocks, raw) {
            #expect(Mirror(reflecting: block).children.first?.label == row["type"] as? String)
            #expect(block.id == row["id"] as? String)
        }
        #expect(Set(raw.compactMap { $0["type"] as? String }).count == 40)
        let meta = try #require(blocks.lazy.compactMap { if case .pageMeta(let meta) = $0 { meta } else { nil } }.first)
        #expect(meta.title == "title-202" && meta.ask == true && meta.dockAction?.prompt == "Plan the next step")
        let carousel = try #require(blocks.lazy.compactMap { if case .cardCarousel(let c) = $0 { c } else { nil } }.first)
        #expect(carousel.cards.count == 2 && carousel.cards.first?.title == "title-332")
        let questions = try #require(blocks.lazy.compactMap { if case .questionList(let q) = $0 { q } else { nil } }.first)
        #expect(questions.items.count == 2)
    }

    @Test func completedStreamsFinishWithTheirSnapshot() throws {
        for (name, persisted) in [("generate-completed.ndjson", true), ("generate-replay.ndjson", true),
                                  ("generate-guest.ndjson", nil), ("home.ndjson", nil)] as [(String, Bool?)] {
            let events = try events(name)
            let snapshots = events.compactMap { if case .pageSnapshot(_, let blocks) = $0 { blocks } else { nil } }
            #expect(snapshots.last?.count == 6, "\(name)")
            #expect(snapshots.last?.contains { if case .unknown = $0 { true } else { false } } == false)
            guard case .finished(let finishedPersisted, let activities, let sources) = events.last else {
                Issue.record("\(name) did not finish")
                continue
            }
            #expect(finishedPersisted == persisted, "\(name)")
            if name == "generate-completed.ndjson" {
                #expect(activities.count == 1)
                #expect(sources.map(\.title) == ["Lisbon travel guide"])
                #expect(events.contains { if case .pagePreview = $0 { true } else { false } })
                #expect(events.contains { if case .status("Searching the web…") = $0 { true } else { false } })
            }
        }
    }

    @Test func homeGreetsByNameAndNamesTheNextEvent() throws {
        let events = try events("home.ndjson")
        let blocks = try #require(events.lazy.compactMap { if case .pageSnapshot(_, let blocks) = $0 { blocks } else { nil } }.last)
        let greeting = try #require(blocks.lazy.compactMap { block -> TextBlock? in
            if case .text(let text) = block, text.id == "greeting" { return text }
            return nil
        }.first)
        #expect(greeting.body.contains("**Sam**") && greeting.body.contains("Dinner with Alex"))
        #expect(blocks.map(\.id) == ["meta", "greeting", "daily-update-h", "daily-update", "ideas-h", "ideas"])
        guard case .finished(nil, _, _) = events.last else {
            Issue.record("home did not finish")
            return
        }
    }

    @Test func homeRequestCarriesThePersonalFieldsInItsBody() throws {
        let start = Date(timeIntervalSince1970: 1_792_937_100)
        let body = GenerateClient.HomeBody(name: "Maya", timezone: "Europe/Lisbon",
                                           nextEventTitle: "Launch review", nextEventStart: start)
        let encoded = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        #expect(encoded["name"] as? String == "Maya" && encoded["timezone"] as? String == "Europe/Lisbon")
        #expect(encoded["nextEventTitle"] as? String == "Launch review")
        #expect(encoded["nextEventStart"] as? Double == 1_792_937_100)
        let guest = GenerateClient.HomeBody(name: nil, timezone: "UTC", nextEventTitle: nil, nextEventStart: nil)
        #expect(Set(try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(guest)) as? [String: Any]).keys)
            == ["timezone"])
    }

    @Test func refusedStreamsFailWithTheServersReason() throws {
        let expected: [(String, String, Bool)] = [
            ("generate-failed.ndjson", "generation_failed", true),
            ("generate-cancelled.ndjson", "cancelled", false),
            ("generate-guest-limited.ndjson", "rate_limited", true),
        ]
        for (name, code, retryable) in expected {
            let events = try events(name)
            guard case .failed(let failure) = events.last else {
                Issue.record("\(name) did not fail")
                continue
            }
            #expect(failure.code == code && failure.retryable == retryable, "\(name)")
            #expect(!failure.message.isEmpty)
            #expect(!events.contains { if case .finished = $0 { true } else { false } })
        }
    }
}
