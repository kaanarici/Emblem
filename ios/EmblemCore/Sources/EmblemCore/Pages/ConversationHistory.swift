import Foundation
import Observation
import CryptoKit

public struct ConversationSummary: Decodable, Identifiable, Sendable {
    public let key: String
    public var title: String
    public let updatedAt: Double
    public var archived: Bool
    public var pinnedAt: Double?
    let image: ImageSpec?
    let imageURL: String?
    public let preview: String?
    let saveCover: SavedPageArtwork?

    init(key: String, title: String, updatedAt: Double, archived: Bool, pinnedAt: Double? = nil,
         image: ImageSpec? = nil, imageURL: String? = nil, preview: String? = nil,
         saveCover: SavedPageArtwork? = nil) {
        self.key = key
        self.title = title
        self.updatedAt = updatedAt
        self.archived = archived
        self.pinnedAt = pinnedAt
        self.image = image
        self.imageURL = imageURL
        self.preview = preview
        self.saveCover = saveCover
    }

    private enum CodingKeys: String, CodingKey {
        case key, title, updatedAt, archived, pinnedAt, image, imageURL, preview, saveCover
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(key: try c.decode(String.self, forKey: .key),
                  title: try c.decode(String.self, forKey: .title),
                  updatedAt: try c.decode(Double.self, forKey: .updatedAt),
                  archived: try c.decode(Bool.self, forKey: .archived),
                  pinnedAt: try c.decodeIfPresent(Double.self, forKey: .pinnedAt),
                  image: try c.decodeIfPresent(ImageSpec.self, forKey: .image),
                  imageURL: try c.decodeIfPresent(String.self, forKey: .imageURL),
                  preview: try c.decodeIfPresent(String.self, forKey: .preview),
                  saveCover: c.contains(.saveCover)
                    ? (try? c.decode(SavedPageArtwork.self, forKey: .saveCover)) ?? .unavailable : nil)
    }

    public var id: String { key }
    public var date: Date { Date(timeIntervalSince1970: updatedAt / 1000) }
    public var isPinned: Bool { pinnedAt != nil }

    public var artwork: SavedPageCover? {
        if let saveCover {
            return SavedPageCover(blockID: key, index: nil, image: saveCover.image,
                                  imageURL: nil, aspect: saveCover.ratio.aspect)
        }
        guard let image, [.poster, .still, .photo].contains(image.kind) else { return nil }
        return SavedPageCover(blockID: key, index: nil, image: image, imageURL: imageURL, aspect: .landscape)
    }

    public var legacyArtworkURL: String? {
        saveCover == nil && image == nil ? imageURL : nil
    }
}

public struct ConversationPage: Decodable, Sendable {
    public var pinned: [ConversationSummary]
    public var conversations: [ConversationSummary]
    public var nextCursor: String?

    public init(pinned: [ConversationSummary] = [], conversations: [ConversationSummary] = [], nextCursor: String? = nil) {
        self.pinned = pinned
        self.conversations = conversations
        self.nextCursor = nextCursor
    }

    @MainActor
    static func fetch(_ scope: ConversationHistory.Scope, cursor: String?) async throws -> ConversationPage {
        let query = [
            scope == .archived ? URLQueryItem(name: "archived", value: "true") : nil,
            cursor.map { URLQueryItem(name: "cursor", value: $0) },
        ].compactMap(\.self)
        let data = try await GenerateClient.fetchJSON(path: "api/conversations", query: query)
        return try JSONDecoder().decode(ConversationPage.self, from: data)
    }
}

@Observable @MainActor
public final class ConversationHistory {
    public enum LoadState: Equatable { case idle, loading, loaded, failed }
    public enum Scope: Sendable { case active, archived }
    public enum Change: Equatable, Sendable { case pin(Bool), rename(String), archive(Bool), delete }
    public enum SaveResult: Sendable { case saved, failed, superseded }

    public struct Edit: Sendable {
        fileprivate let id: UUID
        public let key: String
        fileprivate let field: Field
        fileprivate let epoch: UUID
    }

    fileprivate enum Field: Sendable { case pinned, title, archived, deleted }

    public struct Request: Encodable, Equatable, Sendable {
        public let action: String
        public var conversationKey: String?
        public var conversationKeys: [String]?
        public var title: String?
    }

    private struct PendingEdit {
        let id: UUID
        let change: Change
        let pinnedAt: Double?
        var savedAfter: Int?
    }

    private struct Copy {
        let summary: ConversationSummary
        let request: Int
    }

    private struct List {
        var keys: Set<String> = []
        var cursor: String?
        var state = LoadState.idle
        var loadedAt: Date?
        var stale = true
        var request: Int?
        var firstPage = false
        var task: Task<Void, Never>?
    }

    public static let shared = ConversationHistory()

    public private(set) var epoch: UUID
    public private(set) var ownerID: String?
    public nonisolated let cache: DiskCache
    private let fetch: @MainActor (Scope, String?) async throws -> ConversationPage
    private let send: @MainActor (UUID, Request) async throws -> Void
    private var active = List()
    private var archived = List()
    private var copies: [String: Copy] = [:]
    private var edits: [String: [Field: PendingEdit]] = [:]
    private var requests = 0

    init(
        cacheDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appending(path: "ConversationHistory", directoryHint: .isDirectory),
        fetch: @escaping @MainActor (Scope, String?) async throws -> ConversationPage = ConversationPage.fetch,
        send: @escaping @MainActor (UUID, Request) async throws -> Void = { epoch, body in
            _ = try await GenerateClient.postJSON(identityEpoch: epoch, path: "api/conversation", body: body)
        }
    ) {
        let epoch = UUID()
        self.epoch = epoch
        self.fetch = fetch
        self.send = send
        cache = DiskCache(directory: cacheDirectory, epoch: epoch)
    }

    public var items: [ConversationSummary] { items(.active) }
    public var loadState: LoadState { active.state }
    public var canLoadMore: Bool { active.cursor != nil }

    public func canLoadMore(_ scope: Scope) -> Bool { self[keyPath: list(scope)].cursor != nil }

    public func items(_ scope: Scope) -> [ConversationSummary] {
        let shown = active.keys.union(archived.keys)
            .compactMap { copies[$0].flatMap(edited) }
            .filter { $0.archived == (scope == .archived) }
        let newestFirst = { (a: ConversationSummary, b: ConversationSummary) in (a.updatedAt, a.key) > (b.updatedAt, b.key) }
        guard scope == .active else { return shown.sorted(by: newestFirst) }
        return shown.filter(\.isPinned).sorted { ($0.pinnedAt ?? 0, $0.key) > ($1.pinnedAt ?? 0, $1.key) }
            + shown.filter { !$0.isPinned }.sorted(by: newestFirst)
    }

    public func loadState(_ scope: Scope) -> LoadState { self[keyPath: list(scope)].state }

    public func summary(for key: String) -> ConversationSummary? { copies[key].flatMap(edited) }

    public func load(_ scope: Scope = .active, force: Bool = false) async {
        let current = self[keyPath: list(scope)]
        if !force, !current.stale, current.state == .loaded,
           let loadedAt = current.loadedAt, Date().timeIntervalSince(loadedAt) < 30 {
            return
        }
        if current.firstPage, let task = current.task {
            await task.value
            return
        }
        await request(scope, cursor: nil)
    }

    public func loadMore(_ scope: Scope = .active) async {
        let current = self[keyPath: list(scope)]
        guard current.task == nil, current.state == .loaded, let cursor = current.cursor else { return }
        await request(scope, cursor: cursor)
    }

    public func invalidate() {
        active.stale = true
        archived.stale = true
    }

    public func reset(ownerID: String? = nil) {
        self.ownerID = ownerID
        epoch = UUID()
        cache.reset(ownerID: ownerID, epoch: epoch)
        active.task?.cancel()
        archived.task?.cancel()
        active = List()
        archived = List()
        copies = [:]
        edits = [:]
    }

    public func edit(_ key: String, _ change: Change) -> Edit? {
        let field = change.field
        let exclusive: Set<Field> = field == .pinned ? [.pinned] : [.title, .archived, .deleted]
        if edits[key]?.contains(where: { exclusive.contains($0.key) && $0.value.savedAfter == nil }) == true {
            return nil
        }
        let edit = Edit(id: UUID(), key: key, field: field, epoch: epoch)
        edits[key, default: [:]][field] = PendingEdit(
            id: edit.id, change: change,
            pinnedAt: change == .pin(true) ? Date().timeIntervalSince1970 * 1000 : nil)
        return edit
    }

    public func edit(_ keys: [String], _ change: Change) -> [Edit] {
        keys.compactMap { edit($0, change) }
    }

    public func save(_ edit: Edit) async -> SaveResult {
        await save([edit])
    }

    public func save(_ group: [Edit]) async -> SaveResult {
        guard let change = group.lazy.compactMap({ self.pending($0)?.change }).first else { return .superseded }
        var result = SaveResult.superseded
        for start in stride(from: 0, to: group.count, by: Self.maxKeysPerRequest) {
            let batch = group[start..<min(start + Self.maxKeysPerRequest, group.count)].filter { pending($0) != nil }
            guard let epoch = batch.first?.epoch else { continue }
            var body = Request(action: change.action)
            if batch.count == 1 { body.conversationKey = batch[0].key } else { body.conversationKeys = batch.map(\.key) }
            if case .rename(let title) = change { body.title = title }
            var retries = 2
            while true {
                do {
                    try await send(epoch, body)
                    break
                } catch let failure as GenerateClient.JSONRequestFailure
                            where change == .delete && failure.statusCode == 503 && retries > 0 {
                    retries -= 1
                    try? await Task.sleep(for: .seconds(1))
                    guard batch.contains(where: { pending($0) != nil }) else { return .superseded }
                } catch {
                    return batch.contains { pending($0) != nil } ? .failed : .superseded
                }
            }
            for edit in batch where pending(edit) != nil {
                edits[edit.key]?[edit.field]?.savedAfter = requests
                result = .saved
            }
            invalidate()
        }
        return result
    }

    public func discard(_ edit: Edit) {
        guard pending(edit) != nil else { return }
        edits[edit.key]?[edit.field] = nil
        if edits[edit.key]?.isEmpty == true { edits[edit.key] = nil }
    }

    public func isRemoving(_ key: String) -> Bool {
        edits[key]?.values.contains {
            $0.savedAfter == nil && ($0.change == .delete || $0.change == .archive(true))
        } ?? false
    }

    public var removingKeys: Set<String> { Set(edits.keys.filter(isRemoving)) }

    private static let maxKeysPerRequest = 100

    private func list(_ scope: Scope) -> ReferenceWritableKeyPath<ConversationHistory, List> {
        scope == .active ? \.active : \.archived
    }

    private func pending(_ edit: Edit) -> PendingEdit? {
        guard edit.epoch == epoch, let current = edits[edit.key]?[edit.field],
              current.id == edit.id, current.savedAfter == nil else { return nil }
        return current
    }

    private func edited(_ copy: Copy) -> ConversationSummary? {
        var item = copy.summary
        for edit in (edits[item.key] ?? [:]).values where edit.savedAfter.map({ copy.request <= $0 }) ?? true {
            switch edit.change {
            case .pin: item.pinnedAt = edit.pinnedAt
            case .rename(let title): item.title = title
            case .archive(let archived): item.archived = archived
            case .delete: return nil
            }
        }
        return item
    }

    private func request(_ scope: Scope, cursor: String?) async {
        requests += 1
        let request = requests
        let epoch = epoch
        let path = list(scope)
        self[keyPath: path].state = .loading
        self[keyPath: path].request = request
        self[keyPath: path].firstPage = cursor == nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let page: ConversationPage?
            do { page = try await self.fetch(scope, cursor) } catch { page = nil }
            let path = self.list(scope)
            guard self.epoch == epoch, self[keyPath: path].request == request else { return }
            self[keyPath: path].request = nil
            self[keyPath: path].task = nil
            if let page {
                self.apply(page, to: path, request: request, replacing: cursor == nil)
            } else {
                self[keyPath: path].state = .failed
                self[keyPath: path].stale = true
            }
        }
        self[keyPath: path].task = task
        await task.value
    }

    private func apply(
        _ page: ConversationPage, to path: ReferenceWritableKeyPath<ConversationHistory, List>,
        request: Int, replacing: Bool
    ) {
        var list = self[keyPath: path]
        if replacing {
            list.keys = []
            list.loadedAt = Date()
            list.stale = false
        }
        for item in page.pinned + page.conversations {
            copies[item.key] = Copy(summary: item, request: request)
            list.keys.insert(item.key)
        }
        list.cursor = page.nextCursor
        list.state = .loaded
        self[keyPath: path] = list
        let listed = active.keys.union(archived.keys)
        copies = copies.filter { listed.contains($0.key) }
        for (key, fields) in edits {
            let kept = fields.filter { _, edit in
                guard let savedAfter = edit.savedAfter else { return true }
                return copies[key].map { $0.request <= savedAfter } ?? false
            }
            edits[key] = kept.isEmpty ? nil : kept
        }
    }

    public final class DiskCache: @unchecked Sendable {
        public struct Entry: Sendable {
            public let data: Data
            public let age: TimeInterval
        }

        private let lock = NSLock()
        private let directory: URL?
        private var ownerDirectory: URL?
        private var epoch: UUID

        init(directory: URL?, epoch: UUID) {
            self.directory = directory
            self.epoch = epoch
            ownerDirectory = directory?.appending(path: Self.digest("guest"), directoryHint: .isDirectory)
            if let directory,
               let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                for file in files where file.pathExtension == "json" {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }

        func reset(ownerID: String?, epoch: UUID) {
            lock.withLock {
                if let ownerDirectory { try? FileManager.default.removeItem(at: ownerDirectory) }
                self.epoch = epoch
                let owner = ownerID.map { "user:\($0)" } ?? "guest"
                ownerDirectory = directory?.appending(path: Self.digest(owner), directoryHint: .isDirectory)
            }
        }

        public func read(for key: String, epoch: UUID) -> Entry? {
            lock.withLock {
                guard self.epoch == epoch, let url = url(for: key),
                      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let modified = attributes[.modificationDate] as? Date else { return nil }
                let age = Date().timeIntervalSince(modified)
                guard age <= 7 * 24 * 60 * 60, let data = try? Data(contentsOf: url) else {
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
                return Entry(data: data, age: age)
            }
        }

        public func store(_ data: Data, for key: String, epoch: UUID) {
            lock.withLock {
                guard self.epoch == epoch, let url = url(for: key) else { return }
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url, options: Self.writeOptions)
            }
        }

        public func remove(for key: String, epoch: UUID) {
            lock.withLock {
                guard self.epoch == epoch, let url = url(for: key) else { return }
                try? FileManager.default.removeItem(at: url)
            }
        }

        private func url(for key: String) -> URL? {
            ownerDirectory?.appending(path: "\(Self.digest(key)).json", directoryHint: .notDirectory)
        }

        #if os(iOS)
        private static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtection]
        #else
        private static let writeOptions: Data.WritingOptions = [.atomic]
        #endif

        private static func digest(_ value: String) -> String {
            SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }
}

extension ConversationHistory.Change {
    fileprivate var field: ConversationHistory.Field {
        switch self {
        case .pin: .pinned
        case .rename: .title
        case .archive: .archived
        case .delete: .deleted
        }
    }

    fileprivate var action: String {
        switch self {
        case .pin(let pinned): pinned ? "pin" : "unpin"
        case .rename: "rename"
        case .archive(let archived): archived ? "archive" : "unarchive"
        case .delete: "delete"
        }
    }
}
