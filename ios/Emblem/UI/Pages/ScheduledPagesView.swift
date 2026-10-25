import SwiftUI
import EmblemCore

struct ScheduledPagesView: View {
    let agents: AgentsStore
    let memoryEnabled: Bool
    var onOpenResult: (String) -> Void = { _ in }

    @State private var editing: ScheduledPageEditor.Target?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(AppInfo.name) prepares a page for you at the time you choose, so it's ready when you open the app.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SettingsMetrics.rowInset)
                    .padding(.bottom, 22)

                if agents.isLoading && !agents.hasLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    SettingsCard {
                        dailyRow
                        ForEach(agents.automations) { agent in
                            SettingsHairline()
                            pageRow(agent)
                        }
                        SettingsHairline()
                        Button { editing = .new } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("New scheduled page")
                                    .font(SettingsMetrics.titleFont)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, SettingsMetrics.rowInset)
                            .frame(minHeight: SettingsMetrics.rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("New scheduled page")
                    }
                }

                if let error = agents.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.negative)
                        .padding(.top, 14)
                        .padding(.horizontal, SettingsMetrics.rowInset)
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, 30)
            .padding(.bottom, 60)
        }
        .background(Theme.background)
        .navigationTitle("Scheduled pages")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await agents.refresh()
        }
        .task(id: pollingKey) {
            while !Task.isCancelled, !pollingKey.isEmpty {
                try? await Task.sleep(for: .seconds(2))
                await agents.refresh()
            }
        }
        .sheet(item: $editing) { target in
            NavigationStack {
                ScheduledPageEditor(
                    target: target,
                    agents: agents,
                    memoryEnabled: memoryEnabled,
                    onOpenResult: { id in
                        editing = nil
                        onOpenResult(id)
                    })
            }
            .presentationDetents([.large])
            .presentationCornerRadius(32)
        }
    }

    private var dailyRow: some View {
        let agent = agents.dailyBrief
        let times = agent?.scheduledTimes ?? []
        let on = agent?.enabled == true && !times.isEmpty
        return row(
            title: "Daily update",
            subtitle: subtitle(for: agent, fallback: on
                ? "Every day at \(listed(times))"
                : "Your day, calendar and messages in one page"),
            isOn: Binding(
                get: { on },
                set: { enable in
                    Task {
                        if let agent, !times.isEmpty {
                            await agents.setEnabled(agent, enabled: enable)
                        } else if enable {
                            await agents.configureDailyBrief(
                                times: [.init(hour: 8, minute: 0)], memory: memoryEnabled)
                        }
                    }
                }),
            target: .daily)
    }

    private func pageRow(_ agent: AgentsStore.Agent) -> some View {
        row(
            title: agent.title,
            subtitle: subtitle(for: agent, fallback: ScheduledPageEditor.Repeat.summary(agent.schedule)),
            isOn: Binding(
                get: { agent.enabled },
                set: { enable in Task { await agents.setEnabled(agent, enabled: enable) } }),
            target: .page(agent.id))
    }

    private func row(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        target: ScheduledPageEditor.Target
    ) -> some View {
        HStack(spacing: 12) {
            Button { editing = target } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(SettingsMetrics.titleFont)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(SettingsMetrics.subtitleFont)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(title)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .accentTint(Theme.toggleTint)
                .disabled(agents.busyAction != nil)
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 12)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }

    private func subtitle(for agent: AgentsStore.Agent?, fallback: String) -> String {
        guard let agent else { return fallback }
        if let run = agent.latestRun, run.status == "queued" || run.status == "running" {
            return "Preparing now…"
        }
        if !agent.enabled, !agent.scheduledTimes.isEmpty { return "Off · \(fallback)" }
        return fallback
    }

    private func listed(_ times: [AgentsStore.Agent.BriefingTime]) -> String {
        times.map(ScheduledPageEditor.format).formatted(.list(type: .and))
    }

    private var pollingKey: String {
        agents.agents.compactMap { agent in
            guard let run = agent.latestRun, run.status == "queued" || run.status == "running"
            else { return nil }
            return run.runId
        }.joined(separator: "|")
    }
}

struct ScheduledPageEditor: View {
    enum Target: Identifiable, Hashable {
        case new, daily, page(String)
        var id: Self { self }
    }

    enum Repeat: String, CaseIterable, Identifiable {
        case everyDay = "Every day"
        case weekdays = "Weekdays"
        case weekends = "Weekends"
        case custom = "Same days"
        var id: Self { self }

        func weekdays(keeping original: [Int]?) -> [Int]? {
            switch self {
            case .everyDay: nil
            case .weekdays: [1, 2, 3, 4, 5]
            case .weekends: [6, 7]
            case .custom: original
            }
        }

        init(_ weekdays: [Int]?) {
            switch weekdays ?? [] {
            case []: self = .everyDay
            case [1, 2, 3, 4, 5]: self = .weekdays
            case [6, 7]: self = .weekends
            default: self = .custom
            }
        }

        static func dayNames(_ days: [Int]) -> String {
            days.filter { (1...7).contains($0) }
                .map { Calendar.current.shortWeekdaySymbols[$0 % 7] }
                .formatted(.list(type: .and))
        }

        static func summary(_ schedule: AgentsStore.Agent.Schedule?) -> String {
            guard let schedule else { return "Not scheduled" }
            let time = format(.init(hour: schedule.hour, minute: schedule.minute))
            let days = schedule.weekdays ?? []
            switch days {
            case []: return "Every day at \(time)"
            case [1, 2, 3, 4, 5]: return "Weekdays at \(time)"
            case [6, 7]: return "Weekends at \(time)"
            default: return "\(dayNames(days)) at \(time)"
            }
        }
    }

    let target: Target
    let agents: AgentsStore
    let memoryEnabled: Bool
    var onOpenResult: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var time = ScheduledPageEditor.date(hour: 8, minute: 0)
    @State private var repeatRule = Repeat.everyDay
    @State private var times: [EditableTime] = []
    @State private var confirmDelete = false
    @State private var seeded = false

    private var agent: AgentsStore.Agent? {
        switch target {
        case .new: nil
        case .daily: agents.dailyBrief
        case .page(let id): agents.automations.first { $0.id == id }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if target == .daily {
                    Text("Your calendar, connected messages and the weather, ready at each time below.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, SettingsMetrics.rowInset)
                        .padding(.bottom, 22)
                    dailyTimes
                } else {
                    SettingsSectionLabel(title: "What should be ready")
                    SettingsCard {
                        TextField("A short roundup of today's AI news", text: $prompt, axis: .vertical)
                            .lineLimit(2...6)
                            .font(SettingsMetrics.titleFont)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, SettingsMetrics.rowInset)
                            .padding(.vertical, 15)
                            .accessibilityIdentifier("scheduled-page-prompt")
                    }
                    SettingsSectionLabel(title: "When")
                        .padding(.top, SettingsMetrics.sectionGap)
                    SettingsCard {
                        HStack {
                            Text("Time").font(SettingsMetrics.titleFont).foregroundStyle(Theme.ink)
                            Spacer()
                            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        .padding(.horizontal, SettingsMetrics.rowInset)
                        .frame(minHeight: SettingsMetrics.rowHeight)
                        SettingsHairline()
                        HStack {
                            Text("Repeat").font(SettingsMetrics.titleFont).foregroundStyle(Theme.ink)
                            Spacer()
                            Picker("Repeat", selection: $repeatRule) {
                                ForEach(repeatOptions) { rule in
                                    Text(rule == .custom ? Repeat.dayNames(originalWeekdays ?? []) : rule.rawValue)
                                        .tag(rule)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.inkSecondary)
                        }
                        .padding(.leading, SettingsMetrics.rowInset)
                        .padding(.trailing, 8)
                        .frame(minHeight: SettingsMetrics.rowHeight)
                    }
                }

                if let agent {
                    actions(agent)
                        .padding(.top, SettingsMetrics.sectionGap)
                }

                if let error = validationError ?? agents.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.negative)
                        .padding(.top, 14)
                        .padding(.horizontal, SettingsMetrics.rowInset)
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, 30)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(target == .new ? "Add" : "Save") { Task { await save() } }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .onAppear(perform: seed)
        .alert("Delete this scheduled page?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                guard let agent else { return }
                Task {
                    await agents.delete(agent)
                    if agents.errorMessage == nil { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It stops being prepared, and its past pages are removed.")
        }
    }

    private var originalWeekdays: [Int]? { agent?.schedule?.weekdays }

    private var repeatOptions: [Repeat] {
        Repeat(originalWeekdays) == .custom ? Repeat.allCases : Repeat.allCases.filter { $0 != .custom }
    }

    private var title: String {
        switch target {
        case .new: "New scheduled page"
        case .daily: "Daily update"
        case .page: "Scheduled page"
        }
    }

    private var dailyTimes: some View {
        SettingsCard {
            ForEach($times) { $item in
                HStack {
                    DatePicker("Update time", selection: $item.date, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer()
                    if times.count > 1 {
                        Button {
                            withAnimation(.smooth(duration: 0.22)) { times.removeAll { $0.id == item.id } }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.inkSecondary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove this time")
                    }
                }
                .padding(.leading, SettingsMetrics.rowInset)
                .padding(.trailing, 8)
                .frame(minHeight: SettingsMetrics.rowHeight)
                SettingsHairline()
            }
            Button(action: addTime) {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    Text("Add a time").font(SettingsMetrics.titleFont)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, SettingsMetrics.rowInset)
                .frame(minHeight: SettingsMetrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(times.count >= 8)
            .opacity(times.count >= 8 ? 0.4 : 1)
        }
    }

    private func actions(_ agent: AgentsStore.Agent) -> some View {
        let live = agent.latestRun.flatMap { $0.status == "queued" || $0.status == "running" ? $0 : nil }
        return SettingsCard {
            if let live {
                actionRow("Stop preparing") { await agents.cancel(live) }
            } else {
                actionRow("Prepare now") {
                    await agents.dispatch(agent, retry: agent.latestRun?.status == "failed")
                }
            }
            if agent.latestRun?.status == "completed" {
                SettingsHairline()
                actionRow("Open latest page") { onOpenResult(agent.id) }
            }
            if target != .daily {
                SettingsHairline()
                actionRow("Delete", destructive: true) { confirmDelete = true }
            }
        }
        .disabled(agents.busyAction != nil)
    }

    private func actionRow(
        _ title: String,
        destructive: Bool = false,
        action: @escaping () async -> Void
    ) -> some View {
        Button { Task { await action() } } label: {
            Text(title)
                .font(SettingsMetrics.titleFont)
                .foregroundStyle(destructive ? Theme.negative : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowHeight, alignment: .leading)
                .padding(.horizontal, SettingsMetrics.rowInset)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func seed() {
        guard !seeded else { return }
        seeded = true
        if target == .daily {
            let scheduled = agent?.scheduledTimes ?? []
            times = (scheduled.isEmpty ? [.init(hour: 8, minute: 0)] : scheduled)
                .map { EditableTime(date: Self.date(hour: $0.hour, minute: $0.minute)) }
        } else if let agent, let schedule = agent.schedule {
            prompt = agent.prompt
            time = Self.date(hour: schedule.hour, minute: schedule.minute)
            repeatRule = Repeat(schedule.weekdays)
        }
    }

    private func addTime() {
        let last = times.last?.date ?? Self.date(hour: 8, minute: 0)
        let next = Calendar.current.date(byAdding: .hour, value: 4, to: last) ?? last
        withAnimation(.smooth(duration: 0.22)) { times.append(EditableTime(date: next)) }
    }

    private var trimmedPrompt: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var validationError: String? {
        guard target == .daily else { return nil }
        let minutes = times.map { Self.minuteOfDay($0.date) }
        return Set(minutes).count == minutes.count ? nil : "Choose a different time for each update."
    }

    private var canSave: Bool {
        guard agents.busyAction == nil, validationError == nil else { return false }
        switch target {
        case .daily:
            return times.map { Self.minuteOfDay($0.date) }
                != (agent?.scheduledTimes ?? []).map { $0.hour * 60 + $0.minute }
        case .new:
            return !trimmedPrompt.isEmpty
        case .page:
            guard let agent, let schedule = agent.schedule, !trimmedPrompt.isEmpty else { return false }
            return trimmedPrompt != agent.prompt
                || Self.minuteOfDay(time) != schedule.hour * 60 + schedule.minute
                || repeatRule != Repeat(schedule.weekdays)
        }
    }

    private func save() async {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = parts.hour ?? 8, minute = parts.minute ?? 0
        switch target {
        case .daily:
            let scheduled = times
                .map { Self.minuteOfDay($0.date) }
                .sorted()
                .map { AgentsStore.Agent.BriefingTime(hour: $0 / 60, minute: $0 % 60) }
            await agents.configureDailyBrief(times: scheduled, memory: memoryEnabled)
        case .new:
            await agents.create(prompt: trimmedPrompt, hour: hour, minute: minute,
                                weekdays: repeatRule.weekdays(keeping: nil))
        case .page:
            guard let agent else { return }
            await agents.replace(agent, prompt: trimmedPrompt, hour: hour, minute: minute,
                                 weekdays: repeatRule.weekdays(keeping: originalWeekdays))
        }
        if agents.errorMessage == nil { dismiss() }
    }

    nonisolated static func format(_ time: AgentsStore.Agent.BriefingTime) -> String {
        date(hour: time.hour, minute: time.minute).formatted(date: .omitted, time: .shortened)
    }

    nonisolated private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    private static func minuteOfDay(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private struct EditableTime: Identifiable {
        let id = UUID()
        var date: Date
    }
}
