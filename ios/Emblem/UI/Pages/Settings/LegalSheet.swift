import SwiftUI
import EmblemCore

enum LegalDoc: String, Identifiable {
    case privacy, terms
    var id: String { rawValue }
}

struct LegalSheet: View {
    let doc: LegalDoc

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(doc == .privacy ? "Privacy Policy" : "Terms of Service")
                    .font(Theme.sectionTitle())
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 40)

                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    if let heading = section.heading {
                        Text(heading)
                            .font(Theme.cardTitle())
                            .foregroundStyle(Theme.ink)
                            .padding(.top, 28)
                    }
                    Text(section.body)
                        .font(Theme.bodySecondary())
                        .foregroundStyle(Theme.inkSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, section.heading == nil ? 16 : 8)
                }
            }
            .padding(.horizontal, Theme.contentMargin)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.surface)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }

    private var sections: [(heading: String?, body: String)] {
        (doc == .privacy ? Self.privacy : Self.terms) + [Self.questions]
    }

    private static let questions: (heading: String?, body: String) = (
        "Questions",
        "Open an issue on the project's GitHub repository."
    )

    private static let terms: [(heading: String?, body: String)] = [
        (nil, """
        \(AppInfo.name) is open-source software under the GNU Affero General Public License, version 3. This page summarizes what that means for you; the license itself is the LICENSE file in the source.
        """),
        ("No warranty", """
        \(AppInfo.name) is provided as is, without warranty of any kind. Its answers are written by AI models and can be wrong, so check anything that matters before you rely on it.
        """),
        ("Your own server", """
        There is no \(AppInfo.name) company or hosted service. Whoever builds the app runs their own server and chooses the model and search providers it uses. Your requests go to that server and those providers, and their terms apply to what you send them.
        """),
        ("Your data", """
        What is stored, and how deleting your account removes it, is in the Privacy Policy.
        """),
    ]

    private static let privacy: [(heading: String?, body: String)] = [
        (nil, """
        \(AppInfo.name) is open-source software with no company behind it. Whoever builds the app runs its server, and your data goes only where that build sends it.
        """),
        ("Where requests go", """
        Your messages, attachments, and any location or calendar context you allow go to the server this app was built for. That server passes them to the model, search and image providers it is set up with, and their own terms and privacy policies apply. Speech is transcribed on this iPhone. Apple models run on device, or on Apple's Private Cloud Compute if you choose it.
        """),
        ("What is stored", """
        When you sign in, the server keeps your conversations and pages, saved memories, your profile and custom instructions, scheduled pages, and illustrations made for you. This iPhone keeps your saved pages and settings, and your own AI provider key in the Keychain if you add one.
        """),
        ("Deleting your account", """
        Settings › Data & Privacy › Delete account erases all of that from the server, disconnects your connected apps, deletes your sign-in account, and removes saved pages and your provider key from this iPhone. The server keeps only a one-way hash of your account ID, so nothing new can be saved under it. Copies a provider already received follow that provider's policy.
        """),
    ]
}
