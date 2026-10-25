import SwiftUI
import EmblemCore

struct CountPickerView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let spec: InputSpec?
    @Binding var value: String
    var inline = false

    @State private var count: Int = 1
    @State private var chipPick: Int?
    @State private var typing = false
    @State private var typed = ""
    @FocusState private var keyboardFocused: Bool

    private var unit: String { spec?.unit ?? "" }
    private var lower: Int { Int(spec?.min ?? 1) }
    private var upper: Int { Int(spec?.max ?? 99_999) }
    private var step: Int {
        if let step = spec?.step, step >= 1 { return Int(step) }
        let span = upper - lower
        switch span {
        case ..<40: return 1
        case ..<400: return 10
        case ..<4_000: return 50
        default: return 100
        }
    }
    private var shortcuts: [Int] {
        let suggested = (spec?.options ?? []).compactMap { Int($0.filter(\.isNumber)) }
        let candidates = suggested.count > 1 ? suggested : step == 1
            ? [lower, lower + 1, min(lower + 2, upper)]
            : [lower, lower + span4, min(lower + span4 * 2, upper)]
        return Array(Set(candidates))
            .filter { $0 >= lower && $0 <= upper }
            .sorted()
    }
    private var span4: Int { max(step, (upper - lower) / 4) }
    private var buttonSize: CGFloat { inline ? 56 : 58 }
    private var sideMargin: CGFloat { inline ? 56 : 57.5 }
    private var numberFont: Font {
        inline ? .system(size: 40, weight: .bold) : .system(size: 40, weight: .bold).monospacedDigit()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: inline ? .top : .center, spacing: 0) {
                stepButton("minus") { pick(count - step, chip: false) }
                    .disabled(count <= lower)
                Spacer(minLength: 0)
                VStack(spacing: inline ? -2.5 : -9) {
                    if typing {
                        TextField("", text: $typed)
                            .keyboardType(.numberPad)
                            .focused($keyboardFocused)
                            .font(numberFont)
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                            .blockActivationControl()
                            .onSubmit(commitTyped)
                            .onChange(of: keyboardFocused) { _, focused in
                                if !focused { commitTyped() }
                            }
                            .onChange(of: typed) { _, text in
                                if let entered = Int(text.filter(\.isNumber)) { set(entered, animated: false) }
                            }
                    } else {
                        Text("\(count)")
                            .font(numberFont)
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText())
                            .onTapGesture {
                                guard blockInteraction.allowsActivation else { return }
                                typed = "\(count)"
                                typing = true
                                keyboardFocused = true
                            }
                            .accessibilityHint("Double tap to type a value")
                            .accessibilityIdentifier("count-value")
                    }
                    if !unit.isEmpty {
                        Text(pluralUnit(count))
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.ink)
                            .padding(.bottom, inline ? 6 : 0)
                            .overlay(alignment: .bottom) {
                                if inline {
                                    Capsule().fill(InputPalette.rule).frame(width: 62, height: 2)
                                }
                            }
                    }
                }
                .frame(width: 150)
                .padding(.top, inline ? -10 : 0)
                Spacer(minLength: 0)
                stepButton("plus") { pick(count + step, chip: false) }
                    .disabled(count >= upper)
            }
            .padding(.horizontal, sideMargin)
            .padding(.top, inline ? 6 : 16)

            if shortcuts.count > 1 {
                SuggestionDivider(fontSize: inline ? 12 : 11.5, spacing: inline ? 5 : 8)
                    .padding(.horizontal, inline ? 88 : 57)
                    .padding(.top, inline ? 40.5 : 43)
                    .padding(.bottom, inline ? 23.5 : 28)
                LeadingFlowLayout(spacing: inline ? 4.5 : 6, lineSpacing: 4.5, centered: true) {
                    ForEach(shortcuts, id: \.self) { n in
                        SuggestionChip(label: "\(n) \(pluralUnit(n))", selected: n == (inline ? count : chipPick),
                                       height: inline ? 39.5 : 40) { pick(n, chip: true) }
                            .accessibilityIdentifier("count-chip-\(n)")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, inline ? 0 : 7)
            }
        }
        .task(id: blockInteraction.allowsStoreMutation) { seed() }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: { blockInteraction.performActivation(action) }) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: buttonSize, height: buttonSize)
                .background(Circle().fill(InputPalette.tile))
        }
        .blockActivationControl()
        .buttonStyle(.pressable)
        .accessibilityLabel(symbol == "plus" ? "Increase" : "Decrease")
        .accessibilityIdentifier("count-\(symbol)")
    }

    private func commitTyped() {
        guard blockInteraction.allowsActivation else { return }
        if let entered = Int(typed.filter(\.isNumber)) { set(entered) }
        typing = false
        keyboardFocused = false
    }

    private func pick(_ n: Int, chip: Bool) {
        typed = ""
        typing = false
        keyboardFocused = false
        chipPick = chip ? n : nil
        set(n)
    }

    private func seed() {
        let first = value.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
        let suggested = spec?.value.map { Int($0) }
        let start = inline
            ? first ?? suggested ?? lower
            : Int(value.trimmingCharacters(in: .whitespaces)) ?? suggested ?? first ?? lower
        count = Swift.min(Swift.max(start, lower), upper)
        chipPick = count
        if inline { set(count, animated: false) }
    }

    private func set(_ n: Int, animated: Bool = true) {
        let clamped = Swift.min(Swift.max(n, lower), upper)
        if animated {
            withAnimation(.spring(duration: 0.3)) { count = clamped }
        } else {
            count = clamped
        }
        value = unit.isEmpty || !inline ? "\(clamped)" : "\(clamped) \(pluralUnit(clamped))"
    }

    private func pluralUnit(_ n: Int) -> String {
        guard !unit.isEmpty, n != 1 else { return unit }
        let irregular = ["person": "people", "child": "children", "loaf": "loaves", "box": "boxes"]
        return irregular[unit.lowercased()] ?? (unit.hasSuffix("s") ? unit : unit + "s")
    }
}

struct SuggestionDivider: View {
    var fontSize: CGFloat = 15
    var spacing: CGFloat = 10

    var body: some View {
        HStack(spacing: spacing) {
            rule
            Text("Quick picks")
                .font(.system(size: fontSize))
                .foregroundStyle(InputPalette.hint)
                .fixedSize()
            rule
        }
    }

    private var rule: some View {
        Rectangle().fill(InputPalette.rule).frame(height: 1)
    }
}

struct SuggestionChip: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let label: String
    var selected = false
    var height: CGFloat = 38
    let action: () -> Void

    var body: some View {
        Button(action: { blockInteraction.performActivation(action) }) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12.5)
                .frame(height: height)
                .background(InputOptionBackground(selected: selected, radius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .blockActivationControl()
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.smooth(duration: 0.2), value: selected)
    }
}
