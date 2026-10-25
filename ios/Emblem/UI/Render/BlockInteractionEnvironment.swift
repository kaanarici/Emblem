import SwiftUI
import EmblemCore

private struct BlockInteractionKey: EnvironmentKey {
    static let defaultValue: BlockInteraction? = nil
}

extension EnvironmentValues {
    var blockInteraction: BlockInteraction? {
        get { self[BlockInteractionKey.self] }
        set { self[BlockInteractionKey.self] = newValue }
    }
}

@MainActor
extension Optional where Wrapped == BlockInteraction {
    var allowsActivation: Bool { self?.allowsActivation ?? true }
    var allowsStoreMutation: Bool { self?.allowsStoreMutation ?? true }

    @discardableResult
    func performActivation(_ action: () -> Void) -> Bool {
        guard let interaction = self else { action(); return true }
        return interaction.performActivation(action)
    }

    @discardableResult
    func performStoreMutation(_ action: () -> Void) -> Bool {
        guard let interaction = self else { action(); return true }
        return interaction.performStoreMutation(action)
    }
}

private struct BlockInteractionControl: ViewModifier {
    @Environment(\.blockInteraction) private var interaction
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let mutatesStore: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let allowed = mutatesStore ? interaction.allowsStoreMutation : interaction.allowsActivation
        if voiceOver {
            content.disabled(!allowed)
        } else {
            content.allowsHitTesting(allowed)
        }
    }
}

private struct BlockActivationLinks: ViewModifier {
    @Environment(\.blockInteraction) private var interaction
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            guard interaction.allowsActivation else { return .discarded }
            openURL(url)
            return .handled
        })
    }
}

private struct BlockActivationTextSelection: ViewModifier {
    @Environment(\.blockInteraction) private var interaction

    @ViewBuilder
    func body(content: Content) -> some View {
        if interaction.allowsActivation {
            content.textSelection(.enabled)
        } else {
            content.textSelection(.disabled)
        }
    }
}

extension View {
    func blockActivationControl() -> some View {
        modifier(BlockInteractionControl(mutatesStore: false))
    }

    func blockStoreMutationControl() -> some View {
        modifier(BlockInteractionControl(mutatesStore: true))
    }

    func blockActivationLinks() -> some View {
        modifier(BlockActivationLinks())
    }

    func blockActivationTextSelection() -> some View {
        modifier(BlockActivationTextSelection())
    }
}
