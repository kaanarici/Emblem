import SwiftUI
import UIKit

struct CloseGlyph: View {
    enum Variant { case navigation, table }
    var variant: Variant = .navigation
    @Environment(\.displayScale) private var displayScale
    private static var tableRasters: [CGFloat: UIImage] = [:]

    var body: some View {
        Group {
            switch variant {
            case .navigation:
                CancelMark()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 24, height: 24)
            case .table:
                Image(uiImage: tableImage)
                    .renderingMode(.template)
                    .frame(width: 22, height: 22)
            }
        }
        .accessibilityHidden(true)
    }

    private var tableImage: UIImage {
        if let image = Self.tableRasters[displayScale] { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22), format: format).image { renderer in
            let context = renderer.cgContext
            context.setLineWidth(1.4)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setStrokeColor(UIColor.black.cgColor)
            context.translateBy(x: -0.2 / displayScale, y: 0.225 / displayScale)
            context.addPath(CancelMark().path(in: CGRect(x: 0, y: 0, width: 22, height: 22)).cgPath)
            context.strokePath()
        }
        Self.tableRasters[displayScale] = image
        return image
    }
}

private struct CancelMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 18, y: 6))
        path.addLine(to: CGPoint(x: 6.00081, y: 17.9992))
        path.move(to: CGPoint(x: 17.9992, y: 18))
        path.addLine(to: CGPoint(x: 6, y: 6.00085))
        return path.applying(CGAffineTransform(a: rect.width / 24, b: 0, c: 0, d: rect.height / 24,
                                               tx: rect.minX, ty: rect.minY))
    }
}
