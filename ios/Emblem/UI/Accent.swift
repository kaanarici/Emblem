import SwiftUI
import UIKit

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "theme.appearance"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

enum Accent: String, CaseIterable, Identifiable {
    case aluminum, blue, cyan, green, lime, yellow, orange, pink, magenta, purple, black

    static let storageKey = "theme.accent"

    var id: Self { self }

    var title: String { self == .black ? "Space Black" : rawValue.capitalized }

    private var rgb: UInt32 {
        switch self {
        case .aluminum: 0xCDCFD2
        case .blue: 0x5B78A0
        case .cyan: 0x5E9DA9
        case .green: 0x5D7F65
        case .lime: 0xA6B565
        case .yellow: 0xD8BE6E
        case .orange: 0xCC7646
        case .pink: 0xD69CAD
        case .magenta: 0x9F527F
        case .purple: 0x77689F
        case .black: 0x2F3033
        }
    }

    var color: Color { Color(uiColor: UIColor(rgb: rgb)) }

    var glyph: Color {
        switch self {
        case .blue, .cyan, .green, .magenta, .purple, .black: .white
        default: Color(uiColor: UIColor(rgb: 0x1D1D1F))
        }
    }

    var isNeutral: Bool { self == .aluminum || self == .black }

    func tint(_ neutral: Color) -> Color { isNeutral ? neutral : color }

    var wash: SIMD3<Float> {
        guard !isNeutral else { return SIMD3(1, 1, 1) }
        let channels = SIMD3<Float>(Float((rgb >> 16) & 0xFF), Float((rgb >> 8) & 0xFF), Float(rgb & 0xFF)) / 255
        return SIMD3(repeating: 1) - (SIMD3(repeating: 1) - channels / channels.max()) * 0.16
    }

    var washArgument: Shader.Argument { .float3(wash.x, wash.y, wash.z) }

    var swatch: UIImage {
        let size = CGSize(width: 22, height: 22)
        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let base = UIColor(rgb: rgb)
            let colors = [base.mixed(with: .white, by: 0.16), base, base.mixed(with: .black, by: 0.12)]
                .map(\.cgColor) as CFArray
            let cg = context.cgContext
            cg.addEllipse(in: rect)
            cg.clip()
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
            }
            cg.resetClip()
            UIColor.white.withAlphaComponent(0.55).setStroke()
            let chamfer = UIBezierPath(ovalIn: rect.insetBy(dx: 0.9, dy: 0.9))
            chamfer.lineWidth = 0.8
            chamfer.stroke()
            UIColor.black.withAlphaComponent(0.2).setStroke()
            let rim = UIBezierPath(ovalIn: rect)
            rim.lineWidth = 0.5
            rim.stroke()
        }.withRenderingMode(.alwaysOriginal)
    }
}

extension EnvironmentValues {
    @Entry var accent: Accent = .aluminum
}

extension View {
    func accentTint(_ neutral: Color) -> some View { modifier(AccentTint(neutral: neutral)) }
}

private struct AccentTint: ViewModifier {
    let neutral: Color
    @Environment(\.accent) private var accent

    func body(content: Content) -> some View { content.tint(accent.tint(neutral)) }
}

struct AnodizedSurface<S: InsettableShape>: View {
    let shape: S
    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let base = accent.color
        shape
            .fill(LinearGradient(
                stops: [
                    .init(color: base.mix(with: .white, by: 0.16), location: 0),
                    .init(color: base, location: 0.45),
                    .init(color: base.mix(with: .black, by: 0.12), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom))
            .overlay {
                shape.inset(by: 0.6).strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(scheme == .dark ? 0.6 : 0.8), location: 0),
                            .init(color: .white.opacity(0.26), location: 0.3),
                            .init(color: .white.opacity(0.1), location: 0.7),
                            .init(color: .white.opacity(0.3), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom),
                    lineWidth: 0.8)
            }
            .overlay {
                shape.strokeBorder(Color.black.opacity(scheme == .dark ? 0.5 : 0.16), lineWidth: 0.5)
            }
    }
}

private extension UIColor {
    func mixed(with other: UIColor, by amount: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount,
                       blue: b1 + (b2 - b1) * amount, alpha: 1)
    }
}
