import Foundation

@MainActor
public enum WritingClient {
    public enum Failure: LocalizedError {
        case unavailable, incomplete, conflict, appleOrigin, appleMode
        public var errorDescription: String? {
            switch self {
            case .appleOrigin:
                "Tone rewrites aren’t available for Apple-generated drafts. You can edit this draft directly."
            case .appleMode: "Tone rewrites use Emblem. Choose Emblem in Settings to use them."
            case .unavailable: "The rewrite couldn't finish. Your draft is unchanged. Try again."
            case .incomplete: "The connection ended before the rewrite finished. Try again."
            case .conflict:
                "This draft changed elsewhere. Copy your edits before discarding and reopening it."
            }
        }
    }

    public static func rewrite(
        body: String, style: String, origin: GeneratedPage.Origin,
        session: URLSession = .shared, defaults: UserDefaults = .standard,
        onText: (String) -> Void
    ) async throws -> String {
        guard origin == .server else { throw Failure.appleOrigin }
        guard OnDeviceModel.selection(in: defaults) == .emblem else { throw Failure.appleMode }
        struct Input: Encodable {
            var body: String
            var style: String
        }
        struct Event: Decodable {
            var type: String
            var text: String?
        }
        var request = try await request(method: "POST", body: Input(body: body, style: style))
        if let credential = GenerateClient.inferenceCredentialProvider?() {
            request.setValue(credential.provider, forHTTPHeaderField: "x-emblem-inference-provider")
            request.setValue(
                credential.model.rawValue, forHTTPHeaderField: "x-emblem-inference-model")
            request.setValue(credential.apiKey, forHTTPHeaderField: "x-emblem-inference-key")
        }
        if let model = GenerateClient.managedInferenceModelProvider?() {
            request.setValue(model.rawValue, forHTTPHeaderField: "x-emblem-managed-model")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.unavailable }
        var text = ""
        for try await line in bytes.lines where !line.isEmpty {
            try Task.checkCancellation()
            guard let data = line.data(using: .utf8), data.count < 100_000,
                let event = try? JSONDecoder().decode(Event.self, from: data)
            else { throw Failure.incomplete }
            switch event.type {
            case "delta":
                guard let delta = event.text, text.utf16.count + delta.utf16.count <= 20000 else {
                    throw Failure.incomplete
                }
                text += delta
                onText(text)
            case "complete":
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw Failure.incomplete
                }
                return text
            default: throw Failure.unavailable
            }
        }
        throw Failure.incomplete
    }

    public static func save(
        page: GeneratedPage, blockID: String, draftID: String, previousBody: String, body: String
    ) async throws {
        guard page.origin == .server else { return }
        guard let key = page.conversationKey else { return }
        struct Update: Encodable {
            var conversationKey: String
            var pageKey: String
            var blockID: String
            var draftID: String
            var previousBody: String
            var body: String
        }
        let request = try await request(
            method: "PATCH",
            body: Update(
                conversationKey: key, pageKey: page.pageKey, blockID: blockID,
                draftID: draftID, previousBody: previousBody, body: body))
        guard request.value(forHTTPHeaderField: "Authorization") != nil else { return }
        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode
        if code == 409 { throw Failure.conflict }
        guard code == 200 else { throw URLError(.cannotWriteToFile) }
    }

    private static func request(method: String, body: some Encodable) async throws -> URLRequest {
        let epoch = ConversationHistory.shared.epoch
        var request = URLRequest(url: AppConfig.baseURL.appending(path: "api/writing"))
        request.httpMethod = method
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        if let token = try await GenerateClient.bearerToken(for: epoch) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
