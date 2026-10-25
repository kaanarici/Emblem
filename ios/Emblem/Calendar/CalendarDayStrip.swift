import SwiftUI

@Observable final class CalendarPagerTrack {
    var offset: CGFloat = 0
    var stride: CGFloat = 0
    var tracking = false
}

struct CalendarDayStrip: View {
    let selection: CalendarBrowserSelection
    let pager: CalendarPagerTrack
    let anchor: CalendarBrowserDay
    let reach: Int
    let onSelect: (CalendarBrowserIntent) -> Bool
    @Environment(\.colorScheme) private var colorScheme

    private static let weekdays = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    private static let inset: CGFloat = 6
    private static let height: CGFloat = 56

    var body: some View {
        let calendar = selection.calendar
        let anchorDate = anchor.date(in: selection.zone) ?? selection.selectedInstant
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: anchorDate)?.start ?? anchorDate
        let anchorCell = CGFloat(calendar.dateComponents([.day], from: weekStart, to: anchorDate).day ?? 0)
        let position = anchorCell + daysFromAnchor(calendar: calendar, anchorDate: anchorDate)
        let week = Int((position.rounded() / 7).rounded(.down))
        GeometryReader { proxy in
            let cell = (proxy.size.width - 2 * Self.inset) / 7
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .circular)
                    .fill(colorScheme == .dark ? Theme.ink.opacity(0.12) : Theme.surface)
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
                    .frame(width: 46, height: Self.height)
                    .offset(x: position * cell + (cell - 46) / 2)
                ForEach((week - 1) * 7 ..< (week + 2) * 7, id: \.self) { index in
                    let date = calendar.date(byAdding: .day, value: index, to: weekStart) ?? weekStart
                    dayCell(CalendarBrowserDay(date: date, timeZone: selection.zone),
                            weekday: Self.weekdays[((index % 7) + 7) % 7],
                            emphasis: max(0, 1 - abs(CGFloat(index) - position)), width: cell)
                        .offset(x: CGFloat(index) * cell)
                }
            }
            .offset(x: Self.inset - CGFloat(week * 7) * cell)
            .animation(.easeInOut(duration: 0.29), value: week)
        }
        .frame(height: Self.height)
        .mask { Rectangle().padding(.vertical, -24) }
        .padding(.vertical, -5.0 / 3)
    }

    private func daysFromAnchor(calendar: Calendar, anchorDate: Date) -> CGFloat {
        if pager.tracking { return pager.offset / pager.stride - CGFloat(reach) }
        let selected = selection.selectedInstant
        return CGFloat(calendar.dateComponents([.day], from: anchorDate, to: selected).day ?? 0)
    }

    private func dayCell(_ day: CalendarBrowserDay, weekday: String, emphasis: CGFloat, width: CGFloat) -> some View {
        let selected = day == selection.selectedDate
        return Button {
            selection.propose({ try $0.chooseDay(day) }, accepting: onSelect)
        } label: {
            VStack(spacing: 0) {
                Text(weekday)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(labelInk.mix(with: selectedRed, by: emphasis))
                    .frame(height: 15)
                    .padding(.top, 9.2)
                Text(String(day.day))
                    .font(.system(size: 20 + 4 * emphasis, weight: .medium))
                    .tracking(-1 - 0.2 * emphasis)
                    .fixedSize()
                    .frame(height: 24, alignment: .top)
                Spacer(minLength: 0)
            }
            .frame(width: width, height: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(selection.text(day, format: "EEEE, MMMM d, yyyy"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("calendar-day-" + day.id)
    }

    private var selectedRed: Color {
        colorScheme == .dark ? .red : Color(.sRGB, red: 1, green: 0, blue: 0)
    }

    private var labelInk: Color {
        colorScheme == .dark ? Theme.inkSecondary : Color(white: 0.655)
    }
}
