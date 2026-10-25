import Foundation

extension GenerateClient {
    public struct HomeBody: Encodable, Equatable, Sendable {
        let name: String?
        let timezone: String
        let nextEventTitle: String?
        let nextEventStart: Double?

        public init(name: String?, timezone: String, nextEventTitle: String?, nextEventStart: Date?) {
            self.name = name
            self.timezone = timezone
            self.nextEventTitle = nextEventTitle
            self.nextEventStart = nextEventStart?.timeIntervalSince1970
        }
    }

    public struct Message: Encodable, Equatable, Sendable {
        let role: String
        let content: String

        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    public struct WireAttachment: Encodable, Equatable, Sendable {
        let kind: String
        let name: String
        let dataURL: String
        let text: String?

        public init(kind: String, name: String, dataURL: String, text: String?) {
            self.kind = kind
            self.name = name
            self.dataURL = dataURL
            self.text = text
        }
    }

    public struct WireLocation: Encodable, Equatable, Sendable {
        let city: String?
        let region: String?
        let country: String?
        let latitude: Double?
        let longitude: Double?
    }

    public struct GenerateBody: Encodable, Equatable, Sendable {
        public struct SavedSelection: Encodable, Equatable, Sendable {
            let parentPageKey: String
            let sourceCardKey: String
            let blockID: String
            private let cardJSON: Data

            @MainActor
            public init(entity: SavedEntity) throws {
                parentPageKey = entity.origin.parentPageKey
                sourceCardKey = entity.origin.sourceCardKey
                blockID = entity.origin.blockID
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                cardJSON = try encoder.encode(entity.card)
            }

            private enum CodingKeys: String, CodingKey { case parentPageKey, sourceCardKey, blockID, card }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(parentPageKey, forKey: .parentPageKey)
                try container.encode(sourceCardKey, forKey: .sourceCardKey)
                try container.encode(blockID, forKey: .blockID)
                try container.encode(JSONDecoder().decode(CardCarousel.Card.self, from: cardJSON), forKey: .card)
            }
        }

        let messages: [Message]
        let requestId: String
        let conversationKey: String
        let previousPageKey: String?
        let parentPageKey: String?
        let sourceCardKey: String?
        let sourceCardTitle: String?
        let sourceCardHasImage: Bool?
        let calendarEvent: CalendarEventDetails?
        let drillInPresentation: String?
        let savedSelection: SavedSelection?
        let attachments: [WireAttachment]?
        let location: WireLocation?
        let timezone: String?
        let memory: Bool
        let device: [String]?
        let retry: Bool?

        public init(
            messages: [Message],
            requestId: String,
            conversationKey: String,
            previousPageKey: String? = nil,
            parentPageKey: String? = nil,
            sourceCardKey: String? = nil,
            sourceCardTitle: String? = nil,
            sourceCardHasImage: Bool? = nil,
            savedSelection: SavedSelection? = nil,
            calendarEvent: CalendarEventDetails? = nil,
            attachments: [WireAttachment]? = nil,
            location: WireLocation? = nil,
            timezone: String? = TimeZone.current.identifier,
            memory: Bool = UserDefaults.standard.object(forKey: "memory.enabled") == nil
                ? true
                : UserDefaults.standard.bool(forKey: "memory.enabled"),
            device: [String]? = nil,
            retry: Bool? = nil
        ) {
            self.messages = messages
            self.requestId = requestId
            self.conversationKey = conversationKey
            self.previousPageKey = previousPageKey
            self.parentPageKey = parentPageKey
            self.sourceCardKey = sourceCardKey
            self.sourceCardTitle = sourceCardTitle
            self.sourceCardHasImage = sourceCardHasImage
            self.calendarEvent = calendarEvent
            drillInPresentation = calendarEvent == nil ? nil : "article"
            self.savedSelection = savedSelection
            self.attachments = attachments
            self.location = location
            self.timezone = timezone
            self.memory = memory
            self.device = device
            self.retry = retry
        }

        func retrying() -> GenerateBody {
            GenerateBody(
                messages: messages,
                requestId: requestId,
                conversationKey: conversationKey,
                previousPageKey: previousPageKey,
                parentPageKey: parentPageKey,
                sourceCardKey: sourceCardKey,
                sourceCardTitle: sourceCardTitle,
                sourceCardHasImage: sourceCardHasImage,
                savedSelection: savedSelection,
                calendarEvent: calendarEvent,
                attachments: attachments,
                location: location,
                timezone: timezone,
                memory: memory,
                device: device,
                retry: true)
        }
    }
}
