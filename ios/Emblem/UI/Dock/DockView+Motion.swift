import PhotosUI
import SwiftUI
import EmblemCore

extension DockView {
    var composerMotion: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.24)
    }

    var uploadTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.9)),
            removal: .opacity.combined(with: .scale(scale: 0.86)).combined(with: .offset(y: 6)))
    }

    var attachmentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.96, anchor: .bottom))
                .combined(with: .offset(y: 8)),
            removal: .opacity.combined(with: .offset(y: 5)))
    }

    func sideControlTransition(x: CGFloat) -> AnyTransition {
        reduceMotion ? .opacity : .offset(x: x).combined(with: .opacity)
    }

    var containerTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom))
    }

    var composerTransition: AnyTransition { .opacity }

    var dockControlsHidden: Bool {
        store.dockState == .keyboard || (composerPresented && !composerDismissing)
    }

    var sideControlsParked: Bool {
        if isEditingRecording { return dockControlsHidden }
        return dockControlsHidden || store.dockState == .listening ||
            store.isAwaitingFirstGenerationContent
    }

    var rightControlParked: Bool {
        if isEditingRecording { return dockControlsHidden }
        return dockControlsHidden ||
            store.isAwaitingFirstGenerationContent ||
            (store.dockState == .listening && speech.phase != .locked)
    }

    static let sideParkDistance = controlSize + 44

    var sideParkMotion: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.30, bounce: 0)
    }

    var slotSwapTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: SlotSwap(progress: 0), identity: SlotSwap(progress: 1))
                .animation(.smooth(duration: 0.24).delay(0.06)),
            removal: .modifier(active: SlotSwap(progress: 0), identity: SlotSwap(progress: 1))
                .animation(.easeOut(duration: 0.14)))
    }

    func syncEditorSlots() {
        let target = (left: isEditingRecording, right: speech.phase == .locked || isEditingRecording)
        guard target != showsEditorSlots else { return }
        guard (showsEditorSlots.left && !target.left) || (showsEditorSlots.right && !target.right) else {
            showsEditorSlots = target
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            if sideControlsParked || rightControlParked {
                try? await Task.sleep(for: .milliseconds(300))
            }
            showsEditorSlots = (left: isEditingRecording, right: speech.phase == .locked || isEditingRecording)
        }
    }

    var dockMorph: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : Self.pillMotion
    }

    var dockLayoutKey: DockLayoutKey {
        DockLayoutKey(
            showsStatus: displaysStatus,
            status: displaysStatus ? displayedStatus : "",
            trailingControl: displaysStatus ? nil : activeTrailingControl,
            hint: holdHint)
    }

    var micPressMotion: Animation {
        guard !reduceMotion else { return .easeOut(duration: 0.1) }
        return voicePressActive
            ? .spring(duration: 0.16, bounce: 0.04)
            : .spring(duration: 0.22, bounce: 0)
    }

    var micExpanded: Bool {
        voicePressActive && store.dockState == .listening && speech.phase == .held
    }
}
