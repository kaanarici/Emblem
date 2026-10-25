import SwiftUI

struct EmblemLogo: View {
    var size: CGFloat = 64

    var body: some View {
        Image("EmblemLogo")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct GoogleGMark: View {
    var size: CGFloat = 20

    var body: some View {
        Canvas { context, canvasSize in
            let lw = canvasSize.width * 0.20
            let r = (canvasSize.width - lw) / 2
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            func arc(_ from: Double, _ to: Double, _ color: Color) {
                var p = Path()
                p.addArc(
                    center: c, radius: r,
                    startAngle: .degrees(from), endAngle: .degrees(to),
                    clockwise: false)
                context.stroke(p, with: .color(color), lineWidth: lw)
            }

            let blue = Color(red: 0.26, green: 0.52, blue: 0.96)
            arc(0, 45, blue)
            arc(45, 135, Color(red: 0.20, green: 0.66, blue: 0.33))
            arc(135, 225, Color(red: 0.98, green: 0.74, blue: 0.02))
            arc(225, 315, Color(red: 0.92, green: 0.26, blue: 0.21))

            let bar = CGRect(x: c.x, y: c.y - lw / 2, width: r + lw / 2, height: lw)
            context.fill(Path(bar), with: .color(blue))
        }
        .frame(width: size, height: size)
    }
}
