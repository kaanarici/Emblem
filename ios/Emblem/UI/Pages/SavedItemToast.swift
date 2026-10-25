import SwiftUI

struct ToastCard<Glyph: View>: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?
    @ViewBuilder let glyph: Glyph

    var body: some View {
        HStack(spacing: 12) {
            glyph
                .foregroundStyle(Theme.ink.opacity(0.96))
                .frame(width: 48, height: 48)
                .background(Color(uiColor: .tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink.opacity(0.96))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                    .contentShape(Capsule())
                    .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 73)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct SavedItemToast: View {
    var body: some View {
        ToastCard(title: "Added to Saves") {
            ChromeGlyph(symbol: .bookmark, size: 24, filled: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("saved-item-toast")
        .allowsHitTesting(false)
    }
}

struct HomeRefreshToast: View {
    let retry: () -> Void

    var body: some View {
        ToastCard(title: "Couldn't refresh Home", actionTitle: "Retry", action: retry) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 20, weight: .medium))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-refresh-toast")
    }
}
