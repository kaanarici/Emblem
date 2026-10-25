import SwiftUI
import EmblemCore

enum SettingsMetrics {
    static let rowInset: CGFloat = 20
    static let rowHeight: CGFloat = 52
    static let sectionGap: CGFloat = 32
    static let cardRadius: CGFloat = 22
    static let titleFont = Font.system(size: 16)
    static let subtitleFont = Font.system(size: 13)
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.surface, in: RoundedRectangle(
                cornerRadius: SettingsMetrics.cardRadius, style: .continuous))
    }
}

struct SettingsHairline: View {
    var pastIcon = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Theme.rowButtonStroke)
            .frame(height: 1 / displayScale)
            .padding(.leading, pastIcon ? ConnectorRowMetrics.icon + ConnectorRowMetrics.spacing : 0)
            .padding(.horizontal, SettingsMetrics.rowInset)
    }
}

struct SettingsSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.bottom, 10)
    }
}

struct SettingsCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SettingsMetrics.subtitleFont)
            .foregroundStyle(Theme.inkSecondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.top, 10)
    }
}

struct SettingsRowLabel: View {
    enum Trailing { case chevron, outbound }

    let title: String
    var value: String?
    var trailing: Trailing = .chevron

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(SettingsMetrics.titleFont)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 12)
            if let value {
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSecondary)
            }
            switch trailing {
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
            case .outbound:
                Image("Hugeicons/SquareArrowUpRight")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .frame(minHeight: SettingsMetrics.rowHeight)
        .contentShape(Rectangle())
    }
}

struct SettingsMenuRow<Options: View, Value: View>: View {
    let title: String
    @ViewBuilder let options: Options
    @ViewBuilder let value: Value

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(SettingsMetrics.titleFont)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 12)
            Menu {
                options
            } label: {
                HStack(spacing: 6) {
                    value
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .medium))
                }
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSecondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier(title)
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(SettingsMetrics.titleFont)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .accentTint(Theme.toggleTint)
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}

struct SettingsDestructiveRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(SettingsMetrics.titleFont)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.negative)
            .padding(.horizontal, SettingsMetrics.rowInset)
            .frame(minHeight: SettingsMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(title)
    }
}
