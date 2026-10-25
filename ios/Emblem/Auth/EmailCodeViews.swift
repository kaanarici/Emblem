import SwiftUI

struct EmailEntryView: View {
    var isBusy: Bool
    var errorMessage: String?
    var onBack: () -> Void
    var onSubmit: (String) -> Void

    @State private var email = ""
    @FocusState private var focused: Bool

    var body: some View {
        AuthStepScaffold(
            title: "Sign in with email",
            subtitle: "We'll email you a 6-digit code.",
            errorMessage: errorMessage,
            isBusy: isBusy,
            continueEnabled: canSubmit,
            onBack: onBack,
            onContinue: submit
        ) {
            TextField("Email address", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .font(.system(size: 19))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20)
                .frame(height: 58)
                .modifier(OnboardingGlass(shape: RoundedRectangle(cornerRadius: 20)))
                .onAppear { focused = true }
                .submitLabel(.continue)
                .onSubmit(submit)
        }
    }

    private var canSubmit: Bool {
        email.contains("@") && email.contains(".")
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).contains(
                where: \.isWhitespace)
    }

    private func submit() {
        guard canSubmit, !isBusy else { return }
        onSubmit(email.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct CodeEntryView: View {
    var email: String
    var isBusy: Bool
    var errorMessage: String?
    var onBack: () -> Void
    var onSubmit: (String) -> Void

    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        AuthStepScaffold(
            title: "Enter your code",
            subtitle: "We sent it to \(email).",
            errorMessage: errorMessage,
            isBusy: isBusy,
            continueEnabled: code.count == 6,
            onBack: onBack,
            onContinue: { onSubmit(code) }
        ) {
            TextField("6-digit code", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($focused)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .frame(height: 58)
                .modifier(OnboardingGlass(shape: RoundedRectangle(cornerRadius: 20)))
                .onAppear { focused = true }
                .onChange(of: code) { _, value in
                    code = String(value.filter(\.isNumber).prefix(6))
                    if code.count == 6, !isBusy { onSubmit(code) }
                }
        }
    }
}

private struct AuthStepScaffold<Content: View>: View {
    var title: String
    var subtitle: String
    var errorMessage: String?
    var isBusy: Bool
    var continueEnabled: Bool
    var onBack: () -> Void
    var onContinue: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            OnboardingBackdrop().ignoresSafeArea().allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("auth-back")
                .disabled(isBusy)
                .padding(.top, 4)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.system(.largeTitle, weight: .semibold))
                            .tracking(-0.8)
                            .foregroundStyle(Theme.ink)
                            .padding(.top, 28)

                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineSpacing(4)
                            .padding(.top, 12)

                        content
                            .disabled(isBusy)
                            .padding(.top, 32)
                            .padding(.horizontal, 2)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(Theme.negative)
                                .padding(.top, 16)
                                .accessibilityIdentifier("auth-error")
                        }
                    }
                    .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)

                OnboardingPrimaryButton(title: "Continue", isBusy: isBusy, action: onContinue)
                    .accessibilityIdentifier("auth-continue")
                    .disabled(!continueEnabled || isBusy)
                    .opacity(continueEnabled ? 1 : 0.45)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 24)
        }
        .animation(.easeOut(duration: 0.2), value: errorMessage)
    }
}
