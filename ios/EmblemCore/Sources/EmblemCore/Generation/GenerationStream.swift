import Foundation
import os

public struct SourceActivity: Codable, Identifiable, Hashable {
    var type: String
    public var id: String
    public var source: String
    var category: String
    public var title: String
    public var status: String
    public var message: String
}

public struct CitationSource: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var url: String
    public var domain: String
    public var favicon: String?
    public var publishedAt: String?
    public var snippet: String?
}

public struct GenerationStream {
    public enum Event {
        case accepted
        case status(String)
        case pageSnapshot(revision: Int, blocks: [Block])
        case pagePreview(revision: Int, attempt: Int, blocks: [Block], draft: String?? = .none)
        case clearPagePreview
        case finished(
            persisted: Bool?,
            activities: [SourceActivity],
            sources: [CitationSource])
        case failed(GenerationFailure)
    }

    private enum Line: Decodable {
        case status(String), activity(SourceActivity), sources([CitationSource])
        case failure(GenerationFailure), metric(Metric), inference
        case snapshot(id: String, revision: Int, blocks: [Block])
        case preview(id: String, revision: Int, attempt: Int, blocks: [Block], draft: String??)
        case terminal(status: String, count: Int, revision: Int?, persisted: Bool?)

        private enum Key: String, CodingKey {
            case type, text, items, code, message, retryable, id, revision, attempt, blocks, status, blockCount, persisted, draft
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            switch try c.decode(String.self, forKey: .type) {
            case "status": self = .status(try c.decode(String.self, forKey: .text))
            case "activity": self = .activity(try SourceActivity(from: decoder))
            case "sources": self = .sources(try c.decode([CitationSource].self, forKey: .items))
            case "error": self = .failure(GenerationFailure(
                code: try c.decode(String.self, forKey: .code),
                message: try c.decode(String.self, forKey: .message),
                retryable: try c.decode(Bool.self, forKey: .retryable)))
            case "metric": self = (try? Metric(from: decoder)).map(Self.metric) ?? .inference
            case "inference": self = .inference
            case "pagePreview": self = .preview(
                id: try c.decode(String.self, forKey: .id),
                revision: try c.decode(Int.self, forKey: .revision),
                attempt: try c.decode(Int.self, forKey: .attempt),
                blocks: try c.decode([Block].self, forKey: .blocks),
                draft: c.contains(.draft) ? .some(try c.decodeIfPresent(String.self, forKey: .draft)) : .none)
            case "pageSnapshot": self = .snapshot(
                id: try c.decode(String.self, forKey: .id),
                revision: try c.decode(Int.self, forKey: .revision),
                blocks: try c.decode([Block].self, forKey: .blocks))
            case "terminal": self = .terminal(
                status: try c.decode(String.self, forKey: .status),
                count: try c.decode(Int.self, forKey: .blockCount),
                revision: try c.decodeIfPresent(Int.self, forKey: .revision),
                persisted: try c.decodeIfPresent(Bool.self, forKey: .persisted))
            default: throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "Unsupported stream event")
            }
        }
    }

    private struct Metric: Decodable {
        struct Percentiles: Decodable { let p50: Double; let p90: Double; let p95: Double }
        let route: String
        let stages: [String: Double]
        let percentiles: [String: Percentiles]
        let sampleSize: Int
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "emblem", category: "generation-performance")
    private let decoder = JSONDecoder()
    private var snapshot: (revision: Int, count: Int)?
    private var previewRevision = 0
    private var previewAttempt = 0
    private var failure: GenerationFailure?
    private var activities: [SourceActivity] = []
    private var sources: [CitationSource] = []
    private(set) var isTerminal = false

    mutating func consume(_ data: Data) -> Event? {
        guard !isTerminal else { return nil }
        guard let line = try? decoder.decode(Line.self, from: data) else {
            return finish(.failed(Self.invalidResponse))
        }
        switch line {
        case .status(let text): return .status(text)
        case .activity(let activity): Self.upsert(activity, in: &activities)
        case .sources(let items):
            for source in items { Self.upsert(source, in: &sources) }
        case .failure(let error):
            failure = error
            return .clearPagePreview
        case .metric(let metric):
            let total = metric.stages["total"] ?? 0
            let aggregate = metric.percentiles["total"]
            Self.logger.info(
                "generation server route=\(metric.route, privacy: .public) total_ms=\(total, format: .fixed(precision: 1)) p50_ms=\(aggregate?.p50 ?? 0, format: .fixed(precision: 1)) p90_ms=\(aggregate?.p90 ?? 0, format: .fixed(precision: 1)) p95_ms=\(aggregate?.p95 ?? 0, format: .fixed(precision: 1)) n=\(metric.sampleSize)")
        case .inference: break
        case .preview(let id, let revision, let attempt, let blocks, let draft):
            guard id == "page-preview", revision > previewRevision,
                  revision <= 9_007_199_254_740_991,
                  attempt >= max(1, previewAttempt), attempt <= 9_007_199_254_740_991,
                  !blocks.contains(where: { if case .unknown = $0 { true } else { false } }) else {
                return finish(.failed(Self.invalidResponse))
            }
            previewRevision = revision
            previewAttempt = attempt
            guard failure == nil else { return .clearPagePreview }
            return .pagePreview(revision: revision, attempt: attempt, blocks: blocks, draft: draft)
        case .snapshot(let id, let revision, let blocks):
            guard id == "page-snapshot", revision > 0 else { return finish(.failed(Self.invalidResponse)) }
            if let previous = snapshot, revision <= previous.revision { return finish(.failed(Self.invalidResponse)) }
            snapshot = (revision, blocks.count)
            return .pageSnapshot(revision: revision, blocks: blocks)
        case .terminal(let status, let terminalCount, let terminalRevision, let persisted):
            guard status == "completed" else {
                return finish(.failed(failure ?? GenerationFailure(
                    code: status == "cancelled" ? "cancelled" : "generation_failed",
                    message: "The page didn't finish generating.",
                    retryable: status != "cancelled")))
            }
            guard let snapshot else { return finish(.failed(failure ?? Self.invalidResponse)) }
            guard terminalRevision == snapshot.revision else { return finish(.failed(Self.invalidResponse)) }
            guard failure == nil, terminalCount == snapshot.count else {
                return finish(.failed(failure ?? Self.invalidResponse))
            }
            return finish(.finished(persisted: persisted, activities: activities, sources: sources))
        }
        return nil
    }

    mutating func endOfStream() -> Event {
        finish(.failed(failure ?? GenerationFailure(
            code: "stream_cutoff",
            message: "The connection ended before the page finished.",
            retryable: true)))
    }

    private mutating func finish(_ event: Event) -> Event {
        isTerminal = true
        return event
    }

    private static let invalidResponse = GenerationFailure(
        code: "invalid_stream", message: "The server sent an invalid response.", retryable: true)

    private static func upsert<Item: Identifiable>(_ item: Item, in items: inout [Item]) {
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
        else { items.append(item) }
    }
}
