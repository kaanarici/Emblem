import XCTest

final class CalendarJourneyTests: JourneyTestCase {
    func testCalendarPagesToThePreviousDayAndBack() throws {
        let server = try StubServer(replies: ["calendardaily"])
        launch(server)

        tap(app.buttons["home-calendar"], timeout: 10)
        answerLocationPrompt()
        XCTAssertTrue(app.staticTexts["Morning run club"].waitForExistence(timeout: 15))
        let today = day(offset: 0), yesterday = day(offset: -1)
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertTrue(today.isSelected)

        flick(towardPrevious: true)
        XCTAssertTrue(yesterday.waitForExistence(timeout: 5))
        expectSelected(yesterday)
        XCTAssertTrue(app.staticTexts["Morning run club"].waitForExistence(timeout: 15))

        flick(towardPrevious: false)
        expectSelected(today)
    }

    private func day(offset: Int) -> XCUIElement {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return app.buttons["calendar-day-\(formatter.string(from: date))"]
    }

    private func expectSelected(_ day: XCUIElement) {
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: day)
        wait(for: [selected], timeout: 5)
    }

    private func flick(towardPrevious: Bool) {
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.55))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.55))
        let (from, to) = towardPrevious ? (left, right) : (right, left)
        from.press(forDuration: 0.02, thenDragTo: to, withVelocity: 2400, thenHoldForDuration: 0)
    }
}
