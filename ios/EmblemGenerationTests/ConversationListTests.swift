import Foundation
import Testing
@testable import EmblemCore

@Suite @MainActor
struct ConversationListTests {
    private func item(_ key: String, updatedAt: Double, pinnedAt: Double? = nil, archived: Bool = false,
                      title: String? = nil) -> ConversationSummary {
        ConversationSummary(key: key, title: title ?? key, updatedAt: updatedAt, archived: archived, pinnedAt: pinnedAt)
    }

    private func history(
        fetch: @escaping @MainActor (ConversationHistory.Scope, String?) async throws -> ConversationPage,
        send: @escaping @MainActor (UUID, ConversationHistory.Request) async throws -> Void = { _, _ in }
    ) -> ConversationHistory {
        ConversationHistory(cacheDirectory: nil, fetch: fetch, send: send)
    }

    @Test func pinSurvivesListFetchesThatRaceItsSave() async throws {
        for listReturnsFirst in [true, false] {
            let server = Gate<Void>()
            let list = Gate<ConversationPage>()
            var fetches = 0
            let history = history(fetch: { _, _ in
                fetches += 1
                return fetches == 1 ? ConversationPage(conversations: [item("trip", updatedAt: 1)]) : try await list.wait()
            }, send: { _, _ in try await server.wait() })
            await history.load()
            let edit = try #require(history.edit("trip", .pin(true)))
            let save = Task { await history.save(edit) }
            await server.waitUntilSuspended()
            let reload = Task { await history.load(force: true) }
            await list.waitUntilSuspended()
            if listReturnsFirst {
                await list.resume(ConversationPage(conversations: [item("trip", updatedAt: 1)]))
                await reload.value
                #expect(history.items.first?.isPinned == true)
                await server.resume(())
                #expect(await save.value == .saved)
            } else {
                await server.resume(())
                #expect(await save.value == .saved)
                await list.resume(ConversationPage(conversations: [item("trip", updatedAt: 1)]))
                await reload.value
            }
            #expect(history.items.first?.isPinned == true)
        }
    }

    @Test func aFetchStartedAfterASaveIsTheTruth() async throws {
        var server = ConversationPage(conversations: [item("trip", updatedAt: 1)])
        let history = history(fetch: { _, _ in server })
        await history.load()
        let edit = try #require(history.edit("trip", .rename("Kyoto")))
        #expect(await history.save(edit) == .saved)
        server = ConversationPage(conversations: [item("trip", updatedAt: 2, title: "Kyoto, again")])
        await history.load()
        #expect(history.items.map(\.title) == ["Kyoto, again"])
    }

    @Test func failedChangesRollBackToTheServerCopy() async throws {
        let changes: [ConversationHistory.Change] = [.pin(true), .rename("Renamed"), .archive(true), .delete]
        for change in changes {
            let history = history(
                fetch: { _, _ in ConversationPage(conversations: [item("a", updatedAt: 2), item("b", updatedAt: 1)]) },
                send: { _, _ in throw URLError(.notConnectedToInternet) })
            await history.load()
            let edit = try #require(history.edit("b", change))
            switch change {
            case .pin: #expect(history.items.first?.key == "b" && history.items.first?.isPinned == true)
            case .rename: #expect(history.items.map(\.title) == ["a", "Renamed"])
            case .archive, .delete: #expect(history.items.map(\.key) == ["a"])
            }
            #expect(await history.save(edit) == .failed)
            history.discard(edit)
            #expect(history.items.map(\.title) == ["a", "b"])
            #expect(history.items.allSatisfy { !$0.isPinned && !$0.archived })
            #expect(!history.isRemoving("b"))
        }
    }

    @Test func pinnedConversationsAlwaysListFirstAndLaterPagesAppend() async throws {
        var requested: [String?] = []
        let history = history(fetch: { scope, cursor in
            #expect(scope == .active)
            requested.append(cursor)
            if cursor == nil {
                return ConversationPage(
                    pinned: [item("old-pin", updatedAt: 1, pinnedAt: 50)],
                    conversations: [item("c1", updatedAt: 40), item("c2", updatedAt: 30)],
                    nextCursor: "page-2")
            }
            return ConversationPage(
                conversations: [item("c2", updatedAt: 35, title: "c2 newer"), item("c3", updatedAt: 20)],
                nextCursor: nil)
        })
        await history.load()
        #expect(history.items.map(\.key) == ["old-pin", "c1", "c2"])
        await history.loadMore()
        #expect(history.items.map(\.key) == ["old-pin", "c1", "c2", "c3"])
        #expect(history.items.first { $0.key == "c2" }?.title == "c2 newer")
        await history.loadMore()
        #expect(requested == [nil, "page-2"])
    }

    @Test func archivedConversationsListApartAndUnarchiveMovesThemBack() async throws {
        let history = history(fetch: { scope, _ in
            scope == .archived
                ? ConversationPage(conversations: [item("old", updatedAt: 1, archived: true)])
                : ConversationPage(conversations: [item("new", updatedAt: 2)])
        })
        await history.load()
        await history.load(.archived)
        #expect(history.items.map(\.key) == ["new"])
        #expect(history.items(.archived).map(\.key) == ["old"])
        let edit = try #require(history.edit("old", .archive(false)))
        #expect(history.items.map(\.key) == ["new", "old"])
        #expect(history.items(.archived).isEmpty)
        #expect(await history.save(edit) == .saved)
    }

    @Test func oneLifecycleChangeAtATimeButPinsStayFree() async throws {
        let server = Gate<Void>()
        let history = history(
            fetch: { _, _ in ConversationPage(conversations: [item("a", updatedAt: 1)]) },
            send: { _, _ in try await server.wait() })
        await history.load()
        let rename = try #require(history.edit("a", .rename("A")))
        #expect(history.edit("a", .delete) == nil)
        #expect(history.edit("a", .archive(true)) == nil)
        #expect(history.edit("a", .pin(true)) != nil)
        let save = Task { await history.save(rename) }
        await server.waitUntilSuspended()
        await server.resume(())
        #expect(await save.value == .saved)
        #expect(history.edit("a", .delete) != nil)
        #expect(history.isRemoving("a"))
    }

    @Test func deleteRetriesWhileTheServerIsStillErasing() async throws {
        var attempts = 0
        let history = history(
            fetch: { _, _ in ConversationPage(conversations: [item("a", updatedAt: 1)]) },
            send: { _, body in
                #expect(body == ConversationHistory.Request(action: "delete", conversationKey: "a"))
                attempts += 1
                if attempts == 1 { throw GenerateClient.JSONRequestFailure(statusCode: 503) }
            })
        await history.load()
        let edit = try #require(history.edit("a", .delete))
        #expect(history.items.isEmpty)
        #expect(await history.save(edit) == .saved)
        #expect(attempts == 2)
        #expect(history.items.isEmpty)
    }

    @Test func manyChatsLeaveInBatchesAndAFailedBatchComesBack() async throws {
        let keys = (0..<130).map { "c\($0)" }
        var bodies: [ConversationHistory.Request] = []
        let history = history(
            fetch: { _, _ in ConversationPage(conversations: keys.enumerated().map { item($1, updatedAt: Double($0)) }) },
            send: { _, body in
                bodies.append(body)
                if bodies.count == 2 { throw GenerateClient.JSONRequestFailure(statusCode: 500) }
            })
        await history.load()
        let edits = history.edit(keys, .archive(true))
        #expect(history.items.isEmpty)
        #expect(await history.save(edits) == .failed)
        edits.forEach(history.discard)
        #expect(bodies.map { $0.conversationKeys?.count } == [100, 30])
        #expect(bodies.allSatisfy { $0.action == "archive" && $0.conversationKey == nil })
        #expect(Set(history.items.map(\.key)) == Set(keys.suffix(30)))
        #expect(Set(history.items(.archived).map(\.key)) == Set(keys.prefix(100)))
    }

    @Test func aChangeFromThePreviousAccountNeverLandsOnTheNextOne() async throws {
        let server = Gate<Void>()
        let history = history(
            fetch: { _, _ in ConversationPage(conversations: [item("a", updatedAt: 1)]) },
            send: { _, _ in try await server.wait() })
        history.reset(ownerID: "A")
        await history.load()
        let edit = try #require(history.edit("a", .pin(true)))
        let save = Task { await history.save(edit) }
        await server.waitUntilSuspended()
        history.reset(ownerID: "B")
        await server.resume(())
        #expect(await save.value == .superseded)
        await history.load()
        #expect(history.items.first?.isPinned == false)
    }

    @Test func restoredPagesKeepTheConversationsOwnTitleAndOlderCursor() throws {
        let data = Data(#"""
            {"pages":[{"pageKey":"p1","prompt":"Plan Kyoto","title":"My Kyoto trip","blocks":[
              {"type":"pageMeta","id":"meta","title":"Kyoto in autumn"},
              {"type":"text","id":"intro","body":"Go in November.","style":"intro"}]}],
             "nextCursor":"older"}
            """#.utf8)
        let decoded = try GeneratedPage.decodeHistory(data, conversationKey: "trip")
        #expect(decoded.pages.first?.meta?.title == "My Kyoto trip")
        #expect(decoded.pages.first?.meta?.id == "meta")
        #expect(decoded.olderCursor == "older")
    }
}
