import SwiftUI
import UIKit
import EmblemCore

struct DiagramLayout {
    struct Placed: Identifiable {
        let node: DiagramBlock.Node
        let frame: CGRect
        let fontSize: CGFloat
        let showsIcon: Bool
        var id: String { node.id }
    }
    struct Label: Identifiable {
        let id: Int
        let text: String
        let frame: CGRect
        let fontSize: CGFloat
    }
    struct Route {
        let edge: Int
        let points: [CGPoint]
    }

    let placed: [Placed]
    let routes: [Route]
    let labels: [Label]
    let legend: [String]
    let size: CGSize

    static let renderableNodeLimit = 8
    static let nodeHeight: CGFloat = 38
    static let nodeFontSizes: [CGFloat] = [13, 12, 11]
    static let labelFontSizes: [CGFloat] = [11, 10]
    static let labelPadding = CGSize(width: 5, height: 2)
    static let arrowLength: CGFloat = 7
    static let nodePadding: CGFloat = 12
    static let iconRoom: CGFloat = 21
    private static let nodeGap: CGFloat = 12
    private static let laneInset: CGFloat = 16
    private static let laneStep: CGFloat = 10
    private static let trackStep: CGFloat = 10
    private static let clearance: CGFloat = 6

    init?(block: DiagramBlock, width: CGFloat) {
        var seen = Set<String>()
        let nodes = block.nodes.prefix(Self.renderableNodeLimit).filter { seen.insert($0.id).inserted }
        guard nodes.count >= 2, width > 0 else { return nil }
        let graph = DiagramGraph(nodes: Array(nodes), edges: block.edges)
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        let natural = byID.mapValues { node in
            Self.nodePadding * 2 + (node.icon == nil ? 0 : Self.iconRoom)
                + ceil((node.label as NSString).size(withAttributes: [.font: Self.font(13)]).width)
        }
        let required = min(width, graph.rows.map { row in
            row.count == 1 ? natural[row[0]]!
                : row.map { min(natural[$0]!, 96) }.reduce(0, +) + CGFloat(row.count - 1) * Self.nodeGap
        }.max()!)

        let tries: [(CGFloat, Bool)] = [(96, true), (72, true), (56, true), (96, false), (56, false)]
        let attempts = tries.lazy.compactMap { limit, beside in
            Self.attempt(graph, byID, natural, required: required, width: width, laneLimit: limit, beside: beside)
        }
        guard let chosen = attempts.first(where: \.legend.isEmpty)
            ?? attempts.min(by: { $0.legend.count < $1.legend.count })
            ?? Self.attempt(graph, byID, natural, required: 0, width: width, laneLimit: 0, beside: true)
        else { return nil }
        self = chosen
    }

    private init(placed: [Placed], routes: [Route], labels: [Label], legend: [String], size: CGSize) {
        self.placed = placed
        self.routes = routes
        self.labels = labels
        self.legend = legend
        self.size = size
    }

    private static func attempt(
        _ graph: DiagramGraph, _ byID: [String: DiagramBlock.Node], _ natural: [String: CGFloat],
        required: CGFloat, width: CGFloat, laneLimit: CGFloat, beside: Bool
    ) -> DiagramLayout? {
        var laneLabels: [Int: (size: CGSize, font: CGFloat)] = [:]
        for lane in graph.lanes where laneLimit > 0 {
            if let text = graph.edges[lane.edge].label, let fit = Self.fitLabel(text, maxWidth: laneLimit) {
                laneLabels[lane.edge] = fit
            }
        }
        var offsets: [DiagramGraph.Side: [Int: CGFloat]] = [:]
        var sides: [DiagramGraph.Side: CGFloat] = [:]
        for side in [DiagramGraph.Side.left, .right] {
            var previous: CGFloat = 0
            var extent: CGFloat = 0
            let onSide = graph.lanes.filter { $0.side == side }
            for index in Set(onSide.map(\.index)).sorted() {
                let atIndex = onSide.filter { $0.index == index }
                let half = beside ? atIndex.map { (laneLabels[$0.edge]?.size.width ?? 0) / 2 }.max() ?? 0 : 0
                let offset = max(Self.laneInset, previous + Self.laneStep, half + Self.clearance)
                offsets[side, default: [:]][index] = offset
                extent = max(extent, offset + max(half, 4) + 2)
                previous = offset
            }
            sides[side] = extent
        }
        let even = max(sides[.left]!, sides[.right]!)
        let core = width - even * 2 >= required
            ? CGRect(x: even, y: 0, width: width - even * 2, height: 0)
            : CGRect(x: sides[.left]!, y: 0, width: max(width - sides[.left]! - sides[.right]!, 1), height: 0)
        guard core.width >= required else { return nil }

        let singleNatural = graph.rows.filter { $0.count == 1 }.map { natural[$0[0]]! }.max() ?? 0
        let spineWidth = min(core.width, max(singleNatural, core.width * 0.62))
        var frames: [String: CGRect] = [:]
        var styles: [String: (font: CGFloat, icon: Bool)] = [:]
        var rowWidths: [CGFloat] = []
        var rowTops: [CGFloat] = []
        var rowHeights: [CGFloat] = []
        for row in graph.rows {
            let column = (core.width - CGFloat(row.count - 1) * Self.nodeGap) / CGFloat(row.count)
            let nodeWidth = row.count == 1 ? spineWidth : min(column, row.map { natural[$0]! }.max()!)
            rowWidths.append(column)
            var height = Self.nodeHeight
            for (i, id) in row.enumerated() {
                let node = byID[id]!
                let ladder = (node.icon == nil ? [false] : [true, false]).flatMap { icon in
                    Self.nodeFontSizes.map { (icon, $0) }
                }
                let fit = ladder.lazy.compactMap { icon, size in
                    Self.measure(node.label, size: size, maxWidth: Self.textRoom(nodeWidth, icon: icon)).map { (icon, size, $0) }
                }.first ?? (false, 11, CGSize(width: nodeWidth, height: Self.font(11).lineHeight * 2))
                styles[id] = (fit.1, fit.0)
                height = max(height, fit.2.height + 16)
                let centerX = row.count == 1 ? core.midX : core.minX + column / 2 + CGFloat(i) * (column + Self.nodeGap)
                frames[id] = CGRect(x: centerX - nodeWidth / 2, y: 0, width: nodeWidth, height: 0)
            }
            rowHeights.append(height)
        }

        struct Hop {
            let edge: Int
            let from: String
            let to: String
            var slot: Slot
            var label: (size: CGSize, font: CGFloat)?
        }
        enum Slot { case rise, drop, none }
        var hops: [[Hop]] = Array(repeating: [], count: max(graph.rows.count - 1, 0))
        for i in graph.edges.indices where !graph.laneEdges.contains(i) {
            let (from, to) = graph.ends(i)
            hops[graph.row[from]!].append(Hop(edge: i, from: from, to: to, slot: .none, label: nil))
        }
        var legend: [String] = []
        var gapHeights: [CGFloat] = []
        var riseHeights: [CGFloat] = []
        var tracks: [[Int: Int]] = []
        for (gap, list) in hops.enumerated() {
            for k in list.indices {
                let hop = list[k]
                let indegree = list.filter { $0.to == hop.to }.count
                let outdegree = list.filter { $0.from == hop.from }.count
                let slot: Slot = indegree == 1 ? .drop : (outdegree == 1 ? .rise : .none)
                hops[gap][k].slot = slot
                guard let text = graph.edges[hop.edge].label, slot != .none else { continue }
                let room = (slot == .drop ? rowWidths[gap + 1] : rowWidths[gap]) - 4
                hops[gap][k].label = Self.fitLabel(text, maxWidth: min(room, 150))
            }
            let rise = hops[gap].compactMap { $0.slot == .rise ? $0.label?.size.height : nil }.max()
            let drop = hops[gap].compactMap { $0.slot == .drop ? $0.label?.size.height : nil }.max()
            var bundles: [(key: String, low: CGFloat, high: CGFloat, members: [Int])] = []
            for (k, hop) in hops[gap].enumerated() {
                let sx = frames[hop.from]!.midX
                let tx = frames[hop.to]!.midX
                guard abs(sx - tx) > 0.5 else { continue }
                let shared = hops[gap].filter { $0.to == hop.to }.count > 1
                let key = shared ? "t" + hop.to : "s" + hop.from
                if let b = bundles.firstIndex(where: { $0.key == key }) {
                    bundles[b].low = min(bundles[b].low, sx, tx)
                    bundles[b].high = max(bundles[b].high, sx, tx)
                    bundles[b].members.append(k)
                } else {
                    bundles.append((key, min(sx, tx), max(sx, tx), [k]))
                }
            }
            var trackOf: [Int: Int] = [:]
            var occupied: [[ClosedRange<CGFloat>]] = []
            for bundle in bundles {
                let span = (bundle.low - Self.clearance)...(bundle.high + Self.clearance)
                let track = occupied.firstIndex { !$0.contains { $0.overlaps(span) } } ?? occupied.count
                if track == occupied.count { occupied.append([]) }
                occupied[track].append(span)
                for member in bundle.members { trackOf[member] = track }
            }
            tracks.append(trackOf)
            let riseHeight = rise.map { $0 + Self.labelPadding.height * 2 + Self.clearance * 2 } ?? 10
            let dropHeight = drop.map { $0 + Self.labelPadding.height * 2 + Self.clearance * 2 + Self.arrowLength } ?? 16
            riseHeights.append(riseHeight)
            gapHeights.append(riseHeight + CGFloat(max(occupied.count - 1, 0)) * Self.trackStep + dropHeight)
        }

        var cursor: CGFloat = 0
        for (r, row) in graph.rows.enumerated() {
            if r > 0 { cursor += gapHeights[r - 1] }
            rowTops.append(cursor)
            for id in row {
                let f = frames[id]!
                frames[id] = CGRect(x: f.minX, y: cursor, width: f.width, height: rowHeights[r])
            }
            cursor += rowHeights[r]
        }
        let height = cursor

        var routes: [Route] = []
        var pending: [(edge: Int, label: (size: CGSize, font: CGFloat), candidates: [CGPoint], laneX: CGFloat?)] = []
        for (gap, list) in hops.enumerated() {
            let gapTop = rowTops[gap] + rowHeights[gap]
            let gapBottom = rowTops[gap + 1]
            let riseHeight = riseHeights[gap]
            let lastTrack = tracks[gap].values.max() ?? 0
            let dropTop = gapTop + riseHeight + CGFloat(lastTrack) * Self.trackStep
            for (k, hop) in list.enumerated() {
                let from = frames[hop.from]!
                let to = frames[hop.to]!
                let tip = CGPoint(x: to.midX, y: to.minY - 1)
                if let track = tracks[gap][k] {
                    let y = gapTop + riseHeight + CGFloat(track) * Self.trackStep
                    routes.append(Route(edge: hop.edge, points: [
                        CGPoint(x: from.midX, y: from.maxY), CGPoint(x: from.midX, y: y),
                        CGPoint(x: to.midX, y: y), tip,
                    ]))
                } else {
                    routes.append(Route(edge: hop.edge, points: [CGPoint(x: to.midX, y: from.maxY), tip]))
                }
                guard let label = hop.label else {
                    if let text = graph.edges[hop.edge].label { legend.append(Self.legendLine(graph, hop.edge, byID, text)) }
                    continue
                }
                let center: CGPoint
                if hop.slot == .rise {
                    center = CGPoint(x: from.midX, y: gapTop + riseHeight / 2)
                } else {
                    let bandBottom = gapBottom - Self.arrowLength - 1
                    center = CGPoint(x: to.midX, y: (dropTop + bandBottom) / 2)
                }
                pending.append((hop.edge, label, [center], nil))
            }
        }

        var stubs: [String: [DiagramGraph.Side: [(lane: Int, other: Int, index: Int)]]] = [:]
        for (l, lane) in graph.lanes.enumerated() {
            let (from, to) = graph.ends(lane.edge)
            stubs[from, default: [:]][lane.side, default: []].append((l, graph.row[to]!, lane.index))
            stubs[to, default: [:]][lane.side, default: []].append((l, graph.row[from]!, lane.index))
        }
        func stubY(_ node: String, _ side: DiagramGraph.Side, _ lane: Int) -> CGFloat {
            let list = stubs[node]![side]!.sorted { ($0.other, $0.index) < ($1.other, $1.index) }
            let j = list.firstIndex { $0.lane == lane }!
            let frame = frames[node]!
            return frame.minY + frame.height * CGFloat(j + 1) / CGFloat(list.count + 1)
        }
        for (l, lane) in graph.lanes.enumerated() {
            let (from, to) = graph.ends(lane.edge)
            let source = frames[from]!
            let target = frames[to]!
            let offset = offsets[lane.side]![lane.index]!
            let left = lane.side == .left
            let x = left ? core.minX - offset : core.maxX + offset
            let y1 = stubY(from, lane.side, l)
            let y2 = stubY(to, lane.side, l)
            routes.append(Route(edge: lane.edge, points: [
                CGPoint(x: left ? source.minX : source.maxX, y: y1), CGPoint(x: x, y: y1),
                CGPoint(x: x, y: y2), CGPoint(x: left ? target.minX - 1 : target.maxX + 1, y: y2),
            ]))
            guard let text = graph.edges[lane.edge].label else { continue }
            guard let label = laneLabels[lane.edge] else {
                legend.append(Self.legendLine(graph, lane.edge, byID, text))
                continue
            }
            let top = min(y1, y2)
            let bottom = max(y1, y2)
            var candidates: [CGPoint] = []
            for r in (lane.lo + 1)..<max(lane.hi, lane.lo + 1) {
                candidates.append(CGPoint(x: x, y: rowTops[r] + rowHeights[r] / 2))
            }
            candidates.append(CGPoint(x: x, y: (top + bottom) / 2))
            for r in lane.lo..<lane.hi {
                candidates.append(CGPoint(x: x, y: (rowTops[r] + rowHeights[r] + rowTops[r + 1]) / 2))
            }
            var y = top
            while y <= bottom {
                candidates.append(CGPoint(x: x, y: y))
                y += 4
            }
            pending.append((lane.edge, label, candidates, x))
        }

        let segments = routes.map { route in
            zip(route.points, route.points.dropFirst()).map { a, b in
                CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                    .insetBy(dx: -2, dy: -2)
            }
        }
        let nodeRects = frames.values.map { $0.insetBy(dx: -4, dy: -4) }
        var labels: [Label] = []
        for item in pending {
            let ownRoute = routes.firstIndex { $0.edge == item.edge }!
            let own = routes[ownRoute].points
            let size = CGSize(width: item.label.size.width + Self.labelPadding.width * 2,
                              height: item.label.size.height + Self.labelPadding.height * 2)
            let found = item.candidates.lazy.compactMap { center -> CGRect? in
                var rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                  width: size.width, height: size.height)
                rect.origin.x = min(max(rect.minX, 0), width - size.width)
                guard rect.minX + 4 <= center.x, center.x <= rect.maxX - 4, rect.minY >= 0, rect.maxY <= height else { return nil }
                guard Self.sitsOnStraightRun(rect, x: center.x, route: own) else { return nil }
                if nodeRects.contains(where: { $0.intersects(rect) }) { return nil }
                if labels.contains(where: { $0.frame.insetBy(dx: -3, dy: -3).intersects(rect) }) { return nil }
                for (r, list) in segments.enumerated() where routes[r].edge != item.edge {
                    if list.contains(where: { $0.intersects(rect) }) { return nil }
                }
                return rect
            }.first
            if let found {
                labels.append(Label(id: item.edge, text: graph.edges[item.edge].label!, frame: found, fontSize: item.label.font))
            } else {
                legend.append(Self.legendLine(graph, item.edge, byID, graph.edges[item.edge].label!))
            }
        }
        for edge in graph.unrouted {
            legend.append(Self.legendLine(graph, edge, byID, graph.edges[edge].label))
        }

        return DiagramLayout(
            placed: graph.rows.flatMap { $0 }.map {
                Placed(node: byID[$0]!, frame: frames[$0]!, fontSize: styles[$0]!.font, showsIcon: styles[$0]!.icon)
            },
            routes: routes, labels: labels, legend: legend, size: CGSize(width: width, height: height))
    }

    private static func sitsOnStraightRun(_ rect: CGRect, x: CGFloat, route: [CGPoint]) -> Bool {
        zip(route, route.dropFirst()).contains { a, b in
            abs(a.x - x) < 0.5 && abs(b.x - x) < 0.5
                && rect.minY >= min(a.y, b.y) + 4 && rect.maxY <= max(a.y, b.y) - 4 - (b == route.last ? arrowLength : 0)
        }
    }

    private static func legendLine(_ graph: DiagramGraph, _ edge: Int, _ nodes: [String: DiagramBlock.Node], _ label: String?) -> String {
        let e = graph.edges[edge]
        let base = "\(nodes[e.from]!.label) → \(nodes[e.to]!.label)"
        return label.map { "\(base): \($0)" } ?? base
    }

    static func textRoom(_ width: CGFloat, icon: Bool) -> CGFloat {
        width - nodePadding * 2 - (icon ? iconRoom : 0)
    }

    static func font(_ size: CGFloat) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: .medium)
    }

    static func measure(_ text: String, size: CGFloat, maxWidth: CGFloat) -> CGSize? {
        let attributes: [NSAttributedString.Key: Any] = [.font: font(size)]
        let longest = text.split(separator: " ").map { (String($0) as NSString).size(withAttributes: attributes).width }.max() ?? 0
        guard maxWidth > 0, longest <= maxWidth else { return nil }
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
        guard rect.height <= font(size).lineHeight * 2 + 1 else { return nil }
        return CGSize(width: ceil(rect.width) + 1, height: ceil(rect.height))
    }

    private static func fitLabel(_ text: String, maxWidth: CGFloat) -> (size: CGSize, font: CGFloat)? {
        labelFontSizes.lazy.compactMap { size in
            measure(text, size: size, maxWidth: maxWidth - labelPadding.width * 2).map { ($0, size) }
        }.first
    }
}
