import SwiftUI

struct ExpandMorphSurface<Card: View, Expanded: View>: View {
    let sourceFrame: CGRect
    let cornerRadius: CGFloat
    let closing: Bool
    let reduceMotion: Bool
    let onClosed: () -> Void
    @ViewBuilder let card: () -> Card
    @ViewBuilder let expanded: () -> Expanded
    @State private var morphed = false

    static var animation: Animation { .spring(duration: 0.3, bounce: 0) }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let insets = proxy.safeAreaInsets
            let source = sourceFrame.offsetBy(dx: -origin.x, dy: -origin.y)
            let full = CGRect(x: 0, y: -insets.top, width: proxy.size.width,
                              height: proxy.size.height + insets.top + insets.bottom)
            if closing {
                let width = morphed ? full.width : source.width
                card()
                    .frame(width: source.width, height: source.height)
                    .scaleEffect(source.width > 0 ? width / source.width : 1, anchor: .topLeading)
                    .offset(x: morphed ? 0 : source.minX, y: morphed ? 0 : source.minY)
                    .allowsHitTesting(false)
                    .task {
                        try? await Task.sleep(for: .milliseconds(16))
                        withAnimation(Self.animation) { morphed = false }
                        try? await Task.sleep(for: .milliseconds(320))
                        onClosed()
                    }
            } else {
                let clip = morphed ? full : CGRect(origin: .zero, size: source.size)
                expanded()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .background(alignment: .top) {
                        Theme.responsePaper.frame(height: full.height).offset(y: full.minY)
                    }
                    .mask(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: morphed ? 0 : cornerRadius, style: .continuous)
                            .frame(width: clip.width, height: clip.height)
                            .offset(x: clip.minX, y: clip.minY)
                    }
                    .offset(x: morphed ? 0 : source.minX, y: morphed ? 0 : source.minY)
            }
        }
        .presentationBackground(.clear)
        .onAppear {
            if reduceMotion { morphed = true } else { withAnimation(Self.animation) { morphed = true } }
        }
    }
}

@MainActor
func withoutAnimation(_ change: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, change)
}
