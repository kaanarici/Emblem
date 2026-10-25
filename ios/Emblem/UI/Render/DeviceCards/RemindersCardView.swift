import SwiftUI
import EmblemCore

struct RemindersCardView: View {
    let block: RemindersBlock
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(\.scenePhase) private var scenePhase
    @State private var items: [RemindersService.Item] = []
    @State private var drafts: [String] = []
    @State private var loaded = false
    private let access = DeviceAccess.shared

    private var title: String {
        if let list = block.list, !list.isEmpty { return list }
        return switch block.scope {
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .all: "Reminders"
        }
    }

    var body: some View {
        let allowed = access.canUse(.reminders)
        VStack(alignment: .leading, spacing: 12) {
            DeviceCardTitle(kind: .reminders, title: title)
            if !allowed {
                DeviceCardPermission(kind: .reminders)
            } else if loaded, items.isEmpty, drafts.isEmpty {
                DeviceCardMessage(text: block.scope == .today ? "Nothing due today." : "No reminders here.")
            } else {
                let count = items.count + drafts.count
                VStack(spacing: 5.5) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        itemRow(item)
                            .background(GroupedRowShape(index: index, count: count).fill(Theme.rowFill))
                    }
                    ForEach(Array(drafts.enumerated()), id: \.offset) { offset, draft in
                        draftRow(draft)
                            .background(GroupedRowShape(index: items.count + offset, count: count).fill(Theme.rowFill))
                    }
                }
                .groupedRowShadow()
            }
        }
        .padding(.horizontal, 28)
        .task(id: allowed) { await load(allowed) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { access.refresh() }
        }
        .animation(.smooth(duration: 0.25), value: items)
        .animation(.smooth(duration: 0.25), value: drafts)
    }

    private func load(_ allowed: Bool) async {
        drafts = (block.add ?? []).filter { draft in !items.contains { $0.title == draft } }
        guard allowed else { return }
        items = await RemindersService.shared.fetch(scope: block.scope, list: block.list)
        loaded = true
    }

    private func itemRow(_ item: RemindersService.Item) -> some View {
        Button {
            guard blockInteraction.allowsActivation else { return }
            if RemindersService.shared.setDone(item.id, !item.done),
               let index = items.firstIndex(of: item) {
                items[index].done.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(item.done ? Color.orange : Theme.inkSecondary.opacity(0.7))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15))
                        .foregroundStyle(item.done ? Theme.inkSecondary : Theme.ink)
                        .strikethrough(item.done, color: Theme.inkSecondary)
                    if let due = dueText(item) {
                        Text(due)
                            .font(.system(size: 13))
                            .foregroundStyle(isOverdue(item) ? Color.red.opacity(0.85) : Theme.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .blockActivationControl()
        .sensoryFeedback(EmblemHaptic.toggle, trigger: item.done)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.done ? "Completed" : "Not completed")
        .accessibilityIdentifier("reminder-row")
    }

    private func draftRow(_ draft: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.inkSecondary.opacity(0.7))
            Text(draft)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                guard blockInteraction.allowsActivation,
                      let saved = RemindersService.shared.add(
                        draft, list: block.list, dueToday: block.scope == .today)
                else { return }
                drafts.removeAll { $0 == draft }
                items.append(saved)
            } label: {
                Text("Add")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 11)
                    .frame(minWidth: 56, minHeight: 34)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.rowButtonStroke, lineWidth: 1.2))
            }
            .buttonStyle(.pressable)
            .blockActivationControl()
            .accessibilityLabel("Add reminder \(draft)")
            .accessibilityIdentifier("reminder-add")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
    }

    private func isOverdue(_ item: RemindersService.Item) -> Bool {
        guard let due = item.due, !item.done else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }

    private func dueText(_ item: RemindersService.Item) -> String? {
        guard let due = item.due else { return block.list == nil ? item.list : nil }
        let calendar = Calendar.current
        let hasTime = calendar.component(.hour, from: due) != 0 || calendar.component(.minute, from: due) != 0
        if calendar.isDateInToday(due) {
            return hasTime ? due.formatted(date: .omitted, time: .shortened) : "Today"
        }
        return due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
