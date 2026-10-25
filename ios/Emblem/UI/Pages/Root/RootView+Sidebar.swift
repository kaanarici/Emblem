import SwiftUI
import UIKit
import EmblemCore

extension RootView {
    var windowEdgeGestures: WindowEdgeGestures {
        WindowEdgeGestures(
            leftEnabled: {
                guard !store.isEditingWriting else { return false }
                guard !primaryIsTopmost else { return false }
                return mapIsTopmost || comparisonPresentation != nil || savedEntitySelection != nil || primaryDestination != nil
                    || (!isHomePage && store.canGoBack)
            },
            rightEnabled: {
                !(isHomePage && primaryDestination == nil && savedEntry == nil && savedEntitySelection == nil)
                    && !store.isEditingWriting && !primaryIsTopmost && !mapIsTopmost
                    && comparisonPresentation == nil && store.canGoForward
                    && (primaryDestination == nil || primaryDestination == .calendar || savedEntry != nil)
            },
            onLeft: {
                withAnimation(UIAccessibility.isReduceMotionEnabled
                              ? .easeOut(duration: 0.12) : .smooth(duration: 0.4)) {
                    if mapIsTopmost { mapPresentation = nil }
                    else if comparisonPresentation != nil { comparisonPresentation = nil }
                    else if savedEntitySelection != nil { savedEntitySelection = nil }
                    else if savedEntry != nil {
                        if isSavedEntryRoot { returnToSaves() } else { store.goBack() }
                    }
                    else if primaryDestination == .calendar {
                        if calendarIsTopmost { store.goBack(); primaryDestination = nil }
                        else { store.goBack() }
                    }
                    else if primaryDestination != nil { primaryDestination = nil }
                    else { store.goBack() }
                }
            },
            onRight: {
                guard !mapIsTopmost else { return }
                store.goForward()
            })
    }

    var isHomePage: Bool { store.currentPage?.isHome ?? true }

    var sidebarWidth: CGFloat { viewportWidth * 8 / 11 }

    var sidebarOffset: CGFloat {
        if showSidebar {
            return max(0, min(sidebarWidth, sidebarWidth + sidebarClosingTranslation))
        }
        return max(0, min(sidebarWidth, sidebarOpeningTranslation))
    }

    var sidebarProgress: CGFloat { sidebarOffset / max(1, sidebarWidth) }

    func closeSidebar() {
        withAnimation(sidebarAnimation(duration: 0.26)) {
            sidebarClosingTranslation = 0
            showSidebar = false
        }
    }

    func openFromSidebar(_ destination: PrimaryDestination) {
        mapPresentation = nil
        comparisonPresentation = nil
        savedEntitySelection = nil
        savedEntry = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            primaryDestination = nil
            primaryRoot = PrimaryRoot(destination: destination, homePageID: store.pages.first?.id,
                                      pageIDs: store.navigationPageIDs, scopeID: savedPages.scopeID)
        }
        closeSidebar()
    }

    func openSidebar() {
        guard speech.phase == .idle, store.dockState != .listening else { return }
        store.dockState = .idle
        withAnimation(sidebarAnimation(duration: 0.28)) { showSidebar = true }
    }

    func updateSidebarClosing(_ translation: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            sidebarClosingTranslation = max(-sidebarWidth, min(0, translation))
        }
    }

    func finishSidebarClosing(_ translation: CGFloat, _ velocity: CGFloat) {
        if translation < -70 || velocity < -420 {
            closeSidebar()
        } else {
            withAnimation(sidebarAnimation(duration: 0.22)) {
                sidebarClosingTranslation = 0
            }
        }
    }

    func updateSidebarOpening(_ translation: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            sidebarOpeningTranslation = max(0, min(sidebarWidth, translation))
        }
    }

    func finishSidebarOpening(_ translation: CGFloat, _ velocity: CGFloat) {
        let shouldOpen = translation > 70 || velocity > 420
        withAnimation(sidebarAnimation(duration: 0.28)) {
            showSidebar = shouldOpen
            sidebarOpeningTranslation = 0
        }
    }

    private func sidebarAnimation(duration: TimeInterval) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: duration, extraBounce: 0)
    }
}
