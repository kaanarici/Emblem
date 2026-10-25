import SwiftUI
import EmblemCore

struct SavedPagesView: View {
    let onBack: () -> Void
    let onOpen: (SavedShelfEntry) -> Void
    var showsMenu = false
    var expansionNamespace: Namespace.ID?
    @State private var savedPages = SavedPagesStore.shared

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                if savedPages.shelfEntries.isEmpty {
                    emptyState
                        .frame(minHeight: max(0, viewport.size.height - 140))
                        .padding(.bottom, 140)
                } else {
                    LazyVStack(alignment: .leading, spacing: 127 / 3) {
                        ForEach(shelfGroups) { group in
                            VStack(alignment: .leading, spacing: 50 / 3) {
                                Text(group.categoryTitle)
                                    .font(.system(size: 20, weight: .bold))
                                    .tracking(-0.5)
                                    .foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 32)
                                    .padding(.top, 4 / 3)
                                    .accessibilityAddTraits(.isHeader)
                                ScrollView(.horizontal) {
                                    HStack(alignment: .top, spacing: 12) {
                                        ForEach(group.entries) { saved in
                                            savedCard(saved, width: max(120, (viewport.size.width - 68) / 2))
                                        }
                                    }
                                }
                                .contentMargins(.horizontal, 28, for: .scrollContent)
                                .scrollIndicators(.hidden)
                                .scrollClipDisabled()
                            }
                        }
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 140)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.background)
        .task { savedPages.requestOrganization(retryUncategorized: true) }
        .onChange(of: savedPages.shelfEntries.map(\.id)) { _, _ in savedPages.requestOrganization() }
        .navigationTitle("Saves")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationCircleButton(action: onBack) {
                    ChromeGlyph(symbol: showsMenu ? .menu : .chevronLeft)
                }
                .accessibilityLabel(showsMenu ? "Open menu" : "Back")
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ChromeGlyph(symbol: .bookmark, size: 28)
                .foregroundStyle(Theme.inkSecondary)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text(savedPages.errorMessage == nil ? "No saves yet" : "Couldn't load saves")
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(savedPages.errorMessage == nil
                 ? "Bookmark a page or an item\nto find it here."
                 : "Try opening your saved pages again.")
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            if savedPages.errorMessage != nil {
                Button("Try again") { try? savedPages.reload() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    private func savedCard(_ saved: SavedShelfEntry, width: CGFloat) -> some View {
        return Button { onOpen(saved) } label: {
            VStack(alignment: .leading, spacing: saved.cover?.aspect == .portrait ? 8 : 12) {
                if let cover = saved.cover {
                    RemoteImage(spec: cover.image, url: cover.imageURL.flatMap(URL.init(string:)), maxPixelSize: 700)
                        .frame(width: width, height: width / coverRatio(cover.aspect))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                        .modifier(SavedCoverSource(id: transitionID(for: saved), namespace: expansionNamespace))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(saved.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineSpacing(1)
                        .lineLimit(3)
                        .foregroundStyle(Theme.ink)
                    if let subtitle = saved.previewSubtitle {
                        Text(subtitle)
                            .font(.system(size: 14))
                            .lineSpacing(18 - UIFont.systemFont(ofSize: 14).lineHeight)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(width: width - 8, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            }
            .frame(width: width, alignment: .topLeading)
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier(accessibilityID(for: saved))
    }

    private struct ShelfGroup: Identifiable {
        let id: String
        let categoryTitle: String
        let entries: [SavedShelfEntry]
    }

    private var shelfGroups: [ShelfGroup] {
        let entries = savedPages.shelfEntries
        var keys: [String] = []
        var grouped: [String: [SavedShelfEntry]] = [:]
        for entry in entries {
            if grouped[entry.categoryKey] == nil { keys.append(entry.categoryKey) }
            grouped[entry.categoryKey, default: []].append(entry)
        }
        let orderedKeys = keys.filter { $0 != "other" } + keys.filter { $0 == "other" }
        return orderedKeys.compactMap { key in
            guard let values = grouped[key], let first = values.first else { return nil }
            return ShelfGroup(id: key, categoryTitle: first.categoryTitle, entries: values)
        }
    }

    private func transitionID(for entry: SavedShelfEntry) -> String {
        switch entry {
        case .page(let page): page.pageKey
        case .entity(let entity): "entity-\(entity.id.uuidString)"
        }
    }

    private func accessibilityID(for entry: SavedShelfEntry) -> String {
        switch entry {
        case .page(let page): "saved-page-\(page.pageKey)"
        case .entity(let entity): "saved-entity-\(entity.id.uuidString)"
        }
    }

    private func coverRatio(_ aspect: ImageSpec.Aspect) -> CGFloat {
        switch aspect {
        case .square: 1
        case .landscape: 4 / 3
        case .portrait: 2 / 3
        }
    }
}

private struct SavedCoverSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    @ViewBuilder func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: "saved-\(id)", in: namespace)
        } else {
            content
        }
    }
}
