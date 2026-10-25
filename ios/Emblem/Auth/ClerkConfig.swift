import Foundation

enum AppInfo {
    static let name = "Emblem"
}

enum ClerkConfig {
    static var publishableKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "ClerkPublishableKey") as? String,
              key.hasPrefix("pk_") else { return nil }
        return key
    }

    static let jwtTemplate = "convex"
}
