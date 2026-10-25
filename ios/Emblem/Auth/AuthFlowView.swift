import ClerkKit
import SwiftUI

struct AuthFlowView: View {
    enum Step: Equatable {
        case signIn
        case emailEntry
        case codeEntry(email: String)
        case connect

        var order: Int {
            switch self {
            case .signIn: 0
            case .emailEntry: 1
            case .codeEntry: 2
            case .connect: 3
            }
        }
    }

    var presentedFromApp = false
    var onFinished: () -> Void = {}

    @Environment(AuthStore.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .signIn
    @State private var forward = true
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var pendingSignIn: SignIn?

    var body: some View {
        ZStack {
            OnboardingBackdrop().ignoresSafeArea()
                .opacity(auth.revealingHome && !presentedFromApp ? 0 : 1)
                .animation(.easeInOut(duration: 0.35).delay(0.17), value: auth.revealingHome)

            switch step {
            case .signIn:
                SignInView(
                    isBusy: isBusy,
                    errorMessage: errorMessage,
                    onGoogle: { runSignIn { try await auth.signInWithGoogle() } },
                    onApple: { runSignIn { try await auth.signInWithApple() } },
                    onGuest: { name in
                        auth.setGuestName(name)
                        authenticated()
                    },
                    onEmail: { advance(to: .emailEntry) },
                    onClose: presentedFromApp ? onFinished : nil
                )
                .transition(stepTransition)
            case .emailEntry:
                EmailEntryView(
                    isBusy: isBusy,
                    errorMessage: errorMessage,
                    onBack: { advance(to: .signIn) },
                    onSubmit: { email in sendCode(to: email) }
                )
                .transition(stepTransition)
            case .codeEntry(let email):
                CodeEntryView(
                    email: email,
                    isBusy: isBusy,
                    errorMessage: errorMessage,
                    onBack: { advance(to: .emailEntry) },
                    onSubmit: { code in verifyCode(code) }
                )
                .transition(stepTransition)
            case .connect:
                CalendarConnectView(onSignIn: { advance(to: .signIn) }, onDone: { auth.completeGate() })
                    .transition(stepTransition)
            }
        }
        .onAppear {
            if !presentedFromApp, auth.isSignedIn { step = .connect }
        }
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let shift: CGFloat = forward ? 44 : -44
        return .asymmetric(
            insertion: .offset(x: shift).combined(with: .opacity),
            removal: .offset(x: -shift).combined(with: .opacity))
    }

    private var transitionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(duration: 0.42, bounce: 0)
    }

    private func advance(to next: Step) {
        errorMessage = nil
        let isForward = next.order >= step.order
        guard isForward != forward else {
            withAnimation(transitionAnimation) { step = next }
            return
        }
        forward = isForward
        DispatchQueue.main.async {
            withAnimation(transitionAnimation) { step = next }
        }
    }

    private func authenticated() {
        if presentedFromApp {
            onFinished()
        } else {
            advance(to: .connect)
        }
    }

    private func runSignIn(_ operation: @escaping () async throws -> Void) {
        guard !isBusy else { return }
        errorMessage = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await operation()
                authenticated()
            } catch {
                if error.isUserCancellation { return }
                errorMessage = error.clerkMessage
            }
        }
    }

    private func sendCode(to email: String) {
        guard !isBusy else { return }
        errorMessage = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                pendingSignIn = try await auth.sendEmailCode(to: email)
                advance(to: .codeEntry(email: email))
            } catch {
                errorMessage = error.clerkMessage
            }
        }
    }

    private func verifyCode(_ code: String) {
        guard !isBusy, let pendingSignIn else { return }
        errorMessage = nil
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await auth.verifyEmailCode(code, signIn: pendingSignIn)
                authenticated()
            } catch {
                errorMessage = error.clerkMessage
            }
        }
    }
}

extension Error {
    var clerkMessage: String {
        if let apiError = self as? ClerkAPIError {
            return apiError.longMessage ?? apiError.message ?? "Something went wrong."
        }
        return localizedDescription
    }

    var isUserCancellation: Bool {
        let ns = self as NSError
        return
            (ns.domain == "com.apple.AuthenticationServices.WebAuthenticationSession"
            && ns.code == 1)
            || (ns.domain == "com.apple.AuthenticationServices.AuthorizationError"
                && ns.code == 1001)
    }
}
