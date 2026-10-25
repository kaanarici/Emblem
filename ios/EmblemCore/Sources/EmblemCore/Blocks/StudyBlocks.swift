import Foundation

public struct Quiz: Codable, Hashable {
    public struct Question: Codable, Hashable {
        public var question: String
        public var options: [String]
        public var correctIndex: Int
        public var why: String?
    }
    public var id: String
    public var title: String?
    public var questions: [Question]
}

public struct Flashcards: Codable, Hashable {
    public struct Card: Codable, Hashable {
        public var front: String
        public var back: String
    }
    public var id: String
    public var title: String?
    public var cards: [Card]
}

public struct ChartBlock: Codable, Hashable {
    public enum Kind: String, Codable { case bar, line, pie, area }
    public struct Point: Codable, Hashable {
        public var label: String
        public var value: Double
    }
    public struct Series: Codable, Hashable {
        public var name: String?
        public var points: [Point]
    }
    public var id: String
    public var kind: Kind
    public var title: String?
    public var unit: String?
    public var colors: [String]?
    public var series: [Series]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = Kind(rawValue: (try? c.decode(String.self, forKey: .kind)) ?? "") ?? .bar
        title = try? c.decode(String.self, forKey: .title)
        unit = try? c.decode(String.self, forKey: .unit)
        colors = try? c.decode([String].self, forKey: .colors)
        series = (try? c.decode([Series].self, forKey: .series)) ?? []
    }
}

public struct DiagramBlock: Codable, Hashable {
    public struct Node: Codable, Hashable {
        public var id: String
        public var label: String
        public var icon: Icon?
    }
    public struct Edge: Codable, Hashable {
        public var from: String
        public var to: String
        public var label: String?
    }
    public var id: String
    public var title: String?
    public var nodes: [Node]
    public var edges: [Edge]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try? c.decode(String.self, forKey: .title)
        nodes = try c.decode([Node].self, forKey: .nodes)
        edges = (try? c.decode([Edge].self, forKey: .edges)) ?? []
    }
}

public struct WhatIfBlock: Codable, Hashable {
    public struct Variable: Codable, Hashable {
        public var name: String
        public var label: String
        public var min: Double
        public var max: Double
        public var defaultValue: Double
        public var step: Double?
        public var unit: String?

        public enum CodingKeys: String, CodingKey {
            case name, label, min, max, step, unit
            case defaultValue = "default"
        }
    }
    public struct Output: Codable, Hashable {
        public var label: String
        public var expression: String
        public var unit: String?
    }
    public var id: String
    public var title: String?
    public var variables: [Variable]
    public var outputs: [Output]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try? c.decode(String.self, forKey: .title)
        variables = try c.decode([Variable].self, forKey: .variables)
        outputs = try c.decode([Output].self, forKey: .outputs)
    }
}

public struct RunStamp: Codable, Hashable {
    public var id: String
    public var iso: String
}
