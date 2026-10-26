import EmblemCore
import SwiftUI

struct CalendarPeriodActions {
    let feed: CalendarAgendaFeed
    let namespace: Namespace.ID
    let open: (CalendarAgendaEvent) -> Void
    var presented: Set<String> = []
    var ideas: [CardCarousel.Card] = []
}

struct CalendarPeriodView: View {
    let period: CalendarBrowserSnapshot
    let actions: CalendarPeriodActions

    var body: some View {
        switch period.scope {
        case .day: CalendarDayTimeline(period: period, actions: actions)
        case .week: CalendarWeekView(period: period, actions: actions)
        case .month: CalendarMonthView(period: period, actions: actions)
        }
    }
}

struct CalendarEventButton<Content: View>: View {
    let event: CalendarAgendaEvent
    let actions: CalendarPeriodActions
    @ViewBuilder let label: () -> Content

    var body: some View {
        let feed = actions.feed
        Button { actions.open(event) } label: {
            label()
                .matchedTransitionSource(id: "\(feed.transitionAnchor.uuidString):\(event.id)",
                                         in: actions.namespace) { source in
                    source.background(Theme.sidebarBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .opacity(actions.presented.contains(event.id) || feed.openingEventID == event.id ? 0 : 1)
        }
        .buttonStyle(.pressable)
        .contextMenu { menu }
        .accessibilityIdentifier("calendar-event-" + event.id)
    }

    @ViewBuilder
    private var menu: some View {
        let feed = actions.feed
        if event.editable {
            Menu {
                Button("15 minutes later") { feed.move(event, by: 15) }
                Button("30 minutes later") { feed.move(event, by: 30) }
                Button("1 hour later") { feed.move(event, by: 60) }
                Button("Same time tomorrow") { feed.move(event, by: 24 * 60) }
            } label: {
                Label("Move", systemImage: "arrow.up.and.down")
            }
            Menu {
                ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                    Button(CalendarClock.duration(minutes)) { feed.resize(event, to: minutes) }
                }
            } label: {
                Label("Duration", systemImage: "timer")
            }
            Divider()
            Button(role: .destructive) { feed.delete(event) } label: {
                Label("Delete", systemImage: "trash")
            }
        } else if case .google(_, let url?) = event.source {
            Link(destination: url) { Label("Open in Google Calendar", systemImage: "arrow.up.right") }
        } else {
            Text("This calendar is read-only")
        }
    }
}

struct CalendarDayTimeline: View {
    let period: CalendarBrowserSnapshot
    let actions: CalendarPeriodActions
    @State private var showsEarlier = false
    @State private var positioned = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let calendar = period.calendar
        let feed = actions.feed
        let now = feed.now
        let today = period.interval.holds(now)
        let plan = CalendarDayPlan(events: feed.events(in: period.interval), todos: feed.todos(in: period.interval),
                                   draft: feed.draft, day: period.interval, calendar: calendar, now: now)
        let earlier: [CalendarDayPlan.Item] = today && !showsEarlier
            ? Array(plan.items.prefix(while: { $0.end <= now })) : []
        let items = plan.isEmpty ? [] : Array(plan.items.dropFirst(earlier.count))
        let marker = today ? plan.marker(at: now) : nil
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let notice = feed.notice { CalendarNoticeRow(notice: notice, feed: feed).padding(.bottom, 8) }
                    CalendarBriefLine(text: feed.brief(for: period))
                        .padding(.bottom, 16)
                        .environment(\.openURL, OpenURLAction { url in follow(url, plan: plan, proxy: proxy) })
                    ForEach(plan.allDay) { event in
                        CalendarEventButton(event: event, actions: actions) {
                            CalendarEventRow(event: event, calendar: calendar, now: nil, compact: true)
                        }
                    }
                    if !plan.anytime.isEmpty || plan.anytimeDraft {
                        CalendarSectionLabel(text: "To do").padding(.top, 16).id("todos")
                        ForEach(plan.anytime) { todo in
                            CalendarTodoRow(todo: todo, calendar: calendar) { feed.toggle(todo) }
                        }
                        if plan.anytimeDraft {
                            CalendarAddCard(feed: feed, calendar: calendar)
                                .padding(.leading, CalendarMetrics.time + 8)
                                .padding(.vertical, 8)
                                .id("draft")
                        }
                    }
                    if !earlier.isEmpty {
                        earlierToggle(earlier.reduce(0) { count, item in
                            if case .events(let events) = item { return count + events.count }
                            return count + 1
                        })
                        .padding(.top, 16)
                    }
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            itemView(item, plan: plan, calendar: calendar, now: today ? now : nil)
                                .overlay(alignment: .topLeading) {
                                    if let marker, marker.id == item.id {
                                        GeometryReader { geometry in
                                            CalendarNowLine(now: now, calendar: calendar)
                                                .offset(y: marker.fraction * geometry.size.height - 8)
                                        }
                                    }
                                }
                                .id(item.id)
                        }
                    }
                    .padding(.top, earlier.isEmpty && plan.anytime.isEmpty && !plan.anytimeDraft ? 0 : 8)
                    if plan.isEmpty {
                        CalendarEmptyDay(period: period, plan: plan, actions: actions)
                    }
                    if period.interval.end > now,
                       let next = calendar.date(byAdding: .day, value: 1, to: period.interval.start),
                       let after = calendar.date(byAdding: .day, value: 1, to: next) {
                        let day = DateInterval(start: next, end: after)
                        CalendarNextDayRow(
                            title: calendar.isDate(next, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
                                ? "Tomorrow" : CalendarClock.text(next, calendar: calendar, format: "EEEE"),
                            summary: CalendarBrief.nextDay(feed.events(in: day), day: day, calendar: calendar)) {
                            feed.onFocus?(next)
                        }
                        .padding(.top, 32)
                    }
                }
                .padding(.horizontal, CalendarMetrics.edge)
                .padding(.top, 24)
                .padding(.bottom, 200)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                guard !positioned else { return }
                positioned = true
                if plan.anytimeDraft || plan.items.contains(where: { $0.id == "draft" }) {
                    proxy.scrollTo("draft", anchor: UnitPoint(x: 0.5, y: 0.4))
                } else if earlier.isEmpty, let target = marker?.id {
                    proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: 0.35))
                }
            }
            .onChange(of: feed.nowRequest) {
                guard today else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) {
                    if let target = marker?.id {
                        proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: 0.35))
                    } else if let first = items.first?.id {
                        proxy.scrollTo(first, anchor: .top)
                    }
                }
            }
            .onChange(of: feed.draft?.id) { _, id in
                guard id != nil else { return }
                withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo("draft", anchor: UnitPoint(x: 0.5, y: 0.4)) }
            }
        }
    }

    @ViewBuilder
    private func itemView(_ item: CalendarDayPlan.Item, plan: CalendarDayPlan, calendar: Calendar,
                          now: Date?) -> some View {
        switch item {
        case .events(let events):
            VStack(spacing: 0) {
                ForEach(events) { event in
                    CalendarEventButton(event: event, actions: actions) {
                        CalendarEventRow(event: event, calendar: calendar, now: now,
                                         emphasized: event.id == plan.nextID
                                            && now.flatMap { CalendarClock.countdown(for: event, now: $0) } != nil)
                    }
                }
            }
        case .todo(let todo):
            CalendarTodoRow(todo: todo, calendar: calendar) { actions.feed.toggle(todo) }
        case .draft(let draft):
            HStack(alignment: .top, spacing: 0) {
                CalendarTimeLabel(date: draft.start, calendar: calendar).padding(.top, 18)
                CalendarAddCard(feed: actions.feed, calendar: calendar).padding(.leading, 8)
            }
            .padding(.vertical, 8)
        case .free(let slot):
            CalendarFreeBand(slot: slot, calendar: calendar) { actions.feed.propose(slot) }
        }
    }

    private func follow(_ url: URL, plan: CalendarDayPlan, proxy: ScrollViewProxy) -> OpenURLAction.Result {
        guard url.scheme == CalendarBrief.scheme else { return .systemAction }
        let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        let motion: Animation? = reduceMotion ? nil : .smooth(duration: 0.4)
        switch url.host() {
        case "event":
            let events = plan.items.flatMap { item -> [CalendarAgendaEvent] in
                if case .events(let events) = item { return events }
                return []
            }
            if let event = events.first(where: { $0.id == id }) { actions.open(event) }
        case "slot":
            let slot = plan.items.lazy.compactMap { item -> CalendarFreeSlot? in
                if case .free(let slot) = item, slot.id == id { return slot }
                return nil
            }.first
            if let slot { actions.feed.propose(slot) }
        case "todos":
            withAnimation(motion) { proxy.scrollTo("todos", anchor: .top) }
        default:
            return .discarded
        }
        return .handled
    }

    private func earlierToggle(_ count: Int) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) { showsEarlier = true }
        } label: {
            HStack(spacing: 6) {
                Text(count == 1 ? "1 earlier event" : "\(count) earlier events")
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Shows events that already ended today")
    }
}
