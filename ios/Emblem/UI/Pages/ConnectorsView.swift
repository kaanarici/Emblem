import SwiftUI

struct ConnectorsView: View {
    let connectedApps: ConnectedAppsStore

    @State private var hookDetailSlug: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ConnectorSectionHeader(
                    title: "On this iPhone",
                    subtitle: "Used on your iPhone, only when you ask.")
                OnThisIPhoneSection()

                ConnectorSectionHeader(
                    title: "Connected apps",
                    subtitle: "Accounts \(AppInfo.name) can read for you.")
                    .padding(.top, SettingsMetrics.sectionGap)
                ConnectorCard {
                    ForEach(Array(appRows.enumerated()), id: \.element.slug) { index, app in
                        if index > 0 { SettingsHairline(pastIcon: true) }
                        appRow(app)
                    }
                }
                if unavailable || connectedApps.errorMessage != nil {
                    HStack(spacing: 12) {
                        Text(unavailable ? "Couldn't load your connected apps" : connectedApps.errorMessage ?? "")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ConnectorPill(title: "Retry", style: .secondary) {
                            Task { await connectedApps.refresh(force: true) }
                        }
                        .opacity(connectedApps.isRefreshing ? 0.5 : 1)
                        .disabled(connectedApps.isRefreshing)
                        .accessibilityIdentifier("connectors-retry")
                    }
                    .padding(.top, 14)
                    .padding(.horizontal, SettingsMetrics.rowInset)
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, 34)
            .padding(.bottom, 60)
        }
        .background(Theme.background)
        .navigationTitle("Connectors")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(
            get: { hookDetailSlug != nil },
            set: { if !$0 { hookDetailSlug = nil } })
        ) {
            ConnectorDetailView(connectedApps: connectedApps, slug: hookDetailSlug ?? "")
        }
        .task {
            if connectedApps.apps.isEmpty {
                await connectedApps.refresh()
            }
        }
    }

    private var appRows: [ConnectedAppsStore.App] {
        connectedApps.apps.isEmpty ? ConnectedAppsStore.App.known : connectedApps.apps
    }

    private var unavailable: Bool {
        connectedApps.loadFailed || !connectedApps.enabled
            || connectedApps.apps.contains { $0.diagnosticCode == "connector_service_auth" }
    }

    @ViewBuilder
    private func appRow(_ app: ConnectedAppsStore.App) -> some View {
        let busy = connectedApps.busySlug == app.slug || app.status == "authorizing"
        if app.isConnected || !app.visibleAccounts.isEmpty {
            NavigationLink {
                ConnectorDetailView(connectedApps: connectedApps, slug: app.slug)
            } label: {
                ConnectorRowLayout(title: app.title, subtitle: connectorSummary(app),
                                   attention: app.status == "needs_attention") {
                    ConnectorLogo(slug: app.slug, size: ConnectorRowMetrics.icon)
                } trailing: {
                    HStack(spacing: 8) {
                        if busy {
                            ProgressView()
                        } else if app.isConnected {
                            Text("Connected")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        ConnectorChevron()
                    }
                    .fixedSize()
                }
            }
            .buttonStyle(.plain)
        } else {
            ConnectorRowLayout(title: app.title, subtitle: connectorBlurb(app.slug)) {
                ConnectorLogo(slug: app.slug, size: ConnectorRowMetrics.icon)
            } trailing: {
                if busy {
                    ProgressView()
                } else {
                    ConnectorPill(title: "Connect", style: .primary) {
                        Task { await connectedApps.connect(app.slug) }
                    }
                    .disabled(unavailable)
                    .opacity(unavailable ? 0.35 : 1)
                    .accessibilityLabel("Connect \(app.title)")
                    .accessibilityIdentifier("connect-\(app.slug)")
                }
            }
        }
    }
}

func connectorStatusText(_ status: String) -> String {
    switch status {
    case "connected": "Connected"
    case "authorizing": "Waiting for approval"
    case "checking": "Checking access"
    case "needs_attention": "Needs attention"
    case "unavailable": "Unavailable right now"
    default: "Not connected"
    }
}

private func connectorSummary(_ app: ConnectedAppsStore.App) -> String {
    let connected = app.visibleAccounts.filter(\.isConnected)
    if app.status == "needs_attention" { return "Reconnect to keep using it" }
    if app.isConnected, connected.count > 1 { return "\(connected.count) accounts" }
    if app.isConnected, let only = connected.first, only.label != "Account 1" { return only.label }
    return connectorBlurb(app.slug)
}

struct ConnectorLogo: View {
    let slug: String
    var size: CGFloat = 32

    var body: some View {
        Group {
            if UIImage(named: "connector-\(slug)") != nil {
                Image("connector-\(slug)")
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(Theme.chip)
            }
        }
        .frame(width: size, height: size)
    }
}

enum ConnectorRowMetrics {
    static let icon: CGFloat = 30
    static let spacing: CGFloat = 12
}

struct ConnectorSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            if let subtitle {
                Text(subtitle)
                    .font(SettingsMetrics.subtitleFont)
            }
        }
        .foregroundStyle(Theme.inkSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.bottom, 10)
    }
}

struct ConnectorCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        SettingsCard { content }
    }
}

struct ConnectorRowLayout<Icon: View, Trailing: View>: View {
    let title: String
    let subtitle: String
    var attention = false
    @ViewBuilder let icon: Icon
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: ConnectorRowMetrics.spacing) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SettingsMetrics.titleFont)
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(SettingsMetrics.subtitleFont)
                    .foregroundStyle(attention ? Theme.negative : Theme.inkSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            trailing
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 11)
        .frame(minHeight: SettingsMetrics.rowHeight)
        .contentShape(Rectangle())
    }
}

struct ConnectorPill: View {
    enum Style { case primary, secondary }
    let title: String
    var style: Style = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(style == .primary ? Theme.dockContent : Theme.ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(style == .primary ? Theme.dockSurface : Theme.chip, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }
}

struct ConnectorChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.ink)
    }
}

private struct ConnectorGlyph: View {
    let name: String
    var size: CGFloat = 22
    var color = Theme.ink

    var body: some View {
        Image("Hugeicons/\(name)")
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .frame(width: size, height: size)
            .foregroundStyle(color)
    }
}

struct ConnectorDetailView: View {
    let connectedApps: ConnectedAppsStore
    let slug: String

    @State private var pendingDisconnect: ConnectedAppsStore.Account?

    private var app: ConnectedAppsStore.App? {
        connectedApps.apps.first { $0.slug == slug }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let app {
                    header(app)
                    ConnectorSectionHeader(title: "Accounts")
                        .padding(.top, 30)
                    accountsCard(app)
                    if let error = connectedApps.errorMessage
                        ?? (app.diagnosticCode == "connector_service_auth" ? "Couldn't load your connected apps" : nil) {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 14)
                            .padding(.horizontal, SettingsMetrics.rowInset)
                    }
                    ConnectorSectionHeader(title: "What \(AppInfo.name) reads", subtitle: connectorAccessNote(app.slug))
                        .padding(.top, 30)
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, 22)
            .padding(.bottom, 48)
        }
        .background(Theme.background)
        .navigationTitle(app?.title ?? "Connector")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Disconnect \(pendingDisconnect?.label ?? "this account")?",
            isPresented: Binding(
                get: { pendingDisconnect != nil },
                set: { if !$0 { pendingDisconnect = nil } }),
            presenting: pendingDisconnect
        ) { account in
            Button("Disconnect", role: .destructive) {
                Task { await connectedApps.disconnect(slug, account: account.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("\(AppInfo.name) loses read access to this account until you connect it again.")
        }
    }

    private func header(_ app: ConnectedAppsStore.App) -> some View {
        HStack(spacing: 16) {
            ConnectorLogo(slug: app.slug, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(connectorBlurb(app.slug))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
    }

    private func accountsCard(_ app: ConnectedAppsStore.App) -> some View {
        let busy = connectedApps.busySlug == app.slug || app.status == "authorizing"
        let accounts = app.visibleAccounts
        let serviceDown = app.diagnosticCode == "connector_service_auth"
        return ConnectorCard {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 { SettingsHairline(pastIcon: true) }
                accountRow(account, busy: busy)
            }
            if !serviceDown {
                if !accounts.isEmpty { SettingsHairline(pastIcon: true) }
                Button {
                    Task {
                        if app.status == "unavailable" && app.canReconnect != true {
                            await connectedApps.refresh(force: true)
                        } else {
                            await connectedApps.connect(app.slug, another: app.isConnected)
                        }
                    }
                } label: {
                    HStack(spacing: ConnectorRowMetrics.spacing) {
                        ConnectorGlyph(name: "Add01")
                            .frame(width: ConnectorRowMetrics.icon, height: ConnectorRowMetrics.icon)
                        Text(addTitle(app))
                            .font(SettingsMetrics.titleFont)
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 12)
                        if busy { ProgressView() }
                    }
                    .padding(.horizontal, SettingsMetrics.rowInset)
                    .frame(minHeight: SettingsMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
            } else if accounts.isEmpty {
                Text("No accounts connected.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SettingsMetrics.rowInset)
                    .frame(minHeight: SettingsMetrics.rowHeight)
            }
        }
    }

    private func accountRow(_ account: ConnectedAppsStore.Account, busy: Bool) -> some View {
        HStack(spacing: ConnectorRowMetrics.spacing) {
            ConnectorGlyph(name: "UserCircle")
                .frame(width: ConnectorRowMetrics.icon, height: ConnectorRowMetrics.icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.label)
                    .font(SettingsMetrics.titleFont)
                    .foregroundStyle(Theme.ink)
                Text(accountSubtitle(account))
                    .font(.system(size: 13))
                    .foregroundStyle(account.isConnected ? Theme.inkSecondary : Theme.negative)
            }
            Spacer(minLength: 12)
            ConnectorPill(title: "Disconnect", style: .secondary) { pendingDisconnect = account }
                .disabled(busy)
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 11)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }

    private func accountSubtitle(_ account: ConnectedAppsStore.Account) -> String {
        let status = connectorStatusText(account.status)
        guard let added = account.addedAt.flatMap(Self.parseDate) else { return status }
        return "\(status) · Added \(added.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func addTitle(_ app: ConnectedAppsStore.App) -> String {
        if app.isConnected { return "Add another account" }
        if app.status == "needs_attention" { return "Reconnect" }
        if app.status == "unavailable" { return "Check again" }
        return "Connect an account"
    }
}

func connectorBlurb(_ slug: String) -> String {
    switch slug {
    case "gmail": "Ask about your email"
    case "googlecalendar": "Plan around your schedule"
    default: "Give \(AppInfo.name) read access to your account."
    }
}

private func connectorAccessNote(_ slug: String) -> String {
    switch slug {
    case "gmail": "Recent messages, only when you ask. It never sends mail."
    case "googlecalendar": "Upcoming events. It adds one only when you tap."
    default: "Only what a request needs."
    }
}
