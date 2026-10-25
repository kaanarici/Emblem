import Foundation
import Synchronization
import XCTest
@testable import Emblem
@testable import EmblemCore

@MainActor
final class VoiceOutputPrivacyTests: XCTestCase {
    func testNativeCompletionUsesSystemSpeechWithoutTTSRequest() async throws {
        let rig = try SpeechPrivacyRig()
        defer { rig.close() }
        let page = GeneratedPage(prompt: "Summarize the private attachment")
        page.origin = .apple
        let intro = "Your **private attachment** says the appointment is at 9 AM."

        rig.voice.speak(intro, origin: page.origin, id: "native-intro")
        await rig.waitForSpeech()

        XCTAssertEqual(rig.spoken, ["Your private attachment says the appointment is at 9 AM."])
        XCTAssertTrue(rig.requests.isEmpty, "Native completion must not POST attachment-derived text to TTS")
    }

    func testForcedNativeReplayStaysLocalWhileMuted() async throws {
        let rig = try SpeechPrivacyRig()
        defer { rig.close() }
        let page = GeneratedPage(prompt: "Private Apple response")
        page.origin = .apple
        rig.voice.muted = true

        rig.voice.speak("Private attachment-derived intro", origin: page.origin, id: "native-replay", force: true)
        await rig.waitForSpeech()

        XCTAssertEqual(rig.spoken, ["Private attachment-derived intro"])
        XCTAssertTrue(rig.requests.isEmpty, "Force overrides mute, never the page's native boundary")
    }

    func testServerOriginStillRequestsCloudVoice() async throws {
        let rig = try SpeechPrivacyRig()
        defer { rig.close() }
        let page = GeneratedPage(prompt: "Server response")

        rig.voice.speak("A **server** intro", origin: page.origin, id: "server-intro")
        await rig.waitForSpeech()

        XCTAssertEqual(rig.requests.count, 1)
        let request = try XCTUnwrap(rig.requests.first)
        XCTAssertEqual(request.url?.path, "/api/tts")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "audio/pcm")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: body), ["text": "A server intro"])
        XCTAssertEqual(rig.spoken, ["A server intro"], "The intercepted 503 must retain the system-speech fallback")
    }

    func testForcedServerReplayStillRequestsCloudVoiceWhileMuted() async throws {
        let rig = try SpeechPrivacyRig()
        defer { rig.close() }
        rig.voice.muted = true

        rig.voice.speak("Server replay", origin: .server, id: "server-replay", force: true)
        await rig.waitForSpeech()

        XCTAssertEqual(rig.requests.count, 1)
        XCTAssertEqual(rig.spoken, ["Server replay"])
    }

    func testMutedNativeCompletionDoesNotSpeakOrRequestTTS() async throws {
        let rig = try SpeechPrivacyRig()
        defer { rig.close() }
        rig.voice.muted = true

        rig.voice.speak("Private intro", origin: .apple)
        await Task.yield()

        XCTAssertTrue(rig.spoken.isEmpty)
        XCTAssertTrue(rig.requests.isEmpty)
        XCTAssertNil(rig.voice.activeID)
    }
}

@MainActor
private final class SpeechPrivacyRig {
    let defaults: UserDefaults
    let voice: VoiceOutput
    private let suite = "VoiceOutputPrivacyTests.\(UUID().uuidString)"
    private let session: URLSession
    private let output: SpeechPrivacyOutput

    var spoken: [String] { output.texts }
    var requests: [URLRequest] { SpeechPrivacyTransport.requests(for: suite) }

    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(false, forKey: "voice.muted")
        defaults.set(false, forKey: "apple.webSearch.allowed")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpeechPrivacyTransport.self]
        configuration.httpAdditionalHeaders = ["X-Emblem-Speech-Test": suite]
        session = URLSession(configuration: configuration)
        let output = SpeechPrivacyOutput()
        self.output = output
        voice = VoiceOutput(session: session, defaults: defaults, systemSpeech: { output.texts.append($0) })
    }

    func waitForSpeech() async {
        for _ in 0..<100 {
            if !spoken.isEmpty { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Speech did not reach the injected system-speech sink")
    }

    func close() {
        voice.stop()
        session.invalidateAndCancel()
        defaults.removePersistentDomain(forName: suite)
        SpeechPrivacyTransport.clear(suite)
    }
}

@MainActor
private final class SpeechPrivacyOutput {
    var texts: [String] = []
}

private final class SpeechPrivacyTransport: URLProtocol, @unchecked Sendable {
    private static let captured = Mutex<[String: [URLRequest]]>([:])

    static func requests(for suite: String) -> [URLRequest] {
        captured.withLock { $0[suite] ?? [] }
    }

    static func clear(_ suite: String) {
        captured.withLock { $0[suite] = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let suite = request.value(forHTTPHeaderField: "X-Emblem-Speech-Test") ?? "missing-suite"
        var recorded = request
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            recorded.httpBody = body
        }
        Self.captured.withLock { $0[suite, default: []].append(recorded) }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
