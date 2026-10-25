import Foundation

enum SavedOrganization {
    struct Category: Codable, Hashable {
        let key: String
        let title: String
    }
    struct Item: Codable, Equatable {
        let id: String
        let title: String
        let summary: String
    }
    struct Request: Codable {
        let items: [Item]
        let categories: [Category]
    }
    struct Assignment: Codable {
        let id: String
        let categoryKey: String
        let categoryTitle: String
    }
    struct Response: Codable {
        let assignments: [Assignment]
    }

    @MainActor
    static func classify(_ request: Request) async throws -> Response {
        let data = try await GenerateClient.postJSON(path: "api/saves/classify", body: request)
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

extension SavedShelfEntry {
    var organizationItem: SavedOrganization.Item {
        .init(id: id, title: title.savesPrefix(utf16Limit: 200), summary: (previewSubtitle ?? "").savesPrefix(utf16Limit: 500))
    }
}

private extension String {
    func savesPrefix(utf16Limit: Int) -> String {
        var result = "", used = 0
        for character in self {
            let count = String(character).utf16.count
            guard used + count <= utf16Limit else { break }
            result.append(character)
            used += count
        }
        return result
    }
}
