import SwiftUI
import UIKit
import EmblemCore

extension RootView {
    @ToolbarContentBuilder
    func pageToolbar(for page: GeneratedPage?) -> some ToolbarContent {
        if savedEntitySelection == nil,
           page != nil && savedEntry?.rootPageID == page?.id {
            responsePageToolbar(for: page)
        } else if page != nil, savedEntitySelection == nil {
            ToolbarItem(placement: .principal) {
                Color.clear.frame(width: 1, height: 44)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func ownsSavedEntryAction(_ page: GeneratedPage, _ entry: SavedEntry) -> Bool {
        guard entry.scopeID == savedPages.scopeID,
              savedEntry?.rootPageID == entry.rootPageID,
              store.currentPage === page,
              entry.rootPageID == page.id,
              entry.pageKey == page.pageKey else { return false }
        return savedPages.permitsLocalAction(on: page, entityID: entry.entityID, expectedScope: entry.scopeID)
    }

    @ToolbarContentBuilder
    private func responsePageToolbar(for page: GeneratedPage?) -> some ToolbarContent {
        let isSavedEntryRoot = page != nil && savedEntry?.rootPageID == page?.id
        let isTopLevelPage = page?.isExpansion != true
        if isSavedEntryRoot {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: returnToSaves) {
                    CloseGlyph()
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close saved page")
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                if let page, let entry = savedEntry {
                    HStack(spacing: 0) {
                        ShareLink(item: page.visibleContextSummary) {
                            ChromeGlyph(symbol: .share)
                                .offset(x: -2)
                                .frame(width: 50, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Share saved page")
                        .disabled(!ownsSavedEntryAction(page, entry))
                        Button {
                            guard ownsSavedEntryAction(page, entry) else { return }
                            do {
                                if let entityID = entry.entityID {
                                    try savedPages.removeEntity(id: entityID, expectedScope: entry.scopeID)
                                } else {
                                    try savedPages.remove(pageKey: entry.pageKey, expectedScope: entry.scopeID)
                                }
                                returnToSaves()
                            } catch {
                                pageSaveError = "The saved page couldn't be removed. Try again."
                            }
                        } label: {
                            SavedPageTrashGlyph()
                                .offset(x: 2)
                                .frame(width: 50, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Remove saved page")
                        .accessibilityIdentifier("saved-page-remove")
                        .disabled(!ownsSavedEntryAction(page, entry))
                    }
                    .foregroundStyle(.primary)
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) {
                responseNavigationGroup(isExpansion: !isTopLevelPage)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private var chromePresentationPage: GeneratedPage? {
        if let heldChromePage, store.pages.contains(where: { $0 === heldChromePage }) {
            return heldChromePage
        }
        return store.pendingPresentationSourcePage ?? store.currentPage
    }

    private var sharedResponseChromePage: GeneratedPage? {
        if let origin = primaryOriginPageIDs,
           let source = store.pendingPresentationSourcePage,
           source.id == (origin.last ?? store.pages.first?.id) { return nil }
        guard let page = chromePresentationPage, !primaryIsTopmost, !isSavedEntryRoot,
              savedEntry?.rootPageID != page.id,
              savedEntitySelection == nil, comparisonPresentation == nil,
              !(mapIsTopmost && mapPresentation?.block.thin != true),
              !store.isViewingPhoto,
              !calendarIsTopmost,
              primaryDestination == nil || savedEntry != nil else { return nil }
        return page
    }

    @ViewBuilder
    func persistentResponseChrome(topInset: CGFloat) -> some View {
        if let page = sharedResponseChromePage {
            VStack {
                HStack(spacing: 12) {
                    responseNavigationGroup(isExpansion: page.isExpansion, isHome: page.isHome)
                    Spacer(minLength: 12)
                    if page.isHome {
                        homeActions
                    } else {
                        responseActions(for: page)
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, 20)
                Spacer(minLength: 0)
            }
            .padding(.top, topInset)
        }
    }

    private var homeActions: some View {
        HStack(spacing: 0) {
            Button { openFromSidebar(.saves) } label: {
                ChromeGlyph(symbol: .allBookmark)
                    .frame(width: 50, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Saves")
            .accessibilityIdentifier("home-saves")
            Button(action: openCalendar) {
                ChromeGlyph(symbol: .calendarOutline)
                    .frame(width: 50, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Calendar")
            .accessibilityIdentifier("home-calendar")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func responseActions(for page: GeneratedPage) -> some View {
                HStack(spacing: 0) {
                    ShareLink(item: page.visibleContextSummary) {
                        ChromeGlyph(symbol: .share)
                            .offset(x: -2)
                            .frame(width: 50, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Share page")
                    Button {
                        saveVisiblePage(page)
                    } label: {
                        Group {
                            if pageIsSaved(page) {
                                ChromeGlyph(symbol: .bookmark, size: 24, filled: true)
                            } else {
                                ChromeGlyph(symbol: .bookmark, size: 24)
                            }
                        }
                        .offset(x: 2)
                        .frame(width: 50, height: 44)
                        .contentShape(Rectangle())
                        .foregroundStyle(.primary)
                    }
                    .sensoryFeedback(trigger: pageSaveTaps) { _, _ in
                        pageIsSaved(page) ? EmblemHaptic.saved : EmblemHaptic.removed
                    }
                    .accessibilityLabel(pageIsSaved(page) ? "Remove saved page" : "Save page")
                    .accessibilityIdentifier("page-save")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .glassEffect(.regular.interactive(), in: .capsule)
                .contextMenu {
                    if store.blockInteraction(for: page).allowsStoreMutation {
                        conversationOptions(for: page)
                    }
                }    }

    private func leaveMap() {
        if mapIsTopmost { mapPresentation = nil }
    }

    private func responseNavigationGroup(isExpansion: Bool, isHome: Bool = false) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    if isExpansion { leaveMap(); store.goBack() } else { openSidebar() }
                } label: {
                    ResponseNavigationMark(progress: isExpansion ? 1 : 0)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .frame(width: 24, height: 24)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .accessibilityLabel(isExpansion ? "Close" : "Open menu")
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("primary-navigation", in: toolbarGlassNamespace)
                if !isHome && (!isExpansion || store.canGoForward) {
                    HStack(spacing: 0) {
                        historyButton(.chevronLeft, label: "Back", id: "conversation-back", width: isExpansion ? 0 : 50,
                                      enabled: !isExpansion && store.canGoBack, shown: !isExpansion) {
                            leaveMap(); store.goBack()
                        }
                        .glassEffectID("history-back", in: toolbarGlassNamespace)
                        .glassEffectUnion(id: "history", namespace: toolbarGlassNamespace)
                        historyButton(.chevronRight, label: "Forward", id: "conversation-forward", width: isExpansion ? 44 : 50,
                                      enabled: store.canGoForward, shown: true) {
                            leaveMap(); store.goForward()
                        }
                        .glassEffectID("history-forward", in: toolbarGlassNamespace)
                        .glassEffectUnion(id: "history", namespace: toolbarGlassNamespace)
                    }
                }
            }
            .foregroundStyle(.primary)
            .buttonStyle(.plain)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.30), value: isExpansion)
        .animation(reduceMotion ? nil : .smooth(duration: 0.30), value: isHome)
        .animation(reduceMotion ? nil : .smooth(duration: 0.30), value: store.canGoForward)
    }

    private func historyButton(_ symbol: ChromeGlyph.Symbol, label: String, id: String, width: CGFloat,
                               enabled: Bool, shown: Bool,
                               action: @escaping () -> Void) -> some View {
        ZStack(alignment: .leading) {
            if shown {
                Button(action: action) {
                    ChromeGlyph(symbol: symbol)
                        .offset(x: width < 50 ? 0 : symbol == .chevronLeft ? -2 : 2)
                        .opacity(enabled ? 1 : 0.6)
                        .frame(width: max(width, 44), height: 44)
                        .frame(width: width, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .disabled(!enabled)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
                .transition(.asymmetric(insertion: .opacity.animation(.smooth(duration: 0.18).delay(0.12)),
                                        removal: .opacity.animation(.smooth(duration: 0.12))))
            }
        }
        .frame(width: width, height: 44)
        .clipped()
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    @ViewBuilder
    private func conversationOptions(for page: GeneratedPage) -> some View {
        if !page.isHome, !page.isExpansion, let key = page.conversationKey {
                    Button {
                        currentConversationTitle = page.meta?.title ?? ""
                        renameCurrentConversation = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        if store.archiveConversation(key: key) {
                            store.popToHome(refresh: false)
                        }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    Button(role: .destructive) {
                        if store.deleteConversation(key: key) {
                            store.popToHome(refresh: false)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
        }
    }
}
