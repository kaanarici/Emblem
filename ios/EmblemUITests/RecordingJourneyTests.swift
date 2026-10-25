import XCTest

final class RecordingJourneyTests: JourneyTestCase {
    private let first = "Plan my afternoon around the launch review."
    private let resumed = "Leave time to answer Maya."

    private func launchRecording(_ server: StubServer, segments: [String]) throws {
        let json = String(decoding: try JSONEncoder().encode(segments), as: UTF8.self)
        launch(server, environment: ["EMBLEM_RECORDING_SEGMENTS": json])
    }

    func testHeldRecordingLocksPausesResumesAndSendsTheWholeTranscript() throws {
        let server = try StubServer()
        try launchRecording(server, segments: [first, resumed])
        let mic = app.buttons["voice-microphone"].firstMatch
        XCTAssertTrue(mic.waitForExistence(timeout: 10))

        let start = mic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 3, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -90)),
                    withVelocity: .slow, thenHoldForDuration: 1)
        let transcript = app.staticTexts["voice-live-transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 4))
        XCTAssertEqual(transcript.label, first)
        XCTAssertTrue(element("voice-lock-status").exists, "Sliding up did not lock the recording")
        XCTAssertTrue(element("voice-send").waitForExistence(timeout: 2),
                      "The locked recording's keyboard button did not turn into send once words appeared")

        tap(mic)
        let editor = app.textViews["voice-transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        XCTAssertEqual(editor.value as? String, first)
        XCTAssertTrue(app.buttons["voice-cancel"].exists)

        tap(mic)
        XCTAssertTrue(transcript.waitForExistence(timeout: 4))
        XCTAssertTrue(transcript.label.contains(first), "Resuming replaced the paused transcript")
        XCTAssertTrue(transcript.label.contains(resumed))

        tap(mic)
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        let combined = try XCTUnwrap(editor.value as? String)
        tap(app.buttons["Send recording"])
        answerLocationPrompt()
        XCTAssertTrue(app.buttons["Draft my reply to Maya"].waitForExistence(timeout: 15))
        XCTAssertEqual(server.prompts, [combined])
    }

    func testDismissingTheKeyboardWhileEditingReturnsTheControls() throws {
        let server = try StubServer()
        try launchRecording(server, segments: [first])
        let mic = app.buttons["voice-microphone"].firstMatch
        XCTAssertTrue(mic.waitForExistence(timeout: 10))
        let resting = mic.frame

        let start = mic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 3, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -90)),
                    withVelocity: .slow, thenHoldForDuration: 1)
        tap(mic)
        let editor = app.textViews["voice-transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 4))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4))

        let top = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        top.press(forDuration: 0.05, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 420)),
                  withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 4), "The keyboard did not dismiss")
        Thread.sleep(forTimeInterval: 0.8)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "editing-keyboard-dismissed"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertEqual(mic.frame.midY, resting.midY, accuracy: 2,
                       "The dock sat \(resting.midY - mic.frame.midY)pt off its resting place")
        XCTAssertTrue(app.buttons["voice-cancel"].isHittable)
    }

    func testHoldAndReleaseSendsTheTranscript() throws {
        let server = try StubServer()
        try launchRecording(server, segments: [first])
        let mic = app.buttons["voice-microphone"].firstMatch
        XCTAssertTrue(mic.waitForExistence(timeout: 10))

        mic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 4)
        answerLocationPrompt()
        XCTAssertTrue(app.buttons["Draft my reply to Maya"].waitForExistence(timeout: 15))
        XCTAssertEqual(server.prompts, [first])
    }
}
