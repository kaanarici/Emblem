import ClerkKit
import Foundation
import Observation
import SwiftUI
import EmblemCore

@Observable @MainActor
final class AuthStore {
    private let clerk = ClerkConfig.publishableKey.map { _ in Clerk.shared }
    private static let gateCompletedKey = "auth.gateCompleted"

    private(set) var gateCompleted = UserDefaults.standard.bool(forKey: gateCompletedKey)

    var isSignedIn: Bool { clerk?.user != nil }
    var user: User? { clerk?.user }

    var displayName: String? {
        guard let user = clerk?.user else { return nil }
        let name = [user.firstName, user.lastName].compactMap(\.self).joined(separator: " ")
        return name.isEmpty ? nil : name
    }

    private static let guestNameKey = "profile.guestName"

    var greetingName: String? {
        if let first = clerk?.user?.firstName, !first.isEmpty { return first }
        let stored = UserDefaults.standard.string(forKey: Self.guestNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (stored?.isEmpty == false) ? stored : nil
    }

    func setGuestName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.guestNameKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: Self.guestNameKey)
        }
    }

    var email: String? { clerk?.user?.primaryEmailAddress?.emailAddress }
    var avatarURL: URL? { clerk?.user.flatMap { URL(string: $0.imageUrl) } }

    private(set) var revealingHome = false

    func revealHome() { revealingHome = true }

    func completeGate() {
        gateCompleted = true
        UserDefaults.standard.set(true, forKey: Self.gateCompletedKey)
    }

    private func configuredClerk() throws -> Clerk {
        guard let clerk else {
            throw NSError(domain: "Emblem.Auth", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Sign-in isn't configured for this build. You can continue as a guest.",
            ])
        }
        return clerk
    }

    func bearerToken() async throws -> String? {
        let ownerID = clerk?.user?.id
        let epoch = ConversationHistory.shared.epoch
        guard ConversationHistory.shared.ownerID == ownerID else { throw CancellationError() }
        guard clerk?.session != nil else { return nil }
        guard let token = try await clerk?.auth.getToken(.init(template: ClerkConfig.jwtTemplate)),
              !token.isEmpty else { throw URLError(.userAuthenticationRequired) }
        try Task.checkCancellation()
        guard clerk?.user?.id == ownerID,
              ConversationHistory.shared.ownerID == ownerID,
              ConversationHistory.shared.epoch == epoch else { throw CancellationError() }
        return token
    }

    func signInWithGoogle() async throws {
        try await configuredClerk().auth.signInWithOAuth(provider: .google)
    }

    func signInWithApple() async throws {
        try await configuredClerk().auth.signInWithOAuth(provider: .apple)
    }

    func sendEmailCode(to email: String) async throws -> SignIn {
        try await configuredClerk().auth.signInWithEmailCode(emailAddress: email)
    }

    func verifyEmailCode(_ code: String, signIn: SignIn) async throws {
        try await signIn.verifyCode(code)
    }

    func signOut() async {
        try? await clerk?.auth.signOut()
    }

    @discardableResult
    func deleteAccount() async -> Bool {
        do {
            guard let token = try await bearerToken() else { return false }
            let userID = clerk?.user?.id
            var request = URLRequest(url: AppConfig.baseURL.appending(path: "api/account"))
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            if let userID { try SavedPagesStore.shared.erase(ownerID: userID) }
            try await clerk?.user?.delete()
            if let userID { UserInferenceCredentials.remove(userID: userID) }
            return true
        } catch {
            return false
        }
    }
}
