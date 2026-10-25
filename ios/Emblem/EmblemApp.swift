import ClerkKit
import SwiftUI
import EmblemCore

@main
struct EmblemApp: App {
    @State private var store = ConversationStore()
    @State private var speech = SpeechService()
    @State private var auth: AuthStore
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @AppStorage(Accent.storageKey) private var accent = Accent.aluminum

    init() {
        ObjectLibrary.warm()
        if let key = ClerkConfig.publishableKey { Clerk.configure(publishableKey: key) }
        let auth = AuthStore()
        _auth = State(initialValue: auth)
        GenerateClient.bearerTokenProvider = { try await auth.bearerToken() }
        GenerateClient.inferenceCredentialProvider = {
            guard let user = auth.user,
                  UserInferenceCredentials.choice(userID: user.id) == .custom else { return nil }
            return UserInferenceCredentials.load(userID: user.id)
        }
        GenerateClient.managedInferenceModelProvider = {
            UserInferenceCredentials.choice(userID: auth.user?.id ?? "guest").model
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if auth.gateCompleted || auth.revealingHome {
                    RootView()
                        .ignoresSafeArea(.container)
                }
                if !auth.gateCompleted {
                    AuthFlowView()
                }
            }
            .animation(.smooth(duration: 0.4), value: auth.gateCompleted)
            .environment(store)
            .environment(speech)
            .environment(auth)
            .environment(\.accent, accent)
            .onChange(of: appearance, initial: true) { _, appearance in
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    scene.windows.forEach { $0.overrideUserInterfaceStyle = appearance.interfaceStyle }
                }
            }
        }
    }
}
