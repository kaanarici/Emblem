import Foundation

public struct QuestionOption: Codable, Hashable {
    public var title: String
    public var detail: String
    public var tag: String

    public var answer: String { detail.isEmpty ? title : "\(title) (\(detail))" }

    public func matches(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        return value.caseInsensitiveCompare(answer) == .orderedSame
            || value.caseInsensitiveCompare(title) == .orderedSame
            || value.lowercased().hasPrefix(title.lowercased() + " (")
    }
}

public struct QuestionOptionsRequest: Encodable {
    public struct Sibling: Encodable {
        var question: String
        var answer: String

        public init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }
    }
    var prompt: String?
    var intro: String?
    var question: String
    var ask: String?
    var answer: String?
    var siblings: [Sibling]

    public init(prompt: String? = nil, intro: String? = nil, question: String, ask: String? = nil, answer: String? = nil, siblings: [Sibling]) {
        self.prompt = prompt
        self.intro = intro
        self.question = question
        self.ask = ask
        self.answer = answer
        self.siblings = siblings
    }
}

@MainActor
public enum QuestionOptionsClient {
    enum Failure: Error { case unavailable }

    public static func stream(
        _ body: QuestionOptionsRequest,
        onOptions: ([QuestionOption]) -> Void
    ) async throws -> [QuestionOption] {
        struct Event: Decodable {
            var type: String
            var options: [QuestionOption]?
        }
        let epoch = ConversationHistory.shared.epoch
        var request = URLRequest(url: AppConfig.baseURL.appending(path: "api/question-options"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 25
        if let token = try await GenerateClient.bearerToken(for: epoch) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.unavailable }
        for try await line in bytes.lines where !line.isEmpty {
            try Task.checkCancellation()
            guard let event = try? JSONDecoder().decode(Event.self, from: Data(line.utf8)) else {
                throw Failure.unavailable
            }
            switch event.type {
            case "options": onOptions(Array((event.options ?? []).prefix(4)))
            case "complete":
                let options = Array((event.options ?? []).prefix(4))
                guard options.count >= 2 else { throw Failure.unavailable }
                return options
            default: throw Failure.unavailable
            }
        }
        throw Failure.unavailable
    }
}
