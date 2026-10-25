import SwiftUI
import EmblemCore

struct DiagramLayout {
    struct Placed: Identifiable {
        let node: DiagramBlock.Node
        let frame: CGRect
        var id: String { node.id }
    }
    struct Link {
        let from: CGRect
        let to: CGRect
        let label: String?
        let downward: Bool
        var sourceFraction: CGFloat = 0.5
        var targetFraction: CGFloat = 0.5

        var start: CGPoint {
            if downward { return CGPoint(x: from.minX + from.width * sourceFraction, y: from.maxY) }
            return CGPoint(x: to.midX >= from.midX ? from.maxX : from.minX,
                           y: from.minY + from.height * sourceFraction)
        }

        var tip: CGPoint {
            if downward { return CGPoint(x: to.minX + to.width * targetFraction, y: to.minY - 4) }
            return CGPoint(x: to.midX >= from.midX ? to.minX - 4 : to.maxX + 4,
                           y: to.minY + to.height * targetFraction)
        }
    }

    let placed: [Placed]
    let links: [Link]
    let size: CGSize

    static let nodeHeight: CGFloat = 38
    private static let labeledRowGap: CGFloat = 52
    private static let plainRowGap: CGFloat = 26
    private static let nodeGap: CGFloat = 12
    static let renderableNodeLimit = 8

    init?(block: DiagramBlock, width: CGFloat) {
        var seen = Set<String>()
        let nodes = block.nodes.prefix(Self.renderableNodeLimit).filter {
            seen.insert($0.id).inserted
        }
        guard nodes.count >= 2, width > 0 else { return nil }
        let ids = Set(nodes.map(\.id))
        let edges = block.edges.filter { ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to }

        var rank = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, 0) })
        for _ in 0..<nodes.count {
            var changed = false
            for edge in edges {
                let proposed = rank[edge.from]! + 1
                if rank[edge.to]! < proposed, proposed < nodes.count {
                    rank[edge.to] = proposed
                    changed = true
                }
            }
            if !changed { break }
        }

        var rows: [[DiagramBlock.Node]] = []
        for level in 0...rank.values.max()! {
            let row = nodes.filter { rank[$0.id] == level }
            if !row.isEmpty { rows.append(row) }
        }

        var slot: [String: Double] = [:]
        for (rowIndex, row) in rows.enumerated() {
            let ordered = rowIndex == 0 ? row : row.sorted { a, b in
                func mean(_ node: DiagramBlock.Node) -> Double {
                    let parents = edges.filter { $0.to == node.id }.compactMap { slot[$0.from] }
                    return parents.isEmpty ? .greatestFiniteMagnitude : parents.reduce(0, +) / Double(parents.count)
                }
                return mean(a) < mean(b)
            }
            rows[rowIndex] = ordered
            for (i, node) in ordered.enumerated() { slot[node.id] = Double(i) }
        }

        let font = UIFont.systemFont(ofSize: 13, weight: .medium)
        var frames: [String: CGRect] = [:]
        var result: [Placed] = []
        let labeledTargets = Set(edges.compactMap { edge in
            (edge.label?.isEmpty == false) ? edge.to : nil
        })
        var rowTops: [CGFloat] = []
        var cursor: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            if rowIndex > 0 {
                cursor += row.contains { labeledTargets.contains($0.id) }
                    ? Self.labeledRowGap
                    : Self.plainRowGap
            }
            rowTops.append(cursor)
            cursor += Self.nodeHeight
        }
        for (rowIndex, row) in rows.enumerated() {
            let y = rowTops[rowIndex]
            var widths = row.map { node in
                let text = (node.label as NSString).size(withAttributes: [.font: font]).width
                let iconRoom: CGFloat = node.icon == nil ? 0 : 22
                return min(max(text + 24 + iconRoom, 56), width * 0.8)
            }
            let rowWidth = widths.reduce(0, +) + CGFloat(row.count - 1) * Self.nodeGap
            if rowWidth > width {
                let scale = (width - CGFloat(row.count - 1) * Self.nodeGap) / (rowWidth - CGFloat(row.count - 1) * Self.nodeGap)
                widths = widths.map { $0 * scale }
            }
            var x = max(0, (width - min(rowWidth, width)) / 2)
            for (i, node) in row.enumerated() {
                let frame = CGRect(x: x, y: y, width: widths[i], height: Self.nodeHeight)
                frames[node.id] = frame
                result.append(Placed(node: node, frame: frame))
                x += widths[i] + Self.nodeGap
            }
        }

        placed = result
        struct Port: Hashable { let node: String; let face: Int }
        var built: [Link] = []
        var incoming: [Port: [Int]] = [:]
        var outgoing: [Port: [Int]] = [:]
        for edge in edges {
            guard let from = frames[edge.from], let to = frames[edge.to] else { continue }
            let downward = to.minY > from.minY
            let rightward = to.midX >= from.midX
            outgoing[Port(node: edge.from, face: downward ? 0 : (rightward ? 1 : 2)), default: []].append(built.count)
            incoming[Port(node: edge.to, face: downward ? 0 : (rightward ? 2 : 1)), default: []].append(built.count)
            built.append(Link(from: from, to: to, label: edge.label, downward: downward))
        }
        for (groups, isSource) in [(outgoing, true), (incoming, false)] {
            for group in groups.values where group.count > 1 {
                let ordered = group.sorted { a, b in
                    let lhs = isSource ? built[a].to : built[a].from
                    let rhs = isSource ? built[b].to : built[b].from
                    let x = built[a].downward ? lhs.midX : lhs.midY
                    let y = built[b].downward ? rhs.midX : rhs.midY
                    if x != y { return x < y }
                    return (built[a].label ?? "") < (built[b].label ?? "")
                }
                for (slot, index) in ordered.enumerated() {
                    let fraction = CGFloat(slot + 1) / CGFloat(ordered.count + 1)
                    if isSource { built[index].sourceFraction = fraction }
                    else { built[index].targetFraction = fraction }
                }
            }
        }
        links = built
        size = CGSize(width: width, height: cursor)
    }
}

struct DiagramBlockView: View {
    let block: DiagramBlock
    @State private var width: CGFloat = 0

    var body: some View {
        if block.nodes.count >= 2 {
            let hasTitle = !(block.title ?? "").isEmpty
            VStack(spacing: 3) {
                if let title = block.title, hasTitle {
                    Text(title)
                        .font(Theme.cardTitle())
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .seamCard(.top)
                }
                VStack(alignment: .leading, spacing: 10) {
                    canvas
                    if droppedNodeCount > 0 {
                        Text("+\(droppedNodeCount) more not shown")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .seamCard(hasTitle ? .bottom : .solo)
            }
            .padding(.horizontal, Theme.contentMargin)
        }
    }

    private var droppedNodeCount: Int {
        var seen = Set<String>()
        let unique = block.nodes.filter { seen.insert($0.id).inserted }
        return max(0, unique.count - DiagramLayout.renderableNodeLimit)
    }

    private var canvas: some View {
        let layout = DiagramLayout(block: block, width: width)
        return ZStack(alignment: .topLeading) {
            if let layout {
                Canvas { context, _ in
                    var labelRects = layout.placed.map { $0.frame.insetBy(dx: -4, dy: -4) }
                    for link in layout.links { draw(link, in: &context, avoiding: &labelRects) }
                }
                ForEach(layout.placed) { placed in
                    nodePill(placed.node)
                        .frame(width: placed.frame.width, height: placed.frame.height)
                        .position(x: placed.frame.midX, y: placed.frame.midY)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: layout?.size.height ?? DiagramLayout.nodeHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func nodePill(_ node: DiagramBlock.Node) -> some View {
        HStack(spacing: 5) {
            if let icon = node.icon {
                IconView(icon: icon, size: 16)
            }
            Text(node.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.cardSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func draw(
        _ link: DiagramLayout.Link,
        in context: inout GraphicsContext,
        avoiding labelRects: inout [CGRect]
    ) {
        let color = Theme.inkSecondary.opacity(0.55)

        let start: CGPoint
        let tip: CGPoint
        let c1: CGPoint
        let c2: CGPoint
        if link.downward {
            start = link.start
            tip = link.tip
            let stub = max((tip.y - start.y) * 0.5, 16)
            c1 = CGPoint(x: start.x, y: start.y + stub)
            c2 = CGPoint(x: tip.x, y: tip.y - stub)
        } else {
            let ltr = link.to.midX >= link.from.midX
            start = link.start
            tip = link.tip
            let stub = max(abs(tip.x - start.x) * 0.5, 16) * (ltr ? 1 : -1)
            c1 = CGPoint(x: start.x + stub, y: start.y)
            c2 = CGPoint(x: tip.x - stub, y: tip.y)
        }

        let dir = unit(dx: tip.x - c2.x, dy: tip.y - c2.y)
        let headLen: CGFloat = 8
        let base = CGPoint(x: tip.x - dir.dx * headLen, y: tip.y - dir.dy * headLen)

        var path = Path()
        path.move(to: start)
        path.addCurve(to: base, control1: c1, control2: c2)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

        let perp = (dx: -dir.dy, dy: dir.dx)
        let halfW: CGFloat = 4
        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: base.x + perp.dx * halfW, y: base.y + perp.dy * halfW))
        head.addLine(to: CGPoint(x: base.x - perp.dx * halfW, y: base.y - perp.dy * halfW))
        head.closeSubpath()
        context.fill(head, with: .color(color))

        if let label = link.label {
            let text = Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
            let resolved = context.resolve(text)
            let textSize = resolved.measure(in: CGSize(width: 120, height: 40))
            let pad: CGFloat = 3

            func bezier(_ t: CGFloat) -> CGPoint {
                let u = 1 - t
                let x = u * u * u * start.x + 3 * u * u * t * c1.x
                    + 3 * u * t * t * c2.x + t * t * t * base.x
                let y = u * u * u * start.y + 3 * u * u * t * c1.y
                    + 3 * u * t * t * c2.y + t * t * t * base.y
                return CGPoint(x: x, y: y)
            }
            func rect(at point: CGPoint) -> CGRect {
                CGRect(
                    x: point.x - textSize.width / 2 - pad,
                    y: point.y - textSize.height / 2 - 1,
                    width: textSize.width + pad * 2,
                    height: textSize.height + 2)
            }
            let home: CGFloat = 0.45
            var placedRect = rect(at: bezier(home))
            for offset in [0.0, -0.12, 0.12, -0.24, 0.24] {
                let t = min(0.9, max(0.1, home + offset))
                let candidate = rect(at: bezier(t))
                if !labelRects.contains(where: { $0.intersects(candidate) }) {
                    placedRect = candidate
                    break
                }
            }
            labelRects.append(placedRect)
            context.fill(Path(placedRect), with: .color(Theme.surface))
            context.draw(
                resolved,
                at: CGPoint(x: placedRect.midX, y: placedRect.midY + 1))
        }
    }

    private func unit(dx: CGFloat, dy: CGFloat) -> (dx: CGFloat, dy: CGFloat) {
        let len = max(hypot(dx, dy), 0.0001)
        return (dx / len, dy / len)
    }
}
