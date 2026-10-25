import ContactsUI
import SwiftUI

extension DeviceAccess.Kind {
    var title: String {
        switch self {
        case .location: "Location"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .contacts: "Contacts"
        case .home: "Home"
        case .music: "Apple Music"
        }
    }

    var purpose: String {
        switch self {
        case .location: "Find places near you"
        case .calendar: "See your day and add events"
        case .reminders: "Check and add reminders"
        case .contacts: "Call, text or email people"
        case .home: "Lights and scenes"
        case .music: "Play full songs"
        }
    }
}

struct OnThisIPhoneSection: View {
    @Environment(\.scenePhase) private var scenePhase
    private let access = DeviceAccess.shared

    var body: some View {
        ConnectorCard {
            ForEach(Array(DeviceAccess.Kind.available.enumerated()), id: \.element) { index, kind in
                if index > 0 { SettingsHairline(pastIcon: true) }
                DevicePermissionRow(kind: kind)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { access.refresh() }
        }
    }
}

struct DevicePermissionRow: View {
    let kind: DeviceAccess.Kind
    var iconSize: CGFloat = ConnectorRowMetrics.icon
    @State private var pickingContacts = false
    @Environment(\.scenePhase) private var scenePhase
    private let access = DeviceAccess.shared

    var body: some View {
        let state = access.state(kind)
        let opensSettings = state == .allowed || state == .limited || state == .denied
        Button {
            if opensSettings { access.openSettings() }
        } label: {
            ConnectorRowLayout(title: kind.title, subtitle: subtitle(state)) {
                DeviceAppIcon(kind: kind, size: iconSize)
            } trailing: {
                trailing(state)
            }
        }
        .buttonStyle(.plain)
        .disabled(access.requesting == kind)
        .contactAccessPicker(isPresented: $pickingContacts) { _ in access.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { access.refresh() }
        }
        .animation(.smooth(duration: 0.25), value: state)
        .accessibilityIdentifier("device-access-\(kind.rawValue)")
        .accessibilityHint(opensSettings ? "Opens Settings" : "")
    }

    private func subtitle(_ state: DeviceAccess.State) -> String {
        switch state {
        case .limited: "Some contacts"
        case .addOnly: kind == .reminders ? "Can only add reminders" : "Can only add events"
        case .denied: "Turned off in Settings"
        default: kind.purpose
        }
    }

    @ViewBuilder
    private func trailing(_ state: DeviceAccess.State) -> some View {
        switch state {
        case .allowed:
            Text("Allowed")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize()
                .accessibilityIdentifier("device-access-\(kind.rawValue)-allowed")
        case .limited:
            ConnectorPill(title: "Choose", style: .secondary) { pickingContacts = true }
                .accessibilityIdentifier("device-access-\(kind.rawValue)-choose")
        case .denied:
            Image("Hugeicons/SquareArrowUpRight")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("device-access-\(kind.rawValue)-settings")
        case .notAsked, .addOnly:
            ConnectorPill(title: "Allow", style: .primary) { Task { await access.request(kind) } }
                .opacity(access.requesting == kind ? 0.5 : 1)
                .accessibilityIdentifier("device-access-\(kind.rawValue)-allow")
        }
    }
}

struct DeviceAppIcon: View {
    let kind: DeviceAccess.Kind
    var size: CGFloat = 44

    var body: some View {
        Group {
            if kind == .location {
                let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                shape
                    .fill(LinearGradient(colors: [Color(red: 0.18, green: 0.61, blue: 1), Color(red: 0.04, green: 0.43, blue: 0.94)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Image(systemName: "location.fill")
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(.white))
            } else {
                ConnectorLogo(slug: "apple\(kind.rawValue)", size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
