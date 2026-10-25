import EventKit
import SwiftUI

struct CalendarConnectView: View {
    var onSignIn: () -> Void
    var onDone: () -> Void

    @Environment(AuthStore.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var titleSize = 28
    @State private var connectors = ConnectedAppsStore()
    @State private var checkedConnectors = false
    @State private var awaitingGoogle = false
    @State private var appleStatus = EKEventStore.authorizationStatus(for: .event)
    @State private var requestingApple = false
    @State private var departing = false
    @State private var backdropGone = false

    private var canUseConnectors: Bool {
        return auth.isSignedIn
    }

    private var googleApp: ConnectedAppsStore.App? {
        connectors.apps.first { $0.slug == "googlecalendar" }
    }

    private var googleConnected: Bool { googleApp?.isConnected == true }
    private var appleConnected: Bool { appleStatus == .fullAccess }
    private var anyConnected: Bool { googleConnected || appleConnected }

    var body: some View {
        ZStack {
            OnboardingBackdrop().ignoresSafeArea().allowsHitTesting(false)
                .opacity(backdropGone ? 0 : 1)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(anyConnected ? "Done" : "Not now") { finish() }
                        .font(.system(size: 17))
                        .foregroundStyle(anyConnected ? Theme.ink : Theme.inkSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .contentTransition(.opacity)
                        .accessibilityIdentifier("onboarding-skip")
                        .opacity(departing ? 0 : 1)
                }
                .padding(.horizontal, 24)
                .offset(y: -12)

                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Image("Hugeicons/Calendar03")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundStyle(Theme.ink)
                        .frame(width: 84, height: 84)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .padding(.bottom, 28)
                        .accessibilityHidden(true)
                    Text("Connect your calendar")
                        .font(.system(size: titleSize, weight: .medium))
                        .tracking(-0.4)
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("onboarding-title")
                        .padding(.bottom, 10)
                    Text("\(AppInfo.name) plans around the day you already have.")
                        .font(Theme.body())
                        .foregroundStyle(Theme.inkSecondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .opacity(departing ? 0 : 1)

                Spacer(minLength: 24)

                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        CalendarConnectorCard(
                            title: "Google Calendar",
                            detail: googleDetail,
                            state: googleState,
                            logo: { ConnectorLogo(slug: "googlecalendar", size: 34) },
                            action: connectGoogle)
                        .accessibilityIdentifier("connect-google-calendar")
                        CalendarConnectorCard(
                            title: "Apple Calendar",
                            detail: appleDetail,
                            state: appleState,
                            logo: { ConnectorLogo(slug: "applecalendar", size: 34) },
                            action: connectApple)
                        .accessibilityIdentifier("connect-apple-calendar")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .opacity(departing ? 0 : 1)
                .disabled(departing)
            }
        }
        .task {
            guard canUseConnectors else { return }
            await connectors.refresh()
            checkedConnectors = true
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            appleStatus = EKEventStore.authorizationStatus(for: .event)
            guard awaitingGoogle else { return }
            Task {
                await connectors.refresh(force: true)
                if googleConnected { awaitingGoogle = false }
            }
        }
        .animation(.smooth(duration: 0.3), value: googleConnected)
        .animation(.smooth(duration: 0.3), value: appleStatus)
    }

    private var googleState: CalendarConnectorCard<ConnectorLogo>.State {
        if googleConnected { return .connected }
        if connectors.busySlug == "googlecalendar" || googleApp?.status == "authorizing" { return .busy }
        if canUseConnectors, checkedConnectors, !connectors.enabled { return .unavailable }
        return canUseConnectors ? .connect : .signIn
    }

    private var googleDetail: String {
        switch googleState {
        case .connected:
            googleApp?.visibleAccounts.first { $0.isConnected && $0.label != "Account 1" }?.label
                ?? "Events from your Google account"
        case .signIn: "Sign in with Google to connect"
        case .unavailable: "Unavailable right now"
        default: "Events from your Google account"
        }
    }

    private var appleState: CalendarConnectorCard<ConnectorLogo>.State {
        if appleConnected { return .connected }
        if requestingApple { return .busy }
        if appleStatus == .denied || appleStatus == .restricted { return .settings }
        return .connect
    }

    private var appleDetail: String {
        switch appleState {
        case .settings: "Allow access in Settings"
        default: "Calendars on this iPhone"
        }
    }

    private func connectGoogle() {
        switch googleState {
        case .signIn: onSignIn()
        case .connect:
            awaitingGoogle = true
            Task { await connectors.connect("googlecalendar") }
        default: break
        }
    }

    private func connectApple() {
        switch appleState {
        case .connect:
            requestingApple = true
            Task {
                _ = try? await EKEventStore().requestFullAccessToEvents()
                appleStatus = EKEventStore.authorizationStatus(for: .event)
                requestingApple = false
            }
        case .settings:
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        default: break
        }
    }

    private func finish() {
        guard !departing, !auth.revealingHome else { return }
        guard !reduceMotion else {
            onDone()
            return
        }
        auth.revealHome()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.2)) { departing = true }
            withAnimation(.easeInOut(duration: 0.35).delay(0.12)) { backdropGone = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onDone() }
        }
    }
}

struct CalendarConnectorCard<Logo: View>: View {
    enum State { case connect, busy, connected, signIn, settings, unavailable }

    let title: String
    let detail: String
    let state: State
    @ViewBuilder var logo: Logo
    var action: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                logo
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: shape)
        .disabled(state == .busy || state == .unavailable)
        .accessibilityElement(children: .combine)
        .accessibilityValue(state == .connected ? "Connected" : "")
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .busy:
            ProgressView()
        case .connected:
            HStack(spacing: 5) {
                Image("Hugeicons/Tick02")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 16, height: 16)
                Text("Connected")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(Theme.positive)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        case .unavailable:
            EmptyView()
        case .connect, .signIn, .settings:
            Text(state == .settings ? "Open" : "Connect")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Theme.ink.opacity(0.07), in: Capsule())
        }
    }
}

struct OnboardingPrimaryButton: View {
    let title: String
    var isBusy = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView().tint(Theme.onAccent)
                } else {
                    Text(title)
                }
            }
            .font(Theme.button())
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 55)
            .background(Theme.dockSurface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }
}
