import SwiftUI
import UIKit
import EmblemCore

extension RootView {
    var calendarPage: GeneratedPage? {
        store.pages.last(where: { $0.calendarContext != nil })
    }

    var eventDetailLoading: Bool {
        guard let page = store.currentPage, page.expansionSource?.contentStyle == .event else { return false }
        return page.isStreaming && page.visibleBlocks.allSatisfy {
            switch $0 { case .hero, .titleBlock: true; default: false }
        }
    }

    var calendarIsTopmost: Bool {
        (primaryIsTopmost && primaryRoot?.destination == .calendar)
            || navigationPath.wrappedValue.last == .primary(.calendar)
    }

    func openCalendar() {
        mapPresentation = nil
        comparisonPresentation = nil
        savedEntitySelection = nil
        savedEntry = nil
        let zone = TimeZone.current
        let today = CalendarBrowserDay(date: .now, timeZone: zone)
        if let page = calendarPage,
           page.calendarContext?.date == today.id, page.calendarContext?.mode == .daily,
           let index = store.navigationPageIDs.firstIndex(of: page.id) {
            let firstCalendarIndex = store.navigationPageIDs.firstIndex { id in
                store.pages.first(where: { $0.id == id })?.calendarContext != nil
            } ?? index
            let origin = Array(store.navigationPageIDs.prefix(firstCalendarIndex))
            let retainedPath = Array(store.navigationPageIDs.prefix(index + 1))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                store.popNavigationPath(to: retainedPath)
                primaryDestination = nil
                primaryRoot = PrimaryRoot(destination: .calendar, homePageID: store.pages.first?.id,
                                          pageIDs: origin, scopeID: savedPages.scopeID)
            }
            closeSidebar()
            return
        }
        calendarSelection = try? CalendarBrowserSelection(date: today, timeZone: zone.identifier)
        guard let selection = calendarSelection else { return }
        if let firstCalendarIndex = store.navigationPageIDs.firstIndex(where: { id in
            store.pages.first(where: { $0.id == id })?.calendarContext != nil
        }) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                store.popNavigationPath(to: Array(store.navigationPageIDs.prefix(firstCalendarIndex)))
            }
        }
        let origin = store.navigationPageIDs
        var accepted = false
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            accepted = generateCalendar(selection.intent(.initial))
            if accepted {
                primaryDestination = nil
                primaryRoot = PrimaryRoot(destination: .calendar, homePageID: store.pages.first?.id,
                                          pageIDs: origin, scopeID: savedPages.scopeID)
            }
        }
        if accepted { closeSidebar() }
    }

    func generateCalendar(_ intent: CalendarBrowserIntent) -> Bool {
        let mode: CalendarGenerationContext.Mode
        switch intent.selection.scope {
        case .day: mode = .daily
        case .week: mode = .weekly
        case .month: mode = .monthly
        }
        guard let context = try? CalendarGenerationContext(
            date: intent.selection.selectedDate.id, timeZone: intent.selection.timeZone, mode: mode)
        else { return false }
        if let source = store.currentPage, source.calendarContext != nil {
            switch store.selectCalendarPage(context: context, from: source, expectedScope: savedPages.scopeID) {
            case .selected: return true
            case .rejected: return false
            case .notKnown: break
            }
        }
        return store.sendCalendar(intent.prompt, context: context)
    }

    func calendarPeriodBody(_ period: CalendarBrowserSnapshot) -> some View {
        let mode: CalendarGenerationContext.Mode = period.scope == .day ? .daily : period.scope == .week ? .weekly : .monthly
        let page: GeneratedPage? = (try? CalendarGenerationContext(
            date: period.selectedDate.id, timeZone: period.timeZone, mode: mode)).flatMap { context in
            calendarPage.flatMap { store.knownCalendarPage(context: context, from: $0, expectedScope: savedPages.scopeID) }
        }.flatMap { !$0.visibleBlocks.isEmpty || !$0.isStreaming ? $0 : nil }
        return ZStack {
            if let page {
                PageView(page: page, expansionNamespace: expansionNamespace).id(page.id)
                    .safeAreaPadding(.top, 15)
                    .environment(\.calendarAgenda, true)
                    .environment(\.calendarAgendaDaily, period.scope == .day)
                    .transition(.identity)
            } else {
                CalendarGenerationSkeleton()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.12), value: page?.id)
    }
}
