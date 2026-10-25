import SwiftUI

struct EmptyDayArt: View {
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    private var page: Color { dark ? Color(white: 0.24) : Color(white: 0.996) }
    private var header: Color { dark ? Color(white: 0.28) : Color(white: 0.918) }
    private var stand: Color { dark ? Color(white: 0.20) : Color(white: 0.843) }
    private var foldTop: Color { dark ? Color(white: 0.16) : Color(red: 0.647, green: 0.678, blue: 0.745) }
    private var foldBottom: Color { dark ? Color(white: 0.14) : Color(white: 0.639) }
    private var line: Color { dark ? Color(white: 0.33) : Color(white: 0.898) }
    private var ring: Color { dark ? Color(white: 0.45) : Color(white: 0.553) }

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 534
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
            func shape(_ points: [CGPoint]) -> Path {
                var path = Path()
                path.addLines(points)
                path.closeSubpath()
                return path
            }

            let apex = p(67, 41), topRight = p(452, 41), bottomRight = p(533, 361), bottomLeft = p(155, 361)
            context.fill(shape([apex, p(0, 361), p(55, 361)]), with: .color(stand))
            context.fill(shape([apex, p(55, 361), bottomLeft]), with: .linearGradient(
                Gradient(colors: [foldTop, foldBottom]), startPoint: apex, endPoint: p(67, 220)))
            context.fill(shape([apex, topRight, bottomRight, bottomLeft]), with: .color(page))
            let fold: CGFloat = 72.0 / 320
            context.fill(shape([apex, topRight,
                                p(452 + 81 * fold, 41 + 320 * fold), p(67 + 88 * fold, 41 + 320 * fold)]),
                         with: .color(header))

            var grid = Path()
            for (y, x0, x1) in [(173, 127, 445), (232, 139, 460), (290, 155, 474)] as [(CGFloat, CGFloat, CGFloat)] {
                grid.move(to: p(x0, y))
                grid.addLine(to: p(x1, y))
            }
            for (top, bottom) in [(163, 209), (240, 284), (315, 360), (391, 436)] as [(CGFloat, CGFloat)] {
                grid.move(to: p(top, 131))
                grid.addLine(to: p(bottom, 325))
            }
            context.stroke(grid, with: .color(line), style: StrokeStyle(lineWidth: 5.5 * scale, lineCap: .round))

            for x in [165, 388] as [CGFloat] {
                var hook = Path()
                hook.addArc(center: .zero, radius: 1, startAngle: .degrees(178), endAngle: .degrees(465),
                            clockwise: false)
                let placed = hook.applying(CGAffineTransform(a: 23.5 * scale, b: 0, c: 0, d: 35.5 * scale,
                                                             tx: x * scale, ty: 41 * scale))
                context.stroke(placed, with: .color(ring), style: StrokeStyle(lineWidth: 9 * scale, lineCap: .round))
            }
        }
        .aspectRatio(534.0 / 362, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
