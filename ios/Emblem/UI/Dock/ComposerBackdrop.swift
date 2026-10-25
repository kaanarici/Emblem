import SwiftUI

struct ComposerBackdrop: View {
    var fadesToPaper = true

    var body: some View {
        ZStack {
            VariableBlurView(maxBlurRadius: 2.4, direction: .blurredBottomClearTop, startOffset: 0.07)
            if fadesToPaper {
                LinearGradient(stops: [.init(color: Theme.responsePaper.opacity(0), location: 0.07),
                                       .init(color: Theme.responsePaper.opacity(0.16), location: 0.22),
                                       .init(color: Theme.responsePaper.opacity(0.4), location: 0.42),
                                       .init(color: Theme.responsePaper.opacity(0.62), location: 0.62),
                                       .init(color: Theme.responsePaper.opacity(0.8), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
