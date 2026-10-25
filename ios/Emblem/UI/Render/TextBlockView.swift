import SwiftUI
import EmblemCore

struct TextBlockView: View {
    let block: TextBlock
    @Environment(\.renderedPage) private var renderedPage
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.responseRevealTiming) private var responseRevealTiming
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    @State private var markerRevealed = false
    @State private var markerElapsed = 0.0
    @State private var markerPlanKey: String?
    @State private var markerFirstPresentation: Bool?
    @State private var markerBottom: CGFloat?
    @State private var markerLineWidth: CGFloat = 0
    @State private var markerPhraseWidths: [MarkerPhraseKey: CGFloat] = [:]

    private struct MarkerPhraseKey: Hashable {
        let text: AttributedString
        let font: Font
        let dynamicTypeSize: DynamicTypeSize
        let legibilityWeight: LegibilityWeight?
    }

    private var usesAtomicHighlights: Bool { block.style == .intro && renderedPage?.isHome != true && block.id != "greeting" }

    private func phraseKey(_ text: AttributedString) -> MarkerPhraseKey {
        MarkerPhraseKey(text: text, font: font, dynamicTypeSize: dynamicTypeSize, legibilityWeight: legibilityWeight)
    }

    private var pageMargin: CGFloat { renderedPage?.isHome == true ? Theme.homeMargin : 32 }

    private var body_: AttributedString {
        (try? AttributedString(
            markdown: block.body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(block.body)
    }

    private var markedText: Text {
        let attributed = body_
        let ranges = block.highlightRanges(in: attributed)
        guard !ranges.isEmpty else { return Text(attributed) }
        var result = Text("")
        var didGroup = false
        var start = attributed.startIndex
        for (order, range) in ranges.enumerated() {
            let plain = Text(AttributedString(attributed[start..<range.lowerBound]))
            let source = AttributedString(attributed[range])
            let startsAtBreak = range.lowerBound == attributed.startIndex ||
                attributed.characters[attributed.characters.index(before: range.lowerBound)].isWhitespace
            let display = usesAtomicHighlights && startsAtBreak ? HighlightPhraseWrapping.displayCopy(source,
                measuredWidth: markerPhraseWidths[phraseKey(source)], lineWidth: markerLineWidth) : source
            didGroup = didGroup || display != source
            let marked = Text(display).customAttribute(TextMarkerAttribute(order: order))
            result = Text("\(result)\(plain)\(marked)")
            start = range.upperBound
        }
        let marked = Text("\(result)\(Text(AttributedString(attributed[start..<attributed.endIndex])))")
        return didGroup ? marked.accessibilityLabel(Text(attributed)) : marked
    }

    private var markerPhrases: [AttributedString] {
        let attributed = body_
        return block.highlightRanges(in: attributed).map { AttributedString(attributed[$0]) }
    }

    private var markerPhraseMeasurements: some View {
        ZStack {
            ForEach(Array(markerPhrases.enumerated()), id: \.offset) { _, phrase in
                Text(HighlightPhraseWrapping.candidate(phrase) ?? phrase)
                    .font(font)
                    .tracking(-0.5)
                    .fixedSize(horizontal: true, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        let keys = markerPhrases.map(phraseKey)
                        var retained = markerPhraseWidths.filter { keys.contains($0.key) }
                        retained[phraseKey(phrase)] = width
                        markerPhraseWidths = retained
                    }
            }
        }
        .hidden()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var marker: TextMarkerRenderer {
        let currentPlan = markerPlanKey == markerSchedule.key
        let alreadyPresented = renderedPage?.hasPresentedHighlight(for: block) == true &&
            (!currentPlan || (!markerRevealed && markerFirstPresentation != true))
        return TextMarkerRenderer(
            elapsed: reduceMotion || alreadyPresented ? markerDuration : currentPlan ? markerElapsed : 0,
            color: colorScheme == .dark
                ? Color(red: 0.60, green: 0.48, blue: 0.02).opacity(0.65)
                : Color(.displayP3, red: 63295 / 65535, green: 59999 / 65535, blue: 27280 / 65535))
    }

    private var markerDuration: Double {
        TextMarkerRenderer.wipe + TextMarkerRenderer.stagger * Double(max(0, block.highlightRanges(in: body_).count - 1))
    }

    private struct MarkerSchedule: Hashable {
        let key: String
        let body: String
        let bottom: CGFloat?
        let reveal: ResponseRevealTiming?
        let reduceMotion: Bool
    }

    private var markerSchedule: MarkerSchedule {
        MarkerSchedule(key: block.id + "\u{1F}" + (block.highlights ?? []).joined(separator: "\u{1F}"),
                       body: block.body, bottom: markerBottom,
                       reveal: responseRevealTiming, reduceMotion: reduceMotion)
    }

    var body: some View {
        content
            .blockActivationLinks()
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { bottom in
                if block.highlights?.isEmpty == false, !markerRevealed,
                   abs(bottom - (markerBottom ?? -.infinity)) > 24 { markerBottom = bottom }
            }
            .task(id: markerSchedule) { await revealMarker() }
            .onDisappear {
                if !block.highlightRanges(in: body_).isEmpty {
                    _ = renderedPage?.claimHighlightReveal(for: block)
                    markerRevealed = true
                    updateMarker(animation: nil)
                }
            }
    }

    private func revealMarker() async {
        guard !block.highlightRanges(in: body_).isEmpty else { return }
        let key = markerSchedule.key
        if markerPlanKey != key {
            markerPlanKey = key
            markerRevealed = false
            markerFirstPresentation = nil
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = false
            withTransaction(transaction) { markerElapsed = 0 }
        }
        guard !markerRevealed else {
            if markerElapsed != markerDuration { updateMarker(animation: nil) }
            return
        }
        guard let bottom = markerBottom else { return }
        if markerFirstPresentation == nil {
            markerFirstPresentation = renderedPage?.claimHighlightReveal(for: block) ?? true
        }
        if reduceMotion || markerFirstPresentation == false {
            markerRevealed = true
            updateMarker(animation: nil)
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(16))
            if let responseRevealTiming {
                let delay = responseRevealTiming.readyAt(regionBottom: bottom).timeIntervalSinceNow
                if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            }
            try Task.checkCancellation()
        } catch { return }
        markerRevealed = true
        updateMarker(animation: .linear(duration: markerDuration))
    }

    private func updateMarker(animation: Animation?) {
        var transaction = Transaction(animation: animation)
        transaction.disablesAnimations = false
        withTransaction(transaction) { markerElapsed = markerDuration }
    }

    @ViewBuilder private var content: some View {
        if block.id == "greeting", block.style == .intro {
            HomeGreetingView(block: block, body_: body_)
        } else if block.style == .intro {
            markedText
                .font(font)
                .tracking(-0.5)
                .lineSpacing(renderedPage?.isHome == true ? 2 : 26 - UIFont.systemFont(ofSize: 20).lineHeight)
                .foregroundStyle(Theme.ink)
                .textRenderer(marker)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { markerLineWidth = $0 }
                .background { if usesAtomicHighlights { markerPhraseMeasurements } }
                .padding(.horizontal, pageMargin)
                .padding(.top, renderedPage?.isHome == true ? 0 : -2 / 3)
        } else {
            markedText
                .font(font)
                .lineSpacing(renderedPage?.isHome == true || block.style != .body ? 0 : 3)
                .foregroundStyle(block.style == .footnote ? Theme.inkSecondary : Theme.ink)
                .textRenderer(marker)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, pageMargin)
        }
    }

    private var font: Font {
        switch block.style {
        case .intro: .system(size: 20)
        case .body: .system(size: 16)
        case .footnote: Theme.caption()
        }
    }
}

private enum HighlightPhraseWrapping {
    static func displayCopy(_ source: AttributedString, measuredWidth: CGFloat?, lineWidth: CGFloat) -> AttributedString {
        guard let measuredWidth, measuredWidth.isFinite, lineWidth.isFinite,
              measuredWidth > 0, lineWidth > 0, measuredWidth <= lineWidth else { return source }
        return candidate(source) ?? source
    }

    static func candidate(_ source: AttributedString) -> AttributedString? {
        guard source.characters.contains(" "), source.characters.first != " ", source.characters.last != " ",
              source.unicodeScalars.allSatisfy({ scalar in
                  let c = scalar.value
                  return (65...90).contains(c) || (97...122).contains(c) || (48...57).contains(c) ||
                      c == 32 || c == 44 || c == 46
              }) else { return nil }
        var display = AttributedString()
        for run in source.runs {
            var piece = AttributedString(String(source[run.range].characters).replacingOccurrences(of: " ", with: "\u{00A0}"))
            piece.setAttributes(run.attributes)
            display.append(piece)
        }
        return display
    }
}

private struct TextMarkerAttribute: TextAttribute {
    let order: Int
}

@MainActor
enum TextSweep {
    nonisolated static let done = 1_000.0
    nonisolated static let lineStagger = 0.1
    nonisolated static let lineSweep = 0.2
    nonisolated static let fade = 0.18
    private static var claimed: Set<String> = []

    static func claim(page: UUID, block: String) -> Bool {
        claimed.insert(page.uuidString + "\u{1F}" + block).inserted
    }

    nonisolated static func opacity(at time: Double, line: Int, x: CGFloat, width: CGFloat) -> Double {
        let start = Double(line) * lineStagger + Double(x / max(1, width)) * lineSweep
        return min(1, max(0, (time - start) / fade))
    }
}

private struct TextMarkerRenderer: TextRenderer {
    static let wipe = 0.25
    static let stagger = 0.06
    var elapsed: Double
    var color: Color
    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            var bands: [(rect: CGRect, order: Int)] = []
            for run in line {
                guard let marker = run[TextMarkerAttribute.self] else { continue }
                let rect = run.typographicBounds.rect
                if let last = bands.last, last.order == marker.order, rect.minX <= last.rect.maxX + 0.5 {
                    bands[bands.count - 1].rect = last.rect.union(rect)
                } else {
                    bands.append((rect, marker.order))
                }
            }
            for band in bands {
                let rect = band.rect.insetBy(dx: -2, dy: 0)
                let time = elapsed - Double(band.order) * Self.stagger
                let progress = min(1, max(0, time / Self.wipe))
                var reveal = context
                reveal.opacity = min(1, max(0, (time - 0.04) / 0.16))
                reveal.clip(to: Path(CGRect(
                    x: rect.minX, y: rect.minY,
                    width: rect.width * progress, height: rect.height)))
                reveal.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(color))
            }
            context.draw(line)
        }
    }
}
