import SwiftUI
import EmblemCore

extension EnvironmentValues {
    @Entry var calendarAgenda = false
    @Entry var calendarAgendaDaily = false
}

struct EventCardView: View {
    let block: EventCard
    @Environment(\.calendarAgenda) private var agenda
    @Environment(\.calendarAgendaDaily) private var daily
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.renderedPage) private var renderedPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = Int.max

    private func card(for event: EventCard.Event) -> CardCarousel.Card {
        CardCarousel.Card(
            image: nil,
            imageURL: nil,
            icon: event.icon,
            title: event.title,
            caption: agenda ? [event.timeRange, event.place].compactMap { $0 }.filter { !$0.isEmpty }
                .joined(separator: " • ") : event.timeRange,
            meta: block.dayLabel,
            prompt: event.prompt ?? "Tell me more about my calendar event " +
                "\"\(event.title)\" on \(block.dayLabel) (\(event.timeRange))" +
                (event.place.map { $0.isEmpty ? "" : " at \($0)" } ?? "") + ".")
    }

    var body: some View {
        if agenda { agendaBody } else { cardBody }
    }

    private var agendaBody: some View {
        let groups = EventGap.sections(block.events, byPartOfDay: daily)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                agendaSection(index: index, group: group)
                    .opacity(index < revealed ? 1 : 0)
            }
        }
        .animation(.easeOut(duration: 0.23), value: groups.count)
        .padding(.horizontal, 28)
        .padding(.top, -7)
        .padding(.bottom, 4)
        .onAppear { revealSections(groups.count) }
    }

    private func revealSections(_ count: Int) {
        guard !reduceMotion, count > 0, let page = renderedPage,
              TextSweep.claim(page: page.id, block: block.id + "#sections") else { return }
        revealed = 0
        Task { @MainActor in
            for next in 1...count {
                if next > 1 { try? await Task.sleep(for: .milliseconds(250)) }
                withAnimation(.easeOut(duration: 0.23)) { revealed = next }
            }
            revealed = .max
        }
    }

    @ViewBuilder
    private func agendaSection(index: Int, group: EventGap.Section) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = daily ? group.title : (index == 0 ? block.dayLabel : nil) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 4.67)
                    .padding(.top, index == 0 ? 0 : 31)
                    .padding(.bottom, 14)
            }
            if !daily, group.allDay {
                Text("All day")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 4.67)
                    .padding(.bottom, 12)
            } else if !daily, index > 0 {
                Color.clear.frame(height: 16)
            }
            ForEach(Array(group.events.enumerated()), id: \.offset) { position, event in
                if position > 0 {
                    if let gap = EventGap.label(after: group.events[position - 1].timeRange,
                                                before: event.timeRange) {
                        Text(gap)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(white: colorScheme == .dark ? 0.45 : 0.64))
                            .frame(maxWidth: .infinity)
                            .frame(height: 33.3)
                    } else {
                        Color.clear.frame(height: 16)
                    }
                }
                agendaCard(event)
            }
        }
    }

    private static let agendaElevation = CardElevation(corner: 21, ambient: (0.14, 16, 6))

    private func agendaCard(_ event: EventCard.Event) -> some View {
        let shape = RoundedRectangle(cornerRadius: 21, style: .continuous)
        return VStack(alignment: .leading, spacing: 4.5) {
            Text(event.timeRange)
                .font(.system(size: 14))
                .foregroundStyle(Color(white: colorScheme == .dark ? 0.62 : 0.39))
            Text(event.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            if let place = event.place, !place.isEmpty {
                Text(place)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(white: colorScheme == .dark ? 0.62 : 0.4))
            }
        }
        .lineLimit(2)
        .padding(.horizontal, 17)
        .padding(.vertical, 19.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: shape)
        .contentShape(shape)
        .modifier(ExpandsIntoSubpage(card: card(for: event), blockID: block.id, contentStyle: .event,
                                     elevation: Self.agendaElevation))
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(block.dayLabel)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 8)

            VStack(spacing: 10) {
                ForEach(Array(block.events.enumerated()), id: \.offset) { _, event in
                    HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.timeRange)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.inkSecondary)
                                Text(event.title)
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                            }
                            Spacer(minLength: 10)
                            IconView(icon: event.icon, size: 40)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .modifier(ExpandsIntoSubpage(card: card(for: event), blockID: block.id, elevation: .flat(18)))
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .cardBackground(radius: 24)
        .padding(.horizontal, Theme.contentMargin)
    }
}

enum EventGap {
    struct Section {
        var title: String?
        var allDay: Bool
        var events: [EventCard.Event]
    }

    static func sections(_ events: [EventCard.Event], byPartOfDay: Bool) -> [Section] {
        let allDay = events.filter { minutes($0.timeRange, last: false) == nil }
        let timed = events.filter { minutes($0.timeRange, last: false) != nil }
        var sections: [Section] = allDay.isEmpty ? [] : [Section(title: byPartOfDay ? "All day" : nil,
                                                                  allDay: true, events: allDay)]
        guard byPartOfDay else {
            if !timed.isEmpty { sections.append(Section(title: nil, allDay: false, events: timed)) }
            return sections
        }
        for event in timed {
            let start = minutes(event.timeRange, last: false) ?? 0
            let title = start < 12 * 60 ? "Morning" : start < 17 * 60 ? "Afternoon" : "Evening"
            if sections.last?.title == title, sections.last?.allDay == false {
                sections[sections.count - 1].events.append(event)
            } else {
                sections.append(Section(title: title, allDay: false, events: [event]))
            }
        }
        return sections
    }

    static func label(after previous: String, before next: String) -> String? {
        guard let end = minutes(previous, last: true),
              let start = minutes(next, last: false) else { return nil }
        let gap = start - end
        guard gap > 0, gap < 120 else { return nil }
        let hours = gap / 60, minutes = gap % 60
        if hours == 0 { return "\(minutes) minute gap" }
        return minutes == 0 ? "1 hour gap" : "1 hour \(minutes) minute gap"
    }

    static func minutes(_ range: String, last: Bool) -> Int? {
        let pattern = /(\d{1,2})(?:[:.](\d{2}))?\s*([AaPp]\.?[Mm]\.?)?/
        let times = range.matches(of: pattern)
        let index = last ? 1 : 0
        guard (1...2).contains(times.count), index < times.count else { return nil }
        let meridiems = times.map { $0.output.3.map { $0.lowercased().hasPrefix("p") } }
        let match = times[index]
        guard var hour = Int(match.output.1), hour < 24 else { return nil }
        let minute = match.output.2.flatMap { Int($0) } ?? 0
        guard minute < 60 else { return nil }
        if let pm = meridiems[index] ?? meridiems[times.count - 1] {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (pm ? 12 : 0)
        }
        return hour * 60 + minute
    }
}
