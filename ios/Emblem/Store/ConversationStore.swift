import Foundation
import Observation
import SwiftUI
import UIKit
import EmblemCore

enum DockState: Equatable {
    case idle
    case listening
    case keyboard
}

@Observable @MainActor
final class ConversationStore {
    var failureCount = 0
    enum HomeLoadState: Equatable { case idle, loading, failed }
    enum ConversationLoadState: Equatable {
        case idle
        case loading(key: String, showingCachedContent: Bool)
        case failed(key: String, showingCachedContent: Bool)
    }

    var pages: [GeneratedPage] = []
    var dockState: DockState = .idle
    var isViewingPhoto = false
    var isEditingWriting = false
    var attachmentsExpanded = false
    var attachmentsRevealNewest = false
    var lastAttachmentAdd = Date.distantPast
    let generationRegistry: GenerationRegistry
    let idleGenerationSession: GenerationSession
    let pagePreviewEnabled: Bool

    init(pagePreviewEnabled: Bool = true) {
        self.pagePreviewEnabled = pagePreviewEnabled
        generationRegistry = GenerationRegistry(pagePreviewEnabled: pagePreviewEnabled)
        idleGenerationSession = GenerationSession(pagePreviewEnabled: pagePreviewEnabled)
    }

    var visibleGeneration: GenerationRegistry.Run? {
        generationRegistry.visibleRun(for: currentPage)
    }
    var generationSession: GenerationSession {
        visibleGeneration?.session ?? idleGenerationSession
    }
    private var earlyPreviewRunID: GenerationRunID? {
        guard let run = visibleGeneration, run.earlyPreview else { return nil }
        return run.id
    }

    var visibleGenerationID: GenerationRunID? { visibleGeneration?.id }
    var isVisibleGenerationActive: Bool { generationSession.isActive }
    var canStartNewResponse: Bool { generationRegistry.canBeginOrdinary(from: currentPage) }
    var dockShowsGenerationStop: Bool {
        guard let run = visibleGeneration else { return idleGenerationSession.isGenerating }
        return run.session.isGenerating && !run.firstVisible
    }
    var responseWaveID: UUID?
    var attachments: [Attachment] = []
    var isGenerating: Bool { generationSession.isGenerating }
    var isGenerationActive: Bool { generationRegistry.isActive || idleGenerationSession.isActive }
    var isExpansionGeneration: Bool { generationSession.context?.page.isExpansion == true }
    var isPresentingEarlyServerPreview: Bool {
        guard isGenerating, let context = generationSession.context else { return false }
        return earlyPreviewRunID == context.runID
            && context.saveScopeID == SavedPagesStore.shared.scopeID
            && context.page.origin == .server
            && !context.page.isExpansion
            && pages.last === context.page
    }

    var pendingPresentationSourcePage: GeneratedPage? {
        guard let context = generationSession.context, context.isPending,
              context.saveScopeID == SavedPagesStore.shared.scopeID,
              !context.page.isExpansion,
              pages.last === context.page,
              let source = context.retryAnchorPage,
              pages.contains(where: { $0 === source }) else { return nil }
        return source
    }

    func blockInteraction(for page: GeneratedPage) -> BlockInteraction {
        let epoch = history.epoch
        return BlockInteraction { [weak self, weak page] in
            guard let self, let page else {
                return .init(isCurrentPage: false, isPageStreaming: true,
                             isGenerating: false, isGenerationActive: false)
            }
            return .init(
                isCurrentPage: self.history.epoch == epoch && self.currentPage === page && !page.hasProvisionalPresentation
                    && self.visibleGeneration === self.generationRegistry.run(for: page),
                isPageStreaming: page.isStreaming,
                isGenerating: self.generationRegistry.run(for: page)?.session.isGenerating ?? false,
                isGenerationActive: self.generationRegistry.run(for: page)?.session.isActive ?? false)
        }
    }
    var isAwaitingFirstGenerationContent: Bool {
        guard isGenerating else { return false }
        return generationSession.context?.isPending ?? true
    }
    var statusText: String? {
        showsUploadingAttachment ? upload?.status : generationSession.statusText
    }

    struct Upload {
        let attachment: Attachment
        let status: String
        let runID: GenerationRunID?
        var accepted = false
        var minimumElapsed = false
    }
    var upload: Upload?
    var isOpeningConversation: Bool {
        if case .loading(_, showingCachedContent: false) = conversationLoadState { return true }
        return false
    }
    var completedGenerationID: GenerationRunID? { generationSession.completedRunID }
    var conversationLoadState: ConversationLoadState = .idle
    var openingAutomationID: String?
    var automationOpenFailureID: String?
    var homeLoadState: HomeLoadState = .idle
    struct ExpansionKey: Hashable {
        let parentPageKey: String
        let sourceCardKey: String
    }
    var expansionPages: [ExpansionKey: GeneratedPage] = [:]
    var canRetryCurrentGeneration: Bool {
        guard let run = visibleGeneration else { return false }
        return generationRegistry.canRetry(run, currentPage: currentPage,
                                           blockedConversations: history.removingKeys, historyEpoch: history.epoch)
    }

    let homeClient = GenerateClient()
    let history = ConversationHistory.shared
    var greetingName: String?
    var restoreTask: Task<Void, Never>?
    var restoreRequestID = UUID()
    var homeRequestID = UUID()
    nonisolated static let freshConversationCacheAge: TimeInterval = 30

    var locationSnapshot: LocationSnapshot? { generationSession.locationSnapshot }

    var currentPage: GeneratedPage? { pages.last }
    var currentConversationKey: String? { currentPage?.conversationKey }
    var dockAction: Action? {
        guard let page = currentPage else { return nil }
        if activeQuestion != nil { return Self.doneAction }
        if let action = page.meta?.dockAction { return action }

        let requiredQuestions = page.blocks.flatMap { block -> [String] in
            switch block {
            case .questionList(let list):
                return list.items.compactMap { $0.input == nil ? nil : $0.question }
            case .chipRow(let row) where row.role == .requiredChoice:
                guard let question = row.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !question.isEmpty
                else { return [] }
                return [question]
            default:
                return []
            }
        }
        guard !requiredQuestions.isEmpty else { return nil }
        let asksArea = page.blocks.contains {
            if case .questionList(let list) = $0 { return list.inlineArea != nil }
            return false
        }
        return asksArea ? Self.nextAction : Self.continueAction
    }

    static let continueAction = Action(label: "Continue", prompt: "Continue")
    static let nextAction = Action(label: "Next", prompt: "Continue")
    static let doneAction = Action(label: "Done", prompt: "Done")
    var presentedQuestion: (page: UUID, item: QuestionList.Item)?
    var questionDraft = ""
    var flagged: (page: UUID, questions: Set<String>)?
    var prefetchedOptions: [String: [QuestionOption]] = [:]
    var optionPrefetches: Set<String> = []
    var homePage: GeneratedPage? { pages.first(where: \.isHome) }
    var forwardPages: [GeneratedPage] = []
    struct OlderPages {
        let id = UUID()
        let conversationKey: String
        let cursor: String
        var task: Task<Void, Never>?
    }
    var olderPages: OlderPages?
}
