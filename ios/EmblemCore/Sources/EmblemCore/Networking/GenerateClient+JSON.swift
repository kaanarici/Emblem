import Foundation
import os
import Security

extension GenerateClient {
    struct JSONRequestFailure: Error, LocalizedError, Sendable {
        let statusCode: Int

        var retryable: Bool { statusCode == 408 || statusCode == 425 || statusCode == 429 || statusCode >= 500 }

        var errorDescription: String? {
            switch statusCode {
            case 401: "Sign in again to continue."
            case 403: "This account cannot access that item."
            case 404: "That item is no longer available."
            case 409: "That item changed. Refresh it and try again."
            case 429: "The request limit was reached. Try again later."
            case 500...599: "The service is temporarily unavailable. Try again in a moment."
            default: "The request could not be completed."
            }
        }
    }

    static func checkJSONResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else { throw JSONRequestFailure(statusCode: http.statusCode) }
    }

    public static func fetchJSON(
        identityEpoch: UUID? = nil,
        path: String,
        query: [URLQueryItem],
        timeoutInterval: TimeInterval = oneShotTimeout
    ) async throws -> Data {
        let epoch = identityEpoch ?? ConversationHistory.shared.epoch
        try checkIdentity(epoch)
        guard var components = URLComponents(
            url: AppConfig.baseURL.appending(path: path),
            resolvingAgainstBaseURL: false)
        else { throw URLError(.badURL) }
        components.queryItems = query
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeoutInterval
        if let token = try await bearerToken(for: epoch) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        logAuthState(path: path, request: request)
        let (data, response) = try await session.data(for: request)
        try checkIdentity(epoch)
        try checkJSONResponse(response)
        return data
    }

    public static func postJSON(identityEpoch: UUID? = nil, path: String, body: some Encodable) async throws -> Data {
        let epoch = identityEpoch ?? ConversationHistory.shared.epoch
        try checkIdentity(epoch)
        var request = URLRequest(url: AppConfig.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = oneShotTimeout
        request.httpBody = try JSONEncoder().encode(body)
        if let token = try await Self.bearerToken(for: epoch) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        try checkIdentity(epoch)
        try checkJSONResponse(response)
        return data
    }
}
