import SwiftUI
import EmblemCore

struct ContactAction: Hashable, Identifiable {
    enum Kind { case call, email, website, address }

    var id: String { title + value }

    let kind: Kind
    let value: String

    var title: String {
        switch kind {
        case .call: "Call"
        case .email: "Email"
        case .website: "Website"
        case .address: "Address"
        }
    }

    var symbol: String {
        switch kind {
        case .call: "phone.fill"
        case .email: "envelope.fill"
        case .website: "globe.americas.fill"
        case .address: "mappin.fill"
        }
    }

    static func actions(for facts: [FactList.Fact]) -> [ContactAction]? {
        guard !facts.isEmpty else { return nil }
        let actions = facts.compactMap(action)
        return actions.count == facts.count ? actions : nil
    }

    private static func action(for fact: FactList.Fact) -> ContactAction? {
        let value = fact.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = fact.label.lowercased()
        guard !value.isEmpty else { return nil }
        let digits = value.filter(\.isNumber)
        if value.contains("@"), !value.contains(" "), value.contains(".") {
            return ContactAction(kind: .email, value: value)
        }
        if digits.count >= 7, value.allSatisfy({ $0.isNumber || "+-(). ".contains($0) }) {
            return ContactAction(kind: .call, value: value)
        }
        if ["address", "location", "directions"].contains(where: label.contains) {
            return ContactAction(kind: .address, value: value)
        }
        if ["website", "web", "site", "url", "link"].contains(where: label.contains) || value.hasPrefix("http"),
           !value.contains(" "), value.contains(".") {
            return ContactAction(kind: .website, value: value)
        }
        return nil
    }

    var url: URL? {
        switch kind {
        case .call:
            URL(string: "tel:" + value.filter { $0.isNumber || $0 == "+" })
        case .email:
            URL(string: "mailto:" + value)
        case .website:
            URL(string: value.hasPrefix("http") ? value : "https://" + value)
        case .address:
            nil
        }
    }

    func mapsURL(google: Bool) -> URL? {
        var components = URLComponents(string: google
            ? "https://www.google.com/maps/search/"
            : "https://maps.apple.com/")!
        components.queryItems = google
            ? [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: value)]
            : [URLQueryItem(name: "q", value: value)]
        return components.url
    }
}

struct ContactActionList: View {
    let actions: [ContactAction]
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(\.openURL) private var openURL
    @State private var mapsTarget: ContactAction?

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                Button {
                    guard blockInteraction.allowsActivation else { return }
                    if action.kind == .address {
                        mapsTarget = action
                    } else if let url = action.url {
                        openURL(url)
                    }
                } label: {
                    let locationPill = actions.count == 1 && action.kind == .address
                    HStack(spacing: 12) {
                        GlyphImage(symbol: locationPill ? "mappin.and.ellipse" : action.symbol, size: 18)
                            .foregroundStyle(Theme.ink)
                        Text(locationPill ? action.value : action.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 15.5)
                    .frame(height: 52)
                    .background(GroupedRowShape(index: index, count: actions.count).fill(Theme.rowFill))
                    .contentShape(GroupedRowShape(index: index, count: actions.count))
                }
                .blockActivationControl()
                .buttonStyle(.pressable)
                .accessibilityLabel("\(action.title) \(action.value)")
            }
        }
        .groupedRowShadow()
        .padding(.horizontal, 32)
        .sheet(item: $mapsTarget) { target in
            MapsChoiceSheet { google in
                mapsTarget = nil
                if let url = target.mapsURL(google: google) { openURL(url) }
            }
        }
    }
}

private struct MapsChoiceSheet: View {
    let choose: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            option("Google Maps", google: true)
            Divider()
            option("Apple Maps", google: false)
        }
        .padding(.top, 30)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(145)])
        .presentationBackground(Theme.surface)
        .presentationDragIndicator(.hidden)
    }

    private func option(_ title: String, google: Bool) -> some View {
        Button { choose(google) } label: {
            Text(title)
                .font(.system(size: 18))
                .foregroundStyle(Color(uiColor: .systemBlue))
                .frame(maxWidth: .infinity, minHeight: 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
