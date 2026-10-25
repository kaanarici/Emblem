import SwiftUI

struct ResponseRevealTiming: Hashable {
    static let duration: TimeInterval = 1.02
    let start: Date
    let viewportHeight: CGFloat

    static func band(height: CGFloat) -> CGFloat { max(1, height) * 0.44 }

    static func eased(_ raw: Double) -> Double { min(1, max(0, raw)) }

    static func front(progress: Double, height: CGFloat) -> CGFloat {
        let band = Self.band(height: height)
        return -band + (max(1, height) + band) * progress
    }

    func readyAt(regionBottom: CGFloat) -> Date {
        let height = max(1, viewportHeight)
        let band = Self.band(height: height)
        let bottom = min(height, max(0, regionBottom))
        let progress = min(1, max(0, (bottom + band) / (height + band)))
        return start.addingTimeInterval(progress * Self.duration)
    }
}

private struct ResponseRevealTimingKey: EnvironmentKey {
    static let defaultValue: ResponseRevealTiming? = nil
}

extension EnvironmentValues {
    var responseRevealTiming: ResponseRevealTiming? {
        get { self[ResponseRevealTimingKey.self] }
        set { self[ResponseRevealTimingKey.self] = newValue }
    }
}
