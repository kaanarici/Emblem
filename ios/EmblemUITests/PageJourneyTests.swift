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
}
