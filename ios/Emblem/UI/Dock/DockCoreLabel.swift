import SwiftUI
import EmblemCore

private enum DockCoreContent: Equatable {
    case microphone(locked: Bool, hint: Bool)
    case status(String)

    var isStatus: Bool {
        if case .status = self { return true }
        return false
    }
}

struct DockWidthMorph<Content: View>: View, @preconcurrency Animatable {
    var width: CGFloat
    let height: CGFloat
    var progress: CGFloat
    let newWidth: CGFloat
    let absorbedWidth: CGFloat
    let content: (CGFloat, CGFloat) -> Content

    init(width: CGFloat, height: CGFloat, progress: CGFloat = 0, newWidth: CGFloat = 0,
         absorbedWidth: CGFloat = 0, @ViewBuilder content: @escaping (CGFloat, CGFloat) -> Content) {
        self.width = width
        self.height = height
        self.progress = progress
        self.newWidth = newWidth
        self.absorbedWidth = absorbedWidth
        self.content = content
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, progress) }
        set { width = newValue.first; progress = newValue.second }
    }

    var body: some View {
        let start = width + absorbedWidth * dockMerge(progress)
        let labelWidth = width + (newWidth - width) * progress
        content(progress, labelWidth)
            .frame(width: start + (newWidth - start) * progress, height: height, alignment: .leading)
    }
}

struct TrailingWipe: ViewModifier, @MainActor Animatable {
    var progress: CGFloat
    let gap: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content.mask(alignment: .leading) {
            GeometryReader { proxy in
                Capsule().frame(width: max(0, (proxy.size.width + gap) * min(1, progress) - gap))
            }
        }
    }
}

struct HiddenWhileSidebarOpens: ViewModifier, @MainActor Animatable {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content.opacity(dockMerge(progress) < 1 ? 1 : 0)
    }
}

private func dockMerge(_ sidebarProgress: CGFloat) -> CGFloat {
    min(1, max(0, sidebarProgress / 0.25))
}

struct DockContentLayout: Layout {
    var spacing: CGFloat
    var trailingProgress: CGFloat
    var sidebarProgress: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(trailingProgress, sidebarProgress) }
        set { trailingProgress = newValue.first; sidebarProgress = newValue.second }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let core = subviews.last else { return .zero }
        let coreSize = core.sizeThatFits(.unspecified)
        guard subviews.count > 1 else { return coreSize }
        let trailingSize = subviews[0].sizeThatFits(.unspecified)
        return CGSize(
            width: coreSize.width + clampedProgress * (spacing + trailingSize.width),
            height: max(coreSize.height, trailingSize.height))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let core = subviews.last else { return }
        let coreSize = core.sizeThatFits(.unspecified)
        core.place(
            at: CGPoint(x: bounds.minX, y: bounds.midY - coreSize.height / 2),
            anchor: .topLeading,
            proposal: ProposedViewSize(coreSize))

        guard subviews.count > 1 else { return }
        let trailing = subviews[0]
        let trailingSize = trailing.sizeThatFits(.unspecified)
        trailing.place(
            at: CGPoint(
                x: sidebarProgress > 0
                    ? bounds.maxX - trailingSize.width
                    : bounds.minX + coreSize.width + spacing,
                y: bounds.midY - trailingSize.height / 2),
            anchor: .topLeading,
            proposal: ProposedViewSize(trailingSize))
    }

    private var clampedProgress: CGFloat {
        max(0, min(1, trailingProgress)) * (1 - dockMerge(sidebarProgress))
    }
}

struct DockCoreLabel: View {
    let thinking: Bool
    let status: String
    @Binding var displayedStatus: String
    @Binding var displaysStatus: Bool
    let locked: Bool
    let hint: Bool
    let statusFontSize: CGFloat
    let onStop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accent) private var accent
    @State private var displayedContent = DockCoreContent.microphone(locked: false, hint: false)
    @State private var visible = true
    @State private var statusTextVisible = true
    @State private var lastStatusSwap = Date.distantPast
    @State private var swapTask: Task<Void, Never>?

    init(
        thinking: Bool,
        status: String,
        displayedStatus: Binding<String>,
        displaysStatus: Binding<Bool>,
        locked: Bool,
        hint: Bool,
        statusFontSize: CGFloat,
        onStop: @escaping () -> Void
    ) {
        self.thinking = thinking
        self.status = status
        _displayedStatus = displayedStatus
        _displaysStatus = displaysStatus
        self.locked = locked
        self.hint = hint
        self.statusFontSize = statusFontSize
        self.onStop = onStop
    }

    var body: some View {
        ZStack {
            displayedLabel
                .id(displayedContent.isStatus)
                .transition(Self.labelSwap(reduceMotion))
        }
        .opacity(visible ? 1 : 0)
        .blur(radius: reduceMotion || visible ? 0 : 3.2)
        .onAppear {
            synchronizePresentation(for: displayedContent)
            swap(to: targetContent)
        }
        .onChange(of: targetContent) { _, content in swap(to: content) }
        .onDisappear {
            swapTask?.cancel()
            swapTask = nil
            statusTextVisible = true
            visible = true
        }
    }

    private var targetContent: DockCoreContent {
        thinking ? .status(status) : .microphone(locked: locked, hint: hint && !locked)
    }

    @ViewBuilder
    private var displayedLabel: some View {
        switch displayedContent {
        case .status(let text):
            HStack(spacing: DockStatusMetrics.controlSpacing) {
                Button(action: onStop) {
                    ZStack {
                        Circle()
                            .fill(accent.glyph)
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(accent.color)
                            .frame(
                                width: DockStatusMetrics.stopGlyphSize,
                                height: DockStatusMetrics.stopGlyphSize)
                    }
                    .frame(
                        width: DockStatusMetrics.stopVisibleSize,
                        height: DockStatusMetrics.stopVisibleSize)
                    .frame(
                        width: DockStatusMetrics.stopHitSize,
                        height: DockStatusMetrics.stopHitSize)
                    .contentShape(Circle())
                }
                .buttonStyle(DockStopButtonStyle())
                .accessibilityLabel("Stop response")
                .accessibilityHint("Stops generating this response")
                .accessibilityIdentifier("generation-stop")
                ZStack(alignment: .leading) {
                    ShimmerText(text, active: visible, size: statusFontSize)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id(text)
                        .transition(Self.labelSwap(reduceMotion))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(statusTextVisible ? 1 : 0)
                .blur(radius: reduceMotion || statusTextVisible ? 0 : 2.4)
                .accessibilityIdentifier("generation-status")
            }
            .padding(.leading, DockStatusMetrics.controlEdgePadding)
            .padding(.trailing, DockStatusMetrics.textEdgePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        case .microphone(let locked, let hint):
            ZStack {
                if hint {
                    ShimmerText(DockView.holdHintText, active: visible, size: 15)
                        .fixedSize()
                        .transition(Self.labelSwap(reduceMotion))
                } else {
                    Image(systemName: locked ? "square.fill" : "mic.fill")
                        .font(.system(size: locked ? 19 : 16, weight: .medium))
                        .foregroundStyle(locked && accent.isNeutral ? Theme.record : accent.glyph)
                        .accessibilityIdentifier("dock-microphone")
                        .transition(Self.labelSwap(reduceMotion))
                }
            }
        }
    }

    static func labelSwap(_ reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .modifier(active: LabelBlur(radius: 4), identity: LabelBlur(radius: 0)))
                .animation(.smooth(duration: 0.3).delay(0.1)),
            removal: .opacity.combined(with: .modifier(active: LabelBlur(radius: 4), identity: LabelBlur(radius: 0)))
                .animation(.easeOut(duration: 0.12)))
    }

    private func swap(to content: DockCoreContent) {
        swapTask?.cancel()
        swapTask = nil
        guard content != displayedContent else {
            statusTextVisible = true
            synchronizePresentation(for: content)
            withAnimation(.easeOut(duration: reduceMotion ? 0.06 : 0.10)) {
                visible = true
            }
            return
        }

        if case .microphone(let shown, _) = displayedContent, case .microphone(let next, _) = content, shown == next {
            withAnimation(reduceMotion ? .easeOut(duration: 0.1) : DockView.pillMotion) {
                displayedContent = content
            }
            return
        }

        if case .status = displayedContent, case .status = content {
            if !visible {
                withAnimation(.easeOut(duration: reduceMotion ? 0.06 : 0.10)) {
                    visible = true
                }
            }
            let now = Date()
            if now.timeIntervalSince(lastStatusSwap) < 0.5 {
                displayedContent = content
                synchronizePresentation(for: content)
                if !statusTextVisible {
                    withAnimation(.easeOut(duration: 0.08)) { statusTextVisible = true }
                }
                return
            }
            lastStatusSwap = now
            withAnimation(.easeInOut(duration: reduceMotion ? 0.1 : 0.27)) {
                displayedContent = content
                statusTextVisible = true
            }
            synchronizePresentation(for: content)
            return
        }

        if displayedContent.isStatus != content.isStatus {
            withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.22)) {
                visible = true
                statusTextVisible = true
                displayedContent = content
                synchronizePresentation(for: content)
            }
            return
        }

        swapTask?.cancel()
        swapTask = Task { @MainActor in
            guard !Task.isCancelled else { return }

            let fadeOutMilliseconds = reduceMotion ? 35 : 40
            withAnimation(.easeOut(duration: Double(fadeOutMilliseconds) / 1_000)) {
                visible = false
            }
            do {
                try await Task.sleep(for: .milliseconds(fadeOutMilliseconds))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            var contentTransaction = Transaction()
            contentTransaction.disablesAnimations = true
            withTransaction(contentTransaction) {
                displayedContent = content
                statusTextVisible = true
            }
            synchronizePresentation(for: content)

            if !reduceMotion {
                do {
                    try await Task.sleep(for: .milliseconds(20))
                } catch {
                    return
                }
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else { return }

            withAnimation(
                .easeOut(duration: reduceMotion ? 0.08 : 0.12)
            ) {
                visible = true
            }
        }
    }

    private func synchronizePresentation(for content: DockCoreContent) {
        switch content {
        case .status(let status):
            if displayedStatus != status { displayedStatus = status }
            if !displaysStatus { displaysStatus = true }
        case .microphone:
            if displayedStatus != "Thinking…" { displayedStatus = "Thinking…" }
            if displaysStatus { displaysStatus = false }
        }
    }
}

private struct LabelBlur: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

private struct DockStopButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.76 : 1)
            .animation(
                .easeOut(duration: reduceMotion ? 0.06 : 0.12),
                value: configuration.isPressed)
    }
}
