import Charts
import SwiftUI
import EmblemCore

struct ChartBlockView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let block: ChartBlock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tablePresentation) private var tablePresentation
    @State private var progress: Double = 0
    @State private var expanded = false
    @State private var closing = false
    @State private var sourceFrame: CGRect = .zero
    @State private var liveFrame = GlobalFrameBox()
    @State private var presentationID = UUID()
    @State private var selectedLabel: String?

    private var series: [ChartBlock.Series] {
        block.series.filter { !$0.points.isEmpty }
    }

    private var xLabels: [String] {
        var seen = Set<String>()
        return series.flatMap(\.points).compactMap { point in
            seen.insert(point.label).inserted ? point.label : nil
        }
    }

    var body: some View {
        if !series.isEmpty {
            card(expand: presentExpandedChart)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { liveFrame.frame = $0 }
                .opacity(expanded ? 0 : 1)
                .padding(.horizontal, Theme.contentMargin)
                .clipped()
                .onAppear {
                    if reduceMotion { progress = 1 }
                    else { withAnimation(.smooth(duration: 0.8)) { progress = 1 } }
                }
                .fullScreenCover(isPresented: $expanded, onDismiss: {
                    tablePresentation?.didDismiss(id: presentationID, reduceMotion: reduceMotion)
                }) {
                    ExpandMorphSurface(sourceFrame: sourceFrame, cornerRadius: Theme.cardRadius, closing: closing,
                                       reduceMotion: reduceMotion, onClosed: finishClosing) {
                        card(expand: {})
                    } expanded: {
                        expandedChart
                    }
                }
        }
    }

    private func card(expand: @escaping () -> Void) -> some View {
        let hasTitle = !(block.title ?? "").isEmpty
        return VStack(spacing: 3) {
            if let title = block.title, hasTitle {
                HStack(spacing: 12) {
                    Text(title)
                        .font(Theme.cardTitle())
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ExpandButton(action: expand)
                }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .seamCard(.top)
            }

            VStack(alignment: .leading, spacing: 12) {
                if series.count > 1, block.kind != .pie {
                    legend(names: series.enumerated().map { $0.element.name ?? "Series \($0.offset + 1)" })
                }
                switch block.kind {
                case .pie: pieChart(expanded: false)
                default: xyViewport(expanded: false)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .seamCard(hasTitle ? .bottom : .solo)
            .overlay(alignment: .topTrailing) {
                if !hasTitle {
                    ExpandButton(action: expand)
                        .padding(8)
                }
            }
        }
    }

    private func presentExpandedChart() {
        guard blockInteraction.allowsActivation, !expanded else { return }
        sourceFrame = liveFrame.frame
        tablePresentation?.present(id: presentationID)
        closing = false
        withoutAnimation { expanded = true }
    }

    private func closeExpandedChart() {
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

    private var expandedChart: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                if let title = block.title, !title.isEmpty {
                    Text(title)
                        .font(Theme.sectionTitle())
                        .foregroundStyle(Theme.ink)
                }
                switch block.kind {
                case .pie:
                    pieChart(expanded: true)
                default:
                    readout
                    xyViewport(expanded: true)
                }
            }
            .padding(.horizontal, Theme.contentMargin)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .background(Theme.responsePaper.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button(action: closeExpandedChart) {
                    CloseGlyph(variant: .table)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .glassEffect(.regular.interactive(), in: .circle)
                        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close chart")
                Spacer()
                ShareLink(item: Self.shareTSV(for: block)) {
                    ChromeGlyph(symbol: .share, size: 22)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .blockActivationControl()
                .buttonStyle(.plain)
                .accessibilityLabel("Share chart")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 13)
            .background(Theme.responsePaper.ignoresSafeArea())
        }
    }

    static func shareTSV(for block: ChartBlock) -> String {
        var rows = [["Chart title", "Kind", "Unit", "Series index", "Series", "Point index", "Label", "Value"]]
        for (seriesIndex, series) in block.series.enumerated() {
            for (pointIndex, point) in series.points.enumerated() {
                rows.append([block.title ?? "", block.kind.rawValue, block.unit ?? "",
                             String(seriesIndex + 1), series.name ?? "", String(pointIndex + 1),
                             point.label, String(point.value)])
            }
        }
        return rows.map { $0.map(tsvField).joined(separator: "\t") }.joined(separator: "\n")
    }

    private static func tsvField(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\"" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func xyViewport(expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !expanded, let unit = block.unit, !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    xyChart(expanded: expanded)
                        .frame(width: max(geometry.size.width, plotWidth(expanded: expanded)))
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .clipped()
            }
            .frame(height: expanded ? 420 : 220)
        }
    }

    private func plotWidth(expanded: Bool) -> CGFloat {
        let seriesCount = min(max(series.count, 1), 8)
        if expanded {
            let perLabel: CGFloat = block.kind == .bar ? CGFloat(seriesCount) * 20 : 18
            return min(CGFloat(xLabels.count) * perLabel, 14_000)
        }
        let longestLabel = xLabels.map(\.count).max() ?? 1
        let labelWidth = CGFloat(longestLabel) * 8 + 24
        let spacing = block.kind == .bar
            ? max(52 + CGFloat(seriesCount - 1) * 16, labelWidth)
            : max(52, labelWidth)
        return min(CGFloat(max(xLabels.count, 1)) * spacing + 36, 8_000)
    }

    @ViewBuilder
    private func xyChart(expanded: Bool) -> some View {
        let annotate = block.kind == .bar && series.count == 1 && series[0].points.count <= 6
        let showPoints = xLabels.count <= 16
        let domain = yDomain
        let baseline = min(max(0, domain.lowerBound), domain.upperBound)
        let chart = Chart {
            if yDomain.lowerBound < 0 && yDomain.upperBound > 0 {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Theme.inkSecondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            if expanded, let selectedLabel {
                RuleMark(x: .value("Selected", selectedLabel))
                    .foregroundStyle(Theme.ink.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(Array(series.enumerated()), id: \.offset) { sIndex, s in
                let name = s.name ?? "Series \(sIndex + 1)"
                ForEach(Array(s.points.enumerated()), id: \.offset) { _, point in
                    let y = baseline + (point.value - baseline) * progress
                    switch block.kind {
                    case .line:
                        LineMark(x: .value("Label", point.label), y: .value("Value", y))
                            .foregroundStyle(by: .value("Series", name))
                            .lineStyle(StrokeStyle(lineWidth: expanded ? 3 : 2.5, lineCap: .round))
                            .interpolationMethod(.monotone)
                        if showPoints {
                            PointMark(x: .value("Label", point.label), y: .value("Value", y))
                                .foregroundStyle(by: .value("Series", name))
                                .symbolSize(expanded ? 42 : 28)
                        }
                    case .area:
                        AreaMark(x: .value("Label", point.label), y: .value("Value", y))
                            .foregroundStyle(by: .value("Series", name))
                            .opacity(0.25)
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Label", point.label), y: .value("Value", y))
                            .foregroundStyle(by: .value("Series", name))
                            .lineStyle(StrokeStyle(lineWidth: expanded ? 3 : 2.5, lineCap: .round))
                            .interpolationMethod(.monotone)
                    default:
                        BarMark(x: .value("Label", point.label), y: .value("Value", y), width: .ratio(0.55))
                            .foregroundStyle(by: .value("Series", name))
                            .position(by: .value("Series", name))
                            .cornerRadius(5)
                            .annotation(position: .top, spacing: 4) {
                                if annotate {
                                    Text(format(point.value))
                                        .font(.system(size: 12, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.inkSecondary)
                                        .opacity(progress)
                                }
                            }
                    }
                }
            }
        }
        .chartForegroundStyleScale(range: chartPalette)
        .chartLegend(.hidden)
        .chartXScale(domain: xLabels)
        .chartYScale(domain: yDomain)
        .chartPlotStyle { plot in
            plot.clipped()
        }
        .chartXAxis {
            AxisMarks(values: xLabels) { value in
                AxisValueLabel(collisionResolution: expanded ? .greedy : .automatic) {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.system(size: expanded ? 13 : 12))
                            .lineLimit(1)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.inkSecondary.opacity(0.18))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(formatNumber(v))
                            .font(.system(size: expanded ? 13 : 12))
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)

        if expanded {
            chart.chartXSelection(value: Binding(
                get: { selectedLabel },
                set: { value in
                    blockInteraction.performActivation { selectedLabel = value }
                }))
        } else {
            chart
        }
    }

    @ViewBuilder
    private var readout: some View {
        if let label = selectedLabel ?? xLabels.last {
            let values = series.enumerated().compactMap { index, item in
                item.points.first(where: { $0.label == label }).map { (index, item.name, $0.value) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                if series.count == 1, let value = values.first?.2 {
                    Text(format(value))
                        .font(.system(size: 34, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                } else {
                    ForEach(values, id: \.0) { index, name, value in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(chartPalette[index % chartPalette.count])
                                .frame(width: 8, height: 8)
                            Text(name ?? "Series \(index + 1)")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.inkSecondary)
                            Spacer(minLength: 12)
                            Text(format(value))
                                .font(.system(size: 17, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = series.flatMap(\.points).map(\.value)
        let hi = values.max() ?? 1
        let lo = values.min() ?? 0
        if block.kind == .line {
            let magnitude = max(abs(hi), abs(lo))
            let span = max(hi - lo, magnitude * 0.05, 1)
            let padding = span * 0.18
            return (lo - padding)...(hi + padding)
        }
        let top = hi > 0 ? hi * 1.12 : 0
        let bottom = lo < 0 ? lo * 1.12 : 0
        return bottom...(top > bottom ? top : bottom + 1)
    }

    private func pieChart(expanded: Bool) -> some View {
        let points = series[0].points
        let total = points.map(\.value).reduce(0, +)
        return VStack(spacing: 16) {
            Chart(Array(points.enumerated()), id: \.offset) { index, point in
                SectorMark(
                    angle: .value("Value", point.value),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5)
                    .cornerRadius(4)
                    .foregroundStyle(chartPalette[index % chartPalette.count])
            }
            .frame(height: expanded ? 320 : 190)
            .overlay {
                if expanded, total > 0 {
                    VStack(spacing: 2) {
                        Text(format(total))
                            .font(.system(size: 28, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                        Text("Total")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .scaleEffect(0.85 + 0.15 * progress)
            .opacity(progress)

            VStack(spacing: 8) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(chartPalette[index % chartPalette.count])
                            .frame(width: 9, height: 9)
                        Text(point.label)
                            .font(.system(size: expanded ? 17 : 15))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(expanded ? nil : 1)
                            .fixedSize(horizontal: false, vertical: expanded)
                        Spacer(minLength: 8)
                        Text(format(point.value))
                            .font(.system(size: expanded ? 17 : 15, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                        if total > 0 {
                            Text((point.value / total).formatted(.percent.precision(.fractionLength(0))))
                                .font(.system(size: 13))
                                .monospacedDigit()
                                .foregroundStyle(Theme.inkSecondary)
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private func legend(names: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(chartPalette[index % chartPalette.count])
                            .frame(width: 8, height: 8)
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
    }

    private var chartPalette: [Color] {
        let chosen = (block.colors ?? []).compactMap(Theme.color(hex:))
        guard chosen.isEmpty else { return chosen }
        guard colorScheme == .dark else { return Theme.chartPalette }
        var defaults = Theme.chartPalette
        defaults[3] = Color(.sRGB, red: 125.0 / 255.0, green: 125.0 / 255.0, blue: 133.0 / 255.0, opacity: 1)
        return defaults
    }

    private func formatNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...6)))
    }

    private func format(_ value: Double) -> String {
        let number = formatNumber(value)
        guard let unit = block.unit, !unit.isEmpty else { return number }
        if ["$", "€", "£", "¥"].contains(unit) {
            return value < 0 ? "-\(unit)\(number.replacingOccurrences(of: "-", with: ""))" : unit + number
        }
        return unit.count == 1 || unit.hasPrefix("°") ? number + unit : "\(number) \(unit)"
    }
}
