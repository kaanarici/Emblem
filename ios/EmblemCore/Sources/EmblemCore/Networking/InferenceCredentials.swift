import Foundation
import Security

public struct LocalInferenceCredential: Codable {
    public enum Model: String, Codable, CaseIterable, Identifiable {
        case qwen = "qwen-3.8-27b"
        case gpt6Luna = "gpt-6-luna"
        case mercury = "inception/mercury-3"
        case luna = "openai/gpt-6-luna"

        public var id: String { rawValue }

        var provider: String {
            switch self {
            case .qwen: "cerebras"
            case .gpt6Luna: "openai"
            case .mercury, .luna: "openrouter"
            }
        }

        public var name: String {
            switch self {
            case .qwen: "Qwen 3.8 27B"
            case .gpt6Luna: "GPT-6 Luna"
            case .mercury: "Mercury 3"
            case .luna: "GPT-6 Luna"
            }
        }

        public var ownKeyName: String {
            switch self {
            case .gpt6Luna, .luna: "\(name) (\(keyName) key)"
            case .qwen, .mercury: name
            }
        }

        public var detail: String {
            switch self {
            case .qwen: "Cerebras"
            case .gpt6Luna: "OpenAI · no reasoning"
            case .mercury: "Inception via OpenRouter · diffusion LLM"
            case .luna: "OpenAI via OpenRouter · no reasoning"
            }
        }

        public var keyName: String {
            switch self {
            case .qwen: "Cerebras"
            case .gpt6Luna: "OpenAI"
            case .mercury, .luna: "OpenRouter"
            }
        }
    }

    public var model: Model
    public var apiKey: String

    var provider: String { model.provider }

    public init(model: Model, apiKey: String) {
        self.model = model
        self.apiKey = apiKey
    }
}

public enum UserInferenceCredentials {
    private static let service = "app.emblem.inference"

    public enum Choice: String, CaseIterable {
        case emblem, mercury, luna, custom

        public var model: LocalInferenceCredential.Model? {
            switch self {
            case .mercury: .mercury
            case .luna: .luna
            case .emblem, .custom: nil
            }
        }
    }

    public static func choice(userID: String) -> Choice {
        if let raw = UserDefaults.standard.string(forKey: "inference.choice.\(userID)"),
           let choice = Choice(rawValue: raw) { return choice }
        return load(userID: userID) == nil ? .emblem : .custom
    }

    public static func choose(_ choice: Choice, userID: String) {
        UserDefaults.standard.set(choice.rawValue, forKey: "inference.choice.\(userID)")
    }

    public static func load(userID: String) -> LocalInferenceCredential? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: userID,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(LocalInferenceCredential.self, from: data)
    }

    @discardableResult
    public static func save(_ credential: LocalInferenceCredential, userID: String) -> Bool {
        guard let data = try? JSONEncoder().encode(credential) else { return false }
        let key = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: userID,
        ] as CFDictionary
        let status = SecItemUpdate(key, [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        return SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: userID,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData: data,
        ] as CFDictionary, nil) == errSecSuccess
    }

    public static func remove(userID: String) {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: userID,
        ] as CFDictionary)
    }
}
