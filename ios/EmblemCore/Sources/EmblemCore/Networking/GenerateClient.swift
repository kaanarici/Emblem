import Foundation
import os
import Security

@MainActor
public final class GenerateClient {
    public typealias Event = GenerationStream.Event

    var task: Task<Void, Never>?

    public static var bearerTokenProvider: (() async throws -> String?)?
    public static var inferenceCredentialProvider: (() -> LocalInferenceCredential?)?
    public static var managedInferenceModelProvider: (() -> LocalInferenceCredential.Model?)?

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        return URLSession(configuration: config)
    }()
    @usableFromInline static let oneShotTimeout: TimeInterval = 15

    public static func checkIdentity(_ epoch: UUID) throws {
        try Task.checkCancellation()
        guard ConversationHistory.shared.epoch == epoch else { throw CancellationError() }
    }

    public static func bearerToken(for epoch: UUID) async throws -> String? {
        try checkIdentity(epoch)
        let token = try await bearerTokenProvider?()
        try checkIdentity(epoch)
        return token
    }
    private static let performanceLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "emblem",
        category: "generation-performance")

    public func stream(
        path: String,
        body: (some Encodable)?,
        pagePreviewEnabled: Bool = false,
        onEvent: @escaping @MainActor (Event) -> Void
    ) {
        cancel()
        let epoch = ConversationHistory.shared.epoch
        task = Task {
            let requestStarted = ProcessInfo.processInfo.systemUptime
            do {
                guard let url = URL(string: path, relativeTo: AppConfig.baseURL) else {
                    onEvent(.failed(GenerationFailure(
                        code: "invalid_url",
                        message: "The server couldn't generate this page.",
                        retryable: false)))
                    return
                }
                var request = URLRequest(url: url)
                request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
                request.cachePolicy = .reloadIgnoringLocalCacheData
                if let token = try await Self.bearerToken(for: epoch) {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    if path == "api/generate" {
                        if let credential = Self.inferenceCredentialProvider?() {
                            request.setValue(
                                credential.provider,
                                forHTTPHeaderField: "x-emblem-inference-provider")
                            request.setValue(
                                credential.model.rawValue,
                                forHTTPHeaderField: "x-emblem-inference-model")
                            request.setValue(
                                credential.apiKey,
                                forHTTPHeaderField: "x-emblem-inference-key")
                        }
                    }
                }
                if path == "api/generate", let model = Self.managedInferenceModelProvider?() {
                    request.setValue(model.rawValue, forHTTPHeaderField: "x-emblem-managed-model")
                }
                if path == "api/generate", pagePreviewEnabled {
                    request.setValue("v1", forHTTPHeaderField: "X-Emblem-Preview")
                }
                Self.logAuthState(path: path, request: request)
                if let body {
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(body)
                }

                let (bytes, response) = try await Self.session.bytes(for: request)
                try Self.checkIdentity(epoch)
                let headersMs = (ProcessInfo.processInfo.systemUptime - requestStarted) * 1_000
                Self.performanceLogger.info(
                    "generation headers_ms=\(headersMs, format: .fixed(precision: 1))")
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode
                    onEvent(.failed(Self.httpFailure(statusCode: statusCode)))
                    return
                }

                if body != nil { onEvent(.accepted) }
                var stream = GenerationStream()
                var firstBlockSeen = false
                for try await line in bytes.lines {
                    try Self.checkIdentity(epoch)
                    guard !line.isEmpty else { continue }
                    guard let event = stream.consume(Data(line.utf8)) else { continue }
                    switch event {
                    case .pageSnapshot:
                        if !firstBlockSeen {
                            firstBlockSeen = true
                            let elapsed = (ProcessInfo.processInfo.systemUptime - requestStarted) * 1_000
                            Self.performanceLogger.info(
                                "generation first_block_ms=\(elapsed, format: .fixed(precision: 1))")
                        }
                    case .finished:
                        let elapsed = (ProcessInfo.processInfo.systemUptime - requestStarted) * 1_000
                        Self.performanceLogger.info(
                            "generation client_total_ms=\(elapsed, format: .fixed(precision: 1))")
                    default: break
                    }
                    onEvent(event)
                    if stream.isTerminal { return }
                }
                try Task.checkCancellation()
                onEvent(stream.endOfStream())
            } catch is CancellationError {
            } catch {
                onEvent(.failed(Self.transportFailure(error)))
            }
        }
    }

    func stream(
        body: GenerateBody,
        pagePreviewEnabled: Bool = false,
        onEvent: @escaping @MainActor (Event) -> Void
    ) {
        stream(path: "api/generate", body: body, pagePreviewEnabled: pagePreviewEnabled, onEvent: onEvent)
    }

    private static func httpFailure(statusCode: Int?) -> GenerationFailure {
        let code = statusCode.map { "http_\($0)" } ?? "invalid_response"
        let retryable = statusCode.map { $0 == 408 || $0 == 425 || $0 == 429 || $0 >= 500 } ?? true
        return GenerationFailure(
            code: code,
            message: "The server couldn't generate this page.",
            retryable: retryable)
    }

    private static func transportFailure(_ error: Error) -> GenerationFailure {
        guard let urlError = error as? URLError else {
            return GenerationFailure(
                code: "network_error",
                message: "Couldn't reach the server. Try again in a moment.",
                retryable: true)
        }

        switch urlError.code {
        case .userAuthenticationRequired:
            return GenerationFailure(
                code: "authentication_required",
                message: "Sign in again to continue this conversation.",
                retryable: false)
        case .notConnectedToInternet:
            return GenerationFailure(
                code: "offline",
                message: "You're offline. Your message and attachments are still here.",
                retryable: true)
        case .networkConnectionLost:
            return GenerationFailure(
                code: "connection_lost",
                message: "The connection was lost before the page finished.",
                retryable: true)
        case .timedOut:
            return GenerationFailure(
                code: "timeout",
                message: "The request took too long to finish.",
                retryable: true)
        default:
            return GenerationFailure(
                code: "network_\(urlError.errorCode)",
                message: "Couldn't reach the server. Try again in a moment.",
                retryable: true)
        }
    }

    static func logAuthState(path: String, request: URLRequest) {
        #if DEBUG
        let hasAuth = request.value(forHTTPHeaderField: "Authorization") != nil
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "emblem", category: "auth")
            .info("request \(path, privacy: .public) authorization=\(hasAuth ? "bearer" : "none", privacy: .public)")
        #endif
    }

    public init() {}
}
