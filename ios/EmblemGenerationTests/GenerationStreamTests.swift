import Foundation
@testable import EmblemCore
import XCTest

final class GenerationStreamTests: XCTestCase {
    func testAResponseTheServerIsStillGeneratingIsWaitedForAfterTheConnectionDrops() throws {
        let dropped = GenerationFailure(code: "network_connection_lost", message: "Lost", retryable: true)
        let running = GenerationFailure(code: "generation_in_progress", message: "Running", retryable: true)
        var budget = GenerationSession.ResumeBudget()
        for _ in 0..<2 { budget = try XCTUnwrap(GenerationSession.resumption(after: dropped, budget: budget)).budget }
        XCTAssertNil(GenerationSession.resumption(after: dropped, budget: budget), "A dropped stream resumed forever")
        for _ in 0..<100 {
            let next = try XCTUnwrap(GenerationSession.resumption(after: running, budget: budget), "Gave up on a running response")
            XCTAssertEqual(next.delay, .milliseconds(1_500))
            budget = next.budget
        }
        XCTAssertNil(GenerationSession.resumption(
            after: GenerationFailure(code: "idempotency_conflict", message: "Conflict", retryable: false),
            budget: GenerationSession.ResumeBudget()))
    }

    func testSnapshotsReplaceEarlierRevisionsAndValidateFinalCount() {
        var stream = GenerationStream()
        _ = stream.consume(data(#"{"type":"pageSnapshot","id":"page-snapshot","revision":1,"blocks":[]}"#))
        let event = stream.consume(data(#"{"type":"pageSnapshot","id":"page-snapshot","revision":2,"blocks":[{"type":"text","id":"intro","body":"Hello","style":"intro"}]}"#))
        guard case .pageSnapshot(revision: 2, let blocks) = event else { return XCTFail("Expected revision 2") }
        XCTAssertEqual(blocks.map(\.id), ["intro"])
        guard case .finished(persisted: true, _, _) = stream.consume(data(#"{"type":"terminal","status":"completed","revision":2,"blockCount":1,"persisted":true}"#)) else {
            return XCTFail("Expected a count-checked durable completion")
        }
        XCTAssertTrue(stream.isTerminal)
        XCTAssertNil(stream.consume(data(#"{"type":"status","text":"Too late"}"#)))
    }

    func testInvalidRevisionCountAndMixedModesFail() {
        let invalidTails = [
            #"{"type":"pageSnapshot","id":"page-snapshot","revision":1,"blocks":[]}"#,
            #"{"type":"terminal","status":"completed","revision":2,"blockCount":0}"#,
            #"{"type":"terminal","status":"completed","revision":1,"blockCount":2}"#,
            #"{"type":"text","id":"late","body":"Mixed mode","style":"body"}"#,
        ]
        for tail in invalidTails {
            var stream = GenerationStream()
            _ = stream.consume(data(#"{"type":"pageSnapshot","id":"page-snapshot","revision":1,"blocks":[]}"#))
            guard case .failed(let failure) = stream.consume(data(tail)) else { return XCTFail("Accepted \(tail)") }
            XCTAssertEqual(failure.code, "invalid_stream")
        }
    }

    func testContentOutsideASnapshotIsInvalid() {
        var stream = GenerationStream()
        guard case .failed(let failure) = stream.consume(data(#"{"type":"text","id":"loose","body":"Loose","style":"body"}"#)) else {
            return XCTFail("A bare block line was accepted")
        }
        XCTAssertEqual(failure.code, "invalid_stream")
    }

    func testSnapshotItemsAndUnknownBlocksCount() {
        var stream = GenerationStream()
        let snapshot = #"{"type":"pageSnapshot","id":"page-snapshot","revision":1,"blocks":["#
            + #"{"type":"featureList","id":"features","items":[{"title":"A"}]},"#
            + #"{"type":"future","id":"future","items":[{"anything":true}]}]}"#
        guard case .pageSnapshot(revision: 1, let blocks) = stream.consume(data(snapshot)) else {
            return XCTFail("Snapshot content was mistaken for protocol metadata")
        }
        XCTAssertEqual(blocks.count, 2)
        guard case .finished = stream.consume(data(#"{"type":"terminal","status":"completed","revision":1,"blockCount":2}"#)) else {
            return XCTFail("Unknown blocks no longer count toward the terminal")
        }
    }

    func testActivityAndSourceUpdatesKeepOneEntryPerIdentity() {
        var stream = GenerationStream()
        _ = stream.consume(data(#"{"type":"pageSnapshot","id":"page-snapshot","revision":1,"blocks":[]}"#))
        for status in ["started", "succeeded"] {
            _ = stream.consume(data("{\"type\":\"activity\",\"id\":\"a\",\"source\":\"web\",\"category\":\"web\",\"title\":\"Search\",\"status\":\"\(status)\",\"message\":\"Search\"}"))
            _ = stream.consume(data("{\"type\":\"sources\",\"items\":[{\"id\":\"s\",\"title\":\"\(status)\",\"url\":\"https://example.com\",\"domain\":\"example.com\"}]}"))
        }
        guard case .finished(_, let activities, let sources) = stream.consume(data(#"{"type":"terminal","status":"completed","revision":1,"blockCount":0}"#)) else { return XCTFail("Missing completion") }
        XCTAssertEqual(activities.map(\.status), ["succeeded"])
        XCTAssertEqual(sources.map(\.title), ["succeeded"])
    }

    func testExplicitErrorCannotBecomeSuccessAndEOFIsNeverCompletion() {
        var stream = GenerationStream()
        guard case .failed(let cutoff) = stream.endOfStream() else { return XCTFail("EOF succeeded") }
        XCTAssertEqual(cutoff.code, "stream_cutoff")
        stream = GenerationStream()
        _ = stream.consume(data(#"{"type":"error","code":"provider_failed","message":"Try again","retryable":true}"#))
        guard case .failed(let failure) = stream.consume(data(#"{"type":"terminal","status":"completed","blockCount":0}"#)) else { return XCTFail("Error became success") }
        XCTAssertEqual(failure.code, "provider_failed")
    }

    func testMalformedProtocolLineFailsInsteadOfDisappearing() {
        var stream = GenerationStream()
        guard case .failed = stream.consume(data(#"{"type":"status"}"#)) else { return XCTFail("Missing text accepted") }
    }

    func testSavedBlockArraysTolerateMalformedAndFutureEntries() throws {
        let blocks = try JSONDecoder().decode([Block].self, from: data(#"[null,7,{"type":"chart","id":"broken"},{"type":"future","id":"next"},{"type":"text","id":"kept","body":"Still here","style":"body"}]"#))
        XCTAssertEqual(blocks.count, 5)
        guard case .text(let text) = blocks.last else { return XCTFail("Lost valid content") }
        XCTAssertEqual(text.body, "Still here")
    }

    private func data(_ text: String) -> Data { Data(text.utf8) }
}
