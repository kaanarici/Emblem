import SwiftUI
import EmblemCore

struct ExclusiveSidebarDockLabel: ViewModifier, @MainActor Animatable {
    var progress: CGFloat
    let showsInSidebar: Bool
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        let active = showsInSidebar ? progress >= 0.5 : progress < 0.5
        content
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
            .transaction { $0.animation = nil }
    }
}

struct SlotSwap: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.7 + 0.3 * progress)
            .blur(radius: 5 * (1 - progress))
            .opacity(progress)
    }
}
