import SwiftUI

struct DateRangePickerView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let rangeMode: Bool
    var bottomReserve: CGFloat = 0
    @Binding var value: String

    @State private var start: Date?
    @State private var end: Date?

    private let cal: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 1
        return c
    }()
    private var today: Date { cal.startOfDay(for: Date()) }

    private var months: [Date] {
        let base = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
        return (0..<6).compactMap { cal.date(byAdding: .month, value: $0, to: base) }
    }

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
                .padding(.horizontal, 26)
                .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(months, id: \.self) { month in
                        MonthGrid(
                            month: month,
                            today: today,
                            start: start,
                            end: end,
                            onTap: tap)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 24)
            }
            .mask(
                LinearGradient(
                    stops: [.init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom))

            suggestions
                .padding(.top, 4)
                .padding(.bottom, bottomReserve + 4)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    private var suggestions: some View {
        VStack(spacing: 0) {
            SuggestionDivider()
                .padding(.horizontal, 56)
                .padding(.bottom, 22)
            if rangeMode {
                HStack(spacing: 4) {
                    SuggestionChip(label: "This weekend") { setRange(nextWeekend()) }
                    SuggestionChip(label: "Next week") { setRange(nextWeek()) }
                    SuggestionChip(label: "Later this month") { setRange(laterThisMonth()) }
                }
            }
        }
    }

    private func tap(_ day: Date) {
        withAnimation(.smooth(duration: 0.28)) {
            if !rangeMode {
                start = day
                end = nil
            } else if start == nil || end != nil || day < start! {
                start = day
                end = nil
            } else {
                end = day
            }
        }
        writeBack()
    }

    private func setRange(_ range: (Date, Date)) {
        withAnimation(.smooth(duration: 0.28)) {
            start = range.0
            end = rangeMode ? range.1 : nil
        }
        writeBack()
    }

    private func writeBack() {
        guard let start else { value = ""; return }
        if let end, rangeMode {
            value = "\(short(start)) – \(short(end))"
        } else {
            value = short(start)
        }
    }

    private func short(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f.string(from: date)
    }

    private func nextWeekend() -> (Date, Date) {
        var sat = today
        while cal.component(.weekday, from: sat) != 7 {
            sat = cal.date(byAdding: .day, value: 1, to: sat) ?? sat
        }
        let sun = cal.date(byAdding: .day, value: 1, to: sat) ?? sat
        return (sat, sun)
    }

    private func laterThisMonth() -> (Date, Date) {
        let days = cal.range(of: .day, in: .month, for: today)?.count ?? 30
        let first = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
        let lastDay = cal.date(byAdding: .day, value: days - 1, to: first) ?? today
        let s = max(today, cal.date(byAdding: .day, value: -4, to: lastDay) ?? today)
        return (s, lastDay)
    }

    private func nextWeek() -> (Date, Date) {
        let mon = cal.nextDate(
            after: today,
            matching: DateComponents(weekday: 2),
            matchingPolicy: .nextTime) ?? today
        let sun = cal.date(byAdding: .day, value: 6, to: mon) ?? mon
        return (mon, sun)
    }
}

private struct MonthGrid: View {
    let month: Date
    let today: Date
    let start: Date?
    let end: Date?
    let onTap: (Date) -> Void

    private let cal: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 1
        return c
    }()

    var body: some View {
        VStack(spacing: 0) {
            Text(monthTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(height: 28)

            VStack(spacing: 0) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    weekRow(week)
                }
            }
        }
    }

    private func weekRow(_ week: [Date?]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                DayCell(
                    day: day,
                    today: today,
                    start: start,
                    end: end,
                    band: day.map(bandRole) ?? .none,
                    onTap: onTap)
            }
        }
    }

    private func bandRole(_ day: Date) -> DayCell.Band {
        guard let start, let end, start != end else { return .none }
        let d = cal.startOfDay(for: day)
        let s = cal.startOfDay(for: start)
        let e = cal.startOfDay(for: end)
        if d == s { return .trailing }
        if d == e { return .leading }
        return (d > s && d < e) ? .full : .none
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f.string(from: month)
    }

    private var weeks: [[Date?]] {
        guard
            let range = cal.range(of: .day, in: .month, for: month),
            let first = cal.date(from: cal.dateComponents([.year, .month], from: month))
        else { return [] }

        let leading = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<range.count {
            let d = cal.date(byAdding: .day, value: offset, to: first)
            cells.append(d.map { cal.startOfDay(for: $0) < today ? nil : $0 } ?? nil)
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7)
            .map { Array(cells[$0..<$0 + 7]) }
            .filter { $0.contains { $0 != nil } }
    }
}

private struct DayCell: View {
    @Environment(\.blockInteraction) private var blockInteraction
    enum Band { case none, full, leading, trailing }

    let day: Date?
    let today: Date
    let start: Date?
    let end: Date?
    let band: Band
    let onTap: (Date) -> Void

    private let cal: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 1
        return c
    }()

    private let pill: CGFloat = 40
    private let row: CGFloat = 44

    var body: some View {
        Group {
            if let day {
                Button {
                    guard blockInteraction.allowsActivation else { return }
                    onTap(day)
                } label: { content(day) }
                .blockActivationControl()
                    .buttonStyle(.plain)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: row)
        .background(bandLayer)
    }

    private func content(_ day: Date) -> some View {
        let endpoint = isEndpoint(day)
        return Text("\(cal.component(.day, from: day))")
            .font(.system(size: 15, weight: endpoint ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
            .underline(isToday(day), color: Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: pill)
            .background(
                InputOptionBackground(selected: true, radius: 12)
                    .padding(.horizontal, 2.5)
                    .opacity(endpoint ? 1 : 0))
    }

    @ViewBuilder
    private var bandLayer: some View {
        switch band {
        case .none:
            Color.clear
        case .full:
            InputPalette.tile.frame(height: pill)
        case .leading:
            HStack(spacing: 0) { InputPalette.tile; Color.clear }.frame(height: pill)
        case .trailing:
            HStack(spacing: 0) { Color.clear; InputPalette.tile }.frame(height: pill)
        }
    }

    private func isEndpoint(_ day: Date) -> Bool {
        isSame(day, start) || isSame(day, end)
    }

    private func isSame(_ a: Date, _ b: Date?) -> Bool {
        guard let b else { return false }
        return cal.isDate(a, inSameDayAs: b)
    }

    private func isToday(_ day: Date) -> Bool { cal.isDate(day, inSameDayAs: today) }
}
