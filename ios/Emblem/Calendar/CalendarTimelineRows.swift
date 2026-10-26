import SwiftUI

enum CalendarMetrics {
    static let edge: CGFloat = 20
    static let time: CGFloat = 48
    static let marker: CGFloat = 72
    static let content: CGFloat = 80

    static func red(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .red : Color(.sRGB, red: 1, green: 0, blue: 0)
    }

    static func ink(_ accent: Accent) -> Color { accent.tint(Theme.ink) }

    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
}

struct CalendarSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct CalendarTimeLabel: View {
    let date: Date
    let calendar: Calendar
    var tone: Color = Theme.ink

    var body: some View {
        let parts = CalendarClock.parts(date, calendar: calendar)
        VStack(alignment: .leading, spacing: 1) {
            Text(parts.time).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(tone)
            if let meridiem = parts.meridiem {
                Text(meridiem).font(.system(size: 13)).foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(width: CalendarMetrics.time, alignment: .leading)
    }
}

private struct CalendarMarker<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: CalendarMetrics.marker - CalendarMetrics.time, alignment: .trailing)
            .frame(width: CalendarMetrics.content - CalendarMetrics.time, alignment: .leading)
    }
}

struct CalendarEventRow: View {
    let event: CalendarAgendaEvent
    let calendar: Calendar
    let now: Date?
    var emphasized = false
    var compact = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accent) private var accent

    private var past: Bool { now.map { event.end <= $0 } ?? false }
    private var progress: Double? {
        guard let now, event.start <= now, event.end > now, event.minutes > 0 else { return nil }
        return now.timeIntervalSince(event.start) / event.end.timeIntervalSince(event.start)
    }

    private func progressBar(_ fraction: Double) -> some View {
        GeometryReader { geometry in
            Capsule().fill(CalendarMetrics.ink(accent))
                .frame(width: max(4, geometry.size.width * fraction), height: 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityHidden(true)
    }
    private var height: CGFloat { compact ? 0 : 40 + min(40, CGFloat(event.minutes) * 0.25) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                if event.isAllDay {
                    Text("All day").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSecondary)
                        .frame(width: CalendarMetrics.time, alignment: .leading)
                } else {
                    CalendarTimeLabel(date: event.start, calendar: calendar)
                }
            }
            .padding(.top, emphasized ? 21 : 2)
            VStack(alignment: .leading, spacing: 2) {
                if emphasized, let now, let countdown = CalendarClock.countdown(for: event, now: now) {
                    Text(CalendarClock.leave(for: event, now: now, travel: CalendarTravel.shared.minutes(to: event, now: now),
                                             countdown: countdown, calendar: calendar))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CalendarMetrics.ink(accent))
                        .padding(.bottom, 2)
                }
                Text(event.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                if let place = event.place {
                    Text(place).font(.system(size: 15)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                }
            }
            .overlay(alignment: .leading) {
                Capsule().fill(event.tint).frame(width: 3).padding(.vertical, 2).offset(x: -12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, CalendarMetrics.content - CalendarMetrics.time)
            .padding(.vertical, emphasized ? 16 : 0)
            .padding(.trailing, 16)
        }
        .frame(minHeight: height, alignment: .top)
        .padding(.vertical, 8)
        .background {
            if emphasized {
                let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                shape.fill(Theme.surface)
                    .overlay { shape.strokeBorder(CalendarMetrics.hairline(colorScheme), lineWidth: 0.5) }
                    .overlay(alignment: .bottom) { if let progress { progressBar(progress) } }
                    .padding(.leading, CalendarMetrics.time + 8)
            }
        }
        .opacity(past ? 0.45 : 1)
        .contentShape(Rectangle())
    }
}

struct CalendarTodoRow: View {
    let todo: CalendarAgendaTodo
    let calendar: Calendar
    let toggle: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                if todo.timed {
                    CalendarTimeLabel(date: todo.due, calendar: calendar)
                } else {
                    Color.clear.frame(width: CalendarMetrics.time, height: 1)
                }
            }
            .padding(.top, 2)
            CalendarMarker {
                Button(action: toggle) {
                    ZStack {
                        Circle().strokeBorder(Theme.inkSecondary.opacity(todo.done ? 0 : 0.55), lineWidth: 1.5)
                        Circle().fill(CalendarMetrics.ink(accent)).scaleEffect(todo.done ? 1 : 0.2).opacity(todo.done ? 1 : 0)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(accent.isNeutral ? Theme.onAccent : .white)
                            .scaleEffect(todo.done ? 1 : 0.4)
                            .opacity(todo.done ? 1 : 0)
                    }
                    .frame(width: 20, height: 20)
                    .contentShape(Circle().inset(by: -10))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: todo.done) { _, done in done }
                .accessibilityLabel(todo.title)
                .accessibilityValue(todo.done ? "Done" : "Not done")
                .accessibilityIdentifier("calendar-todo-" + todo.id)
            }
            .padding(.top, 2)
            Text(todo.title)
                .font(.system(size: 17))
                .strikethrough(todo.done, color: Theme.inkSecondary)
                .foregroundStyle(todo.done ? Theme.inkSecondary : Theme.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 1)
                .padding(.trailing, 16)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
    }
}

private struct Hatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 8
        }
        return path
    }
}

struct CalendarFreeBand: View {
    let slot: CalendarFreeSlot
    let calendar: Calendar
    var timeColumn = true
    let action: () -> Void
    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(alignment: .center, spacing: 0) {
            if timeColumn {
                CalendarTimeLabel(date: slot.start, calendar: calendar, tone: Theme.inkSecondary)
                    .opacity(slot.wholeDay ? 0 : 1)
                    .padding(.trailing, 8)
            }
            Button(action: action) {
                HStack(spacing: 6) {
                    Text(slot.label).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                    if !slot.restOfDay {
                        Text(slot.trailing ? "rest of the day" : "until " + CalendarClock.short(slot.end, calendar: calendar))
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CalendarMetrics.ink(accent))
                }
                .padding(.leading, timeColumn ? CalendarMetrics.content - CalendarMetrics.time - 8 : 16)
                .padding(.trailing, 16)
                .frame(height: slot.wholeDay ? 56 : 44)
                .background {
                    Hatch()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07), lineWidth: 1)
                        .clipShape(shape)
                }
                .contentShape(shape)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(slot.label + ", " + CalendarClock.range(slot.start, slot.end, calendar: calendar))
            .accessibilityHint("Adds something at this time")
            .accessibilityIdentifier("calendar-free-" + slot.id)
        }
        .padding(.vertical, 8)
    }
}

struct CalendarNowLine: View {
    let now: Date
    let calendar: Calendar
    @Environment(\.accent) private var accent

    var body: some View {
        let ink = CalendarMetrics.ink(accent)
        HStack(spacing: 0) {
            Circle().fill(ink).frame(width: 7, height: 7)
                .frame(width: CalendarMetrics.marker - 1.5, alignment: .trailing)
            Rectangle().fill(ink).frame(height: 1)
        }
        .frame(height: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now, " + CalendarClock.short(now, calendar: calendar))
    }
}

struct CalendarBriefLine: View {
    let text: String?

    var body: some View {
        if let text {
            Text(Self.styled(text))
                .font(.system(size: 20))
                .foregroundStyle(Theme.inkSecondary)
                .tint(Theme.ink)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        }
    }

    static func styled(_ text: String, size: CGFloat = 20) -> AttributedString {
        var value = (try? AttributedString(markdown: text)) ?? AttributedString(text)
        let strong = value.runs.filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true || $0.link != nil }
            .map(\.range)
        for range in strong {
            value[range].foregroundColor = Theme.ink
            value[range].font = .system(size: size, weight: .semibold)
        }
        return value
    }
}

struct CalendarNextDayRow: View {
    let title: String
    let summary: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                    Text(CalendarBriefLine.styled(summary, size: 17))
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.surface, in: shape)
            .overlay { shape.strokeBorder(CalendarMetrics.hairline(colorScheme), lineWidth: 0.5) }
            .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("calendar-next-day")
    }
}

struct CalendarNoticeRow: View {
    let notice: CalendarAgendaFeed.Notice
    let feed: CalendarAgendaFeed
    @Environment(\.openURL) private var openURL
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(message).font(.system(size: 15)).foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: act) {
                Text(actionTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(CalendarMetrics.ink(accent))
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("calendar-notice-action")
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar-notice")
    }

    private var message: String {
        switch notice {
        case .allowEvents: "See your calendar and reminders here."
        case .eventsOff: "Calendar access is off."
        case .eventsAddOnly: "Emblem can add events but can't see them."
        case .googleFailed: "Google Calendar didn't load."
        case .offline: "You're offline. Showing what's on this iPhone."
        }
    }

    private var actionTitle: String {
        switch notice {
        case .allowEvents: "Allow"
        case .eventsOff, .eventsAddOnly: "Settings"
        case .googleFailed, .offline: "Retry"
        }
    }

    private func act() {
        switch notice {
        case .allowEvents: feed.requestAccess()
        case .eventsOff, .eventsAddOnly:
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        case .googleFailed, .offline: feed.loadGoogle(around: feed.now, force: true)
        }
    }
}
