import SwiftUI

struct SignInView: View {
    var isBusy: Bool
    var errorMessage: String?
    var onGoogle: () -> Void
    var onApple: () -> Void
    var onGuest: (String) -> Void
    var onEmail: () -> Void
    var onClose: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var legalDoc: LegalDoc?
    @State private var naming = false
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            Theme.responsePaper.ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    if naming {
                        Button { setNaming(false) } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .medium))
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")
                        .accessibilityIdentifier("auth-back")
                    } else if let onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .medium))
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                    Spacer()
                }
                .foregroundStyle(Theme.ink)
                .frame(height: 44)
                .padding(.horizontal, 20)
                .padding(.top, 4)

                GeometryReader { geometry in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            if naming { Color.clear.frame(height: 36) } else { Spacer(minLength: 36) }
                            VStack(spacing: 0) {
                                EmblemLogo(size: 64)
                                    .padding(.bottom, 32)
                                ZStack {
                                    if naming {
                                        VStack(spacing: 8) {
                                            Text(greeting)
                                                .font(.largeTitle)
                                                .tracking(-0.4)
                                                .contentTransition(.interpolate)
                                                .animation(.snappy(duration: 0.25), value: name)
                                                .accessibilityIdentifier("guest-greeting")
                                            Text("What's your first name?")
                                                .font(Theme.intro())
                                                .foregroundStyle(Theme.inkSecondary)
                                        }
                                        .transition(headerTransition)
                                    } else {
                                        VStack(spacing: 8) {
                                            Text(AppInfo.name)
                                                .font(.largeTitle.weight(.semibold))
                                                .tracking(-0.4)
                                            Text("Every answer, its own page.")
                                                .font(Theme.intro())
                                                .foregroundStyle(Theme.inkSecondary)
                                        }
                                        .transition(headerTransition)
                                    }
                                }
                                .foregroundStyle(Theme.ink)
                            }
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                            Spacer(minLength: 24)
                            VStack(spacing: 12) {
                                if let errorMessage {
                                    Text(errorMessage)
                                        .font(Theme.caption())
                                        .foregroundStyle(Theme.negative)
                                        .multilineTextAlignment(.center)
                                        .accessibilityIdentifier("auth-error")
                                }

                                if naming {
                                    nameEntry.transition(actionsTransition)
                                } else {
                                    VStack(spacing: 12) {
                                        capsuleButton(
                                            "Sign in with Apple", prominent: true, busy: isBusy, action: onApple
                                        ) {
                                            Image(systemName: "apple.logo")
                                        }
                                        .accessibilityIdentifier("auth-apple")
                                        capsuleButton("Sign in with Google", action: onGoogle) {
                                            GoogleGMark(size: 18)
                                        }
                                        .accessibilityIdentifier("auth-google")
                                        capsuleButton("Sign in with email", action: onEmail) {
                                            Image(systemName: "envelope")
                                        }
                                        .accessibilityIdentifier("auth-email")

                                        Button("Use without an account") { setNaming(true) }
                                            .font(Theme.caption())
                                            .underline(color: Theme.inkSecondary.opacity(0.5))
                                            .foregroundStyle(Theme.inkSecondary)
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .contentShape(Rectangle())
                                            .buttonStyle(.plain)
                                            .padding(.top, 6)
                                            .accessibilityIdentifier("auth-guest")
                                    }
                                    .transition(actionsTransition)
                                }

                                Text(
                                    "Using Emblem means you accept the\n[Terms of Service](emblem-legal://terms) and [Privacy Policy](emblem-legal://privacy)."
                                )
                                .font(.footnote)
                                .lineSpacing(4)
                                .foregroundStyle(Theme.inkSecondary)
                                .tint(Theme.ink)
                                .multilineTextAlignment(.center)
                                .environment(
                                    \.openURL,
                                    OpenURLAction { url in
                                        guard url.scheme == "emblem-legal", let host = url.host,
                                            let doc = LegalDoc(rawValue: host)
                                        else { return .systemAction }
                                        legalDoc = doc
                                        return .handled
                                    }
                                )
                            }
                            .disabled(isBusy)
                            .padding(.bottom, 16)
                        }
                        .padding(.horizontal, Theme.contentMargin)
                        .frame(minHeight: geometry.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .sheet(item: $legalDoc) { LegalSheet(doc: $0) }
        .onChange(of: naming) { _, isNaming in
            if isNaming {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { nameFocused = true }
            }
        }
        .animation(.easeOut(duration: 0.2), value: isBusy)
        .animation(.easeOut(duration: 0.2), value: errorMessage)
    }

    private var greeting: AttributedString {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 5 ? "evening" : hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
        var text = AttributedString("Good \(part)")
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            text += AttributedString(", ")
            var bold = AttributedString(trimmed)
            bold.font = .largeTitle.weight(.semibold)
            text += bold
        }
        text += AttributedString(".")
        return text
    }

    private var nameEntry: some View {
        VStack(spacing: 12) {
            TextField("First name", text: $name)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($nameFocused)
                .font(Theme.button())
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.ink)
                .frame(height: 55)
                .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.2), lineWidth: 1))
                .submitLabel(.continue)
                .onSubmit(submitName)
            OnboardingPrimaryButton(title: "Continue", action: submitName)
                .accessibilityIdentifier("auth-continue")
        }
        .padding(.bottom, 8)
    }

    private func submitName() {
        nameFocused = false
        onGuest(name)
    }

    private var headerTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: 6))
    }

    private var actionsTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 16))
    }

    private func setNaming(_ value: Bool) {
        if !value { nameFocused = false }
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(duration: 0.45, bounce: 0.05)) {
            naming = value
        }
    }

    private func capsuleButton<Mark: View>(
        _ title: String, prominent: Bool = false, busy: Bool = false,
        action: @escaping () -> Void, @ViewBuilder mark: () -> Mark
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy {
                    ProgressView().tint(prominent ? Theme.onAccent : Theme.ink)
                } else {
                    mark().frame(width: 22).accessibilityHidden(true)
                    Text(title)
                }
            }
            .font(Theme.button())
            .foregroundStyle(prominent ? Theme.onAccent : Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 55)
            .background(prominent ? Theme.dockSurface : Theme.chip, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(title)
    }
}
