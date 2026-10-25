import Foundation
import Observation
import SwiftUI
import UIKit
import EmblemCore

extension ConversationStore {
    func openAutomation(id: String) {
        guard !isGenerationActive else { return }
        cancelRestore()
        openingAutomationID = id
        automationOpenFailureID = nil
        let requestID = UUID()
        restoreRequestID = requestID
        restoreTask = Task { [weak self] in
            guard let self else { return }
            do {
                let pages = try await AgentsClient.runPages(id: id)
                guard !pages.isEmpty else {
                    if self.restoreRequestID == requestID {
                        self.openingAutomationID = nil
                        self.automationOpenFailureID = id
                        self.restoreTask = nil
                    }
                    return
                }
                try Task.checkCancellation()
                guard self.restoreRequestID == requestID,
                      !self.isGenerationActive else { return }
                self.generationSession.clearRetryCandidate()
                let root = self.homePage ?? GeneratedPage(prompt: "home", isHome: true)
                self.forwardPages = []
                withAnimation(.smooth(duration: 0.45)) {
                    self.pages = [root] + pages
                }
                self.openingAutomationID = nil
                self.restoreTask = nil
            } catch {
                guard !Task.isCancelled, self.restoreRequestID == requestID else { return }
                self.openingAutomationID = nil
                self.automationOpenFailureID = id
                self.restoreTask = nil
            }
        }
    }

    func dismissAutomationOpenFailure() {
        automationOpenFailureID = nil
    }

    func createAutomation(_ spec: Action.AutomationSpec) {
        let title = spec.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = spec.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let idempotencyKey = spec.idempotencyKey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !generationSession.isActive,
              let page = currentPage,
              let action = page.meta?.dockAction,
              action.automation == spec,
              let idempotencyKey,
              !idempotencyKey.isEmpty,
              idempotencyKey.count <= 200,
              !title.isEmpty,
              !prompt.isEmpty,
              (0...23).contains(spec.hour),
              (0...59).contains(spec.minute) else {
            if let page = currentPage {
                showAutomationError(on: page, "This schedule is incomplete. Ask me to rebuild it.")
            }
            return
        }

        if var meta = page.meta {
            meta.dockAction = nil
            page.meta = meta
        }
        let epoch = history.epoch
        Task { [weak self, weak page] in
            guard let self, let page, self.history.epoch == epoch else { return }
            do {
                try await AgentsClient.createScheduled(
                    title: title,
                    prompt: prompt,
                    hour: spec.hour,
                    minute: spec.minute,
                    weekdays: spec.weekdays,
                    timezone: TimeZone.current.identifier,
                    requestId: idempotencyKey)
            } catch {
                guard self.history.epoch == epoch else { return }
                if var meta = page.meta, meta.dockAction == nil {
                    meta.dockAction = action
                    page.meta = meta
                }
                if self.currentPage === page {
                    self.showAutomationError(
                        on: page,
                        "The automation could not be scheduled. Check your connection and try again.")
                }
                return
            }
            self.refreshHome()
            let clock = Calendar.current.date(from: DateComponents(
                hour: spec.hour,
                minute: spec.minute))
            let time = clock.map {
                DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short)
            } ?? String(format: "%d:%02d", spec.hour, spec.minute)
            withAnimation(.smooth(duration: 0.3)) {
                page.blocks.removeAll {
                    ["automation-action-error", "automation-confirmation", "automation-detail"]
                        .contains($0.id)
                }
                page.blocks.append(.sectionHeader(SectionHeader(
                    id: "automation-confirmation",
                    title: "Automation scheduled",
                    subtitle: nil)))
                page.blocks.append(.text(TextBlock(
                    id: "automation-detail",
                    body: "\(title) will run at \(time).",
                    style: .body)))
            }
        }
    }

    private func showAutomationError(on page: GeneratedPage, _ message: String) {
        page.blocks.removeAll { $0.id == "automation-action-error" }
        page.blocks.append(.text(TextBlock(
            id: "automation-action-error",
            body: message,
            style: .footnote)))
    }
}
