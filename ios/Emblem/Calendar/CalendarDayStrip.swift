import SwiftUI

enum CalendarMotion {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.88)
}

@Observable final class CalendarPagerTrack {
    var offset: CGFloat = 0
    var stride: CGFloat = 0
    var dragging = false

    func page(reach: Int) -> CGFloat { offset / max(1, stride) - CGFloat(reach) }
}

private struct CalendarStripLabels: View {
    let primary: String
    let secondary: String
    let focused: Bool
    let strong: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 1) {
            Text(primary)
                .font(.system(size: 17, weight: focused || strong ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(secondary)
                .font(.system(size: 13, weight: focused ? .semibold : .regular))
                .foregroundStyle(focused ? CalendarMetrics.red(colorScheme) : Theme.inkSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

struct CalendarDayStrip: View {
    let selection: CalendarBrowserSelection
    let pager: CalendarPagerTrack
    let anchor: CalendarBrowserDay
    let reach: Int
    let onSelect: (CalendarBrowserIntent) -> Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height: CGFloat = 44

    var body: some View {
        let calendar = selection.calendar
        let anchorDate = anchor.date(in: selection.zone) ?? selection.selectedInstant
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: anchorDate)?.start ?? anchorDate
        let anchorCell = CGFloat(calendar.dateComponents([.day], from: weekStart, to: anchorDate).day ?? 0)
        let selected = CGFloat(calendar.dateComponents([.day], from: anchorDate, to: selection.selectedInstant).day ?? 0)
        let position = anchorCell + (pager.dragging ? pager.page(reach: reach) : selected)
        let focused = Int(position.rounded())
        let week = Int((CGFloat(focused) / 7).rounded(.down))
        let today = CalendarBrowserDay(date: CalendarAgendaFeed.shared.now, timeZone: selection.zone)
        let weekdays = calendar.shortStandaloneWeekdaySymbols
        GeometryReader { proxy in
            let cell = (proxy.size.width - 2 * Theme.pageMargin) / 7
            ZStack(alignment: .topLeading) {
                ForEach((week - 1) * 7 ..< (week + 2) * 7, id: \.self) { index in
                    let date = calendar.date(byAdding: .day, value: index, to: weekStart) ?? weekStart
                    let day = CalendarBrowserDay(date: date, timeZone: selection.zone)
                    dayCell(day, weekday: weekdays[calendar.component(.weekday, from: date) - 1], today: day == today,
                            focused: index == focused)
                        .frame(width: cell, height: Self.height)
                        .offset(x: CGFloat(index) * cell)
                }
            }
            .offset(x: Theme.pageMargin - CGFloat(week * 7) * cell)
            .animation(reduceMotion ? nil : CalendarMotion.spring, value: week)
            .animation(.smooth(duration: 0.18), value: focused)
        }
        .frame(height: Self.height)
        .mask { Rectangle().padding(.vertical, -24).padding(.horizontal, Theme.pageMargin - 8) }
    }

    private func dayCell(_ day: CalendarBrowserDay, weekday: String, today: Bool, focused: Bool) -> some View {
        Button {
            if day == selection.selectedDate {
                CalendarAgendaFeed.shared.nowRequest += 1
            } else {
                selection.propose({ try $0.chooseDay(day) }, accepting: onSelect)
            }
        } label: {
            CalendarStripLabels(primary: String(day.day), secondary: weekday, focused: focused, strong: today)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(selection.text(day, format: "EEEE, MMMM d, yyyy"))
        .accessibilityAddTraits(day == selection.selectedDate ? .isSelected : [])
        .accessibilityIdentifier("calendar-day-" + day.id)
    }
}

struct CalendarPeriodStrip: View {
    let selection: CalendarBrowserSelection
    let pager: CalendarPagerTrack
    let anchor: CalendarBrowserDay
    let reach: Int
    let onSelect: (CalendarBrowserIntent) -> Bool
    let offset: (CalendarBrowserDay, CalendarBrowserDay) -> Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let height: CGFloat = 44

    var body: some View {
        let selected = offset(anchor, selection.selectedDate) ?? 0
        let position = pager.dragging ? pager.page(reach: reach) : CGFloat(selected)
        let center = Int(position.rounded())
        GeometryReader { proxy in
            let cell = (proxy.size.width - 2 * Theme.pageMargin) / 3
            ZStack(alignment: .topLeading) {
                ForEach(center - 2 ... center + 2, id: \.self) { index in
                    periodCell(index: index, relative: index - selected, focused: index == center)
                        .frame(width: cell, height: Self.height)
                        .offset(x: (CGFloat(index) - position + 1) * cell)
                }
            }
            .offset(x: Theme.pageMargin)
            .animation(pager.dragging || reduceMotion ? nil : CalendarMotion.spring, value: position)
            .animation(.smooth(duration: 0.18), value: center)
        }
        .frame(height: Self.height)
        .mask { Rectangle().padding(.vertical, -24).padding(.horizontal, Theme.pageMargin - 8) }
    }

    private func periodCell(index: Int, relative: Int, focused: Bool) -> some View {
        let calendar = selection.calendar
        let monthly = selection.mode == .monthly
        let base = anchor.date(in: selection.zone) ?? selection.selectedInstant
        let date = calendar.date(byAdding: selection.mode.component, value: index, to: base) ?? base
        let interval = calendar.dateInterval(of: selection.mode.component, for: date) ?? DateInterval(start: date, duration: 1)
        let start = CalendarBrowserDay(date: interval.start, timeZone: selection.zone)
        let last = CalendarBrowserDay(date: interval.end.addingTimeInterval(-1), timeZone: selection.zone)
        let tail = start.month == last.month ? String(last.day) : selection.text(last, format: "MMM d")
        return Button {
            selection.propose({ try $0.choosePeriod(offset: relative) }, accepting: onSelect)
        } label: {
            CalendarStripLabels(
                primary: monthly ? selection.text(start, format: "MMMM") : selection.text(start, format: "MMM d") + "–" + tail,
                secondary: monthly ? String(start.year) : "Week \(calendar.component(.weekOfYear, from: date))",
                focused: focused, strong: interval.holds(CalendarAgendaFeed.shared.now))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(monthly ? selection.text(start, format: "MMMM yyyy")
                            : "Week of " + selection.text(start, format: "MMMM d, yyyy"))
        .accessibilityAddTraits(relative == 0 ? .isSelected : [])
        .accessibilityIdentifier(monthly ? "calendar-month-\(relative)" : "calendar-week-\(relative)")
    }
}
