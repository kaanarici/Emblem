import Foundation
import os
import Security

extension GenerateClient {
    public enum CancellationAcknowledgement: Equatable {
        case cancelled
        case terminalCompleted
        case terminalFailed
        case unconfirmed
    }

    private struct CancellationRequest: Encodable {
        let requestId: String
        let conversationKey: String
    }

    private struct CancellationResponse: Decodable {
        let state: String
        let status: String?
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    func acknowledgeCancellation(
        requestId: String,
        conversationKey: String
    ) async -> CancellationAcknowledgement {
        let epoch = ConversationHistory.shared.epoch

        let backoff: [Int64] = [100, 180, 300]
        for attempt in 0...backoff.count {
            guard !Task.isCancelled else { return .unconfirmed }
            if let response = try? await Self.deleteGeneration(
                requestId: requestId,
                conversationKey: conversationKey,
                epoch: epoch
            ) {
                switch (response.state, response.status) {
                case ("cancelled", _), ("guest", _): return .cancelled
                case ("terminal", "completed"): return .terminalCompleted
                case ("terminal", "failed"): return .terminalFailed
                case ("missing", _): break
                default: return .unconfirmed
                }
            }
            guard attempt < backoff.count else { return .unconfirmed }
            try? await Task.sleep(for: .milliseconds(backoff[attempt]))
        }
        return .unconfirmed
    }

    private static func deleteGeneration(
        requestId: String,
        conversationKey: String,
        epoch: UUID
    ) async throws -> CancellationResponse {
        var request = URLRequest(url: AppConfig.baseURL.appending(path: "api/generate"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 1
        request.httpBody = try JSONEncoder().encode(CancellationRequest(
            requestId: requestId,
            conversationKey: conversationKey))
        if let token = try await bearerToken(for: epoch) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        try checkIdentity(epoch)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(CancellationResponse.self, from: data)
    }
}
