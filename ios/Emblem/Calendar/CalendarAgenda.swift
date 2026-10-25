import EventKit
import SwiftUI

struct CalendarAgendaEvent: Identifiable, Hashable {
    enum Source: Hashable {
        case device(identifier: String, editable: Bool)
        case google(account: String, url: URL?)
    }

    let id: String
    var title: String
    var place: String?
    var start: Date
    var end: Date
    var isAllDay = false
    var tint: Color
    var attendees: [String] = []
    var source: Source
    var externalID: String?

    var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
    var editable: Bool { if case .device(_, true) = source { true } else { false } }
    var dedupeKey: String? { externalID.map { "\($0)|\(Int(start.timeIntervalSince1970))" } }
}

struct CalendarAgendaTodo: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var due: Date
    var timed: Bool
    var done = false
}

extension DateInterval {
    func holds(_ date: Date) -> Bool { start <= date && date < end }
}

struct CalendarFreeSlot: Hashable, Identifiable {
    let start: Date
    let end: Date
    var wholeDay = false
    var trailing = false
    var id: String { "free-\(Int(start.timeIntervalSince1970))" }
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
    var restOfDay: Bool { wholeDay || (trailing && minutes >= 360) }

    var label: String {
        if wholeDay { return "Free all day" }
        return restOfDay ? "Free rest of the day" : CalendarClock.duration(minutes) + " free"
    }
}

struct CalendarAddResult: Equatable {
    let identifier: String?
    let draft: CalendarDraft
}

@Observable @MainActor
final class CalendarAgendaFeed {
    static let shared = CalendarAgendaFeed()
    static let newEventTint = Color(red: 0.25, green: 0.52, blue: 0.96)

    enum Notice: Equatable { case allowEvents, eventsOff, eventsAddOnly, googleFailed, offline }

    private(set) var revision = 0
    private(set) var googleState = CalendarGoogleState.unknown
    private var google: [CalendarAgendaEvent] = []
    private var added: [CalendarAgendaEvent] = []
    private var todoDays: [DateInterval: [CalendarAgendaTodo]] = [:]
    var draft: CalendarDraft?
    var result: CalendarAddResult?
    var writeError: String?
    var openingEventID: String?
    var transitionAnchor = UUID()
    var isFront = false
    var nowRequest = 0
    var onFocus: ((Date) -> Void)?
    private var tick = Date()
    @ObservationIgnored let device = CalendarDeviceSource()
    @ObservationIgnored private var deviceDays: [DateInterval: [CalendarAgendaEvent]] = [:]
    @ObservationIgnored private var freshTodos: Set<DateInterval> = []
    @ObservationIgnored private var googleWindow: DateInterval?

    var now: Date { tick }

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: device.store, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarAgendaFeed.shared.invalidate() }
        }
    }

    func invalidate() {
        deviceDays.removeAll()
        freshTodos.removeAll()
        revision += 1
    }

    func refreshClock() { tick = .now }

    func runClock() async {
        while !Task.isCancelled {
            let next = Calendar.current.nextDate(after: .now, matching: DateComponents(second: 0),
                                                 matchingPolicy: .nextTime) ?? .now.addingTimeInterval(60)
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow + 0.05)))
            tick = .now
        }
    }

    func events(in interval: DateInterval) -> [CalendarAgendaEvent] {
        _ = revision
        let local = deviceDays[interval] ?? {
            let loaded = device.events(in: interval)
            deviceDays[interval] = loaded
            return loaded
        }()
        var seen = Set(local.compactMap(\.dedupeKey))
        let remote = (google + added).filter { event in
            guard event.end > interval.start, event.start < interval.end else { return false }
            guard let key = event.dedupeKey else { return true }
            return seen.insert(key).inserted
        }
        return (local + remote).sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    func todos(in interval: DateInterval) -> [CalendarAgendaTodo] {
        _ = revision
        if device.canReadReminders, freshTodos.insert(interval).inserted {
            let today = interval.holds(now)
            Task {
                let todos = await device.reminders(in: interval, includeOverdue: today)
                withAnimation(.smooth(duration: 0.3)) { todoDays[interval] = todos.sorted { $0.due < $1.due } }
            }
        }
        return todoDays[interval] ?? []
    }

    func brief(for period: CalendarBrowserSnapshot) -> String? {
        guard ![.allowEvents, .eventsOff, .eventsAddOnly].contains(notice) else { return nil }
        let calendar = period.calendar
        switch period.scope {
        case .day:
            return CalendarBrief.day(events: events(in: period.interval), todos: todos(in: period.interval),
                                     day: period.interval, now: now, calendar: calendar)
        case .week:
            let days = (0..<7).compactMap { offset -> (interval: DateInterval, events: [CalendarAgendaEvent])? in
                guard let start = calendar.date(byAdding: .day, value: offset, to: period.startInclusive),
                      let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
                let interval = DateInterval(start: start, end: end)
                return (interval, events(in: interval))
            }
            return CalendarBrief.week(days, now: now, calendar: calendar)
        case .month:
            return nil
        }
    }

    var notice: Notice? {
        _ = revision
        let hasGoogle = googleState == .connected
        switch device.eventAccess {
        case .notDetermined where !hasGoogle: return .allowEvents
        case .denied where !hasGoogle, .restricted where !hasGoogle: return .eventsOff
        case .writeOnly where !hasGoogle: return .eventsAddOnly
        default: break
        }
        switch googleState {
        case .partial, .unavailable: return .googleFailed
        case .offline: return .offline
        default: return nil
        }
    }

    func requestAccess() {
        Task {
            _ = await device.requestEvents()
            _ = await device.requestReminders()
            invalidate()
        }
    }

    func loadGoogle(around date: Date, force: Bool = false) async {
        let calendar = Calendar.current
        let wanted = DateInterval(start: calendar.date(byAdding: .day, value: -7, to: date) ?? date,
                                  end: calendar.date(byAdding: .day, value: 21, to: date) ?? date)
        if !force, let window = googleWindow, window.start <= wanted.start, window.end >= wanted.end { return }
        guard let start = calendar.date(byAdding: .day, value: -14, to: calendar.startOfDay(for: date)),
              let end = calendar.date(byAdding: .day, value: 31, to: start) else { return }
        let window = DateInterval(start: start, end: end)
        googleWindow = window
        do {
            let response = try await CalendarGoogleSource.fetch(window)
            withAnimation(.smooth(duration: 0.3)) {
                google = CalendarGoogleSource.events(response, calendar: calendar)
                googleState = CalendarGoogleSource.state(response)
                revision += 1
            }
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            googleWindow = nil
            googleState = googleState == .notConnected ? .notConnected : .offline
        } catch {
            googleWindow = nil
            if googleState != .notConnected { googleState = .unavailable }
        }
    }

    func compose(_ text: String) {
        let parsed = CalendarDraft.parse(text, now: now, calendar: .current)
        start(parsed)
        onFocus?(parsed.start)
    }

    func blank(_ kind: CalendarDraft.Kind, on day: Date) {
        let calendar = Calendar.current
        let hour = calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
        let next = !calendar.isDate(day, inSameDayAs: now)
            ? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            : calendar.isDate(hour, inSameDayAs: now) ? hour : now
        start(CalendarDraft(kind: kind, title: "", start: next, timed: kind == .event))
    }

    func propose(_ slot: CalendarFreeSlot) {
        start(CalendarDraft(kind: .event, title: "", start: slot.start, minutes: min(60, slot.minutes)))
    }

    private func start(_ next: CalendarDraft) {
        result = nil
        writeError = nil
        withAnimation(.smooth(duration: 0.35)) { draft = next }
    }

    func cancelDraft() {
        writeError = nil
        withAnimation(.smooth(duration: 0.25)) { draft = nil }
    }

    func save() async {
        guard let draft else { return }
        do {
            var identifier: String?
            switch draft.kind {
            case .event:
                let saved = try await device.addEvent(draft)
                if device.canReadEvents {
                    identifier = saved
                } else {
                    added.append(CalendarAgendaEvent(
                        id: "added:\(saved)", title: draft.title.isEmpty ? "New event" : draft.title,
                        start: draft.start, end: draft.end, tint: Self.newEventTint,
                        source: .device(identifier: saved, editable: false)))
                }
            case .todo:
                identifier = try await device.addReminder(draft)
            }
            withAnimation(.smooth(duration: 0.4)) {
                self.draft = nil
                writeError = nil
                result = CalendarAddResult(identifier: identifier, draft: draft)
                invalidate()
            }
        } catch let error as CalendarWriteError {
            writeError = error.message
        } catch {
            writeError = "That couldn't be saved. Try again."
        }
    }

    func undo() {
        guard let identifier = result?.identifier else { return }
        device.remove(itemWithIdentifier: identifier)
        withAnimation(.smooth(duration: 0.35)) {
            result = nil
            invalidate()
        }
    }

    func toggle(_ todo: CalendarAgendaTodo) {
        guard let day = todoDays.first(where: { $0.value.contains { $0.id == todo.id } })?.key,
              let index = todoDays[day]?.firstIndex(where: { $0.id == todo.id }) else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { todoDays[day]?[index].done.toggle() }
        if !device.setDone(todo.id, !todo.done) {
            withAnimation(.smooth(duration: 0.25)) { todoDays[day]?[index].done = todo.done }
        }
    }

    func move(_ event: CalendarAgendaEvent, by minutes: Int) {
        let shift = Double(minutes * 60)
        _ = device.update(event, start: event.start.addingTimeInterval(shift), end: event.end.addingTimeInterval(shift))
        withAnimation(.smooth(duration: 0.35)) { invalidate() }
    }

    func resize(_ event: CalendarAgendaEvent, to minutes: Int) {
        _ = device.update(event, start: event.start, end: event.start.addingTimeInterval(Double(minutes * 60)))
        withAnimation(.smooth(duration: 0.35)) { invalidate() }
    }

    func delete(_ event: CalendarAgendaEvent) {
        _ = device.delete(event)
        withAnimation(.smooth(duration: 0.35)) { invalidate() }
    }
}

struct CalendarDayPlan {
    enum Item: Identifiable {
        case events([CalendarAgendaEvent])
        case todo(CalendarAgendaTodo)
        case draft(CalendarDraft)
        case free(CalendarFreeSlot)

        var id: String {
            switch self {
            case .events(let events): events.map(\.id).joined(separator: "+")
            case .todo(let todo): todo.id
            case .draft: "draft"
            case .free(let slot): slot.id
            }
        }

        var start: Date {
            switch self {
            case .events(let events): events.map(\.start).min() ?? .distantPast
            case .todo(let todo): todo.due
            case .draft(let draft): draft.start
            case .free(let slot): slot.start
            }
        }


        var end: Date {
            switch self {
            case .events(let events): events.map(\.end).max() ?? .distantPast
            case .todo(let todo): todo.due
            case .draft(let draft): draft.kind == .event ? draft.end : draft.start
            case .free(let slot): slot.end
            }
        }
    }

    let allDay: [CalendarAgendaEvent]
    let anytime: [CalendarAgendaTodo]
    let anytimeDraft: Bool
    let items: [Item]
    let nextID: String?
    let isEmpty: Bool

    init(events: [CalendarAgendaEvent], todos: [CalendarAgendaTodo] = [], draft: CalendarDraft? = nil,
         day: DateInterval, calendar: Calendar, now: Date) {
        allDay = events.filter(\.isAllDay)
        anytime = todos.filter { !$0.timed }
        let drafted = draft.flatMap { day.holds($0.start) ? $0 : nil }
        anytimeDraft = drafted.map { $0.kind == .todo && !$0.timed } ?? false
        let timed = events.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        isEmpty = events.isEmpty && todos.isEmpty && draft == nil
        var entries: [Item] = []
        var clusterEnd = Date.distantPast
        for event in timed {
            if event.start < clusterEnd, case .events(let cluster)? = entries.last {
                entries[entries.count - 1] = .events(cluster + [event])
                clusterEnd = max(clusterEnd, event.end)
            } else {
                entries.append(.events([event]))
                clusterEnd = event.end
            }
        }
        if let drafted, !anytimeDraft { entries.append(.draft(drafted)) }
        entries.sort { $0.start < $1.start }
        let open = calendar.date(byAdding: .hour, value: 8, to: day.start) ?? day.start
        let close = calendar.date(byAdding: .hour, value: 21, to: day.start) ?? day.end
        var items: [Item] = []
        func free(from: Date, to: Date) {
            let start = max(from, open, now), stop = min(to, close)
            guard stop.timeIntervalSince(start) >= 30 * 60 else { return }
            items.append(.free(CalendarFreeSlot(start: start, end: stop, wholeDay: start == open && stop == close,
                                                trailing: stop == close)))
        }
        var cursor = open
        for entry in entries {
            free(from: cursor, to: entry.start)
            items.append(entry)
            cursor = max(cursor, entry.end)
        }
        free(from: cursor, to: close)
        for todo in todos.filter(\.timed) {
            items.insert(.todo(todo), at: items.firstIndex { $0.start > todo.due } ?? items.endIndex)
        }
        self.items = items
        nextID = timed.first { $0.end > now }?.id
    }

    func marker(at now: Date) -> (id: String, fraction: CGFloat)? {
        guard let last = items.last else { return nil }
        guard let item = items.first(where: { $0.end > now }) else { return (last.id, 1) }
        if case .events = item, item.start < now { return nil }
        return (item.id, 0)
    }

    static func largestFree(_ events: [CalendarAgendaEvent], day: DateInterval, calendar: Calendar,
                            now: Date) -> CalendarFreeSlot? {
        let plan = CalendarDayPlan(events: events, day: day, calendar: calendar, now: now)
        return plan.items.compactMap { item -> CalendarFreeSlot? in
            if case .free(let slot) = item, slot.minutes >= 90 { return slot }
            return nil
        }.max { $0.minutes < $1.minutes }
    }
}

enum CalendarClock {
    private static func formatter(_ calendar: Calendar, _ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }

    static var usesMeridiem: Bool {
        (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }

    static func parts(_ date: Date, calendar: Calendar) -> (time: String, meridiem: String?) {
        guard usesMeridiem else { return (formatter(calendar, "HH:mm").string(from: date), nil) }
        return (formatter(calendar, "h:mm").string(from: date), formatter(calendar, "a").string(from: date))
    }

    static func short(_ date: Date, calendar: Calendar) -> String {
        let (time, meridiem) = parts(date, calendar: calendar)
        return meridiem.map { "\(time) \($0)" } ?? time
    }

    static func range(_ start: Date, _ end: Date, calendar: Calendar) -> String {
        let first = parts(start, calendar: calendar), last = parts(end, calendar: calendar)
        let head = first.meridiem == last.meridiem ? first.time : short(start, calendar: calendar)
        return head + " – " + short(end, calendar: calendar)
    }

    static func spoken(_ date: Date, calendar: Calendar) -> String {
        guard usesMeridiem, calendar.component(.minute, from: date) == 0 else { return short(date, calendar: calendar) }
        return formatter(calendar, "h a").string(from: date)
    }

    static func duration(_ minutes: Int) -> String {
        let rounded = minutes >= 60 ? (minutes + 2) / 5 * 5 : minutes
        let hours = rounded / 60, rest = rounded % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    static func countdown(for event: CalendarAgendaEvent, now: Date) -> String? {
        guard !event.isAllDay else { return nil }
        if event.start <= now, event.end > now {
            return "Now · \(duration(Int(event.end.timeIntervalSince(now) / 60))) left"
        }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        guard minutes >= 0, minutes <= 90 else { return nil }
        return minutes < 1 ? "Starting now" : "In \(duration(minutes))"
    }

    static func text(_ date: Date, calendar: Calendar, format: String) -> String {
        formatter(calendar, format).string(from: date)
    }
}

extension CalendarBrowserSnapshot {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    var interval: DateInterval { DateInterval(start: startInclusive, end: endExclusive) }
}
