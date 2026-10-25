import Foundation
import Observation
import SwiftUI
import UIKit
import EmblemCore

extension ConversationStore {
    func updateIdentity(_ ownerID: String?) {
        guard history.ownerID != ownerID else { return }
        reset(ownerID: ownerID)
    }

    func reset(ownerID: String? = nil) {
        VoiceOutput.shared.stop()
        history.reset(ownerID: ownerID)
        cancelRestore()
        automationOpenFailureID = nil
        generationRegistry.invalidateAll()
        if let runID = idleGenerationSession.activeRunID {
            idleGenerationSession.cancelActiveWithoutContext(runID: runID)
        }
        idleGenerationSession.clearRetryCandidate()
        attachments = []
        upload = nil
        presentedQuestion = nil
        questionDraft = ""
        flagged = nil
        prefetchedOptions = [:]
        optionPrefetches = []
        attachmentsExpanded = false
        dockState = .idle
        forwardPages = []
        expansionPages = [:]
        olderPages?.task?.cancel()
        olderPages = nil
        withAnimation(.smooth(duration: 0.4)) { pages.removeAll() }
        loadHome()
    }

    func loadHome() {
        Task { [history] in await history.load() }
        homeClient.cancel()
        let incoming = GeneratedPage(prompt: "home", isHome: true)
        let visible = homePage ?? GeneratedPage(prompt: "home", isHome: true)
        if homePage == nil {
            if pages.isEmpty { pages = [visible] }
            else { pages.insert(visible, at: 0) }
        }
        let nextEvent = CalendarService.shared.nextUp()
        let nextEventActions = nextEvent.map(Self.homeEventActions)
        if visible.blocks.isEmpty {
            visible.blocks = [Self.localGreeting(name: greetingName, nextEvent: nextEvent)]
                + (nextEventActions.map { [$0] } ?? [])
        }
        let requestID = UUID()
        homeRequestID = requestID
        homeLoadState = .loading

        homeClient.stream(
            path: "api/home",
            body: GenerateClient.HomeBody(
                name: greetingName, timezone: TimeZone.current.identifier,
                nextEventTitle: nextEvent?.title, nextEventStart: nextEvent?.start)
        ) { [weak self] event in
            guard let self, self.homeRequestID == requestID else { return }
            switch event {
            case .accepted, .status, .pagePreview, .clearPagePreview:
                break
            case .pageSnapshot(_, let blocks):
                incoming.meta = blocks.lazy.compactMap { block -> PageMeta? in
                    if case .pageMeta(let meta) = block { return meta }
                    return nil
                }.first
                incoming.blocks = blocks.filter {
                    if case .pageMeta = $0 { return false }
                    return true
                }
            case .finished:
                incoming.isStreaming = false
                if let nextEventActions,
                   !incoming.blocks.contains(where: { $0.id == nextEventActions.id }),
                   let greetingIndex = incoming.blocks.firstIndex(where: { $0.id == "greeting" }) {
                    incoming.blocks.insert(nextEventActions, at: greetingIndex + 1)
                }
                withAnimation(.smooth(duration: 0.22)) {
                    visible.meta = incoming.meta
                    visible.blocks = incoming.blocks
                    visible.isStreaming = false
                }
                homeLoadState = .idle
            case .failed:
                visible.isStreaming = false
                homeLoadState = .failed
            }
        }
    }

    private static func localGreeting(name: String?, nextEvent: CalendarService.NextEvent?) -> Block {
        let hour = Calendar.current.component(.hour, from: .now)
        let greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let opener = name.map { "\(greeting), **\($0)**." } ?? "\(greeting)."
        let next = nextEvent.map(nextEventLine) ?? "What can I look into for you?"
        return .text(TextBlock(id: "greeting", body: "\(opener)\n\(next)", style: .intro))
    }

    private static func nextEventLine(_ event: CalendarService.NextEvent) -> String {
        let calendar = Calendar.current
        let time = event.start.formatted(date: .omitted, time: .shortened)
        let when: String
        if calendar.isDateInToday(event.start) {
            when = "\(calendar.component(.hour, from: event.start) >= 17 ? "tonight" : "today") at **\(time)**"
        } else if calendar.isDateInTomorrow(event.start) {
            when = "tomorrow at **\(time)**"
        } else {
            when = "\(event.start.formatted(.dateTime.weekday(.wide))) at **\(time)**"
        }
        return "Your 📅 **\(event.title)** is \(when)."
    }

    private static func homeEventActions(_ event: CalendarService.NextEvent) -> Block {
        var rows: [MediaRowList.Row] = []
        if let joinURL = event.joinURL {
            rows.append(.init(
                icon: nil,
                title: event.title,
                subtitle: nil,
                action: Action(label: "Join meeting", sfSymbol: "video.fill", url: joinURL.absoluteString)))
        }
        let when = event.start.formatted(date: .abbreviated, time: .shortened)
        rows.append(.init(
            icon: nil,
            title: event.title,
            subtitle: nil,
            action: Action(
                label: "Prep agenda",
                sfSymbol: "sparkles",
                prompt: "Prepare me for \"\(event.title)\" on \(when). Make the preparation concise, visual, and immediately useful.")))
        return .mediaRowList(MediaRowList(id: "next-event-actions", title: nil, rows: rows))
    }

    func refreshHome() {
        guard currentPage?.isHome ?? false, homeLoadState != .loading else { return }
        loadHome()
    }
}
