import Foundation
import Observation
import SwiftUI
import UIKit
import EmblemCore

extension ConversationStore {
    private struct RemovedConversationCard {
        let home: GeneratedPage
        let carouselID: String
        let carouselIndex: Int
        let cardIndex: Int
        let card: CardCarousel.Card
        let header: SectionHeader?
        let headerIndex: Int?
    }

    @discardableResult
    func archiveConversation(key: String, onFailure: (@MainActor () -> Void)? = nil) -> Bool {
        removeConversation(key: key, change: .archive(true), onFailure: onFailure)
    }

    @discardableResult
    func deleteConversation(key: String, onFailure: (@MainActor () -> Void)? = nil) -> Bool {
        removeConversation(key: key, change: .delete, onFailure: onFailure)
    }

    func setConversationPinned(key: String, pinned: Bool, onFailure: (@MainActor () -> Void)? = nil) {
        let history = self.history
        guard let edit = withAnimation(.smooth(duration: 0.3), { history.edit(key, .pin(pinned)) }) else { return }
        Task {
            guard await history.save(edit) == .failed else { return }
            withAnimation(.smooth(duration: 0.3)) { history.discard(edit) }
            onFailure?()
        }
    }

    @discardableResult
    func renameConversation(key: String, title: String, onFailure: (@MainActor () -> Void)? = nil) -> Bool {
        changeConversation(key: key, change: .rename(title), onFailure: onFailure)
    }

    @discardableResult
    func unarchiveConversation(key: String, onFailure: (@MainActor () -> Void)? = nil) -> Bool {
        changeConversation(key: key, change: .archive(false), onFailure: onFailure)
    }

    func renameCurrentConversation(_ title: String) {
        guard let key = currentConversationKey else { return }
        let originals = pages.compactMap { page -> (GeneratedPage, String?)? in
            guard !page.isHome else { return nil }
            return (page, page.meta?.title)
        }
        guard renameConversation(key: key, title: title, onFailure: {
            for (page, originalTitle) in originals {
                guard var meta = page.meta else { continue }
                meta.title = originalTitle
                page.meta = meta
            }
        }) else { return }
        for page in pages where !page.isHome {
            if var meta = page.meta {
                meta.title = title
                page.meta = meta
            }
        }
    }

    func commitConversationChanges(_ edits: [ConversationHistory.Edit], onFailure: (@MainActor () -> Void)? = nil) {
        let history = self.history
        Task { [weak self] in
            switch await history.save(edits) {
            case .saved: self?.refreshHome()
            case .failed:
                edits.forEach(history.discard)
                onFailure?()
            case .superseded: break
            }
        }
    }

    func commitConversationRemovals(_ edits: [ConversationHistory.Edit], onFailure: (@MainActor () -> Void)? = nil) {
        let history = self.history
        let keys = Set(edits.map(\.key))
        let removed = keys.compactMap(removeConversationCard)
        for run in generationRegistry.runs.values
        where run.page.conversationKey.map(keys.contains) == true && run.session.isActive {
            cancelGeneration(run, navigatingAway: true)
        }
        if let current = currentConversationKey, keys.contains(current) {
            popToHome(refresh: false)
        }
        Task { [weak self] in
            switch await history.save(edits) {
            case .saved:
                guard let self else { return }
                for run in self.generationRegistry.runs.values {
                    guard let key = run.page.conversationKey, keys.contains(key) else { continue }
                    run.session.clearRetryCandidate(conversationKey: key)
                }
                self.forwardPages.removeAll { $0.conversationKey.map(keys.contains) == true }
            case .failed:
                edits.forEach(history.discard)
                for removal in removed.reversed() { self?.restoreConversationCard(removal) }
                onFailure?()
            case .superseded: break
            }
        }
    }

    private func changeConversation(
        key: String, change: ConversationHistory.Change, onFailure: (@MainActor () -> Void)?
    ) -> Bool {
        guard let edit = history.edit(key, change) else { return false }
        commitConversationChanges([edit], onFailure: onFailure)
        return true
    }

    private func removeConversation(
        key: String, change: ConversationHistory.Change, onFailure: (@MainActor () -> Void)?
    ) -> Bool {
        guard let edit = history.edit(key, change) else { return false }
        commitConversationRemovals([edit], onFailure: onFailure)
        return true
    }

    private func removeConversationCard(_ key: String) -> RemovedConversationCard? {
        guard let home = homePage else { return nil }
        for blockIndex in home.blocks.indices {
            guard case .cardCarousel(var carousel) = home.blocks[blockIndex],
                  let cardIndex = carousel.cards.firstIndex(where: { $0.conversation == key })
            else { continue }

            let card = carousel.cards.remove(at: cardIndex)
            let headerIndex = blockIndex > 0 ? blockIndex - 1 : nil
            let header: SectionHeader? = headerIndex.flatMap { index in
                guard case .sectionHeader(let value) = home.blocks[index],
                      value.id == "\(carousel.id)-h"
                else { return nil }
                return value
            }
            let removal = RemovedConversationCard(
                home: home,
                carouselID: carousel.id,
                carouselIndex: blockIndex,
                cardIndex: cardIndex,
                card: card,
                header: header,
                headerIndex: header == nil ? nil : headerIndex)

            withAnimation(.smooth(duration: 0.25)) {
                if carousel.cards.isEmpty {
                    home.blocks.remove(at: blockIndex)
                    if let headerIndex = removal.headerIndex {
                        home.blocks.remove(at: headerIndex)
                    }
                } else {
                    home.blocks[blockIndex] = .cardCarousel(carousel)
                }
            }
            return removal
        }
        return nil
    }

    private func restoreConversationCard(_ removal: RemovedConversationCard) {
        guard homePage === removal.home else { return }
        if let blockIndex = removal.home.blocks.firstIndex(where: {
            guard case .cardCarousel(let carousel) = $0 else { return false }
            return carousel.id == removal.carouselID
        }), case .cardCarousel(var carousel) = removal.home.blocks[blockIndex] {
            guard !carousel.cards.contains(where: { $0.conversation == removal.card.conversation })
            else { return }
            carousel.cards.insert(removal.card, at: min(removal.cardIndex, carousel.cards.count))
            withAnimation(.smooth(duration: 0.25)) {
                removal.home.blocks[blockIndex] = .cardCarousel(carousel)
            }
            return
        }

        withAnimation(.smooth(duration: 0.25)) {
            if let header = removal.header,
               !removal.home.blocks.contains(where: {
                   guard case .sectionHeader(let current) = $0 else { return false }
                   return current.id == header.id
               }) {
                removal.home.blocks.insert(
                    .sectionHeader(header),
                    at: min(removal.headerIndex ?? removal.carouselIndex, removal.home.blocks.count))
            }
            removal.home.blocks.insert(
                .cardCarousel(CardCarousel(id: removal.carouselID, cards: [removal.card])),
                at: min(removal.carouselIndex, removal.home.blocks.count))
        }
    }
}
