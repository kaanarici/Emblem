import SwiftUI
import EmblemCore

@MainActor
enum FollowUpIconGate {
    static let deadline: Duration = .milliseconds(1_200)
    private static let pixelSize: CGFloat = 80

    static func settledFromCache(_ chips: [ChipRow.Chip]) -> [ImageSpec?]? {
        let chosen = choose(for: chips)
        let complete = zip(chips, chosen).allSatisfy { chip, art in chip.icon?.image == nil || art != nil }
        return complete ? chosen : nil
    }

    static func settle(_ chips: [ChipRow.Chip]) async -> [ImageSpec?] {
        await waitForLoads(chips.compactMap(\.icon?.image))
        for spec in chips.compactMap({ ImageSpec.objectStandIn(forSymbol: $0.icon?.sfSymbol) }) {
            _ = await ImageLoader.shared.image(for: spec, maxPixelSize: pixelSize)
        }
        return choose(for: chips)
    }

    private static func choose(for chips: [ChipRow.Chip]) -> [ImageSpec?] {
        var shown = Set<String>()
        return chips.map { chip in
            let candidates = [chip.icon?.image, ImageSpec.objectStandIn(forSymbol: chip.icon?.sfSymbol)]
            return candidates.lazy.compactMap { $0 }.first { spec in
                ImageLoader.shared.cachedImage(for: spec, maxPixelSize: pixelSize) != nil
                    && shown.insert(artIdentity(spec)).inserted
            }
        }
    }

    private static func artIdentity(_ spec: ImageSpec) -> String {
        if spec.kind == .object, let file = ObjectLibrary.imageURL(for: spec.query) {
            return file.lastPathComponent
        }
        let noun = String(spec.query.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
        return "\(spec.kind.rawValue):" + noun.split(separator: " ").joined(separator: " ")
    }

    private static func waitForLoads(_ specs: [ImageSpec]) async {
        guard !specs.isEmpty else { return }
        let (events, continuation) = AsyncStream<Bool>.makeStream()
        for spec in specs {
            Task(priority: .userInitiated) {
                _ = await ImageLoader.shared.image(
                    for: spec, maxPixelSize: pixelSize, priority: .userInitiated)
                continuation.yield(true)
            }
        }
        let timer = Task {
            try? await Task.sleep(for: deadline)
            continuation.yield(false)
        }
        var loaded = 0
        for await finished in events {
            guard finished else { break }
            loaded += 1
            if loaded == specs.count { break }
        }
        timer.cancel()
        continuation.finish()
    }
}
