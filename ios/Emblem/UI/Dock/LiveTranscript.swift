import SwiftUI

struct LiveTranscript: View {
    let text: String
    @Binding var contentHeight: CGFloat
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    let clipsOverflow: Bool
    @Environment(\.accent) private var accent

    var body: some View {
        let height = min(max(contentHeight + 14, minimumHeight), maximumHeight)
        Text(text)
            .accessibilityIdentifier("voice-live-transcript")
            .font(.system(size: 20, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(accent.ink)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .center)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .offset(y: height - contentHeight)
            .frame(height: height, alignment: .top)
            .animation(.smooth(duration: 0.32), value: contentHeight)
            .modifier(OverflowFade(active: clipsOverflow, overflowing: contentHeight > maximumHeight + 1))
    }
}

private struct OverflowFade: ViewModifier {
    let active: Bool
    let overflowing: Bool

    func body(content: Content) -> some View {
        if active {
            content.clipped().mask {
                LinearGradient(
                    stops: [
                        .init(color: overflowing ? .clear : .black, location: 0),
                        .init(color: .black, location: overflowing ? 0.38 : 0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom)
            }
        } else {
            content
        }
    }
}
