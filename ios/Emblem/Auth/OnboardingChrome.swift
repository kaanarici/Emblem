import SwiftUI

struct OnboardingBackdrop: View {
    var body: some View {
        Theme.responsePaper.accessibilityHidden(true)
    }
}

struct OnboardingGlass<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Theme.surface, in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}
