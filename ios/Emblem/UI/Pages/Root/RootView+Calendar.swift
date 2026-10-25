import SwiftUI
import UIKit
import EmblemCore

extension RootView {
    static let calendarParentKey = "calendar"

    var eventDetailLoading: Bool {
        guard let page = store.currentPage, page.expansionSource?.contentStyle == .event else { return false }
        return page.isStreaming && page.visibleBlocks.allSatisfy {
            switch $0 { case .hero, .titleBlock: true; default: false }
        }
    }

    var calendarIsTopmost: Bool { primaryIsTopmost && primaryRoot?.destination == .calendar }

    func openCalendar() {
        mapPresentation = nil
        comparisonPresentation = nil
        savedEntitySelection = nil
        savedEntry = nil
        let zone = TimeZone.current
        calendarSelection = try? CalendarBrowserSelection(
            date: CalendarBrowserDay(date: .now, timeZone: zone), mode: calendarSelection?.mode ?? .daily,
            timeZone: zone.identifier)
        CalendarAgendaFeed.shared.refreshClock()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            primaryDestination = nil
            primaryRoot = PrimaryRoot(destination: .calendar, homePageID: store.pages.first?.id,
                                      pageIDs: store.navigationPageIDs, scopeID: savedPages.scopeID)
        }
        closeSidebar()
    }

    func calendarPeriodBody(_ period: CalendarBrowserSnapshot) -> some View {
        CalendarPeriodView(period: period, actions: CalendarPeriodActions(
            feed: .shared, namespace: expansionNamespace, open: openCalendarEvent,
            presented: Set(store.pages.filter { $0.parentPageKey == Self.calendarParentKey }
                .compactMap { $0.expansionSource?.sourceCardKey }),
            ideas: calendarIdeas))
        .environment(\.performAction, performAction)
    }

    private var calendarIdeas: [CardCarousel.Card] {
        for block in store.homePage?.blocks ?? [] {
            if case .cardCarousel(let carousel) = block, carousel.id == "ideas" { return carousel.cards }
        }
        return []
    }

    var calendarAccessory: some View {
        let feed = CalendarAgendaFeed.shared
        let typing = store.dockState == .keyboard
        return ZStack(alignment: .bottom) {
            if calendarIsTopmost {
                VStack(spacing: 0) {
                    LinearGradient(stops: [.init(color: Theme.sidebarBackground.opacity(0), location: 0),
                                           .init(color: Theme.sidebarBackground.opacity(0.94), location: 0.35),
                                           .init(color: Theme.sidebarBackground, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: typing ? 110 : 220)
                    Theme.sidebarBackground.frame(height: typing ? KeyboardPresence.shared.lastHeight + 50 : 0)
                }
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            if let selection = calendarSelection, calendarIsTopmost, !typing {
                CalendarDockAccessory(feed: feed, calendar: selection.calendar, day: selection.selectedInstant) { prompt in
                    feed.isFront = false
                    _ = store.send(prompt)
                }
                .padding(.bottom, 92)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(DockView.keyboardCurve, value: typing)
        .task { await feed.runClock() }
        .task(id: calendarSelection?.selectedDate) {
            guard let selection = calendarSelection else { return }
            await feed.loadGoogle(around: selection.selectedInstant)
        }
        .onChange(of: calendarIsTopmost, initial: true) { _, topmost in
            feed.isFront = topmost
            feed.onFocus = { date in
                guard let selection = calendarSelection else { return }
                selection.propose({ try $0.chooseDay(CalendarBrowserDay(date: date, timeZone: selection.zone)) },
                                  accepting: { _ in true })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshCalendarClock()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshCalendarClock()
        }
    }

    func refreshCalendarClock() {
        let feed = CalendarAgendaFeed.shared
        feed.refreshClock()
        feed.invalidate()
        guard let selection = calendarSelection, selection.timeZone != TimeZone.current.identifier,
              let moved = try? CalendarBrowserSelection(date: selection.selectedDate, mode: selection.mode,
                                                        timeZone: TimeZone.current.identifier) else { return }
        calendarSelection = moved
    }

    func openCalendarEvent(_ event: CalendarAgendaEvent) {
        let feed = CalendarAgendaFeed.shared
        guard let selection = calendarSelection else { return }
        let calendar = selection.calendar
        let dayLabel = CalendarClock.text(event.start, calendar: calendar, format: "EEEE, MMMM d")
        let timeRange = event.isAllDay ? "All day" : CalendarClock.range(event.start, event.end, calendar: calendar)
        let details = CalendarEventDetails(title: event.title, dayLabel: dayLabel, timeRange: timeRange,
                                           place: event.place, attendees: event.attendees)
        let card = CardCarousel.Card(icon: Icon(sfSymbol: "calendar"), title: event.title, caption: timeRange)
        let source = PageExpansionSource(parentPageID: feed.transitionAnchor, parentPageKey: Self.calendarParentKey,
                                         sourceCardKey: event.id, card: card, contentStyle: .event,
                                         calendarEvent: details)
        let prompt = "Tell me about my calendar event \"\(event.title)\" on \(dayLabel) (\(timeRange))"
            + (event.place.map { " at \($0)" } ?? "") + "."
        feed.openingEventID = event.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(34))
            store.openCalendarEvent(source, prompt: prompt)
            feed.openingEventID = nil
        }
    }
}
