import SwiftUI
import EmblemCore

func relativeTime(_ date: Date) -> String {
    let diff = Date().timeIntervalSince(date)
    let min = Int(diff / 60)
    if min < 1 { return "Just now" }
    if min < 60 { return "\(min)m ago" }
    let hr = min / 60
    if hr < 24 { return "\(hr)h ago" }
    let day = hr / 24
    if day == 1 { return "Yesterday" }
    if day < 7 { return "\(day)d ago" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
}

struct ArchivedChatsView: View {
    @Environment(ConversationStore.self) private var store

    @State private var history = ConversationHistory.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if history.loadState(.archived) == .failed && items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.inkSecondary)
                        Text("Couldn't load archived chats")
                            .font(Theme.bodySecondary())
                            .foregroundStyle(Theme.inkSecondary)
                        Button("Try again") {
                            Task { await history.load(.archived, force: true) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else if history.loadState(.archived) == .idle ||
                            (history.loadState(.archived) == .loading && items.isEmpty) {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                } else if items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(Theme.inkSecondary)
                        Text("Nothing archived")
                            .font(Theme.bodySecondary())
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item)
                                .onAppear {
                                    guard index == items.count - 1 else { return }
                                    Task { await history.loadMore(.archived) }
                                }
                            if index < items.count - 1 {
                                Rectangle()
                                    .fill(Theme.inkSecondary.opacity(0.14))
                                    .frame(height: 1)
                                    .padding(.leading, 18)
                            }
                        }
                    }
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .padding(.top, 18)

                    if history.loadState(.archived) == .failed {
                        Button {
                            Task { await history.load(.archived, force: true) }
                        } label: {
                            Label("Couldn't refresh · Retry", systemImage: "wifi.exclamationmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.inkSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .navigationTitle("Archived chats")
        .navigationBarTitleDisplayMode(.inline)
        .task { await history.load(.archived) }
    }

    private var items: [ConversationSummary] {
        history.items(.archived)
    }

    private func row(_ item: ConversationSummary) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(relativeTime(item.date))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 12)
            Button {
                store.unarchiveConversation(key: item.key)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.cardSoft))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .contextMenu {
            Button {
                store.unarchiveConversation(key: item.key)
            } label: {
                Label("Unarchive", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) {
                store.deleteConversation(key: item.key)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
