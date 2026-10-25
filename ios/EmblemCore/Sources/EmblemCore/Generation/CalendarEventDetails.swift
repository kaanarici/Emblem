import Foundation

public struct CalendarEventDetails: Codable, Hashable, Sendable {
    public let title: String
    public let dayLabel: String
    public let timeRange: String
    public let place: String?
    public let attendees: [String]?

    public init(title: String, dayLabel: String, timeRange: String, place: String? = nil, attendees: [String]? = nil) {
        self.title = String(title.prefix(200))
        self.dayLabel = String(dayLabel.prefix(80))
        self.timeRange = String(timeRange.prefix(80))
        self.place = place.map { String($0.prefix(200)) }.flatMap { $0.isEmpty ? nil : $0 }
        self.attendees = attendees.map { Array($0.prefix(12).map { String($0.prefix(80)) }) }.flatMap { $0.isEmpty ? nil : $0 }
    }
}
