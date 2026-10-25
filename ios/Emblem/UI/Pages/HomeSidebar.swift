import SwiftUI
import EmblemCore

struct HomeSidebar: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accent) private var accent
    @State private var history = ConversationHistory.shared
    @State private var deleteTarget: HistoryTarget?
    @State private var deleteFailed = false
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    let topInset: CGFloat
    let bottomInset: CGFloat
    let isVisible: Bool
    let isOpen: Bool
    let isHomeSelected: Bool
    let selectedConversationKey: String?
    let onHome: () -> Void
    let onConversation: (String) -> Void
    let onSaves: () -> Void
    var isSavesSelected = false
    var isCalendarSelected = false
    var onCalendar: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, topInset)
            VStack(alignment: .leading, spacing: 0) {
                if !searching {
                    sidebarRow("Home", symbol: "house", selected: isHomeSelected, action: onHome)
                    sidebarRow("Saves", symbol: "bookmark", selected: isSavesSelected, action: onSaves)
                    if let onCalendar {
                        sidebarRow("Calendar", symbol: "calendar", selected: isCalendarSelected, action: onCalendar)
                    }
                    Divider().padding(.top, 14)
                    if !recentConversations.isEmpty || history.loadState != .loaded {
                        Text("Chats")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 18)
                        .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
            chats
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebarBackground)
        .task(id: isVisible) {
            if isVisible { await history.load() }
            else { endSearch() }
        }
        .onChange(of: isOpen) { _, open in
            if !open { searchFocused = false }
        }
        .task(id: SearchPaging(query: searchText, matches: recentConversations.count, state: history.loadState)) {
            guard !searchText.isEmpty, recentConversations.count < Self.searchPageTarget,
                  history.loadState == .loaded, history.canLoadMore else { return }
            await history.loadMore()
        }
        .onChange(of: history.epoch) { _, _ in
            deleteTarget = nil
            deleteFailed = false
        }
        .alert("Couldn't delete chat", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please try again.")
        }
    }

    private struct HistoryTarget {
        let key: String
        let epoch: UUID
    }

    private func deletePresented(for target: HistoryTarget) -> Binding<Bool> {
        Binding(get: {
            deleteTarget?.key == target.key && deleteTarget?.epoch == target.epoch
        }, set: { presented in
            if !presented, deleteTarget?.key == target.key, deleteTarget?.epoch == target.epoch {
                deleteTarget = nil
            }
        })
    }

    private func isCurrent(_ target: HistoryTarget) -> Bool {
        target.epoch == history.epoch && history.summary(for: target.key)?.archived == false
    }

    private func deleteConversation() {
        guard let target = deleteTarget else { return }
        deleteTarget = nil
        guard isCurrent(target) else { return }
        let started = store.deleteConversation(key: target.key) {
            guard history.epoch == target.epoch else { return }
            deleteFailed = true
        }
        if !started { deleteFailed = true }
    }

    private var chats: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(recentConversations) { item in
                    conversationRow(item)
                        .transition(reduceMotion ? .identity : .opacity)
                        .onAppear {
                            guard item.key == recentConversations.last?.key else { return }
                            Task { await history.loadMore() }
                        }
                }
                .id(history.epoch)
                .animation(reduceMotion ? nil : .spring(duration: 0.32), value: recentConversations.map(\.key))
                if history.loadState == .loading, recentConversations.isEmpty || !searchText.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else if !searchText.isEmpty, recentConversations.isEmpty, history.loadState == .loaded,
                          !history.canLoadMore {
                    noMatchesRow
                }
                if history.loadState == .failed {
                    failedRow
                }
            }
            .padding(.horizontal, 8)
            .transaction(value: history.epoch) { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .contentMargins(.top, Self.edgeFade, for: .scrollContent)
        .contentMargins(.bottom, dockClearance + Self.edgeFade * 2, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.edgeFade)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.edgeFade * 2)
                Color.clear
                    .frame(height: dockClearance)
            }
        }
    }

    private static let edgeFade: CGFloat = 14

    private var dockClearance: CGFloat {
        guard searchFocused, KeyboardPresence.shared.isVisible else { return bottomInset + DockView.controlSize }
        return KeyboardPresence.shared.lastHeight
    }

    private var recentConversations: [ConversationSummary] {
        guard !searchText.isEmpty else { return history.items }
        return history.items.filter { $0.title.localizedStandardContains(searchText) }
    }

    private var searchText: String {
        searching ? query.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    private struct SearchPaging: Equatable {
        let query: String
        let matches: Int
        let state: ConversationHistory.LoadState
    }

    private static let searchPageTarget = 20

    private var searchMotion: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.28)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if searching {
                    searchField
                        .transition(.opacity)
                } else {
                    Text("Emblem")
                        .font(Theme.greeting(strong: true))
                        .tracking(Theme.greetingTracking)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                if searching { endSearch() } else { beginSearch() }
            } label: {
                ZStack {
                    GlyphImage(symbol: "magnifyingglass", size: 24)
                        .opacity(searching ? 0 : 1)
                    CloseGlyph()
                        .opacity(searching ? 1 : 0)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel(searching ? "Cancel search" : "Search chats")
            .accessibilityIdentifier("sidebar-search")
        }
        .frame(height: 44)
        .padding(.leading, searching ? DockView.sideInset : 20)
        .padding(.trailing, DockView.sideInset)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            GlyphImage(symbol: "magnifyingglass", size: 18)
                .foregroundStyle(Theme.inkSecondary)
            TextField("Search chats", text: $query)
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { searchFocused = false }
                .onKeyPress(.escape) {
                    endSearch()
                    return .handled
                }
                .accessibilityIdentifier("sidebar-search-field")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 28, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, query.isEmpty ? 14 : 6)
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
    }

    private func beginSearch() {
        withAnimation(searchMotion) { searching = true }
        searchFocused = true
    }

    private func endSearch() {
        searchFocused = false
        guard searching || !query.isEmpty else { return }
        withAnimation(searchMotion) {
            searching = false
            query = ""
        }
    }

    private var noMatchesRow: some View {
        Text("No chats match \u{201C}\(searchText)\u{201D}")
            .font(.system(size: 15))
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .accessibilityIdentifier("sidebar-search-empty")
    }

    private func conversationRow(_ item: ConversationSummary) -> some View {
        let selected = item.key == selectedConversationKey
        let target = HistoryTarget(key: item.key, epoch: history.epoch)
        return Button { onConversation(item.key) } label: {
            HStack(spacing: 12) {
                Group {
                    if let artwork = item.artwork {
                        RemoteImage(spec: artwork.image, url: artwork.imageURL.flatMap(URL.init(string:)), maxPixelSize: 128)
                    } else if let url = item.legacyArtworkURL.flatMap(URL.init(string:)) {
                        RemoteImage(url: url, maxPixelSize: 128)
                    } else {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 19, weight: .light))
                            .foregroundStyle(selected ? accent.tint(Theme.ink) : Theme.inkSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.card)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 16))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkSecondary)
                                .fixedSize()
                                .layoutPriority(1)
                                .accessibilityLabel("Pinned")
                        }
                    }
                    Text(item.date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(selected ? Theme.inkSecondary : Theme.ink)
            .background(selected ? Theme.ink.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 14))
            .background(Theme.sidebarBackground, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(hapticsEnabled: false))
        .contextMenu {
            Button {
                guard isCurrent(target) else { return }
                store.setConversationPinned(key: item.key, pinned: !item.isPinned)
            } label: {
                Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) {
                guard isCurrent(target) else { return }
                deleteTarget = target
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete chat?", isPresented: deletePresented(for: target)) {
            Button("Delete", role: .destructive, action: deleteConversation)
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This permanently deletes the chat and its pages.")
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("sidebar-conversation-\(item.key)")
    }

    private var failedRow: some View {
        Button {
            Task { await history.load(force: true) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 56, height: 56)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't load your chats")
                        .font(.system(size: 16))
                    Text("Tap to try again")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(hapticsEnabled: false))
        .accessibilityIdentifier("sidebar-history-retry")
    }

    private func sidebarRow(
        _ title: String,
        symbol: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if symbol == "house" {
                        SidebarHomeGlyph(selected: selected)
                    } else if symbol == "bookmark" {
                        ChromeGlyph(symbol: .allBookmark, filled: selected)
                    } else if symbol == "calendar" {
                        ZStack {
                            ChromeGlyph(symbol: .calendarOutline).opacity(selected ? 0 : 1)
                            ChromeGlyph(symbol: .calendar, filled: true).opacity(selected ? 1 : 0)
                        }
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: selected)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 19, weight: .regular))
                    }
                }
                .frame(width: 24, height: 24)
                .foregroundStyle(selected ? accent.tint(Theme.ink) : Theme.ink)
                Text(title)
                    .font(.system(size: 16))
                Spacer()
            }
            .frame(minHeight: 45)
            .padding(.horizontal, 12)
            .foregroundStyle(Theme.ink)
            .background(selected ? Theme.ink.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SidebarHomeGlyph: View {
    let selected: Bool

    var body: some View {
        ChromeGlyph(symbol: .home, filled: selected)
    }
}

