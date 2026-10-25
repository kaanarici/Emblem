import PhotosUI
import SwiftUI
import EmblemCore

extension DockView {
    func darkPill(thinking: Bool, compact: Bool, merging: DockTrailingControl? = nil) -> some View {
        let status = store.statusText ?? "Thinking…"
        let measuredStatusWidth = ceil(
            (displayedStatus as NSString).size(withAttributes: [
                .font: UIFont.systemFont(ofSize: Self.statusFontSize, weight: .semibold),
                .kern: ShimmerText.tracking,
            ]).width)
        let targetWidth = compact
            ? (isQuestionContinue(displaysStatus ? nil : activeTrailingControl) ? Self.wideMicWidth : Self.innerControlSize)
            : (displaysStatus
                ? min(Self.statusWidth, measuredStatusWidth + Self.statusChromeWidth + 4)
                : Self.micWidth)
        return DockWidthMorph(
            width: targetWidth,
            height: Self.innerControlSize,
            progress: sidebarProgress,
            newWidth: Self.newPageWidth,
            absorbedWidth: merging.map { pairSpacing($0) + trailingWidth($0) } ?? 0) { progress, labelWidth in
            ZStack(alignment: .leading) {
                DockCoreLabel(
                    thinking: thinking,
                    status: status,
                    displayedStatus: $displayedStatus,
                    displaysStatus: $displaysStatus,
                    locked: speech.phase == .locked,
                    statusFontSize: Self.statusFontSize,
                    onStop: { store.stop() })
                    .frame(width: labelWidth)
                    .modifier(ExclusiveSidebarDockLabel(progress: sidebarProgress, showsInSidebar: false))
                    .allowsHitTesting(sidebarProgress == 0)
                    .accessibilityHidden(accessibilitySuppressed || sidebarProgress > 0)
                Button(action: onNewPage) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .regular))
                        Text("New").font(.system(size: 14, weight: .medium))
                    }
                        .foregroundStyle(accent.glyph)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .modifier(ExclusiveSidebarDockLabel(progress: sidebarProgress, showsInSidebar: true))
                .allowsHitTesting(sidebarProgress > 0.5)
                .accessibilityHidden(accessibilitySuppressed || sidebarProgress <= 0.5)
                .accessibilityLabel("New page")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                if let merging {
                    Text(merging.label)
                        .font(.system(size: isQuestionContinue(merging) ? 15 : 17, weight: .semibold))
                        .foregroundStyle(accent.glyph)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: trailingWidth(merging))
                        .offset(x: targetWidth + pairSpacing(merging))
                        .opacity(progress > 0 ? 1 - min(1, max(0, progress - 0.25) / 0.12) : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .background(micShape)
        .contentShape(RoundedRectangle(cornerRadius: Self.micRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Self.micRadius, style: .continuous))
        .scaleEffect(reduceMotion ? 1 : (micExpanded ? 1.48 : 1))
        .zIndex(micExpanded ? 2 : 0)
        .animation(micPressMotion, value: micExpanded)
        .accessibilityIdentifier(sidebarProgress > 0 ? "sidebar-new-page" : "voice-microphone")
        .accessibilityLabel(sidebarProgress > 0 ? "New page" : isEditingRecording ? "Resume recording" : speech.phase == .locked ? "Pause recording" : "Hold to record")
        .accessibilityValue(sidebarProgress > 0 ? "" : String(describing: speech.phase))
        .accessibilityHidden(accessibilitySuppressed)
        .overlay(alignment: .top) { lockBadge }
        .allowsHitTesting(isEditingRecording ? editorControlsReady
            : (!store.isAwaitingFirstGenerationContent || thinking))
        .highPriorityGesture(
            sidebarProgress > 0 || thinking || speech.phase == .locked || isEditingRecording ? nil : holdToTalk)
        .onTapGesture {
            if isEditingRecording {
                dispatchEditor(.resume)
            } else if speech.phase == .locked {
                stopVoiceSegment()
            }
        }
    }

    private static let statusFontSize: CGFloat = 15
    private static let statusWidth: CGFloat = 264
    private static let statusChromeWidth: CGFloat =
        DockStatusMetrics.controlEdgePadding + DockStatusMetrics.stopHitSize +
        DockStatusMetrics.controlSpacing + DockStatusMetrics.textEdgePadding

    var completionPulseOpacity: Double {
        guard completionPulse > 0, completionPulse < 1 else { return 0 }
        return sin(.pi * completionPulse)
    }
}
