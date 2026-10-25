import SwiftUI
import EmblemCore

private struct ComparisonTableExtent: Equatable {
    let viewport: CGSize
    let naturalWidth: CGFloat

    var overflowsVertically: Bool { viewport.height > 470 }
    var needsExpansion: Bool { overflowsVertically || naturalWidth > viewport.width }
}

private struct FrozenColumnTable: View {
    let block: ComparisonTable
    var rowPadding: CGFloat = 12
    var expanded = false
    var onExtentChange: (ComparisonTableExtent) -> Void = { _ in }
    var insetsTrailingRules = false
    @State private var overflow = Overflow()
    @State private var availableWidth: CGFloat = 0

    @ScaledMetric(relativeTo: .footnote) private var fontSize: CGFloat = 14
    private var scale: CGFloat { fontSize / 14 }
    private var tableSurface: Color { expanded ? Theme.responsePaper : Theme.surface }
    private var tableFont: Font { .system(size: fontSize) }
    private var ranked: Bool { !block.rows.isEmpty && block.rows.allSatisfy { $0.rank != nil } }
    private var showsIcons: Bool { block.rows.contains { $0.icon != nil } }
    private var iconSlot: CGFloat { showsIcons ? 24 * scale : 0 }
    private var rankSlot: CGFloat {
        guard ranked else { return 0 }
        return ceil(block.rows.map { measuredWidth($0.rank ?? "", weight: .semibold) }.max() ?? 0) + 9 * scale
    }

    private func title(_ row: ComparisonTable.Row) -> String { ranked ? row.title : row.label }

    private var labelWidth: CGFloat {
        let lead = rankSlot + iconSlot
        let width = ([measuredWidth(block.rowHeader ?? "", weight: .semibold)] + block.rows.map {
            lead + max(measuredWidth(title($0), weight: .semibold), measuredWidth($0.subtitle ?? ""))
        }).max() ?? 0
        return min(expanded ? 200 : 188, max(expanded ? 149 : 96, ceil(width) + 28))
    }

    private var collapsedLabelWidth: CGFloat { min(labelWidth, 72 * scale) }

    private func measuredWidth(_ text: String, weight: UIFont.Weight = .regular) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize, weight: weight)]).width
    }

    private func columnWidth(_ index: Int) -> CGFloat {
        let cells = block.rows.compactMap { $0.values.indices.contains(index) ? $0.values[index] : nil }
        let content = cells.map { measuredWidth($0.value, weight: $0.verdict == nil ? .regular : .semibold) + ($0.verdict == nil ? 0 : 12) }
        let width = max(measuredWidth(block.columns[index], weight: .semibold), content.max() ?? 0)
        let natural = max(52, ceil(width) + 28)
        return expanded ? min(176 * scale, natural) : natural
    }

    private func fittedWidths(_ available: CGFloat) -> (label: CGFloat, values: [CGFloat]) {
        let naturals = block.columns.indices.map(columnWidth)
        guard available >= naturalWidth else { return (labelWidth, naturals) }
        let share = available / CGFloat(max(1, block.columns.count) * 2)
        let growth = naturals.map { max(0, share - $0) }
        let wanted = growth.reduce(0, +)
        let room = available - naturalWidth
        let factor = wanted > room ? room / wanted : 1
        let values = zip(naturals, growth).map { $0 + $1 * factor }
        return (available - values.reduce(0, +), values)
    }

    private func alignment(_ index: Int) -> Alignment {
        if let authored = block.columnAlignments, authored.indices.contains(index) {
            return switch authored[index] { case .left: .leading; case .center: .center; case .right: .trailing }
        }
        let values = block.rows.compactMap { $0.values.indices.contains(index) ? $0.values[index].value : nil }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0 != "—" && $0 != "–" }
        let numeric = !values.isEmpty && values.allSatisfy {
            $0.range(of: #"^[\s\p{Sc}\p{N}.,:%+\-−–()/]+$"#, options: .regularExpression) != nil
                && $0.contains(where: \.isNumber)
        }
        return numeric ? .trailing : .leading
    }

    private struct Overflow: Equatable {
        var leading = false
        var trailing = false
        var offset: CGFloat = 0
    }

    private var naturalWidth: CGFloat {
        labelWidth + block.columns.indices.reduce(0) { $0 + columnWidth($1) }
    }

    var body: some View {
        let contentWidth = naturalWidth
        return Group {
            if expanded {
                scrollTable(fits: false)
            } else {
                ViewThatFits(in: .horizontal) {
                    scrollTable(fits: true)
                        .frame(minWidth: naturalWidth, idealWidth: naturalWidth, maxWidth: .infinity)
                    scrollTable(fits: false)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: ComparisonTableExtent.self) { geometry in
            ComparisonTableExtent(viewport: geometry.size, naturalWidth: contentWidth)
        } action: {
            availableWidth = $0.viewport.width
            onExtentChange($0)
        }
    }

    private func scrollTable(fits: Bool) -> some View {
        let frozenWidth = max(collapsedLabelWidth, labelWidth - overflow.offset)
        return ScrollView(.horizontal, showsIndicators: false) {
            grid(frozenLabels: false, fits: fits)
                .overlay(alignment: .topLeading) {
                    if !fits {
                        ZStack(alignment: .leading) {
                            grid(frozenLabels: true, fits: false)
                                .mask(alignment: .leading) {
                                    Rectangle().frame(width: frozenWidth)
                                }
                                .background(alignment: .leading) {
                                    tableSurface.frame(width: frozenWidth)
                                }
                            VStack(spacing: 0) {
                                frozenSeam(header: true)
                                    .frame(height: expanded ? 48 * scale : UIFont.systemFont(ofSize: fontSize).lineHeight + rowPadding * 2)
                                frozenSeam(header: false)
                            }
                                .frame(width: 14)
                                .offset(x: frozenWidth)
                                .opacity(overflow.leading ? 1 : 0)
                        }
                        .offset(x: overflow.offset)
                        .allowsHitTesting(false)
                    }
                }
        }
        .scrollDisabled(fits)
        .fixedSize(horizontal: false, vertical: true)
        .onScrollGeometryChange(for: Overflow.self) { geometry in
            let offset = geometry.contentOffset.x + geometry.contentInsets.leading
            let remaining = geometry.contentSize.width - geometry.containerSize.width - offset
            return Overflow(leading: offset > 1, trailing: remaining > 1, offset: max(0, offset))
        } action: { _, value in
            if !fits { overflow = value }
        }
        .overlay(alignment: .trailing) {
            LinearGradient(colors: [tableSurface.opacity(0), tableSurface], startPoint: .leading, endPoint: .trailing)
                .frame(width: 28)
                .opacity(!fits && !expanded && overflow.trailing ? 1 : 0)
                .allowsHitTesting(false)
        }
        .accessibilityIdentifier("comparison-table-\(block.id)")
    }

    private func frozenSeam(header: Bool) -> some View {
        let samples: [(CGFloat, Double)] = header
            ? [(0, 8.57), (1, 5.57), (2, 3.87), (3, 2.87), (4, 2.07), (6, 1.08), (8, 0.55), (10, 0), (14, 0)]
            : [(0, 13), (1, 10), (2, 7), (3, 5), (4, 4), (6, 3), (8, 2), (10, 2), (12, 1), (14, 0)]
        return LinearGradient(stops: samples.map {
            .init(color: Theme.ink.opacity($0.1 / 224), location: $0.0 / 14)
        }, startPoint: .leading, endPoint: .trailing)
    }

    private func grid(frozenLabels: Bool, fits: Bool) -> some View {
        let fitted = fits && availableWidth > 0 ? fittedWidths(availableWidth) : nil
        let labelColumn = fitted?.label ?? labelWidth
        let valueColumn = { (index: Int) in fitted.map { $0.values[index] } ?? columnWidth(index) }
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                measuredCell(row: -1, width: labelColumn, fits: fits) { header(block.rowHeader ?? "") }
                    .opacity(fits || frozenLabels ? 1 : 0)
                    .accessibilityHidden(!fits && !frozenLabels)
                ForEach(Array(block.columns.enumerated()), id: \.offset) { index, title in
                    measuredCell(row: -1, width: valueColumn(index), alignment: alignment(index), fillsWidth: true, fits: fits) { header(title) }
                        .opacity(frozenLabels ? 0 : 1)
                        .accessibilityHidden(frozenLabels)
                }
            }
            if !fits {
                headerSeparator
                    .gridCellColumns(block.columns.count + 1)
                    .gridCellUnsizedAxes(.horizontal)
            }
            ForEach(Array(block.rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    measuredCell(row: rowIndex, width: labelColumn, fits: fits) {
                        rowLabel(row, fits: fits)
                    }
                    .overlay(alignment: .bottom) {
                        if expanded || rowIndex < block.rows.count - 1 { separator.padding(.leading, expanded ? 0 : 14) }
                    }
                    .opacity(fits || frozenLabels ? 1 : 0)
                    .accessibilityHidden(!fits && !frozenLabels)
                    ForEach(block.columns.indices, id: \.self) { index in
                        measuredCell(row: rowIndex, width: valueColumn(index), alignment: alignment(index), fillsWidth: true, fits: fits) {
                            valueCell(row: row, index: index)
                        }
                        .overlay(alignment: .bottom) {
                            if expanded || rowIndex < block.rows.count - 1 {
                                separator.padding(.trailing,
                                    fits && insetsTrailingRules && index == block.columns.count - 1 ? 14 : 0)
                            }
                        }
                        .opacity(frozenLabels ? 0 : 1)
                        .accessibilityHidden(frozenLabels)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in max(width, naturalWidth) }
    }

    private func rowLabel(_ row: ComparisonTable.Row, fits: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if ranked, let rank = row.rank {
                Text(rank)
                    .font(tableFont.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: rankSlot, alignment: .leading)
            }
            if showsIcons {
                IconView(icon: row.icon, size: 17 * scale)
                    .frame(width: iconSlot, height: UIFont.systemFont(ofSize: fontSize).lineHeight, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: fits ? 8 / 3 : 4) {
                Text(title(row)).font(tableFont.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle = row.subtitle {
                    Text(subtitle).font(tableFont).foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var separator: some View {
        Rectangle().fill(Theme.ink.opacity(0.16)).frame(height: 0.5)
    }

    private var headerSeparator: some View {
        Rectangle().fill(Theme.ink.opacity(0.16)).frame(height: 1)
    }

    private var headerFill: Color { Theme.ink.opacity(expanded ? 0.012 : 0.06) }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(tableFont.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }

    private func measuredCell<Content: View>(
        row: Int, width: CGFloat, alignment: Alignment = .leading, fillsWidth: Bool = false,
        fits: Bool, @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, rowPadding)
            .frame(width: width, alignment: alignment)
            .frame(minWidth: width, maxWidth: fillsWidth && !fits ? .infinity : width, alignment: alignment)
            .frame(minHeight: minimumHeight(row: row, fits: fits), maxHeight: .infinity, alignment: alignment)
            .background(row < 0 && (fits || expanded) ? headerFill : .clear)
    }

    private func minimumHeight(row: Int, fits: Bool) -> CGFloat? {
        if expanded { return (row < 0 ? 48 : 50) * scale }
        if fits { return (row < 0 ? 50 : block.rows.contains { $0.subtitle != nil } ? 66 : 50) * scale }
        return row >= 0 ? 42 * scale : nil
    }

    private func valueCell(row: ComparisonTable.Row, index: Int) -> some View {
        let cell = row.values.indices.contains(index) ? row.values[index] : .init(value: "–")
        return VStack(alignment: alignment(index) == .trailing ? .trailing : .leading, spacing: 4) {
            if let verdict = cell.verdict {
                Text(cell.value)
                    .font(tableFont.weight(.semibold))
                    .foregroundStyle(tint(verdict))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(fill(verdict), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Text(cell.value)
                    .font(tableFont)
                    .lineSpacing(scale)
                    .padding(.vertical, expanded ? 2 / 3 * scale : 0)
                    .foregroundStyle(Theme.ink)
            }
            if let note = cell.chipLabel {
                Text(note)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint(cell.verdict))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            row.label, block.columns[index], cell.value,
            cell.verdict.map { $0 == .good ? "positive" : "negative" }, cell.chipLabel,
        ].compactMap { $0 }.joined(separator: ", "))
    }

    private func tint(_ verdict: ComparisonTable.Verdict?) -> Color {
        switch verdict {
        case .good: Theme.comparisonPositive
        case .bad: Theme.comparisonNegative
        case nil: Theme.inkSecondary
        }
    }

    private func fill(_ verdict: ComparisonTable.Verdict) -> Color {
        verdict == .good ? Theme.comparisonPositiveFill : Theme.comparisonNegativeFill
    }
}

struct ComparisonTableView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let block: ComparisonTable
    @State private var expanded = false
    @State private var closing = false
    @State private var sourceFrame: CGRect = .zero
    @State private var liveFrame = GlobalFrameBox()
    @State private var extent: ComparisonTableExtent?
    @State private var presentationID = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tablePresentation) private var tablePresentation

    var body: some View {
        card
            .simultaneousGesture(TapGesture().onEnded { presentExpandedTable() })
            .overlay(alignment: .bottomTrailing) {
                if extent?.needsExpansion == true {
                    ExpandButton(action: presentExpandedTable)
                        .padding(12)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { liveFrame.frame = $0 }
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                    .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .opacity(expanded ? 0 : 1)
            .padding(.horizontal, Theme.textMargin)
            .fullScreenCover(isPresented: $expanded, onDismiss: {
                tablePresentation?.didDismiss(id: presentationID, reduceMotion: reduceMotion)
            }) {
                morphSurface
            }
    }

    private var card: some View {
        FrozenColumnTable(block: block, onExtentChange: { extent = $0 },
                          insetsTrailingRules: extent?.needsExpansion == false)
            .frame(maxHeight: 470, alignment: .top)
            .contentShape(Rectangle())
            .clipped()
            .overlay(alignment: .bottom) {
                if extent?.overflowsVertically == true {
                    LinearGradient(colors: [.clear, Theme.surface], startPoint: .top, endPoint: .bottom)
                        .frame(height: 60)
                        .allowsHitTesting(false)
                }
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var morphSurface: some View {
        ExpandMorphSurface(sourceFrame: sourceFrame, cornerRadius: 20, closing: closing,
                           reduceMotion: reduceMotion, onClosed: finishClosing) {
            card
                .overlay(alignment: .bottomTrailing) {
                    if extent?.needsExpansion == true {
                        ExpandButton(action: {}).padding(12)
                    }
                }
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        } expanded: {
            expandedTable
        }
    }

    private func presentExpandedTable() {
        guard extent?.needsExpansion == true, blockInteraction.allowsActivation, !expanded else { return }
        sourceFrame = liveFrame.frame
        tablePresentation?.present(id: presentationID)
        closing = false
        withoutAnimation { expanded = true }
    }

    private func closeExpandedTable() {
        tablePresentation?.dismiss(id: presentationID, reduceMotion: reduceMotion)
        if reduceMotion { finishClosing(); return }
        withoutAnimation { closing = true }
    }

    private func finishClosing() {
        withoutAnimation {
            expanded = false
            closing = false
        }
    }

    private var expandedTable: some View {
        ScrollView(.vertical) {
            FrozenColumnTable(block: block, rowPadding: 14, expanded: true)
        }
        .background(Theme.responsePaper.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button(action: closeExpandedTable) {
                    CloseGlyph(variant: .table)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .glassEffect(.regular.interactive(), in: .circle)
                        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close table")
                Spacer()
                ShareLink(item: shareText) {
                    ChromeGlyph(symbol: .share, size: 22)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .blockActivationControl()
                .buttonStyle(.plain)
                .accessibilityLabel("Share table")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 13)
            .background(Theme.ink.opacity(0.012).background(Theme.responsePaper).ignoresSafeArea())
        }
    }

    private var shareText: String {
        let header = ([block.rowHeader ?? ""] + block.columns).joined(separator: "\t")
        let rows = block.rows.map { row in
            ([row.label] + block.columns.indices.map { index in
                row.values.indices.contains(index) ? row.values[index].value : ""
            }).joined(separator: "\t")
        }
        return ([header] + rows).joined(separator: "\n")
    }
}
