import SwiftUI
import UIKit
import EmblemCore

extension RootView {
    var navigationPath: Binding<[RootRoute]> {
        Binding(get: {
            var routes = visiblePageIDs.map(RootRoute.page)
            if let primaryDestination {
                let insertion = savedEntry.flatMap { entry in
                    routes.firstIndex(of: .page(entry.rootPageID))
                } ?? routes.endIndex
                routes.insert(.primary(primaryDestination), at: insertion)
            }
            if let map = mapPresentation, store.pages.contains(where: { $0 === map.parent }) {
                if map.parent === store.pages.first || map.parent.id == primaryOriginPageIDs?.last {
                    routes.insert(.map(map.id), at: 0)
                } else if let anchor = routes.firstIndex(of: .page(map.parent.id)) {
                    routes.insert(.map(map.id), at: anchor + 1)
                }
            }
            if let savedEntitySelection { routes.append(.savedEntity(savedEntitySelection)) }
            if let comparisonPresentation { routes.append(.comparison(comparisonPresentation)) }
            return routes
        }, set: { routes in
            let pageIDs = (primaryOriginPageIDs ?? []) + routes.compactMap { route -> UUID? in
                if case .page(let id) = route { return id }
                return nil
            }
            primaryDestination = routes.compactMap { route -> PrimaryDestination? in
                if case .primary(let destination) = route { return destination }
                return nil
            }.last
            savedEntitySelection = routes.compactMap { route -> SavedEntitySelection? in
                if case .savedEntity(let selection) = route { return selection }
                return nil
            }.last
            comparisonPresentation = routes.compactMap { route -> ComparisonPresentation? in
                if case .comparison(let presentation) = route { return presentation }
                return nil
            }.last
            if let savedEntry, !pageIDs.contains(savedEntry.rootPageID) {
                self.savedEntry = nil
            }
            if let mapPresentation, !routes.contains(.map(mapPresentation.id)) {
                self.mapPresentation = nil
            }
            if pageIDs != store.navigationPageIDs { store.popNavigationPath(to: pageIDs) }
        })
    }

    var mapIsTopmost: Bool {
        guard let mapPresentation else { return false }
        return navigationPath.wrappedValue.last == .map(mapPresentation.id)
    }

    func handleMapPresentation(_ map: MapPresentation) {
        guard map.interaction.allowsActivation, store.currentPage === map.parent else { return }
        mapPresentation = map
    }

    private func expandedMapDestination(_ map: MapPresentation) -> some View {
        ExpandedMapView(session: map, close: { mapPresentation = nil })
            .environment(\.renderedPage, map.parent)
            .environment(\.blockInteraction, map.interaction)
            .environment(\.expansionNamespace, expansionNamespace)
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .modifier(ExpansionZoomTransition(
                sourceID: reduceMotion ? nil : map.mapTransitionID,
                namespace: expansionNamespace))
    }

    @ViewBuilder
    private func pushedPage(_ id: UUID) -> some View {
        if let page = store.pages.first(where: { $0.id == id }) {
            PageView(page: page, expansionNamespace: expansionNamespace)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .toolbar { pageToolbar(for: page) }
                .modifier(ExpansionZoomTransition(
                    sourceID: savedEntry?.rootPageID == page.id && savedEntry?.hasCover == true
                        ? savedEntry?.transitionID : page.expansionSource?.transitionID,
                    namespace: expansionNamespace))
                .scrollEdgeEffectHidden(for: .top)
        }
    }

    var pageNavigationStack: some View {
        NavigationStack(path: navigationPath) {
            ZStack {
                if let root = primaryRoot, primaryOriginPageIDs != nil {
                    primaryDestinationView(root.destination)
                } else {
                    Theme.background.ignoresSafeArea()
                    if store.currentPage?.isHome ?? true {
                        HomeWash().ignoresSafeArea().transition(.opacity)
                    }
                    if let home = store.pages.first {
                        PageView(page: home, expansionNamespace: expansionNamespace)
                            .id(home.id)
                    }
                }
            }
            .background(NavigationHeaderBackdrop(
                visible: !calendarIsTopmost && !isHoldingForGeneration && !store.isViewingPhoto && comparisonPresentation == nil
                    && !mapIsTopmost,
                faded: store.currentPage.map { $0.isExpansion && !$0.chromeUnderlap } ?? false,
                deep: headerEdgeIsDeep))
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .scrollEdgeEffectHidden(for: .top)
            .navigationTitle(primaryRoot?.destination == .saves ? "Saves" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if primaryOriginPageIDs == nil { pageToolbar(for: store.pages.first) }
            }
            .navigationDestination(for: RootRoute.self) { route in
                switch route {
                case .page(let id): pushedPage(id)
                case .primary(let destination): primaryDestinationView(destination)
                case .savedEntity(let selection):
                    SavedEntityDetailView(entityID: selection.id, scopeID: selection.scopeID,
                                          onClose: { savedEntitySelection = nil },
                                          onExplore: generateSavedEntity)
                case .map(let id):
                    if let map = mapPresentation, map.id == id {
                        expandedMapDestination(map)
                    }
                case .comparison(let comparison):
                    ExpandedComparison(presentation: comparison, dismiss: { comparisonPresentation = nil },
                                       usesNavigationToolbar: true)
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(.visible, for: .navigationBar)
                        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                        .navigationBarBackButtonHidden(true)
                        .modifier(ExpansionZoomTransition(
                            sourceID: reduceMotion ? nil : comparison.sourceID,
                            namespace: expansionNamespace))
                }
            }
        }
        .id(settingsRootActive)
    }
}
