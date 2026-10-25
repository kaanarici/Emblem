import Foundation

public enum ResponseSurface: Equatable {
    case paper, canvas, questions
}

public struct ResponseSurfacePlan {
    public enum TerminalSurface: Equatable {
        case paper, comparisonCanvas, followUpCanvas, questions
    }

    public struct RowID: Hashable {
        public let blockID: String
        public let occurrence: Int
    }

    public struct Row: Identifiable {
        public let id: RowID
        public let sourceIndex: Int
        public let previousSourceIndex: Int?
        public let groupedCarouselIndex: Int?
        public let surface: ResponseSurface?
        public let startsRun: Bool
        public let endsRun: Bool
        public let showsPaperEdge: Bool
        public var isFooter = false
    }

    public let isEnabled: Bool
    public let rows: [Row]
    public let terminalSurface: TerminalSurface?

    public var initialSurface: ResponseSurface? {
        isEnabled ? rows.first?.surface ?? .paper : nil
    }

    public var startsOnFooter: Bool { rows.first?.isFooter == true }

    public var endsOnPaper: Bool { rows.last?.surface == .paper }

    public static func rowIDs(in blocks: [Block]) -> [RowID] {
        var occurrences: [String: Int] = [:]
        return blocks.map { block in
            let occurrence = occurrences[block.id, default: 0]
            occurrences[block.id] = occurrence + 1
            return RowID(blockID: block.id, occurrence: occurrence)
        }
    }

    public init(blocks: [Block], isHome: Bool = false, asksQuestions hinted: Bool = false) {
        let enabled = !isHome
        isEnabled = enabled
        let keys = Self.rowIDs(in: blocks)
        let visible = blocks.indices.filter { Self.role(of: blocks[$0]) != nil }
        var surfaces = Array(repeating: ResponseSurface.paper, count: blocks.count)
        var current = ResponseSurface.paper
        var pending: [Int] = []
        var pendingHasProse = false

        func resolvePending(_ surface: ResponseSurface) {
            for index in pending { surfaces[index] = surface }
            pending.removeAll(keepingCapacity: true)
            pendingHasProse = false
        }

        for index in visible {
            guard let role = Self.role(of: blocks[index]) else { continue }
            switch role {
            case .heading:
                if pendingHasProse { resolvePending(.paper) }
                pending.append(index)
                if case .sectionHeader(let header) = blocks[index], header.subtitle?.isEmpty == false {
                    pendingHasProse = true
                }
                current = .paper
            case .prose:
                if pending.isEmpty {
                    surfaces[index] = current
                } else {
                    pending.append(index)
                    pendingHasProse = true
                }
            case .paper:
                resolvePending(.paper)
                current = .paper
                surfaces[index] = .paper
            case .comparison:
                resolvePending(.canvas)
                current = .canvas
                surfaces[index] = .canvas
            case .followUp:
                resolvePending(pendingHasProse ? .paper : .canvas)
                surfaces[index] = .canvas
                current = .paper
            }
        }
        resolvePending(.paper)
        let asksQuestions = hinted || blocks.contains {
            if case .questionList(let list) = $0 { return list.inlineChoice == nil && list.inlineCount == nil && list.inlineArea == nil }
            return false
        }
        if asksQuestions { surfaces = surfaces.map { _ in .questions } }

        var indices: [(source: Int, carousel: Int?)] = []
        var consumed: Int?
        for index in visible {
            if index == consumed { continue }
            var carousel: Int?
            if case .sectionHeader = blocks[index], index + 1 < blocks.count,
               case .stepCarousel = blocks[index + 1] {
                carousel = index + 1
                consumed = carousel
            }
            indices.append((index, carousel))
        }

        var rows: [Row] = indices.enumerated().map { offset, item in
            let previous = offset > 0 ? indices[offset - 1] : nil
            let surface = enabled ? surfaces[item.source] : nil
            let previousSurface = previous.map { surfaces[$0.source] }
            let nextSurface = offset + 1 < indices.count ? surfaces[indices[offset + 1].source] : nil
            return Row(
                id: keys[item.source], sourceIndex: item.source,
                previousSourceIndex: previous.map { $0.carousel ?? $0.source },
                groupedCarouselIndex: item.carousel, surface: surface,
                startsRun: enabled && previousSurface != surface,
                endsRun: enabled && nextSurface != surface,
                showsPaperEdge: enabled && previousSurface == .paper && surface == .canvas)
        }
        var runStart = 0
        for index in rows.indices {
            if rows[index].startsRun { runStart = index }
            guard rows[index].endsRun, rows[index].surface == .canvas else { continue }
            let run = runStart...index
            if let first = run.first(where: { Self.role(of: blocks[rows[$0].sourceIndex]) == .followUp }) {
                for row in first...index { rows[row].isFooter = true }
            }
        }
        self.rows = rows

        if !enabled {
            terminalSurface = nil
        } else if asksQuestions {
            terminalSurface = .questions
        } else if let last = rows.last {
            terminalSurface = last.isFooter ? .followUpCanvas : last.surface == .canvas ? .comparisonCanvas : .paper
        } else {
            terminalSurface = .paper
        }
    }

    private enum Role { case heading, prose, paper, comparison, followUp }

    private static func role(of block: Block) -> Role? {
        switch block {
        case .pageMeta, .unknown: nil
        case .sectionHeader: .heading
        case .text(let text): text.style == .intro ? .paper : .prose
        case .sideBySide, .oneAgainstMany, .reviewSummary, .stepCarousel: .comparison
        case .chipRow(let chips) where chips.role == .followUp: .followUp
        default: .paper
        }
    }
}
