import SwiftUI
import EmblemCore

struct AppleModelSettingsView: View {
    @AppStorage("apple.model") private var model = ""
    @AppStorage("apple.webSearch.allowed") private var webSearch = true

    private var selection: OnDeviceModel.Selection {
        OnDeviceModel.Selection(rawValue: model) ?? .emblem
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Choose where responses are generated. Apple models never silently switch to the Emblem server.")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(3)

                VStack(spacing: 0) {
                    ForEach(OnDeviceModel.Selection.allCases, id: \.self) { option in
                        if option != .emblem { SettingsHairline() }
                        Button {
                            model = option.rawValue
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.title)
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(Theme.ink)
                                    Text(OnDeviceModel.shared.status(for: option, online: NetworkStatus.shared.isOnline) ?? detail(option))
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.inkSecondary)
                                }
                                Spacer(minLength: 12)
                                if selection == option {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Theme.accentDark)
                                }
                            }
                            .padding(.horizontal, SettingsMetrics.rowInset)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        .disabled(option == .privateCloud && !OnDeviceModel.privateCloudIsConfigured)
                        .opacity(option == .privateCloud && !OnDeviceModel.privateCloudIsConfigured ? 0.55 : 1)
                        .accessibilityIdentifier("apple-model-\(option.rawValue)")
                        .accessibilityAddTraits(selection == option ? [.isSelected] : [])
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous))

                if selection != .emblem {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Allow public web search", isOn: $webSearch)
                            .accentTint(Theme.accentDark)
                        Text("Searches send only the model's public search query to the Emblem server, never your conversation. Search is off for requests with attachments.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkSecondary)
                        if selection == .privateCloud, let quota = OnDeviceModel.shared.quotaNotice() {
                            Text(quota)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    .padding(SettingsMetrics.rowInset)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous))
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, 26)
            .padding(.bottom, 60)
        }
        .background(Theme.background)
        .navigationTitle("Apple Intelligence")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(_ selection: OnDeviceModel.Selection) -> String {
        switch selection {
        case .emblem: "Uses your selected Emblem server provider"
        case .onDevice: "Runs on this device; works offline"
        case .privateCloud: "Sends requests to Apple's Private Cloud Compute; iOS 27, internet and managed app access required"
        }
    }
}
