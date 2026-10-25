import SwiftUI

enum Theme {
    static let background = adaptive(light: 0xEEEEF1, dark: 0x111113)
    static let responsePaper = adaptive(light: 0xFFFFFF, dark: 0x161618)
    static let responseCanvas = adaptive(light: 0xF5F4F0, dark: 0x0F0F11)
    static let responseComparisonCanvas = adaptive(light: 0xFCFCFC, dark: 0x131315)
    static let sidebarBackground = adaptive(light: 0xF5F5F5, dark: 0x0C0C0E)
    static let listeningWash = adaptive(light: 0xECECEE, dark: 0x1B1B1F)
    static let card = adaptive(light: 0xEAEAED, dark: 0x232327)
    static let cardSoft = adaptive(light: 0xEEEEF0, dark: 0x202024)
    static let imagePlaceholder = adaptive(light: 0xEEEEF0, dark: 0x38383E)
    static let itemTile = adaptive(light: 0xF5F5F5, dark: 0x1F1F22)
    static let followUpDisc = adaptive(light: 0xF5F4F0, dark: 0x3A3A40)
    static let rowFill = adaptive(light: 0xF8F8F8, dark: 0x202023)
    static let rowButtonStroke = adaptive(light: 0xE5E5E5, dark: 0x3A3A40)
    static let chip = adaptive(light: 0xEAEAED, dark: 0x333339)
    static let ink = adaptive(light: 0x1F1F1F, dark: 0xF2F2F4)
    static let inkSecondary = adaptive(light: 0x6B6B6B, dark: 0x9A9AA0)
    static let accentDark = adaptive(light: 0x212124, dark: 0xF2F2F4)
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x19191C)
    static let dockSurface = adaptive(light: 0x121112, dark: 0xF2F2F4)
    static let dockContent = onAccent
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x2E2E33)
    static let surfaceRim = adaptive(light: 0xFFFFFF, dark: 0x3C3C43)
    static let record = adaptive(light: 0xF5544A, dark: 0xF5544A)
    static let toggleTint = adaptive(light: 0x212124, dark: 0x7C7C86)
    static let positive = adaptive(light: 0x3F6B57, dark: 0x9ABBAA)
    static let positiveFill = adaptive(light: 0xE5EEE9, dark: 0x26312C)
    static let negative = adaptive(light: 0x8A4B48, dark: 0xD0A09D)
    static let negativeFill = adaptive(light: 0xF2E8E7, dark: 0x362929)
    static let comparisonPositive = adaptiveP3(light: (14408, 32896, 16104), dark: 0x9ABBAA)
    static let comparisonPositiveFill = adaptiveP3(light: (62207, 64799, 63039), dark: 0x26312C)
    static let comparisonNegative = adaptiveP3(light: (45599, 9320, 7072), dark: 0xD0A09D)
    static let comparisonNegativeFill = adaptiveP3(light: (64959, 62399, 62335), dark: 0x362929)

    static let chartPalette: [Color] = [
        adaptive(light: 0x212124, dark: 0xF2F2F4),
        adaptive(light: 0x77777F, dark: 0xA6A6AE),
        adaptive(light: 0xAFAFB6, dark: 0x6E6E76),
        adaptive(light: 0xD4D4D9, dark: 0x48484E),
        adaptive(light: 0x93939B, dark: 0x8A8A92),
        adaptive(light: 0xC3C3C9, dark: 0x5B5B62),
    ]

    static let cardRadius: CGFloat = 20
    static let pageMargin: CGFloat = 20
    static let contentMargin: CGFloat = 28
    static let textMargin: CGFloat = 32
    static func carouselCardWidth(in containerWidth: CGFloat) -> CGFloat {
        ((containerWidth > 0 ? containerWidth : 430) - contentMargin * 2) * 0.75
    }
    static let homeMargin: CGFloat = 28

    static func color(hex: String?) -> Color? {
        guard let hex,
              hex.count == 7,
              hex.first == "#",
              hex.dropFirst().allSatisfy({ $0.isHexDigit }),
              let rgb = UInt32(hex.dropFirst(), radix: 16)
        else { return nil }
        return Color(uiColor: UIColor(rgb: rgb))
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func adaptiveP3(light: (UInt16, UInt16, UInt16), dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark { return UIColor(rgb: dark) }
            return UIColor(displayP3Red: CGFloat(light.0) / 65535,
                           green: CGFloat(light.1) / 65535,
                           blue: CGFloat(light.2) / 65535, alpha: 1)
        })
    }

    static func greeting(strong: Bool = false) -> Font { .system(size: 24, weight: strong ? .semibold : .regular) }
    static let greetingTracking: CGFloat = 0.2
    static func sectionTitle() -> Font { .system(size: 24, weight: .bold) }
    static func intro() -> Font { .system(size: 22, weight: .regular) }
    static func body() -> Font { .system(size: 17, weight: .regular) }
    static func bodySecondary() -> Font { .system(size: 16, weight: .regular) }
    static func cardTitle() -> Font { .system(size: 17, weight: .semibold) }
    static func caption() -> Font { .system(size: 15, weight: .regular) }
    static func button() -> Font { .system(size: 20, weight: .medium) }
    static func quote() -> Font { .system(size: 26, weight: .regular, design: .serif) }
}

extension View {
    func cardBackground(radius: CGFloat = Theme.cardRadius) -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct NavigationCircleButton<Label: View>: View {
    let action: () -> Void
    let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

extension Theme {
    enum Seam { case top, middle, bottom, solo }

    static func seamShape(_ pos: Seam, radius: CGFloat = cardRadius, seam: CGFloat = 8)
        -> UnevenRoundedRectangle {
        let top = pos == .top || pos == .solo ? radius : seam
        let bottom = pos == .bottom || pos == .solo ? radius : seam
        return UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
    }
}

extension View {
    func seamCard(_ pos: Theme.Seam, fill: Color = Theme.surface) -> some View {
        background(fill, in: Theme.seamShape(pos))
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}
