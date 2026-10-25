import Foundation

enum ObjectLibrary {
    private final class Match: NSObject {
        let resolution: Resolution

        init(_ resolution: Resolution) {
            self.resolution = resolution
        }
    }

    private struct Meta: Decodable {
        let items: [Item]
    }

    private struct Item: Decodable {
        let title: String
        let file_name: String
        let slug: String
        let tags: [String]
    }

    private struct Indexed {
        let fileName: String
        let slug: String
        let titleTokens: [String]
        let tagTokens: [String]
        let tagPhrases: Set<String>
    }

    private struct Catalog {
        let items: [Indexed]
        let bySlug: [String: Int]
        let byTitleToken: [String: [Int]]
        let byTagToken: [String: [Int]]
    }

    enum FallbackReason: String, Sendable {
        case emptyQuery
        case packUnavailable
        case noSemanticCandidate
        case lowConfidence
        case assetMissing
    }

    struct Resolution: Sendable {
        let url: URL?
        let fallbackReason: FallbackReason?
        let score: Int
    }

    private static let catalog: Catalog = {
        guard let url = Bundle.main.url(forResource: "ObjectMeta", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let meta = try? JSONDecoder().decode(Meta.self, from: data)
        else {
            return Catalog(
                items: [], bySlug: [:], byTitleToken: [:], byTagToken: [:])
        }
        let items = meta.items.map {
            Indexed(
                fileName: $0.file_name,
                slug: $0.slug,
                titleTokens: tokenize($0.title),
                tagTokens: $0.tags.flatMap(tokenize),
                tagPhrases: Set($0.tags.map {
                    tokenize($0).joined(separator: "-")
                }))
        }
        var bySlug = [String: Int](minimumCapacity: items.count)
        var byTitleToken: [String: [Int]] = [:]
        var byTagToken: [String: [Int]] = [:]
        for (index, item) in items.enumerated() {
            if bySlug[item.slug] == nil { bySlug[item.slug] = index }
            for token in Set(item.titleTokens) {
                byTitleToken[token, default: []].append(index)
            }
            for token in Set(item.tagTokens) {
                byTagToken[token, default: []].append(index)
            }
        }
        return Catalog(
            items: items,
            bySlug: bySlug,
            byTitleToken: byTitleToken,
            byTagToken: byTagToken)
    }()

    static func warm() {
        Task.detached(priority: .utility) { _ = catalog.items.isEmpty }
    }

    nonisolated(unsafe) private static let matches: NSCache<NSString, Match> = {
        let cache = NSCache<NSString, Match>()
        cache.countLimit = 500
        return cache
    }()

    private static let synonyms: [String: String] = [
        "tv": "television", "couch": "sofa", "settee": "sofa",
        "sneaker": "shoe", "trainer": "shoe", "automobile": "car",
        "aircraft": "airplane", "plane": "airplane", "smartphone": "phone",
        "iphone": "phone", "mobile": "phone", "laptop": "computer",
        "notebook": "computer", "timepiece": "clock", "wristwatch": "watch",
        "eyeglasses": "glasses", "spectacles": "glasses", "bicycle": "bike",
        "luggage": "suitcase", "baggage": "suitcase", "pot": "pan",
        "saucepan": "pan", "skillet": "pan", "mug": "cup",
        "aubergine": "eggplant", "courgette": "zucchini",
        "cilantro": "coriander", "rucksack": "backpack",
        "knapsack": "backpack", "pooch": "dog", "puppy": "dog",
        "kitten": "cat", "memo": "note", "cash": "money",
        "currency": "money", "lap": "swimming",
        "maki": "sushi", "nigiri": "sushi",
    ]

    private static let queryAliases: [String: String] = [
        "coffee beans": "coffee grains",
        "duffel bag": "kit bag",
        "duffle bag": "kit bag",
        "milk carton": "carton of milk",
        "presentation board": "whiteboard",
        "white ceramic plate": "plate",
    ]

    private static func stem(_ word: String) -> String {
        if word.count > 4, word.hasSuffix("ies") {
            return String(word.dropLast(3)) + "y"
        }
        if word.count > 4, word.hasSuffix("oes") {
            return String(word.dropLast(2))
        }
        if word.count > 4, word.hasSuffix("es"),
           ["sh", "ch", "x", "z", "s"].contains(where: { String(word.dropLast(2)).hasSuffix($0) }) {
            return String(word.dropLast(2))
        }
        if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") {
            return String(word.dropLast())
        }
        return word
    }

    private static func canonical(_ word: String) -> String {
        let stemmed = stem(word)
        return synonyms[stemmed] ?? synonyms[word] ?? stemmed
    }

    private static func tokenize(_ s: String) -> [String] {
        s.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map { canonical(String($0)) }
    }

    private static let queryNoise: Set<String> = [
        "3d", "icon", "image", "illustration", "render", "asset",
    ]

    private static let misdepictedSlugs: Set<String> = ["water"]

    private static let containerTokens: Set<String> = [
        "of", "with", "in", "on", "a", "an", "the",
        "cup", "glass", "mug", "bowl", "plate", "jar", "bottle", "carton",
        "can", "tin", "pot", "pan", "tray", "sack", "bag", "spoon", "scoop",
        "slice", "piece", "stack", "pile", "bunch", "clove", "stick",
        "sprig", "wedge", "cube", "drop", "bar", "loaf", "set", "pair",
    ]

    private static let modifierTokens: Set<String> = [
        "cold", "hot", "warm", "frozen", "fresh", "dried", "dry", "chopped",
        "sliced", "diced", "grated", "melted", "softened", "unsalted",
        "salted", "raw", "cooked", "ground", "whole", "ripe", "large",
        "small", "medium", "big", "little", "new", "old", "quick", "easy",
        "simple", "perfect", "best", "extra", "light", "dark", "sweet",
        "instant", "baby", "mini", "wild", "organic", "smoked", "toasted",
        "crispy", "creamy", "spicy",
    ]

    static func imageURL(for query: String) -> URL? {
        resolution(for: query).url
    }

    static func imageURL(slug: String) -> URL? {
        Bundle.main.url(forResource: slug, withExtension: "png", subdirectory: "ObjectImages")
    }

    static func resolution(for query: String) -> Resolution {
        let normalized = query
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .lowercased()
        let aliased = queryAliases[normalized] ?? normalized
        var queryTokens = tokenize(aliased).reduce(into: [String]()) { tokens, token in
            if !queryNoise.contains(token), !tokens.contains(token) { tokens.append(token) }
        }
        while let marker = queryTokens.firstIndex(where: { $0 == "free" || $0 == "less" }) {
            queryTokens.removeSubrange(max(0, marker - 1)...marker)
        }
        guard !queryTokens.isEmpty else {
            return Resolution(url: nil, fallbackReason: .emptyQuery, score: 0)
        }
        guard !catalog.items.isEmpty else {
            return Resolution(url: nil, fallbackReason: .packUnavailable, score: 0)
        }
        let cacheKey = queryTokens.joined(separator: "-") as NSString
        if let cached = matches.object(forKey: cacheKey) {
            return cached.resolution
        }

        let querySet = Set(queryTokens)
        let joined = queryTokens.joined(separator: "-")
        let head = queryTokens[queryTokens.count - 1]

        var candidates = Set<Int>()
        if let slugHit = catalog.bySlug[joined] { candidates.insert(slugHit) }
        for token in queryTokens {
            if let postings = catalog.byTitleToken[token] {
                candidates.formUnion(postings)
            }
            if let postings = catalog.byTagToken[token] {
                candidates.formUnion(postings)
            }
        }

        let semanticQuery = queryTokens.filter { !Self.modifierTokens.contains($0) }
        let requiredTokens = semanticQuery.isEmpty ? queryTokens : semanticQuery

        var best: (item: Indexed, score: Int)?
        for index in candidates.sorted() {
            let item = catalog.items[index]
            guard !Self.misdepictedSlugs.contains(item.slug) else { continue }
            let title = item.titleTokens
            let titleSet = Set(title)
            let tagSet = Set(item.tagTokens)
            guard requiredTokens.allSatisfy({ titleSet.contains($0) || tagSet.contains($0) })
            else { continue }

            let matched = title.filter { querySet.contains($0) }.count
            let unmatchedItem = title.count - matched
            let unmatchedQuery = queryTokens.count
                - queryTokens.filter { title.contains($0) }.count
            let tagMatched = item.tagTokens.filter { querySet.contains($0) }.count

            guard item.slug == joined || matched > 0 else { continue }

            var score: Int
            if item.slug == joined {
                score = 100
            } else if matched == title.count, unmatchedQuery == 0 {
                score = 95
            } else {
                let extras = title.filter { !querySet.contains($0) }
                guard extras.allSatisfy({
                    Self.containerTokens.contains($0) || Self.modifierTokens.contains($0)
                }) else { continue }
                score = 60 + 8 * matched
                    + (title.contains(head) ? 8 : 0)
                    - 5 * unmatchedItem
                    - 2 * unmatchedQuery
            }
            score += 3 * min(tagMatched, 2)

            if score > (best?.score ?? 0) { best = (item, score) }
        }

        guard let best else {
            let result = Resolution(
                url: nil, fallbackReason: .noSemanticCandidate, score: 0)
            matches.setObject(Match(result), forKey: cacheKey)
            return result
        }
        guard best.score >= 28 else {
            let result = Resolution(
                url: nil, fallbackReason: .lowConfidence, score: best.score)
            matches.setObject(Match(result), forKey: cacheKey)
            return result
        }

        let name = (best.item.fileName as NSString).deletingPathExtension
        let resolved = Bundle.main.url(
            forResource: name, withExtension: "png", subdirectory: "ObjectImages")
        if let resolved {
            let result = Resolution(url: resolved, fallbackReason: nil, score: best.score)
            matches.setObject(Match(result), forKey: cacheKey)
            return result
        } else {
            let result = Resolution(
                url: nil, fallbackReason: .assetMissing, score: best.score)
            matches.setObject(Match(result), forKey: cacheKey)
            return result
        }
    }
}
