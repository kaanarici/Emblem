import Foundation
import Observation

@Observable @MainActor
public final class GenerationSession {
    public struct CompletedPageReceipt {
        let snapshot: SavedPage.Snapshot
        let runtimePageID: UUID
        let requestID: String
        let runID: GenerationRunID
        public let saveScopeID: UUID

        @MainActor
        fileprivate init(context: Context) {
            snapshot = SavedPage.Snapshot(page: context.page)
            runtimePageID = context.page.id
            requestID = context.requestID
            runID = context.runID
            saveScopeID = context.saveScopeID
        }
    }

    public struct Context {
        public let runID: GenerationRunID
        public let requestID: String
        public let saveScopeID: UUID
        public let page: GeneratedPage
        public let conversationKey: String
        let originalAttachments: [Attachment]
        public let retryAnchorPage: GeneratedPage?
        public let replacingPage: GeneratedPage?
        var request: GenerateClient.GenerateBody?
        public var isPending = true
        var userStopped = false
        var preflightTask: Task<Void, Never>?
        var nativeTask: Task<Void, Never>?
    }

    public struct RetryStart {
        let runID: GenerationRunID
        public let request: GenerateClient.GenerateBody
        public let originalAttachments: [Attachment]
    }

    private struct RetryCandidate {
        let request: GenerateClient.GenerateBody
        let page: GeneratedPage
        let originalAttachments: [Attachment]
        let saveScopeID: UUID
    }

    private(set) var lifecycle = GenerationLifecycle.idle
    public private(set) var context: Context?
    public private(set) var completedPageReceipt: CompletedPageReceipt?
    private var retryCandidate: RetryCandidate?
    private let savedPages: SavedPagesStore
    private let client = GenerateClient()
    let pagePreviewEnabled: Bool
    private var transportID: UUID?
    private let location = LocationService()

    public init(savedPages: SavedPagesStore = .shared, pagePreviewEnabled: Bool = false) {
        self.savedPages = savedPages
        self.pagePreviewEnabled = pagePreviewEnabled
    }

    public var isActive: Bool { lifecycle.isActive }
    public var isGenerating: Bool { lifecycle.isGenerating }
    public var statusText: String? { lifecycle.statusText }
    public var activeRunID: GenerationRunID? { lifecycle.activeRunID }
    public var locationSnapshot: LocationSnapshot? { location.snapshot }
    public var completedRunID: GenerationRunID? {
        guard case .completed(let runID, _) = lifecycle.terminalOutcome else { return nil }
        return runID
    }

    func canRetry(
        currentPage: GeneratedPage?,
        attachments: [Attachment],
        blockedConversationKeys: Set<String>
    ) -> Bool {
        guard !isActive,
              let candidate = retryCandidate,
              candidate.saveScopeID == savedPages.scopeID,
              currentPage === candidate.page else { return false }
        if let key = candidate.page.conversationKey,
           blockedConversationKeys.contains(key) {
            return false
        }
        let available = Set(attachments.map(\.id))
        return candidate.originalAttachments.allSatisfy { available.contains($0.id) }
    }

    func begin(
        page: GeneratedPage,
        conversationKey: String,
        originalAttachments: [Attachment],
        retryAnchorPage: GeneratedPage?
    ) -> GenerationRunID? {
        let runID = GenerationRunID()
        guard lifecycle.begin(runID: runID) else { return nil }
        retryCandidate = nil
        completedPageReceipt = nil
        transportID = nil
        page.beginPagePreview(runID: runID, scopeID: savedPages.scopeID)
        context = Context(
            runID: runID,
            requestID: page.pageKey,
            saveScopeID: savedPages.scopeID,
            page: page,
            conversationKey: conversationKey,
            originalAttachments: originalAttachments,
            retryAnchorPage: retryAnchorPage,
            replacingPage: nil,
            request: nil)
        return runID
    }

    func beginRetry(
        currentPage: GeneratedPage?,
        attachments: [Attachment],
        blockedConversationKeys: Set<String>
    ) -> RetryStart? {
        guard canRetry(
            currentPage: currentPage,
            attachments: attachments,
            blockedConversationKeys: blockedConversationKeys),
            let candidate = retryCandidate
        else { return nil }

        let failedPage = candidate.page
        let replacement = GeneratedPage(
            prompt: failedPage.prompt,
            conversationKey: failedPage.conversationKey,
            pageKey: failedPage.pageKey,
            previousPageKey: failedPage.previousPageKey,
            parentPageKey: failedPage.parentPageKey,
            sourceCardKey: failedPage.sourceCardKey,
            runtimeReplacementAncestors: failedPage.runtimeReplacementAncestors.union([failedPage.id]))
        replacement.isExpansion = failedPage.isExpansion
        replacement.expansionSource = failedPage.expansionSource
        let runID = GenerationRunID()
        guard lifecycle.begin(runID: runID) else { return nil }

        let request = candidate.request.retrying()
        retryCandidate = nil
        completedPageReceipt = nil
        transportID = nil
        failedPage.clearPagePresentation()
        replacement.beginPagePreview(runID: runID, scopeID: candidate.saveScopeID)
        context = Context(
            runID: runID,
            requestID: request.requestId,
            saveScopeID: candidate.saveScopeID,
            page: replacement,
            conversationKey: request.conversationKey,
            originalAttachments: candidate.originalAttachments,
            retryAnchorPage: failedPage,
            replacingPage: failedPage,
            request: request)
        return RetryStart(
            runID: runID,
            request: request,
            originalAttachments: candidate.originalAttachments)
    }

    func accepts(_ runID: GenerationRunID) -> Bool {
        guard lifecycle.acceptsEvents(for: runID), context?.runID == runID else { return false }
        guard context?.saveScopeID == savedPages.scopeID else {
            context?.page.clearPagePresentation()
            return false
        }
        return true
    }

    @discardableResult
    public func applyPagePreview(revision: Int, attempt: Int, blocks: [Block], draft: String?? = .none,
                          runID: GenerationRunID, page: GeneratedPage) -> Bool {
        guard accepts(runID), let context, context.page === page,
              context.requestID == page.pageKey else { return false }
        return page.replacePagePreview(revision: revision, attempt: attempt, blocks: blocks, draft: draft,
                                       runID: runID, scopeID: context.saveScopeID)
    }

    public func clearPagePreview(runID: GenerationRunID) {
        guard context?.runID == runID else { return }
        context?.page.clearPagePresentation()
    }

    public func updateStatus(_ status: String, runID: GenerationRunID) {
        _ = lifecycle.apply(.status(status), to: runID)
    }

    public func setPreflightTask(_ task: Task<Void, Never>, runID: GenerationRunID) {
        guard context?.runID == runID else {
            task.cancel()
            return
        }
        context?.preflightTask = task
    }

    public func setNativeTask(_ task: Task<Void, Never>, runID: GenerationRunID) {
        guard context?.runID == runID else {
            task.cancel()
            return
        }
        context?.nativeTask = task
    }

    public func clearNativeTask(runID: GenerationRunID) {
        guard context?.runID == runID else { return }
        context?.nativeTask = nil
    }

    public func markRevealed(runID: GenerationRunID) {
        guard context?.runID == runID else { return }
        context?.isPending = false
    }

    public func startStream(
        request: GenerateClient.GenerateBody,
        runID: GenerationRunID,
        onEvent: @escaping @MainActor (GenerateClient.Event) -> Void
    ) {
        guard accepts(runID) else { return }
        context?.request = request
        streamResumably(request: request, runID: runID, budget: ResumeBudget(), onEvent: onEvent)
    }

    struct ResumeBudget: Equatable {
        var dropped = 2
        var stillGenerating = 120
    }

    nonisolated static func resumption(after failure: GenerationFailure, budget: ResumeBudget) -> (delay: Duration, budget: ResumeBudget)? {
        guard canResumeSilently(failure) else { return nil }
        var next = budget
        if failure.code == "generation_in_progress" {
            guard budget.stillGenerating > 0 else { return nil }
            next.stillGenerating -= 1
            return (.milliseconds(1_500), next)
        }
        guard budget.dropped > 0 else { return nil }
        next.dropped -= 1
        return (.milliseconds(600), next)
    }

    private func streamResumably(
        request: GenerateClient.GenerateBody,
        runID: GenerationRunID,
        budget: ResumeBudget,
        resuming: Bool = false,
        onEvent: @escaping @MainActor (GenerateClient.Event) -> Void
    ) {
        guard accepts(runID), let context else { return }
        let transport = UUID()
        transportID = transport
        context.page.beginPagePreview(runID: runID, scopeID: context.saveScopeID, keepingVisible: resuming)
        client.stream(body: request, pagePreviewEnabled: pagePreviewEnabled) { [weak self] event in
            guard let self, self.transportID == transport, self.accepts(runID) else { return }
            var resumption: (delay: Duration, budget: ResumeBudget)?
            if case .failed(let failure) = event { resumption = Self.resumption(after: failure, budget: budget) }
            switch event {
            case .failed where resumption != nil:
                break
            case .clearPagePreview, .failed:
                self.clearPagePreview(runID: runID)
            case .pageSnapshot, .finished:
                self.clearPagePreview(runID: runID)
            default: break
            }
            if let resumption {
                self.transportID = nil
                let resumed = request.retrying()
                self.context?.request = resumed
                Task { [weak self] in
                    try? await Task.sleep(for: resumption.delay)
                    guard let self, self.accepts(runID) else { return }
                    self.streamResumably(
                        request: resumed,
                        runID: runID,
                        budget: resumption.budget,
                        resuming: true,
                        onEvent: onEvent)
                }
                return
            }
            onEvent(event)
        }
    }

    private nonisolated static func canResumeSilently(_ failure: GenerationFailure) -> Bool {
        guard failure.retryable else { return false }
        if failure.code.hasPrefix("network_") { return true }
        return [
            "stream_cutoff", "connection_lost", "timeout",
            "invalid_stream", "invalid_response",
            "generation_in_progress", "generation_state_unavailable",
            "http_502", "http_503", "http_504",
        ].contains(failure.code)
    }

    public func beginCancellation(runID: GenerationRunID, preserveVisibleSnapshot: Bool = false) -> Bool {
        guard context?.runID == runID,
              lifecycle.beginCancellation(runID: runID) else { return false }
        context?.userStopped = preserveVisibleSnapshot
        if let context, preserveVisibleSnapshot, context.saveScopeID == savedPages.scopeID {
            context.page.freezePagePreviewForStop(runID: runID, scopeID: context.saveScopeID)
        } else {
            context?.page.clearPagePresentation()
        }
        transportID = nil
        client.cancel()
        context?.preflightTask?.cancel()
        context?.nativeTask?.cancel()
        return true
    }

    public func awaitCancellationAcknowledgement(
        runID: GenerationRunID
    ) async -> GenerateClient.CancellationAcknowledgement {
        guard let context, context.runID == runID, let request = context.request else {
            return .cancelled
        }
        return await client.acknowledgeCancellation(
            requestId: request.requestId,
            conversationKey: request.conversationKey)
    }

    public func cancelActiveWithoutContext(runID: GenerationRunID) {
        guard context?.runID != runID else { return }
        _ = lifecycle.apply(.cancelled, to: runID)
    }

    func originalAttachments(runID: GenerationRunID) -> [Attachment] {
        guard let context, context.runID == runID else { return [] }
        return context.originalAttachments
    }

    public func settle(_ outcome: GenerationTerminalOutcome) {
        let runID = outcome.runID
        guard let context, context.runID == runID else { return }
        let completedFromActive = lifecycle.acceptsEvents(for: runID)
        let event: GenerationLifecycle.Event
        switch outcome {
        case .completed(_, let persisted): event = .completed(persisted: persisted)
        case .failed(_, let failure): event = .failed(failure)
        case .cancelled: event = .cancelled
        }
        guard lifecycle.apply(event, to: runID) else { return }
        completedPageReceipt = nil

        let page = context.page
        transportID = nil
        let preservesStopped: Bool = switch outcome {
        case .completed: false
        default: context.userStopped && context.saveScopeID == savedPages.scopeID
        }
        page.clearPagePresentation(preservingStopped: preservesStopped)
        let keepsRetrySnapshot: Bool = switch outcome {
        case .failed(_, let failure): failure.retryable
        case .cancelled: false
        case .completed: false
        }
        if keepsRetrySnapshot {
            if let request = context.request {
                retryCandidate = RetryCandidate(
                    request: request,
                    page: context.isPending
                        ? context.replacingPage ?? context.retryAnchorPage ?? page
                        : page,
                    originalAttachments: context.originalAttachments,
                    saveScopeID: context.saveScopeID)
            } else {
                retryCandidate = nil
            }
        } else {
            retryCandidate = nil
        }

        if case .completed(_, let persisted) = outcome,
           persisted == false,
           !page.blocks.isEmpty,
           !page.blocks.contains(where: {
               if case .text(let text) = $0 { return text.id == "generation-unsaved" }
               return false
           }) {
            let warning = Block.text(TextBlock(
                id: "generation-unsaved",
                body: "This page is here for now, but it isn't saved to your chats.",
                style: .footnote))
            if let terminal = page.blocks.lastIndex(where: {
                switch $0 { case .pageMeta, .unknown: false; default: true }
            }), case .chipRow(let row) = page.blocks[terminal], row.role == .followUp {
                page.blocks.insert(warning, at: terminal)
            } else {
                page.blocks.append(warning)
            }
        }
        page.isStreaming = false
        if case .completed = outcome,
           completedFromActive,
           context.saveScopeID == savedPages.scopeID,
           !page.isHome,
           !context.requestID.isEmpty,
           page.pageKey == context.requestID,
           !context.conversationKey.isEmpty,
           page.conversationKey == context.conversationKey,
           context.request.map({
               $0.requestId == context.requestID && $0.conversationKey == context.conversationKey
           }) ?? true,
           !page.blocks.contains(where: {
               if case .text(let text) = $0 { return text.id == "generation-error" }
               return false
           }),
           page.blocks.contains(where: {
               switch $0 {
               case .unknown, .pageMeta: false
               case .text(let text):
                   !["generation-unsaved", "generation-cancelled"].contains(text.id) &&
                       !text.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
               default: true
               }
           }) {
            completedPageReceipt = CompletedPageReceipt(context: context)
        }
        self.context = nil
    }

    public func clearRetryCandidate() {
        retryCandidate = nil
        completedPageReceipt = nil
    }

    public func clearRetryCandidate(conversationKey: String) {
        completedPageReceipt = nil
        guard retryCandidate?.page.conversationKey == conversationKey else { return }
        retryCandidate = nil
    }

    public func clearRetryCandidate(attachmentID: UUID) {
        completedPageReceipt = nil
        guard retryCandidate?.originalAttachments.contains(where: { $0.id == attachmentID }) == true
        else { return }
        retryCandidate = nil
    }

    public func clearRetryCandidate(page: GeneratedPage?) {
        completedPageReceipt = nil
        guard retryCandidate?.page === page else { return }
        retryCandidate = nil
    }

    public func resolveLocation() async -> GenerateClient.WireLocation? {
        let snapshot = await withTaskGroup(of: LocationSnapshot?.self) { group in
            group.addTask { await self.location.requestOnce() }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let snapshot else { return nil }
        return GenerateClient.WireLocation(
            city: snapshot.city,
            region: snapshot.region,
            country: snapshot.country,
            latitude: snapshot.latitude,
            longitude: snapshot.longitude)
    }
}
