import SwiftUI
import EmblemCore

struct HomeSidebar: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var history = ConversationHistory.shared
    @State private var deleteTarget: HistoryTarget?
    @State private var deleteFailed = false

    let topInset: CGFloat
    let bottomInset: CGFloat
    let isVisible: Bool
    let isHomeSelected: Bool
    let selectedConversationKey: String?
    let onHome: () -> Void
    let onConversation: (String) -> Void
    let onSaves: () -> Void
    let onSettings: () -> Void
    var isSavesSelected = false
    var isSettingsSelected = false
    var isCalendarSelected = false
    var onCalendar: (() -> Void)? = nil

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    sidebarRow("Home", symbol: "house", selected: isHomeSelected, action: onHome)
                    sidebarRow("Saves", symbol: "bookmark", selected: isSavesSelected, action: onSaves)
                    if let onCalendar {
                        sidebarRow("Calendar", symbol: "calendar", selected: isCalendarSelected, action: onCalendar)
                    }
                    Divider().padding(.vertical, 18)
                    if !recentConversations.isEmpty {
                        Text("Chats")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
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
                    } else if history.loadState == .loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                    if history.loadState == .failed {
                        failedRow
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, topInset + 12)
                .padding(.bottom, 150)
                .transaction(value: history.epoch) { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .bottom) {
                VariableBlurView(maxBlurRadius: 8, direction: .blurredBottomClearTop)
                    .frame(height: bottomInset + 80)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 0) {
                VariableBlurView(maxBlurRadius: 8, direction: .blurredTopClearBottom)
                    .frame(height: topInset + 12)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Spacer()
                SidebarAccount(selected: isSettingsSelected, isVisible: isVisible, onSettings: onSettings)
                    .frame(height: DockView.controlSize)
                    .padding(.bottom, bottomInset)
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebarBackground)
        .task(id: isVisible) {
            if isVisible { await history.load() }
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

    private var recentConversations: [ConversationSummary] {
        history.items
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
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.card)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    let pin = Text(item.isPinned ? "  \(Image(systemName: "pin.fill"))" : "")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSecondary)
                    Text("\(item.title)\(pin)")
                        .font(.system(size: 16))
                        .lineLimit(2)
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

private struct SidebarAccount: View {
    @Environment(AuthStore.self) private var auth

    let selected: Bool
    let isVisible: Bool
    let onSettings: () -> Void

    var body: some View {
        Button(action: onSettings) { account }
            .buttonStyle(.pressable)
            .accessibilityRepresentation {
                if isVisible {
                    Button(action: onSettings) { account }
                        .accessibilityIdentifier("sidebar-settings")
                        .accessibilityHint("Opens Settings and connections")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in
                width / 2 - DockView.newPageWidth / 2 - 16
            }
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var name: String? {
        auth.greetingName ?? auth.displayName ?? auth.email
    }

    private var account: some View {
        HStack(spacing: 10) {
            profileCircle
            Text(name ?? "Guest")
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .accessibilityIdentifier("sidebar-account")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: DockView.innerControlSize)
        .background(selected ? Theme.ink.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
    }

    private var profileCircle: some View {
        Group {
            if let url = auth.avatarURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initial
                    }
                }
            } else {
                initial
            }
        }
        .frame(width: 28, height: 28)
        .background(Theme.ink.opacity(0.08), in: Circle())
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var initial: some View {
        if let letter = name?.first {
            Text(String(letter).uppercased())
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
        } else {
            EmblemLogo(size: 20)
        }
    }
}
