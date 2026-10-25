import SwiftUI
import EmblemCore

private func sourceCountTitle(_ count: Int) -> String {
    count == 0 ? "Sources" : "\(count) \(count == 1 ? "source" : "sources")"
}

private func connectorIcon(_ source: String) -> UIImage? {
    UIImage(named: "connector-\(source)")
}

private enum SourceMark: Identifiable {
    case connector(UIImage, String)
    case site(CitationSource)

    var id: String {
        switch self {
        case .connector(_, let source): "connector:\(source)"
        case .site(let site): site.id
        }
    }
}

struct SourceDisclosure: View {
    let sources: [CitationSource]
    var activities: [SourceActivity] = []
    @State private var isPresented = false

    private var completedActivities: [SourceActivity] {
        activities.filter { $0.status != "started" && $0.source != "web" }
    }

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 8) {
                Text(sourceCountTitle(sources.count))
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                if marks.isEmpty {
                    Image(systemName: sourceSymbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 20, height: 20)
                } else {
                    FaviconStack(marks: marks)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
            }
            .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.06), lineWidth: 0.5))
            .fixedSize()
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(SourcePressStyle())
        .accessibilityLabel("Show sources")
        .accessibilityValue(sourceCountTitle(sources.count))
        .padding(.horizontal, Theme.textMargin)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .sheet(isPresented: $isPresented) {
            SourcesSheet(sources: sources, activities: completedActivities)
                .presentationDetents([.fraction(0.55), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
                .presentationContentInteraction(.scrolls)
        }
    }

    private var marks: [SourceMark] {
        var seen = Set<String>()
        let connectors = completedActivities.compactMap { activity -> SourceMark? in
            guard seen.insert(activity.source).inserted, let icon = connectorIcon(activity.source) else { return nil }
            return .connector(icon, activity.source)
        }
        return Array((connectors + sources.map(SourceMark.site)).prefix(5))
    }

    private var sourceSymbol: String {
        switch completedActivities.first?.source {
        case "weather": "cloud.sun"
        case "gmail": "envelope"
        case "googlecalendar": "calendar"
        case "memory": "brain"
        default: "sparkle.magnifyingglass"
        }
    }
}

private struct FaviconStack: View {
    let marks: [SourceMark]

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(marks.enumerated()), id: \.element.id) { index, mark in
                Group {
                    switch mark {
                    case .connector(let icon, _):
                        Image(uiImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Theme.surface, lineWidth: 2))
                    case .site(let source):
                        SourceFavicon(source: source, size: 20)
                            .background(Circle().fill(Theme.surface))
                            .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                    }
                }
                .offset(x: CGFloat(index) * 13)
                .zIndex(Double(marks.count - index))
            }
        }
        .frame(
            width: CGFloat(20 + max(0, marks.count - 1) * 13),
            height: 20,
            alignment: .leading)
    }
}

private struct SourcesSheet: View {
    let sources: [CitationSource]
    let activities: [SourceActivity]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text(sourceCountTitle(sources.count))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 24)
                .padding(.bottom, 42)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(activities) { activity in
                        ActivityRow(activity: activity)
                    }
                    ForEach(sources) { source in
                        SourceRow(source: source)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.surface)
        .accessibilityAction(.escape) { dismiss() }
    }
}

private struct ActivityRow: View {
    let activity: SourceActivity

    var body: some View {
        HStack(spacing: 12) {
            if let icon = connectorIcon(activity.source) {
                Image(uiImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 34, height: 34)
                    .background(Theme.chip, in: Circle())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(activity.message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 8)
            Image(systemName: statusSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(activity.status == "failed" ? Color.orange : Theme.inkSecondary)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var symbol: String {
        switch activity.source {
        case "weather": "cloud.sun"
        case "gmail": "envelope"
        case "googlecalendar": "calendar"
        case "memory": "brain"
        case "web": "globe"
        default: "sparkles"
        }
    }

    private var statusSymbol: String {
        switch activity.status {
        case "failed": "exclamationmark"
        case "empty": "minus"
        default: "checkmark"
        }
    }
}

private struct SourceRow: View {
    let source: CitationSource
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let url = URL(string: source.url) {
            Link(destination: url) { content }
                .buttonStyle(SourcePressStyle())
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SourceFavicon(source: source, size: 20)
                Text(source.domain.lowercased())
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            Text(source.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .multilineTextAlignment(.leading)
            if !excerpt.isEmpty {
                Text(excerpt)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var excerpt: String {
        [displayDate, source.snippet?.trimmingCharacters(in: .whitespacesAndNewlines)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ": ")
    }

    private var displayDate: String? {
        guard let raw = source.publishedAt else { return nil }
        let parser = ISO8601DateFormatter()
        var date = parser.date(from: raw)
        if date == nil {
            parser.formatOptions.insert(.withFractionalSeconds)
            date = parser.date(from: raw)
        }
        if date == nil {
            parser.formatOptions = [.withFullDate]
            date = parser.date(from: raw)
            if raw.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
                var calendarDateStyle = Date.FormatStyle.dateTime.month(.wide).day().year()
                calendarDateStyle.timeZone = TimeZone(secondsFromGMT: 0)!
                return date?.formatted(calendarDateStyle)
            }
        }
        return date?.formatted(.dateTime.month(.wide).day().year())
    }
}

private struct SourceFavicon: View {
    let source: CitationSource
    let size: CGFloat
    @State private var image: UIImage?
    @State private var settled = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
                    .transition(.opacity)
            } else if !settled {
                Color.clear
            } else {
                Image(systemName: "globe")
                    .font(.system(size: max(9, size * 0.7)))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.chip, in: Circle())
        .clipShape(Circle())
        .task(id: source.id) {
            for url in candidateURLs {
                if let loaded = await ImageLoader.shared.image(at: url, maxPixelSize: size * 3) {
                    withAnimation(.easeOut(duration: 0.3)) { image = loaded }
                    return
                }
            }
            guard !Task.isCancelled else { return }
            settled = true
        }
    }

    private var candidateURLs: [URL] {
        var urls: [URL] = []
        if let favicon = source.favicon, let url = URL(string: favicon) {
            urls.append(url)
        }
        if let fallback = URL(string: "https://icons.duckduckgo.com/ip3/\(source.domain).ico") {
            urls.append(fallback)
        }
        return urls
    }
}

private struct SourcePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
