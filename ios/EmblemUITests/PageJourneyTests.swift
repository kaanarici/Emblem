import XCTest

final class PageJourneyTests: JourneyTestCase {
    func testCardDrillInOpensAndClosesBackToItsCard() throws {
        let server = try StubServer(replies: ["browse", "detail"])
        launch(server)
        send("Which shows return in 2026?")

        let card = app.staticTexts["Will Trent"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        let resting = card.frame
        let row = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: resting.midX, dy: resting.midY))
        row.press(forDuration: 0.05, thenDragTo: row.withOffset(CGVector(dx: -220, dy: 0)))
        XCTAssertFalse(element("expansion-page").waitForExistence(timeout: 1), "A carousel pan opened a card")
        XCTAssertLessThan(card.frame.minX, resting.minX - 100, "The carousel did not take the horizontal pan")
        row.withOffset(CGVector(dx: -220, dy: 0)).press(forDuration: 0.05, thenDragTo: row)
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertEqual(card.frame.minX, resting.minX, accuracy: 2, "The carousel did not return to its first card")

        tap(card)
        XCTAssertTrue(element("expansion-page").waitForExistence(timeout: 3))
        XCTAssertTrue(text(containing: "grief soaked therapy dramedy").waitForExistence(timeout: 15))
        tap(app.buttons["Close"])
        XCTAssertTrue(element("expansion-page").waitForNonExistence(timeout: 3))
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertEqual(card.frame.minY, resting.minY, accuracy: 2, "Closing the drill-in moved the page")
    }

    func testDraggingADrillInDownShrinksItBackIntoItsCard() throws {
        let server = try StubServer(replies: ["browse", "detail"])
        launch(server)
        send("Which shows return in 2026?")

        let card = app.staticTexts["Will Trent"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        let resting = card.frame
        let page = element("expansion-page")
        let grip = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))

        tap(card)
        XCTAssertTrue(page.waitForExistence(timeout: 3))
        XCTAssertTrue(text(containing: "grief soaked therapy dramedy").waitForExistence(timeout: 15))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 0, dy: 40)),
                   withVelocity: 120, thenHoldForDuration: 0.3)
        XCTAssertFalse(page.waitForNonExistence(timeout: 2), "A short pull closed the drill-in instead of springing back")

        for (speed, sideways) in [(XCUIGestureVelocity(400), 0.0), (XCUIGestureVelocity(1400), 90.0)] {
            if !page.exists {
                tap(card)
                XCTAssertTrue(page.waitForExistence(timeout: 3))
            }
            Thread.sleep(forTimeInterval: 1)
            grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: sideways, dy: 320)),
                       withVelocity: speed, thenHoldForDuration: 0)
            XCTAssertTrue(page.waitForNonExistence(timeout: 3), "Dragging down at \(speed.rawValue) pt/s did not close the drill-in")
            XCTAssertTrue(card.waitForExistence(timeout: 3))
            XCTAssertEqual(card.frame.minY, resting.minY, accuracy: 2, "The drill-in did not return to its card")
        }
    }

    func testComparisonExpandsAndClosesInPlace() throws {
        let server = try StubServer(replies: ["butter"])
        launch(server)
        send("Brown butter or regular butter?")

        let expand = app.buttons["comparison-expand-butter"]
        XCTAssertTrue(expand.waitForExistence(timeout: 15))
        let page = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        page.press(forDuration: 0.05, thenDragTo: page.withOffset(CGVector(dx: 0, dy: -260)))
        let resting = expand.frame
        XCTAssertLessThan(resting.maxY, app.buttons["dock-keyboard"].frame.minY - 16, "The dock covers the expand control")
        tap(expand)
        let close = app.buttons["Close comparison"]
        XCTAssertTrue(close.waitForExistence(timeout: 4))
        XCTAssertTrue(element("expanded-comparison").exists)

        tap(close)
        XCTAssertTrue(close.waitForNonExistence(timeout: 3))
        XCTAssertEqual(expand.frame.minY, resting.minY, accuracy: 2, "Closing the comparison moved the page")
    }

    func testWeatherDaySwitchesInPlace() throws {
        let server = try StubServer(replies: ["weather"])
        launch(server)
        send("Weather in San Francisco")

        XCTAssertTrue(element("weather-hourly-weather-1").waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Now"].exists)
        let page = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        page.press(forDuration: 0.05, thenDragTo: page.withOffset(CGVector(dx: 0, dy: -560)))
        let monday = app.buttons["weather-day-2026-10-26"]
        tap(monday)
        XCTAssertTrue(text(containing: "Monday · Rain").waitForExistence(timeout: 3))
        XCTAssertTrue(monday.isSelected)
        XCTAssertFalse(app.staticTexts["Now"].exists)
        XCTAssertFalse(element("expansion-page").exists)
        XCTAssertFalse(app.buttons["Close"].exists, "Tapping a day pushed a new page")
        XCTAssertEqual(server.prompts.count, 1, "Tapping a day asked the server again")

        tap(app.buttons["weather-day-2026-10-25"])
        XCTAssertTrue(app.staticTexts["Now"].waitForExistence(timeout: 3))
        XCTAssertFalse(monday.isSelected)
    }
}
