import SwiftUI
import EmblemCore

struct BlockView: View {
    let block: Block

    var body: some View {
        switch block {
        case .runStamp(let b):
            RunStampView(block: b)
        case .quiz(let b):
            QuizView(block: b)
        case .flashcards(let b):
            FlashcardsView(block: b)
        case .chart(let b):
            ChartBlockView(block: b)
        case .diagram(let b):
            DiagramBlockView(block: b)
        case .whatIf(let b):
            WhatIfView(block: b)
        case .pageMeta, .unknown:
            EmptyView()
        case .text(let b): TextBlockView(block: b)
        case .writing(let b): WritingBlockView(block: b)
        case .hero(let b): HeroView(block: b)
        case .titleBlock(let b): TitleBlockView(block: b)
        case .sectionHeader(let b): SectionHeaderView(block: b)
        case .cardCarousel(let b): CardCarouselView(block: b)
        case .featureList(let b): FeatureListView(block: b)
        case .quote(let b): QuoteView(block: b)
        case .ratingRow(let b): RatingRowView(block: b)
        case .mediaRowList(let b): MediaRowListView(block: b)
        case .spotList(let b): SpotListView(block: b)
        case .factList(let b): FactListView(block: b)
        case .chipRow(let b): ChipRowView(block: b)
        case .statRow(let b): StatRowView(block: b)
        case .itemGrid(let b): ItemGridView(block: b)
        case .stepCarousel(let b): StepCarouselSectionView(header: nil, block: b)
        case .listBlock(let b): ListBlockView(block: b)
        case .comparisonTable(let b): ComparisonTableView(block: b)
        case .sideBySide(let b): SideBySideView(block: b)
        case .oneAgainstMany(let b): OneAgainstManyView(block: b)
        case .reviewSummary(let b): ReviewSummaryView(block: b)
        case .timeline(let b): TimelineView_(block: b)
        case .questionList(let b): QuestionListView(block: b)
        case .map(let b): MapBlockView(block: b)
        case .route(let b): RouteBlockView(block: b)
        case .weather(let b): WeatherView(block: b)
        case .photoGrid(let b): PhotoGridView(block: b)
        case .timeAsk(let b): TimeAskView(block: b)
        case .eventCard(let b): EventCardView(block: b)
        case .music(let b): MusicCardView(block: b)
        case .reminders(let b): RemindersCardView(block: b)
        case .contact(let b): ContactCardView(block: b)
        case .homeControl(let b): HomeControlCardView(block: b)
        }
    }
}

struct VoicePageIDKey: EnvironmentKey {
    static let defaultValue = ""
}

struct RenderedPageKey: EnvironmentKey {
    static let defaultValue: GeneratedPage? = nil
}

struct ExpansionNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var voicePageID: String {
        get { self[VoicePageIDKey.self] }
        set { self[VoicePageIDKey.self] = newValue }
    }

    var renderedPage: GeneratedPage? {
        get { self[RenderedPageKey.self] }
        set { self[RenderedPageKey.self] = newValue }
    }

    var expansionNamespace: Namespace.ID? {
        get { self[ExpansionNamespaceKey.self] }
        set { self[ExpansionNamespaceKey.self] = newValue }
    }
}

extension ResponseSurface {
    var color: Color {
        switch self {
        case .paper: Theme.responsePaper
        case .canvas: Theme.responseComparisonCanvas
        case .questions: InputPalette.canvas
        }
    }
}

extension ResponseSurfacePlan {
    var initialColor: Color {
        startsOnFooter ? Theme.responseCanvas : (initialSurface ?? .paper).color
    }
}

extension ResponseSurfacePlan.TerminalSurface {
    var color: Color {
        switch self {
        case .paper: Theme.responsePaper
        case .comparisonCanvas: Theme.responseComparisonCanvas
        case .followUpCanvas: Theme.responseCanvas
        case .questions: InputPalette.canvas
        }
    }
}

struct ResponseSurfaceBackground: View {
    let surface: ResponseSurface
    var showsPaperEdge = false
    var isFooter = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (isFooter ? Theme.responseCanvas : surface.color)
            .overlay(alignment: .top) {
                if showsPaperEdge {
                    LinearGradient(
                        colors: [.black.opacity(colorScheme == .dark ? 0.16 : 0.03), .clear],
                        startPoint: .top, endPoint: .bottom)
                        .frame(height: 24)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct PageBlockList: View {
    let blocks: [Block]
    @Environment(\.renderedPage) private var renderedPage
    var pageID: String = ""
    var invisibleBlockIDs: Set<String> = []
    var introArmed: Bool = false
    var revealStart: Date?

    var body: some View {
        let plan = ResponseSurfacePlan(
            blocks: blocks,
            isHome: renderedPage?.isHome ?? true,
            asksQuestions: renderedPage?.presentationMeta?.ask == true)
        Group {
            if plan.isEnabled {
                layeredContent(plan: plan)
            } else {
                legacyContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.voicePageID, pageID)
        .task(id: ImagePrefetchPlan.specs(in: blocks)) {
            await ImageLoader.shared.prefetch(
                ImagePrefetchPlan.specs(in: blocks),
                maxPixelSize: 700,
                limit: 10)
        }
    }

    private func layeredContent(plan: ResponseSurfacePlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(plan.rows) { row in
                layeredBlock(row: row)
                    .opacity(isInvisible(row: row) ? 0 : 1)
                    .padding(.top, layeredSpacing(row: row))
                    .padding(.bottom, paperBottomSpacing(row: row, plan: plan))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if let surface = row.surface {
                            ResponseSurfaceBackground(
                                surface: surface, showsPaperEdge: row.showsPaperEdge,
                                isFooter: row.isFooter)
                        }
                    }
                    .modifier(BlockIntro(
                        armed: introArmed, start: revealStart, index: row.sourceIndex))
                    .transition(.opacity)
                    .zIndex(tableElevation(row: row))
            }
        }
    }

    private func tableElevation(row: ResponseSurfacePlan.Row) -> Double {
        switch blocks[row.sourceIndex] {
        case .comparisonTable, .sideBySide, .oneAgainstMany, .map, .route, .flashcards:
            return Double(blocks.count - row.sourceIndex)
        default: return 0
        }
    }

    @ViewBuilder
    private func layeredBlock(row: ResponseSurfacePlan.Row) -> some View {
        if case .sectionHeader(let header) = blocks[row.sourceIndex],
           let index = row.groupedCarouselIndex,
           case .stepCarousel(let carousel) = blocks[index] {
            StepCarouselSectionView(header: header, block: carousel)
        } else {
            BlockView(block: blocks[row.sourceIndex])
        }
    }

    private func isInvisible(row: ResponseSurfacePlan.Row) -> Bool {
        invisibleBlockIDs.contains(blocks[row.sourceIndex].id) ||
            row.groupedCarouselIndex.map { invisibleBlockIDs.contains(blocks[$0].id) } == true
    }

    private func layeredSpacing(row: ResponseSurfacePlan.Row) -> CGFloat {
        guard let previousIndex = row.previousSourceIndex else { return 0 }
        let block = blocks[row.sourceIndex]
        if row.startsRun {
            if case .chipRow(let chips) = block, chips.role == .followUp { return 0 }
            if case .reviewSummary = blocks[previousIndex] { return 41 }
            if row.surface == .canvas, reviewFollows(row.sourceIndex) { return 33 }
            return 28
        }
        if row.surface == .canvas {
            switch (blocks[previousIndex], block) {
            case (.sectionHeader, .text) where comparisonFollows(row.sourceIndex): return 8
            case (.text, .sideBySide), (.text, .oneAgainstMany): return 16
            default: break
            }
        }
        return spacingAbove(block, previous: blocks[previousIndex], isResponse: true)
    }

    private func comparisonFollows(_ index: Int) -> Bool {
        for block in blocks.dropFirst(index + 1) {
            switch block {
            case .sideBySide, .oneAgainstMany, .stepCarousel: return true
            case .sectionHeader, .text, .pageMeta: continue
            default: return false
            }
        }
        return false
    }

    private func reviewFollows(_ index: Int) -> Bool {
        for block in blocks.dropFirst(index + 1) {
            switch block {
            case .reviewSummary: return true
            case .sectionHeader, .text, .pageMeta: continue
            default: return false
            }
        }
        return false
    }

    private func paperBottomSpacing(row: ResponseSurfacePlan.Row, plan: ResponseSurfacePlan) -> CGFloat {
        if row.endsRun, row.surface == .canvas, case .reviewSummary = blocks[row.sourceIndex] { return 48 }
        if row.surface == .canvas, !row.isFooter,
           let index = plan.rows.firstIndex(where: { $0.id == row.id }),
           row.endsRun || (plan.rows.indices.contains(index + 1) && plan.rows[index + 1].isFooter) {
            switch blocks[row.sourceIndex] {
            case .sideBySide, .oneAgainstMany: return 48
            default: return 40
            }
        }
        guard row.endsRun, row.surface == .paper, row.id != plan.rows.last?.id else { return 0 }
        if let index = plan.rows.firstIndex(where: { $0.id == row.id }),
           plan.rows.indices.contains(index + 1), plan.rows[index + 1].isFooter {
            if case .sectionHeader = blocks[row.sourceIndex] { return 65 }
            if case .featureList = blocks[row.sourceIndex] { return 35 }
            return 42
        }
        switch blocks[row.sourceIndex] {
        case .cardCarousel(let carousel) where !carousel.isHotelFamily: return 40
        case .itemGrid: return 40
        default: break
        }
        if case .text(let text) = blocks[row.sourceIndex], text.style == .intro {
            return comparisonFollows(row.sourceIndex) ? 26 : 0
        }
        return 28
    }

    private var legacyContent: some View {
        let items = blocks
        let keys = ResponseSurfacePlan.rowIDs(in: items)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(zip(items.indices, keys)), id: \.1) { index, _ in
                let block = items[index]
                if case .sectionHeader(let header) = block,
                   let carousel = followingStepCarousel(at: index, in: items) {
                    StepCarouselSectionView(header: header, block: carousel)
                        .opacity(
                            invisibleBlockIDs.contains(header.id) ||
                            invisibleBlockIDs.contains(carousel.id) ? 0 : 1)
                        .padding(
                            .top,
                            index == 0 ? 0 : spacingAbove(block, previous: items[index - 1]))
                        .modifier(
                            BlockIntro(armed: introArmed, start: revealStart, index: index))
                        .transition(.opacity.combined(with: .offset(y: 14)))
                } else if isGroupedStepCarousel(at: index, in: items) {
                    EmptyView()
                } else {
                    BlockView(block: block)
                        .opacity(invisibleBlockIDs.contains(block.id) ? 0 : 1)
                        .padding(
                            .top,
                            index == 0 ? 0 : spacingAbove(block, previous: items[index - 1]))
                        .modifier(
                            BlockIntro(armed: introArmed, start: revealStart, index: index))
                        .transition(.opacity.combined(with: .offset(y: 14)))
                }
            }
        }
    }

    private func followingStepCarousel(
        at index: Int,
        in items: [Block]
    ) -> StepCarousel? {
        guard index + 1 < items.count,
              case .stepCarousel(let carousel) = items[index + 1]
        else { return nil }
        return carousel
    }

    private func isGroupedStepCarousel(at index: Int, in items: [Block]) -> Bool {
        guard index > 0,
              case .sectionHeader = items[index - 1],
              case .stepCarousel = items[index]
        else { return false }
        return true
    }

    private struct BlockIntro: ViewModifier {
        let armed: Bool
        let start: Date?
        let index: Int
        @State private var shown = false

        func body(content: Content) -> some View {
            if !armed {
                content
            } else {
                content
                    .opacity(shown ? 1 : 0)
                    .blur(radius: shown ? 0 : 12)
                    .offset(y: shown ? 0 : 30)
                    .scaleEffect(shown ? 1 : 0.96, anchor: .top)
                    .onChange(of: start != nil) { _, hasStart in
                        if hasStart { animateIn() }
                    }
                    .onAppear { if start != nil { animateIn() } }
            }
        }

        private func animateIn() {
            guard !shown else { return }
            withAnimation(.spring(response: 0.62, dampingFraction: 0.8).delay(Double(index) * 0.09)) {
                shown = true
            }
        }
    }

    private func spacingAbove(_ block: Block, previous: Block, isResponse: Bool = false) -> CGFloat {
        switch (previous, block) {
        case (.hero, .titleBlock): 24
        case (_, .map(let map)): map.thin == true ? 42 : 16
        case (.text(let text), .sectionHeader) where isResponse && text.style == .intro: 34
        case (.featureList, .sectionHeader), (.factList, .sectionHeader): 41
        case (.text(let text), .sectionHeader) where isResponse && text.style == .body: 58.3
        case (.mediaRowList, .sectionHeader): 55
        case (.cardCarousel(let carousel), .sectionHeader) where !carousel.isHotelFamily: 58.3
        case (.itemGrid, .sectionHeader): 58.3
        case (_, .sectionHeader): 44
        case (.sectionHeader, .comparisonTable) where isResponse: 52 / 3
        case (.sectionHeader, .cardCarousel(let carousel))
            where isResponse && carousel.presentation != nil: 52 / 3
        case (.sectionHeader, .sideBySide), (.sectionHeader, .oneAgainstMany): 53 / 3
        case (.sectionHeader, .cardCarousel(let carousel)) where carousel.id == "ideas": 40 / 3
        case (.sectionHeader, .featureList): 19
        case (.sectionHeader, .itemGrid) where isResponse: 52 / 3
        case (.sectionHeader, .mediaRowList): 19.5
        case (.sectionHeader, _): 20
        case (.titleBlock, _): 28
        case (.text(let text), _) where text.style == .intro: 18
        case (.text, .text): 16
        case (.chart, .chart): 16
        case (.text, .chart): 20
        case (.text, .flashcards): 20
        case (.text, .whatIf): 20
        case (.diagram, .text): 20
        case (_, .chipRow(let row)) where row.role == .followUp: 0
        case (_, .chipRow): 36
        default: 28
        }
    }
}

private enum ImagePrefetchPlan {
    static func specs(in blocks: [Block]) -> [ImageSpec] {
        var result = [ImageSpec]()
        var seen = Set<ImageSpec>()

        func visit(_ value: Any) {
            if let grid = value as? PhotoGrid, grid.presentation == .collection {
                for spec in grid.images.prefix(4) { visit(spec) }
                return
            }
            if let spec = value as? ImageSpec {
                if seen.insert(spec).inserted { result.append(spec) }
                return
            }

            let mirror = Mirror(reflecting: value)
            switch mirror.displayStyle {
            case .collection, .dictionary, .enum, .optional, .struct, .tuple:
                for child in mirror.children { visit(child.value) }
            default:
                break
            }
        }

        visit(blocks)
        return result
    }
}
