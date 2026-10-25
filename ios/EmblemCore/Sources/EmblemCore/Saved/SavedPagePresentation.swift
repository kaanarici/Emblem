import Foundation

enum SavedCategory: String, CaseIterable, Sendable {
    case hotelsVacationRentals = "hotels-vacation-rentals"
    case flights, foodDrinks = "food-drinks", recipes, places, travel, books
    case filmsTV = "films-tv"
    case music, products, learning, work
    case healthFitness = "health-fitness"
    case general

    var title: String {
        switch self {
        case .hotelsVacationRentals: "Hotels & vacation rentals"
        case .flights: "Flights"
        case .foodDrinks: "Food & drinks"
        case .recipes: "Recipes"
        case .places: "Places"
        case .travel: "Travel"
        case .books: "Books"
        case .filmsTV: "Films & TV"
        case .music: "Music"
        case .products: "Products"
        case .learning: "Learning"
        case .work: "Work"
        case .healthFitness: "Health & fitness"
        case .general: "Saved pages"
        }
    }
}

public struct SavedPageArtwork: Codable, Hashable, Sendable {
    enum Ratio: String, Codable, Sendable {
        case landscape = "4:3", square = "1:1", portrait = "2:3"

        var aspect: ImageSpec.Aspect {
            switch self {
            case .landscape: .landscape
            case .square: .square
            case .portrait: .portrait
            }
        }
    }

    let ratio: Ratio
    let image: ImageSpec?
    static let unavailable = Self(ratio: .square)

    init(ratio: Ratio, image: ImageSpec? = nil) {
        self.ratio = ratio
        self.image = image.flatMap { candidate in
            let prefix = "emblem-step-image.v1."
            guard candidate.kind == .generated, candidate.query.utf16.count <= 4_096,
                  candidate.query.hasPrefix(prefix) else { return nil }
            let payload = candidate.query.dropFirst(prefix.count)
            guard !payload.isEmpty, payload.utf8.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0) ||
                    (48...57).contains($0) || $0 == 45 || $0 == 95
            }) else { return nil }
            return candidate.targeting(ratio.aspect)
        }
    }

    private enum CodingKeys: String, CodingKey { case ratio, image }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: ["ratio", "image"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ratio = try c.decode(Ratio.self, forKey: .ratio)
        let image: ImageSpec? = try? {
            let decoder = try c.superDecoder(forKey: .image)
            try rejectUnknownKeys(decoder, allowed: ["query", "kind", "aspect"])
            let candidate = try ImageSpec(from: decoder)
            guard candidate.aspect == ratio.aspect else { return nil as ImageSpec? }
            return candidate
        }()
        self.init(ratio: ratio, image: image)
    }
}

public struct SavedPagePresentation: Codable, Hashable, Sendable {
    struct CoverReference: Codable, Hashable, Sendable {
        let blockID: String
        let itemID: String?
        let index: Int?
        let aspect: ImageSpec.Aspect

        init(blockID: String, itemID: String? = nil, index: Int? = nil, aspect: ImageSpec.Aspect) throws {
            guard Self.validIdentifier(blockID, limit: 200),
                  itemID.map({ Self.validIdentifier($0, limit: 300) }) ?? true,
                  index.map({ (0...9_999).contains($0) }) ?? true,
                  itemID == nil || index == nil else { throw ValidationFailure.invalidMetadata }
            self.blockID = blockID
            self.itemID = itemID
            self.index = index
            self.aspect = aspect
        }

        private enum CodingKeys: String, CodingKey { case blockID, itemID, index, aspect }

        init(from decoder: Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: ["blockID", "itemID", "index", "aspect"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(blockID: c.decode(String.self, forKey: .blockID),
                          itemID: c.contains(.itemID) ? c.decode(String.self, forKey: .itemID) : nil,
                          index: c.contains(.index) ? c.decode(Int.self, forKey: .index) : nil,
                          aspect: c.decode(ImageSpec.Aspect.self, forKey: .aspect))
        }

        private static func validIdentifier(_ value: String, limit: Int) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                value.utf16.count <= limit && isSingleLine(value)
        }
    }

    let categoryKey: String
    let categoryTitle: String
    let previewSubtitle: String?
    let cover: CoverReference?

    init(categoryKey: String, categoryTitle: String, previewSubtitle: String? = nil,
         cover: CoverReference? = nil) throws {
        if let previewSubtitle, Self.displayText(previewSubtitle, limit: 120) == nil {
            throw ValidationFailure.invalidMetadata
        }
        guard categoryKey.range(of: #"\A[a-z0-9][a-z0-9._-]{0,63}\z"#, options: .regularExpression) != nil,
              let title = Self.displayText(categoryTitle, limit: 64) else {
            throw ValidationFailure.invalidMetadata
        }
        self.categoryKey = categoryKey
        self.categoryTitle = title
        self.previewSubtitle = previewSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cover = cover
    }

    private enum CodingKeys: String, CodingKey { case categoryKey, categoryTitle, previewSubtitle, cover }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: ["categoryKey", "categoryTitle", "previewSubtitle", "cover"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(categoryKey: c.decode(String.self, forKey: .categoryKey),
                      categoryTitle: c.decode(String.self, forKey: .categoryTitle),
                      previewSubtitle: c.contains(.previewSubtitle) ? c.decode(String.self, forKey: .previewSubtitle) : nil,
                      cover: c.contains(.cover) ? c.decode(CoverReference.self, forKey: .cover) : nil)
    }

    func validated(against blocks: [Block]) -> Self? {
        guard let cover else { return self }
        return SavedPageCover.resolve(cover, in: blocks) == nil ? nil : self
    }

    private static func displayText(_ value: String, limit: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return isSingleLine(value) && !trimmed.isEmpty && trimmed.utf16.count <= limit ? trimmed : nil
    }

    private enum ValidationFailure: Error { case invalidMetadata }
}

public struct SavedPageCover {
    let blockID: String
    let index: Int?
    public let image: ImageSpec?
    public let imageURL: String?
    public let aspect: ImageSpec.Aspect

    public var aspectRatio: Double {
        switch aspect {
        case .landscape: 4.0 / 3
        case .square: 1
        case .portrait: 2.0 / 3
        }
    }

    static func resolve(_ reference: SavedPagePresentation.CoverReference, in blocks: [Block]) -> Self? {
        let matches = blocks.filter { $0.id == reference.blockID }
        guard matches.count == 1, let block = matches.first else { return nil }
        let candidates = candidates(in: block)
        let candidate: Candidate?
        if let itemID = reference.itemID {
            let matches = candidates.filter { $0.itemID == itemID }
            candidate = matches.count == 1 ? matches.first : nil
        } else if let index = reference.index {
            candidate = candidates.first { $0.index == index }
        } else {
            candidate = candidates.count == 1 && candidates.first?.index == nil ? candidates.first : nil
        }
        return candidate?.cover(blockID: block.id, aspect: reference.aspect)
    }

    static func first(in blocks: [Block]) -> Self? {
        for block in blocks {
            for candidate in candidates(in: block) {
                if let cover = candidate.cover(blockID: block.id) { return cover }
            }
        }
        return nil
    }

    private struct Candidate {
        let index: Int?
        var itemID: String? = nil
        let image: ImageSpec?
        let imageURL: String?
        var aspect: ImageSpec.Aspect? = nil

        func cover(blockID: String, aspect override: ImageSpec.Aspect? = nil) -> SavedPageCover? {
            let spec = image.flatMap { $0.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            let url = imageURL.flatMap { value -> String? in
                guard value.utf16.count <= 8_192, let components = URLComponents(string: value),
                      ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                      let host = components.host, !host.isEmpty else { return nil }
                return value
            }
            guard spec != nil || url != nil else { return nil }
            return SavedPageCover(blockID: blockID, index: index, image: spec, imageURL: url,
                                  aspect: override ?? aspect ?? spec?.aspect ?? .square)
        }
    }

    private static func candidates(in block: Block) -> [Candidate] {
        switch block {
        case .hero(let hero):
            return [.init(index: nil, image: hero.image, imageURL: hero.imageURL,
                          aspect: hero.aspect == .wide ? .landscape : hero.aspect == .poster ? .portrait : .square)]
        case .cardCarousel(let carousel):
            return carousel.cards.enumerated().map {
                .init(index: $0.offset, itemID: $0.element.id, image: $0.element.image, imageURL: $0.element.imageURL)
            }
        case .photoGrid(let grid):
            return grid.images.enumerated().map { .init(index: $0.offset, image: $0.element, imageURL: nil) }
        case .stepCarousel(let carousel):
            return carousel.steps.enumerated().map { .init(index: $0.offset, image: $0.element.image, imageURL: $0.element.imageURL) }
        case .sideBySide(let comparison):
            return comparison.entities.enumerated().map {
                .init(index: $0.offset, itemID: $0.element.name, image: $0.element.image, imageURL: $0.element.imageURL)
            }
        case .oneAgainstMany(let comparison):
            return ([comparison.anchor] + comparison.challengers).enumerated().map {
                .init(index: $0.offset, itemID: $0.element.name, image: $0.element.image, imageURL: $0.element.imageURL)
            }
        case .spotList(let spots):
            return spots.spots.enumerated().map {
                .init(index: $0.offset, itemID: $0.element.name, image: $0.element.image, imageURL: $0.element.imageURL)
            }
        default: return []
        }
    }
}

public struct ResolvedSavedPagePresentation {
    let categoryKey: String
    let categoryTitle: String
    let previewSubtitle: String?
    public let cover: SavedPageCover?
}

extension PageMeta {
}

extension SavedPage.Snapshot {
    var displayTitle: String {
        let candidates = [meta?.title, selectedSourceCard?.title] + blocks.compactMap {
            if case .titleBlock(let block) = $0 { return block.title }
            return nil
        }.map(Optional.some) + [prompt]
        return candidates.compactMap { text -> String? in
            guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }.first ?? prompt
    }

    var presentation: ResolvedSavedPagePresentation {
        let retainedBlocks = blocks
        let proposed = meta?.savePresentation
        let metadata = proposed?.validated(against: retainedBlocks)
        let selected = selectedSourceCard
        let selectedCover = selected.flatMap {
            SavedPageCover.first(in: [.cardCarousel(CardCarousel(id: "saved-source-preview", cards: [$0]))])
        }
        let cover: SavedPageCover?
        if let meta, let artwork = meta.saveCover, artwork.image != nil || selectedCover == nil {
            cover = SavedPageCover(blockID: meta.id, index: nil, image: artwork.image,
                                   imageURL: nil, aspect: artwork.ratio.aspect)
        } else if let reference = proposed?.cover {
            cover = SavedPageCover.resolve(reference, in: retainedBlocks) ?? selectedCover
        } else {
            cover = SavedPageCover.first(in: retainedBlocks) ?? selectedCover
        }
        let category = selected?.saveCategory.flatMap(SavedCategory.init(rawValue:))
        let summary = selected?.caption ?? retainedBlocks.compactMap {
            if case .titleBlock(let block) = $0 { return block.summary }
            return nil
        }.first
        let preview = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ResolvedSavedPagePresentation(categoryKey: category?.rawValue ?? metadata?.categoryKey ?? "general",
                                             categoryTitle: category?.title ?? metadata?.categoryTitle ?? "Saved pages",
                                             previewSubtitle: metadata?.previewSubtitle ?? preview.flatMap { $0.isEmpty ? nil : String($0.prefix(120)) }, cover: cover)
    }
}

extension SavedPage {
    public var presentation: ResolvedSavedPagePresentation {
        let value = snapshot.presentation
        guard let categoryOverride else { return value }
        return ResolvedSavedPagePresentation(categoryKey: categoryOverride.categoryKey,
            categoryTitle: categoryOverride.categoryTitle, previewSubtitle: value.previewSubtitle, cover: value.cover)
    }
}

private func isSingleLine(_ value: String) -> Bool {
    !value.unicodeScalars.contains {
        [.control, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory)
    }
}

private struct SavedPresentationCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func rejectUnknownKeys(_ decoder: Decoder, allowed: Set<String>) throws {
    let container = try decoder.container(keyedBy: SavedPresentationCodingKey.self)
    guard container.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                debugDescription: "Unknown save presentation field"))
    }
}
