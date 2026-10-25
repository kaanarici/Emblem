import SwiftUI

struct ChromeGlyph: View {
    enum Symbol: Equatable {
        case home, menu, expand, bookmark, calendar, calendarOutline, share, chevronLeft, chevronRight
        case image, camera, file, add, arrowUp, allBookmark, bubbleChat
    }

    let symbol: Symbol
    var size: CGFloat = 24
    var filled: Bool = false

    private var outlineStyle: StrokeStyle {
        StrokeStyle(lineWidth: size * 1.5 / 24, lineCap: .round, lineJoin: .round)
    }

    var body: some View {
        let shape = ChromeGlyphShape(symbol: symbol)
        Group {
            if symbol == .calendar || symbol == .calendarOutline {
                ZStack {
                    shape.fill()
                        .mask(alignment: .top) {
                            Rectangle().frame(height: size * 10 / 24)
                        }
                        .opacity(filled ? 1 : 0)
                    shape.stroke(style: StrokeStyle(
                        lineWidth: size * 1.5 / 24,
                        lineCap: .round,
                        lineJoin: .round))
                }
            } else if filled {
                switch symbol {
                case .home:
                    shape.fill(style: FillStyle(eoFill: true))
                        .overlay { shape.stroke(style: outlineStyle) }
                case .allBookmark:
                    ChromeGlyphShape(symbol: symbol, frontOnly: true).fill()
                        .overlay { shape.stroke(style: outlineStyle) }
                default:
                    shape.fill()
                }
            } else {
                shape.stroke(style: StrokeStyle(
                    lineWidth: size * 1.5 / 24,
                    lineCap: .round,
                    lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct ChromeGlyphShape: Shape {
    let symbol: ChromeGlyph.Symbol
    var frontOnly = false

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let transform = CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - 12 * scale, ty: rect.midY - 12 * scale)
        return ChromeGlyphPaths.path(for: symbol, frontOnly: frontOnly).applying(transform)
    }
}

private enum ChromeGlyphPaths {
    static func path(for symbol: ChromeGlyph.Symbol, frontOnly: Bool = false) -> Path {
        var path = Path()
        switch symbol {
        case .arrowUp:
            path.move(to: CGPoint(x: 12, y: 19.5))
            path.addLine(to: CGPoint(x: 12, y: 5))
            path.move(to: CGPoint(x: 17, y: 10))
            path.addLine(to: CGPoint(x: 12, y: 5))
            path.addLine(to: CGPoint(x: 7, y: 10))
        case .add:
            path.move(to: CGPoint(x: 12.001, y: 5.00003))
            path.addLine(to: CGPoint(x: 12.001, y: 19.002))
            path.move(to: CGPoint(x: 19.002, y: 12.002))
            path.addLine(to: CGPoint(x: 4.99998, y: 12.002))
        case .image: image(into: &path)
        case .camera: camera(into: &path)
        case .file: file(into: &path)
        case .home: home(into: &path)
        case .menu: menu(into: &path)
        case .expand: expand(into: &path)
        case .bookmark: bookmark(into: &path)
        case .allBookmark: allBookmark(into: &path, includeRear: !frontOnly)
        case .calendar: calendar(into: &path)
        case .calendarOutline: calendar(into: &path, includesDays: false)
        case .share: share(into: &path)
        case .bubbleChat: bubbleChat(into: &path)
        case .chevronLeft:
            path.move(to: CGPoint(x: 15, y: 18))
            path.addCurve(to: CGPoint(x: 9, y: 12), control1: CGPoint(x: 15, y: 18), control2: CGPoint(x: 9.00001, y: 13.5811))
            path.addCurve(to: CGPoint(x: 15, y: 6), control1: CGPoint(x: 8.99999, y: 10.4188), control2: CGPoint(x: 15, y: 6))
        case .chevronRight:
            path.move(to: CGPoint(x: 9.00005, y: 18))
            path.addCurve(to: CGPoint(x: 15, y: 12), control1: CGPoint(x: 9.00005, y: 18), control2: CGPoint(x: 15, y: 13.5811))
            path.addCurve(to: CGPoint(x: 9, y: 6), control1: CGPoint(x: 15, y: 10.4188), control2: CGPoint(x: 9, y: 6))
        }
        return path
    }

    private static func home(into path: inout Path) {
        path.move(to: CGPoint(x: 3, y: 11.9896))
        path.addLine(to: CGPoint(x: 3, y: 14.5))
        path.addCurve(to: CGPoint(x: 4.02513, y: 20.4749), control1: CGPoint(x: 3, y: 17.7998), control2: CGPoint(x: 3, y: 19.4497))
        path.addCurve(to: CGPoint(x: 10, y: 21.5), control1: CGPoint(x: 5.05025, y: 21.5), control2: CGPoint(x: 6.70017, y: 21.5))
        path.addLine(to: CGPoint(x: 14, y: 21.5))
        path.addCurve(to: CGPoint(x: 19.9749, y: 20.4749), control1: CGPoint(x: 17.2998, y: 21.5), control2: CGPoint(x: 18.9497, y: 21.5))
        path.addCurve(to: CGPoint(x: 21, y: 14.5), control1: CGPoint(x: 21, y: 19.4497), control2: CGPoint(x: 21, y: 17.7998))
        path.addLine(to: CGPoint(x: 21, y: 11.9896))
        path.addCurve(to: CGPoint(x: 20.6441, y: 8.74005), control1: CGPoint(x: 21, y: 10.3083), control2: CGPoint(x: 21, y: 9.46773))
        path.addCurve(to: CGPoint(x: 18.2976, y: 6.46411), control1: CGPoint(x: 20.2882, y: 8.01237), control2: CGPoint(x: 19.6247, y: 7.49628))
        path.addLine(to: CGPoint(x: 16.2976, y: 4.90855))
        path.addCurve(to: CGPoint(x: 12, y: 2.5), control1: CGPoint(x: 14.2331, y: 3.30285), control2: CGPoint(x: 13.2009, y: 2.5))
        path.addCurve(to: CGPoint(x: 7.70242, y: 4.90855), control1: CGPoint(x: 10.7991, y: 2.5), control2: CGPoint(x: 9.76689, y: 3.30285))
        path.addLine(to: CGPoint(x: 5.70241, y: 6.46411))
        path.addCurve(to: CGPoint(x: 3.3559, y: 8.74005), control1: CGPoint(x: 4.37533, y: 7.49628), control2: CGPoint(x: 3.71179, y: 8.01237))
        path.addCurve(to: CGPoint(x: 3, y: 11.9896), control1: CGPoint(x: 3, y: 9.46773), control2: CGPoint(x: 3, y: 10.3083))
        path.closeSubpath()
        path.move(to: CGPoint(x: 15, y: 21.5))
        path.addLine(to: CGPoint(x: 15, y: 16.5))
        path.addCurve(to: CGPoint(x: 14.5607, y: 13.9393), control1: CGPoint(x: 15, y: 15.0858), control2: CGPoint(x: 15, y: 14.3787))
        path.addCurve(to: CGPoint(x: 12, y: 13.5), control1: CGPoint(x: 14.1213, y: 13.5), control2: CGPoint(x: 13.4142, y: 13.5))
        path.addCurve(to: CGPoint(x: 9.43934, y: 13.9393), control1: CGPoint(x: 10.5858, y: 13.5), control2: CGPoint(x: 9.87868, y: 13.5))
        path.addCurve(to: CGPoint(x: 9, y: 16.5), control1: CGPoint(x: 9, y: 14.3787), control2: CGPoint(x: 9, y: 15.0858))
        path.addLine(to: CGPoint(x: 9, y: 21.5))
    }

    private static func menu(into path: inout Path) {
        path.move(to: CGPoint(x: 4, y: 5))
        path.addLine(to: CGPoint(x: 16, y: 5))
        path.move(to: CGPoint(x: 4, y: 12))
        path.addLine(to: CGPoint(x: 20, y: 12))
        path.move(to: CGPoint(x: 4, y: 19))
        path.addLine(to: CGPoint(x: 12, y: 19))
    }

    private static func expand(into path: inout Path) {
        path.move(to: CGPoint(x: 19, y: 12))
        path.addLine(to: CGPoint(x: 19, y: 8.99996))
        path.addCurve(to: CGPoint(x: 18.4142, y: 5.58577), control1: CGPoint(x: 19, y: 7.11435), control2: CGPoint(x: 18.9999, y: 6.17155))
        path.addCurve(to: CGPoint(x: 15, y: 5), control1: CGPoint(x: 17.8284, y: 4.99999), control2: CGPoint(x: 16.8856, y: 4.99999))
        path.addLine(to: CGPoint(x: 12, y: 5.00001))
        path.move(to: CGPoint(x: 5, y: 12))
        path.addLine(to: CGPoint(x: 5.00003, y: 15))
        path.addCurve(to: CGPoint(x: 5.58584, y: 18.4142), control1: CGPoint(x: 5.00004, y: 16.8856), control2: CGPoint(x: 5.00005, y: 17.8284))
        path.addCurve(to: CGPoint(x: 9.00004, y: 19), control1: CGPoint(x: 6.17163, y: 19), control2: CGPoint(x: 7.11443, y: 19))
        path.addLine(to: CGPoint(x: 12, y: 19))
    }

    private static func allBookmark(into path: inout Path, includeRear: Bool) {
        path.move(to: CGPoint(x: 3, y: 17.9808))
        path.addLine(to: CGPoint(x: 3, y: 12.7075))
        path.addCurve(to: CGPoint(x: 4.09835, y: 6.12874), control1: CGPoint(x: 3, y: 9.07416), control2: CGPoint(x: 3, y: 7.25748))
        path.addCurve(to: CGPoint(x: 10.5, y: 5), control1: CGPoint(x: 5.1967, y: 5), control2: CGPoint(x: 6.96447, y: 5))
        path.addCurve(to: CGPoint(x: 16.9017, y: 6.12874), control1: CGPoint(x: 14.0355, y: 5), control2: CGPoint(x: 15.8033, y: 5))
        path.addCurve(to: CGPoint(x: 18, y: 12.7075), control1: CGPoint(x: 18, y: 7.25748), control2: CGPoint(x: 18, y: 9.07416))
        path.addLine(to: CGPoint(x: 18, y: 17.9808))
        path.addCurve(to: CGPoint(x: 17.2755, y: 21.8523), control1: CGPoint(x: 18, y: 20.2867), control2: CGPoint(x: 18, y: 21.4396))
        path.addCurve(to: CGPoint(x: 11.9906, y: 19.1824), control1: CGPoint(x: 15.8724, y: 22.6514), control2: CGPoint(x: 13.2405, y: 19.9852))
        path.addCurve(to: CGPoint(x: 10.5, y: 18.484), control1: CGPoint(x: 11.2657, y: 18.7168), control2: CGPoint(x: 10.9033, y: 18.484))
        path.addCurve(to: CGPoint(x: 9.00938, y: 19.1824), control1: CGPoint(x: 10.0967, y: 18.484), control2: CGPoint(x: 9.73425, y: 18.7168))
        path.addCurve(to: CGPoint(x: 3.72454, y: 21.8523), control1: CGPoint(x: 7.7595, y: 19.9852), control2: CGPoint(x: 5.12763, y: 22.6514))
        path.addCurve(to: CGPoint(x: 3, y: 17.9808), control1: CGPoint(x: 3, y: 21.4396), control2: CGPoint(x: 3, y: 20.2867))
        path.closeSubpath()
        guard includeRear else { return }
        path.move(to: CGPoint(x: 9, y: 2))
        path.addLine(to: CGPoint(x: 11, y: 2))
        path.addCurve(to: CGPoint(x: 19.5355, y: 3.46447), control1: CGPoint(x: 15.714, y: 2), control2: CGPoint(x: 18.0711, y: 2))
        path.addCurve(to: CGPoint(x: 21, y: 12), control1: CGPoint(x: 21, y: 4.92893), control2: CGPoint(x: 21, y: 7.28595))
        path.addLine(to: CGPoint(x: 21, y: 18))
    }

    private static func bookmark(into path: inout Path) {
        path.move(to: CGPoint(x: 4, y: 17.9808))
        path.addLine(to: CGPoint(x: 4, y: 9.70753))
        path.addCurve(to: CGPoint(x: 5.17157, y: 3.12874), control1: CGPoint(x: 4, y: 6.07416), control2: CGPoint(x: 4, y: 4.25748))
        path.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 6.34315, y: 2), control2: CGPoint(x: 8.22876, y: 2))
        path.addCurve(to: CGPoint(x: 18.8284, y: 3.12874), control1: CGPoint(x: 15.7712, y: 2), control2: CGPoint(x: 17.6569, y: 2))
        path.addCurve(to: CGPoint(x: 20, y: 9.70753), control1: CGPoint(x: 20, y: 4.25748), control2: CGPoint(x: 20, y: 6.07416))
        path.addLine(to: CGPoint(x: 20, y: 17.9808))
        path.addCurve(to: CGPoint(x: 19.2272, y: 21.8523), control1: CGPoint(x: 20, y: 20.2867), control2: CGPoint(x: 20, y: 21.4396))
        path.addCurve(to: CGPoint(x: 13.59, y: 19.1824), control1: CGPoint(x: 17.7305, y: 22.6514), control2: CGPoint(x: 14.9232, y: 19.9852))
        path.addCurve(to: CGPoint(x: 12, y: 18.484), control1: CGPoint(x: 12.8168, y: 18.7168), control2: CGPoint(x: 12.4302, y: 18.484))
        path.addCurve(to: CGPoint(x: 10.41, y: 19.1824), control1: CGPoint(x: 11.5698, y: 18.484), control2: CGPoint(x: 11.1832, y: 18.7168))
        path.addCurve(to: CGPoint(x: 4.77285, y: 21.8523), control1: CGPoint(x: 9.0768, y: 19.9852), control2: CGPoint(x: 6.26947, y: 22.6514))
        path.addCurve(to: CGPoint(x: 4, y: 17.9808), control1: CGPoint(x: 4, y: 21.4396), control2: CGPoint(x: 4, y: 20.2867))
        path.closeSubpath()
    }

    private static func bubbleChat(into path: inout Path) {
        path.move(to: CGPoint(x: 21.5, y: 12))
        path.addCurve(to: CGPoint(x: 12, y: 21.5), control1: CGPoint(x: 21.5, y: 17.2467), control2: CGPoint(x: 17.2467, y: 21.5))
        path.addCurve(to: CGPoint(x: 7.5, y: 20.3687), control1: CGPoint(x: 10.3719, y: 21.5), control2: CGPoint(x: 8.8394, y: 21.0904))
        path.addCurve(to: CGPoint(x: 3.26592, y: 20.4658), control1: CGPoint(x: 5.63177, y: 19.362), control2: CGPoint(x: 4.37462, y: 20.2979))
        path.addCurve(to: CGPoint(x: 2.80997, y: 20.31), control1: CGPoint(x: 3.09774, y: 20.4913), control2: CGPoint(x: 2.93024, y: 20.4302))
        path.addCurve(to: CGPoint(x: 2.6935, y: 19.6074), control1: CGPoint(x: 2.62741, y: 20.1274), control2: CGPoint(x: 2.59266, y: 19.8451))
        path.addCurve(to: CGPoint(x: 2.98341, y: 15), control1: CGPoint(x: 3.12865, y: 18.5818), control2: CGPoint(x: 3.5282, y: 16.6382))
        path.addCurve(to: CGPoint(x: 2.5, y: 12), control1: CGPoint(x: 2.6698, y: 14.057), control2: CGPoint(x: 2.5, y: 13.0483))
        path.addCurve(to: CGPoint(x: 12, y: 2.5), control1: CGPoint(x: 2.5, y: 6.75329), control2: CGPoint(x: 6.75329, y: 2.5))
        path.addCurve(to: CGPoint(x: 21.5, y: 12), control1: CGPoint(x: 17.2467, y: 2.5), control2: CGPoint(x: 21.5, y: 6.75329))
        path.closeSubpath()
        for x in [8.0, 12.0, 16.0] {
            path.addEllipse(in: CGRect(x: x - 0.25, y: 11.75, width: 0.5, height: 0.5))
        }
    }

    private static func share(into path: inout Path) {
        path.move(to: CGPoint(x: 8, y: 7))
        path.addCurve(to: CGPoint(x: 11.4044, y: 3.23889), control1: CGPoint(x: 8, y: 7), control2: CGPoint(x: 10.1958, y: 4.28386))
        path.addCurve(to: CGPoint(x: 12.0337, y: 3.00072), control1: CGPoint(x: 11.5987, y: 3.0709), control2: CGPoint(x: 11.8169, y: 2.99152))
        path.addCurve(to: CGPoint(x: 12.5958, y: 3.23912), control1: CGPoint(x: 12.2282, y: 3.00897), control2: CGPoint(x: 12.4215, y: 3.08844))
        path.addCurve(to: CGPoint(x: 16, y: 7), control1: CGPoint(x: 13.8041, y: 4.28428), control2: CGPoint(x: 16, y: 7))
        path.move(to: CGPoint(x: 12.0337, y: 4))
        path.addLine(to: CGPoint(x: 12.0337, y: 15))
        path.move(to: CGPoint(x: 8, y: 11))
        path.addCurve(to: CGPoint(x: 5.36502, y: 11.2725), control1: CGPoint(x: 6.59987, y: 11), control2: CGPoint(x: 5.8998, y: 11))
        path.addCurve(to: CGPoint(x: 4.27248, y: 12.365), control1: CGPoint(x: 4.89462, y: 11.5122), control2: CGPoint(x: 4.51217, y: 11.8946))
        path.addCurve(to: CGPoint(x: 4, y: 15), control1: CGPoint(x: 4, y: 12.8998), control2: CGPoint(x: 4, y: 13.5999))
        path.addLine(to: CGPoint(x: 4, y: 16))
        path.addCurve(to: CGPoint(x: 4.73223, y: 20.2678), control1: CGPoint(x: 4, y: 18.357), control2: CGPoint(x: 4, y: 19.5355))
        path.addCurve(to: CGPoint(x: 9, y: 21), control1: CGPoint(x: 5.46447, y: 21), control2: CGPoint(x: 6.64298, y: 21))
        path.addLine(to: CGPoint(x: 15, y: 21))
        path.addCurve(to: CGPoint(x: 19.2678, y: 20.2678), control1: CGPoint(x: 17.357, y: 21), control2: CGPoint(x: 18.5355, y: 21))
        path.addCurve(to: CGPoint(x: 20, y: 16), control1: CGPoint(x: 20, y: 19.5355), control2: CGPoint(x: 20, y: 18.357))
        path.addLine(to: CGPoint(x: 20, y: 15))
        path.addCurve(to: CGPoint(x: 19.7275, y: 12.365), control1: CGPoint(x: 20, y: 13.5999), control2: CGPoint(x: 20, y: 12.8998))
        path.addCurve(to: CGPoint(x: 18.635, y: 11.2725), control1: CGPoint(x: 19.4878, y: 11.8946), control2: CGPoint(x: 19.1054, y: 11.5122))
        path.addCurve(to: CGPoint(x: 16, y: 11), control1: CGPoint(x: 18.1002, y: 11), control2: CGPoint(x: 17.4001, y: 11))
    }

    private static func calendar(into path: inout Path, includesDays: Bool = true) {
        path.move(to: CGPoint(x: 16, y: 2))
        path.addLine(to: CGPoint(x: 16, y: 6))
        path.move(to: CGPoint(x: 8, y: 2))
        path.addLine(to: CGPoint(x: 8, y: 6))
        path.move(to: CGPoint(x: 13, y: 4))
        path.addLine(to: CGPoint(x: 11, y: 4))
        path.addCurve(to: CGPoint(x: 4.17157, y: 5.17157), control1: CGPoint(x: 7.22876, y: 4), control2: CGPoint(x: 5.34315, y: 4))
        path.addCurve(to: CGPoint(x: 3, y: 12), control1: CGPoint(x: 3, y: 6.34315), control2: CGPoint(x: 3, y: 8.22876))
        path.addLine(to: CGPoint(x: 3, y: 14))
        path.addCurve(to: CGPoint(x: 4.17157, y: 20.8284), control1: CGPoint(x: 3, y: 17.7712), control2: CGPoint(x: 3, y: 19.6569))
        path.addCurve(to: CGPoint(x: 11, y: 22), control1: CGPoint(x: 5.34315, y: 22), control2: CGPoint(x: 7.22876, y: 22))
        path.addLine(to: CGPoint(x: 13, y: 22))
        path.addCurve(to: CGPoint(x: 19.8284, y: 20.8284), control1: CGPoint(x: 16.7712, y: 22), control2: CGPoint(x: 18.6569, y: 22))
        path.addCurve(to: CGPoint(x: 21, y: 14), control1: CGPoint(x: 21, y: 19.6569), control2: CGPoint(x: 21, y: 17.7712))
        path.addLine(to: CGPoint(x: 21, y: 12))
        path.addCurve(to: CGPoint(x: 19.8284, y: 5.17157), control1: CGPoint(x: 21, y: 8.22876), control2: CGPoint(x: 21, y: 6.34315))
        path.addCurve(to: CGPoint(x: 13, y: 4), control1: CGPoint(x: 18.6569, y: 4), control2: CGPoint(x: 16.7712, y: 4))
        path.closeSubpath()
        path.move(to: CGPoint(x: 3, y: 10))
        path.addLine(to: CGPoint(x: 21, y: 10))
        guard includesDays else { return }
        path.move(to: CGPoint(x: 12.1258, y: 14))
        path.addLine(to: CGPoint(x: 12.0008, y: 14))
        path.move(to: CGPoint(x: 12.1258, y: 18))
        path.addLine(to: CGPoint(x: 12.0008, y: 18))
        path.move(to: CGPoint(x: 7.625, y: 14))
        path.addLine(to: CGPoint(x: 7.5, y: 14))
        path.move(to: CGPoint(x: 7.625, y: 18))
        path.addLine(to: CGPoint(x: 7.5, y: 18))
        path.move(to: CGPoint(x: 16.625, y: 14))
        path.addLine(to: CGPoint(x: 16.5, y: 14))
        path.move(to: CGPoint(x: 12.2508, y: 14))
        path.addCurve(to: CGPoint(x: 12.0008, y: 14.25), control1: CGPoint(x: 12.2508, y: 14.1381), control2: CGPoint(x: 12.1389, y: 14.25))
        path.addCurve(to: CGPoint(x: 11.7508, y: 14), control1: CGPoint(x: 11.8628, y: 14.25), control2: CGPoint(x: 11.7508, y: 14.1381))
        path.addCurve(to: CGPoint(x: 12.0008, y: 13.75), control1: CGPoint(x: 11.7508, y: 13.8619), control2: CGPoint(x: 11.8628, y: 13.75))
        path.addCurve(to: CGPoint(x: 12.2508, y: 14), control1: CGPoint(x: 12.1389, y: 13.75), control2: CGPoint(x: 12.2508, y: 13.8619))
        path.closeSubpath()
        path.move(to: CGPoint(x: 12.2508, y: 18))
        path.addCurve(to: CGPoint(x: 12.0008, y: 18.25), control1: CGPoint(x: 12.2508, y: 18.1381), control2: CGPoint(x: 12.1389, y: 18.25))
        path.addCurve(to: CGPoint(x: 11.7508, y: 18), control1: CGPoint(x: 11.8628, y: 18.25), control2: CGPoint(x: 11.7508, y: 18.1381))
        path.addCurve(to: CGPoint(x: 12.0008, y: 17.75), control1: CGPoint(x: 11.7508, y: 17.8619), control2: CGPoint(x: 11.8628, y: 17.75))
        path.addCurve(to: CGPoint(x: 12.2508, y: 18), control1: CGPoint(x: 12.1389, y: 17.75), control2: CGPoint(x: 12.2508, y: 17.8619))
        path.closeSubpath()
        path.move(to: CGPoint(x: 7.75, y: 14))
        path.addCurve(to: CGPoint(x: 7.5, y: 14.25), control1: CGPoint(x: 7.75, y: 14.1381), control2: CGPoint(x: 7.63807, y: 14.25))
        path.addCurve(to: CGPoint(x: 7.25, y: 14), control1: CGPoint(x: 7.36193, y: 14.25), control2: CGPoint(x: 7.25, y: 14.1381))
        path.addCurve(to: CGPoint(x: 7.5, y: 13.75), control1: CGPoint(x: 7.25, y: 13.8619), control2: CGPoint(x: 7.36193, y: 13.75))
        path.addCurve(to: CGPoint(x: 7.75, y: 14), control1: CGPoint(x: 7.63807, y: 13.75), control2: CGPoint(x: 7.75, y: 13.8619))
        path.closeSubpath()
        path.move(to: CGPoint(x: 7.75, y: 18))
        path.addCurve(to: CGPoint(x: 7.5, y: 18.25), control1: CGPoint(x: 7.75, y: 18.1381), control2: CGPoint(x: 7.63807, y: 18.25))
        path.addCurve(to: CGPoint(x: 7.25, y: 18), control1: CGPoint(x: 7.36193, y: 18.25), control2: CGPoint(x: 7.25, y: 18.1381))
        path.addCurve(to: CGPoint(x: 7.5, y: 17.75), control1: CGPoint(x: 7.25, y: 17.8619), control2: CGPoint(x: 7.36193, y: 17.75))
        path.addCurve(to: CGPoint(x: 7.75, y: 18), control1: CGPoint(x: 7.63807, y: 17.75), control2: CGPoint(x: 7.75, y: 17.8619))
        path.closeSubpath()
        path.move(to: CGPoint(x: 16.75, y: 14))
        path.addCurve(to: CGPoint(x: 16.5, y: 14.25), control1: CGPoint(x: 16.75, y: 14.1381), control2: CGPoint(x: 16.6381, y: 14.25))
        path.addCurve(to: CGPoint(x: 16.25, y: 14), control1: CGPoint(x: 16.3619, y: 14.25), control2: CGPoint(x: 16.25, y: 14.1381))
        path.addCurve(to: CGPoint(x: 16.5, y: 13.75), control1: CGPoint(x: 16.25, y: 13.8619), control2: CGPoint(x: 16.3619, y: 13.75))
        path.addCurve(to: CGPoint(x: 16.75, y: 14), control1: CGPoint(x: 16.6381, y: 13.75), control2: CGPoint(x: 16.75, y: 13.8619))
        path.closeSubpath()
    }

    private static func image(into path: inout Path) {
        path.addEllipse(in: CGRect(x: 6, y: 6, width: 3, height: 3))
        path.move(to: CGPoint(x: 2.5, y: 12))
        path.addCurve(to: CGPoint(x: 3.89124, y: 3.89124), control1: CGPoint(x: 2.5, y: 7.52166), control2: CGPoint(x: 2.5, y: 5.28249))
        path.addCurve(to: CGPoint(x: 12, y: 2.5), control1: CGPoint(x: 5.28249, y: 2.5), control2: CGPoint(x: 7.52166, y: 2.5))
        path.addCurve(to: CGPoint(x: 20.1088, y: 3.89124), control1: CGPoint(x: 16.4783, y: 2.5), control2: CGPoint(x: 18.7175, y: 2.5))
        path.addCurve(to: CGPoint(x: 21.5, y: 12), control1: CGPoint(x: 21.5, y: 5.28249), control2: CGPoint(x: 21.5, y: 7.52166))
        path.addCurve(to: CGPoint(x: 20.1088, y: 20.1088), control1: CGPoint(x: 21.5, y: 16.4783), control2: CGPoint(x: 21.5, y: 18.7175))
        path.addCurve(to: CGPoint(x: 12, y: 21.5), control1: CGPoint(x: 18.7175, y: 21.5), control2: CGPoint(x: 16.4783, y: 21.5))
        path.addCurve(to: CGPoint(x: 3.89124, y: 20.1088), control1: CGPoint(x: 7.52166, y: 21.5), control2: CGPoint(x: 5.28249, y: 21.5))
        path.addCurve(to: CGPoint(x: 2.5, y: 12), control1: CGPoint(x: 2.5, y: 18.7175), control2: CGPoint(x: 2.5, y: 16.4783))
        path.closeSubpath()
        path.move(to: CGPoint(x: 5, y: 21))
        path.addCurve(to: CGPoint(x: 21.4975, y: 13.5424), control1: CGPoint(x: 9.37246, y: 15.775), control2: CGPoint(x: 14.2741, y: 8.88406))
    }

    private static func camera(into path: inout Path) {
        path.move(to: CGPoint(x: 12.6974, y: 3.5))
        path.addLine(to: CGPoint(x: 11.303, y: 3.5))
        path.addCurve(to: CGPoint(x: 9.91067, y: 3.612), control1: CGPoint(x: 10.5884, y: 3.5), control2: CGPoint(x: 10.2311, y: 3.5))
        path.addCurve(to: CGPoint(x: 9.36568, y: 3.90367), control1: CGPoint(x: 9.71499, y: 3.68039), control2: CGPoint(x: 9.53113, y: 3.77879))
        path.addCurve(to: CGPoint(x: 8.50018, y: 5), control1: CGPoint(x: 9.09474, y: 4.10816), control2: CGPoint(x: 8.89655, y: 4.40544))
        path.addLine(to: CGPoint(x: 8.50017, y: 5.00001))
        path.addCurve(to: CGPoint(x: 7.87867, y: 5.87871), control1: CGPoint(x: 8.29717, y: 5.30453), control2: CGPoint(x: 7.99794, y: 5.75337))
        path.addCurve(to: CGPoint(x: 6.77329, y: 6.47029), control1: CGPoint(x: 7.58314, y: 6.18927), control2: CGPoint(x: 7.19563, y: 6.39666))
        path.addCurve(to: CGPoint(x: 6.05387, y: 6.5), control1: CGPoint(x: 6.60284, y: 6.5), control2: CGPoint(x: 6.41985, y: 6.5))
        path.addCurve(to: CGPoint(x: 4.18307, y: 6.61342), control1: CGPoint(x: 5.07379, y: 6.5), control2: CGPoint(x: 4.58376, y: 6.5))
        path.addCurve(to: CGPoint(x: 2.1136, y: 8.68289), control1: CGPoint(x: 3.18074, y: 6.89716), control2: CGPoint(x: 2.39734, y: 7.68055))
        path.addCurve(to: CGPoint(x: 2.00018, y: 10.5537), control1: CGPoint(x: 2.00018, y: 9.08357), control2: CGPoint(x: 2.00018, y: 9.57361))
        path.addLine(to: CGPoint(x: 2.00018, y: 14.5))
        path.addCurve(to: CGPoint(x: 2.87886, y: 19.6213), control1: CGPoint(x: 2.00018, y: 17.3284), control2: CGPoint(x: 2.00018, y: 18.7426))
        path.addCurve(to: CGPoint(x: 8.00018, y: 20.5), control1: CGPoint(x: 3.75754, y: 20.5), control2: CGPoint(x: 5.17176, y: 20.5))
        path.addLine(to: CGPoint(x: 16.0002, y: 20.5))
        path.addCurve(to: CGPoint(x: 21.1215, y: 19.6213), control1: CGPoint(x: 18.8286, y: 20.5), control2: CGPoint(x: 20.2428, y: 20.5))
        path.addCurve(to: CGPoint(x: 22.0002, y: 14.5), control1: CGPoint(x: 22.0002, y: 18.7426), control2: CGPoint(x: 22.0002, y: 17.3284))
        path.addLine(to: CGPoint(x: 22.0002, y: 10.5537))
        path.addCurve(to: CGPoint(x: 21.8868, y: 8.68289), control1: CGPoint(x: 22.0002, y: 9.57361), control2: CGPoint(x: 22.0002, y: 9.08357))
        path.addCurve(to: CGPoint(x: 19.8173, y: 6.61342), control1: CGPoint(x: 21.603, y: 7.68055), control2: CGPoint(x: 20.8196, y: 6.89716))
        path.addCurve(to: CGPoint(x: 17.9465, y: 6.5), control1: CGPoint(x: 19.4166, y: 6.5), control2: CGPoint(x: 18.9266, y: 6.5))
        path.addCurve(to: CGPoint(x: 17.2271, y: 6.47029), control1: CGPoint(x: 17.5805, y: 6.5), control2: CGPoint(x: 17.3975, y: 6.5))
        path.addCurve(to: CGPoint(x: 16.1217, y: 5.87871), control1: CGPoint(x: 16.8047, y: 6.39666), control2: CGPoint(x: 16.4172, y: 6.18927))
        path.addCurve(to: CGPoint(x: 15.5002, y: 5), control1: CGPoint(x: 16.0024, y: 5.75336), control2: CGPoint(x: 15.7032, y: 5.30451))
        path.addCurve(to: CGPoint(x: 14.6347, y: 3.90367), control1: CGPoint(x: 15.1038, y: 4.40544), control2: CGPoint(x: 14.9056, y: 4.10816))
        path.addCurve(to: CGPoint(x: 14.0897, y: 3.612), control1: CGPoint(x: 14.4692, y: 3.77879), control2: CGPoint(x: 14.2854, y: 3.68039))
        path.addCurve(to: CGPoint(x: 12.6974, y: 3.5), control1: CGPoint(x: 13.7693, y: 3.5), control2: CGPoint(x: 13.412, y: 3.5))
        path.closeSubpath()
        path.move(to: CGPoint(x: 16.0002, y: 13))
        path.addCurve(to: CGPoint(x: 12.0002, y: 17), control1: CGPoint(x: 16.0002, y: 15.2091), control2: CGPoint(x: 14.2093, y: 17))
        path.addCurve(to: CGPoint(x: 8.00018, y: 13), control1: CGPoint(x: 9.79104, y: 17), control2: CGPoint(x: 8.00018, y: 15.2091))
        path.addCurve(to: CGPoint(x: 12.0002, y: 9), control1: CGPoint(x: 8.00018, y: 10.7909), control2: CGPoint(x: 9.79104, y: 9))
        path.addCurve(to: CGPoint(x: 16.0002, y: 13), control1: CGPoint(x: 14.2093, y: 9), control2: CGPoint(x: 16.0002, y: 10.7909))
        path.closeSubpath()
        path.move(to: CGPoint(x: 19.1252, y: 9.5))
        path.addLine(to: CGPoint(x: 19.0002, y: 9.5))
        path.move(to: CGPoint(x: 19.2502, y: 9.5))
        path.addCurve(to: CGPoint(x: 19.0002, y: 9.75), control1: CGPoint(x: 19.2502, y: 9.63807), control2: CGPoint(x: 19.1383, y: 9.75))
        path.addCurve(to: CGPoint(x: 18.7502, y: 9.5), control1: CGPoint(x: 18.8621, y: 9.75), control2: CGPoint(x: 18.7502, y: 9.63807))
        path.addCurve(to: CGPoint(x: 19.0002, y: 9.25), control1: CGPoint(x: 18.7502, y: 9.36193), control2: CGPoint(x: 18.8621, y: 9.25))
        path.addCurve(to: CGPoint(x: 19.2502, y: 9.5), control1: CGPoint(x: 19.1383, y: 9.25), control2: CGPoint(x: 19.2502, y: 9.36193))
        path.closeSubpath()
    }

    private static func file(into path: inout Path) {
        path.move(to: CGPoint(x: 8, y: 7))
        path.addLine(to: CGPoint(x: 16, y: 7))
        path.move(to: CGPoint(x: 8, y: 11))
        path.addLine(to: CGPoint(x: 12, y: 11))
        path.move(to: CGPoint(x: 13, y: 21.5))
        path.addLine(to: CGPoint(x: 13, y: 21))
        path.addCurve(to: CGPoint(x: 13.8787, y: 15.8787), control1: CGPoint(x: 13, y: 18.1716), control2: CGPoint(x: 13, y: 16.7574))
        path.addCurve(to: CGPoint(x: 19, y: 15), control1: CGPoint(x: 14.7574, y: 15), control2: CGPoint(x: 16.1716, y: 15))
        path.addLine(to: CGPoint(x: 19.5, y: 15))
        path.move(to: CGPoint(x: 20, y: 13.3431))
        path.addLine(to: CGPoint(x: 20, y: 10))
        path.addCurve(to: CGPoint(x: 18.8284, y: 3.17157), control1: CGPoint(x: 20, y: 6.22876), control2: CGPoint(x: 20, y: 4.34315))
        path.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 17.6569, y: 2), control2: CGPoint(x: 15.7712, y: 2))
        path.addCurve(to: CGPoint(x: 5.17157, y: 3.17157), control1: CGPoint(x: 8.22877, y: 2), control2: CGPoint(x: 6.34315, y: 2))
        path.addCurve(to: CGPoint(x: 4, y: 10), control1: CGPoint(x: 4, y: 4.34314), control2: CGPoint(x: 4, y: 6.22876))
        path.addLine(to: CGPoint(x: 4, y: 14.5442))
        path.addCurve(to: CGPoint(x: 4.88607, y: 20.5107), control1: CGPoint(x: 4, y: 17.7892), control2: CGPoint(x: 4, y: 19.4117))
        path.addCurve(to: CGPoint(x: 5.48933, y: 21.1139), control1: CGPoint(x: 5.06508, y: 20.7327), control2: CGPoint(x: 5.26731, y: 20.9349))
        path.addCurve(to: CGPoint(x: 11.4558, y: 22), control1: CGPoint(x: 6.58831, y: 22), control2: CGPoint(x: 8.21082, y: 22))
        path.addCurve(to: CGPoint(x: 12.8372, y: 21.886), control1: CGPoint(x: 12.1614, y: 22), control2: CGPoint(x: 12.5141, y: 22))
        path.addCurve(to: CGPoint(x: 13.0345, y: 21.8043), control1: CGPoint(x: 12.9044, y: 21.8623), control2: CGPoint(x: 12.9702, y: 21.835))
        path.addCurve(to: CGPoint(x: 14.0919, y: 20.9081), control1: CGPoint(x: 13.3436, y: 21.6564), control2: CGPoint(x: 13.593, y: 21.407))
        path.addLine(to: CGPoint(x: 18.8284, y: 16.1716))
        path.addCurve(to: CGPoint(x: 19.8478, y: 14.9369), control1: CGPoint(x: 19.4065, y: 15.5935), control2: CGPoint(x: 19.6955, y: 15.3045))
        path.addCurve(to: CGPoint(x: 20, y: 13.3431), control1: CGPoint(x: 20, y: 14.5694), control2: CGPoint(x: 20, y: 14.1606))
        path.closeSubpath()
    }
}
