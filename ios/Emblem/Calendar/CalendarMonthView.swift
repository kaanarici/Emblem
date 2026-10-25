import SwiftUI

struct CalendarMonthView: View {
    let period: CalendarBrowserSnapshot
    let actions: CalendarPeriodActions
    @State private var chosen: Date?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let calendar = period.calendar
        let now = actions.feed.now
        let gridStart = calendar.dateInterval(of: .weekOfYear, for: period.startInclusive)?.start ?? period.startInclusive
        let weeks = ((calendar.dateComponents([.day], from: gridStart, to: period.endExclusive).day ?? 35) + 6) / 7
        let selected = chosen ?? (period.interval.holds(now) ? calendar.startOfDay(for: now) : period.startInclusive)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CalendarBriefLine(text: actions.feed.brief(for: period)).padding(.bottom, 24)
                    .padding(.horizontal, CalendarMetrics.edge)
                HStack(spacing: 0) {
                    let symbols = calendar.veryShortStandaloneWeekdaySymbols
                    let focus = calendar.component(.weekday, from: selected)
                    ForEach(0..<7, id: \.self) { column in
                        let weekday = (calendar.firstWeekday - 1 + column) % 7 + 1
                        Text(symbols[weekday - 1])
                            .font(.system(size: 13, weight: weekday == focus ? .semibold : .regular))
                            .foregroundStyle(weekday == focus ? CalendarMetrics.red(colorScheme) : Theme.inkSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .animation(.smooth(duration: 0.18), value: selected)
                .padding(.horizontal, CalendarMetrics.edge)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
                VStack(spacing: 2) {
                    ForEach(0..<weeks, id: \.self) { week in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { weekday in
                                if let date = calendar.date(byAdding: .day, value: week * 7 + weekday, to: gridStart) {
                                    cell(date, calendar: calendar, now: now, selected: selected)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, CalendarMetrics.edge)
                if let end = calendar.date(byAdding: .day, value: 1, to: selected) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(CalendarClock.text(selected, calendar: calendar, format: "EEEE, MMMM d"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.top, 32)
                            .padding(.bottom, 8)
                            .accessibilityAddTraits(.isHeader)
                        CalendarDaySection(day: DateInterval(start: selected, end: end), calendar: calendar,
                                           actions: actions, header: false)
                    }
                    .padding(.horizontal, CalendarMetrics.edge)
                    .id(selected)
                    .transition(.opacity)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 200)
        }
        .scrollIndicators(.hidden)
    }

    private func cell(_ date: Date, calendar: Calendar, now: Date, selected: Date) -> some View {
        let inMonth = period.interval.holds(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selected)
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let end = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        let tints = inMonth ? actions.feed.events(in: DateInterval(start: date, end: end)).map(\.tint) : []
        return Button {
            withAnimation(.smooth(duration: 0.28)) { chosen = date }
        } label: {
            VStack(spacing: 6) {
                Text(String(calendar.component(.day, from: date)))
                    .font(.system(size: 17, weight: isSelected || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? CalendarMetrics.red(colorScheme) : Theme.ink)
                HStack(spacing: 3) {
                    ForEach(Array(tints.prefix(3).enumerated()), id: \.offset) { _, tint in
                        Circle().fill(tint).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(width: 44, height: 52)
            .frame(maxWidth: .infinity)
            .opacity(!inMonth ? 0.22 : end <= calendar.startOfDay(for: now) ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!inMonth)
        .accessibilityLabel(CalendarClock.text(date, calendar: calendar, format: "EEEE, MMMM d")
                            + (tints.isEmpty ? "" : ", \(tints.count) events"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
