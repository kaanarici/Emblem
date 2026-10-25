import SwiftUI
import EmblemCore

struct FeatureListView: View {
    let block: FeatureList
    @Environment(\.renderedPage) private var renderedPage

    private var showsIcons: Bool {
        ListIconPolicy.showsIcons(block.items.map(\.icon))
    }

    private var compact: Bool {
        block.items.allSatisfy { $0.caption?.isEmpty ?? true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 13 : 18.5) {
            ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: compact ? .center : .top, spacing: compact ? 15.5 : 12) {
                    if showsIcons {
                        IconView(icon: item.icon, size: compact ? 19 : 24, loadingSkeleton: true)
                    }
                    ListRowText(title: item.title, caption: item.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, renderedPage?.isHome == true ? Theme.homeMargin : 32)
    }
}

struct ListRowText: View {
    let title: String
    let caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 16))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct MediaRowListView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(\.renderedPage) private var renderedPage
    let block: MediaRowList
    @Environment(\.performAction) private var performAction

    private var showsStandardIcons: Bool {
        ListIconPolicy.showsIcons(block.rows.map(\.icon))
            || block.rows.allSatisfy { $0.logoURL != nil }
    }

    var body: some View {
        if block.id == "next-event-actions" || block.id == "daily-update" {
            EmptyView()
        } else {
            standardList
        }
    }

    private var standardList: some View {
        VStack(spacing: 12) {
            if let title = block.title, !title.isEmpty {
                Text(title)
                    .font(Theme.cardTitle())
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 5.5) {
                ForEach(Array(block.rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 12) {
                        if showsStandardIcons {
                            rowThumb(row)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                            if let subtitle = row.subtitle {
                                Text(subtitle)
                                    .font(.system(size: 14))
                                    .lineSpacing(1.5)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .lineLimit(3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, -4)
                        if let action = row.action, action.hasSupportedDestination || renderedPage?.isPreviewing == true {
                            Button {
                                guard blockInteraction.allowsActivation else { return }
                                performAction(action)
                            } label: {
                                Text(action.label)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 11)
                                    .frame(minWidth: 56, minHeight: 36)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Theme.rowButtonStroke, lineWidth: 1.2))
                            }
                            .blockActivationControl()
                            .buttonStyle(.pressable)
                            .accessibilityLabel("\(action.label) \(row.title)")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11.5)
                    .frame(minHeight: 72)
                    .background(GroupedRowShape(index: index, count: block.rows.count)
                        .fill(Theme.rowFill))
                }
            }
            .groupedRowShadow()
        }
        .padding(.horizontal, 28)
    }

    @ViewBuilder
    private func rowThumb(_ row: MediaRowList.Row) -> some View {
        if let image = row.icon?.image {
            RemoteImage(spec: image, maxPixelSize: 120)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else if let logoURL = row.logoURL {
            ActionRowLogo(url: logoURL, fallback: row.icon ?? Icon(sfSymbol: "globe"))
        } else if row.icon != nil {
            ActionRowSymbolTile(icon: row.icon)
        }
    }
}

private struct ActionRowSymbolTile: View {
    let icon: Icon?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
                .frame(width: 48, height: 48)
            IconView(icon: icon, size: 24)
        }
    }
}

private struct ActionRowLogo: View {
    let url: URL
    let fallback: Icon
    @State private var logo: UIImage?
    @State private var settled = false

    init(url: URL, fallback: Icon) {
        self.url = url
        self.fallback = fallback
        _logo = State(initialValue: Self.usable(ImageLoader.shared.cachedImage(at: url, maxPixelSize: 128)))
    }

    var body: some View {
        Group {
            if let logo {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                Group {
                    if Self.isFullBleed(logo) {
                        Image(uiImage: logo)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(shape)
                            .overlay(shape.strokeBorder(.black.opacity(0.06), lineWidth: 0.5))
                    } else {
                        Image(uiImage: logo)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .frame(width: 48, height: 48)
                            .background(Theme.surface, in: shape)
                    }
                }
                .transition(.objectArrival)
            } else if settled {
                ActionRowSymbolTile(icon: fallback)
            } else {
                ShimmerTile()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .task(id: url) {
            guard logo == nil else { return }
            let loaded = Self.usable(await ImageLoader.shared.image(at: url, maxPixelSize: 128))
            guard !Task.isCancelled else { return }
            withAnimation(.objectArrival) {
                logo = loaded
                settled = true
            }
        }
    }

    private static func usable(_ image: UIImage?) -> UIImage? {
        guard let image, image.size.width * image.scale >= 32 else { return nil }
        return image
    }

    private static func isFullBleed(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        let mid = side / 2
        let edges = [(mid, 0), (mid, side - 1), (0, mid), (side - 1, mid)]
        return edges.allSatisfy { x, y in pixels[(y * side + x) * 4 + 3] > 240 }
    }
}
