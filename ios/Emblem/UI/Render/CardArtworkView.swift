import SwiftUI
import EmblemCore

struct CardArtworkView: View {
    let card: CardCarousel.Card
    let maxPixelSize: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var resolvedImage: UIImage?
    @State private var loadFailed = false
    private var resolutions = ImageResolutions.shared

    init(
        card: CardCarousel.Card,
        maxPixelSize: CGFloat = 400
    ) {
        self.card = card
        self.maxPixelSize = maxPixelSize
        _resolvedImage = State(initialValue: Self.cachedImage(
            card: card,
            maxPixelSize: maxPixelSize))
    }

    private var imageSpec: ImageSpec? { card.image }

    private var imageURL: URL? {
        card.imageURL.flatMap(URL.init(string:))
    }

    private var isObject: Bool { card.image?.kind == .object }

    var body: some View {
        ZStack {
            placeholder
            if let resolvedImage {
                Rectangle()
                    .fill(Theme.imagePlaceholder)
                    .overlay {
                        Image(uiImage: resolvedImage)
                            .resizable()
                            .aspectRatio(contentMode: isObject ? .fit : .fill)
                            .padding(isObject ? 18 : 0)
                    }
                    .transition(reduceMotion ? .opacity : .imageArrival)
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .onChange(of: LoadKey(spec: imageSpec, url: imageURL, maxPixelSize: maxPixelSize)) {
            loadFailed = false
        }
        .task(id: ReloadKey(
            load: LoadKey(spec: imageSpec, url: imageURL, maxPixelSize: maxPixelSize),
            generation: resolvedImage == nil ? resolutions.generation : 0)) {
            if let cachedImage {
                resolvedImage = cachedImage
                return
            }
            resolvedImage = Self.cachedImage(card: card, maxPixelSize: 200)
            let loaded = await loadImage()
            guard !Task.isCancelled else { return }
            guard let loaded else {
                loadFailed = true
                return
            }
            if reduceMotion {
                resolvedImage = loaded
            } else {
                withAnimation(.imageArrival) { resolvedImage = loaded }
            }
        }
    }

    private var awaitsArtwork: Bool {
        (imageSpec != nil || imageURL != nil) && !loadFailed
    }

    @ViewBuilder
    private var placeholder: some View {
        if awaitsArtwork {
            ShimmerTile()
        } else {
            iconPlaceholder
        }
    }

    private var iconPlaceholder: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Theme.cardSoft, Theme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
            if let icon = card.icon, icon.image?.kind == .object || icon.emoji?.isEmpty == false {
                IconView(icon: Icon(emoji: icon.emoji, image: icon.image), size: 46)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func loadImage() async -> UIImage? {
        if let imageURL,
           let image = await ImageLoader.shared.image(
               at: imageURL,
               maxPixelSize: maxPixelSize) {
            return image
        }
        if let imageSpec {
            return await ImageLoader.shared.image(for: imageSpec, maxPixelSize: maxPixelSize)
        }
        return nil
    }

    private var cachedImage: UIImage? {
        Self.cachedImage(card: card, maxPixelSize: maxPixelSize)
    }

    private static func cachedImage(
        card: CardCarousel.Card,
        maxPixelSize: CGFloat
    ) -> UIImage? {
        if let urlString = card.imageURL,
           let url = URL(string: urlString),
           let image = ImageLoader.shared.cachedImage(at: url, maxPixelSize: maxPixelSize) {
            return image
        }
        guard let spec = card.image else { return nil }
        return ImageLoader.shared.cachedImage(for: spec, maxPixelSize: maxPixelSize)
    }

    private struct LoadKey: Hashable {
        let spec: ImageSpec?
        let url: URL?
        let maxPixelSize: CGFloat
    }

    private struct ReloadKey: Hashable {
        let load: LoadKey
        let generation: Int
    }
}

struct ProgressiveFrost: View {
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            .mask(ProgressiveFrostMask())
    }
}

struct ProgressiveFrostMask: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.28), location: 0.18),
                .init(color: .white.opacity(0.84), location: 0.52),
                .init(color: .white, location: 0.82),
            ],
            startPoint: .top,
            endPoint: .bottom)
    }
}
