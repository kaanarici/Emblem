import SwiftUI
import ImageIO
import CryptoKit
import OSLog
import EmblemCore

private struct ImageDevelop: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: 16 * (1 - progress), opaque: true)
            .scaleEffect(1 + 0.03 * (1 - progress))
            .opacity(min(1, progress * 2))
    }
}

extension AnyTransition {
    static var imageArrival: AnyTransition {
        .modifier(active: ImageDevelop(progress: 0), identity: ImageDevelop(progress: 1))
    }
}

extension Animation {
    static let imageArrival = Animation.easeOut(duration: 0.7)
    static let objectArrival = Animation.spring(duration: 0.5, bounce: 0.18)
}

private struct ObjectSettle: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.82 + 0.18 * progress)
            .blur(radius: 6 * (1 - progress))
            .opacity(progress)
    }
}

extension AnyTransition {
    static var objectArrival: AnyTransition {
        .modifier(active: ObjectSettle(progress: 0), identity: ObjectSettle(progress: 1))
    }
}

struct RemoteImage: View {
    var spec: ImageSpec? = nil
    var url: URL? = nil
    var maxPixelSize: CGFloat = 400
    var contentMode: ContentMode = .fill
    var showsSkeleton: Bool = true
    var onFailure: (() -> Void)?
    var onImageSize: ((CGSize) -> Void)?

    @State private var image: UIImage?
    @State private var failed = false
    @State private var frame = GlobalFrameBox()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.responseRevealTiming) private var responseReveal
    private var resolutions = ImageResolutions.shared

    init(
        spec: ImageSpec? = nil,
        url: URL? = nil,
        maxPixelSize: CGFloat = 400,
        contentMode: ContentMode = .fill,
        showsSkeleton: Bool = true,
        onFailure: (() -> Void)? = nil,
        onImageSize: ((CGSize) -> Void)? = nil
    ) {
        self.spec = spec
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        self.showsSkeleton = showsSkeleton
        self.onFailure = onFailure
        self.onImageSize = onImageSize
        _image = State(initialValue: Self.cachedImage(
            spec: spec, url: url, maxPixelSize: maxPixelSize))
    }

    private static func cachedImage(
        spec: ImageSpec?, url: URL?, maxPixelSize: CGFloat
    ) -> UIImage? {
        if let url, let hit = ImageLoader.shared.cachedImage(at: url, maxPixelSize: maxPixelSize) {
            return hit
        }
        if let spec {
            return ImageLoader.shared.cachedImage(for: spec, maxPixelSize: maxPixelSize)
        }
        return nil
    }

    var body: some View {
        ZStack {
            if contentMode == .fill || failed {
                Rectangle().fill(failed ? Theme.cardSoft : Theme.surface)
            }
            if image == nil, showsSkeleton, !failed {
                ShimmerTile()
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.animation(.linear(duration: 0.01).delay(0.7))))
            }
            if failed, image == nil {
                LinearGradient(
                    colors: [Theme.cardSoft, Theme.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
            }
            if let image {
                Color.clear
                    .overlay(
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: contentMode))
                    .transition(reduceMotion ? .opacity : .imageArrival)
            }
        }
        .clipped()
        .onGeometryChange(for: CGRect.self) { [revealing = responseReveal != nil] proxy in
            revealing ? proxy.frame(in: .global) : .zero
        } action: { frame.frame = $0 }
        .task(id: responseReveal) {
            guard responseReveal != nil else { return }
            try? await Task.sleep(for: .milliseconds(16))
            guard let shown = image, let delay = revealDelay, delay > 0.05 else { return }
            image = nil
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { image = shown; return }
            withAnimation(.imageArrival) { image = shown }
        }
        .onChange(of: image?.size, initial: true) { _, size in
            if let size, size.width > 0, size.height > 0 {
                onImageSize?(size)
            }
        }
        .onChange(of: LoadKey(spec: spec, url: url, maxPixelSize: maxPixelSize)) { failed = false }
        .task(id: ReloadKey(
            load: LoadKey(spec: spec, url: url, maxPixelSize: maxPixelSize),
            generation: image == nil ? resolutions.generation : 0)) {
            if let hit = Self.cachedImage(spec: spec, url: url, maxPixelSize: maxPixelSize) {
                if image == nil, !reduceMotion {
                    withAnimation(.imageArrival) { image = hit }
                } else {
                    image = hit
                }
                failed = false
                return
            }
            image = nil
            let resolved: UIImage?
            if let url, let direct = await ImageLoader.shared.image(
                at: url, maxPixelSize: maxPixelSize
            ) {
                resolved = direct
            } else if let spec {
                resolved = await ImageLoader.shared.image(for: spec, maxPixelSize: maxPixelSize)
            } else {
                resolved = nil
            }
            guard !Task.isCancelled else { return }
            if resolved != nil, let delay = revealDelay, delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
            }
            if let resolved {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .imageArrival) {
                    image = resolved
                    failed = false
                }
            } else if !failed {
                failed = true
                onFailure?()
            }
        }
    }

    private var revealDelay: TimeInterval? {
        guard !reduceMotion, let responseReveal, frame.frame != .zero else { return nil }
        return responseReveal.readyAt(regionBottom: frame.frame.midY).timeIntervalSinceNow
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

struct ShimmerTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var drifting = false

    var body: some View {
        if reduceMotion {
            Rectangle().fill(Theme.imagePlaceholder)
        } else {
            GeometryReader { proxy in
                let reach = max(proxy.size.width, proxy.size.height)
                Rectangle()
                    .fill(Theme.imagePlaceholder)
                    .overlay {
                        RadialGradient(
                            colors: [scheme == .dark ? .white.opacity(0.06) : .white.opacity(0.7), .clear],
                            center: .center, startRadius: 0, endRadius: reach * 0.7)
                            .frame(width: reach * 1.4, height: reach * 1.4)
                            .offset(x: reach * (drifting ? 0.3 : -0.3), y: reach * (drifting ? -0.15 : 0.25))
                            .animation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true), value: drifting)
                    }
                    .overlay {
                        RadialGradient(
                            colors: [scheme == .dark ? .black.opacity(0.16) : Theme.ink.opacity(0.04), .clear],
                            center: .center, startRadius: 0, endRadius: reach * 0.8)
                            .frame(width: reach * 1.6, height: reach * 1.6)
                            .offset(x: reach * (drifting ? -0.35 : 0.3), y: reach * (drifting ? 0.3 : -0.1))
                            .animation(.easeInOut(duration: 6.1).repeatForever(autoreverses: true), value: drifting)
                    }
                    .clipped()
            }
            .onAppear { drifting = true }
        }
    }
}
