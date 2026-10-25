import SwiftUI
import EmblemCore

struct TitleBlockView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(\.renderedPage) private var renderedPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let block: TitleBlock
    var sweepsIn = false
    var metaGlyphs = false
    @Environment(\.performAction) private var performAction
    @State private var sweep = TextSweep.done

    private var metaSegments: [String] {
        (block.metaLine ?? "").components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var summaryStart: Double { 0.16 + Double(metaSegments.count) * 0.08 }
    private var tagsStart: Double { summaryStart + 0.45 }

    var body: some View {
        VStack(spacing: 12) {
            Text(block.title)
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .textRenderer(LeadSweepRenderer(time: sweep, start: 0))

            if metaGlyphs, !metaSegments.isEmpty {
                eventMetaRow
                    .padding(.top, 13)
                    .padding(.bottom, -4)
            } else if let metaLine = block.metaLine {
                Text(metaLine)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 9)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .textRenderer(LeadSweepRenderer(time: sweep, start: 0.16))
            }

            if let summary = block.summary {
                Text(summary)
                    .font(.system(size: 16))
                    .lineSpacing(2.6)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 9)
                    .textRenderer(LeadSweepRenderer(time: sweep, start: summaryStart))
            }

            if let tags = block.tags, !tags.isEmpty {
                TagFlowLayout(spacing: 4) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                        Text(tag)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Theme.itemTile, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .modifier(SweepOpacity(time: sweep, start: tagsStart + Double(index) * 0.07))
                    }
                }
                .padding(.top, 5)
                .frame(maxWidth: .infinity)
            }

            if let actions = block.actions, !actions.isEmpty {
                ViewThatFits(in: .horizontal) {
                    EqualWidthRow(spacing: 12) { ForEach(actions, id: \.self) { actionButton($0, wraps: false) } }
                    VStack(spacing: 10) { ForEach(actions, id: \.self) { actionButton($0, wraps: true) } }
                }
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.contentMargin)
        .onAppear(perform: startSweep)
    }

    private func actionButton(_ action: Action, wraps: Bool) -> some View {
        Button {
            guard blockInteraction.allowsActivation else { return }
            performAction(action)
        } label: {
            HStack(spacing: 7) {
                GlyphImage(symbol: action.sfSymbol ?? "play.fill", size: 18, weight: .semibold)
                Text(action.label)
                    .font(.system(size: 16, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: !wraps, vertical: true)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .blockActivationControl()
        .buttonStyle(.pressable)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var eventMetaRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(metaSegments.enumerated()), id: \.offset) { index, segment in
                HStack(spacing: 3) {
                    if index > 0 { Text("·") }
                    GlyphImage(symbol: Self.metaSymbol(for: segment), size: 17)
                    Text(segment).lineLimit(1)
                }
                .modifier(SweepOpacity(time: sweep, start: 0.16 + Double(index) * 0.08))
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private static func metaSymbol(for segment: String) -> String {
        let text = segment.lowercased()
        if text.range(of: #"\d{1,2}[:.]\d{2}"#, options: .regularExpression) != nil
            || text.contains("all day") || text.hasSuffix("am") || text.hasSuffix("pm") { return "clock.fill" }
        let dated = #"^(recurring|repeats|weekly|daily|monthly|every|today|tomorrow|monday|tuesday|wednesday|"#
            + #"thursday|friday|saturday|sunday|mon|tue|tues|wed|thu|thurs|fri|sat|sun|january|february|march|"#
            + #"april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|"#
            + #"sept|oct|nov|dec)\b"#
        if text.range(of: dated, options: .regularExpression) != nil { return "calendar" }
        if ["zoom", "google meet", "teams", "video", "facetime", "webex"].contains(where: text.contains) {
            return "video"
        }
        if text.hasPrefix("with ") { return "person.2" }
        return "mappin.and.ellipse"
    }

    private func startSweep() {
        guard sweepsIn, !reduceMotion, let page = renderedPage,
              TextSweep.claim(page: page.id, block: "lead#" + block.id) else { return }
        let total = tagsStart + Double(block.tags?.count ?? 0) * 0.07 + TextSweep.fade
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { sweep = 0 }
        withAnimation(.linear(duration: total)) {
            sweep = total
        } completion: {
            var settle = Transaction(animation: nil)
            settle.disablesAnimations = true
            withTransaction(settle) { sweep = TextSweep.done }
        }
    }
}

private struct LeadSweepRenderer: TextRenderer {
    var time: Double
    let start: Double
    nonisolated var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        guard time < TextSweep.done else {
            for line in layout { context.draw(line) }
            return
        }
        let width = layout.map { $0.typographicBounds.rect.maxX }.max() ?? 1
        for (index, line) in layout.enumerated() {
            for run in line {
                for slice in run {
                    var glyph = context
                    glyph.opacity = TextSweep.opacity(
                        at: time - start, line: index, x: slice.typographicBounds.rect.minX, width: width)
                    glyph.draw(slice)
                }
            }
        }
    }
}

private struct SweepOpacity: ViewModifier, Animatable {
    var time: Double
    let start: Double
    nonisolated var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(time >= TextSweep.done ? 1 : min(1, max(0, (time - start) / TextSweep.fade)))
    }
}

private struct TagFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let proposedWidth = proposal.width ?? 0
        let naturalWidth = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let maxWidth = proposedWidth.isFinite && proposedWidth > 0
            ? proposedWidth
            : naturalWidth
        let rows = makeRows(subviews: subviews, maxWidth: maxWidth)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in makeRows(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.midX - row.width / 2
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func makeRows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        for subview in subviews {
            let natural = subview.sizeThatFits(.unspecified)
            let width = min(natural.width, maxWidth)
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: natural.height))
            if let last = rows.indices.last,
               rows[last].width + spacing + size.width <= maxWidth {
                rows[last].items.append(Item(subview: subview, size: size))
                rows[last].width += spacing + size.width
                rows[last].height = max(rows[last].height, size.height)
            } else {
                rows.append(Row(
                    items: [Item(subview: subview, size: size)],
                    width: size.width,
                    height: size.height))
            }
        }
        return rows
    }

    private struct Item {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct Row {
        var items: [Item]
        var width: CGFloat
        var height: CGFloat
    }
}

private struct EqualWidthRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(width: proposal.width ?? (sizes.map(\.width).max() ?? 0) * CGFloat(subviews.count) + gaps,
                      height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        let width = (bounds.width - gaps) / CGFloat(max(1, subviews.count))
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.minY),
                          proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}
