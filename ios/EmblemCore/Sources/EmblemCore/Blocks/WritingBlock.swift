import Foundation

public struct WritingBlock: Codable, Hashable {
    public var id: String
    public var title: String?
    public var drafts: [Draft]

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        drafts = try values.decode([Draft].self, forKey: .drafts)
        guard (1...5).contains(drafts.count), Set(drafts.map(\.id)).count == drafts.count,
            drafts.allSatisfy({
                !$0.id.isEmpty && !$0.label.isEmpty
                    && !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.body.utf16.count <= 20000
            })
        else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid writing drafts"))
        }
    }

    public struct Draft: Codable, Hashable, Identifiable {
        public var id: String
        public var label: String
        public var sym: String?
        public var body: String
    }
}
