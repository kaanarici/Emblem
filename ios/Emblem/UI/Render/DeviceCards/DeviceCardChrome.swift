import SwiftUI
import EmblemCore

struct DeviceCardTitle: View {
    let kind: DeviceAccess.Kind
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            DeviceAppIcon(kind: kind, size: 26)
            Text(title)
                .font(Theme.cardTitle())
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("On this iPhone")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}

struct DeviceCardMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Theme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct DeviceCardPermission: View {
    let kind: DeviceAccess.Kind

    var body: some View {
        DevicePermissionRow(kind: kind, iconSize: 40)
            .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .groupedRowShadow()
    }
}
