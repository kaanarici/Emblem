import SwiftUI
import UIKit
import EmblemCore

@MainActor
enum PeerRootRuntimePrefix {
    static func resolve(
        capturedIDs: [UUID], homePageID: UUID?, capturedScope: UUID,
        pages: [GeneratedPage], navigationIDs: [UUID], currentScope: UUID
    ) -> [UUID]? {
        guard capturedScope == currentScope,
              homePageID == pages.first?.id,
              navigationIDs.count >= capturedIDs.count else { return nil }
        let currentPrefix = Array(navigationIDs.prefix(capturedIDs.count))
        for (captured, current) in zip(capturedIDs, currentPrefix) {
            guard let page = pages.first(where: { $0.id == current }),
                  page.id == captured || page.runtimeReplacementAncestors.contains(captured) else { return nil }
        }
        return currentPrefix
    }
}

struct RootView: View {
    @Environment(ConversationStore.self) var store
    @Environment(SpeechService.self) var speech
    @Environment(AuthStore.self) var auth
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State var recordingEditorControls = RecordingEditorControls()
    @State var recordingEditorOwner: UUID?
    private struct GenerationPresentationKey: Equatable {
        let runID: GenerationRunID?
        let isGenerating: Bool
    }

    @State var primaryDestination: PrimaryDestination?
    @State var primaryRoot: PrimaryRoot?

    struct PrimaryRoot {
        let destination: PrimaryDestination
        let homePageID: UUID?
        let pageIDs: [UUID]
        let scopeID: UUID
    }

    var primaryOriginPageIDs: [UUID]? {
        guard let root = primaryRoot,
              let currentPrefix = PeerRootRuntimePrefix.resolve(
                capturedIDs: root.pageIDs, homePageID: root.homePageID, capturedScope: root.scopeID,
                pages: store.pages, navigationIDs: store.navigationPageIDs,
                currentScope: savedPages.scopeID) else { return nil }
        if root.destination == .calendar {
            let calendarIDs = store.navigationPageIDs.dropFirst(root.pageIDs.count).prefix { id in
                store.pages.first(where: { $0.id == id })?.calendarContext != nil
            }
            guard !calendarIDs.isEmpty else { return nil }
            return currentPrefix + Array(calendarIDs)
        }
        return currentPrefix
    }

    var visiblePageIDs: [UUID] {
        Array(store.navigationPageIDs.dropFirst(primaryOriginPageIDs?.count ?? 0))
    }

    var primaryIsTopmost: Bool {
        primaryOriginPageIDs != nil && visiblePageIDs.isEmpty && primaryDestination == nil
            && savedEntitySelection == nil && comparisonPresentation == nil && mapPresentation == nil
    }

    private var savesIsTopmost: Bool {
        primaryIsTopmost && primaryRoot?.destination == .saves
    }

    private var settingsIsTopmost: Bool {
        primaryIsTopmost && primaryRoot?.destination == .settings
    }

    var settingsRootActive: Bool {
        primaryRoot?.destination == .settings && primaryOriginPageIDs != nil
    }
    @State var settingsSubpagePushed = false
    @State var calendarSelection: CalendarBrowserSelection?
    @State var savedEntry: SavedEntry?
    @State var savedEntitySelection: SavedEntitySelection?

    struct SavedEntitySelection: Hashable {
        let id: UUID
        let scopeID: UUID
    }

    struct SavedEntry {
        let scopeID: UUID
        let originPageIDs: [UUID]
        let rootPageID: UUID
        let pageKey: String
        let hasCover: Bool
        let entityID: UUID?

        var transitionID: String {
            entityID.map { "saved-entity-\($0.uuidString)" } ?? "saved-\(pageKey)"
        }
    }

    enum RootRoute: Hashable {
        case page(UUID)
        case primary(PrimaryDestination)
        case savedEntity(SavedEntitySelection)
        case comparison(ComparisonPresentation)
        case map(UUID)
    }
    @State var mapPresentation: MapPresentation?
    @State var comparisonPresentation: ComparisonPresentation?
    @State var tablePresentation = TablePresentationState()
    @State var showSignIn = false
    @State var showSidebar = false
    @State var sidebarOpeningTranslation: CGFloat = 0
    @State var sidebarClosingTranslation: CGFloat = 0
    @State var viewportWidth: CGFloat = 0
    struct Reveal {
        let start: Date
        let sourceImage: UIImage
        let epoch: Date?
        let origin: CGPoint?
    }
    @State var heldChromePage: GeneratedPage?
    @State var reveal: Reveal?
    @State var generationBackdrop: UIImage?
    @State var generationWaveEpoch: Date?
    @State var lastTouch = TouchOriginRecorder.LastTouch()
    @State var generationOrigin: CGPoint?
    @State var generationHoldDelay: TimeInterval = 0
    @State var lastListeningExit = Date.distantPast
    @State var lastKeyboardExit = Date.distantPast
    @State var renameCurrentConversation = false
    @State var currentConversationTitle = ""
    @State var directionsTarget: DirectionsTarget?
    @State var savedPages = SavedPagesStore.shared
    @State var pageSaveError: String?
    @State var saveToastID: UUID?
    @State var homeFailureToastID: UUID?
    @Namespace var toolbarGlassNamespace
    @State var pendingVisibleSave: PendingVisibleSave?

    struct PendingVisibleSave {
        let page: GeneratedPage
        let scope: UUID
    }

    @Namespace var expansionNamespace

    private var foregroundShape: AnyShape {
        if sidebarProgress > 0 {
            return AnyShape(RoundedRectangle(cornerRadius: displayCornerRadius, style: .continuous))
        }
        return AnyShape(Rectangle().inset(by: -1000))
    }

    var headerEdgeIsDeep: Bool {
        switch navigationPath.wrappedValue.last {
        case .page?: true
        case nil: primaryRoot == nil
        default: false
        }
    }

    var isHoldingForGeneration: Bool {
        store.isAwaitingFirstGenerationContent
            && !store.isExpansionGeneration
            && !store.isCalendarGeneration
    }

    @State var windowBottomInset: CGFloat = 0
    @State private var windowTopInset: CGFloat = 0
    @State private var displayCornerRadius: CGFloat = 0

    static func readWindowBottomInset() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes.first?.windows.first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        return window?.safeAreaInsets.bottom ?? 0
    }

    private var windowHeight: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first?.windows.first(where: \.isKeyWindow) ?? scenes.first?.windows.first)?.bounds.height ?? 956
    }

    enum PrimaryDestination: Hashable {
        case calendar
        case saves
        case settings
    }

    var chromeSuppressed: Bool {
        (primaryDestination != nil && primaryDestination != .saves && primaryDestination != .calendar)
            || primaryRoot?.destination == .settings
            || savedEntitySelection != nil
            || store.isViewingPhoto || (mapIsTopmost && mapPresentation?.isCardVisible == true)
    }

    private var pageSaveErrorPresented: Binding<Bool> {
        Binding<Bool>(
            get: { pageSaveError != nil },
            set: { (isPresented: Bool) in
                if !isPresented { pageSaveError = nil }
            })
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
            HomeSidebar(
                topInset: windowTopInset,
                bottomInset: windowBottomInset,
                isVisible: sidebarProgress > 0,
                isHomeSelected: primaryOriginPageIDs == nil && primaryDestination == nil && isHomePage,
                selectedConversationKey: primaryOriginPageIDs == nil && primaryDestination == nil ? store.currentConversationKey : nil,
                onHome: {
                    mapPresentation = nil
                    savedEntry = nil
                    savedEntitySelection = nil
                    primaryDestination = nil
                    primaryRoot = nil
                    store.popToHome()
                    closeSidebar()
                },
                onConversation: { key in
                    mapPresentation = nil
                    savedEntry = nil
                    savedEntitySelection = nil
                    primaryDestination = nil
                    primaryRoot = nil
                    closeSidebar()
                    if store.currentConversationKey != key {
                        store.restoreConversation(key: key)
                    }
                },
                onSaves: {
                    openFromSidebar(.saves)
                },
                onSettings: {
                    openFromSidebar(.settings)
                },
                isSavesSelected: savesIsTopmost,
                isSettingsSelected: settingsIsTopmost,
                isCalendarSelected: calendarIsTopmost,
                onCalendar: openCalendar)
                .frame(width: sidebarWidth)
                .clipped()
                .allowsHitTesting(sidebarProgress > 0.4)
                .accessibilityHidden(sidebarProgress == 0)
                .offset(x: reduceMotion ? 0 : -12 * (1 - sidebarProgress))
                .opacity(0.28 + 0.72 * sidebarProgress)

            if store.isViewingPhoto {
                Color.black.ignoresSafeArea().allowsHitTesting(false)
            }

            ZStack {
                pageNavigationStack
                .ignoresSafeArea(.keyboard, edges: store.dockState == .keyboard ? .bottom : [])
                .simultaneousGesture(TapGesture().onEnded {
                    dismissComposerAfterPageTap()
                })

                if !store.isExpansionGeneration && !store.isCalendarGeneration {
                    GenerationOverlay(
                        thinking: isHoldingForGeneration,
                        holdDelay: generationHoldDelay,
                        origin: reveal?.origin ?? generationOrigin,
                        sourceImage: reveal?.sourceImage ?? generationBackdrop,
                        epoch: reveal?.epoch ?? generationWaveEpoch,
                        revealStart: reveal?.start)
                        .transition(.identity)
                }

                AutomationRestoreNotice()
                    .zIndex(9)

                persistentResponseChrome(topInset: windowTopInset)
                    .zIndex(15)

                QuestionSheetHost(bottomInset: windowBottomInset)
                    .zIndex(20)

                if saveToastID != nil {
                    VStack {
                        Spacer()
                        SavedItemToast()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 79 + windowBottomInset)
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                    .zIndex(41)
                    .allowsHitTesting(false)
                }

                if homeFailureToastID != nil, saveToastID == nil, store.currentPage?.isHome == true {
                    VStack {
                        Spacer()
                        HomeRefreshToast {
                            withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.27)) {
                                homeFailureToastID = nil
                            }
                            store.refreshHome()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 79 + windowBottomInset)
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                    .zIndex(41)
                }

                if store.attachmentsExpanded, !chromeSuppressed {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.42, bounce: 0.12)) {
                                store.attachmentsExpanded = false
                            }
                        }
                        .zIndex(8)
                }

                ListeningTint(listening: store.dockState == .listening,
                              isHolding: { isHoldingForGeneration })
                    .zIndex(29)

                ListeningOverlay(active: store.dockState == .listening,
                                 editingControls: recordingEditorControls,
                                 editingControlOwner: recordingEditorOwner)
                    .zIndex(30)
            }
            .background(Theme.background, ignoresSafeAreaEdges: .all)
            .background(TouchOriginRecorder(lastTouch: lastTouch))
            .background(ResponseWindowSafeArea(
                updateTop: { inset in
                    if windowTopInset != inset { windowTopInset = inset }
                },
                updateCornerRadius: { displayCornerRadius = $0 }))
            .scrollDisabled(sidebarProgress > 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
            .overlay {
                ZStack {
                    Theme.background
                        .opacity(0.55 * sidebarProgress)
                        .allowsHitTesting(false)
                    if showSidebar {
                        SidebarDismissSurface(
                            onTap: closeSidebar,
                            onPanChanged: updateSidebarClosing,
                            onPanEnded: finishSidebarClosing)
                    }
                }
            }
            .clipShape(foregroundShape)
            .offset(x: sidebarOffset)
            .shadow(color: .black.opacity(0.12 * sidebarProgress), radius: 22, x: -3)
            .sensoryFeedback(trigger: speech.phase) { old, new in
                switch (old, new) {
                case (.idle, .held): .impact(flexibility: .soft, intensity: 0.8)
                case (.held, .locked): .impact(weight: .medium)
                default: nil
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: store.isGenerating) { old, new in !old && new }
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: store.pages.count) { old, new in
                new > old
            }
            .sensoryFeedback(.error, trigger: store.failureCount)
            .sensoryFeedback(.selection, trigger: showSidebar)
            .gesture(SidebarOpeningPanGesture(
                isEnabled: !mapIsTopmost && primaryDestination == nil && !(settingsIsTopmost && settingsSubpagePushed) && (primaryIsTopmost || (primaryRoot == nil && isHomePage)) && !showSidebar && store.dockState == .idle && speech.phase == .idle,
                onChanged: updateSidebarOpening,
                onEnded: finishSidebarOpening))
            .background(windowEdgeGestures)
            .environment(\.performAction, performAction)
            .environment(\.presentComparison, { comparisonPresentation = $0 })
            .environment(\.presentExpandedMap, handleMapPresentation)
            .environment(\.tablePresentation, tablePresentation)
            .environment(\.savedItemDidSave, { _ in showSavedToast() })
            .environment(\.responseRevealTiming, reveal.map {
                ResponseRevealTiming(start: $0.start, viewportHeight: windowHeight)
            })
            .onChange(of: geometry.size.width, initial: true) { _, width in
                viewportWidth = width
            }
            .alert("Rename Conversation", isPresented: $renameCurrentConversation) {
                TextField("Title", text: $currentConversationTitle)
                Button("Cancel", role: .cancel) {}
                Button("OK") {
                    let title = currentConversationTitle
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty {
                        store.renameCurrentConversation(title)
                    }
                }
            }
            .background(pendingVisibleSaveObserver)
            .task { await prepareLaunch() }
            .task(id: saveToastID) {
                guard let id = saveToastID else { return }
                do { try await Task.sleep(for: .milliseconds(2500)) }
                catch { return }
                guard saveToastID == id else { return }
                withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.27)) {
                    saveToastID = nil
                }
            }
            .onChange(of: store.responseWaveID) { _, id in
            guard id != nil, store.pages.count >= 2, !store.isExpansionGeneration,
                  !store.isCalendarGeneration else { return }
            guard let sourceImage = generationBackdrop else {
                heldChromePage = nil
                return
            }
            let now = Date()
            let start = max(now.addingTimeInterval(Self.dockLeadBeforeFront),
                            (generationWaveEpoch ?? now).addingTimeInterval(Self.minimumHold))
            reveal = Reveal(
                start: start,
                sourceImage: sourceImage,
                epoch: generationWaveEpoch,
                origin: generationOrigin)
            let delay = start.timeIntervalSince(now)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard reveal?.start == start else { return }
                withAnimation(.smooth(duration: 0.3)) { heldChromePage = nil }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + ResponseRevealTiming.duration + 0.15) {
                if reveal?.start == start {
                    reveal = nil
                    heldChromePage = nil
                    if !store.isGenerating { generationBackdrop = nil }
                    rearmBackdropAfterQuiet(delayMilliseconds: 300)
                }
            }
            }
            .onChange(of: speech.phase == .editing && store.dockState == .listening, initial: true) { _, editing in
                synchronizeRecordingEditor(editing: editing)
            }
            .onAppear {
                if speech.phase == .editing && store.dockState == .listening && recordingEditorOwner == nil {
                    synchronizeRecordingEditor(editing: true)
                }
            }
            .onDisappear { synchronizeRecordingEditor(editing: false) }
            .onChange(of: store.dockState) { old, state in
                handleDockStateChange(old: old, state: state)
            }
            .onChange(of: store.currentPage?.id) { _, _ in
                tablePresentation.reset()
                comparisonPresentation = nil
                if primaryRoot != nil, primaryOriginPageIDs == nil { primaryRoot = nil }
                if let savedEntry, !store.navigationPageIDs.contains(savedEntry.rootPageID) {
                    self.savedEntry = nil
                }
                rearmBackdropAfterQuiet(delayMilliseconds: 600)
            }
            .onChange(of: store.pages.map { ObjectIdentifier($0) }) { _, _ in
                if let mapPresentation, !store.pages.contains(where: { $0 === mapPresentation.parent }) {
                    self.mapPresentation = nil
                }
            }
            .onChange(of: store.conversationLoadState) { _, state in
                if case .loading = state { mapPresentation = nil }
            }
            .onChange(of: store.homeLoadState) { _, state in
                withAnimation(.smooth(duration: reduceMotion ? 0.15 : 0.35)) {
                    homeFailureToastID = state == .failed ? UUID() : nil
                }
                guard state != .loading else { return }
                rearmBackdropAfterQuiet(delayMilliseconds: 700)
            }
            .onChange(of: store.currentPage?.isStreaming ?? false) { _, streaming in
                guard !streaming else { return }
                rearmBackdropAfterQuiet(delayMilliseconds: 700)
            }
            .onChange(of: GenerationPresentationKey(
                runID: store.visibleGenerationID, isGenerating: store.isGenerating)) { _, state in
                handleGenerationChange(isGenerating: state.isGenerating)
            }
            .fullScreenCover(isPresented: $showSignIn) {
                AuthFlowView(presentedFromApp: true, onFinished: { showSignIn = false })
            }
            .sheet(item: $directionsTarget) { destination in
                DirectionsChooser(destination: destination)
                    .presentationDetents([.height(260)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(32)
            }
            .onChange(of: auth.user?.id, initial: true) { _, ownerID in
                mapPresentation = nil
                comparisonPresentation = nil
                primaryDestination = nil
                primaryRoot = nil
                savedEntry = nil
                savedEntitySelection = nil
                directionsTarget = nil
                renameCurrentConversation = false
                currentConversationTitle = ""
                saveToastID = nil
                showSidebar = false
                reveal = nil
                heldChromePage = nil
                generationBackdrop = nil
                generationWaveEpoch = nil
                store.greetingName = auth.greetingName
                calendarSelection = nil
                store.updateIdentity(ownerID)
                do {
                    try savedPages.switchOwner(to: ownerID)
                }
                catch { pageSaveError = "Saved pages couldn't be opened. Try again." }
            }
            .alert("Couldn't save page", isPresented: pageSaveErrorPresented) {
                Button("OK", role: .cancel) { pageSaveError = nil }
            } message: {
                Text(pageSaveError ?? "Try again.")
            }

            dockOverlay
            }
            .background(Theme.sidebarBackground, ignoresSafeAreaEdges: .all)
        }
    }
}
