import SwiftUI
import UIKit
import EmblemCore

extension RootView {
    var areaPageIsTopmost: Bool {
        store.currentPage?.presentedBlocks.contains {
            if case .questionList(let list) = $0 { list.inlineArea != nil } else { false }
        } ?? false
    }

    var keyboardLiftsDock: Bool {
        store.dockState == .keyboard || (KeyboardPresence.shared.isVisible && speech.phase == .editing)
    }

    func dismissComposerAfterPageTap() {
        guard store.dockState == .keyboard else { return }
        let pageID = store.currentPage?.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            guard store.dockState == .keyboard,
                  store.currentPage?.id == pageID,
                  comparisonPresentation == nil,
                  tablePresentation.activeID == nil,
                  !store.isViewingPhoto,
                  let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }),
                  let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController,
                  root.presentedViewController == nil
            else { return }
            store.dockState = .idle
        }
    }

    var dockOverlay: some View {
        VStack {
            Spacer()
            DockView(sidebarProgress: sidebarProgress, bottomInset: windowBottomInset,
                     accessibilitySuppressed: chromeSuppressed, onNewPage: {
                mapPresentation = nil
                savedEntry = nil
                savedEntitySelection = nil
                primaryDestination = nil
                primaryRoot = nil
                store.popToHome()
                closeSidebar()
            }, onSettings: {
                openFromSidebar(.settings)
            }, editingControls: recordingEditorControls,
               editingControlOwner: recordingEditorOwner)
        }
        .opacity(chromeSuppressed ? 0 : tablePresentation.opacity)
        .allowsHitTesting(!chromeSuppressed && tablePresentation.activeID == nil)
        .accessibilityHidden(chromeSuppressed)
        .animation(.easeOut(duration: 0.18), value: chromeSuppressed)
        .padding(.bottom, keyboardLiftsDock ? 8 : windowBottomInset)
        .background(alignment: .bottom) {
            ComposerBackdrop(fadesToPaper: !isHomePage)
                .frame(height: (keyboardLiftsDock ? 8 : windowBottomInset) + 56 + 24)
                .opacity(chromeSuppressed || mapIsTopmost || calendarIsTopmost || areaPageIsTopmost || eventDetailLoading
                    || isHoldingForGeneration || reveal != nil || store.activeQuestion != nil
                    ? 0 : tablePresentation.opacity * (1 - sidebarProgress))
                .animation(.easeOut(duration: 0.2), value: store.activeQuestion != nil)
                .animation(.easeOut(duration: 0.35), value: reveal == nil)
        }
        .animation(.spring(duration: 0.30, bounce: 0), value: keyboardLiftsDock)
        .task {
            windowBottomInset = Self.readWindowBottomInset()
            if windowBottomInset == 0 {
                try? await Task.sleep(for: .milliseconds(350))
                windowBottomInset = Self.readWindowBottomInset()
            }
        }
        .zIndex(40)
        .environment(\.performAction, performAction)
    }

    func synchronizeRecordingEditor(editing: Bool) {
        let token = editing ? UUID() : nil
        recordingEditorOwner = token
        recordingEditorControls.expect(owner: token)
    }
}
