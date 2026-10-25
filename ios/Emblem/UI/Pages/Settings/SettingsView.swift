import SwiftUI
import EmblemCore

struct SettingsView: View {
    @Environment(AuthStore.self) private var auth
    var onBack: () -> Void = {}
    var showsMenu = false
    var onSubpagePushed: (Bool) -> Void = { _ in }
    var onOpenAutomation: (String) -> Void = { _ in }
    var onSignIn: () -> Void = {}

    @State private var voice = VoiceOutput.shared
    @State private var connectedApps = ConnectedAppsStore()
    @State private var agents = AgentsStore()
    @AppStorage("memory.enabled") private var memoryEnabled = true
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system
    @AppStorage(Accent.storageKey) private var accent = Accent.aluminum
    @State private var showConnectors = false
    @State private var showMemory = false
    @State private var showInference = false
    @State private var showScheduled = false
    @State private var showPrivacy = false
    @State private var legalDoc: LegalDoc?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                identity
                    .padding(.top, 34)

                SettingsSectionLabel(title: "Theme")
                    .padding(.top, 46)
                SettingsCard {
                    SettingsMenuRow(title: "Appearance") {
                        Picker("Appearance", selection: $appearance) {
                            ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                        }
                    } value: {
                        Text(appearance.title)
                    }
                    SettingsHairline()
                    SettingsMenuRow(title: "Accent color") {
                        Picker("Accent color", selection: $accent) {
                            ForEach(Accent.allCases) { accent in
                                Label {
                                    Text(accent.title)
                                } icon: {
                                    Image(uiImage: accent.swatch)
                                }
                                .tag(accent)
                            }
                        }
                    } value: {
                        AnodizedSurface(shape: Circle())
                            .frame(width: 14, height: 14)
                        Text(accent.title)
                    }
                }

                SettingsSectionLabel(title: "Personalization")
                    .padding(.top, SettingsMetrics.sectionGap)
                SettingsCard {
                    row("Memory", value: auth.isSignedIn ? (memoryEnabled ? "On" : "Off") : nil) { showMemory = true }
                    if agentOwnerVisible {
                        SettingsHairline()
                        row("Scheduled pages") { showScheduled = true }
                    }
                }

                SettingsSectionLabel(title: "Voice")
                    .padding(.top, SettingsMetrics.sectionGap)
                SettingsCard {
                    SettingsToggleRow(title: "Mute \(AppInfo.name) voice", isOn: muteBinding)
                }

                SettingsSectionLabel(title: "Connections")
                    .padding(.top, SettingsMetrics.sectionGap)
                SettingsCard {
                    if connectorOwnerVisible {
                        row("Connectors") { showConnectors = true }
                        SettingsHairline()
                    }
                    row("Location settings", trailing: .outbound) {
                        open(UIApplication.openSettingsURLString)
                    }
                    SettingsHairline()
                    row("Notification settings", trailing: .outbound) {
                        open(UIApplication.openNotificationSettingsURLString)
                    }
                }

                SettingsSectionLabel(title: "Models")
                    .padding(.top, SettingsMetrics.sectionGap)
                SettingsCard {
                    navigationRow("Apple Intelligence") { AppleModelSettingsView() }
                    if let userID = inferenceOwnerID {
                        SettingsHairline()
                        navigationRow("AI provider") { InferenceSettingsView(userID: userID) }
                    }
                }

                SettingsSectionLabel(title: "Privacy")
                    .padding(.top, SettingsMetrics.sectionGap)
                SettingsCard {
                    row("Data & Privacy") { showPrivacy = true }
                }

                SettingsSectionLabel(title: "About")
                    .padding(.top, SettingsMetrics.sectionGap)
                SettingsCard {
                    row("Privacy policy") { legalDoc = .privacy }
                    SettingsHairline()
                    row("Terms of service") { legalDoc = .terms }
                }

                accountButton
                    .padding(.top, 36)

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
        .navigationDestination(isPresented: $showInference) {
            InferenceSettingsView(userID: inferenceOwnerID ?? "")
        }
        .navigationDestination(isPresented: $showScheduled) {
            ScheduledPagesView(agents: agents, memoryEnabled: memoryEnabled,
                               onOpenResult: onOpenAutomation)
        }
        .navigationDestination(isPresented: $showPrivacy) {
            DataPrivacyView(onAccountDeleted: onBack)
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
        .onAppear { onSubpagePushed(false) }
        .onDisappear { onSubpagePushed(true) }
        .sheet(item: $legalDoc) { doc in
            LegalSheet(doc: doc)
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

    private var muteBinding: Binding<Bool> {
        Binding(get: { voice.muted }, set: { voice.muted = $0 })
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

    private func navigationRow(_ title: String, destination: @escaping () -> some View) -> some View {
        NavigationLink {
            destination()
        } label: {
            SettingsRowLabel(title: title)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(title)
    }

    @ViewBuilder
    private var accountButton: some View {
        if auth.isSignedIn {
            capsuleButton("Log out") {
                Task {
                    await auth.signOut()
                    onBack()
                }
            }
        } else {
            capsuleButton("Sign in") { onSignIn() }
        }
    }

    private func capsuleButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.surface, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
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
