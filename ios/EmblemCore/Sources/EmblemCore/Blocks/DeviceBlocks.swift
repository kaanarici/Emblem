import Foundation

public struct EventCard: Codable, Hashable {
    public struct Event: Codable, Hashable {
        public var timeRange: String
        public var title: String
        public var place: String?
        public var icon: Icon?
        public var prompt: String?

        public init(timeRange: String, title: String, place: String? = nil, icon: Icon? = nil, prompt: String? = nil) {
            self.timeRange = timeRange
            self.title = title
            self.place = place
            self.icon = icon
            self.prompt = prompt
        }
    }
    public var id: String
    public var dayLabel: String
    public var events: [Event]

    public init(id: String, dayLabel: String, events: [Event]) {
        self.id = id
        self.dayLabel = dayLabel
        self.events = events
    }
}

public struct MusicBlock: Codable, Hashable {
    public struct Track: Codable, Hashable {
        public var name: String
        public var artist: String
        public var album: String?
        public var art: URL?
        public var preview: URL?
        public var url: URL?
    }
    public var id: String
    public var title: String?
    public var tracks: [Track]
}

public struct RemindersBlock: Codable, Hashable {
    public enum Scope: String, Codable, Hashable { case today, upcoming, all }
    public var id: String
    public var scope: Scope
    public var list: String?
    public var add: [String]?

    public init(id: String, scope: Scope, list: String? = nil, add: [String]? = nil) {
        self.id = id
        self.scope = scope
        self.list = list
        self.add = add
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        scope = Scope(rawValue: (try? c.decode(String.self, forKey: .scope)) ?? "") ?? .today
        list = try? c.decodeIfPresent(String.self, forKey: .list)
        add = try? c.decodeIfPresent([String].self, forKey: .add)
    }
}

public struct ContactBlock: Codable, Hashable {
    public var id: String
    public var name: String
    public var draft: String?
}

public struct HomeControlBlock: Codable, Hashable {
    public var id: String
    public var q: String?
}
