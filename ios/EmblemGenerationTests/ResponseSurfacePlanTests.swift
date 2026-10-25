import Foundation
import Testing
@testable import EmblemCore

struct ResponseSurfacePlanTests {
    private static let butter = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Emblem/Fixtures/butter.json")

    private func blocks(adding extra: [String] = []) throws -> [Block] {
        var lines = try String(contentsOf: Self.butter, encoding: .utf8).split(separator: "\n").map(String.init)
        lines.insert(contentsOf: extra, at: 2)
        return try lines.map { try JSONDecoder().decode(Block.self, from: Data($0.utf8)) }
    }

    private func surfaces(_ plan: ResponseSurfacePlan) -> [ResponseSurface?] {
        plan.rows.filter { !$0.isFooter }.map(\.surface)
    }

    @Test func aResponseThatIsJustATableIsOneSurface() throws {
        let plan = ResponseSurfacePlan(blocks: try blocks())
        #expect(surfaces(plan) == [.canvas, .canvas, .canvas])
        let edges = plan.rows.filter(\.showsPaperEdge)
        #expect(edges.isEmpty)
    }

    @Test func aTableAfterOtherContentKeepsItsOwnBand() throws {
        let plan = ResponseSurfacePlan(blocks: try blocks(adding: [#"{"type":"quote","id":"q","text":"Worth the wait."}"#]))
        #expect(surfaces(plan) == [.paper, .paper, .canvas, .canvas])
        let edges = plan.rows.filter(\.showsPaperEdge)
        #expect(edges.count == 1)
    }
}
