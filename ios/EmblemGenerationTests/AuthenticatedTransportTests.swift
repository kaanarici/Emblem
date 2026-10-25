import Foundation
@testable import EmblemCore
import XCTest

@MainActor
final class AuthenticatedTransportTests: XCTestCase {
    func testJSONRequestsDoNotDowngradeTokenFailuresToGuestRequests() async {
        let original = GenerateClient.bearerTokenProvider
        defer { GenerateClient.bearerTokenProvider = original }
        GenerateClient.bearerTokenProvider = { throw URLError(.userAuthenticationRequired) }
        do {
            _ = try await GenerateClient.fetchJSON(path: "api/memory", query: [])
            XCTFail("GET continued after token failure")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .userAuthenticationRequired)
        }
        do {
            _ = try await GenerateClient.postJSON(path: "api/memory", body: ["action": "clear"])
            XCTFail("POST continued after token failure")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .userAuthenticationRequired)
        }
    }

    func testStreamReportsTokenFailureWithoutSendingAGuestRequest() async {
        let original = GenerateClient.bearerTokenProvider
        defer { GenerateClient.bearerTokenProvider = original }
        GenerateClient.bearerTokenProvider = { throw URLError(.userAuthenticationRequired) }
        let failed = expectation(description: "Authentication failure")
        let client = GenerateClient()
        client.stream(path: "api/generate", body: Optional<String>.none) { event in
            guard case .failed(let failure) = event else { return XCTFail("Unexpected guest stream event") }
            XCTAssertEqual(failure.code, "authentication_required")
            XCTAssertFalse(failure.retryable)
            failed.fulfill()
        }
        await fulfillment(of: [failed], timeout: 2)
        client.cancel()
    }
}
