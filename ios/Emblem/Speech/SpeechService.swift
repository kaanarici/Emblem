import Foundation
import Speech
import AVFoundation
import Observation
import UIKit

@Observable @MainActor
final class SpeechService {
    private(set) var listeningSourceBackdrop: UIImage?
    private(set) var listeningFrostedBackdrop: UIImage?
    private(set) var backdropDockStrip: CGFloat = 152

    @ObservationIgnored private let levelBox = AudioLevelBox()
    var audioLevel: Float {
        return levelBox.load()
    }

    private(set) var isAvailable = false
    private(set) var isRunning = false
    private(set) var volatileText = ""
    private(set) var finalizedText = ""

    enum VoicePhase: Equatable { case idle, held, locked, editing }
    var phase: VoicePhase = .idle
    var draft = ""
    var insertionPoint: String.Index?

    func insertIntoDraft(_ segment: String) {
        guard !segment.isEmpty else { return }
        defer { insertionPoint = nil }
        if draft.isEmpty {
            draft = segment
        } else if let point = insertionPoint, point <= draft.endIndex {
            let before = String(draft[..<point])
            let after = String(draft[point...])
            let lead = before.isEmpty || before.hasSuffix(" ") ? "" : " "
            let tail = after.isEmpty || after.hasPrefix(" ") ? "" : " "
            draft = before + lead + segment + tail + after
        } else {
            draft += " " + segment
        }
    }

    var displayText: String {
        (finalizedText + " " + volatileText).trimmingCharacters(in: .whitespaces)
    }

    func prepareForFreshSegment() {
        volatileText = ""
        finalizedText = ""
    }

    var overlayText: String {
        let live = displayText
        guard !draft.isEmpty else { return live }
        guard !live.isEmpty else { return draft }

        let point = insertionPoint.flatMap { $0 <= draft.endIndex ? $0 : nil }
            ?? draft.endIndex
        let before = String(draft[..<point])
        let after = String(draft[point...])
        let lead = before.isEmpty || before.hasSuffix(" ") ? "" : " "
        let tail = after.isEmpty || after.hasPrefix(" ") ? "" : " "
        return before + lead + live + tail + after
    }

    @ObservationIgnored private var frostTask: Task<Void, Never>?
    @ObservationIgnored private var backdropFingerprint: [CGFloat]?

    func captureListeningBackdrop(reusingUnchanged: Bool = false) {
        let fingerprint = Self.pageFingerprint()
        if reusingUnchanged, listeningSourceBackdrop != nil, fingerprint != nil, fingerprint == backdropFingerprint {
            return
        }
        let source = capturePageBackdrop()
        backdropFingerprint = fingerprint
        listeningSourceBackdrop = source
        listeningFrostedBackdrop = nil
        frostTask?.cancel()
        guard let source else { return }
        frostTask = Task {
            let frosted = await Task.detached(priority: .userInitiated) { LensFrost.frost(source) }.value
            guard !Task.isCancelled, listeningSourceBackdrop === source else { return }
            listeningFrostedBackdrop = frosted
        }
    }

    func clearListeningBackdrop() {
        frostTask?.cancel()
        backdropFingerprint = nil
        listeningSourceBackdrop = nil
        listeningFrostedBackdrop = nil
    }

    func capturePageBackdrop() -> UIImage? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let inset = scenes.first?.windows.first(where: \.isKeyWindow)?.safeAreaInsets.bottom ?? 34
        backdropDockStrip = inset + 118
        return captureWindowBackdrop()
    }

    func captureWindowBackdrop() -> UIImage? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                ?? scenes.first,
              let window = scene.windows.first(where: \.isKeyWindow)
                ?? scene.windows.first(where: { !$0.isHidden })
        else { return nil }
        let target = Self.pageCaptureView(in: window) ?? window

        let format = UIGraphicsImageRendererFormat()
        format.scale = scene.screen.scale
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        return renderer.image { _ in
            target.drawHierarchy(
                in: window.convert(target.bounds, from: target),
                afterScreenUpdates: false)
        }
    }

    private static func pageFingerprint() -> [CGFloat]? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.first?.windows.first(where: \.isKeyWindow),
              let page = pageCaptureView(in: window) else { return nil }
        var values: [CGFloat] = [window.bounds.width, window.bounds.height,
                                 CGFloat(window.traitCollection.userInterfaceStyle.rawValue)]
        var queue: [UIView] = [page]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let scroll = view as? UIScrollView {
                values += [scroll.contentOffset.x, scroll.contentOffset.y, scroll.contentSize.height]
            }
            queue.append(contentsOf: view.subviews)
        }
        return values
    }

    private static func pageCaptureView(in window: UIWindow) -> UIView? {
        var queue: [UIView] = [window]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if view.next is UINavigationController { return view }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    private var locale = Locale(identifier: "en-US")
    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private let converter = BufferConverter()
    private var starting = false

    #if DEBUG && targetEnvironment(simulator)
    @ObservationIgnored private let recordingSource: RecordingTranscriptSource?

    init(recordingSource: RecordingTranscriptSource? = .fromEnvironment()) {
        self.recordingSource = recordingSource
    }
    #endif

    func prepare() async {
        #if DEBUG && targetEnvironment(simulator)
        if recordingSource != nil {
            isAvailable = true
            return
        }
        #endif
        var chosen: Locale?
        for identifier in Locale.preferredLanguages + [Locale.current.identifier, "en-US"] where chosen == nil {
            chosen = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier))
        }
        guard let chosen else { return }
        locale = chosen

        let probe = Self.makeTranscriber(locale: locale)
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
                try await request.downloadAndInstall()
            }
            isAvailable = true
        } catch {
            isAvailable = false
        }
    }

    func start() async {
        guard isAvailable, analyzer == nil, !isRunning, !starting, !Task.isCancelled else { return }
        #if DEBUG && targetEnvironment(simulator)
        if let recordingSource {
            prepareForFreshSegment()
            isRunning = true
            resultsTask = Task { [weak self] in
                for await text in recordingSource.start() {
                    guard !Task.isCancelled else { return }
                    self?.volatileText = text
                }
            }
            return
        }
        #endif
        starting = true
        defer { starting = false }
        guard await AVAudioApplication.requestRecordPermission() else {
            isAvailable = false
            return
        }
        guard !Task.isCancelled else { return }

        prepareForFreshSegment()

        do {
            let transcriber = Self.makeTranscriber(locale: locale)
            self.transcriber = transcriber

            try await Task.detached(priority: .userInitiated) {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .spokenAudio, options: .duckOthers)
                try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            }.value

            let analyzer = SpeechAnalyzer(
                modules: [transcriber],
                options: .init(priority: .userInitiated, modelRetention: .processLifetime))
            self.analyzer = analyzer
            analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            try await analyzer.prepareToAnalyze(in: analyzerFormat)
            guard !Task.isCancelled else {
                await teardown()
                return
            }

            let (inputSequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
            inputBuilder = builder

            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self else { return }
                        let text = String(result.text.characters)
                        if result.isFinal {
                            self.finalizedText += text
                            self.volatileText = ""
                        } else {
                            self.volatileText = text
                        }
                    }
                } catch {
                }
            }

            try await analyzer.start(inputSequence: inputSequence)
            guard !Task.isCancelled else {
                await teardown()
                return
            }

            let tapFormat = audioEngine.inputNode.outputFormat(forBus: 0)
            nonisolated(unsafe) let converter = self.converter
            let tapBuilder = self.inputBuilder
            let format = analyzerFormat
            let levelBox = self.levelBox
            audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { @Sendable buffer, _ in
                if let data = buffer.floatChannelData?[0] {
                    let n = Int(buffer.frameLength)
                    if n > 0 {
                        var sum: Float = 0
                        for i in stride(from: 0, to: n, by: 8) { sum += data[i] * data[i] }
                        let rms = (sum / Float((n + 7) / 8)).squareRoot()
                        levelBox.decayingStore(min(1, rms * 9))
                    }
                }
                guard let format else { return }
                if let converted = try? converter.convertBuffer(buffer, to: format) {
                    tapBuilder?.yield(AnalyzerInput(buffer: converted))
                }
            }
            let engine = audioEngine
            try await Task.detached(priority: .userInitiated) {
                engine.prepare()
                try engine.start()
            }.value
            isRunning = true
        } catch {
            await teardown()
        }
    }

    private static func makeTranscriber(locale: Locale) -> DictationTranscriber {
        DictationTranscriber(
            locale: locale,
            contentHints: [.shortForm],
            transcriptionOptions: [.punctuation],
            reportingOptions: [.volatileResults, .frequentFinalization],
            attributeOptions: [])
    }

    func finish() async -> String {
        while starting {
            try? await Task.sleep(for: .milliseconds(40))
        }
        #if DEBUG && targetEnvironment(simulator)
        if let recordingSource {
            recordingSource.finish()
            resultsTask?.cancel()
            resultsTask = nil
            isRunning = false
            return displayText
        }
        #endif
        guard analyzer != nil else { return "" }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        let transcript = displayText
        await teardown()
        return transcript
    }

    private func teardown() async {
        isRunning = false
        resultsTask?.cancel()
        resultsTask = nil
        inputBuilder = nil
        analyzer = nil
        transcriber = nil
        analyzerFormat = nil
        levelBox.reset()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

final class AudioLevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0

    func decayingStore(_ new: Float) {
        lock.lock()
        let decayed = value * 0.90
        value = new > decayed ? value + (new - value) * 0.45 : decayed
        lock.unlock()
    }

    func load() -> Float {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func reset() {
        lock.lock(); value = 0; lock.unlock()
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor
final class RecordingTranscriptSource {
    private var segments: [String]
    private var continuation: AsyncStream<String>.Continuation?

    init(segments: [String]) { self.segments = segments }

    static func fromEnvironment() -> RecordingTranscriptSource? {
        guard let json = ProcessInfo.processInfo.environment["EMBLEM_RECORDING_SEGMENTS"],
              let data = json.data(using: .utf8),
              let segments = try? JSONDecoder().decode([String].self, from: data),
              !segments.isEmpty else { return nil }
        return RecordingTranscriptSource(segments: segments)
    }

    func start() -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        self.continuation = continuation
        if !segments.isEmpty { continuation.yield(segments.removeFirst()) }
        return stream
    }

    func finish() {
        continuation?.finish()
        continuation = nil
    }
}
#endif
