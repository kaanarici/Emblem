import Foundation
import SwiftUI
import EmblemCore

@MainActor
extension ConversationStore {
    func createCalendarEvent(_ spec: Action.CalendarSpec) {
        guard !isGenerating,
              let page = currentPage,
              let action = page.meta?.dockAction,
              action.calendar == spec,
              CalendarService.receiptStatus(for: spec.idempotencyKey) == .none
        else { return }
        guard (5...1_440).contains(spec.durationMinutes),
              let time = page.answers[spec.timeAnswerKey],
              let start = CalendarService.startDate(date: spec.date, time: time),
              start >= Date() else {
            showCalendarError(on: page, "Choose a valid future date and time before adding it.")
            return
        }

        if var meta = page.meta {
            meta.dockAction = nil
            page.meta = meta
        }
        Task { [weak self, weak page] in
            guard let self, let page else { return }
            let result = await CalendarService.shared.addEvent(
                title: spec.title,
                start: start,
                durationMinutes: spec.durationMinutes,
                idempotencyKey: spec.idempotencyKey)
            switch result {
            case .saved(let savedStart):
                self.showCalendarConfirmation(on: page, spec: spec, start: savedStart)
                self.reconcileCalendarActions()
            case .uncertain(let pendingStart):
                if CalendarService.shared.isWriteActive(for: spec.idempotencyKey) {
                    self.showCalendarSaving(on: page)
                } else {
                    self.showCalendarUncertain(on: page, spec: spec, start: pendingStart)
                }
            case .failed:
                if var meta = page.meta, meta.dockAction == nil {
                    meta.dockAction = action
                    page.meta = meta
                }
                self.reconcileCalendarActions()
                let matchingPages = self.pages.filter {
                    $0.meta?.dockAction?.calendar?.idempotencyKey == spec.idempotencyKey
                }
                for failedPage in matchingPages {
                    self.showCalendarError(
                        on: failedPage,
                        "Calendar access was denied or the event could not be saved.")
                }
                if !matchingPages.contains(where: { $0 === page }) {
                    self.showCalendarError(
                        on: page,
                        "Calendar access was denied or the event could not be saved.")
                }
            }
        }
    }

    func reconcileCalendarActions() {
        for page in pages {
            reconcileCalendarAction(on: page)
        }
    }

    func reconcileCalendarAction(on page: GeneratedPage) {
        page.blocks.removeAll { $0.id == "calendar-saving" }
        guard let spec = page.meta?.dockAction?.calendar else { return }
        switch CalendarService.receiptStatus(for: spec.idempotencyKey) {
        case .completed(let start):
            if var meta = page.meta {
                meta.dockAction = nil
                page.meta = meta
            }
            showCalendarConfirmation(on: page, spec: spec, start: start)
        case .pending(let start):
            if CalendarService.shared.isWriteActive(for: spec.idempotencyKey) {
                showCalendarSaving(on: page)
            } else {
                showCalendarUncertain(on: page, spec: spec, start: start)
            }
        case .none:
            break
        }
    }

    private func showCalendarSaving(on page: GeneratedPage) {
        page.blocks.removeAll {
            $0.id == "calendar-action-error" || $0.id == "calendar-saving"
        }
        page.blocks.append(.text(TextBlock(
            id: "calendar-saving",
            body: "Saving to Calendar…",
            style: .footnote)))
    }

    private func showCalendarConfirmation(
        on page: GeneratedPage,
        spec: Action.CalendarSpec,
        start: Date
    ) {
        showCalendarOutcome(
            on: page,
            spec: spec,
            start: start,
            title: "Added to calendar",
            subtitle: nil)
    }

    private func showCalendarUncertain(
        on page: GeneratedPage,
        spec: Action.CalendarSpec,
        start: Date
    ) {
        showCalendarOutcome(
            on: page,
            spec: spec,
            start: start,
            title: "Check Calendar",
            subtitle: "Saving was interrupted. Verify this event before adding another copy.")
    }

    private func showCalendarOutcome(
        on page: GeneratedPage,
        spec: Action.CalendarSpec,
        start: Date,
        title: String,
        subtitle: String?
    ) {
        let end = start.addingTimeInterval(TimeInterval(spec.durationMinutes * 60))
        let day = DateFormatter()
        day.dateFormat = "EEEE, MMMM d"
        let clock = DateFormatter()
        clock.timeStyle = .short
        clock.dateStyle = .none
        withAnimation(.smooth(duration: 0.3)) {
            page.blocks.removeAll { block in
                if case .timeAsk(let ask) = block { return ask.question == spec.timeAnswerKey }
                return [
                    "calendar-action-error",
                    "calendar-saving",
                    "calendar-confirmation",
                    "calendar-event",
                ].contains(block.id)
            }
            page.blocks.append(.sectionHeader(SectionHeader(
                id: "calendar-confirmation",
                title: title,
                subtitle: subtitle)))
            page.blocks.append(.eventCard(EventCard(
                id: "calendar-event",
                dayLabel: day.string(from: start),
                events: [.init(
                    timeRange: "\(clock.string(from: start)) – \(clock.string(from: end))",
                    title: spec.title,
                    icon: Icon(sfSymbol: "calendar"),
                    prompt: nil)])))
        }
    }

    private func showCalendarError(on page: GeneratedPage, _ message: String) {
        page.blocks.removeAll { $0.id == "calendar-action-error" }
        page.blocks.append(.text(TextBlock(
            id: "calendar-action-error",
            body: message,
            style: .footnote)))
    }
}

extension ConversationStore {
    @discardableResult
    func sendCalendar(_ prompt: String, context: CalendarGenerationContext) -> Bool {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return send(prompt, expansion: false, expansionSource: nil, calendarContext: context)
    }

    typealias CalendarPageSelection = GenerationRegistry.CalendarPageSelection

    func selectCalendarPage(context: CalendarGenerationContext, from source: GeneratedPage,
                            expectedScope: UUID) -> CalendarPageSelection {
        guard currentPage === source, SavedPagesStore.shared.scopeID == expectedScope,
              let key = source.conversationKey, !history.isRemoving(key) else { return .rejected }
        switch generationRegistry.calendarSelectionPlan(context: context, from: source,
                    navigationPages: pages, historyEpoch: history.epoch, expectedScope: expectedScope) {
        case .rejected: return .rejected
        case .notKnown: return .notKnown
        case .selected(_, let targetPages):
            guard let target = targetPages.last else { return .rejected }
            if currentPage !== target { VoiceOutput.shared.stop() }
            cancelRestore()
            let existingPath = pages + forwardPages.reversed()
            let keepsForward = existingPath.count >= targetPages.count &&
                zip(existingPath, targetPages).allSatisfy { pair in pair.0 === pair.1 }
            let remaining: [GeneratedPage] = keepsForward
                ? Array(existingPath.dropFirst(targetPages.count).reversed()) : []
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pages = targetPages
                forwardPages = remaining
                generationRegistry.select(page: target)
            }
            return .selected(actualPageID: target.id)
        }
    }

    func knownCalendarPage(context: CalendarGenerationContext, from source: GeneratedPage,
                           expectedScope: UUID) -> GeneratedPage? {
        guard pages.contains(where: { $0 === source }), SavedPagesStore.shared.scopeID == expectedScope,
              let key = source.conversationKey, !history.isRemoving(key) else { return nil }
        return generationRegistry.retainedCalendarPage(
            context: context, from: source, navigationPages: pages,
            historyEpoch: history.epoch, expectedScope: expectedScope)
    }
}
