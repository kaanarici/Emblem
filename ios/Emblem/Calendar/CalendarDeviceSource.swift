import EventKit
import SwiftUI

@MainActor
final class CalendarDeviceSource {
    let store = EKEventStore()

    var eventAccess: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    var reminderAccess: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .reminder) }
    var canReadEvents: Bool { eventAccess == .fullAccess }
    var canReadReminders: Bool { reminderAccess == .fullAccess }

    var defaultCalendarTitle: String? {
        canReadEvents ? store.defaultCalendarForNewEvents?.title : nil
    }

    func requestEvents() async -> Bool { (try? await store.requestFullAccessToEvents()) ?? false }
    func requestReminders() async -> Bool { (try? await store.requestFullAccessToReminders()) ?? false }

    func events(in interval: DateInterval) -> [CalendarAgendaEvent] {
        guard canReadEvents else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).map(Self.agendaEvent)
    }

    static func agendaEvent(_ event: EKEvent) -> CalendarAgendaEvent {
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        let names = (event.attendees ?? []).filter { !$0.isCurrentUser }.compactMap { $0.name ?? $0.url.absoluteString
            .replacingOccurrences(of: "mailto:", with: "") }
        return CalendarAgendaEvent(
            id: "\(identifier)@\(Int(event.startDate.timeIntervalSince1970))",
            title: event.title?.isEmpty == false ? event.title : "New event",
            place: event.location?.split(separator: "\n").first.map(String.init),
            start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
            tint: event.calendar.map { Color(cgColor: $0.cgColor) } ?? CalendarAgendaFeed.newEventTint,
            attendees: Array(names.prefix(12)),
            source: .device(identifier: identifier, editable: event.calendar?.allowsContentModifications ?? false),
            externalID: event.calendarItemExternalIdentifier)
    }

    func reminders(in interval: DateInterval, includeOverdue: Bool) async -> [CalendarAgendaTodo] {
        guard canReadReminders else { return [] }
        let open = store.predicateForIncompleteReminders(
            withDueDateStarting: includeOverdue ? nil : interval.start.addingTimeInterval(-86_400),
            ending: interval.end.addingTimeInterval(86_400), calendars: nil)
        let done = store.predicateForCompletedReminders(
            withCompletionDateStarting: interval.start, ending: interval.end, calendars: nil)
        return await fetch(open, in: interval, includeOverdue: includeOverdue)
            + fetch(done, in: interval, includeOverdue: includeOverdue)
    }

    private func fetch(_ predicate: NSPredicate, in interval: DateInterval, includeOverdue: Bool) async -> [CalendarAgendaTodo] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { @Sendable reminders in
                continuation.resume(returning: Self.todos(reminders ?? [], in: interval, includeOverdue: includeOverdue))
            }
        }
    }

    private nonisolated static func todos(_ reminders: [EKReminder], in interval: DateInterval,
                                          includeOverdue: Bool) -> [CalendarAgendaTodo] {
        reminders.compactMap { reminder in
            let parts = reminder.dueDateComponents
            let day = parts.map { DateComponents(year: $0.year, month: $0.month, day: $0.day) }
            guard let due = (parts?.hour == nil ? day : parts).flatMap({ Calendar.current.date(from: $0) })
                    ?? reminder.completionDate else { return nil }
            let done = reminder.isCompleted
            let inside = interval.holds(due)
            guard inside || (!done && includeOverdue && due < interval.start)
                    || (done && reminder.completionDate.map(interval.holds) == true) else { return nil }
            return CalendarAgendaTodo(
                id: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                due: inside ? due : interval.start, timed: inside && parts?.hour != nil, done: done)
        }
    }

    func addEvent(_ draft: CalendarDraft) async throws -> String {
        if eventAccess == .notDetermined {
            _ = try? await store.requestWriteOnlyAccessToEvents()
        }
        guard eventAccess == .fullAccess || eventAccess == .writeOnly else { throw CalendarWriteError.eventsOff }
        let event = EKEvent(eventStore: store)
        event.title = draft.title.isEmpty ? "New event" : draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.calendar = store.defaultCalendarForNewEvents
        guard event.calendar != nil else { throw CalendarWriteError.noCalendar }
        try store.save(event, span: .thisEvent)
        return event.eventIdentifier ?? event.calendarItemIdentifier
    }

    func addReminder(_ draft: CalendarDraft) async throws -> String {
        if reminderAccess == .notDetermined { _ = await requestReminders() }
        guard canReadReminders else { throw CalendarWriteError.remindersOff }
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title.isEmpty ? "New to-do" : draft.title
        reminder.calendar = store.defaultCalendarForNewReminders()
        guard reminder.calendar != nil else { throw CalendarWriteError.noCalendar }
        let fields: Set<Calendar.Component> = draft.timed ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
        reminder.dueDateComponents = Calendar.current.dateComponents(fields, from: draft.start)
        if draft.timed { reminder.addAlarm(EKAlarm(absoluteDate: draft.start)) }
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func remove(itemWithIdentifier identifier: String) {
        if let event = store.event(withIdentifier: identifier) {
            try? store.remove(event, span: .thisEvent)
        } else if let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder {
            try? store.remove(reminder, commit: true)
        }
    }

    func setDone(_ identifier: String, _ done: Bool) -> Bool {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return false }
        reminder.isCompleted = done
        return (try? store.save(reminder, commit: true)) != nil
    }

    func update(_ event: CalendarAgendaEvent, start: Date, end: Date) -> Bool {
        guard let stored = occurrence(of: event) else { return false }
        stored.startDate = start
        stored.endDate = end
        return (try? store.save(stored, span: .thisEvent)) != nil
    }

    func delete(_ event: CalendarAgendaEvent) -> Bool {
        guard let stored = occurrence(of: event) else { return false }
        return (try? store.remove(stored, span: .thisEvent)) != nil
    }

    private func occurrence(of event: CalendarAgendaEvent) -> EKEvent? {
        guard case .device(let identifier, true) = event.source else { return nil }
        let predicate = store.predicateForEvents(withStart: event.start.addingTimeInterval(-1),
                                                 end: event.end.addingTimeInterval(1), calendars: nil)
        return store.events(matching: predicate).first {
            ($0.eventIdentifier ?? $0.calendarItemIdentifier) == identifier && $0.startDate == event.start
        } ?? store.event(withIdentifier: identifier)
    }
}

enum CalendarWriteError: Error {
    case eventsOff, remindersOff, noCalendar

    var message: String {
        switch self {
        case .eventsOff: "Calendar access is off. Turn it on in Settings to add events."
        case .remindersOff: "Reminders access is off. Turn it on in Settings to add to-dos."
        case .noCalendar: "There's no calendar on this iPhone to save to."
        }
    }
}
