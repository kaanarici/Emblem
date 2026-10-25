import Foundation

@Observable @MainActor
public final class MemoryStore {
    private let identityEpoch = ConversationHistory.shared.epoch

    public init() {}
    public struct Profile: Codable, Equatable {
        public var nickname: String?
        public var occupation: String?
        public var about: String?
        public var instructions: String?
        public var memoryEnabled: Bool?

        var isEmpty: Bool {
            [nickname, occupation, about, instructions]
                .compactMap { $0 }
                .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        public init(nickname: String? = nil, occupation: String? = nil, about: String? = nil, instructions: String? = nil, memoryEnabled: Bool? = nil) {
            self.nickname = nickname
            self.occupation = occupation
            self.about = about
            self.instructions = instructions
            self.memoryEnabled = memoryEnabled
        }
    }

    private struct StateResponse: Decodable {
        var memories: [String]
        var profile: Profile
    }

    private struct ProfileAction: Encodable {
        var action = "saveProfile"
        var profile: Profile
    }

    private struct TextAction: Encodable {
        var action: String
        var text: String
    }

    public private(set) var memories: [String] = []
    public private(set) var profile = Profile()
    public private(set) var hasLoaded = false
    public private(set) var isBusy = false
    public private(set) var errorMessage: String?

    public func refresh() async {
        do {
            let data = try await GenerateClient.fetchJSON(identityEpoch: identityEpoch, path: "api/memory", query: [])
            let state = try JSONDecoder().decode(StateResponse.self, from: data)
            memories = state.memories
            profile = state.profile
            hasLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = "Memory couldn't be loaded. Try again."
        }
    }

    public func saveProfile(_ draft: Profile) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try await GenerateClient.postJSON(identityEpoch: identityEpoch,
                path: "api/memory",
                body: ProfileAction(profile: draft))
            struct SaveResponse: Decodable { var profile: Profile }
            profile = try JSONDecoder().decode(SaveResponse.self, from: data).profile
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Your changes couldn't be saved. Try again."
            return false
        }
    }

    public func forget(_ text: String) async {
        let previous = memories
        memories.removeAll { $0 == text }
        do {
            _ = try await GenerateClient.postJSON(identityEpoch: identityEpoch,
                path: "api/memory",
                body: TextAction(action: "forget", text: text))
        } catch {
            memories = previous
            errorMessage = "The memory couldn't be removed. Try again."
        }
    }

    public func clearAll() async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            struct ClearAction: Encodable { var action = "clear" }
            _ = try await GenerateClient.postJSON(identityEpoch: identityEpoch, path: "api/memory", body: ClearAction())
            memories = []
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Memories couldn't be deleted. Try again."
            return false
        }
    }
}
