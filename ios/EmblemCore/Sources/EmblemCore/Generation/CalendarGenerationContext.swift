import Foundation

public struct CalendarGenerationContext: Codable, Equatable, Hashable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable { case daily, weekly, monthly }
    enum ValidationError: Error { case invalidDate, invalidTimeZone }

    public let date: String
    public let timeZone: String
    public let mode: Mode

    public init(date: String, timeZone: String, mode: Mode) throws {
        guard timeZone == "UTC" || TimeZone.knownTimeZoneIdentifiers.contains(timeZone),
              let zone = TimeZone(identifier: timeZone)
        else { throw ValidationError.invalidTimeZone }
        let bytes = Array(date.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ index, byte in
                  index == 4 || index == 7 || (48...57).contains(byte)
              }),
              let year = Int(date.prefix(4)), (1...9999).contains(year),
              let month = Int(date.dropFirst(5).prefix(2)),
              let day = Int(date.suffix(2))
        else { throw ValidationError.invalidDate }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let instant = calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: 12)),
              calendar.component(.year, from: instant) == year,
              calendar.component(.month, from: instant) == month,
              calendar.component(.day, from: instant) == day
        else { throw ValidationError.invalidDate }
        self.date = date
        self.timeZone = timeZone
        self.mode = mode
    }

    private enum CodingKeys: String, CodingKey { case date, timeZone, mode }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(date: values.decode(String.self, forKey: .date),
                      timeZone: values.decode(String.self, forKey: .timeZone),
                      mode: values.decode(Mode.self, forKey: .mode))
    }
}
