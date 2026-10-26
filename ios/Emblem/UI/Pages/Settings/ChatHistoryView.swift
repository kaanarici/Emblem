import SwiftUI
import EmblemCore

struct ChatHistoryView: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onOpen: (String) -> Void = { _ in }

    @State private var history = ConversationHistory.shared
    @State private var scope = ConversationHistory.Scope.active
    @State private var query = ""
    @State private var editing = false
    @State private var selection = Set<String>()
    @State private var confirmDelete = false
    @State private var pending: PendingChange?
    @State private var failure: String?

    private struct PendingChange {
        let id = UUID()
        let edits: [ConversationHistory.Edit]
        let change: ConversationHistory.Change
        let message: String
    }

    private static let searchPageTarget = 20
    private static let undoSeconds = 5

    var body: some View {
        List {
            Section {
                Picker("Chats", selection: $scope) {
                    Text("Chats").tag(ConversationHistory.Scope.active)
                    Text("Archived").tag(ConversationHistory.Scope.archived)
                }
                .pickerStyle(.segmented)
                .disabled(editing)
                .accessibilityIdentifier("chats-scope")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .listSectionSpacing(14)

            Section {
                ForEach(visible) { item in
                    row(item)
                        .onAppear {
                            guard item.key == visible.last?.key else { return }
                            Task { await history.loadMore(scope) }
                        }
                }
                footer
            }
            .listRowBackground(Theme.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .background(Theme.background)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search chats")
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: visible.map(\.key))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(editing)
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .task(id: scope) { await history.load(scope) }
        .task(id: [searchText, "\(visible.count)", "\(history.loadState(scope))"]) {
            guard !searchText.isEmpty, visible.count < Self.searchPageTarget,
                  history.loadState(scope) == .loaded, history.canLoadMore(scope) else { return }
            await history.loadMore(scope)
        }
        .onChange(of: scope) { _, _ in selection = [] }
        .onChange(of: history.epoch) { _, _ in
            pending = nil
            endEditing()
        }
        .onDisappear(perform: commitPending)
        .alert(failure ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your chats are unchanged. Check your connection and try again.")
        }
    }

    private var searchText: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var items: [ConversationSummary] { history.items(scope) }

    private var visible: [ConversationSummary] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.title.localizedStandardContains(searchText) }
    }

    private var title: String {
        guard editing else { return scope == .archived ? "Archived" : "Chats" }
        return selection.isEmpty ? "Select Chats" : "\(selection.count) Selected"
    }

    private var deleteTitle: String {
        selection.count == 1 ? "Delete this chat?" : "Delete \(selection.count) chats?"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if editing {
            ToolbarItem(placement: .topBarLeading) {
                Button(allSelected ? "Deselect All" : "Select All") {
                    selection = allSelected ? [] : Set(visible.map(\.key))
                }
                .accessibilityIdentifier("chats-select-all")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if editing {
                Button("Done", action: endEditing)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("chats-select")
            } else if !visible.isEmpty {
                Button("Select") { withAnimation(.smooth(duration: 0.25)) { editing = true } }
                    .accessibilityIdentifier("chats-select")
            }
        }
    }

    private var allSelected: Bool {
        !visible.isEmpty && visible.allSatisfy { selection.contains($0.key) }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if editing {
            HStack(spacing: 12) {
                barButton(scope == .archived ? "Unarchive" : "Archive", id: "chats-archive") {
                    stage(Array(selection), .archive(scope == .active))
                }
                barButton("Delete", id: "chats-delete", role: .destructive) { confirmDelete = true }
                .confirmationDialog(deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button(selection.count == 1 ? "Delete Chat" : "Delete \(selection.count) Chats", role: .destructive) {
                        stage(Array(selection), .delete)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Their pages are erased from your account. You can undo for a few seconds.")
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .background {
                LinearGradient(colors: [Theme.background.opacity(0), Theme.background],
                               startPoint: .top, endPoint: .center)
                    .ignoresSafeArea()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let pending {
            ToastCard(title: pending.message, actionTitle: "Undo", action: undo) {
                Image(systemName: pending.change == .delete ? "trash" : "archivebox")
                    .font(.system(size: 20, weight: .medium))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chats-undo-toast")
            .padding(.horizontal, Theme.pageMargin)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func barButton(
        _ title: String, id: String, role: ButtonRole? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(role == .destructive ? Theme.negative : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .disabled(selection.isEmpty)
        .opacity(selection.isEmpty ? 0.45 : 1)
        .accessibilityIdentifier(id)
    }

    private func row(_ item: ConversationSummary) -> some View {
        let selected = selection.contains(item.key)
        return Button {
            guard editing else { return onOpen(item.key) }
            if selected { selection.remove(item.key) } else { selection.insert(item.key) }
        } label: {
            HStack(spacing: 14) {
                if editing {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(selected ? accent.tint(Theme.accentDark) : Theme.inkSecondary.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                ChatHistoryRow(item: item)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat-\(item.key)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !editing { swipeButtons(item) }
        }
        .contextMenu {
            if !editing { menuButtons(item) }
        }
    }

    @ViewBuilder
    private func swipeButtons(_ item: ConversationSummary) -> some View {
        Button(role: .destructive) { stage([item.key], .delete) } label: {
            Label("Delete", systemImage: "trash")
        }
        .tint(Theme.record)
        Button { stage([item.key], .archive(!item.archived)) } label: {
            Label(item.archived ? "Unarchive" : "Archive",
                  systemImage: item.archived ? "tray.and.arrow.up" : "archivebox")
        }
        .tint(Theme.inkSecondary)
    }

    @ViewBuilder
    private func menuButtons(_ item: ConversationSummary) -> some View {
        Button { stage([item.key], .archive(!item.archived)) } label: {
            Label(item.archived ? "Unarchive" : "Archive",
                  systemImage: item.archived ? "tray.and.arrow.up" : "archivebox")
        }
        Button(role: .destructive) { stage([item.key], .delete) } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var footer: some View {
        let state = history.loadState(scope)
        if state == .failed {
            Button {
                Task { await history.load(scope, force: true) }
            } label: {
                Label(items.isEmpty ? "Couldn't load your chats. Retry" : "Couldn't load more. Retry",
                      systemImage: "wifi.exclamationmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chats-retry")
        } else if state == .idle || state == .loading || (!searchText.isEmpty && history.canLoadMore(scope)) {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44)
            } else if visible.isEmpty {
            Text(emptyText)
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("chats-empty")
        }
    }

    private var emptyText: String {
        if !searchText.isEmpty { return "No chats match \u{201C}\(searchText)\u{201D}" }
        return scope == .archived ? "Nothing archived" : "No chats yet"
    }

    private func endEditing() {
        withAnimation(.smooth(duration: 0.25)) { editing = false }
        selection = []
    }

    private func stage(_ keys: [String], _ change: ConversationHistory.Change) {
        commitPending()
        let edits = withAnimation(.smooth(duration: 0.3)) { history.edit(keys, change) }
        endEditing()
        guard !edits.isEmpty else { return }
        let staged = PendingChange(edits: edits, change: change, message: message(change, count: edits.count))
        withAnimation(.smooth(duration: 0.3)) { pending = staged }
        Task {
            try? await Task.sleep(for: .seconds(Self.undoSeconds))
            guard pending?.id == staged.id else { return }
            commitPending()
        }
    }

    private func undo() {
        guard let pending else { return }
        withAnimation(.smooth(duration: 0.3)) {
            pending.edits.forEach(history.discard)
            self.pending = nil
        }
    }

    private func commitPending() {
        guard let pending else { return }
        withAnimation(.smooth(duration: 0.3)) { self.pending = nil }
        let verb = pending.change == .delete ? "delete" : pending.change == .archive(true) ? "archive" : "unarchive"
        let onFailure: @MainActor () -> Void = { failure = "Couldn't \(verb) \(pending.edits.count == 1 ? "chat" : "chats")" }
        if pending.change == .archive(false) {
            store.commitConversationChanges(pending.edits, onFailure: onFailure)
        } else {
            store.commitConversationRemovals(pending.edits, onFailure: onFailure)
        }
    }

    private func message(_ change: ConversationHistory.Change, count: Int) -> String {
        let chats = count == 1 ? "chat" : "\(count) chats"
        switch change {
        case .delete: return "Deleted \(chats)"
        case .archive(true): return "Archived \(chats)"
        default: return "Unarchived \(chats)"
        }
    }
}

private struct ChatHistoryRow: View {
    let item: ConversationSummary

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(SettingsMetrics.titleFont)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkSecondary)
                            .accessibilityLabel("Pinned")
                    }
                }
                Text(item.date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .font(SettingsMetrics.subtitleFont)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var artwork: some View {
        if let cover = item.artwork {
            RemoteImage(spec: cover.image, url: cover.imageURL.flatMap(URL.init(string:)), maxPixelSize: 128)
        } else if let url = item.legacyArtworkURL.flatMap(URL.init(string:)) {
            RemoteImage(url: url, maxPixelSize: 128)
        } else {
            Image(systemName: "bubble.left")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.card)
        }
    }
}
