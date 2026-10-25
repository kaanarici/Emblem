import SwiftUI
import EmblemCore

struct DataPrivacyView: View {
    @Environment(AuthStore.self) private var auth
    var onAccountDeleted: () -> Void

    @State private var confirmDelete = false
    @State private var deleteFailure = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SettingsCard {
                    NavigationLink {
                        ArchivedChatsView()
                    } label: {
                        SettingsRowLabel(title: "Archived chats")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("Archived chats")
                }
                if auth.isSignedIn {
                    SettingsCard {
                        SettingsDestructiveRow(title: "Delete account") { confirmDelete = true }
                    }
                    .padding(.top, SettingsMetrics.sectionGap)
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, 30)
            .padding(.bottom, 60)
        }
        .background(Theme.background)
        .navigationTitle("Data & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete account?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    if await auth.deleteAccount() {
                        onAccountDeleted()
                    } else {
                        deleteFailure = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This erases your conversations, memories, profile and scheduled pages from your server, disconnects your apps and deletes your sign-in. It can't be undone.")
        }
        .alert("Couldn't delete account", isPresented: $deleteFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your account is still intact. Check your connection and try again.")
        }
    }
}
