import SwiftUI
import ImageIO
import CryptoKit
import OSLog
import EmblemCore

actor ImageLoader {
    static let shared = ImageLoader()

    struct Metrics: Sendable {
        fileprivate(set) var memoryHits = 0
        fileprivate(set) var diskHits = 0
        fileprivate(set) var coalescedHits = 0
        fileprivate(set) var coldLoads = 0
        fileprivate(set) var failures = 0
        fileprivate(set) var elapsedMilliseconds = 0.0

        var requests: Int {
            memoryHits + diskHits + coalescedHits + coldLoads + failures
        }

        var hitRate: Double {
            guard requests > 0 else { return 0 }
            return Double(memoryHits + diskHits + coalescedHits) / Double(requests)
        }

        var averageMilliseconds: Double {
            guard requests > 0 else { return 0 }
            return elapsedMilliseconds / Double(requests)
        }
    }

    private enum LoadSource {
        case memory, disk, coalesced, cold, failure
    }

    private struct LoadedImage {
        let image: UIImage
        let rescueURL: String?
        var fromDisk = false
    }

    nonisolated(unsafe) private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 180
        cache.totalCostLimit = 96 << 20
        return cache
    }()
    private var inFlight: [String: Task<LoadedImage?, Never>] = [:]
    private var urlInFlight: [String: Task<LoadedImage?, Never>] = [:]
    private var resolveInFlight: [String: Task<URL?, Never>] = [:]
    private var resolvedURLs: [String: URL] = [:]
    private var dataInFlight: [URL: Task<Data?, Never>] = [:]
    private var metrics = Metrics()
    private(set) var objectIconsUnavailable = false
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "emblem", category: "image-pipeline")

    private static let rescueKey = "image.rescues"
    private var rescues: [String: String] =
        (UserDefaults.standard.dictionary(forKey: rescueKey) as? [String: String] ?? [:])
            .filter { $0.value != "miss" }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20,
                                   directory: caches.appending(path: "EmblemHTTP2", directoryHint: .isDirectory))
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    nonisolated func cachedImage(for spec: ImageSpec, maxPixelSize: CGFloat) -> UIImage? {
        Self.specCacheKeys(spec, maxPixelSize: maxPixelSize)
            .lazy
            .compactMap { self.cache.object(forKey: $0) }
            .first
    }

    nonisolated func cachedImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        guard let url = Self.normalizedRemoteURL(url) else { return nil }
        return Self.urlCacheKeys(url, maxPixelSize: maxPixelSize)
            .lazy
            .compactMap { self.cache.object(forKey: $0) }
            .first
    }

    private static func specCacheKey(_ spec: ImageSpec, maxPixelSize: CGFloat) -> NSString {
        let loadPixelSize = pixelBucket(
            spec.kind == .object ? 160 : maxPixelSize)
        return "v2:\(resolutionKey(for: spec, hero: isHero(spec, maxPixelSize))):\(Int(loadPixelSize))" as NSString
    }

    private static func urlCacheKey(_ url: URL, maxPixelSize: CGFloat) -> NSString {
        "v2:url:\(url.absoluteString):\(Int(pixelBucket(maxPixelSize)))" as NSString
    }

    private static func pixelBucket(_ size: CGFloat) -> CGFloat {
        switch size {
        case ...200: 200
        case ...400: 400
        case ...800: 800
        case ...1200: 1200
        default: ceil(size / 400) * 400
        }
    }

    private static func reusableBuckets(startingAt size: CGFloat) -> [CGFloat] {
        let bucket = pixelBucket(size)
        return [bucket, 200, 400, 800, 1200]
            .filter { $0 >= bucket }
            .reduce(into: [CGFloat]()) { values, value in
                if !values.contains(value) { values.append(value) }
            }
    }

    private static func specCacheKeys(
        _ spec: ImageSpec, maxPixelSize: CGFloat
    ) -> [NSString] {
        if spec.kind == .object {
            return [specCacheKey(spec, maxPixelSize: 160)]
        }
        return reusableBuckets(startingAt: maxPixelSize).map {
            "v2:\(resolutionKey(for: spec, hero: isHero(spec, maxPixelSize))):\(Int($0))" as NSString
        }
    }

    private static func urlCacheKeys(
        _ url: URL, maxPixelSize: CGFloat
    ) -> [NSString] {
        reusableBuckets(startingAt: maxPixelSize).map {
            "v2:url:\(url.absoluteString):\(Int($0))" as NSString
        }
    }

    func image(
        for spec: ImageSpec,
        maxPixelSize: CGFloat,
        priority: TaskPriority? = nil
    ) async -> UIImage? {
        let started = CFAbsoluteTimeGetCurrent()
        let loadPixelSize = Self.pixelBucket(
            spec.kind == .object ? 160 : maxPixelSize)
        let key = Self.specCacheKey(spec, maxPixelSize: maxPixelSize)
        if let cached = cachedImage(for: spec, maxPixelSize: maxPixelSize) {
            record(.memory, since: started)
            return cached
        }
        for candidate in Self.specCacheKeys(spec, maxPixelSize: maxPixelSize) {
            guard let existing = inFlight[candidate as String] else { continue }
            let image = await existing.value?.image
            record(image == nil ? .failure : .coalesced, since: started)
            return image
        }

        let usesDisk = !(spec.kind == .object && ObjectLibrary.imageURL(for: spec.query) != nil)
        let hero = Self.isHero(spec, maxPixelSize)
        let resolution = Self.resolutionKey(for: spec, hero: hero)
        let rescueValue = rescues[resolution]
        let task = Task<LoadedImage?, Never>(priority: priority ?? Task.currentPriority) {
            await self.load(
                spec, maxPixelSize: loadPixelSize, hero: hero,
                diskKey: usesDisk ? key as String : nil, rescue: rescueValue)
        }
        inFlight[key as String] = task
        let loaded = await task.value
        inFlight[key as String] = nil

        if let rescueURL = loaded?.rescueURL { setRescue(rescueURL, for: resolution) }
        if loaded == nil, rescueValue != nil { clearRescue(for: resolution) }
        if let image = loaded?.image {
            cache.setObject(image, forKey: key, cost: Self.cost(of: image))
        }
        record(loaded == nil ? .failure : loaded?.fromDisk == true ? .disk : .cold, since: started)
        return loaded?.image
    }

    func prefetch(
        _ specs: [ImageSpec],
        maxPixelSize: CGFloat = 700,
        limit: Int = 4
    ) async {
        var unique = [ImageSpec]()
        var seen = Set<String>()
        for spec in specs {
            let key = Self.specCacheKey(spec, maxPixelSize: maxPixelSize) as String
            if seen.insert(key).inserted { unique.append(spec) }
        }
        guard !unique.isEmpty else { return }

        let concurrency = max(1, min(limit, 12))
        await withTaskGroup(of: Void.self) { group in
            var iterator = unique.makeIterator()
            for _ in 0..<min(concurrency, unique.count) {
                guard let spec = iterator.next() else { break }
                group.addTask(priority: .utility) {
                    _ = await self.image(
                        for: spec, maxPixelSize: maxPixelSize, priority: .utility)
                }
            }
            while await group.next() != nil {
                guard !Task.isCancelled, let spec = iterator.next() else {
                    group.cancelAll()
                    break
                }
                group.addTask(priority: .utility) {
                    _ = await self.image(
                        for: spec, maxPixelSize: maxPixelSize, priority: .utility)
                }
            }
        }

        let snapshot = metrics
        Self.logger.info(
            "prefetch complete count=\(unique.count, privacy: .public) hitRate=\(snapshot.hitRate, format: .fixed(precision: 3), privacy: .public) avgMs=\(snapshot.averageMilliseconds, format: .fixed(precision: 1), privacy: .public)")
    }

    nonisolated private func load(
        _ spec: ImageSpec, maxPixelSize: CGFloat, hero: Bool, diskKey: String?, rescue: String?
    ) async -> LoadedImage? {
        if let diskKey, let cached = Self.diskImage(for: diskKey, maxPixelSize: maxPixelSize) {
            return LoadedImage(image: cached, rescueURL: nil, fromDisk: true)
        }
        if spec.kind == .object,
           let url = ObjectLibrary.imageURL(for: spec.query),
           let data = try? Data(contentsOf: url),
           let image = Self.downsample(data, maxPixelSize: maxPixelSize) {
            return LoadedImage(image: image, rescueURL: nil)
        }
        func fetch(_ url: URL) async -> UIImage? {
            guard let data = await sharedData(url),
                  let image = Self.downsample(data, maxPixelSize: maxPixelSize)
            else { return nil }
            if let diskKey { Self.store(image, for: diskKey) }
            return image
        }
        if let rescue, let url = URL(string: rescue), let image = await fetch(url) {
            return LoadedImage(image: image, rescueURL: nil)
        }
        if spec.kind == .object, await objectIconsUnavailable { return nil }
        let identityEpoch = await MainActor.run { ConversationHistory.shared.epoch }
        var resolved = await sharedResolve(spec, hero: hero, identityEpoch: identityEpoch, excluding: nil)
        let cannotGenerate = spec.kind == .object ? await objectIconsUnavailable : false
        if resolved == nil, Self.isGenerated(spec), !cannotGenerate {
            try? await Task.sleep(for: .seconds(3))
            resolved = await sharedResolve(spec, hero: hero, identityEpoch: identityEpoch, excluding: nil)
        }
        guard let url = resolved else { return nil }
        if let image = await fetch(url) {
            return LoadedImage(image: image, rescueURL: url.absoluteString)
        }
        guard let alternate = await sharedResolve(
            spec, hero: hero, identityEpoch: identityEpoch, excluding: url.absoluteString),
              alternate != url,
              let image = await fetch(alternate)
        else { return nil }
        return LoadedImage(image: image, rescueURL: alternate.absoluteString)
    }

    private func sharedResolve(_ spec: ImageSpec, hero: Bool, identityEpoch: UUID, excluding: String?) async -> URL? {
        let key = Self.resolutionKey(for: spec, hero: hero) + "\u{1F}" + (excluding ?? "")
        if let known = resolvedURLs[key] { return known }
        if let existing = resolveInFlight[key] { return await existing.value }
        let session = session
        let task = Task<URL?, Never> {
            await Self.withResolverTimeout(seconds: Self.resolveBudget(for: spec)) {
                await Self.resolveURL(
                    spec, hero: hero, session: session, identityEpoch: identityEpoch, excluding: excluding)
            }
        }
        resolveInFlight[key] = task
        let url = await task.value
        resolveInFlight[key] = nil
        if let url { resolvedURLs[key] = url }
        return url
    }

    private func sharedData(_ url: URL) async -> Data? {
        guard let url = Self.normalizedRemoteURL(url) else { return nil }
        if let existing = dataInFlight[url] { return await existing.value }
        let session = session
        let task = Task<Data?, Never> { await Self.downloadData(url, session: session) }
        dataInFlight[url] = task
        let data = await task.value
        dataInFlight[url] = nil
        return data
    }

    private func markObjectIconsUnavailable() {
        objectIconsUnavailable = true
    }

    private func setRescue(_ value: String, for resolution: String) {
        rescues[resolution] = value
        UserDefaults.standard.set(rescues, forKey: Self.rescueKey)
        Task { @MainActor in ImageResolutions.shared.record() }
    }

    private func clearRescue(for resolution: String) {
        rescues.removeValue(forKey: resolution)
        UserDefaults.standard.set(rescues, forKey: Self.rescueKey)
    }

    private static func isHero(_ spec: ImageSpec, _ maxPixelSize: CGFloat) -> Bool {
        spec.kind != .object && maxPixelSize >= 800
    }

    private static func resolutionKey(for spec: ImageSpec, hero: Bool) -> String {
        let query = spec.query
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .lowercased()
        let tier = hero ? ":hero" : ""
        if let aspect = spec.aspect {
            return "\(spec.kind.rawValue):\(aspect.rawValue)\(tier):\(query)"
        }
        return "\(spec.kind.rawValue)\(tier):\(query)"
    }

    private static func isGenerated(_ spec: ImageSpec) -> Bool {
        spec.kind == .object || spec.kind == .generated
    }

    private static func resolveBudget(for spec: ImageSpec) -> Double {
        isGenerated(spec) ? 45 : 18
    }

    private static func withResolverTimeout(
        seconds: Double, operation: @escaping @Sendable () async -> URL?
    ) async -> URL? {
        await withTaskGroup(of: URL?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    func image(
        at url: URL,
        maxPixelSize: CGFloat,
        priority: TaskPriority? = nil
    ) async -> UIImage? {
        let started = CFAbsoluteTimeGetCurrent()
        guard let url = Self.normalizedRemoteURL(url) else { return nil }
        let key = Self.urlCacheKey(url, maxPixelSize: maxPixelSize)
        if let cached = cachedImage(at: url, maxPixelSize: maxPixelSize) {
            record(.memory, since: started)
            return cached
        }
        for candidate in Self.urlCacheKeys(url, maxPixelSize: maxPixelSize) {
            guard let existing = urlInFlight[candidate as String] else { continue }
            let image = await existing.value?.image
            record(image == nil ? .failure : .coalesced, since: started)
            return image
        }
        let pixelSize = Self.pixelBucket(maxPixelSize)
        let task = Task<LoadedImage?, Never>(priority: priority ?? Task.currentPriority) {
            await self.loadDirect(url, maxPixelSize: pixelSize, diskKey: key as String)
        }
        urlInFlight[key as String] = task
        let loaded = await task.value
        urlInFlight[key as String] = nil
        if let image = loaded?.image {
            cache.setObject(image, forKey: key, cost: Self.cost(of: image))
        }
        record(loaded == nil ? .failure : loaded?.fromDisk == true ? .disk : .cold, since: started)
        return loaded?.image
    }

    nonisolated private func loadDirect(_ url: URL, maxPixelSize: CGFloat, diskKey: String) async -> LoadedImage? {
        if let cached = Self.diskImage(for: diskKey, maxPixelSize: maxPixelSize) {
            return LoadedImage(image: cached, rescueURL: nil, fromDisk: true)
        }
        guard let data = await sharedData(url),
              let image = Self.downsample(data, maxPixelSize: maxPixelSize)
        else { return nil }
        Self.store(image, for: diskKey)
        return LoadedImage(image: image, rescueURL: nil)
    }

    private static let diskCacheURL: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: base.appending(path: "EmblemImages", directoryHint: .isDirectory))
        let url = base.appending(path: "EmblemImages2", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static func diskURL(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return diskCacheURL.appending(path: "\(hash).jpg")
    }

    private static let diskLifetime: TimeInterval = 60 * 24 * 60 * 60

    private static func diskImage(for key: String, maxPixelSize: CGFloat) -> UIImage? {
        let url = diskURL(for: key)
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let modified = values.contentModificationDate,
              Date().timeIntervalSince(modified) <= diskLifetime,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe)
        else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return downsample(data, maxPixelSize: maxPixelSize)
    }

    private static func store(_ image: UIImage, for key: String) {
        let alpha = image.cgImage?.alphaInfo
        let keepsAlpha = alpha == .first || alpha == .last
            || alpha == .premultipliedFirst || alpha == .premultipliedLast
        guard let data = keepsAlpha ? image.pngData() : image.jpegData(compressionQuality: 0.88)
        else { return }
        try? data.write(to: diskURL(for: key), options: .atomic)
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private static func normalizedRemoteURL(_ url: URL) -> URL? {
        let absolute = url.scheme == nil
            ? URL(string: url.relativeString, relativeTo: AppConfig.baseURL)?.absoluteURL
            : url.absoluteURL
        guard let absolute,
              let scheme = absolute.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return absolute
    }

    private static func downloadData(_ url: URL, session: URLSession) async -> Data? {
        guard let (data, response) = try? await session.data(from: url) else { return nil }
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            return nil
        }
        return data
    }

    private static func resolveURL(
        _ spec: ImageSpec,
        hero: Bool,
        session: URLSession,
        identityEpoch: UUID,
        excluding: String? = nil
    ) async -> URL? {
        var components = URLComponents(
            url: AppConfig.baseURL.appending(path: "api/image"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: spec.query),
            URLQueryItem(name: "kind", value: spec.kind.rawValue),
        ]
        if let aspect = spec.aspect {
            components.queryItems?.append(URLQueryItem(name: "aspect", value: aspect.rawValue))
        }
        if let excluding {
            components.queryItems?.append(URLQueryItem(name: "exclude", value: excluding))
        }
        if hero {
            components.queryItems?.append(URLQueryItem(name: "placement", value: "hero"))
        }
        guard let url = components.url else { return nil }
        let data: Data
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = resolveBudget(for: spec)
            if let token = try await GenerateClient.bearerToken(for: identityEpoch) {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (received, response) = try await session.data(for: request)
            try await GenerateClient.checkIdentity(identityEpoch)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            data = received
        } catch { return nil }
        struct Payload: Decodable { let url: String?; let unavailable: Bool? }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        if payload.unavailable == true, spec.kind == .object {
            await shared.markObjectIconsUnavailable()
        }
        guard let urlString = payload.url else { return nil }
        guard let url = URL(string: urlString, relativeTo: AppConfig.baseURL) else { return nil }
        return normalizedRemoteURL(url)
    }

    private static func downsample(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize * 3,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func record(_ source: LoadSource, since started: CFAbsoluteTime) {
        switch source {
        case .memory: metrics.memoryHits += 1
        case .disk: metrics.diskHits += 1
        case .coalesced: metrics.coalescedHits += 1
        case .cold: metrics.coldLoads += 1
        case .failure: metrics.failures += 1
        }
        metrics.elapsedMilliseconds += (CFAbsoluteTimeGetCurrent() - started) * 1_000
    }
}

@Observable @MainActor
final class ImageResolutions {
    static let shared = ImageResolutions()
    private(set) var generation = 0
    func record() { generation &+= 1 }
}
