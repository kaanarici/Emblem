import SwiftUI
import EmblemCore

struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    var onBack: () -> Void = {}
    var showsMenu = false
    var onSubpagePushed: (Bool) -> Void = { _ in }
    var onOpenAutomation: (String) -> Void = { _ in }
    var onOpenConversation: (String) -> Void = { _ in }
    var onSignIn: () -> Void = {}

    @State private var voice = VoiceOutput.shared
    @State private var connectedApps = ConnectedAppsStore()
    @State private var agents = AgentsStore()
    @AppStorage("memory.enabled") private var memoryEnabled = true
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @AppStorage(Accent.storageKey) private var accent = Accent.aluminum
    @AppStorage(ListeningStyle.storageKey) private var listening = ListeningStyle.wave
    @AppStorage("apple.model") private var appleModel = ""
    @State private var serverModel = UserInferenceCredentials.Choice.emblem
    @State private var showConnectors = false
    @State private var showMemory = false
    @State private var showScheduled = false
    @State private var confirmDeleteAccount = false
    @State private var deleteAccountFailed = false
    @State private var legalDoc: LegalDoc?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                identity
                    .padding(.top, 34)

                SettingsSectionLabel(title: "Appearance")
                    .padding(.top, 46)
                SettingsCard {
                    SettingsPickerRow(title: "Theme", options: Appearance.allCases, selection: $appearance,
                                      name: \.title)
                    SettingsHairline()
                    SettingsPickerRow(title: "Accent color", options: Accent.allCases, selection: $accent,
                                      name: \.title, swatch: \.swatch)
                    SettingsHairline()
                    SettingsPickerRow(title: "Listening style", options: ListeningStyle.allCases, selection: $listening,
                                      name: \.title)
                }

                SettingsSectionLabel(title: "Chats")
                    .padding(.top, SettingsMetrics.sectionGap)
                SettingsCard {
                    navigationRow("Chat history") { ChatHistoryView(onOpen: onOpenConversation) }
                    SettingsHairline()
                    row("Memory", value: auth.isSignedIn ? (memoryEnabled ? "On" : "Off") : nil) { showMemory = true }
                    if agentOwnerVisible {
                        SettingsHairline()
                        row("Scheduled pages") { showScheduled = true }
                    }
                }

                SettingsSectionLabel(title: "Assistant")
                    .padding(.top, SettingsMetrics.sectionGap)
                SettingsCard {
                    if let userID = inferenceOwnerID {
                        navigationRow("Model", value: modelValue) { InferenceSettingsView(userID: userID) }
                        SettingsHairline()
                    }
                    navigationRow("Runs on", value: runsOnValue) { AppleModelSettingsView() }
                    SettingsHairline()
                    SettingsToggleRow(title: "Spoken replies", isOn: spokenBinding)
                }

                SettingsSectionLabel(title: "Connections")
                    .padding(.top, SettingsMetrics.sectionGap)
                SettingsCard {
                    if connectorOwnerVisible {
                        row("Connectors") { showConnectors = true }
                        SettingsHairline()
                    }
                    row("Location", trailing: .outbound) {
                        open(UIApplication.openSettingsURLString)
                    }
                    SettingsHairline()
                    row("Notifications", trailing: .outbound) {
                        open(UIApplication.openNotificationSettingsURLString)
                    }
                }

                SettingsSectionLabel(title: "About")
                    .padding(.top, SettingsMetrics.sectionGap)
                SettingsCard {
                    row("Privacy policy") { legalDoc = .privacy }
                    SettingsHairline()
                    row("Terms of service") { legalDoc = .terms }
                }

                account
                    .padding(.top, SettingsMetrics.sectionGap)

                Text("Version \(version)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 30)
                    .padding(.bottom, 60)
            }
            .padding(.horizontal, Theme.pageMargin)
        }
        .background(Theme.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .navigationDestination(isPresented: $showConnectors) {
            ConnectorsView(connectedApps: connectedApps)
        }
        .navigationDestination(isPresented: $showMemory) {
            MemorySettingsView()
        }
        .navigationDestination(isPresented: $showScheduled) {
            ScheduledPagesView(agents: agents, memoryEnabled: memoryEnabled,
                               onOpenResult: onOpenAutomation)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationCircleButton(action: onBack) {
                    if showsMenu {
                        ChromeGlyph(symbol: .menu)
                    } else {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Theme.ink)
                    }
                }
                .accessibilityLabel(showsMenu ? "Open menu" : "Back")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .task {
            if connectorOwnerVisible {
                Task { await connectedApps.refresh() }
            }
            if agentOwnerVisible {
                await agents.refresh()
                await agents.reconcileDailyBrief(memory: memoryEnabled)
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            if connectorOwnerVisible {
                Task { await connectedApps.refresh(force: true) }
            }
        }
        .onChange(of: memoryEnabled) { _, enabled in
            guard agents.hasLoaded else { return }
            Task { await agents.reconcileDailyBrief(memory: enabled) }
        }
        .onAppear {
            onSubpagePushed(false)
            if let userID = inferenceOwnerID { serverModel = UserInferenceCredentials.choice(userID: userID) }
        }
        .onDisappear { onSubpagePushed(true) }
        .sheet(item: $legalDoc) { doc in
            LegalSheet(doc: doc)
        }
        .alert("Delete account?", isPresented: $confirmDeleteAccount) {
            Button("Delete", role: .destructive) {
                Task {
                    if await auth.deleteAccount() {
                        onBack()
                    } else {
                        deleteAccountFailed = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This erases your conversations, memories, profile and scheduled pages from your server, disconnects your apps and deletes your sign-in. It can't be undone.")
        }
        .alert("Couldn't delete account", isPresented: $deleteAccountFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your account is still intact. Check your connection and try again.")
        }
    }

    private var identity: some View {
        VStack(spacing: 0) {
            avatar
            Text(auth.displayName ?? (auth.isSignedIn ? (auth.email ?? "Signed in") : "Guest"))
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 22)
            if auth.isSignedIn, auth.displayName != nil, let email = auth.email {
                Text(email)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var avatar: some View {
        AsyncImage(url: auth.avatarURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Text(initial)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.white)
        }
        .frame(width: 76, height: 76)
        .background(Color(red: 0.43, green: 0.54, blue: 0.60))
        .clipShape(Circle())
    }

    private var initial: String {
        let name = auth.displayName ?? auth.email ?? "Guest"
        return String(name.prefix(1)).uppercased()
    }

    private var inferenceOwnerID: String? {
        return auth.user?.id
    }

    private var connectorOwnerVisible: Bool {
        return auth.isSignedIn
    }

    private var agentOwnerVisible: Bool { auth.isSignedIn }

    private var spokenBinding: Binding<Bool> {
        Binding(get: { !voice.muted }, set: { voice.muted = !$0 })
    }

    private var runsOn: OnDeviceModel.Selection {
        OnDeviceModel.Selection(rawValue: appleModel) ?? .emblem
    }

    private var runsOnValue: String {
        switch runsOn {
        case .emblem: AppInfo.name
        case .onDevice: "This iPhone"
        case .privateCloud: "Private Cloud"
        }
    }

    private var modelValue: String? {
        guard runsOn == .emblem else { return nil }
        if serverModel == .custom { return "Your key" }
        return serverModel.model?.name ?? AppInfo.name
    }

    private func row(
        _ title: String,
        value: String? = nil,
        trailing: SettingsRowLabel.Trailing = .chevron,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SettingsRowLabel(title: title, value: value, trailing: trailing)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(title)
        .accessibilityHint(trailing == .outbound ? "Opens the Settings app" : "")
    }

    private func navigationRow(
        _ title: String, value: String? = nil, destination: @escaping () -> some View
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            SettingsRowLabel(title: title, value: value)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(title)
    }

    @ViewBuilder
    private var account: some View {
        if auth.isSignedIn {
            SettingsCard {
                SettingsDestructiveRow(title: "Log out") {
                    Task {
                        await auth.signOut()
                        onBack()
                    }
                }
                SettingsHairline()
                SettingsDestructiveRow(title: "Delete account") { confirmDeleteAccount = true }
            }
        } else {
            Button(action: onSignIn) {
                Text("Sign in")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.surface, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
        }
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
