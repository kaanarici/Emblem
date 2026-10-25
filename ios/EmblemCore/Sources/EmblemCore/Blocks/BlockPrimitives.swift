import Foundation

public struct ImageSpec: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case poster, still, logo, photo, object, generated }
    public enum Aspect: String, Codable, Sendable { case square, portrait, landscape }
    public var query: String
    public var kind: Kind
    public var aspect: Aspect?

    public init(query: String, kind: Kind, aspect: Aspect? = nil) {
        self.query = query
        self.kind = kind
        self.aspect = aspect
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query = try c.decode(String.self, forKey: .query)
        kind = Kind(rawValue: (try? c.decode(String.self, forKey: .kind)) ?? "") ?? .photo
        aspect = try? c.decode(Aspect.self, forKey: .aspect)
    }

    public func targeting(_ aspect: Aspect) -> ImageSpec {
        ImageSpec(query: query, kind: kind, aspect: aspect)
    }
}

public struct Icon: Codable, Hashable {
    public var emoji: String?
    public var sfSymbol: String?
    public var image: ImageSpec?
    public var color: String?

    public init(emoji: String? = nil, sfSymbol: String? = nil, image: ImageSpec? = nil, color: String? = nil) {
        self.emoji = emoji
        self.sfSymbol = sfSymbol
        self.image = image
        self.color = color
    }

    private enum CodingKeys: String, CodingKey { case emoji, sym, image, color }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        emoji = try? c.decode(String.self, forKey: .emoji)
        sfSymbol = try? c.decode(String.self, forKey: .sym)
        image = try? c.decode(ImageSpec.self, forKey: .image)
        color = try? c.decode(String.self, forKey: .color)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(emoji, forKey: .emoji)
        try c.encodeIfPresent(sfSymbol, forKey: .sym)
        try c.encodeIfPresent(image, forKey: .image)
        try c.encodeIfPresent(color, forKey: .color)
    }
}

public struct Action: Codable, Hashable {
    public var label: String
    public var sfSymbol: String?
    public var url: String?
    public var prompt: String?
    public var conversation: String?
    public var native: String?
    public var destination: DirectionsTarget?
    public var openAutomation: String?
    public var hasSupportedDestination: Bool {
        url != nil || prompt != nil || conversation != nil ||
            openAutomation != nil || automation != nil || calendar != nil ||
            (native == "directions" && destination != nil)
    }
    public var automation: AutomationSpec?
    public var calendar: CalendarSpec?
    public var expansion: Bool? = nil

    public struct AutomationSpec: Codable, Hashable {
        public var idempotencyKey: String? = nil
        public var title: String
        public var prompt: String
        public var hour: Int
        public var minute: Int
        public var weekdays: [Int]?
    }

    public struct CalendarSpec: Codable, Hashable {
        public var idempotencyKey: String
        public var title: String
        public var date: String
        public var durationMinutes: Int
        public var timeAnswerKey: String
    }

    public init(label: String, sfSymbol: String? = nil, url: String? = nil,
         prompt: String? = nil, conversation: String? = nil, native: String? = nil,
         destination: DirectionsTarget? = nil, openAutomation: String? = nil,
         automation: AutomationSpec? = nil, calendar: CalendarSpec? = nil,
         expansion: Bool? = nil) {
        self.label = label
        self.sfSymbol = sfSymbol
        self.url = url
        self.prompt = prompt
        self.conversation = conversation
        self.native = native
        self.destination = destination
        self.openAutomation = openAutomation
        self.automation = automation
        self.calendar = calendar
        self.expansion = expansion
    }

    private enum CodingKeys: String, CodingKey {
        case label, sym, url, prompt, conversation, native, destination
        case openAutomation, automation, calendar, expansion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        sfSymbol = try? c.decode(String.self, forKey: .sym)
        url = try? c.decode(String.self, forKey: .url)
        prompt = try? c.decode(String.self, forKey: .prompt)
        conversation = try? c.decode(String.self, forKey: .conversation)
        native = try? c.decode(String.self, forKey: .native)
        destination = try? c.decode(DirectionsTarget.self, forKey: .destination)
        openAutomation = try? c.decode(String.self, forKey: .openAutomation)
        automation = try? c.decode(AutomationSpec.self, forKey: .automation)
        calendar = try? c.decode(CalendarSpec.self, forKey: .calendar)
        expansion = try? c.decode(Bool.self, forKey: .expansion)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encodeIfPresent(sfSymbol, forKey: .sym)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(prompt, forKey: .prompt)
        try c.encodeIfPresent(conversation, forKey: .conversation)
        try c.encodeIfPresent(native, forKey: .native)
        try c.encodeIfPresent(destination, forKey: .destination)
        try c.encodeIfPresent(openAutomation, forKey: .openAutomation)
        try c.encodeIfPresent(automation, forKey: .automation)
        try c.encodeIfPresent(calendar, forKey: .calendar)
        try c.encodeIfPresent(expansion, forKey: .expansion)
    }
}

public struct DirectionsTarget: Codable, Hashable, Identifiable {
    public enum Mode: String, Codable, Hashable {
        case driving, walking, transit, cycling

        public var googleMapsMode: String { self == .cycling ? "bicycling" : rawValue }
    }

    public var name: String
    public var locality: String?
    public var query: String
    public var mode: Mode
    public var id: String { "\(mode.rawValue):\(query)" }

    public init(name: String, locality: String? = nil, query: String, mode: Mode) {
        self.name = name
        self.locality = locality
        self.query = query
        self.mode = mode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        locality = try? container.decode(String.self, forKey: .locality)
        query = try container.decode(String.self, forKey: .query)
        mode = Mode(rawValue: (try? container.decode(String.self, forKey: .mode)) ?? "") ?? .driving
    }
}
