import Foundation

public struct CardCarousel: Codable, Hashable {
    public struct Card: Codable, Hashable, Identifiable {
        public var resourceID: String? = nil
        public var saveCategory: String? = nil
        public var image: ImageSpec?
        public var imageURL: String?
        public var icon: Icon?
        public var title: String
        public var caption: String?
        public var meta: String? = nil
        public var strap: String? = nil
        public var tag: String? = nil
        public var tags: [String]? = nil
        public var preview: String? = nil
        public var prompt: String?
        public var conversation: String?
        public var automation: String?

        public var id: String {
            if let resourceID, !resourceID.isEmpty { return "resource:\(resourceID)" }
            if let conversation { return "conversation:\(conversation)" }
            if let automation { return "automation:\(automation)" }
            if let prompt { return "prompt:\(prompt)" }
            return "card:\(title):\(caption ?? "")"
        }

        public init(resourceID: String? = nil, saveCategory: String? = nil, image: ImageSpec? = nil, imageURL: String? = nil, icon: Icon? = nil, title: String, caption: String? = nil, meta: String? = nil, strap: String? = nil, tag: String? = nil, tags: [String]? = nil, preview: String? = nil, prompt: String? = nil, conversation: String? = nil, automation: String? = nil) {
            self.resourceID = resourceID
            self.saveCategory = saveCategory
            self.image = image
            self.imageURL = imageURL
            self.icon = icon
            self.title = title
            self.caption = caption
            self.meta = meta
            self.strap = strap
            self.tag = tag
            self.tags = tags
            self.preview = preview
            self.prompt = prompt
            self.conversation = conversation
            self.automation = automation
        }
    }
    public enum Layout: String, Codable, Hashable {
        case rail, grid
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Layout(rawValue: raw) ?? .rail
        }
    }
    public enum Presentation: String, Codable, Hashable {
        case standard, poster, paged
        case hotelRail, hotelList, roomGrid, roomList
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Presentation(rawValue: raw) ?? .standard
        }
    }
    public var id: String
    public var layout: Layout?
    public var presentation: Presentation?
    public var cards: [Card]

    public var isHotelFamily: Bool {
        switch presentation {
        case .hotelRail, .hotelList, .roomGrid, .roomList: true
        default: false
        }
    }

    public init(id: String, layout: Layout? = nil, presentation: Presentation? = nil, cards: [Card]) {
        self.id = id
        self.layout = layout
        self.presentation = presentation
        self.cards = cards
    }
}

extension CardCarousel.Card {
    private enum CodingKeys: String, CodingKey {
        case resourceID, saveCategory, image, imageURL, icon, title, caption, meta, strap, tag, tags, preview, prompt, conversation, automation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        resourceID = try c.decodeIfPresent(String.self, forKey: .resourceID)
        saveCategory = try? c.decodeIfPresent(String.self, forKey: .saveCategory)
        image = try c.decodeIfPresent(ImageSpec.self, forKey: .image)
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        icon = try c.decodeIfPresent(Icon.self, forKey: .icon)
        title = try c.decode(String.self, forKey: .title)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        meta = try c.decodeIfPresent(String.self, forKey: .meta)
        strap = try c.decodeIfPresent(String.self, forKey: .strap)
        tag = try c.decodeIfPresent(String.self, forKey: .tag)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        preview = try c.decodeIfPresent(String.self, forKey: .preview)
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
        conversation = try c.decodeIfPresent(String.self, forKey: .conversation)
        automation = try c.decodeIfPresent(String.self, forKey: .automation)
    }
}

public struct FeatureList: Codable, Hashable {
    public struct Item: Codable, Hashable {
        public var icon: Icon?
        public var title: String
        public var caption: String?
    }
    public var id: String
    public var items: [Item]
}

public struct Quote: Codable, Hashable {
    public var id: String
    public var text: String
    public var attribution: String?
}

public struct RatingRow: Codable, Hashable {
    public var id: String
    public var icon: Icon?
    public var text: String
}

extension CardCarousel {
    public func renderKeys(positional: Bool) -> [String] {
        cards.indices.map { positional ? "\($0)" : cards[$0].id }
    }
}

public struct MediaRowList: Codable, Hashable {
    public struct Row: Codable, Hashable {
        public var icon: Icon?
        public var title: String
        public var subtitle: String?
        public var action: Action?
        public var site: String?

        public var logoURL: URL? {
            guard icon?.image == nil else { return nil }
            let target = site.flatMap { Self.logoTarget($0, keepsPath: true) }
                ?? action?.url.flatMap { Self.logoTarget($0, keepsPath: false) }
            guard let target else { return nil }
            var components = URLComponents(string: "https://www.google.com/s2/favicons")
            components?.queryItems = [
                URLQueryItem(name: "domain", value: target),
                URLQueryItem(name: "sz", value: "128"),
            ]
            return components?.url
        }

        public static func logoTarget(_ raw: String, keepsPath: Bool) -> String? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)"),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  url.user() == nil, url.password() == nil,
                  let host = url.host()?.lowercased(), host.contains("."), !host.hasSuffix(".")
            else { return nil }
            let path = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return keepsPath && !path.isEmpty ? "\(host)/\(path)" : host
        }

        public init(icon: Icon? = nil, title: String, subtitle: String? = nil, action: Action? = nil, site: String? = nil) {
            self.icon = icon
            self.title = title
            self.subtitle = subtitle
            self.action = action
            self.site = site
        }
    }
    public var id: String
    public var title: String?
    public var rows: [Row]

    public init(id: String, title: String? = nil, rows: [Row]) {
        self.id = id
        self.title = title
        self.rows = rows
    }
}

public struct SpotList: Codable, Hashable {
    public struct Spot: Codable, Hashable {
        public var image: ImageSpec
        public var imageURL: String?
        public var name: String
        public var caption: String?
        public var rating: String?
        public var meta: String?
    }
    public var id: String
    public var spots: [Spot]
}

public struct FactList: Codable, Hashable {
    public struct Fact: Codable, Hashable {
        public var icon: Icon?
        public var label: String
        public var value: String
    }
    public var id: String
    public var facts: [Fact]
}

public struct ChipRow: Codable, Hashable {
    public enum Role: String, Codable, Hashable { case requiredChoice, followUp }

    public struct Chip: Codable, Hashable {
        public var label: String
        public var prompt: String?
        public var icon: Icon?
    }
    public var id: String
    public var role: Role?
    public var title: String?
    public var chips: [Chip]
}

public struct StatRow: Codable, Hashable {
    public struct Stat: Codable, Hashable {
        public enum Direction: String, Codable { case up, down }
        public var value: String
        public var label: String
        public var delta: String?
        public var deltaDirection: Direction?

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            value = try c.decode(String.self, forKey: .value)
            label = try c.decode(String.self, forKey: .label)
            delta = try? c.decode(String.self, forKey: .delta)
            deltaDirection = Direction(rawValue: (try? c.decode(String.self, forKey: .deltaDirection)) ?? "")
        }
    }
    public var id: String
    public var stats: [Stat]
}

public struct ItemGrid: Codable, Hashable {
    public struct Item: Codable, Hashable {
        public var icon: Icon?
        public var title: String
        public var caption: String?
    }
    public var id: String
    public var items: [Item]
    public var columns: Int?
}

public struct StepCarousel: Codable, Hashable {
    public struct Step: Codable, Hashable {
        public var icon: Icon?
        public var sfSymbol: String?
        public var railLabel: String?
        public var imageScene: String?
        public var image: ImageSpec? = nil
        public var imageURL: String? = nil
        public var title: String
        public var meta: String?
        public var body: String

        private enum CodingKeys: String, CodingKey {
            case icon, sym, sfSymbol, railLabel, imageScene, image, imageURL, title, meta, body
        }

        public init(icon: Icon? = nil, sfSymbol: String? = nil, railLabel: String? = nil,
             imageScene: String? = nil, image: ImageSpec? = nil, imageURL: String? = nil,
             title: String, meta: String? = nil, body: String) {
            self.icon = icon
            self.sfSymbol = sfSymbol
            self.railLabel = railLabel
            self.imageScene = imageScene
            self.image = image
            self.imageURL = imageURL
            self.title = title
            self.meta = meta
            self.body = body
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            icon = try? c.decode(Icon.self, forKey: .icon)
            sfSymbol = (try? c.decode(String.self, forKey: .sym))
                ?? (try? c.decode(String.self, forKey: .sfSymbol))
            railLabel = try? c.decode(String.self, forKey: .railLabel)
            imageScene = try? c.decode(String.self, forKey: .imageScene)
            image = try? c.decode(ImageSpec.self, forKey: .image)
            imageURL = try? c.decode(String.self, forKey: .imageURL)
            title = try c.decode(String.self, forKey: .title)
            meta = try? c.decode(String.self, forKey: .meta)
            body = try c.decode(String.self, forKey: .body)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(icon, forKey: .icon)
            try c.encodeIfPresent(sfSymbol, forKey: .sym)
            try c.encodeIfPresent(railLabel, forKey: .railLabel)
            try c.encodeIfPresent(imageScene, forKey: .imageScene)
            try c.encodeIfPresent(image, forKey: .image)
            try c.encodeIfPresent(imageURL, forKey: .imageURL)
            try c.encode(title, forKey: .title)
            try c.encodeIfPresent(meta, forKey: .meta)
            try c.encode(body, forKey: .body)
        }
    }
    public var id: String
    public var steps: [Step]
}

public struct ListBlock: Codable, Hashable {
    public enum Style: String, Codable { case bullet, check }
    public struct Item: Codable, Hashable {
        public var icon: Icon?
        public var text: String
    }
    public var id: String
    public var style: Style
    public var items: [Item]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        style = Style(rawValue: (try? c.decode(String.self, forKey: .style)) ?? "") ?? .bullet
        items = try c.decode([Item].self, forKey: .items)
    }
}

public struct Timeline: Codable, Hashable {
    public struct Item: Codable, Hashable {
        public var time: String
        public var title: String
        public var caption: String?
        public var icon: Icon?
    }
    public var id: String
    public var items: [Item]
}

public struct PhotoGrid: Codable, Hashable {
    public enum Layout: String, Codable, Hashable {
        case collage, grid, strip

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Layout(rawValue: raw) ?? .collage
        }
    }

    public enum Presentation: String, Codable, Hashable {
        case direct, collection

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Presentation(rawValue: raw) ?? .direct
        }
    }

    public var id: String
    public var images: [ImageSpec]
    public var layout: Layout? = nil
    public var presentation: Presentation? = nil

    public var collectionImageRows: [Range<Int>] {
        var rows: [Range<Int>] = []
        for start in stride(from: 0, to: images.count, by: 5) {
            let end = min(start + 5, images.count)
            let firstEnd = min(start + 2, end)
            let secondEnd = min(start + 4, end)
            rows.append(start..<firstEnd)
            if firstEnd < secondEnd { rows.append(firstEnd..<secondEnd) }
            if secondEnd < end { rows.append(secondEnd..<end) }
        }
        return rows
    }
}

extension PhotoGrid {
    private enum CodingKeys: String, CodingKey { case id, images, layout, presentation }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        images = try c.decode([ImageSpec].self, forKey: .images)
        layout = try c.decodeIfPresent(Layout.self, forKey: .layout)
        presentation = try? c.decodeIfPresent(Presentation.self, forKey: .presentation)
    }
}
