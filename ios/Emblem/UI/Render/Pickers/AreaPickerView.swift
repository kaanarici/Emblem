import SwiftUI
import MapKit
import EmblemCore

enum AreaAnswer {
    static func text(_ reading: AreaReading, nearYou: Bool) -> String {
        let name = reading.spot ?? (nearYou ? "Near me" : reading.locality ?? "The map area")
        let size = measure(reading.meters)
        let lat = reading.center.latitude.formatted(.number.precision(.fractionLength(2)))
        let lng = reading.center.longitude.formatted(.number.precision(.fractionLength(2)))
        return "\(name) (about a \(size.value) \(size.short) area around \(lat), \(lng))"
    }

    static func place(in answer: String) -> String {
        answer.range(of: " (about a ").map { String(answer[..<$0.lowerBound]) } ?? answer
    }

    static func measure(_ diameter: Double) -> (value: String, unit: String, short: String) {
        let miles = Locale.current.measurementSystem == .us
        let amount = diameter / 2 / (miles ? 1609.344 : 1000)
        let value = amount < 1
            ? amount.formatted(.number.precision(.fractionLength(1)))
            : Int(amount.rounded()).formatted()
        return (value, miles ? "mile" : "km", miles ? "mi" : "km")
    }
}

struct AreaPickerPage: View {
    @Environment(ConversationStore.self) private var store
    let item: QuestionList.Item
    @State private var selection: AreaSelection? = AreaSelection.debugLaunch

    var body: some View {
        ZStack {
            AreaLensMap(spots: item.input?.areas ?? [], lensCenter: 0.491, selection: $selection) { reading in
                store.setAnswer(question: item.question,
                                value: AreaAnswer.text(reading, nearYou: selection == .nearYou))
            }
            .ignoresSafeArea()
            VStack(spacing: 0) {
                Text(item.question)
                    .font(.system(size: 17))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                AreaChips(spots: item.input?.areas ?? [], selection: $selection)
                    .padding(.bottom, 88)
            }
        }
        .accessibilityIdentifier("area-page")
    }
}

struct AreaQuestionSheet: View {
    @Environment(ConversationStore.self) private var store
    let item: QuestionList.Item
    let headerDrag: AnyGesture<Void>
    @State private var selection: AreaSelection? = AreaSelection.debugLaunch

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40, style: .continuous)
        ZStack(alignment: .top) {
            AreaLensMap(spots: item.input?.areas ?? [], lensCenter: 0.429, selection: $selection) { reading in
                store.questionDraft = AreaAnswer.text(reading, nearYou: selection == .nearYou)
            }
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(InputPalette.grabber)
                        .frame(width: 58, height: 4)
                        .padding(.top, 5.7)
                    Text(item.input?.ask ?? item.question)
                        .font(.system(size: 19.3, weight: .bold))
                        .tracking(-0.5)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.ink)
                        .shadow(color: Color(uiColor: .systemBackground).opacity(0.9), radius: 3)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 28)
                        .padding(.top, 22)
                        .padding(.bottom, 10)
                        .accessibilityAddTraits(.isHeader)
                }
                .contentShape(Rectangle())
                .gesture(headerDrag)
                Spacer(minLength: 0)
                AreaChips(spots: item.input?.areas ?? [], selection: $selection)
                    .padding(.bottom, 117)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(shape)
        .ignoresSafeArea(edges: .bottom)
        .padding(.top, 60)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("question-sheet")
        .onAppear {
            if item.input?.areas?.isEmpty ?? true { selection = .nearYou }
        }
    }
}

extension AreaSpot {
    var glyph: String { Hugeicons.isRenderable(sym) ? sym ?? "mappin" : "mappin" }
}

struct AreaChips: View {
    let spots: [AreaSpot]
    @Binding var selection: AreaSelection?

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    chip("Near you", symbol: "location", value: .nearYou)
                    ForEach(spots, id: \.label) { spot in
                        chip(spot.label, symbol: spot.glyph, value: .spot(spot.label))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, selection in
                guard let selection else { return }
                withAnimation(.smooth(duration: 0.4)) { reader.scrollTo(selection, anchor: .center) }
            }
        }
    }

    private func chip(_ label: String, symbol: String, value: AreaSelection) -> some View {
        let chosen = selection == value
        return Button {
            selection = value
        } label: {
            HStack(spacing: 8) {
                GlyphImage(symbol: symbol, size: 17, weight: .regular)
                    .frame(width: 19, height: 19)
                Text(label)
                    .font(.system(size: 15.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 13)
            .frame(height: 38.5)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.ink, lineWidth: 1.6)
                    .opacity(chosen ? 1 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .id(value)
        .animation(.easeOut(duration: 0.2), value: chosen)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("area-chip-\(label)")
    }
}

struct AreaArcLabel: View {
    let reading: AreaReading?
    let radius: CGFloat

    private struct Glyph {
        let text: String
        let font: UIFont
        let color: Color
    }

    var body: some View {
        let glyphs = Self.glyphs(for: reading)
        let widths = glyphs.map { ($0.text as NSString).size(withAttributes: [.font: $0.font]).width }
        let total = widths.reduce(0, +)
        ZStack {
            ForEach([true, false], id: \.self) { isHalo in
                ForEach(glyphs.indices, id: \.self) { index in
                    let middle = widths[..<index].reduce(0, +) + widths[index] / 2 - total / 2
                    let glyph = glyphs[index]
                    Group {
                        if isHalo {
                            Self.halo(glyph)
                        } else {
                            Text(glyph.text)
                                .font(Font(glyph.font))
                                .foregroundStyle(glyph.color)
                                .fixedSize()
                        }
                    }
                    .offset(y: -(radius + glyph.font.capHeight / 2))
                    .rotationEffect(.radians(Double(middle / radius)))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(glyphs.map(\.text).joined())
    }

    private static func halo(_ glyph: Glyph) -> some View {
        ZStack {
            ForEach(0..<8, id: \.self) { step in
                let angle = Double(step) * .pi / 4
                Text(glyph.text)
                    .font(Font(glyph.font))
                    .fixedSize()
                    .offset(x: 2 * cos(angle), y: 2 * sin(angle))
            }
        }
        .foregroundStyle(Color(uiColor: .systemBackground))
    }

    private static func glyphs(for reading: AreaReading?) -> [Glyph] {
        guard let reading else { return [] }
        let size = AreaAnswer.measure(reading.meters)
        let bold = UIFont.systemFont(ofSize: 17.5, weight: .bold)
        let light = UIFont.systemFont(ofSize: 17.5, weight: .regular)
        var runs: [(String, UIFont, Color)] = [
            ("\(size.value)-\(size.unit)", bold, Theme.ink),
            (" area", light, Theme.ink.opacity(0.72)),
        ]
        if let locality = reading.locality {
            runs.append((", ", light, Theme.ink.opacity(0.72)))
            runs.append((locality, bold, Theme.ink))
        }
        return runs.flatMap { text, font, color in text.map { Glyph(text: String($0), font: font, color: color) } }
    }
}
