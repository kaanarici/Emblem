import XCTest
@testable import Emblem
@testable import EmblemCore

final class DiagramLayoutTests: XCTestCase {
    private static func diagram(_ nodes: [(String, String)], _ edges: [(String, String, String?)]) throws -> DiagramBlock {
        let nodeJSON = nodes.map { #"{"id":"\#($0.0)","label":"\#($0.1)","icon":{"emoji":"🔹"}}"# }
        let edgeJSON = edges.map { from, to, label in
            #"{"from":"\#(from)","to":"\#(to)"\#(label.map { #","label":"\#($0)""# } ?? "")}"#
        }
        let json = #"{"id":"d","nodes":[\#(nodeJSON.joined(separator: ","))],"edges":[\#(edgeJSON.joined(separator: ","))]}"#
        return try JSONDecoder().decode(DiagramBlock.self, from: Data(json.utf8))
    }

    private static let shown: [String: ([(String, String)], [(String, String, String?)])] = [
        "economy": (
            [("cb", "Central Bank"), ("out", "Total Output"), ("lab", "Labor Market"), ("price", "Price Level")],
            [("cb", "out", "stimulates growth"), ("cb", "lab", "controls rates"), ("out", "lab", "creates jobs"),
             ("lab", "price", "drives spending"), ("out", "price", "raises prices")]),
        "chain": (
            [("a", "Seed"), ("b", "Sprout"), ("c", "Plant"), ("d", "Fruit")],
            [("a", "b", "germinates"), ("b", "c", "grows leaves"), ("c", "d", "flowers")]),
        "fan-out": (
            [("sun", "Sunlight"), ("a", "Plants"), ("b", "Solar Panels"), ("c", "Weather")],
            [("sun", "a", "feeds"), ("sun", "b", "powers"), ("sun", "c", "drives")]),
        "fan-in": (
            [("a", "Sleep"), ("b", "Diet"), ("c", "Exercise"), ("h", "Health")],
            [("a", "h", "restores"), ("b", "h", "fuels"), ("c", "h", "strengthens")]),
        "cycle": (
            [("a", "Evaporation"), ("b", "Condensation"), ("c", "Precipitation")],
            [("a", "b", "cools"), ("b", "c", "falls"), ("c", "a", "collects")]),
        "mixed": (
            [("idea", "Idea"), ("product", "Product"), ("users", "Users"), ("feedback", "Feedback"),
             ("revenue", "Revenue"), ("team", "Team")],
            [("idea", "product", "shapes"), ("product", "users", "attracts"), ("users", "revenue", "pay"),
             ("users", "feedback", "share"), ("feedback", "product", "improves"), ("revenue", "team", "funds"),
             ("team", "product", "ships")]),
    ]

    private static let stress: [String: ([(String, String)], [(String, String, String?)])] = [
        "isolated": ((1...8).map { ("n\($0)", "Concept \($0)") }, []),
        "dense": (
            (1...8).map { ("n\($0)", ["Supply Chain Pressure", "Wages", "Consumer Demand", "Interest Rates",
                                      "Exchange Rate", "Housing", "Exports", "Inflation Expectations"][$0 - 1]) },
            [("n1", "n3", "raises costs significantly"), ("n2", "n3", "boosts"), ("n4", "n3", "cools"),
             ("n4", "n6", "slows"), ("n5", "n7", "helps"), ("n3", "n8", "lifts"), ("n6", "n8", "feeds"),
             ("n7", "n1", "strains"), ("n8", "n2", "pushes up"), ("n1", "n8", "adds to"), ("n4", "n5", "moves")]),
        "two-way": (
            [("a", "Buyers"), ("b", "Sellers")],
            [("a", "b", "pay"), ("b", "a", "deliver"), ("a", "b", "rate")]),
    ]

    func testShownDiagramsKeepEveryLabelOnItsArrow() throws {
        for (name, graph) in Self.shown {
            for width in [300.0, 310, 350] {
                let block = try Self.diagram(graph.0, graph.1)
                let layout = try XCTUnwrap(DiagramLayout(block: block, width: width), name)
                assertGuarantees(layout, block: block, name: "\(name) at \(width)")
                XCTAssertEqual(layout.legend, [], "\(name) at \(width)")
                XCTAssertEqual(layout.labels.count, graph.1.count, "\(name) at \(width)")
            }
        }
    }

    func testCrowdedDiagramsStillNeverOverlap() throws {
        for (name, graph) in Self.stress.merging(Self.shown, uniquingKeysWith: { a, _ in a }) {
            for width in [283.0, 310] {
                let block = try Self.diagram(graph.0, graph.1)
                let layout = try XCTUnwrap(DiagramLayout(block: block, width: width), name)
                assertGuarantees(layout, block: block, name: "\(name) at \(width)")
            }
        }
    }

    private func assertGuarantees(_ layout: DiagramLayout, block: DiagramBlock, name: String) {
        let bounds = CGRect(origin: .zero, size: layout.size)
        let nodes = layout.placed.map(\.frame)
        XCTAssertEqual(nodes.count, block.nodes.count, name)
        for (i, node) in nodes.enumerated() {
            XCTAssertTrue(bounds.contains(node), "\(name): node outside the card")
            for other in nodes[(i + 1)...] { XCTAssertFalse(node.intersects(other), "\(name): nodes overlap") }
        }
        for placed in layout.placed {
            let room = DiagramLayout.textRoom(placed.frame.width, icon: placed.showsIcon)
            XCTAssertNotNil(DiagramLayout.measure(placed.node.label, size: placed.fontSize, maxWidth: room),
                            "\(name): \(placed.node.label) is cut")
        }
        let segments = layout.routes.map { route in
            zip(route.points, route.points.dropFirst()).map { a, b in
                XCTAssertTrue(a.x == b.x || a.y == b.y, "\(name): diagonal segment")
                return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                    .insetBy(dx: -0.5, dy: -0.5)
            }
        }
        for (route, list) in zip(layout.routes, segments) {
            XCTAssertTrue(list.allSatisfy(bounds.insetBy(dx: -1, dy: -1).contains), "\(name): edge leaves the card")
            for node in nodes {
                XCTAssertFalse(list.contains { $0.intersects(node.insetBy(dx: 1, dy: 1)) }, "\(name): edge crosses a node")
            }
            let before = route.points[route.points.count - 2]
            let tip = route.points[route.points.count - 1]
            XCTAssertGreaterThanOrEqual(hypot(tip.x - before.x, tip.y - before.y), DiagramLayout.arrowLength + 3,
                                        "\(name): arrow longer than its line")
        }
        for (i, label) in layout.labels.enumerated() {
            XCTAssertTrue(bounds.contains(label.frame), "\(name): \(label.text) outside the card")
            XCTAssertFalse(nodes.contains { $0.intersects(label.frame) }, "\(name): \(label.text) covers a node")
            for other in layout.labels[(i + 1)...] {
                XCTAssertFalse(label.frame.intersects(other.frame), "\(name): \(label.text) overlaps \(other.text)")
            }
            for (route, list) in zip(layout.routes, segments) where route.edge != label.id {
                XCTAssertFalse(list.contains { $0.intersects(label.frame) }, "\(name): \(label.text) covers another arrow")
            }
            let room = label.frame.width - DiagramLayout.labelPadding.width * 2
            XCTAssertNotNil(DiagramLayout.measure(label.text, size: label.fontSize, maxWidth: room), "\(name): \(label.text) is cut")
        }
        let labeled = Set(block.edges.compactMap(\.label))
        let shown = Set(layout.labels.map(\.text))
        for text in labeled where !shown.contains(where: { $0.contains(text) }) {
            XCTAssertTrue(layout.legend.contains { $0.contains(text) }, "\(name): \(text) disappeared")
        }
    }
}
