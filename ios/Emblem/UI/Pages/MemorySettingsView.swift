import SwiftUI
import EmblemCore

struct MemorySettingsView: View {
    @Environment(AuthStore.self) private var auth

    @State private var memory = MemoryStore()
    @AppStorage("memory.enabled") private var memoryEnabled = true

    @State private var nickname = ""
    @State private var occupation = ""
    @State private var about = ""
    @State private var instructions = ""
    @State private var draftSeeded = false
    @State private var showInstructionsEditor = false
    @State private var showSaved = false

    static let fieldLimit = 200
    static let instructionsLimit = 1500

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if auth.isSignedIn {
                    SettingsCard {
                        SettingsToggleRow(title: "Memory", isOn: $memoryEnabled)
                        SettingsHairline()
                        Button { showSaved = true } label: {
                            SettingsRowLabel(
                                title: "Saved memories",
                                value: memory.hasLoaded ? "\(memory.memories.count)" : nil)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("Saved memories")
                    }
                    SettingsCaption(text: "When memory is on, \(AppInfo.name) saves what you ask it to remember and preferences you mention that will last, and uses them when they help. Turning it off stops both; saved memories stay until you delete them.")

                    SettingsSectionLabel(title: "About you")
                        .padding(.top, SettingsMetrics.sectionGap)
                    SettingsCard {
                        field("Nickname", prompt: "What \(AppInfo.name) should call you", text: $nickname)
                        SettingsHairline()
                        field("Occupation", prompt: "Engineer, student, etc.", text: $occupation)
                        SettingsHairline()
                        field("More about you", prompt: "Interests, values or preferences", text: $about, axis: .vertical)
                        SettingsHairline()
                        Button { showInstructionsEditor = true } label: {
                            SettingsRowLabel(title: "Custom instructions", value: normalized(instructions) == nil ? nil : "On")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("Custom instructions")
                    }
                    SettingsCaption(text: "Your profile and custom instructions go with every request to your server, even when memory is off.")

                    if let error = memory.errorMessage {
                        MemoryError(text: error)
                    }
                } else {
                    MemoryEmptyState(
                        symbol: "person.crop.circle",
                        title: "Sign in to use memory",
                        detail: "Memory, your profile and custom instructions are saved to your account.")
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, 30)
            .padding(.bottom, 60)
        }
        .background(Theme.background)
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if auth.isSignedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    saveButton
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .navigationDestination(isPresented: $showSaved) {
            SavedMemoriesView(memory: memory, memoryEnabled: $memoryEnabled)
        }
        .task {
            guard auth.isSignedIn else { return }
            await memory.refresh()
            seedDraftIfPristine()
        }
        .sheet(isPresented: $showInstructionsEditor) {
            CustomInstructionsEditor(text: instructions) { updated in
                instructions = updated
                var profile = memory.profile
                profile.instructions = normalized(updated)
                Task { _ = await memory.saveProfile(profile) }
            }
        }
        .onChange(of: memoryEnabled) { _, enabled in
            guard auth.isSignedIn, memory.hasLoaded else { return }
            var profile = memory.profile
            guard profile.memoryEnabled != enabled else { return }
            profile.memoryEnabled = enabled
            Task { _ = await memory.saveProfile(profile) }
        }
    }

    private var draftProfile: MemoryStore.Profile {
        .init(
            nickname: normalized(nickname),
            occupation: normalized(occupation),
            about: normalized(about),
            instructions: memory.profile.instructions,
            memoryEnabled: memory.profile.memoryEnabled)
    }

    private var isDirty: Bool { draftProfile != memory.profile }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func seedDraftIfPristine() {
        guard !draftSeeded, memory.hasLoaded else { return }
        draftSeeded = true
        nickname = memory.profile.nickname ?? ""
        occupation = memory.profile.occupation ?? ""
        about = memory.profile.about ?? ""
        instructions = memory.profile.instructions ?? ""
        if let stored = memory.profile.memoryEnabled {
            memoryEnabled = stored
        }
    }

    private var saveButton: some View {
        Button {
            Task { _ = await memory.saveProfile(draftProfile) }
        } label: {
            if memory.isBusy {
                ProgressView()
                    .frame(width: 58, height: 44)
            } else {
                Text("Save")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(isDirty ? Theme.ink : Theme.inkSecondary)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .contentShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(!isDirty || memory.isBusy)
        .accessibilityLabel("Save")
    }

    private func field(
        _ title: String,
        prompt: String,
        text: Binding<String>,
        axis: Axis = .horizontal
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SettingsMetrics.subtitleFont)
                .foregroundStyle(Theme.inkSecondary)
            TextField(title, text: text, prompt: Text(prompt), axis: axis)
                .lineLimit(axis == .vertical ? 1...4 : 1...1)
                .font(SettingsMetrics.titleFont)
                .foregroundStyle(Theme.ink)
                .onChange(of: text.wrappedValue) { _, value in
                    if value.count > Self.fieldLimit { text.wrappedValue = String(value.prefix(Self.fieldLimit)) }
                }
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowHeight, alignment: .leading)
    }
}

private struct MemoryError: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SettingsMetrics.subtitleFont)
            .foregroundStyle(Theme.negative)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.top, 14)
    }
}

private struct MemoryEmptyState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(Theme.inkSecondary)
            Text(title)
                .font(Theme.bodySecondary())
                .foregroundStyle(Theme.inkSecondary)
            Text(detail)
                .font(SettingsMetrics.subtitleFont)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }
}

struct SavedMemoriesView: View {
    let memory: MemoryStore
    @Binding var memoryEnabled: Bool

    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !memory.hasLoaded && memory.errorMessage == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                } else if memory.hasLoaded && memory.memories.isEmpty {
                    MemoryEmptyState(
                        symbol: "bookmark",
                        title: "No saved memories",
                        detail: memoryEnabled
                            ? "Ask \(AppInfo.name) to remember something, like a preference, and it appears here."
                            : "Memory is off, so nothing new is saved.")
                } else if memory.hasLoaded {
                    SettingsCard {
                        ForEach(Array(memory.memories.enumerated()), id: \.element) { index, item in
                            if index > 0 { SettingsHairline() }
                            row(item)
                        }
                    }
                    SettingsCaption(text: "Touch and hold a memory to forget it. \(AppInfo.name) keeps the 40 most recent\(memoryEnabled ? "" : "; memory is off, so nothing new is saved").")

                    SettingsCard {
                        SettingsDestructiveRow(title: "Delete all memories") { confirmDelete = true }
                    }
                    .padding(.top, SettingsMetrics.sectionGap)
                }
                if let error = memory.errorMessage {
                    MemoryError(text: error)
                }
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, 30)
            .padding(.bottom, 60)
        }
        .background(Theme.background)
        .navigationTitle("Saved memories")
        .navigationBarTitleDisplayMode(.inline)
        .task { await memory.refresh() }
        .alert("Delete all memories?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    if await memory.clearAll() {
                        memoryEnabled = false
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved memory and turns memory off. Your profile and custom instructions stay.")
        }
    }

    private func row(_ item: String) -> some View {
        Text(item)
            .font(SettingsMetrics.titleFont)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowHeight, alignment: .leading)
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .contextMenu {
                Button(role: .destructive) {
                    Task { await memory.forget(item) }
                } label: {
                    Label("Forget", systemImage: "trash")
                }
            }
            .accessibilityAction(named: "Forget") {
                Task { await memory.forget(item) }
            }
    }
}

struct CustomInstructionsEditor: View {
    @State var text: String
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Custom instructions")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 28)
                .padding(.bottom, 18)

            TextEditor(text: $text)
                .focused($focused)
                .font(.system(size: 18))
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 24)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("How \(AppInfo.name) should answer you, every time")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(.horizontal, 29)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: text) { _, value in
                    let limit = MemorySettingsView.instructionsLimit
                    if value.count > limit { text = String(value.prefix(limit)) }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, alignment: .trailing) {
            Button {
                onConfirm(text)
                dismiss()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 56, height: 56)
                    .background(Theme.accentDark, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.pressable)
            .padding(.trailing, 24)
            .padding(.bottom, 12)
            .accessibilityLabel("Done")
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(32)
        .onAppear { focused = true }
    }
}
