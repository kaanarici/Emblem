import SwiftUI

struct CalendarDraft: Identifiable, Equatable {
    enum Kind: Hashable { case event, todo }

    var id = UUID()
    var kind: Kind
    var title: String
    var start: Date
    var minutes = 60
    var timed = true

    var end: Date { start.addingTimeInterval(Double(minutes * 60)) }

    static func parse(_ text: String, now: Date, calendar: Calendar) -> CalendarDraft {
        var title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let todoPrefix = ["remind me to ", "remind me ", "to-do ", "todo "].first { title.lowercased().hasPrefix($0) }
        if let todoPrefix { title.removeFirst(todoPrefix.count) }
        var minutes = 60
        if let match = title.firstMatch(of: /\s+for\s+(\d+)\s*(min|mins|minutes|h|hr|hrs|hour|hours)\b/.ignoresCase()) {
            let value = Int(match.output.1) ?? 60
            minutes = match.output.2.lowercased().hasPrefix("h") ? value * 60 : value
            title.removeSubrange(match.range)
        }
        var start: Date?
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        if let found = detector?.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
           let date = found.date, let range = Range(found.range, in: title) {
            start = date
            title.removeSubrange(range)
        } else if let match = title.firstMatch(of: /\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b/.ignoresCase()),
                  let hour = Int(match.output.1), hour < 24 {
            let minute = match.output.2.flatMap { Int($0) } ?? 0
            let meridiem = match.output.3?.lowercased()
            let clock = meridiem == nil ? (hour < 8 ? hour + 12 : hour) : hour % 12 + (meridiem == "pm" ? 12 : 0)
            if let today = calendar.date(bySettingHour: clock, minute: minute, second: 0, of: now) {
                start = today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
            }
            title.removeSubrange(match.range)
        }
        title = title.replacing(/\s+(at|on|by)\s*$/.ignoresCase(), with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let first = title.first { title = first.uppercased() + title.dropFirst() }
        let nextHour = calendar.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
        return CalendarDraft(kind: todoPrefix == nil ? .event : .todo, title: title, start: start ?? nextHour,
                             minutes: minutes, timed: start != nil || todoPrefix == nil)
    }

    func when(calendar: Calendar, now: Date) -> String {
        let day = calendar.isDate(start, inSameDayAs: now) ? "Today"
            : calendar.isDate(start, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now) ?? now) ? "Tomorrow"
            : CalendarClock.text(start, calendar: calendar, format: "EEEE, MMM d")
        guard timed else { return day }
        return day + " · " + (kind == .event ? CalendarClock.range(start, end, calendar: calendar)
                                              : CalendarClock.short(start, calendar: calendar))
    }
}

struct CalendarAddCard: View {
    @Bindable var feed: CalendarAgendaFeed
    let calendar: Calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var editing = false
    @State private var saving = false

    var body: some View {
        if let draft = feed.draft {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Kind", selection: Binding(get: { feed.draft?.kind ?? .event },
                                                      set: { kind in withAnimation(.smooth(duration: 0.25)) { feed.draft?.kind = kind } })) {
                        Text("Event").tag(CalendarDraft.Kind.event)
                        Text("To-do").tag(CalendarDraft.Kind.todo)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 168)
                    .accessibilityIdentifier("calendar-draft-kind")
                    Spacer(minLength: 8)
                    Button { feed.cancelDraft() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(width: 28, height: 28)
                            .background(Theme.chip, in: Circle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Cancel")
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField(draft.kind == .event ? "New event" : "New to-do", text: Binding(
                        get: { feed.draft?.title ?? "" }, set: { feed.draft?.title = $0 }))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .submitLabel(.done)
                        .accessibilityIdentifier("calendar-draft-title")
                    Label(draft.when(calendar: calendar, now: feed.now),
                          systemImage: draft.kind == .event ? "calendar" : "checklist")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkSecondary)
                        .labelStyle(CalendarInlineLabelStyle())
                }
                if let error = feed.writeError {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(error).font(.system(size: 15)).foregroundStyle(Theme.negative)
                        Button("Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .buttonStyle(.pressable)
                    }
                    .transition(.opacity)
                }
                HStack(spacing: 8) {
                    Text(destination(draft))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CalendarPill(title: "Edit") { editing = true }
                    CalendarPill(title: "Save", primary: true) {
                        guard !saving else { return }
                        saving = true
                        Task {
                            await feed.save()
                            saving = false
                        }
                    }
                    .accessibilityIdentifier("calendar-draft-save")
                }
            }
            .padding(16)
            .background(Theme.surface, in: shape)
            .overlay { shape.strokeBorder(CalendarMetrics.hairline(colorScheme), lineWidth: 0.5) }
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            .sheet(isPresented: $editing) {
                CalendarDraftEditor(feed: feed)
                    .presentationDetents([.medium])
            }
        }
    }

    private func destination(_ draft: CalendarDraft) -> String {
        guard draft.kind == .event else { return "Saves to Reminders" }
        return feed.device.defaultCalendarTitle.map { "Saves to \($0)" } ?? "Saves to Calendar on this iPhone"
    }
}

private struct CalendarDraftEditor: View {
    @Bindable var feed: CalendarAgendaFeed
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: Binding(get: { feed.draft?.title ?? "" }, set: { feed.draft?.title = $0 }))
                DatePicker("Starts", selection: Binding(get: { feed.draft?.start ?? .now },
                                                        set: { feed.draft?.start = $0; feed.draft?.timed = true }))
                if feed.draft?.kind == .event {
                    Picker("Duration", selection: Binding(get: { feed.draft?.minutes ?? 60 }, set: { feed.draft?.minutes = $0 })) {
                        ForEach([15, 30, 45, 60, 90, 120, 180], id: \.self) { Text(CalendarClock.duration($0)).tag($0) }
                    }
                }
            }
            .navigationTitle(feed.draft?.kind == .todo ? "To-do" : "Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct CalendarInlineLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 13, weight: .medium))
            configuration.title
        }
    }
}

struct CalendarPill: View {
    let title: String
    var image: String?
    var primary = false
    let action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let image {
                    Image(image).resizable().frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(primary ? accent.glyph : Theme.ink)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background {
                if primary { AnodizedSurface(shape: Capsule()) } else { Capsule().fill(Theme.chip) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }
}

struct CalendarDockAccessory: View {
    @Bindable var feed: CalendarAgendaFeed
    let calendar: Calendar
    let day: Date
    let onAsk: (String) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let result = feed.result {
                VStack(spacing: 14) {
                    Text(sentence(result.draft))
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        let todo = result.draft.kind == .todo
                        CalendarPill(title: todo ? "Open in Reminders" : "Open in Calendar",
                                     image: todo ? "connector-applereminders" : "connector-applecalendar") {
                            let link = todo ? "x-apple-reminderkit://"
                                : "calshow:\(Int(result.draft.start.timeIntervalSinceReferenceDate))"
                            if let url = URL(string: link) { openURL(url) }
                        }
                        if result.identifier != nil { CalendarPill(title: "Undo") { feed.undo() } }
                    }
                }
                .padding(.horizontal, CalendarMetrics.edge)
                .transition(.opacity.combined(with: .offset(y: 8)))
            } else if feed.draft == nil {
                HStack(spacing: 8) {
                    chip("Add event", image: "connector-applecalendar") { feed.blank(.event, on: day) }
                    chip("Add to-do", image: "connector-applereminders") { feed.blank(.todo, on: day) }
                    chip("Find a free hour", symbol: "clock") { onAsk("Find me a free hour this week") }
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: feed.result)
        .task(id: feed.result?.draft.id) {
            guard let id = feed.result?.draft.id, (try? await Task.sleep(for: .seconds(8))) != nil,
                  feed.result?.draft.id == id else { return }
            feed.result = nil
        }
    }

    private func sentence(_ draft: CalendarDraft) -> AttributedString {
        var value = AttributedString("Added ")
        var title = AttributedString(draft.title.isEmpty ? (draft.kind == .event ? "New event" : "New to-do") : draft.title)
        title.foregroundColor = Theme.ink
        title.font = .system(size: 17, weight: .semibold)
        value += title
        let day = draft.when(calendar: calendar, now: feed.now).components(separatedBy: " · ")
        value += AttributedString(" " + (day.first ?? "").lowercased())
        if draft.timed {
            var time = AttributedString(CalendarClock.spoken(draft.start, calendar: calendar))
            time.foregroundColor = Theme.ink
            time.font = .system(size: 17, weight: .semibold)
            value += AttributedString(" at ") + time
        }
        return value
    }

    private func chip(_ title: String, image: String? = nil, symbol: String? = nil,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let image {
                    Image(image).resizable().frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSecondary)
                }
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Theme.surface, in: Capsule())
        }
        .buttonStyle(.pressable)
    }
}
