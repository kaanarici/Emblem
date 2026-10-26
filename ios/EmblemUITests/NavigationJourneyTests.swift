import XCTest

final class NavigationJourneyTests: JourneyTestCase {
    func testSidebarReopensAPastConversationAndBackReturnsHome() throws {
        let server = try StubServer(history: [.init(key: "launch-day", title: "Launch day", fixture: "natural-evidence")])
        launch(server)
        XCTAssertTrue(element("home-greeting").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["sidebar-settings"].exists, "The closed sidebar is still in the accessibility tree")

        openSidebar()
        tap(app.buttons["sidebar-conversation-launch-day"])
        XCTAssertTrue(text(containing: "Your launch review begins at 2:00 PM").waitForExistence(timeout: 10))
        XCTAssertTrue(server.prompts.isEmpty, "Reopening a conversation generated a new page")

        tap(app.buttons["conversation-back"])
        XCTAssertTrue(element("home-greeting").waitForExistence(timeout: 5))
    }

    func testHomeRecentChatsPutPinsFirstAndOpenTheConversation() throws {
        let server = try StubServer(history: [
            .init(key: "launch-day", title: "Launch day", fixture: "natural-evidence"),
            .init(key: "kept", title: "Kept chat", fixture: "butter", pinned: true),
        ])
        launch(server)
        let pinned = element("home-recent-kept")
        let recent = element("home-recent-launch-day")
        XCTAssertTrue(pinned.waitForExistence(timeout: 10), "Home shows no recent chats")
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        XCTAssertLessThan(pinned.frame.minX, recent.frame.minX, "The pin is not first")
        XCTAssertEqual(pinned.label.components(separatedBy: "Kept chat").count, 2, "The preview repeats the title")
        let unpin = element("home-unpin-kept")
        tap(unpin)
        XCTAssertTrue(unpin.waitForNonExistence(timeout: 3), "The pin badge stayed after unpinning")
        XCTAssertGreaterThan(pinned.frame.minX, recent.frame.minX, "The unpinned chat did not move behind the newer one")
        if !recent.isHittable {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -260)))
        }
        tap(recent)
        XCTAssertTrue(text(containing: "Your launch review begins at 2:00 PM").waitForExistence(timeout: 10))
        XCTAssertTrue(server.prompts.isEmpty, "Opening a recent chat generated a new page")
        XCTAssertFalse(server.pinnedKeys.contains("kept"), "Unpinning never reached the server")
    }

    func testSidebarKeepsPinsFirstAndLoadsOlderConversationsAsItScrolls() throws {
        let history = (1...30).map { StubServer.Conversation(key: "chat-\($0)", title: "Chat \($0)", fixture: "natural-evidence") }
            + [.init(key: "kept", title: "Kept chat", fixture: "natural-evidence", pinned: true)]
        let server = try StubServer(history: history, listPageSize: 12)
        launch(server)
        XCTAssertTrue(element("home-greeting").waitForExistence(timeout: 10))
        openSidebar()
        let pinned = app.buttons["sidebar-conversation-kept"]
        XCTAssertTrue(pinned.waitForExistence(timeout: 8))
        XCTAssertLessThan(pinned.frame.minY, app.buttons["sidebar-conversation-chat-1"].frame.minY, "The pin is not first")
        let chat = app.buttons["sidebar-conversation-chat-3"]
        chat.press(forDuration: 1.2)
        tap(app.buttons["Pin"])
        XCTAssertTrue(app.buttons["Pin"].waitForNonExistence(timeout: 3), "The first tap on Pin did nothing")
        XCTAssertLessThan(chat.frame.minY, app.buttons["sidebar-conversation-chat-1"].frame.minY, "Pinning did not move the chat up")
        let home = app.buttons.matching(NSPredicate(format: "label == 'Home'")).firstMatch
        let homeTop = home.frame.minY
        let oldest = app.buttons["sidebar-conversation-chat-30"]
        for _ in 0..<15 where !oldest.exists {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)))
        }
        XCTAssertTrue(oldest.exists, "The oldest conversation never loaded")
        XCTAssertEqual(home.frame.minY, homeTop, accuracy: 1, "Home scrolled away with the chats")
    }

    func testSidebarSearchFindsAnOlderChatAndCancelRestoresTheList() throws {
        let history = (1...30).map { StubServer.Conversation(key: "chat-\($0)", title: "Chat \($0)", fixture: "natural-evidence") }
            + [.init(key: "lisbon", title: "Weekend in Lisbon", fixture: "natural-evidence")]
        let server = try StubServer(history: history, listPageSize: 12)
        launch(server)
        XCTAssertTrue(element("home-greeting").waitForExistence(timeout: 10))
        openSidebar()
        XCTAssertTrue(app.buttons["sidebar-conversation-chat-1"].waitForExistence(timeout: 8))
        let menu = app.buttons["Open menu"].firstMatch
        XCTAssertEqual(app.buttons["sidebar-search"].frame.midY, menu.frame.midY, accuracy: 1, "The header is off the menu row")

        tap(app.buttons["sidebar-search"])
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Search did not focus the field")
        app.typeText("lisbon")
        let older = app.buttons["sidebar-conversation-lisbon"]
        XCTAssertTrue(older.waitForExistence(timeout: 8), "Search never paged to the older chat")
        XCTAssertFalse(app.buttons["sidebar-conversation-chat-1"].exists, "Search did not filter the list")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == 'Home'")).firstMatch.exists)

        tap(app.buttons["sidebar-search"])
        XCTAssertTrue(app.buttons["sidebar-conversation-chat-1"].waitForExistence(timeout: 5), "Cancel did not restore the list")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Home'")).firstMatch.exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "The keyboard stayed after cancel")

        tap(app.buttons["sidebar-search"])
        app.typeText("lisbon")
        tap(older)
        XCTAssertTrue(text(containing: "Your launch review begins at 2:00 PM").waitForExistence(timeout: 10))
        XCTAssertTrue(server.prompts.isEmpty, "Opening a search result generated a new page")
    }

    func testLongConversationGoesBackToItsFirstPage() throws {
        let server = try StubServer(history: [.init(key: "long", title: "Long chat", fixture: "natural-evidence", pages: 7)])
        launch(server)
        XCTAssertTrue(element("home-greeting").waitForExistence(timeout: 10))
        openSidebar()
        tap(app.buttons["sidebar-conversation-long"])
        XCTAssertTrue(text(containing: "Long chat page 7.").waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 3)
        for page in stride(from: 6, through: 1, by: -1) {
            tap(app.buttons["conversation-back"])
            let body = text(containing: "Long chat page \(page).")
            XCTAssertTrue(body.waitForExistence(timeout: 10), "Page \(page) is unreachable")
            XCTAssertTrue(body.isHittable, "Page \(page) rendered blank")
        }
        tap(app.buttons["conversation-back"])
        XCTAssertTrue(element("home-greeting").waitForExistence(timeout: 5))
    }

    func testSettingsOpensFromSidebarPushesASubpageAndReturnsHome() throws {
        let server = try StubServer()
        launch(server)
        XCTAssertTrue(element("home-greeting").waitForExistence(timeout: 10))

        openSidebar()
        let settings = app.buttons["sidebar-settings"]
        XCTAssertGreaterThan(settings.frame.minY, app.frame.height * 0.8, "Settings is out of thumb reach")
        XCTAssertLessThan(settings.frame.maxX, app.frame.width / 2, "Settings is not the bottom-left button")
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 6))

        let row = app.buttons["Runs on"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        if !row.isHittable { app.swipeUp() }
        tap(row)
        XCTAssertTrue(app.navigationBars["Runs on"].waitForExistence(timeout: 5))
        tap(app.navigationBars["Runs on"].buttons.firstMatch)
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        openSidebar()
        tap(app.buttons.matching(NSPredicate(format: "label == 'Home'")).firstMatch)
        XCTAssertTrue(element("home-greeting").waitForExistence(timeout: 6))
    }

    func testChatHistoryDeletesSeveralChatsInOneRequest() throws {
        let server = try StubServer(history: (1...6).map {
            StubServer.Conversation(key: "chat-\($0)", title: "Chat \($0)", fixture: "natural-evidence")
        })
        launch(server)
        XCTAssertTrue(element("home-greeting").waitForExistence(timeout: 10))
        openSidebar()
        tap(app.buttons["sidebar-settings"])
        tap(app.buttons["Chat history"].firstMatch, timeout: 6)
        XCTAssertTrue(element("chat-chat-1").waitForExistence(timeout: 8), "Chat history listed nothing")

        tap(app.buttons["chats-select"])
        let doomed = ["chat-1", "chat-3", "chat-5"]
        for key in doomed { tap(element("chat-\(key)")) }
        XCTAssertTrue(app.navigationBars["3 Selected"].waitForExistence(timeout: 3), "The rows were not selected")
        tap(app.buttons["chats-delete"])
        tap(app.buttons["Delete 3 Chats"])

        for key in doomed {
            XCTAssertTrue(element("chat-\(key)").waitForNonExistence(timeout: 3), "\(key) stayed in the list")
        }
        XCTAssertTrue(element("chat-chat-2").exists)
        XCTAssertTrue(element("chats-undo-toast").exists, "Deleting offered no undo")
        let sent = expectation(for: NSPredicate { _, _ in
            server.conversationChanges.contains { $0.action == "delete" }
        }, evaluatedWith: nil)
        wait(for: [sent], timeout: 10)
        let deletes = server.conversationChanges.filter { $0.action == "delete" }
        XCTAssertEqual(deletes.count, 1, "The chats were not deleted in one request")
        XCTAssertEqual(Set(deletes.first?.keys ?? []), Set(doomed))
    }

    func testHomeThatFailsToLoadStillGreetsAndOffersRetry() throws {
        let server = try StubServer()
        launch(server, fakeHome: false)
        XCTAssertTrue(element("home-greeting").waitForExistence(timeout: 10), "Home rendered no greeting while its feed failed")
        let retry = element("home-refresh-toast").buttons["Retry"]
        tap(retry, timeout: 10)
        XCTAssertTrue(element("home-refresh-toast").waitForExistence(timeout: 10), "A second failure showed no toast")
        XCTAssertTrue(element("home-greeting").exists)
    }
}
