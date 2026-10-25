import SwiftUI
import UIKit
import EmblemCore

struct CalendarGenerationSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var bend: CGFloat = 0
    @State private var lastSample: TimeInterval = 0
    @State private var relax: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size.height
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        barrel(line(width: geometry.size.width - 100), viewport)
                        barrel(line(width: geometry.size.width - 90), viewport)
                        barrel(line(width: geometry.size.width - 162), viewport)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 42)
                    barrel(line(width: 126), viewport).padding(.horizontal, 32).padding(.bottom, 17)
                    VStack(spacing: 12) {
                        barrel(RoundedRectangle(cornerRadius: 20).fill(fill).frame(height: 100), viewport)
                        barrel(RoundedRectangle(cornerRadius: 20).fill(fill).frame(height: 100), viewport)
                    }.padding(.horizontal, 28)
                }
                .padding(.top, 109.0 / 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .phaseAnimator(reduceMotion ? [1] : [1, 0.53]) { content, opacity in
                    content.opacity(opacity)
                } animation: { _ in .easeInOut(duration: 0.8).delay(0.55) }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always, axes: .vertical)
            .background(Theme.sidebarBackground)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { old, new in
                track(delta: new - old)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading selected calendar")
            .accessibilityIdentifier("calendar-generation-skeleton")
        }
    }

    private func barrel(_ row: some View, _ viewport: CGFloat) -> some View {
        let bend = bend
        return row.visualEffect { content, proxy in
            let half = max(1, viewport / 2)
            let distance = proxy.frame(in: .scrollView).midY - half
            let maxAngle = 1.25 * min(1, abs(bend))
            let angle = maxAngle * max(-1.25, min(1.25, distance / half))
            let radius = maxAngle > 0.001 ? half / maxAngle : .infinity
            let shift = radius.isFinite ? radius * sin(angle) - distance : 0
            return content
                .scaleEffect(x: 1 - 0.2 * (1 - cos(angle)), y: max(0.05, cos(angle)))
                .offset(y: shift)
        }
    }

    private func track(delta: CGFloat) {
        let now = CACurrentMediaTime()
        let elapsed = max(1.0 / 120, min(0.1, now - lastSample))
        lastSample = now
        flex(min(1, abs(delta) / elapsed / 600))
    }

    private func flex(_ target: CGFloat) {
        guard !reduceMotion else { return }
        bend = max(target, bend * 0.85)
        relax?.cancel()
        relax = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.45, bounce: 0.15)) { bend = 0 }
        }
    }

    private var fill: Color { colorScheme == .dark ? Theme.card : Color(white: 225.0 / 255) }

    private func line(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6).fill(fill).frame(width: max(0, width), height: 16)
    }
}
