import SwiftUI
import EmblemCore

struct ExpandedComparison: View {
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(\.displayScale) private var displayScale
    let presentation: ComparisonPresentation
    let dismiss: () -> Void
    @State private var fallbackSelected = 0
    @State private var verticalOffset: CGFloat = 0
    @State private var settledColumnOffset: CGFloat = 0
    @State private var outgoing: Int?
    @State private var swapProgress: CGFloat = 1
    @State private var swapGeneration = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding private var ownerSelected: Int
    let usesNavigationToolbar: Bool

    init(presentation: ComparisonPresentation, dismiss: @escaping () -> Void,
         usesNavigationToolbar: Bool = false) {
        self.presentation = presentation
        self.dismiss = dismiss
        self.usesNavigationToolbar = usesNavigationToolbar
        _ownerSelected = presentation.selectedChallenger ?? .constant(0)
    }

    private var isOneAgainstMany: Bool {
        presentation.selectedChallenger != nil && presentation.entities.count > 2
    }
    private var isPeerSet: Bool { !isOneAgainstMany && presentation.entities.count > 2 }
    private var selected: Binding<Int> {
        presentation.selectedChallenger == nil ? $fallbackSelected : $ownerSelected
    }
    private var columns: [Int] {
        guard isOneAgainstMany else { return Array(presentation.entities.indices) }
        let index = min(max(0, ownerSelected), presentation.entities.count - 2)
        return [0, index + 1]
    }
    private var hasArtwork: Bool {
        columns.contains { presentation.entities[$0].photographicArtwork != nil || presentation.entities[$0].photographicArtworkURL != nil }
    }
    private var artworkHeight: CGFloat { hasArtwork ? 136 : 0 }
    private var usesPrimaryEnvelope: Bool { columns.count == 2 }
    private var showsLabels: Bool { false }

    private func columnWidth(for width: CGFloat) -> CGFloat {
        if isPeerSet { return (width * CompareMetrics.peerColumnFraction).rounded() }
        return max(0, width - CompareMetrics.expandedInset * 2) / CGFloat(max(1, columns.count))
    }

    private func contentWidth(for width: CGFloat, columnWidth: CGFloat) -> CGFloat {
        guard isPeerSet else { return width }
        return max(width, CompareMetrics.expandedInset * 2 + CGFloat(columns.count) * columnWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !usesNavigationToolbar {
                HStack {
                    closeControl
                    Spacer()
                    shareControl
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            GeometryReader { geometry in
                let columnWidth = columnWidth(for: geometry.size.width)
                let width = contentWidth(for: geometry.size.width, columnWidth: columnWidth)
                if isPeerSet {
                    ScrollView(.horizontal, showsIndicators: false) {
                        comparisonPage(columnWidth: columnWidth)
                            .frame(width: width, height: geometry.size.height)
                            .background(EdgeBounceLock())
                    }
                    .scrollTargetBehavior(ColumnSnap(pitch: columnWidth, settledOffset: settledColumnOffset))
                    .onScrollPhaseChange { _, phase, context in
                        if phase == .idle { settledColumnOffset = context.geometry.contentOffset.x }
                    }
                    .accessibilityIdentifier("expanded-comparison-columns")
                } else {
                    comparisonPage(columnWidth: columnWidth)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if isOneAgainstMany {
                ComparisonSwapChips(entities: Array(presentation.entities.dropFirst()), selected: selected)
                    .padding(.top, 36)
                    .padding(.bottom, usesNavigationToolbar ? 73 : 21)
                    .background {
                        ZStack {
                            VariableBlurView(maxBlurRadius: 6, direction: .blurredBottomClearTop, startOffset: 0.3)
                            LinearGradient(stops: [.init(color: Theme.responsePaper.opacity(0), location: 0.45),
                                                   .init(color: Theme.responsePaper.opacity(0.6), location: 0.8),
                                                   .init(color: Theme.responsePaper.opacity(0.75), location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                    }
            }
        }
        .padding(.top, usesNavigationToolbar ? 2 : 0)
        .background(NavigationHeaderBackdrop(visible: usesNavigationToolbar, deep: false))
        .toolbar { comparisonToolbar }
        .background(ZStack { Theme.responsePaper; Theme.ink.opacity(0.018) }.ignoresSafeArea())
        .accessibilityIdentifier("expanded-comparison")
        .onChange(of: ownerSelected) { old, _ in
            guard !reduceMotion else { return }
            swapGeneration += 1
            let generation = swapGeneration
            withTransaction(Transaction(animation: nil)) {
                outgoing = old
                swapProgress = 0
            }
            withAnimation(.comparisonSwap(delay: CompareMetrics.expandedSwapDelay)) {
                swapProgress = 1
            } completion: {
                guard generation == swapGeneration else { return }
                outgoing = nil
            }
        }
    }

    private func comparisonPage(columnWidth: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: artworkHeight)
                headerStrip(columnWidth: columnWidth).hidden().accessibilityHidden(true)
                groupStack(columns: columns, columnWidth: columnWidth, outgoingCopy: false)
                    .overlay(alignment: .topLeading) {
                        if let outgoing, isOneAgainstMany {
                            groupStack(columns: [0, min(outgoing, presentation.entities.count - 2) + 1],
                                       columnWidth: columnWidth, outgoingCopy: true)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                .padding(.horizontal, CompareMetrics.expandedInset)
                .padding(.top, isPeerSet ? 36 : 24)
                .padding(.bottom, isOneAgainstMany ? 196 : 112)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.responsePaper.ignoresSafeArea(edges: .bottom))
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, offset in verticalOffset = offset }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                if hasArtwork {
                    artworkStrip(columnWidth: columnWidth, height: max(0, 386 / 3 - verticalOffset))
                        .frame(height: max(0, artworkHeight - verticalOffset), alignment: .top)
                        .clipped()
                        .opacity(min(1, max(0, artworkHeight - verticalOffset) / 44))
                }
                headerStrip(columnWidth: columnWidth)
                    .overlay {
                        if usesPrimaryEnvelope && hasArtwork {
                            Rectangle().fill(Theme.ink.opacity(0.1)).frame(width: 1, height: 53 / 3)
                                .padding(.top, 25 / 3).padding(.bottom, 38 / 3)
                                .opacity(1 - min(1, max(0, artworkHeight - verticalOffset) / 44))
                        }
                    }
            }
            .background {
                ZStack {
                    VariableBlurView(maxBlurRadius: 20, startOffset: -0.2)
                    Theme.responsePaper.opacity(0.92)
                    Theme.ink.opacity(0.018)
                }
                .accessibilityHidden(true)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    Rectangle().fill(Theme.ink.opacity(0.08)).frame(height: 1)
                    Rectangle().fill(Theme.ink.opacity(0.24)).frame(height: 1 / max(1, displayScale))
                }
            }
            .background(alignment: .bottom) {
                LinearGradient(stops: [.init(color: .black.opacity(0.09), location: 0),
                                       .init(color: .black.opacity(0.045), location: 0.35),
                                       .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 42)
                    .offset(y: 42)
            }
            .allowsHitTesting(false)
        }
        .clipped()
    }

    private var closeControl: some View {
        Button(action: dismiss) { chromeIcon("xmark") }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Close comparison")
    }

    private var shareControl: some View {
        ShareLink(item: presentation.shareText) { chromeIcon("square.and.arrow.up") }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .blockActivationControl()
            .accessibilityLabel("Share comparison")
    }

    @ToolbarContentBuilder
    private var comparisonToolbar: some ToolbarContent {
        if usesNavigationToolbar {
            ToolbarItem(placement: .topBarLeading) {
                closeControl
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                shareControl
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private var incomingVisibility: CGFloat { outgoing == nil ? 1 : swapProgress }

    @ViewBuilder
    private func swapSlot<Content: View>(_ slot: Int, _ column: Int,
                                         @ViewBuilder content: (Int) -> Content) -> some View {
        if slot > 0 && isOneAgainstMany {
            content(column)
                .modifier(SwapFade(visibility: incomingVisibility))
                .overlay {
                    if let outgoing {
                        content(min(outgoing, presentation.entities.count - 2) + 1)
                            .modifier(SwapFade(visibility: 1 - swapProgress))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        } else {
            content(column)
        }
    }

    private func groupStack(columns: [Int], columnWidth: CGFloat, outgoingCopy: Bool) -> some View {
        VStack(alignment: .leading, spacing: usesPrimaryEnvelope ? 116 / 3 : isPeerSet ? 58 : 46) {
            ForEach(Array(presentation.groups.enumerated()), id: \.offset) { _, group in
                groupView(group, columns: columns, columnWidth: columnWidth, outgoingCopy: outgoingCopy)
            }
        }
    }

    private func headerColumnWidth(_ columnWidth: CGFloat) -> CGFloat {
        isPeerSet ? columnWidth : max(0, columnWidth - CompareMetrics.columnGap / 2)
    }

    private func artworkStrip(columnWidth: CGFloat, height: CGFloat) -> some View {
        HStack(alignment: .top, spacing: isPeerSet ? 0 : CompareMetrics.columnGap) {
            ForEach(Array(columns.enumerated()), id: \.offset) { slot, column in
                swapSlot(slot, column) { column in
                    let entity = presentation.entities[column]
                    CompareImage(image: entity.photographicArtwork, imageURL: entity.photographicArtworkURL, icon: entity.icon,
                                 maxPixelSize: 600, iconSize: 40, showsSkeleton: true)
                        .frame(width: max(0, columnWidth - (isPeerSet ? CompareMetrics.columnGap : 32)), height: height)
                        .clipShape(RoundedRectangle(cornerRadius: CompareMetrics.imageRadius, style: .continuous))
                        .frame(width: headerColumnWidth(columnWidth), alignment: isPeerSet ? .leading : .center)
                }
            }
        }
        .padding(.horizontal, CompareMetrics.expandedInset)
        .padding(.top, 22 / 3)
    }

    private func headerStrip(columnWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: isPeerSet ? 0 : CompareMetrics.columnGap) {
            ForEach(Array(columns.enumerated()), id: \.offset) { slot, column in
                swapSlot(slot, column) { column in
                    EntityHeader(entity: presentation.entities[column], expanded: true,
                                 showsImage: false, showsIcon: !hasArtwork, leading: isPeerSet)
                        .padding(.leading, isPeerSet ? 4 : 0)
                        .padding(.trailing, isPeerSet ? CompareMetrics.columnGap : 0)
                        .frame(width: headerColumnWidth(columnWidth))
                }
            }
        }
        .padding(.horizontal, CompareMetrics.expandedInset)
        .padding(.top, 25 / 3)
        .padding(.bottom, 38 / 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func groupView(_ group: CompareSection, columns: [Int], columnWidth: CGFloat,
                           outgoingCopy: Bool) -> some View {
        let rowsLayout = usesPrimaryEnvelope
            ? AnyLayout(ComparisonRowsLayout(hasSecondaryContent: group.rows.map { row in
                (showsLabels && row.label?.isEmpty == false) || row.values.contains { $0.chipLabel != nil }
            }))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: isPeerSet ? 38 / 3 : CompareMetrics.rowSpacing))
        return VStack(alignment: .leading, spacing: usesPrimaryEnvelope ? 76 / 3 : isPeerSet ? 16 : 94 / 3) {
            ComparisonGroupHeading(title: group.title, icon: group.icon, centered: !isPeerSet && columns.count == 2)
                .padding(.leading, isPeerSet ? 4 : 0)
                .frame(width: isPeerSet ? columnWidth * 2 - CompareMetrics.columnGap : nil, alignment: .leading)
                .visualEffect { [isPeerSet] content, proxy in
                    content.offset(x: isPeerSet ? CompareMetrics.expandedInset - proxy.frame(in: .scrollView(axis: .horizontal)).minX : 0)
                }
                .padding(.bottom, isPeerSet ? 16 : 0)
                .opacity(outgoingCopy ? 0 : 1)
            rowsLayout {
                ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 6) {
                        if showsLabels, let label = row.label, !label.isEmpty {
                            Text(label).font(.caption.weight(.medium))
                                .foregroundStyle(Theme.inkSecondary)
                                .accessibilityAddTraits(.isHeader)
                        }
                        HStack(alignment: .comparePrimaryCenter, spacing: 0) {
                            ForEach(Array(columns.enumerated()), id: \.offset) { slot, index in
                                let entity = presentation.entities[index]
                                let cell = row.values.indices.contains(index) ? row.values[index] : nil
                                let hasAnnotationRow = columns.contains { row.values.indices.contains($0) && row.values[$0].chipLabel != nil }
                                CompareValueView(cell: cell, centered: !isPeerSet, expanded: true,
                                                 usesPrimaryEnvelope: usesPrimaryEnvelope,
                                                 hasAnnotationRow: hasAnnotationRow)
                                    .padding(.leading, isPeerSet ? 4 : 0)
                                    .padding(.trailing, isPeerSet ? CompareMetrics.columnGap + 4 : 0)
                                    .padding(.horizontal, isOneAgainstMany ? 8 : columns.count == 2 ? 4 : 0)
                                    .frame(width: columnWidth, alignment: isPeerSet ? .leading : .center)
                                    .modifier(SwapFade(visibility: cellVisibility(slot: slot, outgoingCopy: outgoingCopy)))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(compareCellAccessibility(
                                    entity: entity.name, axis: row.label ?? group.title, cell: cell))
                            }
                        }
                    }
                }
            }
            .overlay {
                GeometryReader { geometry in
                    Path { path in
                        for column in 1..<max(1, columns.count) {
                            let rawX = CGFloat(column) * columnWidth - (isPeerSet ? CompareMetrics.columnGap / 2 : 0)
                            let scale = max(1, displayScale)
                            let halfPixel: CGFloat = Int(scale.rounded()) % 2 == 1 ? 0.5 : 0
                            let x = usesPrimaryEnvelope ? ((rawX * scale - halfPixel).rounded() + halfPixel) / scale : rawX
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                        }
                    }
                    .stroke(Theme.ink.opacity(usesPrimaryEnvelope ? 0.08 : 0.14), lineWidth: usesPrimaryEnvelope ? 1 : 0.5)
                }
                .opacity(outgoingCopy ? 0 : 1)
                .allowsHitTesting(false)
            }
        }
    }

    private func cellVisibility(slot: Int, outgoingCopy: Bool) -> CGFloat {
        if outgoingCopy { return slot == 0 ? 0 : 1 - swapProgress }
        return slot > 0 && isOneAgainstMany ? incomingVisibility : 1
    }

    private func chromeIcon(_ symbol: String) -> some View {
        Group {
            if symbol == "square.and.arrow.up" {
                ChromeGlyph(symbol: .share)
            } else if symbol == "xmark" {
                CloseGlyph()
            } else {
                Image(systemName: symbol).font(.system(size: 17))
            }
        }
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}

private struct ColumnSnap: ScrollTargetBehavior {
    let pitch: CGFloat
    let settledOffset: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard pitch > 0 else { return }
        let maxPage = ((context.contentSize.width - context.containerSize.width) / pitch).rounded(.down)
        let start = (settledOffset / pitch).rounded()
        var page = (target.rect.minX / pitch).rounded()
        if page == start, abs(context.velocity.dx) > 0.2 {
            page += context.velocity.dx > 0 ? 1 : -1
        }
        page = min(max(page, start - 1), start + 1)
        target.rect.origin.x = min(max(0, page), max(0, maxPage)) * pitch
    }
}

private struct EdgeBounceLock: UIViewRepresentable {
    final class LockView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            lock()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            lock()
        }

        private func lock() {
            var view = superview
            while let current = view {
                if let scrollView = current as? UIScrollView {
                    scrollView.bounces = false
                    scrollView.alwaysBounceHorizontal = false
                    return
                }
                view = current.superview
            }
        }
    }

    func makeUIView(context: Context) -> LockView {
        let view = LockView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: LockView, context: Context) {}
}

private struct SwapFade: ViewModifier, Animatable {
    var visibility: CGFloat

    nonisolated var animatableData: CGFloat {
        get { visibility }
        set { visibility = newValue }
    }

    func body(content: Content) -> some View {
        return content
            .blur(radius: CompareMetrics.swapBlur * (1 - visibility))
            .opacity(visibility)
    }
}

private struct BlurFade: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .blur(radius: phase.isIdentity ? 0 : CompareMetrics.swapBlur)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

extension Animation {
    static func comparisonSwap(delay: TimeInterval) -> Animation {
        .timingCurve(0.42, 0, 0.58, 1, duration: CompareMetrics.swapDuration).delay(delay)
    }
}

extension AnyTransition {
    static var comparisonSwap: AnyTransition {
        AnyTransition(BlurFade()).animation(.comparisonSwap(delay: CompareMetrics.inlineSwapDelay))
    }
}
