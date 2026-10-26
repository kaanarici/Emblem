import SwiftUI
import EmblemCore

struct InferenceSettingsView: View {
    let userID: String

    @State private var apiKey = ""
    @State private var saved = false
    @State private var saveFailed = false
    @State private var showsCustomKey = false
    @State private var selected: LocalInferenceCredential.Model = .qwen
    @State private var choice: UserInferenceCredentials.Choice = .emblem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Choose a model and start chatting. Emblem provides access; no API key is needed.")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(3)

                managedModelCard
                    .padding(.top, 24)

                if saved && choice == .custom {
                    Text("Your own \(selected.keyName) key is active.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.top, 12)
                        .padding(.horizontal, 6)
                }

                customKeyCard
                    .padding(.top, 30)

                Text("Your key stays in this iPhone's Keychain and is sent only with chats. Agents continue on Emblem's managed runtime.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(2)
                    .padding(.top, 12)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, 26)
            .padding(.bottom, 60)
        }
        .background(Theme.background)
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            choice = UserInferenceCredentials.choice(userID: userID)
            guard !saved,
                  let credential = UserInferenceCredentials.load(userID: userID)
            else { return }
            apiKey = credential.apiKey
            selected = credential.model
            saved = true
            showsCustomKey = true
        }
        .alert("Key wasn't saved", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your existing setting is unchanged.")
        }
    }

    private var managedModelCard: some View {
        VStack(spacing: 0) {
            ForEach([UserInferenceCredentials.Choice.emblem, .mercury, .luna], id: \.self) { option in
                if option != .emblem { SettingsHairline() }
                Button {
                    choose(option)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.model?.name ?? "Emblem")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Text(option.model == nil ? "Default · managed by Emblem" : "OpenRouter · managed by Emblem")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer(minLength: 12)
                        if choice == option && OnDeviceModel.selection() == .emblem {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.accentDark)
                        }
                    }
                    .padding(.horizontal, SettingsMetrics.rowInset)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("managed-model-\(option.rawValue)")
                .accessibilityAddTraits(choice == option && OnDeviceModel.selection() == .emblem ? [.isSelected] : [])
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous))
    }

    private func choose(_ option: UserInferenceCredentials.Choice) {
        UserDefaults.standard.set("emblem", forKey: "apple.model")
        choice = option
        UserInferenceCredentials.choose(option, userID: userID)
    }

    private var modelCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(LocalInferenceCredential.Model.allCases.enumerated()),
                    id: \.element.id) { index, model in
                if index > 0 { SettingsHairline() }
                modelRow(model)
            }
        }
        .background(
            Theme.surface,
            in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous))
    }

    private func modelRow(_ model: LocalInferenceCredential.Model) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) {
                selected = model
                showsCustomKey = true
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.ownKeyName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text(model.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 12)
                if selected == model {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentDark)
                }
            }
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(model.ownKeyName), \(model.detail)")
        .accessibilityAddTraits(selected == model ? [.isSelected] : [])
    }

    private var customKeyCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.3)) { showsCustomKey.toggle() }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Use your own key")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Text(choice == .custom && saved ? "Your key is active" : "Optional")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .rotationEffect(.degrees(showsCustomKey ? 180 : 0))
                }
                .padding(.horizontal, SettingsMetrics.rowInset)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsCustomKey {
                SettingsHairline()
                modelCard

                SecureField("API key", text: $apiKey)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, SettingsMetrics.rowInset)
                    .frame(height: 58)

                Button(saved ? "Save changes" : "Use this key", action: save)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.accentDark, in: Capsule())
                    .buttonStyle(.pressable)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, saved ? 0 : 16)

                if saved {
                    Button("Remove key", role: .destructive) {
                        UserInferenceCredentials.remove(userID: userID)
                        apiKey = ""
                        saved = false
                        selected = .qwen
                        if choice == .custom { choose(.emblem) }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(
            Theme.surface,
            in: RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous))
    }

    private func save() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        let didSave = UserInferenceCredentials.save(
            .init(model: selected, apiKey: key),
            userID: userID)
        if didSave {
            saved = true
            choose(.custom)
        }
        saveFailed = !didSave
    }
}
