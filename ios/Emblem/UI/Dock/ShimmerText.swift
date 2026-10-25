import SwiftUI
import EmblemCore

struct ShimmerText: View {
    let text: String
    var active: Bool = true
    var size: CGFloat = 17
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accent) private var accent

    init(_ text: String, active: Bool = true, size: CGFloat = 17) {
        self.text = text
        self.active = active
        self.size = size
    }

    var body: some View {
        statusLabel
            .frame(height: ceil(size * 1.3), alignment: .center)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if reduceMotion {
            label.foregroundStyle(accent.glyph.opacity(0.88))
        } else {
            label
                .foregroundStyle(accent.glyph.opacity(GenerationShimmer.restingOpacity))
                .overlay {
                    GeometryReader { proxy in
                        TimelineView(.animation(minimumInterval: 1 / 60, paused: !active)) { timeline in
                            let width = proxy.size.width
                            let band = width * GenerationShimmer.bandWidth
                            GenerationShimmer.band(accent.glyph)
                                .frame(width: band, height: proxy.size.height)
                                .offset(x: GenerationShimmer.center(at: timeline.date) * width - band / 2)
                                .frame(width: width, height: proxy.size.height, alignment: .leading)
                        }
                    }
                    .mask(label)
                    .allowsHitTesting(false)
                }
        }
    }

    private var label: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .tracking(Self.tracking)
            .contentTransition(.interpolate)
    }

    static let tracking: CGFloat = -0.3
}

enum GenerationShimmer {
    static let restingOpacity = 0.26
    static let period: TimeInterval = 1.53
    static let sweep: TimeInterval = 1.14
    static let bandWidth: CGFloat = 0.57
    static let travel: ClosedRange<CGFloat> = -0.45...1.45

    static func center(at date: Date) -> CGFloat {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        let progress = CGFloat(min(1, phase / sweep))
        return travel.lowerBound + progress * (travel.upperBound - travel.lowerBound)
    }

    static func band(_ ink: Color) -> LinearGradient {
        let stops = stride(from: -2.5, through: 2.5, by: 0.5).map { sigma in
            Gradient.Stop(color: ink.opacity(exp(-sigma * sigma / 2)), location: (sigma + 2.5) / 5)
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }
}
