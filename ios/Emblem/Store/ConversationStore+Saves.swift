import Foundation
import Observation
import SwiftUI
import UIKit
import EmblemCore

extension ConversationStore {
    func saveWritingDraft(
        page: GeneratedPage, blockID: String, draftID: String, previousBody: String, body: String
    ) async throws {
        guard pages.contains(where: { $0 === page }) else { throw CancellationError() }
        let epoch = history.epoch
        try await WritingClient.save(page: page, blockID: blockID, draftID: draftID, previousBody: previousBody, body: body)
        guard history.epoch == epoch,
              let index = page.blocks.firstIndex(where: { $0.id == blockID }),
              case .writing(var writing) = page.blocks[index],
              let draftIndex = writing.drafts.firstIndex(where: { $0.id == draftID }) else { return }
        writing.drafts[draftIndex].body = body
        page.blocks[index] = .writing(writing)
        if let key = page.conversationKey {
            let cache = history.cache
            Task.detached { cache.remove(for: key, epoch: epoch) }
        }
    }

    func openSavedPage(_ page: GeneratedPage) {
        guard !generationSession.isActive else { return }
        cancelRestore()
        forwardPages = []
        withAnimation(navigationAnimation(expansion: false)) {
            pages.append(page)
        }
    }

    @discardableResult
    func returnFromSavedPage(_ page: GeneratedPage, to originIDs: [UUID]) -> Bool {
        guard currentPage === page, pages.last === page,
              navigationPageIDs.last == page.id,
              navigationPageIDs.count == originIDs.count + 1, canGoBack else { return false }
        let saves = SavedPagesStore.shared
        if let run = generationRegistry.run(for: page),
           let selection = run.savedSelection,
           selection.scopeID == saves.scopeID,
           !saves.entities.contains(where: { $0.id == selection.entityID }) {
            run.savedSelection = nil
        }
        cancelRestore()
        VoiceOutput.shared.stop()
        withAnimation(navigationAnimation(expansion: page.isExpansion)) {
            recordForward(popping: [pages.removeLast()])
        }
        generationRegistry.select(page: currentPage)
        return true
    }

    @discardableResult
    func generateSavedEntity(id: UUID, expectedScope: UUID) -> GeneratedPage? {
        let saves = SavedPagesStore.shared
        guard generationRegistry.canBeginOrdinary(from: currentPage), saves.scopeID == expectedScope,
              let entity = saves.entities.first(where: { $0.id == id }),
              entity.isValidArchiveRecord,
              let selection = try? GenerateClient.GenerateBody.SavedSelection(entity: entity) else { return nil }
        let prompt = entity.card.prompt ?? "Tell me more about \(entity.card.title)"
        let conversationKey = entity.origin.conversationKey ?? UUID().uuidString
        let page = GeneratedPage(prompt: prompt, conversationKey: conversationKey,
                                 previousPageKey: entity.origin.parentPageKey,
                                 parentPageKey: entity.origin.parentPageKey,
                                 sourceCardKey: entity.origin.sourceCardKey)
        page.isExpansion = true
        page.expansionSource = PageExpansionSource(
            parentPageID: currentPage?.id ?? entity.id,
            parentPageKey: entity.origin.parentPageKey,
            sourceCardKey: entity.origin.sourceCardKey, card: entity.card)
        guard let run = generationRegistry.begin(page: page, from: currentPage,
            conversationKey: conversationKey, attachments: [], retryAnchor: currentPage,
            historyEpoch: history.epoch, admission: .ordinary) else { return nil }
        let runID = run.id
        cancelRestore()
        VoiceOutput.shared.stop()
        run.savedSelection = .init(entityID: id, scopeID: expectedScope)
        forwardPages = []
        dockState = .idle
        withAnimation(navigationAnimation(expansion: true)) { pages.append(page) }
        let request = GenerateClient.GenerateBody(
            messages: [.init(role: "user", content: prompt)], requestId: page.pageKey,
            conversationKey: conversationKey, previousPageKey: entity.origin.parentPageKey,
            parentPageKey: entity.origin.parentPageKey, sourceCardKey: entity.origin.sourceCardKey,
            sourceCardTitle: entity.card.title,
            sourceCardHasImage: entity.card.image != nil || entity.card.imageURL != nil,
            savedSelection: selection, memory: false, device: DeviceAccess.advertisedSources)
        startStream(request: request, runID: runID)
        return page
    }

    func retainCompletedSavedEntityDetail(_ run: GenerationRegistry.Run) {
        guard let receipt = run.session.completedPageReceipt else { return }
        let saves = SavedPagesStore.shared
        guard saves.scopeID == receipt.saveScopeID,
              let detail = try? SavedEntity.CompletedDetail(receipt: receipt, expectedScope: receipt.saveScopeID) else { return }
        for entity in saves.entities where entity.origin.parentPageKey == detail.snapshot.parentPageKey &&
            entity.origin.sourceCardKey == detail.snapshot.sourceCardKey &&
            entity.origin.conversationKey == detail.snapshot.conversationKey {
            do { try saves.attachCompletedDetail(detail, to: entity.id, expectedScope: receipt.saveScopeID) }
            catch {}
        }
        run.savedSelection = nil
    }
}
