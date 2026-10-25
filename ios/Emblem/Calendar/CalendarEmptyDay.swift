import EmblemCore
import SwiftUI

struct CalendarEmptyDay: View {
    let period: CalendarBrowserSnapshot
    let plan: CalendarDayPlan
    let actions: CalendarPeriodActions

    var body: some View {
        let feed = actions.feed
        let slot = plan.items.compactMap { item -> CalendarFreeSlot? in
            if case .free(let slot) = item { return slot }
            return nil
        }.first
        VStack(alignment: .leading, spacing: 0) {
            if let slot {
                CalendarFreeBand(slot: slot, calendar: period.calendar, timeColumn: false) { feed.propose(slot) }
            }
            if !actions.ideas.isEmpty, period.interval.end > feed.now {
                CalendarSectionLabel(text: "Ideas for a free day").padding(.top, 24).padding(.bottom, 8)
                CardCarouselView(block: CardCarousel(id: "ideas", cards: Array(actions.ideas.prefix(3))))
                    .padding(.horizontal, -Theme.contentMargin)
            }
        }
    }
}
