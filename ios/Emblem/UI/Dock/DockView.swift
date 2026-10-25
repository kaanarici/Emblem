import PhotosUI
import SwiftUI
import EmblemCore

enum DockTrailingControl: Hashable {
    case retry
    case action(Action)

    var label: String {
        switch self {
        case .retry: "Retry"
        case .action(let action): action.label
        }
    }
}

enum DockStatusMetrics {
    static let textEdgePadding: CGFloat = 14
    static let controlSpacing: CGFloat = 1
    static let controlEdgePadding: CGFloat = 4.5
    static let stopHitSize: CGFloat = 40
    static let stopVisibleSize: CGFloat = 19
    static let stopGlyphSize: CGFloat = 22.0 / 3
}

struct DockLayoutKey: Equatable {
    let showsStatus: Bool
    let status: String
    let trailingControl: DockTrailingControl?
    let hint: Bool
}

enum VoiceFinalizationIntent {
    case edit
    case send
}

struct DockView: View {
    var sidebarProgress: CGFloat = 0
    var bottomInset: CGFloat = 34
    var accessibilitySuppressed = false
    var onNewPage: () -> Void = {}
    var onSettings: () -> Void = {}
    var editingControls: RecordingEditorControls? = nil
    var editingControlOwner: UUID? = nil

    @Environment(ConversationStore.self) var store
    @Environment(SpeechService.self) var speech
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accent) var accent
    @Environment(\.performAction) var performAction

    @State var holdStartedAt: Date?
    @State var lockPull: CGFloat = 0
    @State var holdHint = false
    @State var holdHintDelay: Double = 8
    @GestureState var voicePressActive = false
    @State var voiceStartTask: Task<Void, Never>?
    @State var voiceFinalizationTask: Task<Void, Never>?
    @State var missingAnswersNudges = 0
    @State var draft = ""
    @State var showsEditorSlots = (left: false, right: false)
    @State private var shownTrailing: DockTrailingControl?
    @State var composerPresented = false
    @State var composerDismissing = false
    @State private var composerKeyboardVisible = false
    @State var completionPulse: CGFloat = 0
    @State var displayedStatus = "Thinking…"
    @State var displaysStatus = false
    @Namespace private var attachmentMorph
    @FocusState private var draftFocused: Bool

    @State private var photoItems: [PhotosPickerItem] = []
    @State var showPhotoPicker = false
    @State var showCamera = false
    @State var showFileImporter = false

    static let keyboardCurve = Animation.spring(duration: 0.30, bounce: 0)
    private static let attachmentMotion = Animation.spring(duration: 0.26, bounce: 0)
    static let pillMotion = Animation.spring(duration: 0.30, bounce: 0.05)
    static let controlSize: CGFloat = 56
    static let capsuleInset: CGFloat = 4
    static let innerControlSize = controlSize - capsuleInset * 2
    static let sideInset: CGFloat = 18
    static let newPillWidth = newPageWidth + capsuleInset * 2
    private static let composerRadius: CGFloat = 22

    var body: some View {
        let acceptsInput = isEditingRecording || sidebarProgress > 0 || store.canStartNewResponse || store.dockShowsGenerationStop || store.isOpeningConversation
        dockBody
            .allowsHitTesting(acceptsInput)
            .accessibilityHidden(accessibilitySuppressed)
            .sensoryFeedback(trigger: speech.phase) { old, new in
                switch (old, new) {
                case (.idle, .held), (.editing, .locked): EmblemHaptic.listenStart
                case (.held, .locked): EmblemHaptic.listenLock
                default: nil
                }
            }
            .sensoryFeedback(EmblemHaptic.listenStop, trigger: voiceFinalizationTask != nil) { old, new in !old && new }
            .sensoryFeedback(EmblemHaptic.needsAnswer, trigger: missingAnswersNudges)
    }

    private var dockBody: some View {
        VStack(spacing: 0) {
            if !store.attachments.isEmpty && !dockControlsHidden {
                AttachmentStrip(
                    size: 48,
                    morphNamespace: attachmentMorph,
                    expanded: Binding(
                        get: { store.attachmentsExpanded },
                        set: { store.attachmentsExpanded = $0 }))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: store.dockState == .listening ? .leading : .center)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
                    .opacity((1 - sidebarProgress) * (store.attachmentsExpanded ? 0 : 1))
                    .allowsHitTesting(sidebarProgress == 0)
                    .accessibilityHidden(accessibilitySuppressed || sidebarProgress > 0)
                    .transition(attachmentTransition)
            } else if store.showsUploadingAttachment, let uploading = store.upload?.attachment {
                UploadingAttachmentChip(attachment: uploading)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
                    .opacity(1 - sidebarProgress)
                    .transition(uploadTransition)
            }

            ZStack(alignment: .bottom) {
                ZStack {
                    HStack(spacing: 12) {
                        Group {
                            if showsEditorSlots.left {
                                editorCancelButton.transition(slotSwapTransition)
                            } else {
                                plusButton.transition(slotSwapTransition)
                            }
                        }
                            .offset(x: reduceMotion ? 0 : (sideControlsParked ? -Self.sideParkDistance : 0))
                            .opacity(reduceMotion && sideControlsParked ? 0 : 1)
                            .allowsHitTesting(!sideControlsParked)
                            .opacity(dockControlsHidden ? 0 : 1)
                            .animation(.linear(duration: 0), value: dockControlsHidden)
                            .animation(sideParkMotion, value: sideControlsParked)
                            .transition(sideControlTransition(x: -14))
                            .zIndex(store.attachmentsExpanded ? 1 : 0)
                        Spacer(minLength: 0)
                        Group {
                            if showsEditorSlots.right {
                                voiceSendButton.transition(slotSwapTransition)
                            } else {
                                keyboardButton.transition(slotSwapTransition)
                            }
                        }
                        .offset(x: reduceMotion ? 0 : (rightControlParked ? Self.sideParkDistance : 0))
                        .opacity(reduceMotion && rightControlParked ? 0 : 1)
                        .allowsHitTesting(!rightControlParked && !store.attachmentsExpanded && sidebarProgress == 0)
                        .opacity(1 - sidebarProgress)
                        .accessibilityHidden(sidebarProgress > 0)
                        .opacity(dockControlsHidden ? 0 : 1)
                        .animation(.linear(duration: 0), value: dockControlsHidden)
                        .animation(sideParkMotion, value: rightControlParked)
                        .transition(sideControlTransition(x: 14))
                    }
                    .accessibilityHidden(accessibilitySuppressed)
                    .zIndex(store.attachmentsExpanded ? 2 : 0)
                    .onChange(of: speech.phase, initial: true) { syncEditorSlots() }

                    containerCapsule
                        .opacity(dockControlsHidden ? 0 : 1)
                        .scaleEffect(
                            reduceMotion ? 1 : dockControlsHidden ? 0.96 : 1,
                            anchor: .bottom)
                        .allowsHitTesting(!dockControlsHidden && !store.attachmentsExpanded)
                        .animation(dockControlsHidden ? .linear(duration: 0) : .easeOut(duration: 0.14), value: dockControlsHidden)
                        .transition(containerTransition)
                        .transaction { transaction in
                            if dockControlsHidden {
                                transaction.animation = nil
                                transaction.disablesAnimations = true
                            }
                        }
                }
                .padding(.horizontal, speech.phase == .idle ? Self.sideInset : 20)
            }
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { }
                    .allowsHitTesting(!accessibilitySuppressed && sidebarProgress == 0 &&
                        !composerPresented && !store.attachmentsExpanded)
            }
            .overlay(alignment: .bottom) {
                if composerPresented {
                    ComposerCard(
                        draft: $draft,
                        focus: $draftFocused,
                        attachmentMorph: attachmentMorph,
                        onPhotos: { showPhotoPicker = true },
                        onCamera: { showCamera = true },
                        onFiles: { showFileImporter = true },
                        onSend: sendDraft)
                        .glassEffect(.regular, in: .rect(cornerRadius: Self.composerRadius))
                        .contentShape(RoundedRectangle(
                            cornerRadius: Self.composerRadius,
                            style: .continuous))
                        .onTapGesture { draftFocused = true }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.bottom, store.dockState == .keyboard ? 0 : 16 - bottomInset)
                        .opacity(composerDismissing ? 0 : 1)
                        .animation(composerMotion, value: composerDismissing)
                        .transition(composerTransition)
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { value in
                                    if value.translation.height > 40 {
                                        store.dockState = .idle
                                    }
                                })
                }
            }
        }
        .animation(reduceMotion ? nil : Self.attachmentMotion, value: store.attachmentsExpanded)
        .animation(reduceMotion ? nil : Self.attachmentMotion, value: store.attachments)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: store.showsUploadingAttachment)
        .animation(Self.keyboardCurve, value: store.dockState)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })
            else { return }
            composerKeyboardVisible = frame.height > 0 && frame.minY < scene.screen.bounds.maxY - 1
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            guard store.dockState != .keyboard else { return }
            composerKeyboardVisible = false
            composerPresented = false
        }
        .onChange(of: store.dockState) { _, state in
            if state == .keyboard {
                store.attachmentsExpanded = false
                composerDismissing = false
                composerPresented = true
                Task { @MainActor in
                    await Task.yield()
                    guard store.dockState == .keyboard else { return }
                    draftFocused = true
                }
            } else if composerPresented {
                draftFocused = false
                withAnimation(composerMotion) {
                    composerDismissing = true
                    if !composerKeyboardVisible { composerPresented = false }
                }
            }
        }
        .onChange(of: store.attachments.isEmpty) { _, empty in
            if empty { store.attachmentsExpanded = false }
        }
        .onChange(of: store.completedGenerationID) { oldID, newID in
            guard let newID, newID != oldID else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { completionPulse = 0 }
            withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.28)) {
                completionPulse = 1
            }
        }

        .onDisappear {
            voiceStartTask?.cancel()
            endHoldIfNeeded()
        }
        .modifier(AttachmentInputs(
            photoItems: $photoItems,
            showPhotoPicker: $showPhotoPicker,
            showCamera: $showCamera,
            showFileImporter: $showFileImporter))
    }

    private var containerCapsule: some View {
        containerContent
            .padding(Self.capsuleInset)
            .background {
                if !micExpanded {
                    Capsule().fill(.clear)
                        .glassEffect(.regular, in: .capsule)
                }
            }
            .overlay {
                Capsule()
                    .stroke(Theme.ink.opacity(0.18), lineWidth: 1.25)
                    .scaleEffect(reduceMotion ? 1 : 0.99 + 0.15 * completionPulse)
                    .opacity(completionPulseOpacity)
                    .allowsHitTesting(false)
            }
            .geometryGroup()
    }

    @ViewBuilder
    var containerContent: some View {
        let thinking = !isEditingRecording && (store.dockShowsGenerationStop || store.isOpeningConversation)
        let trailingControl = displaysStatus ? nil : activeTrailingControl
        let shown = trailingControl ?? shownTrailing
        DockContentLayout(
            spacing: shown.map(pairSpacing) ?? 4,
            trailingProgress: trailingControl == nil ? 0 : 1,
            sidebarProgress: sidebarProgress
        ) {
            if let shown {
                trailingPill(shown)
                    .modifier(TrailingWipe(progress: trailingControl == nil ? 0 : 1, gap: pairSpacing(shown)))
                    .modifier(HiddenWhileSidebarOpens(progress: sidebarProgress))
                    .allowsHitTesting(trailingControl != nil && sidebarProgress == 0)
                    .accessibilityHidden(trailingControl == nil || accessibilitySuppressed || sidebarProgress > 0)
                    .transition(.modifier(
                        active: TrailingWipe(progress: 0, gap: pairSpacing(shown)),
                        identity: TrailingWipe(progress: 1, gap: pairSpacing(shown))))
            }
            darkPill(thinking: thinking, compact: trailingControl != nil, merging: trailingControl)
        }
        .animation(dockMorph, value: dockLayoutKey)
        .modifier(HoldHintScheduler(dock: self))
        .onChange(of: trailingControl) { _, control in
            if let control {
                shownTrailing = control
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    if displaysStatus || activeTrailingControl == nil { shownTrailing = nil }
                }
            }
        }
    }
}
