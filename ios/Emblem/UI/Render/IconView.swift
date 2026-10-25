import SwiftUI
import EmblemCore

struct IconView: View {
    let icon: Icon?
    var size: CGFloat = 28
    var glyphFallback = true
    var placeholder = false
    var loadingSkeleton = false
    var cardGlyph = false

    static let glyphFallbackLimit: CGFloat = 44

    var body: some View {
        if placeholder && !ListIconPolicy.isRenderable(icon) {
            IconPlaceholderTile(size: size)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image = icon?.image {
            if image.kind == .object {
                ObjectIconImage(
                    spec: image,
                    fallbackSymbol: validSymbol,
                    accent: accent,
                    size: size,
                    glyphFallback: glyphFallback,
                    glyphSize: glyphSize,
                    placeholder: placeholder,
                    loadingSkeleton: loadingSkeleton)
            } else {
                RemoteImage(spec: image, maxPixelSize: size * 2)
                    .frame(width: size * 1.3, height: size * 1.3)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            }
        } else if let emoji = icon?.emoji, !emoji.isEmpty {
            Text(emoji)
                .font(.system(size: size))
                .frame(width: size, height: size)
        } else if let symbol = validSymbol {
            symbolView(symbol)
        }
    }

    private var glyphSize: CGFloat { cardGlyph ? min(size, 40) : size }

    private var validSymbol: String? {
        guard let symbol = icon?.sfSymbol, Hugeicons.isRenderable(symbol) else { return nil }
        return symbol
    }

    private var accent: Color {
        Theme.color(hex: icon?.color) ?? .primary
    }

    private func symbolView(_ symbol: String) -> some View {
        GlyphImage(symbol: symbol, size: glyphSize)
            .foregroundStyle(accent)
    }
}

enum ListIconPolicy {
    static func showsIcons(_ icons: [Icon?]) -> Bool {
        !icons.isEmpty && icons.allSatisfy(isRenderable)
    }

    static func isRenderable(_ icon: Icon?) -> Bool {
        guard let icon else { return false }
        if let image = icon.image,
           !image.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if let emoji = icon.emoji,
           !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if Hugeicons.isRenderable(icon.sfSymbol) {
            return true
        }
        return false
    }
}

struct IconPlaceholderTile: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(InputPalette.iconSlot)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct ObjectImageLoadingPlaceholder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                Theme.cardSoft
            } else {
                ShimmerTile()
            }
        }
        .accessibilityHidden(true)
    }
}

extension ImageSpec {
    static func objectStandIn(forSymbol symbol: String?) -> ImageSpec? {
        guard let symbol else { return nil }
        let modifiers: Set<String> = ["fill", "circle", "square", "badge", "bullet", "and", "plus",
                                      "minus", "rectangle", "slash", "2", "3", "stack", "lines"]
        let words = symbol.lowercased().split(separator: ".").map(String.init)
            .filter { !modifiers.contains($0) }
        for word in words.reversed() where ObjectLibrary.imageURL(for: word) != nil {
            return ImageSpec(query: word, kind: .object)
        }
        return nil
    }
}

private struct ObjectIconImage: View {
    let spec: ImageSpec
    let fallbackSymbol: String?
    let accent: Color
    let size: CGFloat
    let glyphFallback: Bool
    let glyphSize: CGFloat
    let placeholder: Bool
    let loadingSkeleton: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var showsSkeleton = false
    @State private var loadingFailed = false
    @State private var settledSpec: ImageSpec?
    private var resolutions = ImageResolutions.shared

    init(spec: ImageSpec, fallbackSymbol: String?, accent: Color, size: CGFloat, glyphFallback: Bool,
         glyphSize: CGFloat, placeholder: Bool, loadingSkeleton: Bool) {
        self.spec = spec
        self.placeholder = placeholder
        self.loadingSkeleton = loadingSkeleton
        self.glyphFallback = glyphFallback
        self.glyphSize = glyphSize
        self.fallbackSymbol = fallbackSymbol
        self.accent = accent
        self.size = size
        let cached = ImageLoader.shared.cachedImage(for: spec, maxPixelSize: size * 2)
        _image = State(initialValue: cached)
        _settledSpec = State(initialValue: cached == nil ? nil : spec)
    }

    var body: some View {
        ZStack {
            if image == nil && placeholder && !(loadingFailed && showsGlyph) {
                IconPlaceholderTile(size: size)
                    .transition(.opacity)
            } else if image == nil && loadingFailed && showsGlyph {
                GlyphImage(symbol: fallbackSymbol ?? "shippingbox", size: glyphSize)
                    .foregroundStyle(accent)
            } else if image == nil && !loadingFailed && showsSkeleton {
                ObjectImageLoadingPlaceholder()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
                    .transition(.opacity)
            }
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(reduceMotion ? .opacity : .objectArrival)
            }
        }
        .frame(width: size * 1.35, height: size * 1.35)
        .task(id: ReloadKey(spec: spec, generation: image == nil ? resolutions.generation : 0)) {
            if image != nil, settledSpec == spec { return }
            if let hit = ImageLoader.shared.cachedImage(for: spec, maxPixelSize: size * 2) {
                image = hit
                loadingFailed = false
                settledSpec = spec
                return
            }
            if settledSpec != spec {
                image = nil
                loadingFailed = false
                showsSkeleton = false
            }
            let skeleton = Task {
                guard loadingSkeleton else { return }
                try await Task.sleep(for: .milliseconds(150))
                withAnimation(.easeOut(duration: 0.2)) { showsSkeleton = true }
            }
            defer { skeleton.cancel() }
            var loaded = await ImageLoader.shared.image(for: spec, maxPixelSize: size * 2)
            if loaded == nil, let local = ImageSpec.objectStandIn(forSymbol: fallbackSymbol) {
                loaded = await ImageLoader.shared.image(for: local, maxPixelSize: size * 2)
            }
            guard !Task.isCancelled else { return }
            settledSpec = spec
            guard let loaded else {
                loadingFailed = true
                return
            }
            if reduceMotion {
                image = loaded
            } else {
                withAnimation(.objectArrival) { image = loaded }
            }
        }
    }

    private var showsGlyph: Bool { glyphFallback && glyphSize < IconView.glyphFallbackLimit }

    private struct ReloadKey: Hashable {
        let spec: ImageSpec
        let generation: Int
    }
}

struct PressableStyle: ButtonStyle {
    var hapticsEnabled = true
    var pressedScale: CGFloat = 0.96
    var elevation: CardElevation? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(RestingElevation(elevation: elevation))
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.28), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { old, new in
                hapticsEnabled && isEnabled && !old && new
            }
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

struct PerformActionKey: EnvironmentKey {
    static let defaultValue: @MainActor (Action) -> Void = { _ in }
}

extension EnvironmentValues {
    var performAction: @MainActor (Action) -> Void {
        get { self[PerformActionKey.self] }
        set { self[PerformActionKey.self] = newValue }
    }
}
