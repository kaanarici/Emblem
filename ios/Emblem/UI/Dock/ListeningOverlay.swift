import Observation
import SwiftUI
import UIKit

struct ListeningOverlay: View {
    let active: Bool
    var editingControls: RecordingEditorControls? = nil
    var editingControlOwner: UUID? = nil
    @Environment(SpeechService.self) private var speech
    @Environment(ConversationStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let minimumTranscriptHeight: CGFloat = 132

    @State private var transcriptHeight: CGFloat = Self.minimumTranscriptHeight
    @State private var selection: TextSelection?
    @FocusState private var editorFocused: Bool
    @State private var editorHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            LiquidLensBackdrop(
                sourceImage: speech.listeningSourceBackdrop,
                frosted: speech.listeningFrostedBackdrop,
                active: active && speech.phase != .editing,
                audioLevel: { speech.audioLevel }) { frame in
                ZStack(alignment: .bottom) {
                    if speech.phase == .editing {
                        domeWash(frame: frame)
                    }

                    if speech.phase == .editing {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: Theme.listeningWash.opacity(0.96), location: 0.28),
                                .init(color: Theme.listeningWash, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom)
                    }

                    ZStack(alignment: .bottom) {
                        if active, speech.phase != .editing, !speech.overlayText.isEmpty {
                            transcript(frame: frame)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: frame.size.width, height: frame.size.height)
                    .mask { frame.transcriptMask }
                }
                .animation(.smooth(duration: 0.25), value: speech.overlayText.isEmpty)
                .animation(.smooth(duration: 0.25), value: active)
            }

            if speech.phase == .editing {
                editingSurface
                    .padding(.bottom, 56 + 14 + 8)
                    .transition(editingTransition)
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.24),
            value: speech.phase)
        .contentShape(Rectangle())
        .allowsHitTesting(active)
        .onChange(of: active) { _, isActive in
            if !isActive { transcriptHeight = Self.minimumTranscriptHeight }
            if !isActive {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    if store.dockState != .listening {
                        speech.clearListeningBackdrop()
                    }
                }
            }
        }
    }

    private var editingTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var transcriptEditor: some View {
        @Bindable var speech = speech
        return TextEditor(text: $speech.draft, selection: $selection)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .accentTint(Theme.accentDark)
            .focused($editorFocused)
            .frame(minHeight: 140, maxHeight: 280)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { editorHeight = $0 }
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                if value.translation.height > abs(value.translation.width), value.location.y > editorHeight {
                    editorFocused = false
                }
            })
            .padding(.horizontal, 32)
            .accessibilityIdentifier("voice-transcript-editor")
            .accessibilityLabel("Recording transcript")
            .onAppear { editorFocused = true }
    }

    @ViewBuilder
    private var editingSurface: some View {
        if let editingControls, let editingControlOwner {
            RecordingEditorMount(
                controls: editingControls,
                owner: editingControlOwner,
                callbacks: .init(
                    isCurrentEditingSurface: {
                        active && speech.phase == .editing && store.dockState == .listening
                    },
                    cancel: cancel,
                    resume: resumeRecording,
                    send: sendNow)) {
                transcriptEditor
            }
            .id(editingControlOwner)
        } else {
            transcriptEditor
        }
    }

    private func resumeRecording() {
        speech.insertionPoint = currentCursor()
        editorFocused = false
        VoiceOutput.shared.stop()
        speech.prepareForFreshSegment()
        speech.phase = .locked
        Task {
            await speech.start()
            if !speech.isRunning { speech.phase = .editing }
        }
    }

    private func sendNow() {
        let text = speech.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            speech.draft = ""
            speech.phase = .idle
            selection = nil
            store.dockState = .idle
        } else if store.send(text) {
            speech.draft = ""
            speech.phase = .idle
            selection = nil
        } else {
            speech.phase = .editing
        }
    }

    private func cancel() {
        speech.draft = ""
        speech.phase = .idle
        selection = nil
        store.dockState = .idle
    }

    private func currentCursor() -> String.Index? {
        guard let selection else { return nil }
        if case .selection(let range) = selection.indices {
            return range.lowerBound
        }
        return nil
    }

    private func transcript(frame: LiquidLensFrame) -> some View {
        let bottomClearance = speech.backdropDockStrip + 54
        let transcriptMaximumHeight = max(1, frame.size.height - bottomClearance - frame.apex - 16)
        let textTop = bottomClearance
            + min(max(transcriptHeight + 14, Self.minimumTranscriptHeight), transcriptMaximumHeight)
        let washHeight = max(transcriptMaximumHeight + 260, textTop + 72)
        let solid = max(0.45 * (transcriptMaximumHeight + 260), textTop)
        return ZStack(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Theme.listeningWash.opacity(0.9), location: 1 - solid / washHeight),
                    .init(color: Theme.listeningWash.opacity(0.9), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom)
                .frame(height: washHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LiveTranscript(
                    text: speech.overlayText,
                    contentHeight: $transcriptHeight,
                    minimumHeight: Self.minimumTranscriptHeight,
                    maximumHeight: transcriptMaximumHeight)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.bottom, bottomClearance)
            .padding(.horizontal, 36)
        }
        .frame(width: frame.size.width, height: frame.size.height)
    }

    private func domeWash(frame: LiquidLensFrame) -> some View {
        let editing = speech.phase == .editing
        let radius = frame.size.width * (editing ? 1.55 : 1.45)
        let keyboard = KeyboardPresence.shared
        let lowered = keyboard.isVisible ? 0 : max(0, keyboard.lastHeight - Self.bottomInset)
        let apex = editing ? frame.size.height * 0.20 + lowered : frame.apex
        return Circle()
            .fill(LinearGradient(
                stops: [
                    .init(color: Theme.listeningWash.opacity(editing ? 0.30 : 0.02), location: 0),
                    .init(color: Theme.listeningWash.opacity(editing ? 0.84 : 0.10), location: 0.055),
                    .init(color: Theme.listeningWash.opacity(editing ? 0.72 : 0.10), location: 0.62),
                    .init(color: Theme.listeningWash.opacity(editing ? 0.34 : 0.06), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom))
            .frame(width: radius * 2, height: radius * 2)
            .opacity(editing ? 1 : frame.progress)
            .position(x: frame.size.width / 2, y: apex + radius)
            .animation(.spring(duration: 0.3, bounce: 0), value: keyboard.isVisible)
    }

    private static var bottomInset: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first?.windows.first(where: \.isKeyWindow)?.safeAreaInsets.bottom ?? 34
    }
}

private struct LiveTranscript: View {
    let text: String
    @Binding var contentHeight: CGFloat
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                VStack(alignment: .center, spacing: 0) {
                    Text(text)
                        .accessibilityIdentifier("voice-live-transcript")
                        .font(.system(size: 20, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: TranscriptHeightKey.self,
                                    value: proxy.size.height)
                            })
                    Color.clear.frame(height: 1).id("transcript-tail")
                }
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(true)
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .frame(
                height: min(max(contentHeight + 14, minimumHeight), maximumHeight),
                alignment: .bottom)
            .clipped()
            .mask {
                if contentHeight > maximumHeight + 1 {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.38),
                        ],
                        startPoint: .top,
                        endPoint: .bottom)
                } else {
                    Rectangle().fill(.white)
                }
            }
            .onChange(of: maximumHeight) { _, height in
                guard contentHeight > height + 1 else { return }
                Task { @MainActor in
                    await Task.yield()
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        reader.scrollTo("transcript-tail", anchor: .bottom)
                    }
                }
            }
            .onPreferenceChange(TranscriptHeightKey.self) { height in
                contentHeight = height
                guard height > maximumHeight + 1 else { return }
                Task { @MainActor in
                    await Task.yield()
                    reader.scrollTo("transcript-tail", anchor: .bottom)
                }
            }
        }
    }
}

private struct TranscriptHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 32
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TouchOriginRecorder: UIViewRepresentable {
    @MainActor
    final class LastTouch {
        var point: CGPoint?
    }

    let lastTouch: LastTouch

    func makeCoordinator() -> Coordinator { Coordinator(lastTouch: lastTouch) }

    func makeUIView(context: Context) -> UIView {
        let probe = UIView()
        probe.isUserInteractionEnabled = false
        return probe
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.lastTouch = lastTouch
        DispatchQueue.main.async { [weak coordinator = context.coordinator, weak view] in
            if let view { coordinator?.install(on: view.window) }
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.install(on: nil)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var lastTouch: LastTouch
        private var recognizer: UIGestureRecognizer?

        init(lastTouch: LastTouch) { self.lastTouch = lastTouch }

        func install(on window: UIWindow?) {
            guard recognizer?.view !== window else { return }
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            guard let window else { return }
            let probe = UITapGestureRecognizer()
            probe.cancelsTouchesInView = false
            probe.delaysTouchesBegan = false
            probe.delaysTouchesEnded = false
            probe.delegate = self
            window.addGestureRecognizer(probe)
            recognizer = probe
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            if let window = gestureRecognizer.view { lastTouch.point = touch.location(in: window) }
            return false
        }
    }
}

struct GenerationOverlay: View {
    let thinking: Bool
    var holdDelay: TimeInterval = 0
    var origin: CGPoint?
    var sourceImage: UIImage?
    var epoch: Date?
    var revealStart: Date?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dimmed = false
    @State private var startedAt = Date()
    @State private var cycleOffset = Double.random(in: 0..<14)
    @State private var revealing = false
    @State private var thinkingNow = false
    @State private var firstFrame = FirstFrame()

    private var visible: Bool { thinking || revealStart != nil }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: nil, paused: !dimmed || reduceMotion)) { timeline in
                if let sourceImage {
                    if reduceMotion {
                        Image(uiImage: sourceImage)
                            .resizable()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .colorMultiply(Color(white: scheme == .dark ? 0.9 : 0.84))
                    } else {
                        heldPage(sourceImage, size: proxy.size, now: timeline.date)
                    }
                } else {
                    Color.black.opacity(scheme == .dark ? 0.10 : 0.12)
                }
            }
        }
        .ignoresSafeArea()
        .opacity(dimmed ? 1 : 0)
        .allowsHitTesting(thinking)
        .onAppear {
            dimmed = visible
            thinkingNow = thinking
        }
        .task {
            try? await holdShader(size: .zero, now: Date()).compile(as: .layerEffect)
        }
        .onChange(of: thinking) { _, isThinking in
            guard isThinking else {
                thinkingNow = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if !revealing, !thinkingNow { fadeOut() }
                }
                return
            }
            thinkingNow = true
            firstFrame.date = nil
            startedAt = Date().addingTimeInterval(holdDelay)
            cycleOffset = Double.random(in: 0..<14)
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { dimmed = true }
        }
        .onChange(of: revealStart) { old, start in
            revealing = start != nil
            if let start {
                guard reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.25).delay(max(0, start.timeIntervalSinceNow))) {
                    dimmed = false
                }
            } else if old != nil, !thinking {
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { dimmed = false }
            }
        }
    }

    private func fadeOut() {
        withAnimation(.easeOut(duration: 0.22)) { dimmed = false }
    }

    private func heldPage(_ image: UIImage, size: CGSize, now: Date) -> some View {
        Image(uiImage: image)
            .resizable()
            .frame(width: size.width, height: size.height)
            .background(Theme.responsePaper)
            .layerEffect(holdShader(size: size, now: now),
                         maxSampleOffset: CGSize(width: 48, height: 48))
    }

    private func smoothstep(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    private final class FirstFrame {
        var date: Date?
    }

    private func holdShader(size: CGSize, now: Date) -> Shader {
        if dimmed, firstFrame.date == nil { firstFrame.date = now }
        let elapsed = now.timeIntervalSince(max(epoch ?? startedAt, firstFrame.date ?? now))
        let point = origin ?? CGPoint(x: size.width / 2, y: size.height * 0.62)
        var front: CGFloat = -10_000
        let band = ResponseRevealTiming.band(height: size.height)
        if let revealStart {
            let raw = now.timeIntervalSince(revealStart) / ResponseRevealTiming.duration
            if raw > 0 {
                front = ResponseRevealTiming.front(
                    progress: ResponseRevealTiming.eased(raw), height: size.height)
            }
        }
        return ShaderLibrary.generationHold(
            .float2(size),
            .float2(point),
            .float(Float(elapsed)),
            .float(scheme == .dark ? 0 : 1),
            .float(Float(smoothstep(min(1, max(0, elapsed / 0.22))))),
            .float(Float(front)),
            .float(Float(band)),
            .float(Float(cycleOffset)),
            accent.washArgument)
    }
}

@Observable @MainActor
final class RecordingEditorControls {
    enum Action { case cancel, resume, send }

    struct Callbacks {
        let isCurrentEditingSurface: @MainActor () -> Bool
        let cancel: @MainActor () -> Void
        let resume: @MainActor () -> Void
        let send: @MainActor () -> Void
    }

    private(set) var owner: UUID?
    private(set) var installedOwner: UUID?
    @ObservationIgnored private var callbacks: Callbacks?

    var isReady: Bool { owner != nil && installedOwner == owner && callbacks != nil }

    func expect(owner token: UUID?) {
        guard owner != token else { return }
        owner = token
        installedOwner = nil
        callbacks = nil
    }

    @discardableResult
    func install(owner token: UUID, callbacks: Callbacks) -> Bool {
        guard owner == token else { return false }
        installedOwner = token
        self.callbacks = callbacks
        return true
    }

    func clear(owner token: UUID) {
        guard owner == token, installedOwner == token else { return }
        installedOwner = nil
        callbacks = nil
    }

    @discardableResult
    func dispatch(_ action: Action, owner token: UUID) -> Bool {
        guard owner == token, installedOwner == token,
              let callbacks, callbacks.isCurrentEditingSurface() else { return false }
        switch action {
        case .cancel: callbacks.cancel()
        case .resume: callbacks.resume()
        case .send: callbacks.send()
        }
        return true
    }
}

private struct RecordingEditorMount<Content: View>: View {
    let controls: RecordingEditorControls
    let owner: UUID
    let callbacks: RecordingEditorControls.Callbacks
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .onAppear { controls.install(owner: owner, callbacks: callbacks) }
            .onDisappear { controls.clear(owner: owner) }
    }
}

struct ListeningTint: View {
    let listening: Bool
    let isHolding: () -> Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level = 0.0

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: nil, paused: level == 0 || reduceMotion)) { timeline in
                Rectangle()
                    .colorEffect(ShaderLibrary.listeningTint(
                        .float2(proxy.size),
                        .float(Float(timeline.date.timeIntervalSince(ListeningTintClock.start))),
                        .float(Float(ListeningTintClock.offset)),
                        accent.washArgument))
            }
        }
        .ignoresSafeArea()
        .blendMode(.multiply)
        .opacity(scheme == .dark ? 0 : level)
        .allowsHitTesting(false)
        .task {
            let f = Shader.Argument.float(0)
            let size = Shader.Argument.float2(CGSize(width: 1, height: 1))
            let tint = Shader.Argument.float3(1, 1, 1)
            try? await ShaderLibrary.listeningTint(size, f, f, tint).compile(as: .colorEffect)
            let circle = Shader.Argument.float3(0, 0, 1)
            try? await ShaderLibrary.liquidLens(size, circle, f, f, f, f, f, f, f, f, tint).compile(as: .layerEffect)
            try? await ShaderLibrary.liquidLensMeniscus(size, circle, f, f, f, f, f, f, f, f, tint).compile(as: .layerEffect)
            try? await ShaderLibrary.liquidLensTranscriptMask(size, circle, f, f, f).compile(as: .colorEffect)
        }
        .onChange(of: listening) { _, isListening in
            if isListening {
                ListeningTintClock.start = Date()
                ListeningTintClock.offset = Double.random(in: 0..<14)
                ListeningTintClock.fade = nil
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { level = 1 }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard level > 0 else { return }
                let holding = isHolding()
                ListeningTintClock.fade = holding ? (Date(), 0.37, 0.22, true) : (Date(), 0, 0.3, false)
                withAnimation(holding
                              ? .easeInOut(duration: 0.22).delay(0.37)
                              : .easeOut(duration: 0.3)) { level = 0 }
            }
        }
    }
}
