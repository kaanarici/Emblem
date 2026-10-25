import SwiftUI
import EmblemCore

struct HeroView: View {
    let block: Hero
    @State private var imageFailed = false
    @State private var attempt = 0
    @State private var waitingToRetry = false
    private static let retryDelays: [Double] = [0, 1.2, 2.5]

    var body: some View {
        if !imageFailed {
            imageBox
                .frame(maxWidth: block.aspect == .poster ? 260 : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.contentMargin)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
    }

    private var imageBox: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(RemoteImage(
                spec: block.image.targeting(imageAspect),
                url: block.imageURL.flatMap(URL.init(string:)),
                maxPixelSize: 800,
                showsSkeleton: true,
                onFailure: {
                    guard attempt < Self.retryDelays.count else {
                        withAnimation(.easeOut(duration: 0.18)) { imageFailed = true }
                        return
                    }
                    let next = attempt + 1
                    waitingToRetry = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelays[attempt]) {
                        attempt = next
                        waitingToRetry = false
                    }
                })
                .id(attempt))
            .overlay { if waitingToRetry { ShimmerTile() } }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipped()
    }

    private var aspectRatio: CGFloat {
        switch block.aspect {
        case .poster: 3 / 4
        case .wide: 16 / 10
        case .square: 1
        }
    }

    private var imageAspect: ImageSpec.Aspect {
        switch block.aspect {
        case .poster: .portrait
        case .wide: .landscape
        case .square: .square
        }
    }
}
