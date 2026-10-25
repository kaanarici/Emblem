import Foundation

public struct PageMeta: Codable, Hashable {
    public var id: String
    public var title: String?
    public var ask: Bool?
    public var dockAction: Action?
    public var savePresentation: SavedPagePresentation?
    public var saveCover: SavedPageArtwork?

    public init(id: String, title: String? = nil, dockAction: Action? = nil,
         savePresentation: SavedPagePresentation? = nil, saveCover: SavedPageArtwork? = nil) {
        self.id = id
        self.title = title
        self.dockAction = dockAction
        self.savePresentation = savePresentation
        self.saveCover = saveCover
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        ask = try? c.decodeIfPresent(Bool.self, forKey: .ask)
        dockAction = try c.decodeIfPresent(Action.self, forKey: .dockAction)
        savePresentation = try? c.decodeIfPresent(SavedPagePresentation.self, forKey: .savePresentation)
        saveCover = c.contains(.saveCover)
            ? (try? c.decode(SavedPageArtwork.self, forKey: .saveCover)) ?? .unavailable
            : nil
    }
}

public struct TextBlock: Codable, Hashable {
    public enum Style: String, Codable { case intro, body, footnote }
    public var id: String
    public var body: String
    public var style: Style
    public var highlights: [String]?

    public init(id: String, body: String, style: Style, highlights: [String]? = nil) {
        self.id = id
        self.body = body
        self.style = style
        self.highlights = highlights
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        body = try c.decode(String.self, forKey: .body)
        style = Style(rawValue: (try? c.decode(String.self, forKey: .style)) ?? "") ?? .body
        highlights = try? c.decodeIfPresent([String].self, forKey: .highlights)
    }

    public func highlightRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
        guard let highlights, !highlights.isEmpty else { return [] }
        let visible = String(text.characters)
        let boundaries = Set(visible.indices).union([visible.endIndex])
        let matches = highlights.prefix(6).compactMap { anchor -> Range<AttributedString.Index>? in
            guard !anchor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  anchor.utf16.count <= 120,
                  let range = visible.range(of: anchor, options: .literal),
                  boundaries.contains(range.lowerBound), boundaries.contains(range.upperBound),
                  let start = AttributedString.Index(range.lowerBound, within: text),
                  let end = AttributedString.Index(range.upperBound, within: text) else { return nil }
            return start..<end
        }.sorted { $0.lowerBound < $1.lowerBound }
        return matches.reduce(into: []) { ranges, range in
            if let last = ranges.last, range.lowerBound <= last.upperBound {
                ranges[ranges.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                ranges.append(range)
            }
        }
    }
}

public struct Hero: Codable, Hashable {
    public enum Aspect: String, Codable { case poster, wide, square }
    public var id: String
    public var image: ImageSpec
    public var imageURL: String?
    public var aspect: Aspect

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        image = try c.decode(ImageSpec.self, forKey: .image)
        imageURL = try? c.decode(String.self, forKey: .imageURL)
        aspect = Aspect(rawValue: (try? c.decode(String.self, forKey: .aspect)) ?? "") ?? .poster
    }
}

public struct TitleBlock: Codable, Hashable {
    public var id: String
    public var title: String
    public var metaLine: String?
    public var summary: String?
    public var tags: [String]?
    public var actions: [Action]?
    public var icon: Icon?

    public init(id: String, title: String, metaLine: String? = nil, summary: String? = nil, tags: [String]? = nil, actions: [Action]? = nil, icon: Icon? = nil) {
        self.id = id
        self.title = title
        self.metaLine = metaLine
        self.summary = summary
        self.tags = tags
        self.actions = actions
        self.icon = icon
    }
}

public struct SectionHeader: Codable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String?

    public init(id: String, title: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}
