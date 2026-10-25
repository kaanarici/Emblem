import EmblemCore
import SwiftUI

struct CalendarGoogleResponse: Decodable, Sendable {
    struct Google: Decodable, Sendable {
        let state: String
        let accounts: [Account]
    }

    struct Account: Decodable, Sendable {
        let email: String
        let state: String
    }

    struct Event: Decodable, Sendable {
        let id: String
        let iCalUID: String?
        let title: String
        let start: String
        let end: String
        let allDay: Bool
        let location: String?
        let color: String?
        let account: String
        let url: String?
        let attendees: [String]
    }

    let google: Google
    let events: [Event]
}

enum CalendarGoogleState: Equatable {
    case unknown, notConnected, connected, unavailable, offline
    case partial(failed: [String])
}

enum CalendarGoogleSource {
    static let tint = Color(red: 0.26, green: 0.52, blue: 0.96)

    static func fetch(_ interval: DateInterval) async throws -> CalendarGoogleResponse {
        let iso = ISO8601DateFormatter()
        let data = try await GenerateClient.fetchJSON(path: "api/calendar/events", query: [
            URLQueryItem(name: "start", value: iso.string(from: interval.start)),
            URLQueryItem(name: "end", value: iso.string(from: interval.end)),
            URLQueryItem(name: "timeZone", value: TimeZone.current.identifier),
        ])
        return try JSONDecoder().decode(CalendarGoogleResponse.self, from: data)
    }

    static func state(_ response: CalendarGoogleResponse) -> CalendarGoogleState {
        switch response.google.state {
        case "connected":
            let failed = response.google.accounts.filter { $0.state != "ok" }.map(\.email)
            return failed.isEmpty ? .connected : .partial(failed: failed)
        case "unavailable": return .unavailable
        default: return .notConnected
        }
    }

    static func events(_ response: CalendarGoogleResponse, calendar: Calendar) -> [CalendarAgendaEvent] {
        let iso = ISO8601DateFormatter()
        let day = DateFormatter()
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return response.events.compactMap { event in
            let parse = { (value: String) in event.allDay ? day.date(from: value) : iso.date(from: value) }
            guard let start = parse(event.start), let end = parse(event.end), end >= start else { return nil }
            return CalendarAgendaEvent(
                id: "google:\(event.account):\(event.id)", title: event.title,
                place: event.location?.split(separator: "\n").first.map(String.init),
                start: start, end: end, isAllDay: event.allDay,
                tint: Theme.color(hex: event.color) ?? tint, attendees: event.attendees,
                source: .google(account: event.account, url: event.url.flatMap(URL.init(string:))),
                externalID: event.iCalUID)
        }
    }
}
