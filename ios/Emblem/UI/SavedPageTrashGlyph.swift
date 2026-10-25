import SwiftUI

struct SavedPageTrashGlyph: View {
    var body: some View {
        SavedPageTrashMark()
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }
}

private struct SavedPageTrashMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 19.5, y: 5.5))
        path.addLine(to: CGPoint(x: 18.8803, y: 15.5251))
        path.addCurve(to: CGPoint(x: 18.0008, y: 20.2879), control1: CGPoint(x: 18.7219, y: 18.0864), control2: CGPoint(x: 18.6428, y: 19.3671))
        path.addCurve(to: CGPoint(x: 16.8007, y: 21.416), control1: CGPoint(x: 17.6833, y: 20.7431), control2: CGPoint(x: 17.2747, y: 21.1273))
        path.addCurve(to: CGPoint(x: 11.9927, y: 22), control1: CGPoint(x: 15.8421, y: 22), control2: CGPoint(x: 14.559, y: 22))
        path.addCurve(to: CGPoint(x: 7.17905, y: 21.4149), control1: CGPoint(x: 9.42312, y: 22), control2: CGPoint(x: 8.1383, y: 22))
        path.addCurve(to: CGPoint(x: 5.97868, y: 20.2848), control1: CGPoint(x: 6.7048, y: 21.1257), control2: CGPoint(x: 6.296, y: 20.7408))
        path.addCurve(to: CGPoint(x: 5.10461, y: 15.5152), control1: CGPoint(x: 5.33688, y: 19.3626), control2: CGPoint(x: 5.25945, y: 18.0801))
        path.addLine(to: CGPoint(x: 4.5, y: 5.5))
        path.move(to: CGPoint(x: 3, y: 5.5))
        path.addLine(to: CGPoint(x: 21, y: 5.5))
        path.move(to: CGPoint(x: 16.0557, y: 5.5))
        path.addLine(to: CGPoint(x: 15.3731, y: 4.09173))
        path.addCurve(to: CGPoint(x: 14.3017, y: 2.39681), control1: CGPoint(x: 14.9196, y: 3.15626), control2: CGPoint(x: 14.6928, y: 2.68852))
        path.addCurve(to: CGPoint(x: 14.027, y: 2.2247), control1: CGPoint(x: 14.215, y: 2.3321), control2: CGPoint(x: 14.1231, y: 2.27454))
        path.addCurve(to: CGPoint(x: 12.0345, y: 2), control1: CGPoint(x: 13.5939, y: 2), control2: CGPoint(x: 13.0741, y: 2))
        path.addCurve(to: CGPoint(x: 9.99568, y: 2.23412), control1: CGPoint(x: 10.9688, y: 2), control2: CGPoint(x: 10.436, y: 2))
        path.addCurve(to: CGPoint(x: 9.71729, y: 2.41317), control1: CGPoint(x: 9.8981, y: 2.28601), control2: CGPoint(x: 9.80498, y: 2.3459))
        path.addCurve(to: CGPoint(x: 8.65861, y: 4.17126), control1: CGPoint(x: 9.32164, y: 2.7167), control2: CGPoint(x: 9.10063, y: 3.20155))
        path.addLine(to: CGPoint(x: 8.05292, y: 5.5))
        return path.applying(CGAffineTransform(a: rect.width / 24, b: 0, c: 0, d: rect.height / 24,
                                               tx: rect.minX, ty: rect.minY))
    }
}
