import Foundation
import Observation

struct CalendarBrowserDay: Hashable, Comparable, Sendable, Codable, Identifiable {
    let year: Int
    let month: Int
    let day: Int
    var id: String { String(format: "%04d-%02d-%02d", year, month, day) }

    init(year: Int, month: Int, day: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard (1...9999).contains(year), let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: year, month: month, day: day)
        else { throw CalendarBrowserSelectionError.invalidDate }
        self.year = year; self.month = month; self.day = day
    }

    init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year!; month = parts.month!; day = parts.day!
    }

    func date(in zone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: year, month: month, day: day)
        else { return nil }
        return date
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.id < rhs.id }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        let pieces = value.split(separator: "-", omittingEmptySubsequences: false)
        guard value.utf8.count == 10, pieces.count == 3, pieces[0].count == 4,
              pieces[1].count == 2, pieces[2].count == 2,
              value.utf8.allSatisfy({ (48...57).contains($0) || $0 == 45 }),
              let y = Int(pieces[0]), let m = Int(pieces[1]), let d = Int(pieces[2])
        else { throw CalendarBrowserSelectionError.invalidDate }
        try self.init(year: y, month: m, day: d)
    }
    func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(id) }
}

enum CalendarBrowserMode: String, CaseIterable, Codable, Sendable { case daily, weekly }
enum CalendarBrowserScope: String, Codable, Sendable { case day, week, month }
enum CalendarBrowserSelectionError: Error, Equatable { case invalidDate, invalidTimeZone }

struct CalendarBrowserSnapshot: Equatable, Hashable, Sendable {
    let selectedDate: CalendarBrowserDay
    let mode: CalendarBrowserMode
    let timeZone: String
    let scope: CalendarBrowserScope
    let startInclusive: Date
    let endExclusive: Date
}

struct CalendarBrowserIntent: Equatable, Sendable {
    enum Reason: String, Sendable { case initial, day, week, month, mode, today, retry }
    let id: UUID
    let selection: CalendarBrowserSnapshot
    let reason: Reason

    var prompt: String {
        let zone = TimeZone(identifier: selection.timeZone)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = zone
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        let subject: String
        switch selection.scope {
        case .day: subject = formatter.string(from: selection.startInclusive)
        case .week:
            subject = "the week of " + formatter.string(from: selection.startInclusive)
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            subject = formatter.string(from: selection.startInclusive)
        }
        return "Show my calendar for \(subject). Use the selected \(selection.timeZone) time zone."
    }
}

@Observable @MainActor
final class CalendarBrowserSelection {
    private(set) var selectedDate: CalendarBrowserDay
    private(set) var mode: CalendarBrowserMode
    private(set) var timeZone: String
    private(set) var scope: CalendarBrowserScope
    var responseScrollAnchor: String?

    init(date: CalendarBrowserDay, mode: CalendarBrowserMode = .daily, timeZone: String) throws {
        guard let zone = TimeZone(identifier: timeZone) else { throw CalendarBrowserSelectionError.invalidTimeZone }
        guard date.date(in: zone) != nil else { throw CalendarBrowserSelectionError.invalidDate }
        selectedDate = date; self.mode = mode; self.timeZone = timeZone
        scope = mode == .daily ? .day : .week
    }

    var zone: TimeZone { TimeZone(identifier: timeZone)! }
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone; calendar.firstWeekday = 1; calendar.minimumDaysInFirstWeek = 1
        return calendar
    }
    var selectedInstant: Date { selectedDate.date(in: zone)! }
    var snapshot: CalendarBrowserSnapshot {
        let component: Calendar.Component = scope == .day ? .day : scope == .week ? .weekOfYear : .month
        let interval = calendar.dateInterval(of: component, for: selectedInstant)!
        return CalendarBrowserSnapshot(selectedDate: selectedDate, mode: mode, timeZone: timeZone, scope: scope,
                                       startInclusive: interval.start, endExclusive: interval.end)
    }

    func intent(_ reason: CalendarBrowserIntent.Reason) -> CalendarBrowserIntent {
        CalendarBrowserIntent(id: UUID(), selection: snapshot, reason: reason)
    }

    func chooseDay(_ day: CalendarBrowserDay) throws -> CalendarBrowserIntent {
        guard day.date(in: zone) != nil else { throw CalendarBrowserSelectionError.invalidDate }
        selectedDate = day; scope = .day; responseScrollAnchor = nil
        return intent(.day)
    }

    func chooseWeek(offset: Int) throws -> CalendarBrowserIntent {
        guard let date = calendar.date(byAdding: .weekOfYear, value: offset, to: selectedInstant) else {
            throw CalendarBrowserSelectionError.invalidDate
        }
        let candidate = CalendarBrowserDay(date: date, timeZone: zone)
        guard (1...9999).contains(candidate.year), candidate.date(in: zone) != nil else { throw CalendarBrowserSelectionError.invalidDate }
        selectedDate = candidate; scope = .week; responseScrollAnchor = nil
        return intent(.week)
    }

    func chooseMode(_ value: CalendarBrowserMode) -> CalendarBrowserIntent {
        mode = value; scope = value == .daily ? .day : .week; responseScrollAnchor = nil
        return intent(.mode)
    }

    func today(now: Date = .now) -> CalendarBrowserIntent {
        selectedDate = CalendarBrowserDay(date: now, timeZone: zone)
        scope = mode == .daily ? .day : .week; responseScrollAnchor = nil
        return intent(.today)
    }

    @discardableResult
    func propose(_ change: (CalendarBrowserSelection) throws -> CalendarBrowserIntent,
                 accepting: (CalendarBrowserIntent) -> Bool) -> Bool {
        guard let candidate = try? CalendarBrowserSelection(date: selectedDate, mode: mode, timeZone: timeZone) else { return false }
        candidate.scope = scope
        candidate.responseScrollAnchor = responseScrollAnchor
        guard let intent = try? change(candidate), accepting(intent) else { return false }
        selectedDate = candidate.selectedDate
        mode = candidate.mode
        timeZone = candidate.timeZone
        scope = candidate.scope
        responseScrollAnchor = candidate.responseScrollAnchor
        return true
    }

    func text(_ day: CalendarBrowserDay, format: String) -> String {
        guard let date = day.date(in: zone) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = zone; formatter.calendar = calendar; formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
