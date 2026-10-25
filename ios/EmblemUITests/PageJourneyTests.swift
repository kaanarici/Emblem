import XCTest

final class PageJourneyTests: JourneyTestCase {
    func testDrillInOpensOnTheCardImageThenCrossfadesToItsOwnCover() throws {
        let server = try StubServer(replies: ["cover-browse", "cover-detail"])
        launch(server)
        send("Which Kyoto temples are worth it?")

        let card = app.staticTexts["Kinkaku-ji"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        tap(card)
        var frames: [(cover: Cover, edge: CGFloat?)] = []
        let opened = Date()
        while Date().timeIntervalSince(opened) < 3 {
            let shot = XCUIScreen.main.screenshot()
            frames.append(coverFrame(in: shot))
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = String(format: "cover-frame-%02d-%@", frames.count, "\(frames[frames.count - 1].cover)")
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let covers = frames.map(\.cover)
        let shown = covers.filter { $0 != .other }
        XCTAssertEqual(shown.first, .card, "The drill-in did not open on the card's image: \(covers)")
        XCTAssertEqual(shown.last, .refreshed, "The drill-in never showed its own cover: \(covers)")
        guard let firstBlend = covers.firstIndex(of: .blend), firstBlend > 0,
              let firstRefreshed = covers.firstIndex(of: .refreshed), firstBlend < firstRefreshed else {
            return XCTFail("The cover cut instead of crossfading: \(covers)")
        }
        XCTAssertEqual(covers[firstBlend - 1], .card, "The crossfade did not start from the card's image: \(covers)")
        let edges = Set(frames[(firstBlend - 1)...].map(\.edge))
        XCTAssertEqual(edges.count, 1, "The cover swap moved the page: \(edges)")
    }

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

    enum Cover { case card, blend, refreshed, other }

    private func coverFrame(in shot: XCUIScreenshot) -> (cover: Cover, edge: CGFloat?) {
        guard let image = shot.image.cgImage,
              let strip = image.cropping(to: CGRect(x: image.width / 2, y: 0, width: 1, height: image.height))
        else { return (.other, nil) }
        let scale = CGFloat(image.width) / app.frame.width
        var rgba = [UInt8](repeating: 0, count: image.height * 4)
        rgba.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: 1, height: image.height, bitsPerComponent: 8, bytesPerRow: 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .draw(strip, in: CGRect(x: 0, y: 0, width: 1, height: image.height))
        }
        func color(atPoint y: Int) -> (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
            let offset = Int(CGFloat(y) * scale) * 4
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            UIColor(red: CGFloat(rgba[offset]) / 255, green: CGFloat(rgba[offset + 1]) / 255,
                    blue: CGFloat(rgba[offset + 2]) / 255, alpha: 1)
                .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
            return (hue, saturation, brightness)
        }
        let edge = (150..<600).first {
            let paper = color(atPoint: $0)
            return paper.saturation < 0.1 && paper.brightness > 0.9
        }.map(CGFloat.init)
        let sample = color(atPoint: 250)
        let cover: Cover = switch sample.saturation > 0.2 ? sample.hue : -1 {
        case 0.3..<0.47: .card
        case 0.47..<0.55: .blend
        case 0.55..<0.72: .refreshed
        default: .other
        }
        return (cover, edge)
    }
}
