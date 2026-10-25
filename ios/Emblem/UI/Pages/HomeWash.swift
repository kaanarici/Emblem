import SwiftUI
import UIKit
import EmblemCore

struct HomeWash: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if scheme == .dark {
            Theme.background
        } else {
            ZStack {
                Color(uiColor: UIColor(rgb: 0xF9F9FA))
                wash(0xF0F1F6, at: UnitPoint(x: 0.5, y: 0.66), radius: 280)
                wash(0xEBF3EF, at: UnitPoint(x: 0, y: 0.52), radius: 320)
                wash(0xF7EDF1, at: UnitPoint(x: 1, y: 0.56), radius: 320)
                wash(0xF9F1EE, at: UnitPoint(x: 1, y: 0.28), radius: 200)
                wash(0xF4F1E9, at: UnitPoint(x: 0, y: 0.86), radius: 240)
                wash(0xEEEDF4, at: UnitPoint(x: 0.8, y: 1), radius: 380)
            }
        }
    }

    private func wash(_ hex: UInt32, at center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(colors: [Color(uiColor: UIColor(rgb: hex)), Color(uiColor: UIColor(rgb: hex)).opacity(0)],
                       center: center, startRadius: 0, endRadius: radius)
    }
}
