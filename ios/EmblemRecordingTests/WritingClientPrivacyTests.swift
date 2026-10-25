import Foundation
import Synchronization
import XCTest
@testable import Emblem
@testable import EmblemCore

@MainActor
final class WritingClientPrivacyTests: XCTestCase {
    func testAppleDraftRejectsRewriteEvenWithEmblemSelectedBeforeAuthOrTransport() async throws {
        let rig = try WritingPrivacyRig(selection: .emblem)
        defer { rig.close() }
        let page = GeneratedPage(prompt: "Private attachment draft")
        page.origin = .apple
        XCTAssertEqual(OnDeviceModel.selection(in: rig.defaults), .emblem)
        var streamed: [String] = []

        do {
            _ = try await WritingClient.rewrite(
                body: "Private attachment-derived draft", style: "crisper", origin: page.origin,
                session: rig.session, defaults: rig.defaults
            ) { streamed.append($0) }
            XCTFail("Apple-origin draft was admitted to cloud rewriting")
        } catch {
            guard case WritingClient.Failure.appleOrigin = error else {
                return XCTFail("Expected the Apple-origin restriction, got \(error)")
            }
            XCTAssertEqual(
                error.localizedDescription,
                "Tone rewrites aren’t available for Apple-generated drafts. You can edit this draft directly.")
        }

        XCTAssertEqual(rig.authLookups, 0, "Reject before constructing an authenticated request")
        XCTAssertTrue(rig.requests.isEmpty)
        XCTAssertTrue(streamed.isEmpty)
    }

    func testMissingPageOriginFailsClosedForRewrite() async throws {
        let rig = try WritingPrivacyRig(selection: .emblem)
        defer { rig.close() }
        let page: GeneratedPage? = nil

        do {
            _ = try await WritingClient.rewrite(
                body: "Draft with missing page context", style: "shorter", origin: page?.origin ?? .apple,
                session: rig.session, defaults: rig.defaults
            ) { _ in XCTFail("A rejected rewrite streamed text") }
            XCTFail("Missing page context was admitted to cloud rewriting")
        } catch {
            guard case WritingClient.Failure.appleOrigin = error else {
                return XCTFail("Expected fail-closed Apple origin, got \(error)")
            }
        }

        XCTAssertEqual(rig.authLookups, 0)
        XCTAssertTrue(rig.requests.isEmpty)
    }

    func testServerDraftRetainsSeparateNativeSelectionRestriction() async throws {
        let rig = try WritingPrivacyRig(selection: .onDevice)
        defer { rig.close() }

        do {
            _ = try await WritingClient.rewrite(
                body: "Server draft", style: "bolder", origin: .server,
                session: rig.session, defaults: rig.defaults
            ) { _ in XCTFail("A rejected rewrite streamed text") }
            XCTFail("Server rewrite bypassed the selected-model restriction")
        } catch {
            guard case WritingClient.Failure.appleMode = error else {
                return XCTFail("Expected the selected-model restriction, got \(error)")
            }
            XCTAssertEqual(
                error.localizedDescription,
                "Tone rewrites use Emblem. Choose Emblem in Settings to use them.")
        }

        XCTAssertEqual(rig.authLookups, 0)
        XCTAssertTrue(rig.requests.isEmpty)
    }

    func testServerDraftStillStreamsRewriteWithEmblemSelected() async throws {
        let rig = try WritingPrivacyRig(selection: .emblem)
        defer { rig.close() }
        var streamed: [String] = []

        let result = try await WritingClient.rewrite(
            body: "Original server draft", style: "shorter", origin: .server,
            session: rig.session, defaults: rig.defaults
        ) { streamed.append($0) }

        XCTAssertEqual(result, "A shorter draft.")
        XCTAssertEqual(streamed, ["A shorter draft."])
        XCTAssertEqual(rig.authLookups, 1)
        XCTAssertEqual(rig.requests.count, 1)
        let request = try XCTUnwrap(rig.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/writing")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
}

@MainActor
private final class WritingPrivacyRig {
    let defaults: UserDefaults
    let session: URLSession
    private(set) var authLookups = 0
    private let suite = "WritingClientPrivacyTests.\(UUID().uuidString)"
    private let restoreProviders: () -> Void

    var requests: [URLRequest] { WritingPrivacyTransport.requests(for: suite) }

    init(selection: OnDeviceModel.Selection) throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(selection.rawValue, forKey: "apple.model")
        defaults.set(false, forKey: "apple.webSearch.allowed")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WritingPrivacyTransport.self]
        configuration.httpAdditionalHeaders = ["X-Emblem-Writing-Test": suite]
        session = URLSession(configuration: configuration)

        let bearer = GenerateClient.bearerTokenProvider
        let credential = GenerateClient.inferenceCredentialProvider
        let managed = GenerateClient.managedInferenceModelProvider
        restoreProviders = {
            GenerateClient.bearerTokenProvider = bearer
            GenerateClient.inferenceCredentialProvider = credential
            GenerateClient.managedInferenceModelProvider = managed
        }
        GenerateClient.bearerTokenProvider = { [weak self] in
            self?.authLookups += 1
            return nil
        }
        GenerateClient.inferenceCredentialProvider = nil
        GenerateClient.managedInferenceModelProvider = nil
    }

    func close() {
        restoreProviders()
        session.invalidateAndCancel()
        defaults.removePersistentDomain(forName: suite)
        WritingPrivacyTransport.clear(suite)
    }
}

private final class WritingPrivacyTransport: URLProtocol, @unchecked Sendable {
    private static let captured = Mutex<[String: [URLRequest]]>([:])

    static func requests(for suite: String) -> [URLRequest] {
        captured.withLock { ($0[suite] ?? []) + ($0["missing-suite"] ?? []) }
    }

    static func clear(_ suite: String) {
        captured.withLock { $0[suite] = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let suite = request.value(forHTTPHeaderField: "X-Emblem-Writing-Test") ?? "missing-suite"
        Self.captured.withLock { $0[suite, default: []].append(request) }
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/x-ndjson"])
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = "{\"type\":\"delta\",\"text\":\"A shorter draft.\"}\n{\"type\":\"complete\"}\n"
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
