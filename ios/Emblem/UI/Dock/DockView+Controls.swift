import PhotosUI
import SwiftUI
import EmblemCore

extension DockView {
    private var activeDockAction: Action? {
        guard !(store.currentPage?.isHome ?? true) else { return nil }
        guard let action = store.dockAction else { return nil }
        if let calendar = action.calendar,
           CalendarService.receiptStatus(for: calendar.idempotencyKey) != .none {
            return nil
        }
        guard action.prompt != nil ||
                action.url != nil ||
                action.conversation != nil ||
                action.openAutomation != nil ||
                action.automation?.idempotencyKey?.isEmpty == false ||
                action.calendar != nil ||
                (action.native == "directions" && action.destination != nil)
        else { return nil }
        return action
    }

    var activeTrailingControl: DockTrailingControl? {
        guard !store.isVisibleGenerationActive, store.dockState != .listening else { return nil }
        if store.canRetryCurrentGeneration { return .retry }
        return activeDockAction.map(DockTrailingControl.action)
    }

    var plusButton: some View {
        Color.clear
            .frame(width: 44, height: 44)
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .bottomLeading) {
                    Button {
                        if sidebarOpen { onSettings() } else { store.attachmentsExpanded = true }
                    } label: { plusLabel }
                        .buttonStyle(.plain)
                        .opacity(store.attachmentsExpanded ? 0 : 1)
                        .animation(
                            store.attachmentsExpanded || reduceMotion
                                ? .linear(duration: 0) : .easeOut(duration: 0.1).delay(0.17),
                            value: store.attachmentsExpanded)
                        .allowsHitTesting(!store.attachmentsExpanded)
                        .accessibilityHidden(store.attachmentsExpanded)
                        .accessibilityLabel(sidebarOpen ? "Settings" : "Add attachments")
                        .accessibilityIdentifier(sidebarOpen ? "sidebar-settings" : "dock-attachments")
                    if store.attachmentsExpanded {
                        AttachmentMenuPanel(
                            onPhotos: { openAttachmentPicker { showPhotoPicker = true } },
                            onCamera: { openAttachmentPicker { showCamera = true } },
                            onFiles: { openAttachmentPicker { showFileImporter = true } })
                            .transition(.opacity)
                    }
                }
                .frame(
                    width: store.attachmentsExpanded ? AttachmentMenuPanel.width(for: store.attachments.count) : 44,
                    height: store.attachmentsExpanded ? AttachmentMenuPanel.height(for: store.attachments.count) : 44,
                    alignment: .bottomLeading)
                .clipShape(.rect(cornerRadius: store.attachmentsExpanded ? 32 : 22))
                .glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: store.attachmentsExpanded ? 32 : 22))
                .offset(
                    x: store.attachmentsExpanded ? -2 : 0,
                    y: store.attachmentsExpanded ? -4 : 0)
            }
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
        .accessibilityHidden(accessibilitySuppressed)
    }

    var sidebarOpen: Bool { sidebarProgress > 0.5 }

    private var plusLabel: some View {
        ZStack {
            ChromeGlyph(symbol: .add, size: 28)
                .opacity(1 - sidebarProgress)
                .rotationEffect(.degrees(90 * sidebarProgress))
            Image(systemName: "gearshape")
                .font(.system(size: 20, weight: .regular))
                .opacity(sidebarProgress)
                .rotationEffect(.degrees(-90 * (1 - sidebarProgress)))
        }
        .foregroundStyle(Color.primary)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }

    private func openAttachmentPicker(_ action: @escaping () -> Void) {
        store.attachmentsExpanded = false
        action()
    }

    func sendDraft() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty || !store.attachments.isEmpty else { return }
        if !prompt.isEmpty, store.activeQuestion?.input?.kind == .area {
            store.questionDraft = prompt
            store.confirmQuestion()
            draft = ""
            return
        }
        if store.send(prompt) { draft = "" }
    }

    var isEditingRecording: Bool { speech.phase == .editing }

    var editorControlsReady: Bool {
        guard let editingControlOwner, let editingControls else { return false }
        return editingControls.owner == editingControlOwner && editingControls.isReady
    }

    func dispatchEditor(_ action: RecordingEditorControls.Action) {
        guard isEditingRecording, let editingControls, let editingControlOwner else { return }
        editingControls.dispatch(action, owner: editingControlOwner)
    }

    var editorCancelButton: some View {
        Button { dispatchEditor(.cancel) } label: {
            CloseGlyph()
                .foregroundStyle(Color.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
        .disabled(!editorControlsReady)
        .accessibilityLabel("Cancel recording")
        .accessibilityIdentifier("voice-cancel")
        .accessibilityHidden(accessibilitySuppressed)
    }

    var voiceSendButton: some View {
        let ready = isEditingRecording || !speech.overlayText.isEmpty
        let swap: AnyTransition = reduceMotion
            ? .opacity
            : .modifier(active: SlotSwap(progress: 0), identity: SlotSwap(progress: 1))
        return Button {
            if isEditingRecording { dispatchEditor(.send) }
            else if ready { sendVoiceNow() }
            else { typeInstead() }
        } label: {
            ZStack {
                AnodizedSurface(shape: Circle())
                    .opacity(ready ? 1 : 0)
                if ready {
                    ChromeGlyph(symbol: .arrowUp, size: 28)
                        .foregroundStyle(accent.glyph)
                        .transition(swap)
                } else {
                    KeyboardGlyph()
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                        .transition(swap)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.3), value: ready)
        }
        .buttonStyle(.plain)
        .disabled(isEditingRecording && !editorControlsReady)
        .glassEffect(.regular.interactive(), in: .circle)
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
        .accessibilityLabel(ready ? "Send recording" : "Type instead")
        .accessibilityIdentifier(ready ? "voice-send" : "voice-type-instead")
        .accessibilityHidden(accessibilitySuppressed)
    }

    private func typeInstead() {
        voiceStartTask?.cancel()
        voiceStartTask = nil
        holdStartedAt = nil
        Task { _ = await speech.finish() }
        speech.prepareForFreshSegment()
        speech.draft = ""
        speech.phase = .idle
        store.dockState = .keyboard
    }

    func stopVoiceSegment() {
        beginVoiceFinalization(.edit)
    }

    private func sendVoiceNow() {
        beginVoiceFinalization(.send)
    }

    var keyboardButton: some View {
        Button {
            speech.captureListeningBackdrop()
            store.dockState = .keyboard
        } label: {
            KeyboardGlyph()
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
        .accessibilityLabel("Keyboard")
        .accessibilityIdentifier("dock-keyboard")
        .accessibilityHidden(accessibilitySuppressed)
    }
}
