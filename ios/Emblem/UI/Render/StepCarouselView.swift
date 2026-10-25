import SwiftUI
import EmblemCore

struct CenterSnapBehavior: ScrollTargetBehavior {
    let snapOffsets: [CGFloat]
    let leadingInset: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard !snapOffsets.isEmpty else { return }
        let originalOffset = context.originalTarget.rect.origin.x + leadingInset
        let proposedOffset = target.rect.origin.x + leadingInset
        let originalIndex = nearestIndex(to: originalOffset)
        let proposedIndex = nearestIndex(to: proposedOffset)
        let destinationIndex = min(
            max(proposedIndex, originalIndex - 1),
            originalIndex + 1)
        target.rect.origin.x = snapOffsets[destinationIndex] - leadingInset
    }

    private func nearestIndex(to offset: CGFloat) -> Int {
        snapOffsets.indices.min {
            abs(snapOffsets[$0] - offset) < abs(snapOffsets[$1] - offset)
        } ?? 0
    }
}

struct StepCarouselSectionView: View {
    let header: SectionHeader?
    let block: StepCarousel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let header {
                SectionHeaderView(block: header)
            }
            StepCarouselView(block: block)
        }
        .padding(.vertical, 24)
    }
}

struct StepCarouselView: View {
    let block: StepCarousel
    @Environment(\.renderedPage) private var renderedPage

    @State private var progress: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var hasStepPhotos: Bool { block.steps.contains { $0.image != nil } }

    private var isPhotoRail: Bool {
        !block.steps.isEmpty && block.steps.allSatisfy { $0.image?.kind == .photo }
    }
    private var cardWidth: CGFloat { Theme.carouselCardWidth(in: containerWidth) }
    private var minimumCardHeight: CGFloat { (isPhotoRail ? 309 + 1.0 / 3.0 : 284) * cardWidth / 288 }
    private var cardGap: CGFloat { isPhotoRail ? 0 : 12 }
    private var cardMargin: CGFloat { Theme.contentMargin }
    private var cardPitch: CGFloat { cardWidth + cardGap }

    private var clamped: CGFloat {
        min(max(progress, 0), CGFloat(block.steps.count - 1))
    }
    private var nearestIndex: Int { Int(clamped.rounded()) }

    private var snapOffsets: [CGFloat] {
        let count = block.steps.count
        guard containerWidth > 0, count > 0 else { return [0] }
        let centerBase = cardMargin + cardWidth / 2 - containerWidth / 2
        let contentSpan = CGFloat(count - 1) * cardPitch + cardWidth + cardMargin * 2
        let maxOffset = max(0, contentSpan - containerWidth)
        return (0..<count).map {
            min(max(centerBase + CGFloat($0) * cardPitch, 0), maxOffset)
        }
    }

    private func progressValue(for offset: CGFloat) -> CGFloat {
        let offsets = snapOffsets
        guard offsets.count > 1 else { return 0 }
        if offset <= offsets[0] { return 0 }
        for index in 0..<(offsets.count - 1) {
            let a = offsets[index], b = offsets[index + 1]
            if offset < b {
                return CGFloat(index) + (b > a ? (offset - a) / (b - a) : 0)
            }
        }
        return CGFloat(offsets.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isPhotoRail ? 71.0 / 3.0 : 18) {
            progressRail
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: cardGap) {
                    stepCards
                }
                .padding(.horizontal, cardMargin)
            }
            .scrollTargetBehavior(
                CenterSnapBehavior(snapOffsets: snapOffsets, leadingInset: 0))
            .scrollBounceBehavior(.basedOnSize)
            .scrollClipDisabled()
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.x + geo.contentInsets.leading
            } action: { _, offset in
                progress = progressValue(for: offset)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                containerWidth = $0
            }
        }
        .sensoryFeedback(EmblemHaptic.select, trigger: indicatorHapticState) { old, new in
            abs(new - old) == 1 && max(new, old) % 2 == 1
        }
    }

    private func weight(_ index: Int) -> CGFloat {
        max(0, 1 - abs(clamped - CGFloat(index)))
    }

    private var stepCards: some View {
        ForEach(Array(block.steps.enumerated()), id: \.offset) { index, step in
            let emphasis = weight(index)
            Group {
                if isPhotoRail {
                    photoStepCard(step, foregroundEmphasis: 0.4 + 0.6 * emphasis)
                } else {
                    legacyStepCard(step)
                }
            }
            .shadow(
                color: .black.opacity(0.03 + 0.05 * emphasis),
                radius: 5 + 7 * emphasis,
                y: 2 + 4 * emphasis)
            .opacity(isPhotoRail ? 1 : 0.42 + 0.58 * emphasis)
            .scaleEffect(isPhotoRail ? 0.92 + 0.08 * emphasis : 1, anchor: .center)
            .zIndex(emphasis)
        }
    }

    private func photoStepCard(_ step: StepCarousel.Step, foregroundEmphasis: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            if let photo = step.image {
                RemoteImage(
                    spec: photo,
                    url: step.imageURL.flatMap(URL.init(string:)),
                    maxPixelSize: 600,
                    showsSkeleton: true)
                    .frame(width: cardWidth, height: cardWidth * 2 / 3)
                    .clipped()
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(step.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink.opacity(foregroundEmphasis))
                    .fixedSize(horizontal: false, vertical: true)
                if let meta = step.meta {
                    Text(meta)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink.opacity(foregroundEmphasis))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                Text(step.body)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSecondary.opacity(foregroundEmphasis))
                    .lineSpacing(max(0, 18 - UIFont.systemFont(ofSize: 14).lineHeight))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20 / 3)
            }
            .padding(.horizontal, 16)
            .padding(.top, 17)
            .padding(.bottom, 16)
        }
        .frame(width: cardWidth)
        .frame(minHeight: minimumCardHeight, alignment: .topLeading)
        .background(Theme.surface, in: shape)
        .clipShape(shape)
    }

    private func legacyStepCard(_ step: StepCarousel.Step) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            if hasStepPhotos {
                stepPhotoSlot(step)
            } else if let generated = step.icon?.image, generated.kind == .generated {
                stepImageSlot(generated)
            } else if renderedPage?.isPreviewing == true || renderedPage?.isStreamingDraft(block.id) == true {
                stepImageSlot(nil)
            } else if let icon = stepCardIcon(step) {
                IconView(icon: icon, size: 72)
                .frame(width: 96, height: 96)
                .padding(.bottom, 16)
            }
            Text(step.title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let meta = step.meta {
                Text(meta)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            Text(step.body)
                .font(.system(size: 16))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(hasStepPhotos ? 12 : 20)
        .frame(width: cardWidth)
        .frame(minHeight: minimumCardHeight, alignment: .topLeading)
        .background(Theme.surface, in: shape)
    }

    private func stepPhotoSlot(_ step: StepCarousel.Step) -> some View {
        Group {
            if let photo = step.image {
                RemoteImage(
                    spec: photo,
                    url: step.imageURL.flatMap(URL.init(string:)),
                    maxPixelSize: 600,
                    showsSkeleton: true)
            } else if let generated = step.icon?.image, generated.kind == .generated {
                RemoteImage(spec: generated, maxPixelSize: 600, showsSkeleton: true)
            } else {
                ZStack {
                    Theme.card
                    if let icon = stepCardIcon(step) {
                        IconView(icon: icon, size: 72)
                    }
                }
            }
        }
        .frame(width: cardWidth - 24, height: 148)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 14)
        .accessibilityHidden(true)
    }

    private func stepImageSlot(_ spec: ImageSpec?) -> some View {
        Group {
            if let spec {
                RemoteImage(spec: spec, maxPixelSize: 200)
            } else {
                ShimmerTile()
            }
        }
        .frame(width: 93.6, height: 93.6)
        .clipShape(RoundedRectangle(cornerRadius: 20.16, style: .continuous))
        .frame(width: 96, height: 96)
        .padding(.bottom, 16)
        .accessibilityHidden(true)
    }

    private func stepCardIcon(_ step: StepCarousel.Step) -> Icon? {
        guard step.icon != nil || step.sfSymbol != nil else { return nil }
        return Icon(
            emoji: step.icon?.emoji,
            sfSymbol: step.icon?.sfSymbol ?? step.sfSymbol,
            image: step.icon?.image)
    }

    private let railLineWidth: CGFloat = 1.5

    private struct RailMetrics {
        struct Column {
            let origin: CGFloat
            let width: CGFloat
            var center: CGFloat { origin + width / 2 }
        }

        let columns: [Column]
        let totalWidth: CGFloat
    }

    private func makeRailMetrics() -> RailMetrics {
        let font = isPhotoRail
            ? UIFont.systemFont(ofSize: 14, weight: .semibold)
            : UIFont.systemFont(ofSize: 15, weight: .medium)
        var leading = Theme.contentMargin
        let columns = block.steps.enumerated().map { index, step in
            let width = max(24, ((step.railLabel ?? "Step \(index + 1)") as NSString)
                .size(withAttributes: [.font: font]).width)
            defer { leading += width + 56.0 + 1.0 / 3.0 }
            return RailMetrics.Column(origin: leading, width: width)
        }
        let totalWidth = columns.last.map { $0.origin + $0.width + Theme.contentMargin } ?? Theme.contentMargin * 2
        return RailMetrics(columns: columns, totalWidth: totalWidth)
    }

    private var railMidlineY: CGFloat {
        17 + (isPhotoRail ? 38.0 / 3.0 : 8) + 12
    }

    private func railShift(for metrics: RailMetrics) -> CGFloat {
        let overflow = metrics.totalWidth - containerWidth
        guard overflow > 0 else { return 0 }
        let ideal = columnCenterX(clamped, metrics: metrics) - containerWidth / 2
        return min(max(ideal, 0), overflow)
    }

    private var progressRail: some View {
        let metrics = makeRailMetrics()
        return Color.clear
            .frame(height: isPhotoRail ? 161.0 / 3.0 : 49)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                railStrip(metrics: metrics).offset(x: -railShift(for: metrics))
            }
    }

    private func railStrip(metrics: RailMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<max(block.steps.count - 1, 0), id: \.self) { index in
                connector(after: index, metrics: metrics)
            }
            travelingIndicator(metrics: metrics)
            ForEach(Array(block.steps.enumerated()), id: \.offset) { index, step in
                railColumn(index, step, metrics: metrics)
            }
        }
        .frame(width: metrics.totalWidth, height: isPhotoRail ? 161.0 / 3.0 : 49, alignment: .topLeading)
    }

    private func columnCenterX(_ position: CGFloat, metrics: RailMetrics) -> CGFloat {
        let columns = metrics.columns
        guard !columns.isEmpty else { return Theme.contentMargin }
        let position = min(max(position, 0), CGFloat(columns.count - 1))
        let lower = Int(position)
        let upper = min(lower + 1, columns.count - 1)
        return columns[lower].center
            + (columns[upper].center - columns[lower].center) * (position - CGFloat(lower))
    }

    private func railColumn(_ index: Int, _ step: StepCarousel.Step, metrics: RailMetrics) -> some View {
        let w = weight(index)
        let column = metrics.columns[index]
        return VStack(spacing: isPhotoRail ? 38.0 / 3.0 : 8) {
            Text(step.railLabel ?? "Step \(index + 1)")
                .font(.system(size: isPhotoRail ? 14 : 15, weight: isPhotoRail ? .semibold : .medium))
                .foregroundStyle(Theme.ink.opacity(0.22 + 0.78 * w))
                .lineLimit(1)
                .fixedSize()
            GlyphImage(symbol: validatedSymbol(step), size: 24, weight: .regular)
                .foregroundStyle(Theme.ink.opacity(0.22 + 0.78 * w))
        }
        .frame(width: column.width)
        .offset(x: column.origin)
    }

    private func connector(after index: Int, metrics: RailMetrics) -> some View {
        let railConnectorInset: CGFloat = isPhotoRail ? 50.0 / 3.0 : 22
        let railLineWidth: CGFloat = isPhotoRail ? 3 : self.railLineWidth
        let start = columnCenterX(CGFloat(index), metrics: metrics) + railConnectorInset
        let end = columnCenterX(CGFloat(index + 1), metrics: metrics) - railConnectorInset
        return Rectangle()
            .fill(Theme.inkSecondary.opacity(0.22))
            .frame(width: max(end - start, 0), height: railLineWidth)
            .offset(x: start, y: railMidlineY - railLineWidth / 2)
    }

    @ViewBuilder
    private func travelingIndicator(metrics: RailMetrics) -> some View {
        if block.steps.count > 1 {
            let railConnectorInset: CGFloat = isPhotoRail ? 50.0 / 3.0 : 22
            let railLineWidth: CGFloat = isPhotoRail ? 3 : self.railLineWidth
            let base = min(Int(clamped), block.steps.count - 2)
            let frac = clamped - CGFloat(base)
            let start = columnCenterX(CGFloat(base), metrics: metrics) + railConnectorInset
            let end = columnCenterX(CGFloat(base + 1), metrics: metrics) - railConnectorInset
            let lineLength = max(end - start, 0)
            let segment = lineLength * 0.9
            Color.clear
                .frame(width: lineLength, height: railLineWidth)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.ink)
                        .frame(width: segment, height: railLineWidth)
                        .offset(x: -segment + frac * (lineLength + segment))
                }
                .clipped()
                .offset(x: start, y: railMidlineY - railLineWidth / 2)
        }
    }

    private var indicatorHapticState: Int {
        guard block.steps.count > 1 else { return 0 }
        let base = min(Int(clamped), block.steps.count - 2)
        let frac = clamped - CGFloat(base)
        return base * 2 + (frac >= 1.0 / 1.9 ? 1 : 0)
    }

    private func validatedSymbol(_ step: StepCarousel.Step) -> String {
        if let symbol = step.sfSymbol, Hugeicons.isRenderable(symbol) {
            return symbol
        }
        if let symbol = step.icon?.sfSymbol, Hugeicons.isRenderable(symbol) {
            return symbol
        }
        return "circle.dashed"
    }
}
