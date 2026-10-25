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
                    Button { store.attachmentsExpanded = true } label: { plusLabel }
                        .buttonStyle(.plain)
                        .opacity(store.attachmentsExpanded ? 0 : 1)
                        .animation(
                            store.attachmentsExpanded || reduceMotion
                                ? .linear(duration: 0) : .easeOut(duration: 0.1).delay(0.17),
                            value: store.attachmentsExpanded)
                        .allowsHitTesting(!store.attachmentsExpanded)
                        .accessibilityHidden(store.attachmentsExpanded)
                        .accessibilityLabel("Add attachments")
                        .accessibilityIdentifier("dock-attachments")
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

    private var plusLabel: some View {
        ChromeGlyph(symbol: .add, size: 28)
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
        Button {
            if isEditingRecording { dispatchEditor(.send) }
            else { sendVoiceNow() }
        } label: {
            ChromeGlyph(symbol: .arrowUp, size: 28)
                .foregroundStyle(Color.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isEditingRecording && !editorControlsReady)
        .glassEffect(.regular.interactive(), in: .circle)
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
        .accessibilityLabel("Send recording")
        .accessibilityIdentifier("voice-send")
        .accessibilityHidden(accessibilitySuppressed)
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
