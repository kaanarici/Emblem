import Foundation
import Observation
import SwiftUI
import UIKit
import EmblemCore

extension ConversationStore {
    func arrivalAnimation(on page: GeneratedPage, of run: GenerationRegistry.Run) -> Animation? {
        run.session.context?.isPending == true && !GenerationRegistry.hasVisibleContent(page)
            ? nil : .smooth(duration: 0.35)
    }

    func revealPending(_ runID: GenerationRunID) {
        guard let run = generationRegistry.runs[runID],
              generationRegistry.accepts(run, historyEpoch: history.epoch),
              let context = run.session.context, context.isPending,
              GenerationRegistry.hasVisibleContent(run.page) else { return }
        let isForeground = visibleGeneration === run
        generationRegistry.markVisible(run)
        let page = run.page
        if let replacing = run.replacingPage,
           replaceGenerationPage(replacing, with: page) {
            if let key = expansionKey(for: page) { expansionPages[key] = page }
            if isForeground && !page.isExpansion { responseWaveID = UUID() }
            return
        }
        if pages.contains(where: { $0 === page }) {
            if isForeground && !page.isExpansion { responseWaveID = UUID() }
            return
        }
        guard isForeground else { return }
        forwardPages = []
        if !page.isExpansion { responseWaveID = UUID() }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { pages.append(page) }
    }

    private func replaceGenerationPage(_ previous: GeneratedPage, with replacement: GeneratedPage) -> Bool {
        guard pages.contains(where: { $0 === previous }) || forwardPages.contains(where: { $0 === previous })
        else { return false }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            for index in pages.indices where pages[index] === previous { pages[index] = replacement }
            for index in forwardPages.indices where forwardPages[index] === previous { forwardPages[index] = replacement }
        }
        return true
    }

    func generationPageIsReachable(_ runID: GenerationRunID) -> Bool {
        guard let run = generationRegistry.runs[runID] else { return false }
        return generationRegistry.accepts(run, historyEpoch: history.epoch)
    }

    func restoreAttachments(for runID: GenerationRunID) {
        guard let run = generationRegistry.runs[runID], visibleGeneration === run else { return }
        let existing = Set(attachments.map(\.id))
        attachments.append(contentsOf: run.originalAttachments.filter { !existing.contains($0.id) })
    }

    func stop(navigatingAway: Bool = false) {
        VoiceOutput.shared.stop()
        if isOpeningConversation {
            cancelRestore()
            if !navigatingAway { goBack() }
        }
        guard let run = visibleGeneration else {
            if let runID = idleGenerationSession.activeRunID {
                idleGenerationSession.cancelActiveWithoutContext(runID: runID)
            }
            return
        }
        cancelGeneration(run, navigatingAway: navigatingAway)
    }

    func cancelGeneration(_ run: GenerationRegistry.Run, navigatingAway: Bool) {
        let session = run.session
        let runID = run.id
        guard generationRegistry.runs[runID] === run,
              let context = session.context, context.runID == runID,
              session.beginCancellation(runID: runID, preserveVisibleSnapshot: !navigatingAway)
        else { return }
        let presentationPage = context.isPending ? context.replacingPage ?? run.page : run.page
        if !navigatingAway { discardEmptyGenerationPage(run.page, animated: false) }
        Task { [weak self] in
            let acknowledgement = await session.awaitCancellationAcknowledgement(runID: runID)
            guard let self,
                  self.generationRegistry.runs[runID] === run,
                  self.history.epoch == run.historyEpoch,
                  SavedPagesStore.shared.scopeID == run.saveScopeID,
                  session.context?.runID == runID else { return }
            switch acknowledgement {
            case .cancelled:
                self.restoreAttachments(for: runID)
                self.presentCancellation(on: presentationPage)
                self.discardEmptyGenerationPage(run.page)
                session.settle(.cancelled(runID: runID))
            case .terminalCompleted:
                let restored = await self.fetchCompletedConversation(key: context.conversationKey)
                guard self.generationRegistry.runs[runID] === run,
                      self.history.epoch == run.historyEpoch,
                      SavedPagesStore.shared.scopeID == run.saveScopeID,
                      session.context?.runID == runID else { return }
                guard let completed = restored?.first(where: {
                    $0.pageKey == context.requestID && $0.conversationKey == context.conversationKey
                }) else {
                    let failure = GenerationFailure(code: "completion_restore_failed",
                        message: "The response finished, but couldn't be reloaded.", retryable: true)
                    self.presentGenerationFailure(failure, on: run)
                    session.settle(.failed(runID: runID, failure: failure))
                    return
                }
                let page = run.page
                page.clearPagePresentation()
                page.blocks = completed.blocks
                page.meta = completed.meta
                page.sources = completed.sources
                page.activities = completed.activities
                let isForeground = self.visibleGeneration === run
                let replaced = run.replacingPage.map { self.replaceGenerationPage($0, with: page) } ?? false
                if !replaced && isForeground && !self.pages.contains(where: { $0 === page }) {
                    self.forwardPages = []
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { self.pages.append(page) }
                }
                session.settle(.completed(runID: runID, persisted: true))
                self.history.invalidate()
            case .terminalFailed:
                let failure = GenerationFailure(code: "generation_failed",
                    message: "The server couldn't finish this response.", retryable: true)
                self.presentGenerationFailure(failure, on: run)
                session.settle(.failed(runID: runID, failure: failure))
            case .unconfirmed:
                let failure = GenerationFailure(code: "cancellation_unconfirmed",
                    message: "Couldn't confirm that this response stopped.", retryable: true)
                self.presentGenerationFailure(failure, on: run)
                session.settle(.failed(runID: runID, failure: failure))
            }
        }
    }

    private func presentGenerationFailure(_ failure: GenerationFailure, on run: GenerationRegistry.Run) {
        let isForeground = visibleGeneration === run
        if isForeground { failureCount += 1 }
        let page = run.session.context?.isPending == true ? run.replacingPage ?? run.page : run.page
        run.presentationPage = page
        if page === run.page { run.session.markRevealed(runID: run.id) }
        page.blocks.removeAll { $0.id == "generation-error" }
        page.blocks.append(.text(TextBlock(id: "generation-error", body: failure.message, style: .footnote)))
        self.restoreAttachments(for: run.id)
        if isForeground && page === run.page && !pages.contains(where: { $0 === page }) {
            forwardPages = []
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { pages.append(page) }
        }
    }

    private func presentCancellation(on page: GeneratedPage) {
        guard !page.hasStoppedPresentation else { return }
        if !page.blocks.isEmpty,
           !page.blocks.contains(where: {
               if case .text(let text) = $0 { return text.id == "generation-cancelled" }
               return false
           }) {
            page.blocks.append(.text(TextBlock(
                id: "generation-cancelled", body: "Stopped.", style: .footnote)))
        }
        if var meta = page.meta {
            meta.dockAction = nil
            page.meta = meta
        }
    }

    func discardEmptyGenerationPage(_ page: GeneratedPage, animated: Bool = true) {
        guard page.visibleBlocks.isEmpty, !page.isHome else { return }
        if let key = expansionKey(for: page), expansionPages[key] === page {
            expansionPages[key] = nil
        }
        forwardPages.removeAll { $0 === page }
        guard pages.count > 1, pages.last === page else { return }
        var transaction = Transaction(animation: animated ? navigationAnimation(expansion: page.isExpansion) : nil)
        transaction.disablesAnimations = !animated
        withTransaction(transaction) { _ = pages.removeLast() }
        if currentPage?.isHome == true { refreshHome() }
    }
}
