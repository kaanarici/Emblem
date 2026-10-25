import Foundation
import EmblemCore

struct DiagramGraph {
    struct Edge {
        let from: String
        let to: String
        var label: String?
        var reversed = false
    }
    enum Side { case left, right }
    struct Lane {
        let edge: Int
        let side: Side
        let index: Int
        let lo: Int
        let hi: Int
    }

    static let rowCapacity = 3
    static let lanesPerSide = 3

    let edges: [Edge]
    let rows: [[String]]
    let row: [String: Int]
    let lanes: [Lane]
    let laneEdges: Set<Int>
    let unrouted: [Int]

    init(nodes: [DiagramBlock.Node], edges raw: [DiagramBlock.Edge]) {
        let ids = Set(nodes.map(\.id))
        var edges: [Edge] = []
        var merged: [String: Int] = [:]
        for edge in raw where ids.contains(edge.from) && ids.contains(edge.to) && edge.from != edge.to {
            let label = edge.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = label?.isEmpty == false ? label : nil
            let key = edge.from + "\u{1F}" + edge.to
            if let i = merged[key] {
                if let text, edges[i].label?.contains(text) != true {
                    edges[i].label = [edges[i].label, text].compactMap { $0 }.joined(separator: ", ")
                }
            } else {
                merged[key] = edges.count
                edges.append(Edge(from: edge.from, to: edge.to, label: text))
            }
        }

        var visiting = Set<String>()
        var done = Set<String>()
        func visit(_ id: String) {
            visiting.insert(id)
            for i in edges.indices where edges[i].from == id {
                if visiting.contains(edges[i].to) {
                    edges[i].reversed = true
                } else if !done.contains(edges[i].to) {
                    visit(edges[i].to)
                }
            }
            visiting.remove(id)
            done.insert(id)
        }
        for node in nodes where !done.contains(node.id) { visit(node.id) }
        let ordered = edges.map { $0.reversed ? ($0.to, $0.from) : ($0.from, $0.to) }

        var floor: [String: Int] = [:]
        var rank: [String: Int] = [:]
        for _ in 0...(nodes.count * nodes.count) {
            rank = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, floor[$0.id] ?? 0) })
            for _ in 0...nodes.count {
                var changed = false
                for (u, v) in ordered where rank[v]! < rank[u]! + 1 {
                    rank[v] = rank[u]! + 1
                    changed = true
                }
                if !changed { break }
            }
            let levels = Set(rank.values).sorted()
            guard let crowded = levels.first(where: { level in
                nodes.filter { rank[$0.id] == level }.count > Self.rowCapacity
            }) else { break }
            let last = nodes.last { rank[$0.id] == crowded }!
            floor[last.id] = crowded + 1
        }

        var rows = Set(rank.values).sorted().map { level in nodes.filter { rank[$0.id] == level }.map(\.id) }
        var row: [String: Int] = [:]
        for (r, ids) in rows.enumerated() { for id in ids { row[id] = r } }

        func reorder(_ r: Int, against other: Int) {
            let position = Dictionary(uniqueKeysWithValues: rows[other].enumerated().map { ($1, Double($0)) })
            let keyed = rows[r].enumerated().map { i, id -> (Double, Int, String) in
                let near = ordered.compactMap { u, v in u == id ? position[v] : (v == id ? position[u] : nil) }
                return (near.isEmpty ? Double(i) : near.reduce(0, +) / Double(near.count), i, id)
            }
            rows[r] = keyed.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
        }
        if rows.count > 1 {
            for r in 1..<rows.count { reorder(r, against: r - 1) }
            for r in (0..<(rows.count - 1)).reversed() { reorder(r, against: r + 1) }
            for r in 1..<rows.count { reorder(r, against: r - 1) }
        }

        let laneEdges = edges.indices.filter { i in
            edges[i].reversed || row[ordered[i].1]! - row[ordered[i].0]! != 1
        }
        var lanes: [Lane] = []
        var unrouted: [Int] = []
        var pins: [String: Side] = [:]
        for i in laneEdges.sorted(by: { a, b in
            let span = { (e: Int) in abs(row[edges[e].to]! - row[edges[e].from]!) }
            return (span(a), a) < (span(b), b)
        }) {
            let ends = [edges[i].from, edges[i].to]
            let lo = ends.map { row[$0]! }.min()!
            let hi = ends.map { row[$0]! }.max()!
            let options = [Side.right, .left].compactMap { side -> (index: Int, side: Side)? in
                for id in ends where rows[row[id]!].count > 1 {
                    if let pin = pins[id], pin != side { return nil }
                    if rows[row[id]!].contains(where: { $0 != id && pins[$0] == side }) { return nil }
                }
                let used = Set(lanes.filter { $0.side == side && $0.lo <= hi && lo <= $0.hi }.map(\.index))
                let index = (1...Self.lanesPerSide).first { !used.contains($0) }
                return index.map { ($0, side) }
            }
            guard let choice = options.min(by: { $0.index < $1.index }) else {
                unrouted.append(i)
                continue
            }
            for id in ends where rows[row[id]!].count > 1 {
                pins[id] = choice.side
                let r = row[id]!
                rows[r].removeAll { $0 == id }
                if choice.side == .left { rows[r].insert(id, at: 0) } else { rows[r].append(id) }
            }
            lanes.append(Lane(edge: i, side: choice.side, index: choice.index, lo: lo, hi: hi))
        }

        self.edges = edges
        self.rows = rows
        self.row = row
        self.lanes = lanes
        self.laneEdges = Set(laneEdges)
        self.unrouted = unrouted
    }

    func ends(_ edge: Int) -> (String, String) {
        (edges[edge].from, edges[edge].to)
    }
}
