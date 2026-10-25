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

    private func changeConversation(
        key: String, change: ConversationHistory.Change, onFailure: (@MainActor () -> Void)?
    ) -> Bool {
        let history = self.history
        guard let edit = history.edit(key, change) else { return false }
        Task { [weak self] in
            switch await history.save(edit) {
            case .saved: self?.refreshHome()
            case .failed:
                history.discard(edit)
                onFailure?()
            case .superseded: break
            }
        }
        return true
    }

    private func removeConversation(
        key: String, change: ConversationHistory.Change, onFailure: (@MainActor () -> Void)?
    ) -> Bool {
        let history = self.history
        guard let edit = history.edit(key, change) else { return false }
        let removed = removeConversationCard(key: key)
        for run in generationRegistry.runs.values where run.page.conversationKey == key && run.session.isActive {
            cancelGeneration(run, navigatingAway: true)
        }
        if currentConversationKey == key {
            popToHome(refresh: false)
        }
        Task { [weak self] in
            switch await history.save(edit) {
            case .saved:
                guard let self else { return }
                for run in self.generationRegistry.runs.values where run.page.conversationKey == key {
                    run.session.clearRetryCandidate(conversationKey: key)
                }
                self.forwardPages.removeAll { $0.conversationKey == key }
            case .failed:
                history.discard(edit)
                if let removed { self?.restoreConversationCard(removed) }
                onFailure?()
            case .superseded: break
            }
        }
        return true
    }

    private func removeConversationCard(key: String) -> RemovedConversationCard? {
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
