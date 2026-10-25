import Foundation
import Observation
import SwiftUI
import UIKit
import EmblemCore

extension ConversationStore {
    var canGoBack: Bool { pages.count > 1 && !(currentPage?.isHome ?? false) }

    var navigationPageIDs: [UUID] {
        var stack = Array(pages.dropFirst())
        if isAwaitingFirstGenerationContent,
           !isPresentingEarlyServerPreview,
           let last = stack.last,
           last === generationSession.context?.page,
           !GenerationRegistry.hasVisibleContent(last),
           !last.isExpansion {
            stack.removeLast()
        }
        return stack.map(\.id)
    }

    func popNavigationPath(to ids: [UUID]) {
        guard ids.count < navigationPageIDs.count else { return }
        for _ in 0..<(navigationPageIDs.count - ids.count) {
            guard canGoBack else { break }
            goBack()
        }
    }

    func expansionKey(for page: GeneratedPage) -> ExpansionKey? {
        guard let parentPageKey = page.parentPageKey,
              let sourceCardKey = page.sourceCardKey else { return nil }
        return ExpansionKey(
            parentPageKey: parentPageKey,
            sourceCardKey: sourceCardKey)
    }

    func registerHistory(
        _ restored: [GeneratedPage],
        conversationKey: String
    ) -> [GeneratedPage] {
        expansionPages = expansionPages.filter {
            $0.value.conversationKey != conversationKey
        }
        registerExpansions(restored)
        let preferred = generationRegistry.runs.values.filter {
            $0.historyEpoch == history.epoch && $0.saveScopeID == SavedPagesStore.shared.scopeID
                && $0.page.conversationKey == conversationKey
        }.max { $0.admissionOrder < $1.admissionOrder }?.page.pageKey
        return Self.path(through: restored, endingAt: preferred)
    }

    func registerExpansions(_ restored: [GeneratedPage]) {
        for page in restored.reversed() {
            guard let key = expansionKey(for: page) else { continue }
            page.isExpansion = true
            if expansionPages[key] == nil { expansionPages[key] = page }
        }
    }

    static func olderChain(_ older: [GeneratedPage], before oldest: GeneratedPage) -> [GeneratedPage] {
        let chain = path(through: older + [oldest], endingAt: oldest.pageKey)
        return chain.last === oldest ? Array(chain.dropLast()) : []
    }

    private static func path(through pages: [GeneratedPage], endingAt leafKey: String?) -> [GeneratedPage] {
        let entries = pages.map {
            ConversationHistoryPath.Entry(
                key: $0.pageKey,
                previousKey: $0.previousPageKey ?? $0.parentPageKey,
                isExpansion: $0.isExpansion)
        }
        return ConversationHistoryPath.indices(in: entries, preferredLeafKey: leafKey).map { pages[$0] }
    }

    func navigationAnimation(expansion: Bool) -> Animation {
        if UIAccessibility.isReduceMotionEnabled {
            return .easeOut(duration: 0.12)
        }
        return expansion
            ? .spring(response: 0.44, dampingFraction: 0.86)
            : .smooth(duration: 0.4)
    }

    func fetchCompletedConversation(key: String) async -> [GeneratedPage]? {
        do {
            let data = try await GenerateClient.fetchJSON(
                path: "api/history",
                query: [.init(name: "conversationKey", value: key)],
                timeoutInterval: 3)
            let restored = try GeneratedPage.decodeHistory(
                data,
                conversationKey: key).pages
            guard let latest = restored.last, !latest.blocks.isEmpty else { return nil }
            for page in restored { reconcileCalendarAction(on: page) }
            return restored
        } catch {
            return nil
        }
    }

    func recordForward(popping leaving: [GeneratedPage]) {
        forwardPages = ForwardHistory.afterPopping(leaving, forward: forwardPages) {
            $0.isExpansion || $0.expansionSource != nil
                || $0.parentPageKey != nil || $0.sourceCardKey != nil
        }
    }
    var canGoForward: Bool {
        guard generationRegistry.canBeginOrdinary(from: currentPage), let page = forwardPages.last else { return false }
        guard let key = page.conversationKey else { return true }
        return !history.isRemoving(key)
    }

    func goBack() {
        guard canGoBack else { return }
        cancelRestore()
        let target = currentPage
        if visibleGeneration?.firstVisible == true { VoiceOutput.shared.stop() }
        else { stop(navigatingAway: true) }
        guard currentPage === target, canGoBack else { return }
        withAnimation(navigationAnimation(expansion: target?.isExpansion == true)) {
            recordForward(popping: [pages.removeLast()])
        }
        generationRegistry.select(page: currentPage)
        if currentPage?.isHome == true { refreshHome() }
        loadOlderPagesIfNeeded()
    }

    func goForward() {
        guard generationRegistry.canBeginOrdinary(from: currentPage), let page = forwardPages.popLast() else { return }
        cancelRestore()
        withAnimation(navigationAnimation(expansion: page.isExpansion)) {
            pages.append(page)
        }
        generationRegistry.select(page: page)
    }

    func popToHome(refresh: Bool = true) {
        cancelRestore()
        if visibleGeneration?.firstVisible == true { VoiceOutput.shared.stop() }
        else { stop(navigatingAway: true) }
        if currentPage?.isHome == true { return }
        guard let index = pages.firstIndex(where: \.isHome), pages.count > index + 1 else { return }
        withAnimation(.smooth(duration: 0.4)) {
            recordForward(popping: Array(pages[(index + 1)...]))
            pages.removeSubrange((index + 1)...)
        }
        generationRegistry.select(page: currentPage)
        if refresh { refreshHome() }
    }
}
