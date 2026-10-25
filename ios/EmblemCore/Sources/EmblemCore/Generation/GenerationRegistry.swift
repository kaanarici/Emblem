import Foundation
import Observation

@Observable @MainActor
public final class GenerationRegistry {
    public enum Admission { case ordinary, calendar, exclusive }
    public enum CalendarPageSelection: Equatable {
        case selected(actualPageID: UUID)
        case notKnown
        case rejected
    }
    public enum CalendarSelectionPlan {
        case selected(run: Run, pages: [GeneratedPage])
        case notKnown
        case rejected
    }

    final class CalendarFrame {
        let id: GenerationRunID
        let historyEpoch: UUID
        let saveScopeID: UUID
        let conversationKey: String
        let originPages: [GeneratedPage]

        fileprivate init(id: GenerationRunID, historyEpoch: UUID, saveScopeID: UUID,
                         conversationKey: String, originPages: [GeneratedPage]) {
            self.id = id
            self.historyEpoch = historyEpoch
            self.saveScopeID = saveScopeID
            self.conversationKey = conversationKey
            self.originPages = originPages
        }
    }

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
        let calendarFrame: CalendarFrame?
        let calendarPath: [GeneratedPage]
        public var presentationPage: GeneratedPage
        public var earlyPreview = false
        public var firstVisible = false
        public var savedSelection: SavedSelection?

        fileprivate init(session: GenerationSession, context: GenerationSession.Context,
                         historyEpoch: UUID, admissionOrder: UInt64,
                         calendarFrame: CalendarFrame? = nil, calendarPath: [GeneratedPage] = []) {
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
            self.calendarFrame = calendarFrame
            self.calendarPath = calendarPath
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
               attachments: [Attachment], retryAnchor: GeneratedPage?, historyEpoch: UUID,
               admission: Admission, navigationPrefix: [GeneratedPage] = []) -> Run? {
        var calendarSource: Run?
        if case .calendar = admission {
            guard page.calendarContext != nil, page.conversationKey == conversationKey,
                  navigationPrefix.isEmpty || navigationPrefix.last === source else { return nil }
            if let source, source.calendarContext != nil {
                guard let known = run(for: source), known.calendarFrame != nil,
                      visibleRun(for: source) === known,
                      known.historyEpoch == historyEpoch,
                      source.conversationKey == conversationKey else { return nil }
                calendarSource = known
            }
        }
        switch admission {
        case .ordinary: guard canBeginOrdinary(from: source) else { return nil }
        case .calendar: break
        case .exclusive: guard !isActive else { return nil }
        }
        let session = makeSession()
        guard let id = session.begin(page: page, conversationKey: conversationKey,
                                     originalAttachments: attachments, retryAnchorPage: retryAnchor),
              let context = session.context, context.runID == id else { return nil }
        if let calendarSource, calendarSource.saveScopeID != context.saveScopeID {
            _ = session.beginCancellation(runID: id)
            session.settle(.cancelled(runID: id))
            return nil
        }
        let frame: CalendarFrame?
        let calendarPath: [GeneratedPage]
        if case .calendar = admission {
            frame = calendarSource?.calendarFrame ?? CalendarFrame(
                id: id, historyEpoch: historyEpoch, saveScopeID: context.saveScopeID,
                conversationKey: conversationKey,
                originPages: navigationPrefix.isEmpty ? source.map { [$0] } ?? [] : navigationPrefix)
            calendarPath = (calendarSource?.calendarPath ?? []) + [page]
        } else {
            frame = nil
            calendarPath = []
        }
        let run = Run(session: session, context: context, historyEpoch: historyEpoch,
                      admissionOrder: nextOrder, calendarFrame: frame, calendarPath: calendarPath)
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
        let path = failed.calendarPath.isEmpty ? [] : Array(failed.calendarPath.dropLast()) + [context.page]
        let next = Run(session: failed.session, context: context, historyEpoch: failed.historyEpoch,
                       admissionOrder: failed.admissionOrder, calendarFrame: failed.calendarFrame,
                       calendarPath: path)
        next.savedSelection = failed.savedSelection
        runs[failed.id] = nil
        runs[next.id] = next
        selectedRunID = next.id
        return (next, retry)
    }

    private func calendarRun(representing page: GeneratedPage, in frame: CalendarFrame) -> Run? {
        runs.values.filter {
            $0.calendarFrame === frame &&
                ($0.page === page || $0.presentationPage === page ||
                 $0.page.runtimeReplacementAncestors.contains(page.id))
        }.max { $0.admissionOrder < $1.admissionOrder }
    }

    private func displayedCalendarPage(_ run: Run) -> GeneratedPage {
        if run.session.context?.isPending == true, let replacing = run.replacingPage { return replacing }
        return run.presentationPage
    }

    public func retainedCalendarPage(context: CalendarGenerationContext, from source: GeneratedPage,
                              navigationPages: [GeneratedPage], historyEpoch: UUID,
                              expectedScope: UUID) -> GeneratedPage? {
        guard let sourceIndex = navigationPages.firstIndex(where: { $0 === source }),
              source.calendarContext != nil,
              let sourceRun = run(for: source), let frame = sourceRun.calendarFrame,
              sourceRun.historyEpoch == historyEpoch, sourceRun.saveScopeID == expectedScope,
              frame.historyEpoch == historyEpoch, frame.saveScopeID == expectedScope,
              source.conversationKey == frame.conversationKey,
              let originHome = frame.originPages.first, originHome.isHome,
              navigationPages.first === originHome,
              frame.originPages.count <= sourceIndex else { return nil }
        for (index, captured) in frame.originPages.enumerated() {
            let actual = navigationPages[index]
            guard actual.isHome == captured.isHome, actual.conversationKey == captured.conversationKey,
                  actual === captured || (!actual.isHome && actual.runtimeReplacementAncestors.contains(captured.id))
            else { return nil }
        }
        for actual in navigationPages[frame.originPages.count...sourceIndex] {
            guard let member = calendarRun(representing: actual, in: frame),
                  member.historyEpoch == historyEpoch, member.saveScopeID == expectedScope,
                  actual.calendarContext == member.page.calendarContext,
                  actual.conversationKey == frame.conversationKey else { return nil }
        }
        guard let target = runs.values.filter({
            $0.calendarFrame === frame && $0.historyEpoch == historyEpoch &&
                $0.saveScopeID == expectedScope && $0.page.calendarContext == context
        }).max(by: { $0.admissionOrder < $1.admissionOrder }) else { return nil }
        let actual = displayedCalendarPage(target)
        guard actual.calendarContext == context, actual.conversationKey == frame.conversationKey else { return nil }
        return actual
    }

    public func calendarSelectionPlan(context: CalendarGenerationContext, from source: GeneratedPage,
                               navigationPages: [GeneratedPage], historyEpoch: UUID,
                               expectedScope: UUID) -> CalendarSelectionPlan {
        guard navigationPages.last === source, source.calendarContext != nil,
              let sourceRun = run(for: source), let frame = sourceRun.calendarFrame,
              visibleRun(for: source) === sourceRun,
              sourceRun.historyEpoch == historyEpoch, sourceRun.saveScopeID == expectedScope,
              frame.historyEpoch == historyEpoch, frame.saveScopeID == expectedScope,
              source.conversationKey == frame.conversationKey,
              let originHome = frame.originPages.first, originHome.isHome,
              navigationPages.first === originHome,
              frame.originPages.count < navigationPages.count else { return .rejected }
        var prefix: [GeneratedPage] = []
        for (index, captured) in frame.originPages.enumerated() {
            let actual = navigationPages[index]
            guard actual.isHome == captured.isHome, actual.conversationKey == captured.conversationKey,
                  actual === captured || (!actual.isHome && actual.runtimeReplacementAncestors.contains(captured.id))
            else { return .rejected }
            prefix.append(actual)
        }
        for actual in navigationPages.dropFirst(prefix.count) {
            guard let member = calendarRun(representing: actual, in: frame),
                  member.historyEpoch == historyEpoch, member.saveScopeID == expectedScope,
                  actual.calendarContext == member.page.calendarContext,
                  actual.conversationKey == frame.conversationKey
            else { return .rejected }
        }
        guard let target = runs.values.filter({
            $0.calendarFrame === frame && $0.historyEpoch == historyEpoch &&
                $0.saveScopeID == expectedScope && $0.page.calendarContext == context
        }).max(by: { $0.admissionOrder < $1.admissionOrder }) else { return .notKnown }
        for captured in target.calendarPath {
            guard let member = calendarRun(representing: captured, in: frame),
                  member.historyEpoch == historyEpoch, member.saveScopeID == expectedScope else { return .rejected }
            let actual = displayedCalendarPage(member)
            guard actual.calendarContext != nil, actual.conversationKey == frame.conversationKey,
                  !prefix.contains(where: { $0 === actual }) else { return .rejected }
            prefix.append(actual)
        }
        guard prefix.last === displayedCalendarPage(target),
              prefix.last?.calendarContext == context else { return .rejected }
        return .selected(run: target, pages: prefix)
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
