import Foundation
import Observation
import SwiftUI
import UIKit
import EmblemCore

extension ConversationStore {
    var activeQuestion: QuestionList.Item? {
        guard let presentedQuestion, presentedQuestion.page == currentPage?.id else { return nil }
        return presentedQuestion.item
    }
    var flaggedQuestions: Set<String> {
        guard let flagged, flagged.page == currentPage?.id else { return [] }
        return flagged.questions
    }

    var hasEditableQuestions: Bool {
        currentPage?.blocks.contains { block in
            switch block {
            case .questionList(let list): list.items.contains { $0.input != nil }
            case .chipRow(let row): row.role == .requiredChoice
            default: false
            }
        } ?? false
    }

    func openQuestion(_ item: QuestionList.Item) {
        guard let page = currentPage, blockInteraction(for: page).allowsActivation else { return }
        questionDraft = answer(for: item.question) ?? ""
        presentedQuestion = (page.id, item)
    }

    func confirmQuestion() {
        guard let item = activeQuestion else { return }
        let value = questionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { setAnswer(question: item.question, value: value) }
        presentedQuestion = nil
    }

    func dismissQuestion() {
        presentedQuestion = nil
    }

    private func optionsKey(_ page: GeneratedPage, _ item: QuestionList.Item) -> String {
        "\(page.id.uuidString):\(item.question)"
    }

    func prefetchQuestionOptions(_ list: QuestionList, on page: GeneratedPage) {
        for item in list.items where item.input?.kind == .choice && item.input?.presentation.isCards == false {
            let key = optionsKey(page, item)
            guard prefetchedOptions[key] == nil, !optionPrefetches.contains(key) else { continue }
            optionPrefetches.insert(key)
            let request = optionsRequest(for: item, on: page)
            let epoch = history.epoch
            Task { [weak self] in
                let options = try? await QuestionOptionsClient.stream(request) { _ in }
                guard let self, self.history.epoch == epoch else { return }
                optionPrefetches.remove(key)
                if let options { prefetchedOptions[key] = options }
            }
        }
    }

    func prefetchedOptions(for item: QuestionList.Item) -> [QuestionOption]? {
        currentPage.flatMap { prefetchedOptions[optionsKey($0, item)] }
    }

    func optionsRequest(for item: QuestionList.Item, on page: GeneratedPage? = nil) -> QuestionOptionsRequest {
        let page = page ?? currentPage
        let intro = page?.blocks.lazy.compactMap { block -> String? in
            if case .text(let text) = block, text.style == .intro { return text.body }
            return nil
        }.first
        let siblings = page?.blocks.flatMap { block -> [QuestionOptionsRequest.Sibling] in
            guard case .questionList(let list) = block else { return [] }
            return list.items.compactMap { row in
                answer(for: row.question).map { .init(question: row.question, answer: $0) }
            }
        } ?? []
        return QuestionOptionsRequest(
            prompt: page?.prompt, intro: intro, question: item.question, ask: item.input?.ask,
            answer: answer(for: item.question), siblings: siblings)
    }

    static func isUnset(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.caseInsensitiveCompare("Not set") == .orderedSame
    }

    private var missingQuestions: [String] {
        guard let page = currentPage, page.meta?.dockAction == nil else { return [] }
        return page.blocks.flatMap { block -> [String] in
            switch block {
            case .questionList(let list) where list.items.count == 1:
                return list.items.compactMap { item in
                    guard item.input != nil else { return nil }
                    return Self.isUnset(page.answers[item.question] ?? "") ? item.question : nil
                }
            case .chipRow(let row) where row.role == .requiredChoice:
                let question = row.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return !question.isEmpty && Self.isUnset(page.answers[question] ?? "") ? [question] : []
            default:
                return []
            }
        }
    }

    var requiredAnswersMissing: Bool { !missingQuestions.isEmpty }

    func flagMissingAnswers() {
        guard let page = currentPage else { return }
        flagged = (page.id, Set(missingQuestions))
    }

    func setAnswer(question: String, value: String) {
        guard let page = currentPage,
              blockInteraction(for: page).allowsStoreMutation else { return }
        generationSession.clearRetryCandidate(page: currentPage)
        page.answers[question] = value
        flagged?.questions.remove(question)
    }

    func answer(for question: String) -> String? {
        currentPage.flatMap { Self.answer(for: question, on: $0) }
    }

    static func answer(for question: String, on page: GeneratedPage) -> String? {
        if let picked = page.answers[question] { return picked }
        for block in page.blocks {
            guard case .questionList(let list) = block,
                  let item = list.items.first(where: { $0.question == question }) else { continue }
            return isUnset(item.answer) ? nil : item.answer
        }
        return nil
    }

    func appendingAnswers(to text: String, from page: GeneratedPage?) -> String {
        guard let page else { return text }
        let rows = page.blocks.flatMap { block -> [String] in
            if case .questionList(let list) = block { return list.items.map(\.question) }
            return []
        }
        let picked = { (question: String) in
            Self.answer(for: question, on: page).flatMap { Self.isUnset($0) ? nil : $0 }
        }
        var pairs = rows.compactMap { question in picked(question).map { (question, $0) } }
        let listed = Set(rows)
        pairs += page.answers.filter { !listed.contains($0.key) && !Self.isUnset($0.value) }
            .sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        let open = rows.filter { picked($0) == nil }
        var sections: [String] = []
        if !pairs.isEmpty {
            sections.append("My answers so far:\n" + pairs.map { "- \($0.0): \($0.1)" }.joined(separator: "\n"))
        }
        if !open.isEmpty {
            sections.append("I left these open:\n" + open.map { "- \($0)" }.joined(separator: "\n"))
        }
        guard !sections.isEmpty else { return text }
        let base = text.isEmpty ? "Continue" : text
        return ([base] + sections).joined(separator: "\n\n")
    }
}
