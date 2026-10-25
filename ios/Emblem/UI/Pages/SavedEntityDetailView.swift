import SwiftUI
import EmblemCore

struct SavedEntityDetailView: View {
    let entityID: UUID
    let scopeID: UUID
    let onClose: () -> Void
    let onExplore: (UUID, UUID) -> Void
    @State private var saves = SavedPagesStore.shared
    @State private var errorMessage: String?

    private var entity: SavedEntity? {
        guard saves.scopeID == scopeID else { return nil }
        return saves.entities.first { $0.id == entityID }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if let entity {
                    VStack(spacing: 28) {
                        if let cover = entity.cover {
                            CardArtworkView(card: entity.card, maxPixelSize: 1_200)
                                .frame(width: geometry.size.width,
                                       height: geometry.size.width / aspect(cover.aspect))
                                .clipped()
                                .ignoresSafeArea(.container, edges: .top)
                                .accessibilityHidden(true)
                        }
                        TitleBlockView(block: TitleBlock(
                            id: "saved-entity-lead", title: entity.card.title,
                            metaLine: entity.card.meta, summary: entity.card.caption,
                            tags: entity.card.tag.map { [$0] }, actions: nil))
                        Button {
                            guard saves.scopeID == scopeID,
                                  saves.entities.contains(where: { $0.id == entityID }) else { return }
                            onExplore(entityID, scopeID)
                        } label: {
                            HStack {
                                Text("More about \(entity.card.title)")
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 16)
                                Image(systemName: "arrow.right")
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .padding(20)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.pressable)
                        .accessibilityIdentifier("saved-entity-explore")
                        .padding(.horizontal, 28)
                    }
                    .padding(.bottom, 44)
                } else {
                    Text("This saved item is no longer available.")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(32)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.background, ignoresSafeAreaEdges: .all)
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .scrollEdgeEffectHidden(for: .top)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationCircleButton(action: onClose) { CloseGlyph() }
                    .accessibilityLabel("Close saved item")
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                if let entity {
                    HStack(spacing: 0) {
                        ShareLink(item: [entity.card.title, entity.card.caption].compactMap { $0 }.joined(separator: "\n")) {
                            ChromeGlyph(symbol: .share)
                                .offset(x: -2)
                                .frame(width: 50, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Share saved item")
                        Button {
                            do {
                                try saves.removeEntity(id: entityID, expectedScope: scopeID)
                                onClose()
                            } catch { errorMessage = error.localizedDescription }
                        } label: {
                            SavedPageTrashGlyph()
                                .offset(x: 2)
                                .frame(width: 50, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Remove saved item")
                        .accessibilityIdentifier("saved-entity-remove")
                    }
                    .foregroundStyle(.primary)
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .alert("Couldn't update Saves", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    private func aspect(_ value: ImageSpec.Aspect) -> CGFloat {
        switch value {
        case .portrait: 2 / 3
        case .square: 1
        case .landscape: 4 / 3
        }
    }
}
