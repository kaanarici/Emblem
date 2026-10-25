import Foundation

public struct InputSpec: Codable, Hashable {
    public enum Kind: String, Codable { case choice, date, dateRange, count, place, area, text, time }
    public var kind: Kind
    public var options: [String]?
    public var min: Double?
    public var max: Double?
    public var unit: String?
    public var step: Double?
    public var value: Double?
    public var ask: String?
    public var icons: [String]?
    public var look: String?
    public var areas: [AreaSpot]?

    public init(kind: Kind, options: [String]? = nil, min: Double? = nil, max: Double? = nil, unit: String? = nil,
         step: Double? = nil, value: Double? = nil,
         ask: String? = nil, icons: [String]? = nil, look: String? = nil, areas: [AreaSpot]? = nil) {
        self.kind = kind
        self.options = options
        self.min = min
        self.max = max
        self.unit = unit
        self.step = step
        self.value = value
        self.ask = ask
        self.icons = icons
        self.look = look
        self.areas = areas
    }

    public enum Presentation { case rows, chips, cards([Icon]) }

    public var presentation: Presentation {
        if let icons, let options, icons.count == options.count,
           icons.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return .cards(icons.map { Icon(image: ImageSpec(query: $0, kind: .object)) })
        }
        return look == "chips" ? .chips : .rows
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = Kind(rawValue: (try? c.decode(String.self, forKey: .kind)) ?? "") ?? .text
        options = try? c.decode([String].self, forKey: .options)
        min = try? c.decode(Double.self, forKey: .min)
        max = try? c.decode(Double.self, forKey: .max)
        unit = try? c.decode(String.self, forKey: .unit)
        step = try? c.decode(Double.self, forKey: .step)
        value = try? c.decode(Double.self, forKey: .value)
        ask = try? c.decode(String.self, forKey: .ask)
        icons = try? c.decode([String].self, forKey: .icons)
        look = try? c.decode(String.self, forKey: .look)
        areas = try? c.decode([AreaSpot].self, forKey: .areas)
    }
}

public struct AreaSpot: Codable, Hashable {
    public var label: String
    public var sym: String?
    public var icon: String?
    public var lat: Double
    public var lng: Double
    public var km: Double

    public init(label: String, sym: String? = nil, icon: String? = nil, lat: Double, lng: Double, km: Double) {
        self.label = label
        self.sym = sym
        self.icon = icon
        self.lat = lat
        self.lng = lng
        self.km = km
    }
}

public struct QuestionList: Codable, Hashable {
    public struct Item: Codable, Hashable {
        public var icon: Icon?
        public var question: String
        public var answer: String
        public var input: InputSpec?
    }
    public var id: String
    public var items: [Item]
}

public struct TimeAsk: Codable, Hashable {
    public struct Suggestion: Codable, Hashable {
        public var label: String
        public var time: String
    }
    public var id: String
    public var icon: Icon?
    public var question: String
    public var defaultTime: String?
    public var suggestions: [Suggestion]?
}

extension QuestionList {
    public var inlineChoice: (item: Item, options: [String])? {
        guard items.count == 1, let item = items.first, let input = item.input,
              input.kind == .choice || input.kind == .place,
              let options = input.options, !options.isEmpty
        else { return nil }
        return (item, options)
    }

    public var inlineCount: Item? {
        guard items.count == 1, let item = items.first, item.input?.kind == .count else { return nil }
        return item
    }

    public var inlineArea: Item? {
        guard items.count == 1, let item = items.first, item.input?.kind == .area else { return nil }
        return item
    }
}
