import SwiftUI
import EmblemCore

struct QuizView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(\.performAction) private var performAction
    let block: Quiz

    @State private var picked: [Int: Int] = [:]
    @State private var graded = false
    @State private var hints: [Int: String] = [:]
    @State private var hintLoading: Set<Int> = []

    private static let pickMotion = Animation.easeOut(duration: 0.18)
    private static let layoutMotion = Animation.smooth(duration: 0.35)
    private static let arrival = AnyTransition.asymmetric(
        insertion: .opacity.animation(.smooth(duration: 0.25).delay(0.15)),
        removal: .opacity.animation(.easeOut(duration: 0.12)))

    private var allAnswered: Bool { picked.count == block.questions.count }
    private var score: Int {
        block.questions.enumerated().filter { picked[$0.offset] == $0.element.correctIndex }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let title = block.title, !title.isEmpty {
                Text(title)
                    .font(Theme.cardTitle())
                    .foregroundStyle(Theme.ink)
            }
            ForEach(Array(block.questions.enumerated()), id: \.offset) { qIndex, question in
                questionView(qIndex, question)
            }
            footer
        }
        .padding(.horizontal, Theme.contentMargin)
    }

    private func questionView(_ qIndex: Int, _ question: Quiz.Question) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(qIndex + 1) of \(block.questions.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 8)
                hintButton(qIndex, question)
            }
            Text(question.question)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { oIndex, option in
                    optionRow(qIndex: qIndex, question: question, oIndex: oIndex, option: option)
                }
            }

            if let hint = hints[qIndex] {
                note(hint, symbol: "lightbulb")
                    .transition(Self.arrival)
            }
            if graded, let why = question.why, !why.isEmpty {
                note(why, symbol: nil)
                    .accessibilityLabel("Explanation: \(why)")
                    .transition(Self.arrival)
            }
        }
    }

    private func note(_ text: String, symbol: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 14))
        .lineSpacing(2)
        .foregroundStyle(Theme.inkSecondary)
        .padding(.horizontal, 2)
    }

    private func optionRow(qIndex: Int, question: Quiz.Question, oIndex: Int, option: String) -> some View {
        let isPicked = picked[qIndex] == oIndex
        let showCorrect = graded && oIndex == question.correctIndex
        let showWrong = graded && isPicked && !showCorrect
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        return Button {
            guard blockInteraction.allowsActivation, !graded else { return }
            withAnimation(Self.pickMotion) { picked[qIndex] = isPicked ? nil : oIndex }
        } label: {
            HStack(spacing: 12) {
                mark(picked: isPicked, correct: showCorrect, wrong: showWrong)
                Text(option)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(graded && !showCorrect && !showWrong ? 0.55 : 1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(showCorrect ? Theme.positiveFill : showWrong ? Theme.negativeFill : Theme.chip, in: shape)
            .overlay(shape.strokeBorder(isPicked && !graded ? Theme.ink : .clear, lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .blockActivationControl()
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        .accessibilityValue(showCorrect ? "Correct answer" : showWrong ? "Incorrect" : "")
    }

    private func mark(picked: Bool, correct: Bool, wrong: Bool) -> some View {
        let settled = correct || wrong
        return ZStack {
            Circle()
                .strokeBorder(picked ? Theme.ink : Theme.inkSecondary.opacity(0.45), lineWidth: 1.5)
                .opacity(settled ? 0 : 1)
            Circle()
                .fill(Theme.ink)
                .frame(width: 10, height: 10)
                .opacity(picked && !settled ? 1 : 0)
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .foregroundStyle(Theme.positive)
                .opacity(correct ? 1 : 0)
            Image(systemName: "xmark.circle.fill")
                .resizable()
                .foregroundStyle(Theme.negative)
                .opacity(wrong ? 1 : 0)
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }

    private func hintButton(_ qIndex: Int, _ question: Quiz.Question) -> some View {
        let loading = hintLoading.contains(qIndex)
        let shown = !graded && hints[qIndex] == nil
        return Button {
            guard blockInteraction.allowsStoreMutation else { return }
            requestHint(qIndex, question)
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    Image(systemName: "lightbulb").opacity(loading ? 0 : 1)
                    ProgressView().controlSize(.mini).opacity(loading ? 1 : 0)
                }
                .frame(width: 14, height: 14)
                Text("Hint")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.inkSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .blockStoreMutationControl()
        .disabled(loading || !shown)
        .opacity(shown ? 1 : 0)
        .accessibilityHidden(!shown)
    }

    private func requestHint(_ qIndex: Int, _ question: Quiz.Question) {
        guard blockInteraction.allowsStoreMutation else { return }
        hintLoading.insert(qIndex)
        let identityEpoch = ConversationHistory.shared.epoch
        Task {
            defer { hintLoading.remove(qIndex) }
            struct Payload: Decodable { let hint: String }
            guard let data = try? await GenerateClient.postJSON(
                identityEpoch: identityEpoch, path: "api/hint",
                body: [
                    "question": question.question,
                    "options": question.options.joined(separator: " | "),
                    "answer": question.options.indices.contains(question.correctIndex)
                        ? question.options[question.correctIndex] : "",
                ]),
                let payload = try? JSONDecoder().decode(Payload.self, from: data)
            else { return }
            reveal(payload.hint, for: qIndex)
        }
    }

    private func reveal(_ hint: String, for qIndex: Int) {
        withAnimation(Self.layoutMotion) {
            hints[qIndex] = hint
            hintLoading.remove(qIndex)
        }
    }

    private var footer: some View {
        ZStack(alignment: .top) {
            if graded {
                summary.transition(Self.arrival)
            } else {
                pill("Check answers") {
                    guard blockInteraction.allowsActivation, allAnswered else { return }
                    withAnimation(Self.layoutMotion) { graded = true }
                }
                .blockActivationControl()
                .opacity(allAnswered ? 1 : 0.4)
                .accessibilityHint(allAnswered ? "" : "Answer every question first")
                .transition(Self.arrival)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(score) of \(block.questions.count) correct")
                        .font(.system(size: 18, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    Text(encouragement)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 12)
                Button {
                    guard blockInteraction.allowsActivation else { return }
                    withAnimation(Self.layoutMotion) {
                        picked = [:]
                        hints = [:]
                        graded = false
                    }
                } label: {
                    Text("Try again")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 38)
                        .background(Theme.chip, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .blockActivationControl()
            }

            if score < block.questions.count {
                pill("Explain my misses") {
                    guard blockInteraction.allowsStoreMutation else { return }
                    let missed = block.questions.enumerated()
                        .filter { picked[$0.offset] != $0.element.correctIndex }
                        .map(\.element.question)
                        .joined(separator: "; ")
                    performAction(Action(
                        label: "Explain",
                        prompt: "Explain these, I got them wrong in the quiz: \(missed)"))
                }
                .blockStoreMutationControl()
            }
        }
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.accentDark, in: Capsule())
        }
        .buttonStyle(.pressable)
    }

    private var encouragement: String {
        let ratio = block.questions.isEmpty ? 0 : Double(score) / Double(block.questions.count)
        if ratio == 1 { return "You got them all." }
        if ratio >= 0.6 { return "Nice work." }
        if ratio > 0 { return "Worth another look." }
        return "Give it another go."
    }
}
