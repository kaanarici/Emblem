import Foundation

enum CalendarBrief {
    static func day(events: [CalendarAgendaEvent], todos: [CalendarAgendaTodo], day: DateInterval, now: Date,
                    calendar: Calendar) -> String {
        let timed = events.filter { !$0.isAllDay && day.holds($0.start) }
        let open = todos.filter { !$0.done }.count
        let tasks = open == 1 ? "1 to-do" : "\(open) to-dos"
        guard !timed.isEmpty else {
            if let allDay = events.first { return "**\(allDay.title)** is all day, and nothing else is on the calendar." }
            return open == 0 ? "Nothing on the calendar. **The whole day is yours.**"
                : "Nothing on the calendar, and **\(tasks)** to get to."
        }
        let plan = CalendarDayPlan(events: events, day: day, calendar: calendar, now: day.holds(now) ? now : day.start)
        let gap = plan.items.compactMap { item -> CalendarFreeSlot? in
            if case .free(let slot) = item, slot.minutes >= 120 { return slot }
            return nil
        }.max { $0.minutes < $1.minutes }
        var opening: [String] = []
        let parts = ["morning", "afternoon", "evening"].map { part in
            (part, timed.filter { part == partOfDay($0.start, calendar) }.count)
        }
        if timed.count >= 4, let busiest = parts.max(by: { $0.1 < $1.1 }), busiest.1 >= 2 {
            opening.append("**Busy \(busiest.0)**")
        } else if timed.count <= 2 {
            opening.append("A light day")
        } else {
            opening.append("**\(timed.count) events**")
        }
        if let gap { opening.append(gap.restOfDay ? "free after \(CalendarClock.spoken(gap.start, calendar: calendar))"
                                       : "free \(CalendarClock.spoken(gap.start, calendar: calendar)) to "
                                           + CalendarClock.spoken(gap.end, calendar: calendar)) }
        let upcoming = timed.first { $0.start > now } ?? timed.last
        var sentence = opening.joined(separator: ", ") + "."
        if let upcoming {
            sentence += " \(upcoming.title) at **\(CalendarClock.spoken(upcoming.start, calendar: calendar))**."
        }
        if open > 0 { sentence += " \(tasks.prefix(1).uppercased() + tasks.dropFirst()) to get to." }
        return sentence
    }

    static func week(_ days: [(interval: DateInterval, events: [CalendarAgendaEvent])], now: Date,
                     calendar: Calendar) -> String? {
        guard !days.isEmpty else { return nil }
        let name = { (day: DateInterval) in CalendarClock.text(day.start, calendar: calendar, format: "EEEE") }
        let counts = days.map { ($0.interval, $0.events.filter { !$0.isAllDay }.count) }
        let full = counts.filter { $0.1 >= 4 }.map { name($0.0) }
        let open = counts.filter { $0.1 == 0 && $0.0.end > now && !calendar.isDateInWeekend($0.0.start) }.map { name($0.0) }
        guard counts.contains(where: { $0.1 > 0 }) else { return "Nothing on the calendar. **The whole week is open.**" }
        var sentence = full.isEmpty ? "A steady week." : "**Full \(list(full)).**"
        if !open.isEmpty { sentence += " \(list(open)) \(open.count == 1 ? "is" : "are") wide open." }
        return sentence
    }

    private static func partOfDay(_ date: Date, _ calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        return hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
    }

    private static func list(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}
