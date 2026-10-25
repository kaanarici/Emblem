import SwiftUI
import EmblemCore

struct QuestionSheetHost: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let bottomInset: CGFloat
    @State private var drag: CGFloat = 0

    var body: some View {
        let item = store.activeQuestion
        ZStack(alignment: .bottom) {
            if item != nil {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { store.dismissQuestion() }
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.2)),
                        removal: .opacity.animation(.easeOut(duration: 0.35))))
                    .accessibilityHidden(true)
            }
            if let item {
                Group {
                    if item.input?.kind == .area {
                        AreaQuestionSheet(item: item, headerDrag: AnyGesture(dismissDrag.map { _ in }))
                    } else {
                        QuestionSheet(item: item, dockReserve: bottomInset + 56 + 17,
                                      prefetched: store.prefetchedOptions(for: item))
                            .gesture(dismissDrag)
                    }
                }
                    .offset(y: drag)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .bottom).animation(.spring(duration: 0.36, bounce: 0.12).delay(0.12)),
                        removal: .move(edge: .bottom)))
                    .id(item.question)
            }
        }
        .ignoresSafeArea(.container)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.36, bounce: 0), value: item?.question)
        .onChange(of: item?.question) { _, question in
            if question != nil { drag = 0 }
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { drag = max(0, $0.translation.height) }
            .onEnded { value in
                if value.predictedEndTranslation.height > 140 {
                    store.dismissQuestion()
                } else {
                    withAnimation(.spring(duration: 0.3, bounce: 0)) { drag = 0 }
                }
            }
    }
}

private struct QuestionSheet: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: QuestionList.Item
    let dockReserve: CGFloat

    init(item: QuestionList.Item, dockReserve: CGFloat, prefetched: [QuestionOption]?) {
        self.item = item
        self.dockReserve = dockReserve
        _phase = State(initialValue: prefetched == nil ? .loading : .done)
        _streamed = State(initialValue: prefetched ?? [])
        _finished = State(initialValue: prefetched != nil)
    }

    private enum Phase { case loading, collapsing, streaming, done, fallback }
    @State private var phase: Phase = .loading
    @State private var streamed: [QuestionOption] = []
    @State private var finished = false

    private var kind: InputSpec.Kind {
        let declared = item.input?.kind ?? .text
        if declared == .choice, phase == .fallback, options.isEmpty { return .text }
        return declared
    }

    private var streams: Bool { item.input?.kind == .choice && !cards && phase != .fallback }
    private var cards: Bool { item.input?.presentation.isCards ?? false }
    private var fills: Bool { kind == .date || kind == .dateRange }
    private var options: [String] { item.input?.options ?? [] }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            Capsule()
                .fill(InputPalette.grabber)
                .frame(width: 40, height: 5)
                .padding(.top, 7)
            if streams {
                streamedChoice
            } else {
                if kind == .count {
                    IconView(icon: item.icon, size: 64)
                        .frame(width: 64, height: 64)
                        .padding(.top, 38)
                }
                title
                    .padding(.top, kind == .count ? 20 : fills ? 34 : cards ? 30 : 26)
                    .padding(.bottom, fills ? 27 : cards ? 30 : 24)
                picker(draft: $store.questionDraft)
            }
            if !fills { Color.clear.frame(height: dockReserve - 8) }
        }
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .top)
        .background {
            if fills {
                UnevenRoundedRectangle(topLeadingRadius: 36, topTrailingRadius: 36, style: .continuous)
                    .fill(InputPalette.sheet)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ConcentricRectangle(
                    uniformTopCorners: .fixed(32),
                    uniformBottomCorners: .concentric(minimum: .fixed(38)))
                    .fill(InputPalette.sheet)
            }
        }
        .scaleEffect(phase == .collapsing && !reduceMotion ? 0.9 : 1)
        .padding(.horizontal, fills ? 0 : 8)
        .padding(.bottom, fills ? 0 : 8)
        .padding(.top, fills ? 60 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("question-sheet")
        .task(id: item.question) { await loadOptions() }
    }

    private var title: some View {
        Text(item.input?.ask ?? item.question)
            .font(.system(size: streams ? 19 : 19.3, weight: .bold))
            .tracking(streams ? -0.4 : -0.5)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var streamedChoice: some View {
        switch phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 93)
                .padding(.bottom, 34)
                .transition(.opacity)
                .accessibilityLabel("Loading options")
        case .collapsing, .fallback:
            EmptyView()
        case .streaming, .done:
            VStack(spacing: 0) {
                title
                    .padding(.top, 56.5)
                    .padding(.bottom, 24)
                ViewThatFits(in: .vertical) {
                    optionList
                    ScrollView { optionList }.scrollBounceBehavior(.basedOnSize)
                }
            }
            .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.05)))
        }
    }

    private var optionList: some View {
        VStack(spacing: 6) {
            ForEach(Array(streamed.enumerated()), id: \.offset) { index, option in
                StreamedOptionRow(
                    option: option,
                    selected: phase == .done && option.matches(store.questionDraft)
                ) {
                    guard phase == .done else { return }
                    store.questionDraft = option.answer
                }
                .accessibilityIdentifier("option-\(index)")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 23)
    }

    private func loadOptions() async {
        guard streams else { return }
        if let ready = store.prefetchedOptions(for: item) {
            if let match = ready.first(where: { $0.matches(store.questionDraft) }) {
                store.questionDraft = match.answer
            }
            return
        }
        let request = store.optionsRequest(for: item)
        do {
            let final = try await QuestionOptionsClient.stream(request) { partial in
                guard !partial.isEmpty else { return }
                if phase == .loading {
                    streamed = partial
                    collapse()
                } else {
                    withAnimation(.spring(duration: 0.35, bounce: 0)) { streamed = partial }
                }
            }
            if phase == .loading {
                streamed = final
                collapse()
            }
            finished = true
            withAnimation(.spring(duration: 0.35, bounce: 0)) {
                streamed = final
                if phase != .collapsing { phase = .done }
                if let match = final.first(where: { $0.matches(store.questionDraft) }) {
                    store.questionDraft = match.answer
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.35, bounce: 0)) { phase = .fallback }
        }
    }

    private func collapse() {
        withAnimation(.easeIn(duration: 0.13)) { phase = .collapsing }
        Task {
            try? await Task.sleep(for: .seconds(0.13))
            withAnimation(.spring(duration: 0.45, bounce: 0.18)) {
                phase = finished ? .done : .streaming
            }
        }
    }

    @ViewBuilder
    private func picker(draft: Binding<String>) -> some View {
        switch kind {
        case .choice:
            choiceOptions(draft: draft)
        case .place where !options.isEmpty:
            choiceOptions(draft: draft)
        case .count:
            CountPickerView(spec: item.input, value: Binding(
                get: { draft.wrappedValue },
                set: {
                    draft.wrappedValue = $0
                    store.setAnswer(question: item.question, value: $0)
                }))
        case .date, .dateRange:
            DateRangePickerView(rangeMode: kind == .dateRange, bottomReserve: dockReserve, value: draft)
        case .place, .area:
            PlacePickerView(value: draft)
                .frame(height: 360)
        case .text:
            TextPickerView(question: item.question, value: draft)
        case .time:
            TimePickerView(value: draft)
        }
    }

    private func choiceOptions(draft: Binding<String>) -> some View {
        ScrollView {
            ChoiceOptions(options: options, presentation: item.input?.presentation ?? .rows,
                          rowHeight: 69, multiple: cards, selection: draft)
                .padding(.horizontal, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: sheetOptionsHeight)
    }

    private var sheetOptionsHeight: CGFloat {
        switch item.input?.presentation ?? .rows {
        case .rows: CGFloat(options.count) * 81 - 12
        case .chips: 200
        case .cards:
            CGFloat((options.count + 1) / 2) * (ChoiceCardGrid.cardHeight + ChoiceCardGrid.rowSpacing)
                - ChoiceCardGrid.rowSpacing
        }
    }
}

private struct StreamedOptionRow: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let option: QuestionOption
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            guard blockInteraction.allowsActivation else { return }
            action()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2.7) {
                    Text(option.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if !option.detail.isEmpty {
                        Text(option.detail)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineSpacing(1.1)
                    }
                }
                .multilineTextAlignment(.leading)
                .contentTransition(.identity)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 222, alignment: .leading)
                Spacer(minLength: 0)
                Text(option.tag)
                    .font(.system(size: 15.5))
                    .contentTransition(.identity)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 15.5)
            .padding(.vertical, 16.35)
            .animation(nil, value: option)
            .frame(maxWidth: .infinity, minHeight: 69)
            .background(InputOptionBackground(selected: selected, rest: InputPalette.streamedOption))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .blockActivationControl()
        .buttonStyle(.pressable)
        .animation(.smooth(duration: 0.2), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
