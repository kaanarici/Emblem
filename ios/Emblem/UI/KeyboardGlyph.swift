import SwiftUI
import UIKit

struct KeyboardGlyph: View {
    var size: CGFloat = 24

    @Environment(\.displayScale) private var displayScale
    private struct RasterKey: Hashable {
        let size: CGFloat
        let scale: CGFloat
    }
    private static var rasters: [RasterKey: UIImage] = [:]

    var body: some View {
        Image(uiImage: raster)
            .renderingMode(.template)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var raster: UIImage {
        let key = RasterKey(size: size, scale: displayScale)
        if let image = Self.rasters[key] { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { renderer in
            let context = renderer.cgContext
            context.setFlatness(0.01)
            context.setFillColor(UIColor.black.cgColor)
            context.addPath(KeyboardGlyphShape().path(in: CGRect(x: 0, y: 0, width: size, height: size)).cgPath)
            context.drawPath(using: .eoFill)
        }
        Self.rasters[key] = image
        return image
    }
}

struct KeyboardGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let transform = CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - 12 * scale, ty: rect.midY - 12 * scale)
        return Self.designPath.applying(transform)
    }

    private static var designPath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 7.88250855, y: 3.75000000))
        path.addLine(to: CGPoint(x: 16.11749145, y: 3.75000000))
        path.addCurve(to: CGPoint(x: 20.08023728, y: 4.23630515), control1: CGPoint(x: 16.94195842, y: 3.75000000), control2: CGPoint(x: 19.13142818, y: 3.80022796))
        path.addCurve(to: CGPoint(x: 22.26188338, y: 6.40985483), control1: CGPoint(x: 21.02904638, y: 4.67238233), control2: CGPoint(x: 21.82418181, y: 5.46456690))
        path.addCurve(to: CGPoint(x: 22.75000000, y: 10.35789430), control1: CGPoint(x: 22.69958494, y: 7.35514275), control2: CGPoint(x: 22.75000000, y: 9.53648705))
        path.addLine(to: CGPoint(x: 22.75000000, y: 13.64210570))
        path.addCurve(to: CGPoint(x: 22.26188338, y: 17.59014517), control1: CGPoint(x: 22.75000000, y: 14.46351295), control2: CGPoint(x: 22.69958494, y: 16.64485725))
        path.addCurve(to: CGPoint(x: 20.08023728, y: 19.76369485), control1: CGPoint(x: 21.82418181, y: 18.53543310), control2: CGPoint(x: 21.02904638, y: 19.32761767))
        path.addCurve(to: CGPoint(x: 16.11749145, y: 20.25000000), control1: CGPoint(x: 19.13142818, y: 20.19977204), control2: CGPoint(x: 16.94195842, y: 20.25000000))
        path.addLine(to: CGPoint(x: 7.88250855, y: 20.25000000))
        path.addCurve(to: CGPoint(x: 3.91976272, y: 19.76369485), control1: CGPoint(x: 7.05804158, y: 20.25000000), control2: CGPoint(x: 4.86857182, y: 20.19977204))
        path.addCurve(to: CGPoint(x: 1.73811662, y: 17.59014517), control1: CGPoint(x: 2.97095362, y: 19.32761767), control2: CGPoint(x: 2.17581819, y: 18.53543310))
        path.addCurve(to: CGPoint(x: 1.25000000, y: 13.64210570), control1: CGPoint(x: 1.30041506, y: 16.64485725), control2: CGPoint(x: 1.25000000, y: 14.46351295))
        path.addLine(to: CGPoint(x: 1.25000000, y: 10.35789430))
        path.addCurve(to: CGPoint(x: 1.73811662, y: 6.40985483), control1: CGPoint(x: 1.25000000, y: 9.53648705), control2: CGPoint(x: 1.30041506, y: 7.35514275))
        path.addCurve(to: CGPoint(x: 3.91976272, y: 4.23630515), control1: CGPoint(x: 2.17581819, y: 5.46456690), control2: CGPoint(x: 2.97095362, y: 4.67238233))
        path.addCurve(to: CGPoint(x: 7.88250855, y: 3.75000000), control1: CGPoint(x: 4.86857182, y: 3.80022796), control2: CGPoint(x: 7.05804158, y: 3.75000000))
        path.closeSubpath()
        path.move(to: CGPoint(x: 7.92822470, y: 5.25000000))
        path.addLine(to: CGPoint(x: 16.07177530, y: 5.25000000))
        path.addCurve(to: CGPoint(x: 19.36952600, y: 5.58645022), control1: CGPoint(x: 17.13560350, y: 5.25000000), control2: CGPoint(x: 18.69691244, y: 5.33337487))
        path.addCurve(to: CGPoint(x: 20.91129224, y: 7.11794034), control1: CGPoint(x: 20.04213955, y: 5.83952557), control2: CGPoint(x: 20.65651878, y: 6.44980986))
        path.addCurve(to: CGPoint(x: 21.25000000, y: 10.39371099), control1: CGPoint(x: 21.16606570, y: 7.78607082), control2: CGPoint(x: 21.25000000, y: 9.33697338))
        path.addLine(to: CGPoint(x: 21.25000000, y: 13.60628901))
        path.addCurve(to: CGPoint(x: 20.91129224, y: 16.88205966), control1: CGPoint(x: 21.25000000, y: 14.66302662), control2: CGPoint(x: 21.16606570, y: 16.21392918))
        path.addCurve(to: CGPoint(x: 19.36952600, y: 18.41354978), control1: CGPoint(x: 20.65651878, y: 17.55019014), control2: CGPoint(x: 20.04213955, y: 18.16047443))
        path.addCurve(to: CGPoint(x: 16.07177530, y: 18.75000000), control1: CGPoint(x: 18.69691244, y: 18.66662513), control2: CGPoint(x: 17.13560350, y: 18.75000000))
        path.addLine(to: CGPoint(x: 7.92822470, y: 18.75000000))
        path.addCurve(to: CGPoint(x: 4.63047400, y: 18.41354978), control1: CGPoint(x: 6.86439650, y: 18.75000000), control2: CGPoint(x: 5.30308756, y: 18.66662513))
        path.addCurve(to: CGPoint(x: 3.08870776, y: 16.88205966), control1: CGPoint(x: 3.95786045, y: 18.16047443), control2: CGPoint(x: 3.34348122, y: 17.55019014))
        path.addCurve(to: CGPoint(x: 2.75000000, y: 13.60628901), control1: CGPoint(x: 2.83393430, y: 16.21392918), control2: CGPoint(x: 2.75000000, y: 14.66302662))
        path.addLine(to: CGPoint(x: 2.75000000, y: 10.39371099))
        path.addCurve(to: CGPoint(x: 3.08870776, y: 7.11794034), control1: CGPoint(x: 2.75000000, y: 9.33697338), control2: CGPoint(x: 2.83393430, y: 7.78607082))
        path.addCurve(to: CGPoint(x: 4.63047400, y: 5.58645022), control1: CGPoint(x: 3.34348122, y: 6.44980986), control2: CGPoint(x: 3.95786045, y: 5.83952557))
        path.addCurve(to: CGPoint(x: 7.92822470, y: 5.25000000), control1: CGPoint(x: 5.30308756, y: 5.33337487), control2: CGPoint(x: 6.86439650, y: 5.25000000))
        path.closeSubpath()

        for y: CGFloat in [9, 12] {
            for x: CGFloat in [6.375, 10.125, 13.875, 17.625] {
                addKey(to: &path, center: CGPoint(x: x, y: y), width: 2.5)
            }
        }
        addKey(to: &path, center: CGPoint(x: 6.25, y: 15), width: 2.5)
        addKey(to: &path, center: CGPoint(x: 12, y: 15), width: 6.5)
        addKey(to: &path, center: CGPoint(x: 17.75, y: 15), width: 2.5)
        return path
    }

    private static func addKey(to path: inout Path, center: CGPoint, width: CGFloat) {
        let radius: CGFloat = 0.75
        let handle = radius * 0.5522847498307936
        let left = center.x - width / 2
        let right = center.x + width / 2
        let top = center.y - radius
        let bottom = center.y + radius
        path.move(to: CGPoint(x: left + radius, y: top))
        path.addLine(to: CGPoint(x: right - radius, y: top))
        path.addCurve(to: CGPoint(x: right, y: center.y),
                      control1: CGPoint(x: right - radius + handle, y: top),
                      control2: CGPoint(x: right, y: center.y - handle))
        path.addCurve(to: CGPoint(x: right - radius, y: bottom),
                      control1: CGPoint(x: right, y: center.y + handle),
                      control2: CGPoint(x: right - radius + handle, y: bottom))
        path.addLine(to: CGPoint(x: left + radius, y: bottom))
        path.addCurve(to: CGPoint(x: left, y: center.y),
                      control1: CGPoint(x: left + radius - handle, y: bottom),
                      control2: CGPoint(x: left, y: center.y + handle))
        path.addCurve(to: CGPoint(x: left + radius, y: top),
                      control1: CGPoint(x: left, y: center.y - handle),
                      control2: CGPoint(x: left + radius - handle, y: top))
        path.closeSubpath()
    }
}
