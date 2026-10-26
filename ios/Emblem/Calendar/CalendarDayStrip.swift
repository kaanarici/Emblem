import SwiftUI

enum CalendarMotion {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.88)

    static func settle(_ reduceMotion: Bool) -> Animation { reduceMotion ? .easeOut(duration: 0.2) : spring }

    static func flick(_ velocity: CGFloat, toward distance: CGFloat) -> Animation {
        let relative = distance == 0 ? 0 : max(0, min(8, velocity / distance))
        return .interpolatingSpring(duration: 0.42, bounce: 0, initialVelocity: relative)
    }

    static func pages(drag: CGFloat, velocity: CGFloat, stride: CGFloat) -> Int {
        let projected = drag + velocity * 0.2
        guard abs(projected) > stride / 2 else { return 0 }
        return projected < 0 ? 1 : -1
    }
}

@Observable final class CalendarPagerTrack {
    var offset: CGFloat = 0
    var stride: CGFloat = 0
    var dragging = false

    func page(reach: Int) -> CGFloat { offset / max(1, stride) - CGFloat(reach) }
}

struct CalendarStripIndex {
    let calendar: Calendar
    let zone: TimeZone
    private let reference: Date

    init(calendar: Calendar, zone: TimeZone) {
        self.calendar = calendar
        self.zone = zone
        let origin = Date(timeIntervalSinceReferenceDate: 0)
        reference = calendar.dateInterval(of: .weekOfYear, for: origin)?.start ?? origin
    }

    func day(_ day: CalendarBrowserDay) -> Int {
        day.date(in: zone).flatMap { calendar.dateComponents([.day], from: reference, to: $0).day } ?? 0
    }

    func date(day index: Int) -> Date { calendar.date(byAdding: .day, value: index, to: reference) ?? reference }

    func period(_ day: CalendarBrowserDay, monthly: Bool) -> Int {
        monthly ? day.year * 12 + day.month - 1 : Int((Double(self.day(day)) / 7).rounded(.down))
    }

    func start(period index: Int, monthly: Bool) -> Date {
        guard monthly else { return date(day: index * 7) }
        var parts = DateComponents(year: index / 12, month: index % 12 + 1, day: 1)
        parts.timeZone = zone
        return calendar.date(from: parts) ?? reference
    }
}

private struct CalendarStripThumb: View {
    var body: some View {
        Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CalendarStripLabels: View {
    let primary: String
    let secondary: String
    let today: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 1) {
            Text(primary)
                .font(.system(size: 17, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(secondary)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(today ? CalendarMetrics.red(colorScheme) : Theme.inkSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

private extension View {
    func calendarSettle(_ value: some Equatable, while dragging: Bool, reduceMotion: Bool) -> some View {
        transaction(value: value) { transaction in
            guard transaction.animation == nil, !dragging else { return }
            transaction.animation = CalendarMotion.settle(reduceMotion)
        }
    }
}

struct CalendarDayStrip: View {
    let selection: CalendarBrowserSelection
    let pager: CalendarPagerTrack
    let anchor: CalendarBrowserDay
    let reach: Int
    let onSelect: (CalendarBrowserIntent) -> Bool
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 48

    var body: some View {
        let index = CalendarStripIndex(calendar: selection.calendar, zone: selection.zone)
        let selected = index.day(selection.selectedDate)
        let position = pager.dragging ? CGFloat(index.day(anchor)) + pager.page(reach: reach) : CGFloat(selected)
        let week = Int((Double(Int(position.rounded())) / 7).rounded(.down))
        let slot = position - CGFloat(week * 7)
        let today = index.day(CalendarBrowserDay(date: CalendarAgendaFeed.shared.now, timeZone: selection.zone))
        GeometryReader { proxy in
            let cell = (proxy.size.width - 2 * Theme.pageMargin) / 7
            ZStack(alignment: .topLeading) {
                CalendarStripThumb()
                    .frame(width: cell - 4, height: Self.height)
                    .offset(x: Theme.pageMargin + slot * cell + 2)
                    .calendarSettle(slot, while: pager.dragging, reduceMotion: reduceMotion)
                ZStack(alignment: .topLeading) {
                    ForEach((week - 1) * 7 ..< (week + 2) * 7, id: \.self) { day in
                        dayCell(index, day: day, today: day == today)
                            .frame(width: cell, height: Self.height)
                            .offset(x: CGFloat(day) * cell)
                    }
                }
                .offset(x: Theme.pageMargin - CGFloat(week * 7) * cell + drag)
                .calendarSettle(week, while: false, reduceMotion: reduceMotion)
            }
            .frame(width: proxy.size.width, height: Self.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .highPriorityGesture(swipe(stride: 7 * cell))
        }
        .frame(height: Self.height)
        .mask { Rectangle().padding(.vertical, -24).padding(.horizontal, Theme.pageMargin - 8) }
    }

    private func swipe(stride: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard drag != 0 || abs(value.translation.width) > abs(value.translation.height) else { return }
                drag = value.translation.width
            }
            .onEnded { value in
                guard drag != 0 else { return }
                let weeks = CalendarMotion.pages(drag: drag, velocity: value.velocity.width, stride: stride)
                let target = selection.calendar.date(byAdding: .day, value: weeks * 7, to: selection.selectedInstant)
                let travel = -CGFloat(weeks) * stride - drag
                withAnimation(reduceMotion ? .easeOut(duration: 0.2)
                              : CalendarMotion.flick(value.velocity.width, toward: travel)) {
                    drag = 0
                    if weeks != 0, let target {
                        selection.propose({ try $0.chooseDay(CalendarBrowserDay(date: target, timeZone: selection.zone)) },
                                          accepting: onSelect)
                    }
                }
            }
    }

    private func dayCell(_ index: CalendarStripIndex, day position: Int, today: Bool) -> some View {
        let date = index.date(day: position)
        let day = CalendarBrowserDay(date: date, timeZone: selection.zone)
        let weekday = index.calendar.shortStandaloneWeekdaySymbols[index.calendar.component(.weekday, from: date) - 1]
        return Button {
            if day == selection.selectedDate {
                CalendarAgendaFeed.shared.nowRequest += 1
            } else {
                withAnimation(CalendarMotion.settle(reduceMotion)) {
                    selection.propose({ try $0.chooseDay(day) }, accepting: onSelect)
                }
            }
        } label: {
            CalendarStripLabels(primary: String(day.day), secondary: weekday, today: today)
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
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let monthly = selection.mode == .monthly
        let index = CalendarStripIndex(calendar: selection.calendar, zone: selection.zone)
        let selected = index.period(selection.selectedDate, monthly: monthly)
        let position = pager.dragging
            ? CGFloat(index.period(anchor, monthly: monthly)) + pager.page(reach: reach) : CGFloat(selected)
        let center = Int(position.rounded())
        let now = CalendarAgendaFeed.shared.now
        let current = index.period(CalendarBrowserDay(date: now, timeZone: selection.zone), monthly: monthly)
        GeometryReader { proxy in
            let cell = (proxy.size.width - 2 * Theme.pageMargin) / 3
            ZStack(alignment: .topLeading) {
                CalendarStripThumb()
                    .frame(width: cell - 8, height: CalendarDayStrip.height)
                    .offset(x: cell + 4)
                ForEach(center - 2 ... center + 2, id: \.self) { period in
                    periodCell(index, period: period, relative: period - selected, current: period == current)
                        .frame(width: cell, height: CalendarDayStrip.height)
                        .offset(x: (CGFloat(period) - position + 1) * cell + drag)
                }
            }
            .offset(x: Theme.pageMargin)
            .calendarSettle(position, while: pager.dragging, reduceMotion: reduceMotion)
            .frame(width: proxy.size.width, height: CalendarDayStrip.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .highPriorityGesture(swipe(stride: cell))
        }
        .frame(height: CalendarDayStrip.height)
        .mask { Rectangle().padding(.vertical, -24).padding(.horizontal, Theme.pageMargin - 8) }
    }

    private func swipe(stride: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard drag != 0 || abs(value.translation.width) > abs(value.translation.height) else { return }
                drag = value.translation.width
            }
            .onEnded { value in
                guard drag != 0 else { return }
                let periods = CalendarMotion.pages(drag: drag, velocity: value.velocity.width, stride: stride)
                let travel = -CGFloat(periods) * stride - drag
                withAnimation(reduceMotion ? .easeOut(duration: 0.2)
                              : CalendarMotion.flick(value.velocity.width, toward: travel)) {
                    drag = 0
                    if periods != 0 { selection.propose({ try $0.choosePeriod(offset: periods) }, accepting: onSelect) }
                }
            }
    }

    private func periodCell(_ index: CalendarStripIndex, period: Int, relative: Int, current: Bool) -> some View {
        let calendar = selection.calendar
        let monthly = selection.mode == .monthly
        let start = CalendarBrowserDay(date: index.start(period: period, monthly: monthly), timeZone: selection.zone)
        let last = CalendarBrowserDay(date: index.date(day: index.day(start) + 6), timeZone: selection.zone)
        let tail = start.month == last.month ? String(last.day) : selection.text(last, format: "MMM d")
        let week = index.start(period: period, monthly: false)
        return Button {
            withAnimation(CalendarMotion.settle(reduceMotion)) {
                selection.propose({ try $0.choosePeriod(offset: relative) }, accepting: onSelect)
            }
        } label: {
            CalendarStripLabels(
                primary: monthly ? selection.text(start, format: "MMMM") : selection.text(start, format: "MMM d") + "–" + tail,
                secondary: monthly ? String(start.year) : "Week \(calendar.component(.weekOfYear, from: week))",
                today: current)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(monthly ? selection.text(start, format: "MMMM yyyy")
                            : "Week of " + selection.text(start, format: "MMMM d, yyyy"))
        .accessibilityAddTraits(relative == 0 ? .isSelected : [])
        .accessibilityIdentifier(monthly ? "calendar-month-\(relative)" : "calendar-week-\(relative)")
    }
}
