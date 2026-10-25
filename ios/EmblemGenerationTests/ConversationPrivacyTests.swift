import Foundation
import Testing
@testable import EmblemCore

@Suite @MainActor
struct ConversationPrivacyTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "emblem-privacy-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func files(in directory: URL) -> [URL] {
        (FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
            .allObjects as? [URL] ?? []).filter { $0.pathExtension == "json" }
    }

    private func summary(_ owner: String) -> ConversationSummary {
        .init(key: "same-key", title: "\(owner) private", updatedAt: 1, archived: false,
              image: nil, imageURL: nil, preview: nil)
    }

    @Test func departingHistoryAndFreshOrStaleCacheAreClearedOffline() async throws {
        for destination: String? in [nil, "B"] {
            for age: TimeInterval in [0, 120] {
                let root = try directory()
                var online = true
                let history = ConversationHistory(cacheDirectory: root, fetch: { _, _ in
                    guard online else { throw URLError(.notConnectedToInternet) }
                    return ConversationPage(conversations: [summary("A")])
                })
                history.reset(ownerID: "A")
                let oldEpoch = history.epoch
                await history.load()
                #expect(history.items.map(\.title) == ["A private"])
                online = false
                history.cache.store(Data("A private".utf8), for: "same-key", epoch: oldEpoch)
                let file = try #require(files(in: root).first)
                try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: file.path)
                #expect(history.cache.read(for: "same-key", epoch: oldEpoch)?.data == Data("A private".utf8))

                history.reset(ownerID: destination)
                #expect(history.items.isEmpty)
                #expect(history.loadState == .idle)
                #expect(files(in: root).isEmpty)
                #expect(history.cache.read(for: "same-key", epoch: history.epoch) == nil)
                await history.load()
                #expect(history.items.isEmpty)
                #expect(history.loadState == .failed)
                history.reset(ownerID: "A")
                #expect(history.cache.read(for: "same-key", epoch: history.epoch) == nil)
            }
        }
    }

    @Test func cachePathsAreOwnerScopedAndOldRemovalCannotDeleteNewOwner() throws {
        let root = try directory()
        let history = ConversationHistory(cacheDirectory: root)
        history.reset(ownerID: "A")
        let oldEpoch = history.epoch
        history.cache.store(Data("A".utf8), for: "same-key", epoch: oldEpoch)
        let oldPath = try #require(files(in: root).first)
        history.reset(ownerID: "B")
        history.cache.store(Data("B".utf8), for: "same-key", epoch: history.epoch)
        let newPath = try #require(files(in: root).first)
        #expect(oldPath != newPath)
        history.cache.remove(for: "same-key", epoch: oldEpoch)
        #expect(history.cache.read(for: "same-key", epoch: history.epoch)?.data == Data("B".utf8))
        #expect(history.cache.read(for: "same-key", epoch: oldEpoch) == nil)
    }

    @Test func oldDetachedCacheWritesCannotRecreateDepartingDirectory() async throws {
        let root = try directory()
        let history = ConversationHistory(cacheDirectory: root)
        history.reset(ownerID: "A")
        let cache = history.cache
        let oldEpoch = history.epoch
        let gate = Gate<Void>()
        let write = Task.detached {
            _ = try? await gate.wait()
            cache.store(Data("late A".utf8), for: "same-key", epoch: oldEpoch)
        }
        await gate.waitUntilSuspended()
        history.reset(ownerID: "B")
        await gate.resume(())
        await write.value
        #expect(files(in: root).isEmpty)
        #expect(cache.read(for: "same-key", epoch: history.epoch) == nil)
    }

    @Test func concurrentCacheWritesAreDrainedBeforeClearReturns() async throws {
        let root = try directory()
        let history = ConversationHistory(cacheDirectory: root)
        history.reset(ownerID: "A")
        let cache = history.cache
        let epoch = history.epoch
        let writes = (0..<100).map { index in
            Task.detached { cache.store(Data(repeating: 65, count: 32_768), for: "\(index)", epoch: epoch) }
        }
        history.reset(ownerID: nil)
        for write in writes { await write.value }
        #expect(files(in: root).isEmpty)
    }

    @Test func legacyUnscopedCacheIsNeverAdopted() throws {
        let root = try directory()
        let legacy = root.appending(path: "old-key.json")
        try Data("legacy private".utf8).write(to: legacy)
        let history = ConversationHistory(cacheDirectory: root)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(history.cache.read(for: "old-key", epoch: history.epoch) == nil)
    }

    @Test func previousLoadCannotReplaceIncomingHistoryEvenIgnoringCancellation() async throws {
        for fails in [false, true] {
            let gate = Gate<ConversationPage>()
            var calls = 0
            let history = ConversationHistory(cacheDirectory: try directory(), fetch: { _, _ in
                calls += 1
                return calls == 1 ? try await gate.wait() : ConversationPage(conversations: [summary("B")])
            })
            history.reset(ownerID: "A")
            let load = Task { await history.load() }
            await gate.waitUntilSuspended()
            history.reset(ownerID: "B")
            await history.load()
            if fails { await gate.fail() } else { await gate.resume(ConversationPage(conversations: [summary("A")])) }
            await load.value
            #expect(history.items.map(\.title) == ["B private"])
            #expect(history.loadState == .loaded)
        }
    }

    @Test func resetBypassesPreviousOwnersThirtySecondShortcut() async throws {
        var fetches = 0
        let history = ConversationHistory(cacheDirectory: try directory(), fetch: { _, _ in
            fetches += 1
            return ConversationPage(conversations: [summary(fetches == 1 ? "A" : "B")])
        })
        history.reset(ownerID: "A")
        await history.load()
        await history.load()
        #expect(fetches == 1)
        history.reset(ownerID: "B")
        await history.load()
        #expect(fetches == 2)
        #expect(history.items.map(\.title) == ["B private"])
    }

    @Test func serverMetadataCannotAuthorizeAppleContext() throws {
        for id in ["apple-meta", "ondevice-meta", "ordinary"] {
            let data = try JSONSerialization.data(withJSONObject: ["pages": [[
                "prompt": "Server private prompt", "blocks": [
                    ["type": "pageMeta", "id": id, "title": "Private title"],
                    ["type": "text", "id": "body", "body": "Connector projection", "style": "body"],
                ],
            ]]])
            let restored = try GeneratedPage.decodeHistory(data, conversationKey: "private-key").pages
            #expect(restored.first?.meta?.id == id)
            #expect(restored.first?.origin == .server)
            #expect(GeneratedPage.appleContextPages(from: restored) == nil)
            let snapshot = GeneratedPage(prompt: "HTTP response")
            snapshot.meta = restored.first?.meta
            #expect(GeneratedPage.appleContextPages(from: [snapshot]) == nil)
        }
    }

    @Test func nativeSuccessRetainsContextAndMixedStacksFailClosed() throws {
        let home = GeneratedPage(prompt: "home", isHome: true)
        let native = (0..<5).map { index in
            let page = GeneratedPage(prompt: "Native \(index)")
            page.origin = .apple
            page.isReusableAppleTurn = true
            page.meta = PageMeta(id: "untrusted-arbitrary-id", title: "Native")
            return page
        }
        let context = try #require(GeneratedPage.appleContextPages(from: [home] + native))
        #expect(context.map(\.prompt) == ["Native 2", "Native 3", "Native 4"])
        let server = GeneratedPage(prompt: "Server")
        #expect(GeneratedPage.appleContextPages(from: [server] + native) == nil)
    }

    @Test func failedNativeTurnAllowsFreshAttemptWithoutReusingPartialOrErrorText() throws {
        let failed = GeneratedPage(prompt: "Native attempt")
        failed.origin = .apple
        failed.meta = nil
        failed.blocks = [.text(TextBlock(id: "generation-error", body: "Try again", style: .footnote))]
        let context = try #require(GeneratedPage.appleContextPages(from: [failed]))
        #expect(context.isEmpty)
        let success = GeneratedPage(prompt: "Earlier native success")
        success.origin = .apple
        success.isReusableAppleTurn = true
        let followup = try #require(GeneratedPage.appleContextPages(from: [success, failed]))
        #expect(followup.map(\.id) == [success.id])
    }
}

actor Gate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?
    func wait() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func waitUntilSuspended() async {
        while continuation == nil { await Task.yield() }
    }
    func resume(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
    func fail() { continuation?.resume(throwing: URLError(.notConnectedToInternet)); continuation = nil }
}
