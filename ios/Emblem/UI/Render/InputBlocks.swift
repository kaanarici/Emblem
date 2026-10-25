import SwiftUI
import EmblemCore

struct QuestionListView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(ConversationStore.self) private var store
    @Environment(\.renderedPage) private var renderedPage
    let block: QuestionList

    var body: some View {
        Group {
            if let inline = block.inlineChoice {
                RequiredChoiceView(
                    id: block.id,
                    question: inline.item.question,
                    options: inline.options,
                    presentation: inline.item.input?.presentation ?? .rows)
            } else if let item = block.inlineCount {
                VStack(alignment: .leading, spacing: 0) {
                    TextBlockView(block: TextBlock(id: "\(block.id)-question", body: item.question, style: .intro))
                    CountPickerView(
                        spec: item.input,
                        value: Binding(
                            get: { store.answer(for: item.question) ?? "" },
                            set: { store.setAnswer(question: item.question, value: $0) }),
                        inline: true)
                        .padding(.top, 51)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(block.items.enumerated()), id: \.offset) { index, item in
                        let value = store.answer(for: item.question).map { answer in
                            item.input?.kind == .area ? AreaAnswer.place(in: answer) : answer
                        }
                        if item.input != nil {
                            Button {
                                guard blockInteraction.allowsActivation else { return }
                                store.openQuestion(item)
                            } label: {
                                QuestionCard(item: item, value: value)
                            }
                            .blockActivationControl()
                            .buttonStyle(.pressable)
                            .accessibilityIdentifier("question-\(index)")
                        } else {
                            QuestionCard(item: item, value: value)
                                .accessibilityElement(children: .combine)
                        }
                    }
                    if block.items.contains(where: { store.flaggedQuestions.contains($0.question) }) {
                        FieldWarning()
                    }
                }
                .padding(.horizontal, InputMetrics.cardMargin)
                .padding(.top, 14)
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.flaggedQuestions)
        .task(id: renderedPage?.isStreaming == false) {
            guard let renderedPage, !renderedPage.isStreaming, !renderedPage.hasProvisionalPresentation else { return }
            store.prefetchQuestionOptions(block, on: renderedPage)
        }
    }
}

struct RequiredChoiceView: View {
    @Environment(ConversationStore.self) private var store
    let id: String
    let question: String
    let options: [String]
    let presentation: InputSpec.Presentation

    var body: some View {
        let flagged = store.flaggedQuestions.contains(question)
        VStack(alignment: .leading, spacing: 0) {
            TextBlockView(block: TextBlock(id: "\(id)-question", body: question, style: .intro))
            ChoiceOptions(
                options: options,
                presentation: presentation,
                selection: Binding(
                    get: { store.answer(for: question) ?? "" },
                    set: { store.setAnswer(question: question, value: $0) }))
                .padding(.horizontal, presentation.margin)
                .padding(.top, presentation.questionGap)
            if flagged {
                FieldWarning()
                    .padding(.horizontal, presentation.margin + 4)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: flagged)
        .accessibilityElement(children: .contain)
    }
}

extension InputSpec.Presentation {
    var margin: CGFloat {
        switch self {
        case .rows: InputMetrics.cardMargin
        case .chips, .cards: 32
        }
    }

    var isCards: Bool {
        if case .cards = self { return true }
        return false
    }

    var questionGap: CGFloat {
        switch self {
        case .rows: 34
        case .chips, .cards: 34
        }
    }
}

struct ChoiceOptions: View {
    let options: [String]
    let presentation: InputSpec.Presentation
    var rowHeight: CGFloat = 72
    var multiple = false
    @Binding var selection: String

    var body: some View {
        switch presentation {
        case .rows:
            ChoiceOptionList(options: options, rowHeight: rowHeight, selection: $selection)
        case .chips:
            ChoiceChips(options: options, selection: $selection)
        case .cards(let icons):
            ChoiceCardGrid(options: options, icons: icons, multiple: multiple, selection: $selection)
        }
    }
}

struct FieldWarning: View {
    var body: some View {
        Text("This one needs an answer")
            .font(.system(size: 13))
            .foregroundStyle(InputPalette.warning)
            .accessibilityIdentifier("field-warning")
    }
}

enum QuestionIcon {
    static func icon(for item: QuestionList.Item) -> Icon? {
        if ListIconPolicy.isRenderable(item.icon) { return item.icon }
        let (query, symbol) = defaults(for: item.input)
        return Icon(sfSymbol: symbol, image: ImageSpec(query: query, kind: .object))
    }

    private static func defaults(for input: InputSpec?) -> (String, String) {
        switch input?.kind {
        case .place: ("map pin", "mappin.and.ellipse")
        case .area: ("map", "map")
        case .date, .dateRange: ("calendar", "calendar")
        case .time: ("alarm clock", "alarm")
        case .count:
            switch input?.unit?.lowercased() ?? "" {
            case let unit where ["day", "night", "week", "month"].contains { unit.hasPrefix($0) }:
                ("calendar", "calendar")
            case let unit where ["people", "person", "travel", "guest", "adult", "kid", "child", "passenger"]
                .contains(where: { unit.hasPrefix($0) }):
                ("group of people", "person.2")
            default: ("abacus", "slider.horizontal.3")
            }
        case .text: ("pencil", "pencil")
        case .choice, nil: ("clipboard", "checklist")
        }
    }
}

private struct QuestionCard: View {
    let item: QuestionList.Item
    let value: String?

    var body: some View {
        HStack(spacing: 0) {
            IconView(icon: QuestionIcon.icon(for: item), size: 42, placeholder: true)
                .frame(width: 42, height: 42)
                .padding(.leading, 23.5)
                .padding(.trailing, 23)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.question)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                Text(value ?? "Choose")
                    .font(.system(size: 19, weight: .semibold))
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.25), value: value)
                    .foregroundStyle(value == nil ? Theme.inkSecondary : Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, minHeight: 89, alignment: .leading)
        .background(InputCardBackground())
    }
}

private struct InputCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        shape
            .fill(InputPalette.card)
            .overlay(shape.strokeBorder(Color.black.opacity(colorScheme == .dark ? 0 : 0.05), lineWidth: 0.5))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 2, y: 1)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 10, y: 4)
    }
}

enum InputMetrics {
    static let cardMargin: CGFloat = 28
}

enum InputPalette {
    static let canvas = adaptive(light: 0xF5F5F5, dark: 0x101012)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x1F1F22)
    static let sheet = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let option = adaptive(light: 0xFAFAFA, dark: 0x2A2A2E)
    static let optionSelected = adaptive(light: 0xFFFFFF, dark: 0x3A3A3F)
    static let optionStroke = adaptive(light: 0xC0C0C0, dark: 0x6A6A70)
    static let streamedOption = adaptive(light: 0xF3F3F3, dark: 0x2A2A2E)
    static let rule = adaptive(light: 0xE3E3E3, dark: 0x3A3A3F)
    static let hint = adaptive(light: 0xB4B4B4, dark: 0x6E6E74)
    static let grabber = adaptive(light: 0xBBBBBB, dark: 0x58585C)
    static let tile = adaptive(light: 0xF5F5F5, dark: 0x232326)
    static let iconSlot = adaptive(light: 0xF2F2F2, dark: 0x2E2E32)
    static let warning = adaptive(light: 0xC40C14, dark: 0xFF5A52)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

struct InputOptionBackground: View {
    var selected: Bool
    var radius: CGFloat = 18
    var rest: Color = InputPalette.option
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(selected ? InputPalette.optionSelected : rest)
            if selected {
                shape.fill(LinearGradient(
                    stops: [.init(color: .clear, location: 0.78),
                            .init(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), location: 1)],
                    startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(InputPalette.optionStroke, lineWidth: 4 / 3)
            } else {
                shape.strokeBorder(LinearGradient(
                    stops: [.init(color: .white.opacity(colorScheme == .dark ? 0.04 : 0.7), location: 0),
                            .init(color: .black.opacity(colorScheme == .dark ? 0.1 : 0.03), location: 0.25),
                            .init(color: .black.opacity(colorScheme == .dark ? 0.14 : 0.04), location: 1)],
                    startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
        }
    }
}

extension QuestionList.Item: Identifiable {
    public var id: String { question }
}
