import Foundation
import Observation
import SwiftUI
import UIKit
import EmblemCore

extension ConversationStore {
    @discardableResult
    func send(
        _ prompt: String,
        expansion: Bool = false,
        expansionSource: PageExpansionSource? = nil
    ) -> Bool {
        send(prompt, expansion: expansion, expansionSource: expansionSource, calendarContext: nil)
    }

    func send(
        _ prompt: String,
        expansion: Bool,
        expansionSource: PageExpansionSource?,
        calendarContext: CalendarGenerationContext?
    ) -> Bool {
        if let source = generationRegistry.run(for: currentPage),
           (source.historyEpoch != history.epoch || source.saveScopeID != SavedPagesStore.shared.scopeID) {
            return false
        }
        if calendarContext == nil {
            guard generationRegistry.canBeginOrdinary(from: currentPage) else { return false }
        }
        if calendarContext != nil,
           pages.contains(where: { $0.calendarContext != nil }),
           currentPage?.calendarContext == nil { return false }
        if let key = currentConversationKey,
           history.isRemoving(key) { return false }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let outgoing = calendarContext == nil ? attachments : []
        guard !trimmed.isEmpty || !outgoing.isEmpty else { return false }
        cancelRestore()
        automationOpenFailureID = nil

        let userText = calendarContext == nil
            ? appendingAnswers(to: trimmed, from: currentPage) : trimmed
        let sourcePage = currentPage
        let runConversationKey = sourcePage?.conversationKey ?? UUID().uuidString
        if sourcePage?.conversationKey != nil {
            let cache = history.cache
            let epoch = history.epoch
            Task.detached {
                cache.remove(for: runConversationKey, epoch: epoch)
            }
        }

        VoiceOutput.shared.stop()
        var messages: [GenerateClient.Message] = []
        let contextPages = pages
        for page in contextPages.suffix(9) where !page.isHome {
            messages.append(.init(role: "user", content: page.prompt))
            messages.append(.init(role: "assistant", content: page.contextSummary))
        }
        messages.append(.init(role: "user", content: userText))

        let wireAttachments = outgoing.map {
            GenerateClient.WireAttachment(
                kind: $0.wireKind, name: $0.filename, dataURL: $0.dataURL, text: $0.text)
        }
        let page = GeneratedPage(
            prompt: trimmed.isEmpty ? "Attachment" : trimmed,
            conversationKey: runConversationKey,
            previousPageKey: sourcePage?.isHome == false ? sourcePage?.pageKey : nil,
            parentPageKey: expansionSource?.parentPageKey,
            sourceCardKey: expansionSource?.sourceCardKey,
            calendarContext: calendarContext)
        page.isExpansion = expansion || expansionSource != nil
        page.expansionSource = expansionSource
        let appleSelection = OnDeviceModel.selection()
        let mountBeforeContent = calendarContext == nil && pagePreviewEnabled
            && appleSelection == .emblem
            && !page.isExpansion
            && dockState != .listening
        guard let run = generationRegistry.begin(
            page: page, from: sourcePage, conversationKey: runConversationKey,
            attachments: outgoing, retryAnchor: sourcePage,
            historyEpoch: history.epoch,
            admission: calendarContext == nil ? .ordinary : .calendar,
            navigationPrefix: calendarContext == nil ? [] : pages)
        else { return false }
        let runID = run.id
        let session = run.session
        run.earlyPreview = mountBeforeContent
        beginUpload(outgoing, runID: runID)
        if calendarContext == nil { attachments = [] }
        dockState = .idle

        if let key = expansionKey(for: page) {
            expansionPages[key] = page
        }

        if calendarContext != nil {
            forwardPages = []
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pages.append(page)
            }
        } else if (sourcePage?.isHome ?? true) || expansionSource != nil || mountBeforeContent {
            forwardPages = []
            withAnimation(navigationAnimation(expansion: expansionSource != nil)) {
                pages.append(page)
            }
        }

        if appleSelection != .emblem {
            page.origin = .apple
            let contextPages = GeneratedPage.appleContextPages(from: pages.filter { !$0.isHome && $0 !== page })
            let containsServerContext = contextPages == nil
            let nativeContext = (contextPages ?? []).map {
                OnDeviceModel.Turn(prompt: $0.prompt, response: $0.contextSummary)
            }
            let task = Task { [weak self] in
                guard let self else { return }
                let outcome = await OnDeviceModel.shared.streamPage(
                    prompt: userText,
                    selection: appleSelection,
                    online: NetworkStatus.shared.isOnline,
                    allowWebSearch: UserDefaults.standard.object(forKey: "apple.webSearch.allowed") as? Bool ?? true,
                    context: nativeContext,
                    containsServerContext: containsServerContext,
                    images: outgoing.filter { $0.kind == .image }.map(\.payload),
                    documents: outgoing.filter { $0.kind != .image }.compactMap(\.text),
                    unsupportedAttachments: outgoing.contains {
                        $0.kind != .image && $0.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
                    },
                    onStatus: { status in session.updateStatus(status, runID: runID) }
                ) { [weak self] blocks in
                    guard let self, self.generationRegistry.accepts(run, historyEpoch: self.history.epoch),
                          self.generationPageIsReachable(runID) else { return }
                    let content = blocks.filter {
                        if case .pageMeta = $0 { return false }
                        return true
                    }
                    let animation: Animation? = page.blocks.map(\.id) == content.map(\.id)
                        ? nil : self.arrivalAnimation(on: page, of: run)
                    withAnimation(animation) {
                        for block in blocks {
                            if case .pageMeta(let meta) = block { page.meta = meta }
                        }
                        page.blocks = content
                    }
                    if !page.blocks.isEmpty {
                        session.updateStatus("Responding…", runID: runID)
                        self.revealPending(runID)
                    }
                }
                guard self.generationRegistry.accepts(run, historyEpoch: self.history.epoch),
                      self.generationPageIsReachable(runID) else { return }
                session.clearNativeTask(runID: runID)
                switch outcome {
                case .rendered(let sources):
                    page.sources = sources
                    page.isReusableAppleTurn = true
                    session.markRevealed(runID: runID)
                    if self.visibleGeneration === run, self.currentPage === page, self.dockState == .idle,
                       let first = page.blocks.first, case .text(let text) = first,
                       text.style == .intro, !page.spokeIntro {
                        page.spokeIntro = true
                        VoiceOutput.shared.speak(text.body, origin: page.origin)
                    }
                    session.settle(.completed(runID: runID, persisted: false))
                case .failed(let message):
                    page.meta = nil
                    page.blocks = [.text(TextBlock(id: "generation-error", body: message, style: .footnote))]
                    self.restoreAttachments(for: runID)
                    self.revealPending(runID)
                    session.settle(.failed(runID: runID, failure: GenerationFailure(
                        code: "apple_generation_failed", message: message, retryable: false)))
                case .cancelled:
                    page.meta = nil
                    page.blocks = []
                    self.restoreAttachments(for: runID)
                    self.discardEmptyGenerationPage(page)
                    session.settle(.cancelled(runID: runID))
                }
            }
            session.setNativeTask(task, runID: runID)
            return true
        }

        streamWithContext(
            messages: messages, attachments: wireAttachments,
            prompt: trimmed, runID: runID)
        return true
    }

    @discardableResult
    func openExpansion(
        card: CardCarousel.Card,
        blockID: String,
        from parent: GeneratedPage,
        contentStyle: PageExpansionSource.ContentStyle = .article
    ) -> Bool {
        guard currentPage === parent, !generationSession.isActive else { return false }
        let sourceCardKey = PageExpansionSource.cardKey(blockID: blockID, card: card)
        let source = PageExpansionSource(
            parentPageID: parent.id,
            parentPageKey: parent.pageKey,
            sourceCardKey: sourceCardKey,
            card: card,
            contentStyle: contentStyle)
        let key = ExpansionKey(
            parentPageKey: parent.pageKey,
            sourceCardKey: sourceCardKey)

        if let existing = expansionPages[key] {
            cancelRestore()
            existing.isExpansion = true
            existing.expansionSource = source
            forwardPages = []
            withAnimation(navigationAnimation(expansion: true)) {
                pages.append(existing)
            }
            return true
        }

        return send(
            card.prompt ?? "Tell me more about \(card.title)",
            expansion: true,
            expansionSource: source)
    }

    func retryCurrentGeneration() {
        guard let failed = visibleGeneration else { return }
        if let selection = failed.savedSelection {
            guard SavedPagesStore.shared.scopeID == selection.scopeID,
                  SavedPagesStore.shared.entities.contains(where: { $0.id == selection.entityID }) else {
                failed.session.clearRetryCandidate()
                return
            }
        }
        guard let (run, retry) = generationRegistry.beginRetry(
            failed, currentPage: currentPage, blockedConversations: history.removingKeys, historyEpoch: history.epoch)
        else { return }
        let originalIDs = Set(retry.originalAttachments.map(\.id))
        attachments.removeAll { originalIDs.contains($0.id) }
        dockState = .idle
        VoiceOutput.shared.stop()
        startStream(request: retry.request, runID: run.id)
    }

    private func streamWithContext(
        messages: [GenerateClient.Message],
        attachments wireAttachments: [GenerateClient.WireAttachment],
        prompt trimmed: String,
        runID: GenerationRunID
    ) {
        guard let run = generationRegistry.runs[runID] else { return }
        let session = run.session
        let task = Task { [weak self] in
            guard let self else { return }
            let wireLocation = await session.resolveLocation()
            guard self.generationRegistry.accepts(run, historyEpoch: self.history.epoch),
                  !Task.isCancelled else { return }
            guard let context = session.context, context.runID == runID else { return }
            let request = GenerateClient.GenerateBody(
                messages: messages,
                requestId: context.requestID,
                conversationKey: context.conversationKey,
                previousPageKey: context.page.previousPageKey,
                parentPageKey: context.page.parentPageKey,
                sourceCardKey: context.page.sourceCardKey,
                sourceCardTitle: context.page.expansionSource?.card.title,
                sourceCardHasImage: context.page.expansionSource.map {
                    $0.card.image != nil || $0.card.imageURL != nil
                },
                calendarContext: context.page.calendarContext,
                attachments: wireAttachments.isEmpty ? nil : wireAttachments,
                location: wireLocation,
                timezone: context.page.calendarContext?.timeZone ?? TimeZone.current.identifier,
                device: DeviceAccess.advertisedSources)
            self.startStream(request: request, runID: runID)
        }
        session.setPreflightTask(task, runID: runID)
    }

    func startStream(
        request: GenerateClient.GenerateBody,
        runID: GenerationRunID
    ) {
        guard let run = generationRegistry.runs[runID],
              generationRegistry.accepts(run, historyEpoch: history.epoch),
              run.session.context != nil else { return }
        let session = run.session
        let page = run.page
        let ownerEpoch = run.historyEpoch
        session.startStream(request: request, runID: runID) { [weak self] event in
            guard let self, self.history.epoch == ownerEpoch,
                  self.generationRegistry.accepts(run, historyEpoch: ownerEpoch),
                  session.context?.page === page else { return }
            if let selection = run.savedSelection,
               (SavedPagesStore.shared.scopeID != selection.scopeID ||
                !SavedPagesStore.shared.entities.contains(where: { $0.id == selection.entityID })) {
                self.cancelGeneration(run, navigatingAway: true)
                return
            }
            switch event {
            case .accepted:
                if self.upload?.runID == runID { self.upload?.accepted = true }
            case .status(let status):
                session.updateStatus(
                    session.context?.isPending == false
                        ? "Responding…"
                        : status,
                    runID: runID)
            case .pagePreview(let revision, let attempt, let blocks, let draft):
                if session.applyPagePreview(revision: revision, attempt: attempt, blocks: blocks, draft: draft,
                                                          runID: runID, page: page), !page.visibleBlocks.isEmpty {
                    session.updateStatus("Responding…", runID: runID)
                    self.revealPending(runID)
                }
            case .clearPagePreview:
                session.clearPagePreview(runID: runID)
            case .pageSnapshot(_, let blocks):
                let meta = blocks.lazy.compactMap { block -> PageMeta? in
                    if case .pageMeta(let meta) = block { return meta }
                    return nil
                }.first
                let content = blocks.filter {
                    if case .pageMeta = $0 { return false }
                    return true
                }
                let animation: Animation? = page.blocks.map(\.id) == content.map(\.id)
                    ? nil : self.arrivalAnimation(on: page, of: run)
                withAnimation(animation) {
                    page.meta = meta
                    page.blocks = content
                }
                session.updateStatus("Responding…", runID: runID)
                if !content.isEmpty { self.revealPending(runID) }
                if self.visibleGeneration === run, self.currentPage === page, self.dockState == .idle, !page.spokeIntro,
                   let intro = content.lazy.compactMap({ block -> TextBlock? in
                       if case .text(let text) = block, text.style == .intro { return text }
                       return nil
                   }).first {
                    page.spokeIntro = true
                    VoiceOutput.shared.speak(intro.body, origin: page.origin)
                }
            case .finished(let persisted, let activities, let sources):
                page.activities = activities
                page.sources = sources
                session.markRevealed(runID: runID)
                if page.blocks.isEmpty { self.discardEmptyGenerationPage(page) }
                session.settle(.completed(runID: runID, persisted: persisted))
                self.history.invalidate()
                self.retainCompletedSavedEntityDetail(run)
            case .failed(let failure):
                let failurePage: GeneratedPage
                if let context = session.context,
                   context.runID == runID,
                   context.isPending,
                   let replacingPage = context.replacingPage {
                    failurePage = replacingPage
                } else {
                    failurePage = page
                }
                run.presentationPage = failurePage
                failurePage.blocks.removeAll {
                    if case .text(let text) = $0 { return text.id == "generation-error" }
                    return false
                }
                failurePage.blocks.append(.text(TextBlock(
                    id: "generation-error", body: failure.message, style: .footnote)))
                if var meta = failurePage.meta {
                    meta.dockAction = nil
                    failurePage.meta = meta
                }
                self.restoreAttachments(for: runID)
                if failurePage === page { self.revealPending(runID) }
                session.settle(.failed(runID: runID, failure: failure))
            }
        }
    }
}
