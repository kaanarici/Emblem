import SwiftUI
import EmblemCore

struct DiagramBlockView: View {
    let block: DiagramBlock
    @State private var width: CGFloat = 0

    var body: some View {
        if block.nodes.count >= 2 {
            let hasTitle = !(block.title ?? "").isEmpty
            let layout = DiagramLayout(block: block, width: width)
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
                    canvas(layout)
                    ForEach(Array((layout?.legend ?? []).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                    }
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

    private func canvas(_ layout: DiagramLayout?) -> some View {
        ZStack(alignment: .topLeading) {
            if let layout {
                Canvas { context, _ in draw(layout.routes, in: &context) }
                ForEach(layout.placed) { placed in
                    nodePill(placed)
                        .frame(width: placed.frame.width, height: placed.frame.height)
                        .position(x: placed.frame.midX, y: placed.frame.midY)
                }
                ForEach(layout.labels) { label in
                    Text(label.text)
                        .font(.system(size: label.fontSize, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .frame(width: label.frame.width, height: label.frame.height)
                        .background(Theme.surface)
                        .position(x: label.frame.midX, y: label.frame.midY)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: layout?.size.height ?? DiagramLayout.nodeHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func nodePill(_ placed: DiagramLayout.Placed) -> some View {
        HStack(spacing: 5) {
            if let icon = placed.node.icon, placed.showsIcon {
                IconView(icon: icon, size: 16)
            }
            Text(placed.node.label)
                .font(.system(size: placed.fontSize, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, DiagramLayout.nodePadding - 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.cardSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func draw(_ routes: [DiagramLayout.Route], in context: inout GraphicsContext) {
        var lines = Path()
        var heads = Path()
        for route in routes {
            let points = route.points
            guard let tip = points.last, points.count >= 2 else { continue }
            let before = points[points.count - 2]
            let length = max(hypot(tip.x - before.x, tip.y - before.y), 0.0001)
            let dx = (tip.x - before.x) / length
            let dy = (tip.y - before.y) / length
            let base = CGPoint(x: tip.x - dx * DiagramLayout.arrowLength, y: tip.y - dy * DiagramLayout.arrowLength)
            lines.move(to: points[0])
            for i in 1..<(points.count - 1) {
                let previous = points[i - 1]
                let next = i + 1 == points.count - 1 ? base : points[i + 1]
                let room = min(hypot(points[i].x - previous.x, points[i].y - previous.y),
                               hypot(next.x - points[i].x, next.y - points[i].y)) / 2
                lines.addArc(tangent1End: points[i], tangent2End: next, radius: min(18, room))
            }
            lines.addLine(to: base)
            heads.move(to: tip)
            heads.addLine(to: CGPoint(x: base.x - dy * 3.5, y: base.y + dx * 3.5))
            heads.addLine(to: CGPoint(x: base.x + dy * 3.5, y: base.y - dx * 3.5))
            heads.closeSubpath()
        }
        context.drawLayer { layer in
            layer.opacity = 0.55
            layer.stroke(lines, with: .color(Theme.inkSecondary), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            layer.fill(heads, with: .color(Theme.inkSecondary))
        }
    }
}
