import XCTest

final class CalendarJourneyTests: JourneyTestCase {
    func testGoogleOnlyEventsShowAndPageByDay() throws {
        let start = Calendar.current.startOfDay(for: Date())
        let at = { (days: Int, hour: Int) in start.addingTimeInterval(Double(days * 86_400 + hour * 3_600)) }
        let server = try StubServer(google: [
            .init(title: "Design review", start: Date().addingTimeInterval(-600)),
            .init(title: "Dentist", start: at(1, 10)),
            .init(title: "Coffee with Ana", start: at(-1, 15), minutes: 30),
            .init(title: "Offsite", start: at(7, 11)),
        ], googleFailures: 2)
        app.resetAuthorizationStatus(for: .calendar)
        app.resetAuthorizationStatus(for: .reminders)
        launch(server)

        tap(app.buttons["home-calendar"], timeout: 10)
        XCTAssertTrue(googleEvent(0).waitForExistence(timeout: 15))
        XCTAssertFalse(element("calendar-notice").exists, "A retried Google load showed an error")
        XCTAssertTrue(day(offset: 0).isSelected)

        flick(towardPrevious: false)
        expectSelected(day(offset: 1))
        XCTAssertTrue(googleEvent(1).waitForExistence(timeout: 5))

        flick(towardPrevious: true)
        flick(towardPrevious: true)
        expectSelected(day(offset: -1))
        XCTAssertTrue(googleEvent(2).waitForExistence(timeout: 5))
        XCTAssertFalse(element("calendar-notice").exists, "Paging showed a Google error")

        tap(app.buttons["calendar-go-to-today"])
        expectSelected(day(offset: 0))
        tap(onScreen("calendar-next-day"))
        expectSelected(day(offset: 1))

        swipeStrip(towardPrevious: false)
        expectSelected(day(offset: 8))
        swipeStrip(towardPrevious: true)
        expectSelected(day(offset: 1))
        swipeStrip(towardPrevious: false)
        expectSelected(day(offset: 8))
        flick(towardPrevious: true)
        expectSelected(day(offset: 7))
        XCTAssertTrue(googleEvent(3).waitForExistence(timeout: 5))
    }

    func testAddingAnEventFromTheDockSavesItToTheCalendar() throws {
        let server = try StubServer()
        app.resetAuthorizationStatus(for: .calendar)
        app.resetAuthorizationStatus(for: .reminders)
        launch(server)

        tap(app.buttons["home-calendar"], timeout: 10)
        allowCalendarAndReminders()
        send("Lunch with Sam tomorrow at 1pm")
        expectSelected(day(offset: 1))
        let title = element("calendar-draft-title")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Lunch with Sam")

        tap(element("calendar-draft-save"))
        XCTAssertTrue(text(containing: "Added Lunch with Sam tomorrow at 1 PM").waitForExistence(timeout: 5))
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-event-' AND label CONTAINS 'Lunch with Sam'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        tap(app.buttons["Undo"])
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
    }

    func testAddingAToDoAndCheckingItOff() throws {
        let server = try StubServer()
        app.resetAuthorizationStatus(for: .calendar)
        app.resetAuthorizationStatus(for: .reminders)
        launch(server)

        tap(app.buttons["home-calendar"], timeout: 10)
        allowCalendarAndReminders()
        tap(app.buttons["Add to-do"])
        tap(element("calendar-draft-title"))
        let name = "Call the bank \(Int.random(in: 1_000...9_999))"
        app.typeText(name + "\n")
        tap(element("calendar-draft-save"))
        XCTAssertTrue(text(containing: "Added \(name) today").waitForExistence(timeout: 5))

        let todo = app.buttons[name]
        XCTAssertTrue(todo.waitForExistence(timeout: 5))
        XCTAssertEqual(todo.value as? String, "Not done")
        tap(todo)
        expectValue(todo, "Done")
    }

    private func allowCalendarAndReminders() {
        tap(onScreen("calendar-notice-action"))
        allowSystemAlert()
        allowSystemAlert()
        XCTAssertTrue(element("calendar-notice").waitForNonExistence(timeout: 5))
    }

    private func onScreen(_ identifier: String) -> XCUIElement {
        let matches = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 8))
        return matches.allElementsBoundByIndex.first(where: \.isHittable) ?? matches.firstMatch
    }

    private func googleEvent(_ index: Int) -> XCUIElement {
        element("calendar-event-google:sam@example.com:g\(index)")
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

    private func expectValue(_ element: XCUIElement, _ value: String) {
        let matched = expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)
        wait(for: [matched], timeout: 5)
    }

    private func swipeStrip(towardPrevious: Bool) {
        let strip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-day-'")).firstMatch
        let y = strip.frame.midY / app.frame.height
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: y))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: y))
        let (from, to) = towardPrevious ? (left, right) : (right, left)
        from.press(forDuration: 0.02, thenDragTo: to, withVelocity: 1600, thenHoldForDuration: 0)
    }

    private func flick(towardPrevious: Bool) {
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.55))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.55))
        let (from, to) = towardPrevious ? (left, right) : (right, left)
        from.press(forDuration: 0.02, thenDragTo: to, withVelocity: 2400, thenHoldForDuration: 0)
    }
}
