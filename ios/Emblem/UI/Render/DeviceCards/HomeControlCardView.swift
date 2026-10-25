import SwiftUI
import EmblemCore

#if EMBLEM_HOMEKIT
struct HomeControlCardView: View {
    let block: HomeControlBlock
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var ranScene: UUID?
    @State private var pending: Set<UUID> = []
    private let access = DeviceAccess.shared
    private let home = HomeService.shared

    var body: some View {
        let allowed = access.canUse(.home)
        let match = home.matching(block.q)
        VStack(alignment: .leading, spacing: 12) {
            DeviceCardTitle(kind: .home, title: block.q.map { $0.capitalized } ?? "Home")
            if !allowed {
                DeviceCardPermission(kind: .home)
            } else if home.loaded, !home.hasHome {
                DeviceCardMessage(text: "No home is set up in the Home app yet.")
            } else if home.loaded, match.accessories.isEmpty, match.scenes.isEmpty {
                DeviceCardMessage(text: "Nothing in your home matches \u{201C}\(block.q ?? "")\u{201D}.")
            } else {
                if !match.scenes.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(match.scenes) { scene in sceneButton(scene) }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(match.accessories) { accessory in tile(accessory) }
                }
            }
        }
        .padding(.horizontal, 28)
        .task(id: allowed) { if allowed { home.load() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { access.refresh() }
        }
    }

    private func tile(_ accessory: HomeService.Accessory) -> some View {
        let on = accessory.isOn == true
        return Button {
            guard blockInteraction.allowsActivation, accessory.reachable, !pending.contains(accessory.id) else { return }
            pending.insert(accessory.id)
            Task {
                _ = await home.setPower(accessory.id, on: !on)
                pending.remove(accessory.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: accessory.symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(on ? Color(red: 1, green: 0.72, blue: 0.1) : Theme.inkSecondary)
                    .symbolEffect(.bounce, value: on)
                VStack(alignment: .leading, spacing: 1) {
                    Text(accessory.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(on ? Color.black : Theme.ink)
                        .lineLimit(1)
                    Text(accessory.reachable ? "\(accessory.room.isEmpty ? "" : accessory.room + " · ")\(on ? "On" : "Off")" : "No Response")
                        .font(.system(size: 13))
                        .foregroundStyle(on ? Color.black.opacity(0.55) : Theme.inkSecondary)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(on ? Color.white : (colorScheme == .dark ? Theme.rowFill : Theme.chip),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(accessory.reachable ? (pending.contains(accessory.id) ? 0.6 : 1) : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.pressable)
        .blockActivationControl()
        .groupedRowShadow()
        .sensoryFeedback(EmblemHaptic.toggle, trigger: on)
        .animation(.smooth(duration: 0.2), value: on)
        .accessibilityLabel(accessory.name)
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityIdentifier("home-accessory")
    }

    private func sceneButton(_ scene: HomeService.Scene) -> some View {
        Button {
            guard blockInteraction.allowsActivation else { return }
            Task {
                if await home.run(scene.id) {
                    ranScene = scene.id
                    try? await Task.sleep(for: .seconds(2))
                    if ranScene == scene.id { ranScene = nil }
                }
            }
        } label: {
            Label(scene.name, systemImage: ranScene == scene.id ? "checkmark" : "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(Theme.rowFill, in: Capsule())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.pressable)
        .blockActivationControl()
        .groupedRowShadow()
        .accessibilityIdentifier("home-scene")
    }
}
#else
struct HomeControlCardView: View {
    let block: HomeControlBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeviceCardTitle(kind: .home, title: block.q.map { $0.capitalized } ?? "Home")
            DeviceCardMessage(text: "Home control isn't available in this version of \(AppInfo.name).")
        }
        .padding(.horizontal, 28)
    }
}
#endif
