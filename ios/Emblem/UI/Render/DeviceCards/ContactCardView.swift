import ContactsUI
import MessageUI
import SwiftUI
import EmblemCore

struct ContactCardView: View {
    let block: ContactBlock
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var matches: [ContactsService.Match] = []
    @State private var loaded = false
    @State private var composing = false
    private let access = DeviceAccess.shared

    var body: some View {
        let state = access.state(.contacts)
        let canRead = access.canUse(.contacts)
        VStack(alignment: .leading, spacing: 12) {
            DeviceCardTitle(kind: .contacts, title: "Contact")
            if !canRead {
                DeviceCardPermission(kind: .contacts)
            } else if let match = matches.first {
                card(match)
            } else if loaded {
                VStack(alignment: .leading, spacing: 10) {
                    DeviceCardMessage(text: "No contact named \(block.name) on this iPhone.")
                    if state == .limited {
                        ContactAccessButton(queryString: block.name) { _ in
                            Task { await load(true) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .task(id: canRead) { await load(canRead) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { access.refresh() }
        }
        .sheet(isPresented: $composing) {
            if let phone = matches.first?.phones.first?.value {
                MessageComposer(recipient: phone, body: block.draft ?? "")
                    .ignoresSafeArea()
            }
        }
    }

    private func load(_ canRead: Bool) async {
        guard canRead else { return }
        matches = await ContactsService.lookup(block.name)
        loaded = true
    }

    private func card(_ match: ContactsService.Match) -> some View {
        let phone = match.phones.first
        let email = match.emails.first
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ContactAvatar(name: match.name, data: match.thumbnail)
                VStack(alignment: .leading, spacing: 3) {
                    Text(match.name)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if let line = phone ?? email {
                        Text("\(line.label.isEmpty ? "" : line.label + " · ")\(line.value)")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            if let draft = block.draft, !draft.isEmpty {
                Text(draft)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Message draft: \(draft)")
            }
            HStack(spacing: 8) {
                action("Call", symbol: "phone.fill", enabled: phone != nil) {
                    if let phone, let url = URL(string: "tel:\(Self.digits(phone.value))") { openURL(url) }
                }
                action("Message", symbol: "message.fill", enabled: phone != nil) {
                    if MFMessageComposeViewController.canSendText() {
                        composing = true
                    } else if let phone, let url = URL(string: "sms:\(Self.digits(phone.value))") {
                        openURL(url)
                    }
                }
                action("Email", symbol: "envelope.fill", enabled: email != nil) {
                    if let email, let url = URL(string: "mailto:\(email.value)") { openURL(url) }
                }
            }
        }
        .padding(16)
        .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .groupedRowShadow()
    }

    private func action(_ title: String, symbol: String, enabled: Bool, perform: @escaping () -> Void) -> some View {
        Button {
            guard blockInteraction.allowsActivation else { return }
            perform()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 17))
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.rowButtonStroke, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .blockActivationControl()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityIdentifier("contact-\(title.lowercased())")
    }

    private static func digits(_ phone: String) -> String {
        phone.filter { $0.isNumber || $0 == "+" }
    }
}

private struct ContactAvatar: View {
    let name: String
    let data: Data?

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(
                colors: [Color(white: 0.72), Color(white: 0.56)], startPoint: .top, endPoint: .bottom))
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

private struct MessageComposer: UIViewControllerRepresentable {
    let recipient: String
    let body: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = [recipient]
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject, @MainActor MFMessageComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult
        ) {
            dismiss()
        }
    }
}
