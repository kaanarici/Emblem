import SwiftUI

struct PosterArtworkTreatment: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay {
                content.blur(radius: 2, opaque: true)
                    .mask(blurMask(from: 0.58, to: 0.76))
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            .overlay {
                content.blur(radius: 6, opaque: true)
                    .mask(blurMask(from: 0.68, to: 0.86))
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            .overlay {
                content.blur(radius: 12, opaque: true)
                    .mask(blurMask(from: 0.78, to: 0.96))
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            .overlay {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.58),
                    .init(color: .black.opacity(0.35), location: 0.76),
                    .init(color: .black, location: 0.95),
                ], startPoint: .top, endPoint: .bottom)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
            .clipped()
    }

    private func blurMask(from start: CGFloat, to end: CGFloat) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: .clear, location: start),
            .init(color: .white, location: end),
        ], startPoint: .top, endPoint: .bottom)
    }
}
