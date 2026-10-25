import SwiftUI
import EmblemCore

struct TimeAskView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let block: TimeAsk
    @Environment(ConversationStore.self) private var store

    @State private var time = Date()
    @State private var selectedChip: String?
    @State private var seeded = false
    @State private var calendarSpec: Action.CalendarSpec?

    var body: some View {
        VStack(spacing: 22) {
            IconView(icon: block.icon ?? Icon(emoji: "🕰️"), size: 64)
                .padding(.top, 26)

            Text(block.question)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)

            if let spec = calendarSpec {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEW EVENT")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(Theme.inkSecondary)
                    Text(spec.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("\(dateLabel(spec.date)) · \(spec.durationMinutes) minutes")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .cardBackground(radius: 18)
                .padding(.horizontal, Theme.contentMargin)
                .accessibilityElement(children: .combine)
            }

            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                .blockStoreMutationControl()
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 190)
                .onChange(of: time) {
                    if seeded { writeAnswer(clearChip: true) }
                }

            if let suggestions = block.suggestions, !suggestions.isEmpty {
                HStack(spacing: 12) {
                    Rectangle().fill(Theme.inkSecondary.opacity(0.2)).frame(height: 1)
                    Text("Quick picks")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize()
                    Rectangle().fill(Theme.inkSecondary.opacity(0.2)).frame(height: 1)
                }
                .padding(.horizontal, Theme.contentMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(suggestions, id: \.label) { suggestion in
                            chip(suggestion)
                        }
                    }
                    .padding(.horizontal, Theme.contentMargin)
                }
                .scrollClipDisabled()
            }
        }
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
        .onAppear {
            if let spec = store.dockAction?.calendar,
               spec.timeAnswerKey == block.question {
                calendarSpec = spec
            }
            if let savedTime = store.answer(for: block.question) {
                apply(time: savedTime)
            } else {
                apply(time: block.defaultTime ?? nextRoundedTime())
                writeAnswer(clearChip: false)
            }
            DispatchQueue.main.async { seeded = true }
        }
    }

    private func chip(_ suggestion: TimeAsk.Suggestion) -> some View {
        let selected = selectedChip == suggestion.label
        return Button {
            guard blockInteraction.allowsStoreMutation else { return }
            seeded = false
            withAnimation(.smooth(duration: 0.3)) {
                apply(time: suggestion.time)
                selectedChip = suggestion.label
            }
            writeAnswer(clearChip: false)
            DispatchQueue.main.async { seeded = true }
        } label: {
            Text(suggestion.label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(selected ? Theme.surface : Theme.chip))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(selected ? Theme.ink : .clear, lineWidth: 1.5))
        }
        .blockStoreMutationControl()
        .buttonStyle(.pressable)
    }

    private func apply(time string: String) {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = parts[0]
        components.minute = parts[1]
        if let date = Calendar.current.date(from: components) { time = date }
    }

    private func nextRoundedTime() -> String {
        let next = Date().addingTimeInterval(3600)
        return String(format: "%02d:00", Calendar.current.component(.hour, from: next))
    }

    private func dateLabel(_ value: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        parser.isLenient = false
        guard let date = parser.date(from: value) else { return value }
        let display = DateFormatter()
        display.dateFormat = "EEEE, MMMM d"
        return display.string(from: date)
    }

    private func writeAnswer(clearChip: Bool) {
        guard blockInteraction.allowsStoreMutation else { return }
        if clearChip { selectedChip = nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm"
        store.setAnswer(question: block.question, value: formatter.string(from: time))
    }
}
