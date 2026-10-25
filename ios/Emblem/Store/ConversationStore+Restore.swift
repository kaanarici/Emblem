import Foundation
import Observation
import SwiftUI
import UIKit
import EmblemCore

extension ConversationStore {
    func restoreConversation(key: String) {
        guard !isGenerationActive else { return }
        if case let .loading(loadingKey, _) = conversationLoadState,
           loadingKey == key,
           currentConversationKey == key {
            return
        }

        let reusesCurrentDestination = currentConversationKey == key
            && !(currentPage?.isHome ?? true)
        cancelRestore()
        olderPages?.task?.cancel()
        olderPages = nil
        automationOpenFailureID = nil
        let requestID = UUID()
        restoreRequestID = requestID

        let epoch = history.epoch
        let cache = history.cache

        if !reusesCurrentDestination {
            let root = homePage ?? GeneratedPage(prompt: "home", isHome: true)
            let placeholder = GeneratedPage(
                prompt: "Conversation",
                conversationKey: key)
            placeholder.isStreaming = false
            if let title = history.summary(for: key)?.title {
                placeholder.meta = PageMeta(id: "loading", title: title)
            }
            forwardPages = []
            withAnimation(.smooth(duration: 0.32)) {
                pages = [root, placeholder]
            }
        }
        conversationLoadState = .loading(key: key, showingCachedContent: false)

        restoreTask = Task { [weak self] in
            guard let self else { return }
            guard self.history.epoch == epoch else { return }
            let cached = await Task.detached {
                cache.read(for: key, epoch: epoch)
            }.value

            if let cached {
                do {
                    let decoded = try GeneratedPage.decodeHistory(cached.data, conversationKey: key)
                    try Task.checkCancellation()
                    guard self.history.epoch == epoch,
                          self.restoreRequestID == requestID,
                          self.currentConversationKey == key,
                          !self.isGenerationActive else { return }
                    if !decoded.pages.isEmpty {
                        self.installRegisteredConversation(
                            self.registerHistory(decoded.pages, conversationKey: key),
                            conversationKey: key, olderCursor: decoded.olderCursor)
                        if cached.age <= Self.freshConversationCacheAge {
                            self.conversationLoadState = .idle
                            self.restoreTask = nil
                            return
                        }
                        self.conversationLoadState = .loading(
                            key: key,
                            showingCachedContent: true)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    await Task.detached {
                        cache.remove(for: key, epoch: epoch)
                    }.value
                }
            }

            do {
                guard self.history.epoch == epoch else { return }
                let data = try await GenerateClient.fetchJSON(identityEpoch: epoch,
                    path: "api/history",
                    query: [.init(name: "conversationKey", value: key)])
                let decoded = try GeneratedPage.decodeHistory(data, conversationKey: key)
                try Task.checkCancellation()
                guard self.history.epoch == epoch,
                      self.restoreRequestID == requestID,
                      !self.isGenerationActive else { return }
                let restored = self.registerHistory(decoded.pages, conversationKey: key)
                guard !restored.isEmpty else {
                    let showingCachedContent = self.hasVisibleConversationContent(key: key)
                    self.conversationLoadState = .failed(
                        key: key,
                        showingCachedContent: showingCachedContent)
                    self.restoreTask = nil
                    return
                }
                self.installRegisteredConversation(restored, conversationKey: key, olderCursor: decoded.olderCursor)
                self.conversationLoadState = .idle
                self.restoreTask = nil
                await Task.detached {
                    cache.store(data, for: key, epoch: epoch)
                }.value
            } catch {
                guard !Task.isCancelled else { return }
                guard self.history.epoch == epoch,
                      self.restoreRequestID == requestID,
                      self.currentConversationKey == key else { return }
                let showingCachedContent = self.hasVisibleConversationContent(key: key)
                self.conversationLoadState = .failed(
                    key: key,
                    showingCachedContent: showingCachedContent)
                self.restoreTask = nil
            }
        }
    }

    func cancelRestore() {
        restoreTask?.cancel()
        restoreTask = nil
        restoreRequestID = UUID()
        conversationLoadState = .idle
        openingAutomationID = nil
    }

    private func hasVisibleConversationContent(key: String) -> Bool {
        currentConversationKey == key && !(currentPage?.blocks.isEmpty ?? true)
    }

    private func installRegisteredConversation(
        _ restored: [GeneratedPage],
        conversationKey: String,
        olderCursor: String?
    ) {
        guard !restored.isEmpty, currentConversationKey == conversationKey else { return }
        olderPages?.task?.cancel()
        olderPages = olderCursor.map { OlderPages(conversationKey: conversationKey, cursor: $0) }
        let root = homePage ?? GeneratedPage(prompt: "home", isHome: true)
        for page in restored { reconcileCalendarAction(on: page) }
        generationSession.clearRetryCandidate()
        forwardPages = []
        let wasWaiting = isOpeningConversation
        pages = [root] + restored
        if wasWaiting { responseWaveID = UUID() }
        loadOlderPagesIfNeeded()
    }

    func loadOlderPagesIfNeeded() {
        guard let older = olderPages, older.task == nil, currentConversationKey == older.conversationKey,
              let oldest = pages.dropFirst().first, oldest.conversationKey == older.conversationKey,
              pages.dropFirst().prefix(2).contains(where: { $0 === currentPage }) else { return }
        let epoch = history.epoch
        olderPages?.task = Task { [weak self] in
            var cursor: String? = older.cursor
            var fetched: [GeneratedPage] = []
            var chain: [GeneratedPage] = []
            var failed = false
            while chain.isEmpty, let next = cursor {
                do {
                    let data = try await GenerateClient.fetchJSON(identityEpoch: epoch, path: "api/history", query: [
                        .init(name: "conversationKey", value: older.conversationKey), .init(name: "cursor", value: next),
                    ])
                    let batch = try GeneratedPage.decodeHistory(data, conversationKey: older.conversationKey)
                    fetched = batch.pages + fetched
                    cursor = batch.olderCursor
                    chain = Self.olderChain(fetched, before: oldest)
                } catch {
                    failed = true
                    break
                }
            }
            guard let self, self.olderPages?.id == older.id else { return }
            self.olderPages?.task = nil
            guard !failed, self.history.epoch == epoch, self.pages.dropFirst().first === oldest else { return }
            self.registerExpansions(fetched)
            for page in chain { self.reconcileCalendarAction(on: page) }
            self.olderPages = cursor.map { OlderPages(conversationKey: older.conversationKey, cursor: $0) }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { self.pages.insert(contentsOf: chain, at: 1) }
            self.loadOlderPagesIfNeeded()
        }
    }
}
