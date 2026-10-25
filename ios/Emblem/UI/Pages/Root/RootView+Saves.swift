import SwiftUI
import UIKit
import EmblemCore

extension RootView {
    var pendingVisibleSaveObserver: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: store.currentPage.map { hasVisibleSaveContent($0) }) { _, _ in fulfillPendingVisibleSave() }
            .onChange(of: store.currentPage?.id) { _, _ in
                if pendingVisibleSave?.page !== store.currentPage { pendingVisibleSave = nil }
            }
            .onChange(of: savedPages.scopeID) { _, _ in pendingVisibleSave = nil }
    }

    func pageIsSaved(_ page: GeneratedPage) -> Bool {
        savedPages.contains(page) ||
            (pendingVisibleSave?.page === page && pendingVisibleSave?.scope == savedPages.scopeID)
    }

    private func hasVisibleSaveContent(_ page: GeneratedPage) -> Bool {
        page.visibleBlocks.contains { block in
            switch block {
            case .unknown, .pageMeta: false
            case .text(let text):
                !["generation-error", "generation-cancelled"].contains(text.id) &&
                    !text.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            default: true
            }
        }
    }

    func saveVisiblePage(_ page: GeneratedPage) {
        guard !page.isHome,
              store.currentPage === page || store.pendingPresentationSourcePage === page else { return }
        let scope = savedPages.scopeID
        do {
            if pendingVisibleSave?.page === page {
                pendingVisibleSave = nil
            } else if savedPages.contains(page) {
                try savedPages.remove(page, expectedScope: scope)
            } else if hasVisibleSaveContent(page) {
                try retainCurrentSave(page, scope: scope)
                showSavedToast()
            } else {
                pendingVisibleSave = PendingVisibleSave(page: page, scope: scope)
            }
        } catch {
            pageSaveError = "The page couldn't be saved on this device. Try again."
        }
    }

    private func fulfillPendingVisibleSave() {
        guard let intent = pendingVisibleSave else { return }
        guard intent.scope == savedPages.scopeID, store.currentPage === intent.page else {
            pendingVisibleSave = nil
            return
        }
        guard hasVisibleSaveContent(intent.page) else { return }
        pendingVisibleSave = nil
        do {
            try retainCurrentSave(intent.page, scope: intent.scope)
            showSavedToast()
        } catch {
            pageSaveError = "The page couldn't be saved on this device. Try again."
        }
    }

    private func retainCurrentSave(_ page: GeneratedPage, scope: UUID) throws {
        if !page.isStreaming && !page.hasProvisionalPresentation {
            try savedPages.save(page, expectedScope: scope)
        } else {
            try savedPages.saveVisibleSnapshot(page, expectedScope: scope)
        }
    }

    var isSavedEntryRoot: Bool {
        savedEntry?.rootPageID == store.currentPage?.id && savedEntry != nil
    }

    func showSavedToast() {
        savedPages.requestOrganization()
        withAnimation(.smooth(duration: reduceMotion ? 0.15 : 0.35)) {
            saveToastID = UUID()
        }
        UIAccessibility.post(notification: .announcement, argument: "Added to Saves")
    }

    private func openSavedPage(_ saved: SavedPage, entity: SavedEntity? = nil) {
        guard !store.isGenerationActive else { return }
        mapPresentation = nil
        let page = saved.makePage()
        if let entity {
            guard saved.snapshot.selectionKey == entity.origin.selectionKey else { return }
            page.expansionSource = PageExpansionSource(parentPageID: entity.id,
                parentPageKey: entity.origin.parentPageKey, sourceCardKey: entity.origin.sourceCardKey,
                card: entity.card)
        }
        savedEntry = SavedEntry(scopeID: savedPages.scopeID,
                                originPageIDs: store.navigationPageIDs,
                                rootPageID: page.id, pageKey: saved.pageKey,
                                hasCover: saved.presentation.cover != nil || entity?.cover != nil, entityID: entity?.id)
        store.openSavedPage(page)
    }

    private func openSavedItem(_ item: SavedShelfEntry) {
        guard !store.isGenerationActive else { return }
        switch item {
        case .page(let page): openSavedPage(page)
        case .entity(let entity):
            let scope = savedPages.scopeID
            guard let current = savedPages.entities.first(where: { $0.id == entity.id }) else { return }
            if current.detail == nil {
                do {
                    if let retained = try savedPages.retainedPage(for: current.origin, expectedScope: scope) {
                        openSavedPage(retained, entity: current)
                        return
                    }
                } catch {
                    pageSaveError = "This saved item couldn't be opened. Try again."
                    return
                }
            }
            if let snapshot = current.detail {
                let page = SavedPage(snapshot: snapshot, savedAt: current.savedAt).makePage()
                page.expansionSource = PageExpansionSource(parentPageID: current.id,
                    parentPageKey: current.origin.parentPageKey, sourceCardKey: current.origin.sourceCardKey,
                    card: current.card)
                savedEntry = SavedEntry(scopeID: scope, originPageIDs: store.navigationPageIDs,
                    rootPageID: page.id, pageKey: page.pageKey, hasCover: current.cover != nil, entityID: current.id)
                store.openSavedPage(page)
            } else {
                generateSavedEntity(current.id, scope)
            }
        }
    }

    func generateSavedEntity(_ id: UUID, _ scope: UUID) {
        let origin = store.navigationPageIDs
        let hasCover = savedPages.entities.first(where: { $0.id == id })?.cover != nil
        guard let page = store.generateSavedEntity(id: id, expectedScope: scope) else {
            pageSaveError = "This saved item couldn't be opened. Try again."
            return
        }
        savedEntitySelection = nil
        savedEntry = SavedEntry(scopeID: scope, originPageIDs: origin, rootPageID: page.id,
            pageKey: page.pageKey, hasCover: hasCover, entityID: id)
    }

    func returnToSaves() {
        guard let entry = savedEntry else { return }
        guard entry.scopeID == savedPages.scopeID else {
            savedEntry = nil
            primaryDestination = nil
            primaryRoot = nil
            return
        }
        guard let page = store.currentPage, page.id == entry.rootPageID,
              store.returnFromSavedPage(page, to: entry.originPageIDs) else { return }
        savedEntry = nil
    }

    @ViewBuilder
    func primaryDestinationView(_ destination: PrimaryDestination) -> some View {
        Group {
            switch destination {
            case .calendar:
                if let calendarSelection {
                    CalendarBrowserView(selection: calendarSelection, onMenu: openSidebar,
                                        onSelect: { [selection = calendarSelection, scopeID = savedPages.scopeID] _ in
                        self.calendarSelection === selection && savedPages.scopeID == scopeID && calendarIsTopmost
                    }) { period in
                        calendarPeriodBody(period)
                    }
                    .overlay(alignment: .bottom) { calendarAccessory }
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationBarBackButtonHidden(true)
                }
            case .saves:
                SavedPagesView(onBack: openSidebar, onOpen: openSavedItem,
                               showsMenu: true, expansionNamespace: expansionNamespace)
            case .settings:
                SettingsView(
                    onBack: openSidebar, showsMenu: true,
                    onSubpagePushed: { settingsSubpagePushed = $0 },
                    onOpenAutomation: { id in
                        store.openAutomation(id: id)
                        primaryDestination = nil
                        primaryRoot = nil
                    },
                    onSignIn: {
                        primaryDestination = nil
                        primaryRoot = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showSignIn = true
                        }
                    })
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .scrollEdgeEffectHidden(for: .top)
    }
}
