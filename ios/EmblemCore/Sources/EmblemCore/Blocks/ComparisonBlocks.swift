import Foundation

public struct ComparisonTable: Codable, Hashable {
    public enum Verdict: String, Codable { case good, bad }
    public enum ColumnAlignment: String, Codable { case left, center, right }

    public struct Cell: Codable, Hashable {
        public var value: String
        public var verdict: Verdict?
        public var note: String?

        public var chipLabel: String? {
            guard let note = note?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !note.isEmpty,
                  note.caseInsensitiveCompare(
                    value.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame
            else { return nil }
            return note
        }

        public init(value: String, verdict: Verdict? = nil, note: String? = nil) {
            self.value = value
            self.verdict = verdict
            self.note = note
        }

        public init(from decoder: Decoder) throws {
            if let plain = try? decoder.singleValueContainer().decode(String.self) {
                self.init(value: plain)
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                value: try c.decode(String.self, forKey: .value),
                verdict: Verdict(rawValue: (try? c.decode(String.self, forKey: .verdict)) ?? ""),
                note: try? c.decode(String.self, forKey: .note))
        }
    }

    public struct Row: Codable, Hashable {
        public var label: String
        public var subtitle: String? = nil
        public var icon: Icon? = nil
        public var values: [Cell]

        private var rankMatch: Regex<(Substring, Substring)>.Match? {
            label.prefixMatch(of: /(\d{1,2})(?:\.\s*|\s{2,})(?=\S)/)
        }

        public var rank: String? { rankMatch.map { String($0.1) } }
        public var title: String { rankMatch.map { String(label[$0.range.upperBound...]) } ?? label }
    }
    public var id: String
    public var rowHeader: String?
    public var columns: [String]
    public var columnAlignments: [ColumnAlignment]? = nil
    public var rows: [Row]
}

public enum CompareVerdict: String, Codable, Hashable {
    case good, bad

    public init?(rawValue: String) {
        switch rawValue {
        case "good": self = .good
        case "bad": self = .bad
        default: return nil
        }
    }
}

public struct CompareCell: Codable, Hashable {
    public var text: String
    public var verdict: CompareVerdict?
    public var note: String?

    public var chipLabel: String? {
        guard let note = note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty,
              note.caseInsensitiveCompare(
                text.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame
        else { return nil }
        return note
    }

    public init(text: String, verdict: CompareVerdict? = nil, note: String? = nil) {
        self.text = text
        self.verdict = verdict
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        if let plain = try? decoder.singleValueContainer().decode(String.self) {
            self.init(text: plain)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            text: try c.decode(String.self, forKey: .text),
            verdict: CompareVerdict(rawValue: (try? c.decode(String.self, forKey: .verdict)) ?? ""),
            note: try? c.decode(String.self, forKey: .note))
    }
}

public struct CompareEntity: Codable, Hashable {
    public var name: String
    public var price: String?
    public var image: ImageSpec?
    public var imageURL: String?
    public var icon: Icon?

    public var photographicArtwork: ImageSpec? {
        if let image, image.kind == .photo || image.kind == .poster || image.kind == .still {
            return image.targeting(.landscape)
        }
        guard imageURL == nil || image != nil else { return nil }
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? nil : ImageSpec(query: query, kind: .photo, aspect: .landscape)
    }

    public var photographicArtworkURL: String? {
        guard let image else { return imageURL }
        return image.kind == .photo || image.kind == .poster || image.kind == .still ? imageURL : nil
    }

    public init(name: String, price: String? = nil, image: ImageSpec? = nil, imageURL: String? = nil, icon: Icon? = nil) {
        self.name = name
        self.price = price
        self.image = image
        self.imageURL = imageURL
        self.icon = icon
    }
}

public struct CompareSection: Codable, Hashable {
    public struct Row: Codable, Hashable {
        public var label: String?
        public var values: [CompareCell]
    }
    public var title: String
    public var icon: Icon?
    public var rows: [Row]
}

public struct SideBySide: Codable, Hashable {
    public struct Row: Codable, Hashable {
        public var label: String
        public var values: [CompareCell]
    }
    public var id: String
    public var sectionTitle: String?
    public var sectionIcon: Icon?
    public var entities: [CompareEntity]
    public var rows: [Row]
    public var sections: [CompareSection]? = nil

    public var comparisonSections: [CompareSection] {
        if let sections, !sections.isEmpty { return sections }
        return [CompareSection(title: sectionTitle ?? "", icon: sectionIcon,
                               rows: rows.map { .init(label: $0.label, values: $0.values) })]
    }

    public init(id: String, sectionTitle: String?, sectionIcon: Icon?, entities: [CompareEntity],
         rows: [Row] = [], sections: [CompareSection]? = nil) {
        self.id = id
        self.sectionTitle = sectionTitle
        self.sectionIcon = sectionIcon
        self.entities = entities
        self.rows = rows
        self.sections = sections
    }

    private enum CodingKeys: String, CodingKey {
        case id, sectionTitle, sectionIcon, entities, rows, sections
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  sectionTitle: try c.decodeIfPresent(String.self, forKey: .sectionTitle),
                  sectionIcon: try c.decodeIfPresent(Icon.self, forKey: .sectionIcon),
                  entities: try c.decode([CompareEntity].self, forKey: .entities),
                  rows: try c.decodeIfPresent([Row].self, forKey: .rows) ?? [],
                  sections: try c.decodeIfPresent([CompareSection].self, forKey: .sections))
    }
}

public struct OneAgainstMany: Codable, Hashable {
    public struct Contender: Codable, Hashable {
        public var name: String
        public var price: String?
        public var image: ImageSpec?
        public var imageURL: String?
        public var icon: Icon?
        public var values: [CompareCell]

        public init(name: String, price: String? = nil, image: ImageSpec? = nil,
             imageURL: String? = nil, icon: Icon? = nil, values: [CompareCell] = []) {
            self.name = name
            self.price = price
            self.image = image
            self.imageURL = imageURL
            self.icon = icon
            self.values = values
        }

        private enum CodingKeys: String, CodingKey {
            case name, price, image, imageURL, icon, values
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(name: try c.decode(String.self, forKey: .name),
                      price: try c.decodeIfPresent(String.self, forKey: .price),
                      image: try c.decodeIfPresent(ImageSpec.self, forKey: .image),
                      imageURL: try c.decodeIfPresent(String.self, forKey: .imageURL),
                      icon: try c.decodeIfPresent(Icon.self, forKey: .icon),
                      values: try c.decodeIfPresent([CompareCell].self, forKey: .values) ?? [])
        }
    }
    public var id: String
    public var sectionTitle: String?
    public var sectionIcon: Icon?
    public var anchor: Contender
    public var rowLabels: [String]
    public var challengers: [Contender]
    public var sections: [CompareSection]? = nil

    public var comparisonSections: [CompareSection] {
        if let sections, !sections.isEmpty { return sections }
        let columns = [anchor] + challengers
        let rows = rowLabels.enumerated().map { index, label in
            CompareSection.Row(label: label, values: columns.map {
                $0.values.indices.contains(index) ? $0.values[index] : CompareCell(text: "–")
            })
        }
        return [CompareSection(title: sectionTitle ?? "", icon: sectionIcon, rows: rows)]
    }

    public init(id: String, sectionTitle: String?, sectionIcon: Icon?, anchor: Contender,
         rowLabels: [String] = [], challengers: [Contender], sections: [CompareSection]? = nil) {
        self.id = id
        self.sectionTitle = sectionTitle
        self.sectionIcon = sectionIcon
        self.anchor = anchor
        self.rowLabels = rowLabels
        self.challengers = challengers
        self.sections = sections
    }

    private enum CodingKeys: String, CodingKey {
        case id, sectionTitle, sectionIcon, anchor, rowLabels, challengers, sections
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  sectionTitle: try c.decodeIfPresent(String.self, forKey: .sectionTitle),
                  sectionIcon: try c.decodeIfPresent(Icon.self, forKey: .sectionIcon),
                  anchor: try c.decode(Contender.self, forKey: .anchor),
                  rowLabels: try c.decodeIfPresent([String].self, forKey: .rowLabels) ?? [],
                  challengers: try c.decode([Contender].self, forKey: .challengers),
                  sections: try c.decodeIfPresent([CompareSection].self, forKey: .sections))
    }
}

public struct ReviewSummary: Codable, Hashable {
    public struct Source: Codable, Hashable {
        public var icon: Icon?
        public var score: String
        public var source: String
    }
    public struct Theme: Codable, Hashable {
        public var icon: Icon?
        public var title: String
        public var summary: String
        public var quote: String?
        public var attribution: String?
    }
    public var id: String
    public var intro: String?
    public var sources: [Source]?
    public var themes: [Theme]
}
