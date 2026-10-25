import SwiftUI
import UIKit
import EmblemCore

struct HomeWash: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack {
            wash
                .id(accent)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.4), value: accent)
    }

    @ViewBuilder
    private var wash: some View {
        let tint = accent.color
        let share = accent.isNeutral ? 0.08 : 0.16
        if scheme == .dark {
            ZStack {
                Theme.background
                glow(Theme.background.mix(with: tint, by: share * 0.7), at: UnitPoint(x: 0.5, y: 0.66), radius: 320)
                glow(Theme.background.mix(with: tint, by: share * 0.5), at: UnitPoint(x: 1, y: 0.3), radius: 260)
                glow(Theme.background.mix(with: tint, by: share * 0.5), at: UnitPoint(x: 0, y: 0.9), radius: 300)
            }
        } else {
            ZStack {
                hex(0xF9F9FA).mix(with: tint, by: share * 0.2)
                glow(hex(0xF0F1F6).mix(with: tint, by: share), at: UnitPoint(x: 0.5, y: 0.66), radius: 280)
                glow(hex(0xEBF3EF).mix(with: tint, by: share), at: UnitPoint(x: 0, y: 0.52), radius: 320)
                glow(hex(0xF7EDF1).mix(with: tint, by: share), at: UnitPoint(x: 1, y: 0.56), radius: 320)
                glow(hex(0xF9F1EE).mix(with: tint, by: share), at: UnitPoint(x: 1, y: 0.28), radius: 200)
                glow(hex(0xF4F1E9).mix(with: tint, by: share), at: UnitPoint(x: 0, y: 0.86), radius: 240)
                glow(hex(0xEEEDF4).mix(with: tint, by: share), at: UnitPoint(x: 0.8, y: 1), radius: 380)
            }
        }
    }

    private func hex(_ rgb: UInt32) -> Color { Color(uiColor: UIColor(rgb: rgb)) }

    private func glow(_ color: Color, at center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(colors: [color, color.opacity(0)], center: center, startRadius: 0, endRadius: radius)
    }
}
