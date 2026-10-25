import Foundation
import Observation

@Observable @MainActor
public final class GenerationRegistry {

    public struct SavedSelection {
        public let entityID: UUID
        public let scopeID: UUID

        public init(entityID: UUID, scopeID: UUID) {
            self.entityID = entityID
            self.scopeID = scopeID
        }
    }

    @Observable @MainActor
    public final class Run {
        public let id: GenerationRunID
        public let page: GeneratedPage
        public let session: GenerationSession
        public let historyEpoch: UUID
        public let saveScopeID: UUID
        public let originalAttachments: [Attachment]
        let retryAnchorPage: GeneratedPage?
        public let replacingPage: GeneratedPage?
        public let admissionOrder: UInt64
        public var presentationPage: GeneratedPage
        public var earlyPreview = false
        public var firstVisible = false
        public var savedSelection: SavedSelection?

        fileprivate init(session: GenerationSession, context: GenerationSession.Context,
                         historyEpoch: UUID, admissionOrder: UInt64) {
            id = context.runID
            page = context.page
            presentationPage = context.page
            self.session = session
            self.historyEpoch = historyEpoch
            saveScopeID = context.saveScopeID
            originalAttachments = context.originalAttachments
            retryAnchorPage = context.retryAnchorPage
            replacingPage = context.replacingPage
            self.admissionOrder = admissionOrder
        }
    }

    public private(set) var runs: [GenerationRunID: Run] = [:]
    private(set) var selectedRunID: GenerationRunID?
    @ObservationIgnored private let makeSession: @MainActor () -> GenerationSession
    private var nextOrder: UInt64 = 0

    public init(pagePreviewEnabled: Bool = true,
         makeSession: (@MainActor () -> GenerationSession)? = nil) {
        self.makeSession = makeSession ?? { GenerationSession(pagePreviewEnabled: pagePreviewEnabled) }
    }

    public var isActive: Bool { runs.values.contains { $0.session.isActive } }

    public func run(for page: GeneratedPage?) -> Run? {
        guard let page else { return nil }
        return runs.values.first {
            $0.page === page || $0.presentationPage === page ||
                ($0.session.context?.isPending == true && $0.replacingPage === page)
        }
    }

    public func visibleRun(for page: GeneratedPage?) -> Run? {
        if let selectedRunID, let selected = runs[selectedRunID],
           selected.session.context?.isPending == true,
           selected.page !== page,
           selected.retryAnchorPage === page || selected.replacingPage === page {
            return selected
        }
        return run(for: page)
    }

    public func select(page: GeneratedPage?) { selectedRunID = run(for: page)?.id }

    public func canBeginOrdinary(from page: GeneratedPage?) -> Bool {
        guard let run = visibleRun(for: page), run.session.isActive else { return true }
        return run.session.isGenerating && run.firstVisible
    }

    @discardableResult
    public func begin(page: GeneratedPage, from source: GeneratedPage?, conversationKey: String,
               attachments: [Attachment], retryAnchor: GeneratedPage?, historyEpoch: UUID) -> Run? {
        guard canBeginOrdinary(from: source) else { return nil }
        let session = makeSession()
        guard let id = session.begin(page: page, conversationKey: conversationKey,
                                     originalAttachments: attachments, retryAnchorPage: retryAnchor),
              let context = session.context, context.runID == id else { return nil }
        let run = Run(session: session, context: context, historyEpoch: historyEpoch, admissionOrder: nextOrder)
        nextOrder &+= 1
        runs[id] = run
        selectedRunID = id
        return run
    }

    public func accepts(_ run: Run, historyEpoch: UUID) -> Bool {
        runs[run.id] === run && run.historyEpoch == historyEpoch && run.session.accepts(run.id)
            && run.session.context?.page === run.page
    }

    public func markVisible(_ run: Run) {
        guard runs[run.id] === run, run.session.accepts(run.id),
              Self.hasVisibleContent(run.page) else { return }
        run.firstVisible = true
        run.session.markRevealed(runID: run.id)
    }

    public static func hasVisibleContent(_ page: GeneratedPage) -> Bool {
        page.visibleBlocks.contains {
            switch $0 {
            case .pageMeta, .unknown: false
            case .text(let text): !text.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            default: true
            }
        }
    }

    public func canRetry(_ run: Run, currentPage: GeneratedPage?, blockedConversations: Set<String>,
                  historyEpoch: UUID) -> Bool {
        guard runs[run.id] === run, run.historyEpoch == historyEpoch else { return false }
        return run.session.canRetry(currentPage: currentPage, attachments: run.originalAttachments,
                                    blockedConversationKeys: blockedConversations)
    }

    public func beginRetry(_ failed: Run, currentPage: GeneratedPage?, blockedConversations: Set<String>,
                    historyEpoch: UUID) -> (Run, GenerationSession.RetryStart)? {
        guard runs[failed.id] === failed, failed.historyEpoch == historyEpoch,
              let retry = failed.session.beginRetry(currentPage: currentPage,
                  attachments: failed.originalAttachments, blockedConversationKeys: blockedConversations),
              let context = failed.session.context, context.runID == retry.runID else { return nil }
        let next = Run(session: failed.session, context: context, historyEpoch: failed.historyEpoch,
                       admissionOrder: failed.admissionOrder)
        next.savedSelection = failed.savedSelection
        runs[failed.id] = nil
        runs[next.id] = next
        selectedRunID = next.id
        return (next, retry)
    }

    public func invalidateAll() {
        for run in runs.values {
            if run.session.isActive {
                _ = run.session.beginCancellation(runID: run.id)
                run.session.settle(.cancelled(runID: run.id))
            }
            run.session.clearRetryCandidate()
        }
        runs.removeAll()
        selectedRunID = nil
    }
}
