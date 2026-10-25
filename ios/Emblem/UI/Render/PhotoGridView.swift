import SwiftUI
import EmblemCore

struct PhotoGridView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let block: PhotoGrid
    @Environment(\.expansionNamespace) private var expansionNamespace
    @Environment(\.renderedPage) private var renderedPage
    @Environment(ConversationStore.self) private var store

    private static let gutter: CGFloat = 4
    private static let corner: CGFloat = 6
    private static let collageCorner: CGFloat = 20

    private var layout: PhotoGrid.Layout {
        block.presentation == .collection ? .collage : (block.layout ?? .strip)
    }

    @State private var selectedImage: PhotoLightboxSelection?
    @State private var selectedCollection: PhotoCollectionSelection?
    @State private var stripRatios: [ImageSpec: CGFloat] = [:]

    @ViewBuilder var body: some View {
        if block.presentation == .collection {
            collectionPreview
        } else {
            directGallery
        }
    }

    private var directGallery: some View {
        arrangement
            .navigationDestination(item: $selectedImage) { selection in
                PhotoLightboxView(images: resolvedImages, initialIndex: selection.index)
                    .modifier(PhotoLightboxZoomTransition(
                        sourceID: lightboxTransitionID(for: selection.index),
                        namespace: expansionNamespace))
            }
    }

    private var collectionSelection: Binding<PhotoCollectionSelection?> {
        Binding(
            get: { selectedCollection },
            set: { selection in
                guard selectedCollection != selection else { return }
                store.isViewingPhoto = selection != nil
                selectedCollection = selection
            })
    }

    private var collectionPreview: some View {
        arrangement
            .navigationDestination(item: collectionSelection) { selection in
                PhotoCollectionView(
                    images: resolvedImages,
                    rows: block.collectionImageRows,
                    scopeID: selection.scopeID,
                    shareText: renderedPage?.visibleContextSummary,
                    onClose: { collectionSelection.wrappedValue = nil })
                    .modifier(PhotoLightboxZoomTransition(
                        sourceID: lightboxTransitionID(for: selection.index),
                        namespace: expansionNamespace))
            }
    }

    private var displayedImages: [ImageSpec] {
        layout == .collage ? Array(block.images.prefix(4)) : block.images
    }

    private var resolvedImages: [ImageSpec] {
        block.images.enumerated().map { index, spec in
            resolvedSpec(spec, index: index)
        }
    }

    private func resolvedSpec(_ spec: ImageSpec, index: Int) -> ImageSpec {
        guard layout == .collage else { return spec }
        return spec.targeting(displayedImages.count == 3 && index == 0 ? .portrait : .landscape)
    }

    @ViewBuilder private var arrangement: some View {
        switch layout {
        case .collage:
            masonry
                .clipShape(RoundedRectangle(cornerRadius: Self.collageCorner, style: .continuous))
                .padding(.horizontal, Theme.contentMargin)
        case .grid:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                ForEach(Array(displayedImages.enumerated()), id: \.offset) { index, spec in
                    fillTile(spec, index: index, corner: 12)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.horizontal, Theme.contentMargin)
        case .strip:
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(displayedImages.enumerated()), id: \.offset) { index, spec in
                            fillTile(spec, index: index, corner: 12, onImageSize: { size in
                                if let ratio = Self.stripRatio(size: size) {
                                    stripRatios[spec] = ratio
                                }
                            })
                            .frame(width: geometry.size.height * stripRatio(for: spec),
                                   height: geometry.size.height)
                        }
                    }
                    .padding(.horizontal, Theme.contentMargin)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .aspectRatio(2.35, contentMode: .fit)
        }
    }

    private func stripRatio(for spec: ImageSpec) -> CGFloat {
        if let ratio = stripRatios[spec] { return ratio }
        if let size = ImageLoader.shared.cachedImage(for: spec, maxPixelSize: 700)?.size,
           let ratio = Self.stripRatio(size: size) {
            return ratio
        }
        switch spec.aspect {
        case .portrait: return 2 / 3
        case .landscape: return 4 / 3
        case .square: return 1
        case nil: return 2 / 3
        }
    }

    private static func stripRatio(size: CGSize) -> CGFloat? {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        return min(max(size.width / size.height, 0.5), 1.35)
    }

    @ViewBuilder private var masonry: some View {
        let specs = displayedImages
        switch specs.count {
        case 0:
            EmptyView()
        case 1:
            fillTile(specs[0], index: 0)
                .aspectRatio(16 / 10, contentMode: .fit)
        case 2:
            HStack(spacing: Self.gutter) {
                fillTile(specs[0], index: 0).aspectRatio(1, contentMode: .fit)
                fillTile(specs[1], index: 1).aspectRatio(1, contentMode: .fit)
            }
        case 3:
            GeometryReader { geo in
                let g = Self.gutter
                let tall = (geo.size.width - g) * 0.44
                let stack = geo.size.width - g - tall
                let rowH = (geo.size.height - g) / 2
                HStack(spacing: g) {
                    fillTile(specs[0], index: 0)
                        .frame(width: tall, height: geo.size.height)
                    VStack(spacing: g) {
                        fillTile(specs[1], index: 1)
                            .frame(width: stack, height: rowH)
                        fillTile(specs[2], index: 2)
                            .frame(width: stack, height: rowH)
                    }
                }
            }
            .aspectRatio(1.30, contentMode: .fit)
        default:
            Grid(horizontalSpacing: Self.gutter, verticalSpacing: Self.gutter) {
                GridRow {
                    fillTile(specs[0], index: 0)
                    fillTile(specs[1], index: 1)
                }
                GridRow {
                    fillTile(specs[2], index: 2)
                    fillTile(specs[3], index: 3)
                }
            }
            .aspectRatio(1.143, contentMode: .fit)
        }
    }

    private func fillTile(
        _ spec: ImageSpec, index: Int, corner: CGFloat = Self.corner,
        onImageSize: ((CGSize) -> Void)? = nil
    ) -> some View {
        Color.clear
            .overlay {
                RemoteImage(
                    spec: resolvedSpec(spec, index: index),
                    maxPixelSize: 700,
                    showsSkeleton: true,
                    onImageSize: onImageSize)
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .onTapGesture {
                guard blockInteraction.allowsActivation else { return }
                if block.presentation == .collection {
                    collectionSelection.wrappedValue = PhotoCollectionSelection(
                        scopeID: "photo-collection:\(renderedPage?.id.uuidString ?? "preview"):\(block.id)",
                        index: index)
                } else {
                    selectedImage = PhotoLightboxSelection(index: index)
                }
            }
            .modifier(PhotoLightboxZoomSource(
                id: lightboxTransitionID(for: index),
                namespace: expansionNamespace,
                corner: corner))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Open photo \(index + 1) of \(resolvedImages.count)")
            .blockActivationControl()
    }

    private func lightboxTransitionID(for index: Int) -> String {
        "photo-grid:\(renderedPage?.id.uuidString ?? "preview"):\(block.id):\(index)"
    }
}

private struct PhotoCollectionSelection: Hashable, Identifiable {
    let scopeID: String
    let index: Int
    var id: String { "\(scopeID):\(index)" }
}

private struct PhotoCollectionView: View {
    let images: [ImageSpec]
    let rows: [Range<Int>]
    let scopeID: String
    let shareText: String?
    let onClose: () -> Void
    @Environment(\.blockInteraction) private var blockInteraction
    @Namespace private var namespace
    @State private var selectedImage: PhotoLightboxSelection?

    var body: some View {
            ZStack {
                Theme.responsePaper.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(rows, id: \.lowerBound) { indices in
                            HStack(spacing: 4) {
                                ForEach(indices, id: \.self) { index in
                                    collectionTile(at: index)
                                        .aspectRatio(3.0 / 2.0, contentMode: .fit)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
                .accessibilityIdentifier("photo-collection-scroll")
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    NavigationCircleButton {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Close photo collection")
                    Spacer()
                    ShareLink(item: shareText ?? "") {
                        ChromeGlyph(symbol: .share, size: 22)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .disabled(shareText == nil)
                    .accessibilityLabel("Share photo collection")
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 24)
                .background(Theme.responsePaper)
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .navigationDestination(item: $selectedImage) { selection in
                PhotoLightboxView(
                    images: images, initialIndex: selection.index, ownsPhotoFocus: false)
                    .modifier(PhotoLightboxZoomTransition(
                        sourceID: transitionID(for: selection.index), namespace: namespace))
            }
        .environment(\.expansionNamespace, namespace)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    private func collectionTile(at index: Int) -> some View {
        Color.clear
            .overlay {
                RemoteImage(spec: images[index], maxPixelSize: 700, showsSkeleton: true)
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .onTapGesture {
                guard blockInteraction.allowsActivation else { return }
                selectedImage = PhotoLightboxSelection(index: index)
            }
            .modifier(PhotoLightboxZoomSource(id: transitionID(for: index), namespace: namespace, corner: 5))
            .id(transitionID(for: index))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Open collection photo \(index + 1) of \(images.count)")
            .blockActivationControl()
    }

    private func transitionID(for index: Int) -> String { "\(scopeID):\(index)" }
}

private struct PhotoLightboxSelection: Hashable, Identifiable {
    let index: Int
    var id: Int { index }
}

private struct PhotoLightboxView: View {
    let images: [ImageSpec]
    let initialIndex: Int
    let ownsPhotoFocus: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(ConversationStore.self) private var store
    @State private var viewerIndex: Int

    init(images: [ImageSpec], initialIndex: Int, ownsPhotoFocus: Bool = true) {
        self.images = images
        self.initialIndex = initialIndex
        self.ownsPhotoFocus = ownsPhotoFocus
        _viewerIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea(.all)

            TabView(selection: $viewerIndex) {
                ForEach(Array(images.enumerated()), id: \.offset) { offset, spec in
                    ZoomablePhoto(
                        spec: spec,
                        isActive: viewerIndex == offset,
                        onDismiss: dismiss.callAsFunction)
                        .tag(offset)
                        .accessibilityLabel("Photo \(offset + 1) of \(images.count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .ignoresSafeArea(.all)
            .tint(.white)

            NavigationCircleButton(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
            }
            .padding(.leading, 16)
            .padding(.top, 10)
            .accessibilityLabel("Close image viewer")
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .environment(\.colorScheme, .dark)
        .background {
            if ownsPhotoFocus {
                AppearanceProbe { store.isViewingPhoto = $0 }
                    .frame(width: 0, height: 0)
            }
        }
    }
}

private struct AppearanceProbe: UIViewControllerRepresentable {
    let onChange: (Bool) -> Void

    func makeUIViewController(context: Context) -> Controller { Controller(onChange: onChange) }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onChange = onChange
    }

    final class Controller: UIViewController {
        var onChange: (Bool) -> Void
        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            onChange(true)
            fadePage(.from, out: true)
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            onChange(false)
            fadePage(.to, out: false)
        }

        private func fadePage(_ key: UITransitionContextViewKey, out: Bool) {
            guard let coordinator = transitionCoordinator,
                  let page = coordinator.view(forKey: key) else { return }
            coordinator.containerView.backgroundColor = .black
            page.alpha = out ? 1 : 0
            coordinator.animate(alongsideTransition: { _ in
                page.alpha = out ? 0 : 1
            }, completion: { _ in
                page.alpha = 1
            })
        }
    }
}

private struct ZoomablePhoto: View {
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(\.expansionNamespace) private var expansionNamespace
    let spec: ImageSpec
    let isActive: Bool
    let onDismiss: () -> Void

    private static let maxScale: CGFloat = 4

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isZoomed: Bool { committedScale > 1.01 }
    private var usesSimpleDismissal: Bool { reduceMotion || expansionNamespace == nil }

    var body: some View {
        GeometryReader { viewport in
            RemoteImage(
                spec: spec,
                maxPixelSize: 1600,
                contentMode: .fit,
                showsSkeleton: true)
                .frame(width: viewport.size.width, height: viewport.size.height)
                .scaleEffect(scale)
                .offset(x: offset.width, y: offset.height)
                .frame(width: viewport.size.width, height: viewport.size.height)
                .clipped()
                .contentShape(Rectangle())
                .overlay {
                    PhotoViewerGestures(
                        isActive: isActive,
                        isZoomed: isZoomed,
                        allowsDragDismissal: usesSimpleDismissal,
                        onMagnify: { value in
                            scale = min(max(committedScale * value, 1), Self.maxScale)
                        },
                        onMagnifyEnd: {
                            committedScale = scale
                            if !isZoomed { reset(animated: true) }
                        },
                        onPan: updatePan,
                        onPanEnd: finishPan,
                        onDoubleTap: { blockInteraction.performActivation(toggleZoom) })
                        .accessibilityHidden(true)
                }
        }
        .background(Color.black)
        .clipped()
        .onChange(of: isActive) { _, active in
            if !active { reset(animated: false) }
        }
    }

    private func updatePan(_ translation: CGSize) {
        if isZoomed {
            offset = CGSize(
                width: committedOffset.width + translation.width,
                height: committedOffset.height + translation.height)
        }
    }

    private func finishPan(_ translation: CGSize) {
        if isZoomed {
            committedOffset = offset
        } else if usesSimpleDismissal && translation.height > 140 {
            onDismiss()
        }
    }

    private func toggleZoom() {
        let target: CGFloat = isZoomed ? 1 : 2.5
        withAnimation(reduceMotion ? nil : .spring(duration: 0.32)) {
            scale = target
            committedScale = target
            offset = .zero
            committedOffset = .zero
        }
    }

    private func reset(animated: Bool) {
        withAnimation(animated && !reduceMotion ? .spring(duration: 0.28) : nil) {
            scale = 1
            committedScale = 1
            offset = .zero
            committedOffset = .zero
        }
    }
}

private struct PhotoLightboxZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    let corner: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if !reduceMotion, let namespace {
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            }
        } else {
            content
        }
    }
}

private struct PhotoLightboxZoomTransition: ViewModifier {
    let sourceID: String
    let namespace: Namespace.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if !reduceMotion, let namespace {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

struct ExpandButton: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let action: () -> Void

    var body: some View {
        Button(action: { blockInteraction.performActivation(action) }) {
            ChromeGlyph(symbol: .expand)
                .foregroundStyle(Theme.ink)
                .frame(width: 42, height: 42)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.surfaceRim, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .contentShape(Circle())
        }
        .blockActivationControl()
        .buttonStyle(.plain)
        .accessibilityLabel("Expand")
    }
}
