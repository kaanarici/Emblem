import EventKit
import Foundation
import Observation

@Observable @MainActor
final class CalendarService {
    static let shared = CalendarService()

    enum AddResult: Equatable {
        case saved(Date)
        case uncertain(Date)
        case failed
    }

    enum ReceiptStatus: Equatable {
        case none
        case pending(Date)
        case completed(Date)
    }

    struct NextEvent: Equatable {
        var title: String
        var start: Date
        var joinURL: URL?
    }

    private struct ReceiptRecord: Codable {
        var state: String
        var start: TimeInterval
    }

    private let store = EKEventStore()
    private var activeWrites: Set<String> = []

    func addEvent(
        title: String,
        start: Date,
        durationMinutes: Int = 60,
        idempotencyKey: String
    ) async -> AddResult {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (5...1_440).contains(durationMinutes),
              !idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              idempotencyKey.count <= 200 else { return .failed }
        switch Self.receiptStatus(for: idempotencyKey) {
        case .completed(let savedStart): return .saved(savedStart)
        case .pending(let pendingStart): return .uncertain(pendingStart)
        case .none: break
        }
        Self.recordReceipt(.pending(start), for: idempotencyKey)
        activeWrites.insert(idempotencyKey)
        defer { activeWrites.remove(idempotencyKey) }
        let granted = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        guard granted, !Task.isCancelled else {
            Self.clearReceipt(for: idempotencyKey)
            return .failed
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        event.calendar = store.defaultCalendarForNewEvents
        guard !Task.isCancelled else {
            Self.clearReceipt(for: idempotencyKey)
            return .failed
        }
        do {
            try store.save(event, span: .thisEvent)
            Self.recordReceipt(.completed(start), for: idempotencyKey)
            return .saved(start)
        } catch {
            Self.clearReceipt(for: idempotencyKey)
            return .failed
        }
    }

    func isWriteActive(for idempotencyKey: String) -> Bool {
        activeWrites.contains(idempotencyKey)
    }

    func nextUp() -> NextEvent? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        let now = Date()
        let horizon = now.addingTimeInterval(36 * 3600)
        let predicate = store.predicateForEvents(withStart: now, end: horizon, calendars: nil)
        guard let event = store.events(matching: predicate)
            .filter({ !$0.isAllDay && $0.startDate > now })
            .min(by: { $0.startDate < $1.startDate }),
            let title = event.title
        else { return nil }

        let joinURL = Self.joinURL(for: event)
        return NextEvent(title: title, start: event.startDate, joinURL: joinURL)
    }

    private static func joinURL(for event: EKEvent) -> URL? {
        let candidates = [event.url?.absoluteString, event.notes, event.location]
        for candidate in candidates.compactMap({ $0 }) {
            let range = NSRange(candidate.startIndex..., in: candidate)
            guard let match = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
                .firstMatch(in: candidate, range: range),
                  let url = match.url,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            else { continue }
            return url
        }
        return nil
    }

    static func startDate(date dateString: String, time timeString: String) -> Date? {
        let rawDateParts = dateString.split(separator: "-")
        guard rawDateParts.count == 3,
              let year = Int(rawDateParts[0]),
              let month = Int(rawDateParts[1]),
              let day = Int(rawDateParts[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let formats = ["h:mm a", "HH:mm", "h a"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        for format in formats {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: timeString) {
                let time = calendar.dateComponents([.hour, .minute], from: parsed)
                var components = DateComponents()
                components.calendar = calendar
                components.timeZone = calendar.timeZone
                components.year = year
                components.month = month
                components.day = day
                components.hour = time.hour
                components.minute = time.minute
                guard let date = calendar.date(from: components) else { return nil }
                let resolved = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: date)
                guard resolved.year == components.year,
                      resolved.month == components.month,
                      resolved.day == components.day,
                      resolved.hour == components.hour,
                      resolved.minute == components.minute else { return nil }
                return date
            }
        }
        return nil
    }

    static func receiptStatus(for idempotencyKey: String) -> ReceiptStatus {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: receiptKey(idempotencyKey)),
              let receipt = try? JSONDecoder().decode(ReceiptRecord.self, from: data)
        else { return .none }
        let start = Date(timeIntervalSince1970: receipt.start)
        switch receipt.state {
        case "completed": return .completed(start)
        case "pending": return .pending(start)
        default: return .none
        }
    }

    private static func recordReceipt(_ status: ReceiptStatus, for idempotencyKey: String) {
        let receipt: ReceiptRecord
        switch status {
        case .pending(let date):
            receipt = ReceiptRecord(state: "pending", start: date.timeIntervalSince1970)
        case .completed(let date):
            receipt = ReceiptRecord(state: "completed", start: date.timeIntervalSince1970)
        case .none:
            receipt = ReceiptRecord(state: "none", start: 0)
        }
        guard let data = try? JSONEncoder().encode(receipt) else { return }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: receiptKey(idempotencyKey))
        defaults.synchronize()
    }

    private static func clearReceipt(for idempotencyKey: String) {
        recordReceipt(.none, for: idempotencyKey)
    }

    private static func receiptKey(_ idempotencyKey: String) -> String {
        "calendar.action.receipt.\(idempotencyKey)"
    }
}
