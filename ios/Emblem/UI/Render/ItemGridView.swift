import SwiftUI
import EmblemCore

struct ItemGridView: View {
    let block: ItemGrid

    @State private var resolvedImages: [Int: UIImage]
    @State private var imageGroupResolved = false
    @State private var gridWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cellSpacing: CGFloat = 14
    private let margin: CGFloat = 28
    private let tileRadius: CGFloat = 16
    private var columnCount: Int { max(2, min(block.columns ?? 3, 4)) }
    private var isRail: Bool { block.items.count > columnCount && block.items.count < columnCount * 2 }
    private static let semanticEmoji: [([String], String)] = [
        (["eggplant", "aubergine"], "🍆"),
        (["lentil", "bean"], "🫘"),
        (["onion"], "🧅"),
        (["garlic"], "🧄"),
        (["tomato"], "🍅"),
        (["pepper", "chili", "paprika"], "🌶️"),
        (["parsley", "herb", "basil", "mint"], "🌿"),
        (["olive", "oil"], "🫒"),
        (["salt"], "🧂"),
        (["spice", "cumin"], "🫙"),
        (["coffee"], "☕️"),
        (["tea"], "🍵"),
        (["water"], "💧"),
        (["milk"], "🥛"),
        (["bread"], "🍞"),
        (["fruit", "apple"], "🍎"),
    ]
    private static let semanticSymbols: [([String], String)] = [
        (["bag", "luggage", "travel"], "suitcase.fill"),
        (["shoe", "sneaker", "boot"], "shoe.2.fill"),
        (["shirt", "clothing", "outfit"], "tshirt.fill"),
        (["book", "read"], "book.closed.fill"),
        (["phone", "mobile"], "iphone"),
        (["computer", "laptop"], "laptopcomputer"),
        (["music", "audio"], "music.note"),
        (["calendar", "date"], "calendar"),
        (["medicine", "health"], "cross.case.fill"),
        (["tool", "repair"], "wrench.and.screwdriver.fill"),
    ]

    init(block: ItemGrid) {
        self.block = block
        _resolvedImages = State(initialValue: Self.cachedImages(for: block))
    }

    private var cellWidth: CGFloat {
        let width = gridWidth > 0 ? gridWidth : 390 - margin * 2
        return ((width - cellSpacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)).rounded(.down)
    }

    var body: some View {
        Group {
            if isRail { rail } else { grid }
        }
        .task(id: block) {
            let cached = Self.cachedImages(for: block)
            resolvedImages = cached
            imageGroupResolved = false
            let loaded = await loadImageGroup()
            guard !Task.isCancelled else { return }
            let images = cached.merging(loaded) { _, latest in latest }
            if reduceMotion {
                resolvedImages = images
                imageGroupResolved = true
            } else {
                withAnimation(.imageArrival) {
                    resolvedImages = images
                    imageGroupResolved = true
                }
            }
        }
    }

    private var widthProbe: some View {
        Color.clear
            .frame(height: 0)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
    }

    private var grid: some View {
        let indexedItems = Array(block.items.enumerated())
        let rows = stride(from: 0, to: indexedItems.count, by: columnCount).map {
            Array(indexedItems[$0..<min($0 + columnCount, indexedItems.count)])
        }
        return VStack(alignment: .leading, spacing: 0) {
            widthProbe
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(alignment: .top, spacing: cellSpacing) {
                    ForEach(row, id: \.offset) { index, item in
                        tile(item, at: index, centered: true).frame(width: cellWidth)
                    }
                }
                .padding(.top, rowIndex == 0 ? 0 : 24)
            }
        }
        .padding(.horizontal, margin)
    }

    private var rail: some View {
        VStack(spacing: 0) {
            widthProbe.padding(.horizontal, margin)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: cellSpacing) {
                    ForEach(Array(block.items.enumerated()), id: \.offset) { index, item in
                        tile(item, at: index, centered: false).frame(width: cellWidth)
                    }
                }
                .padding(.horizontal, margin)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollBounceBehavior(.basedOnSize)
            .scrollClipDisabled()
        }
    }

    private func tile(_ item: ItemGrid.Item, at index: Int, centered: Bool) -> some View {
        tileBody(item, at: index, centered: centered)
            .modifier(ExpandsIntoSubpage(
                card: CardCarousel.Card(
                    image: item.icon?.image,
                    imageURL: nil,
                    icon: item.icon,
                    title: item.title,
                    caption: item.caption,
                    prompt: "Tell me more about \(item.title)" +
                        "\(item.caption.map { " (\($0))" } ?? "")."),
                blockID: block.id))
    }

    private func tileBody(_ item: ItemGrid.Item, at index: Int, centered: Bool) -> some View {
        let image = resolvedImages[index]
        let fallback = fallbackIcon(for: item)
        let shape = RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
        let isPhoto = item.icon?.image.map { $0.kind != .object } == true
        return VStack(spacing: 8) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ZStack {
                        Theme.itemTile
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: isPhoto ? .fill : .fit)
                                .padding(isPhoto ? 0 : 10)
                                .transition(reduceMotion ? .opacity : isPhoto ? .imageArrival : .objectArrival)
                        } else if !imageGroupResolved {
                            ObjectImageLoadingPlaceholder()
                        } else if !isPhoto, let fallback {
                            IconView(icon: fallback, size: 56)
                        }
                    }
                }
                .clipShape(shape)
                .modifier(PhotoTileShadow(enabled: isPhoto))
                .contentShape(shape)
            itemLabel(item, centered: centered)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private struct PhotoTileShadow: ViewModifier {
        let enabled: Bool
        func body(content: Content) -> some View {
            if enabled { content.modifier(MediaArtworkShadow()) } else { content }
        }
    }

    private func itemLabel(_ item: ItemGrid.Item, centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 1) {
            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            if let caption = item.caption {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .multilineTextAlignment(centered ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .padding(.horizontal, 4)
    }

    private func loadImageGroup() async -> [Int: UIImage] {
        let specs = block.items.enumerated().map { index, item in
            (index, Self.objectSpec(for: item))
        }
        guard !specs.isEmpty else { return [:] }

        return await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, spec) in specs {
                group.addTask {
                    let image = await ImageLoader.shared.image(for: spec, maxPixelSize: 320)
                    return (index, image)
                }
            }

            var images: [Int: UIImage] = [:]
            for await (index, image) in group {
                if let image { images[index] = image }
            }
            return images
        }
    }

    private static func objectSpec(for item: ItemGrid.Item) -> ImageSpec {
        if let image = item.icon?.image {
            return image.targeting(.square)
        }
        return ImageSpec(query: item.title, kind: .object, aspect: .square)
    }

    private static func cachedImages(for block: ItemGrid) -> [Int: UIImage] {
        block.items.enumerated().reduce(into: [:]) { images, element in
            let (index, item) = element
            let spec = objectSpec(for: item)
            guard let image = ImageLoader.shared.cachedImage(for: spec, maxPixelSize: 320)
            else { return }
            images[index] = image
        }
    }

    private func fallbackIcon(for item: ItemGrid.Item) -> Icon? {
        if let emoji = item.icon?.emoji, !emoji.isEmpty {
            return Icon(emoji: emoji)
        }
        if let symbol = item.icon?.sfSymbol, Hugeicons.isRenderable(symbol) {
            return Icon(sfSymbol: symbol)
        }

        guard item.icon?.image == nil else { return nil }

        let subject = "\(item.icon?.image?.query ?? "") \(item.title)".lowercased()
        let words = subject.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        func matches(_ terms: [String]) -> Bool {
            terms.contains { term in words.contains { $0.hasPrefix(term) } }
        }
        if let match = Self.semanticEmoji.first(where: { terms, _ in
            matches(terms)
        }) {
            return Icon(emoji: match.1)
        }

        if let match = Self.semanticSymbols.first(where: { terms, _ in
            matches(terms)
        }) {
            return Icon(sfSymbol: match.1)
        }
        return nil
    }
}
