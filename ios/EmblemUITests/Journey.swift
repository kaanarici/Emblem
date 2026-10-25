import Network
import UIKit
import XCTest

@MainActor
class JourneyTestCase: XCTestCase {
    let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        app.terminate()
    }

    func launch(
        _ server: StubServer,
        onboarded: Bool = true,
        fakeHome: Bool = true,
        environment: [String: String] = [:]
    ) {
        app.launchArguments = [
            "-auth.gateCompleted", onboarded ? "YES" : "NO",
            "-voice.muted", "YES",
            "-memory.enabled", "NO",
        ]
        app.launchEnvironment = ["EMBLEM_SERVER_URL": server.url]
            .merging(fakeHome ? ["EMBLEM_FAKE_HOME": "1"] : [:]) { _, new in new }
            .merging(environment) { _, new in new }
        app.launch()
    }

    func tap(_ element: XCUIElement, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(element) never appeared", file: file, line: line)
        XCTAssertTrue(element.isHittable, "\(element) is not hittable", file: file, line: line)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    func send(_ prompt: String) {
        tap(app.buttons["dock-keyboard"], timeout: 12)
        XCTAssertTrue(element("composer-draft").waitForExistence(timeout: 5))
        app.typeText(prompt)
        tap(app.buttons["Send message"])
        answerLocationPrompt()
    }

    func answerLocationPrompt() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        guard alert.waitForExistence(timeout: 2) else { return }
        let allow = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "While Using")).firstMatch
        (allow.exists ? allow : alert.buttons.firstMatch).tap()
    }

    func allowSystemAlert(timeout: TimeInterval = 5) {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else { return }
        let allow = alert.buttons.matching(NSPredicate(
            format: "NOT (label BEGINSWITH[c] 'Don') AND (label CONTAINS[c] 'Allow' OR label CONTAINS[c] 'Add' OR label ==[c] 'OK')"))
            .firstMatch
        (allow.exists ? allow : alert.buttons.element(boundBy: alert.buttons.count - 1)).tap()
    }

    func openSidebar() {
        tap(app.buttons["Open menu"].firstMatch)
        XCTAssertTrue(app.buttons["sidebar-settings"].waitForExistence(timeout: 5))
    }
}

final class StubServer: @unchecked Sendable {
    struct GoogleEvent {
        let title: String
        let start: Date
        var minutes = 60
    }

    struct Conversation {
        let key: String
        let title: String
        let fixture: String
        var pinned = false
        var pages = 1
        var artwork = false
    }

    private let listener: NWListener
    private let lock = NSLock()
    private var replies: [String]
    private var history: [Conversation]
    private let listPageSize: Int
    private let google: [GoogleEvent]
    private var received: [String] = []
    private(set) var url = ""

    var prompts: [String] { lock.withLock { received } }
    var pinnedKeys: [String] { lock.withLock { history.filter(\.pinned).map(\.key) } }

    init(replies: [String] = ["natural-evidence"], history: [Conversation] = [], listPageSize: Int = 50,
         google: [GoogleEvent] = []) throws {
        self.google = google
        self.replies = replies
        self.history = history
        self.listPageSize = listPageSize
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.newConnectionHandler = { [unowned self] connection in
            connection.start(queue: .global(qos: .userInitiated))
            receive(connection, buffered: Data())
        }
        listener.start(queue: .global(qos: .userInitiated))
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port else {
            throw URLError(.cannotConnectToHost)
        }
        url = "http://127.0.0.1:\(port.rawValue)"
    }

    deinit { listener.cancel() }

    static func blocks(_ fixture: String) -> [String] {
        let fixtures = URL(filePath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Emblem/Fixtures/\(fixture).json")
        let lines = (try? String(contentsOf: fixtures, encoding: .utf8)) ?? ""
        return lines.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, ended, error in
            let request = buffered + (data ?? Data())
            guard error == nil, let boundary = request.range(of: Data("\r\n\r\n".utf8)) else {
                if error == nil, !ended { receive(connection, buffered: request) } else { connection.cancel() }
                return
            }
            let head = String(decoding: request[..<boundary.lowerBound], as: UTF8.self)
            let length = head.split(separator: "\r\n")
                .first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.dropFirst(15).trimmingCharacters(in: .whitespaces)) } ?? 0
            guard request.count >= boundary.upperBound + length else {
                if ended { connection.cancel() } else { receive(connection, buffered: request) }
                return
            }
            let target = head.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let body = request[boundary.upperBound..<(boundary.upperBound + length)]
            let (type, payload) = respond(to: URLComponents(string: target), body: Data(body))
            let status = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(status.utf8) + payload, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func respond(to target: URLComponents?, body: Data) -> (String, Data) {
        if let path = target?.path, path.hasPrefix("/art/") {
            return ("image/png", Self.artwork(seed: path.unicodeScalars.reduce(0) { $0 + Int($1.value) }))
        }
        let (type, text) = respondText(to: target, body: body)
        return (type, Data(text.utf8))
    }

    private func respondText(to target: URLComponents?, body: Data) -> (String, String) {
        switch target?.path {
        case "/api/generate":
            let fixture = lock.withLock {
                received.append(Self.prompt(in: body))
                return replies.count > 1 ? replies.removeFirst() : replies[0]
            }
            let blocks = Self.blocks(fixture)
            return ("application/x-ndjson", """
                {"type":"status","text":"Putting it together…"}
                {"type":"pageSnapshot","id":"page-snapshot","revision":1,"blocks":[\(blocks.joined(separator: ","))]}
                {"type":"terminal","status":"completed","revision":1,"blockCount":\(blocks.count),"persisted":false}

                """)
        case "/api/calendar/events":
            guard !google.isEmpty else { return ("application/json", #"{"google":{"state":"notConnected","accounts":[]},"events":[]}"#) }
            let iso = ISO8601DateFormatter()
            let rows = google.enumerated().map { index, event in
                let end = event.start.addingTimeInterval(Double(event.minutes * 60))
                return #"{"id":"g\#(index)","iCalUID":null,"title":"\#(event.title)","start":"\#(iso.string(from: event.start))","end":"\#(iso.string(from: end))","allDay":false,"location":null,"calendar":"Work","color":null,"account":"sam@example.com","url":null,"attendees":[]}"#
            }
            return ("application/json", #"{"google":{"state":"connected","accounts":[{"email":"sam@example.com","state":"ok"}]},"events":[\#(rows.joined(separator: ","))]}"#)
        case "/api/conversation":
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: String] ?? [:]
            lock.withLock {
                guard let index = history.firstIndex(where: { $0.key == json["conversationKey"] }) else { return }
                if json["action"] == "pin" { history[index].pinned = true }
                if json["action"] == "unpin" { history[index].pinned = false }
            }
            return ("application/json", "{}")
        case "/api/conversations":
            let now = Int(Date().timeIntervalSince1970 * 1000)
            let row = { (index: Int, item: Conversation) in
                let pin = item.pinned ? #","pinnedAt":\#(now)"# : ""
                let art = item.artwork ? #","image":{"query":"\#(item.title)","kind":"photo"},"imageURL":"\#(self.url)/art/\#(item.key).png""# : ""
                return #"{"key":"\#(item.key)","title":"\#(item.title)","updatedAt":\#(now - index * 60_000),"archived":false\#(pin)\#(art),"preview":"\#(item.title)"}"#
            }
            let history = lock.withLock { self.history }
            let offset = Int(Self.query("cursor", in: target) ?? "") ?? 0
            let unpinned = Array(history.enumerated().filter { !$0.element.pinned })
            let page = unpinned.dropFirst(offset).prefix(listPageSize)
            let pinned = offset == 0 ? history.enumerated().filter(\.element.pinned).map(row) : []
            let next = offset + page.count < unpinned.count ? #""\#(offset + page.count)""# : "null"
            return ("application/json", #"{"pinned":[\#(pinned.joined(separator: ","))],"conversations":[\#(page.map(row).joined(separator: ","))],"nextCursor":\#(next)}"#)
        case "/api/history":
            guard let item = lock.withLock({ history }).first(where: { $0.key == Self.query("conversationKey", in: target) }) else {
                return ("application/json", #"{"pages":[],"nextCursor":null}"#)
            }
            guard item.pages > 1 else {
                let blocks = Self.blocks(item.fixture).joined(separator: ",")
                return ("application/json", #"{"pages":[{"prompt":"\#(item.title)","title":"\#(item.title)","blocks":[\#(blocks)]}],"nextCursor":null}"#)
            }
            let newest = Int(Self.query("cursor", in: target) ?? "") ?? item.pages
            let pages = (max(1, newest - 2)...newest).map { index in
                let previous = index > 1 ? #","previousPageKey":"\#(item.key)-\#(index - 1)""# : ""
                return #"{"pageKey":"\#(item.key)-\#(index)"\#(previous),"prompt":"\#(item.title) \#(index)","title":"\#(item.title)","blocks":[{"type":"text","id":"intro","style":"intro","body":"\#(item.title) page \#(index)."}]}"#
            }
            let next = newest > 3 ? #""\#(newest - 3)""# : "null"
            return ("application/json", #"{"pages":[\#(pages.joined(separator: ","))],"nextCursor":\#(next)}"#)
        default:
            return ("application/json", #"{"enabled":false,"toolkits":[],"agents":[],"pinned":[],"conversations":[],"pages":[],"nextCursor":null}"#)
        }
    }

    private static func artwork(seed: Int) -> Data {
        let hues: [CGFloat] = [0.58, 0.08, 0.36, 0.83, 0.15]
        let hue = hues[seed % hues.count]
        let size = CGSize(width: 330, height: 428)
        return UIGraphicsImageRenderer(size: size).pngData { context in
            let colors = [UIColor(hue: hue, saturation: 0.55, brightness: 0.85, alpha: 1).cgColor,
                          UIColor(hue: hue + 0.08, saturation: 0.7, brightness: 0.45, alpha: 1).cgColor]
            guard let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 1]) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
    }

    private static func query(_ name: String, in target: URLComponents?) -> String? {
        target?.queryItems?.first { $0.name == name }?.value
    }

    private static func prompt(in body: Data) -> String {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let messages = json?["messages"] as? [[String: Any]] ?? []
        return messages.last { $0["role"] as? String == "user" }?["content"] as? String ?? ""
    }
}
