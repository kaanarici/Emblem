import AVFoundation
import Foundation
import Observation
import SwiftUI
import os.log
import EmblemCore

@Observable @MainActor
final class VoiceOutput: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceOutput()

    private static let mutedKey = "voice.muted"
    private let defaults: UserDefaults
    var muted: Bool {
        didSet {
            defaults.set(muted, forKey: Self.mutedKey)
            if muted { stop() }
        }
    }

    enum Playback { case idle, generating, playing }
    private(set) var state: Playback = .idle
    private(set) var activeID: String?
    private(set) var finishedIDs: Set<String> = []

    static func key(page: String, block: String) -> String { "\(page)#\(block)" }

    private let synthesizer = AVSpeechSynthesizer()
    private let session: URLSession
    private let systemSpeech: ((String) -> Void)?
    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var fetchTask: Task<Void, Never>?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "emblem", category: "voice")

    private var audioCache: [String: Data] = [:]

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        systemSpeech: ((String) -> Void)? = nil
    ) {
        self.session = session
        self.defaults = defaults
        self.systemSpeech = systemSpeech
        self.muted = defaults.bool(forKey: Self.mutedKey)
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, origin: GeneratedPage.Origin, id: String? = nil, force: Bool = false) {
        guard force || !muted else { return }
        stop()

        if origin == .server, let id, let cached = audioCache[id] {
            playCached(cached, id: id)
            return
        }

        let plain = text.replacingOccurrences(of: "**", with: "")
        guard !plain.isEmpty else { return }

        activeID = id
        state = .generating
        if origin == .apple {
            speakOnDevice(plain)
            return
        }

        let identityEpoch = ConversationHistory.shared.epoch
        fetchTask = Task { [weak self] in
            guard let self else { return }
            let spoke = await self.streamGrok(plain, identityEpoch: identityEpoch)
            guard (try? GenerateClient.checkIdentity(identityEpoch)) != nil else { return }
            if !spoke, !Task.isCancelled, force || !self.muted {
                self.speakOnDevice(plain)
            }
        }
    }

    func stop() {
        fetchTask?.cancel()
        fetchTask = nil
        var wasPlaying = false
        if engine != nil {
            node?.stop()
            engine?.stop()
            node = nil
            engine = nil
            wasPlaying = true
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            wasPlaying = true
        }
        if wasPlaying { releaseSession() }
        activeID = nil
        state = .idle
    }

    private func streamGrok(_ text: String, identityEpoch: UUID) async -> Bool {
        let started = ContinuousClock.now
        var request = URLRequest(url: AppConfig.baseURL.appending(path: "api/tts"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/pcm", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 6
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])
        do {
            if let token = try await GenerateClient.bearerToken(for: identityEpoch) {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        } catch { return false }

        guard let (bytes, response) = try? await session.bytes(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("audio/pcm")
        else { return false }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1) else {
            return false
        }
        guard (try? GenerateClient.checkIdentity(identityEpoch)) != nil else { return true }
        var pending = Data()
        var captured = Data()
        var playedAny = false
        do {
            for try await byte in bytes {
                if Task.isCancelled { break }
                pending.append(byte)
                if pending.count >= 9600 {
                    try GenerateClient.checkIdentity(identityEpoch)
                    guard let player = try ensureEngine(format: format) else { break }
                    if let buffer = Self.pcmBuffer(pending, format: format) {
                        if !playedAny {
                            log.info("first audio in \((ContinuousClock.now - started).description, privacy: .public)")
                            state = .playing
                        }
                        player.scheduleBuffer(buffer, completionHandler: nil)
                        playedAny = true
                    }
                    captured.append(pending)
                    pending.removeAll(keepingCapacity: true)
                }
            }
        } catch {
            if !playedAny { log.error("pcm stream failed before audio: \(String(describing: error), privacy: .public)") }
        }

        if Task.isCancelled || (try? GenerateClient.checkIdentity(identityEpoch)) == nil {
            return true
        }
        var playerIfAny = node
        if playerIfAny == nil {
            playerIfAny = try? ensureEngine(format: format)
        }
        guard let player = playerIfAny else { return playedAny }
        if let tail = Self.pcmBuffer(pending, format: format) {
            if !playedAny { state = .playing }
            player.scheduleBuffer(tail, completionHandler: nil)
            playedAny = true
        }
        captured.append(pending)
        guard playedAny else {
            stopEngineOnly()
            return false
        }
        if let id = activeID, !captured.isEmpty { audioCache[id] = captured }
        if let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1200) {
            silence.frameLength = 1200
            player.scheduleBuffer(silence, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.finishPlayback() }
            }
        }
        return true
    }

    private func playCached(_ pcm: Data, id: String) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1),
              let player = try? ensureEngine(format: format),
              let buffer = Self.pcmBuffer(pcm, format: format) else { return }
        activeID = id
        state = .playing
        player.scheduleBuffer(buffer, completionHandler: nil)
        if let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1200) {
            silence.frameLength = 1200
            player.scheduleBuffer(silence, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.finishPlayback() }
            }
        }
    }

    private func ensureEngine(format: AVAudioFormat) throws -> AVAudioPlayerNode? {
        if let node { return node }
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        activateSession()
        try engine.start()
        node.play()
        self.engine = engine
        self.node = node
        return node
    }

    private func finishPlayback() {
        stopEngineOnly()
        releaseSession()
        markFinished()
    }

    private func markFinished() {
        if let activeID {
            withAnimation(.smooth(duration: 0.3)) {
                _ = finishedIDs.insert(activeID)
            }
        }
        activeID = nil
        state = .idle
    }

    private func stopEngineOnly() {
        node?.stop()
        engine?.stop()
        node = nil
        engine = nil
    }

    private static func pcmBuffer(_ data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = data.count / 2
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            let int16 = raw.bindMemory(to: Int16.self)
            let out = buffer.floatChannelData![0]
            for i in 0..<frames {
                out[i] = Float(Int16(littleEndian: int16[i])) / 32768.0
            }
        }
        return buffer
    }

    private func speakOnDevice(_ text: String) {
        if let systemSpeech {
            systemSpeech(text)
            return
        }
        activateSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice
        synthesizer.speak(utterance)
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func releaseSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in if self.state == .generating { self.state = .playing } }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.releaseSession()
            self.markFinished()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.releaseSession() }
    }

    static let bestVoice: AVSpeechSynthesisVoice? = {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
        return candidates.first { $0.quality == .premium }
            ?? candidates.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: language)
    }()
}
