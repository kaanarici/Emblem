import SwiftUI

struct CalendarWeekView: View {
    let period: CalendarBrowserSnapshot
    let actions: CalendarPeriodActions

    var body: some View {
        let calendar = period.calendar
        let days = (0..<7).compactMap { offset -> DateInterval? in
            guard let start = calendar.date(byAdding: .day, value: offset, to: period.startInclusive),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return DateInterval(start: start, end: end)
        }
        let today = days.dropFirst().first { $0.contains(actions.feed.now) }
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let notice = actions.feed.notice {
                        CalendarNoticeRow(notice: notice, feed: actions.feed).padding(.bottom, 8)
                    }
                    CalendarBriefLine(text: actions.feed.brief(for: period))
                    ForEach(days, id: \.start) { day in
                        CalendarDaySection(day: day, calendar: calendar, actions: actions, header: true).id(day.start)
                    }
                }
                .padding(.horizontal, CalendarMetrics.edge)
                .padding(.top, 24)
                .padding(.bottom, 200)
            }
            .scrollIndicators(.hidden)
            .onAppear { if let today { proxy.scrollTo(today.start, anchor: .top) } }
        }
    }
}

struct CalendarDaySection: View {
    let day: DateInterval
    let calendar: Calendar
    let actions: CalendarPeriodActions
    let header: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let now = actions.feed.now
        let events = actions.feed.events(in: day)
        let today = day.holds(now)
        let free = CalendarDayPlan.largestFree(events, day: day, calendar: calendar, now: now)
        let timed = events.filter { !$0.isAllDay }
        let timedBefore = free.map { slot in timed.filter { $0.start < slot.start }.count } ?? 0
        VStack(alignment: .leading, spacing: 0) {
            if header {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(CalendarClock.text(day.start, calendar: calendar, format: "EEEE"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(today ? CalendarMetrics.red(colorScheme) : Theme.ink)
                    Text(CalendarClock.text(day.start, calendar: calendar, format: "MMM d"))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(.top, 32)
                .padding(.bottom, 8)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            ForEach(events.filter(\.isAllDay)) { row($0, now: nil) }
            ForEach(Array(timed.enumerated()), id: \.element.id) { index, event in
                if index == timedBefore, let free { band(free) }
                row(event, now: today ? now : nil)
            }
            if timed.count == timedBefore, let free { band(free) }
        }
        .opacity(day.end <= now ? 0.5 : 1)
    }

    private func row(_ event: CalendarAgendaEvent, now: Date?) -> some View {
        CalendarEventButton(event: event, actions: actions) {
            CalendarEventRow(event: event, calendar: calendar, now: now, compact: true)
        }
    }

    private func band(_ slot: CalendarFreeSlot) -> some View {
        CalendarFreeBand(slot: slot, calendar: calendar) { actions.feed.propose(slot) }
    }
}
