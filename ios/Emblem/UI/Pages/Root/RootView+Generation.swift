import SwiftUI
import UIKit
import EmblemCore

extension RootView {
    func handleGenerationChange(isGenerating: Bool) {
        if isGenerating {
            if primaryDestination == .saves, savedEntry == nil { primaryDestination = nil }
            if store.isExpansionGeneration {
                generationBackdrop = nil
                reveal = nil
                heldChromePage = nil
                return
            }
            reveal = nil
            let now = Date()
            if store.dockState == .listening
                || now.timeIntervalSince(lastListeningExit) < 0.8 {
                generationHoldDelay = 0.42
            } else if store.dockState == .keyboard
                || now.timeIntervalSince(lastKeyboardExit) < 0.8 {
                generationHoldDelay = 0.35
            } else {
                generationHoldDelay = 0
            }
            generationWaveEpoch = now.addingTimeInterval(generationHoldDelay)
            if generationBackdrop == nil {
                generationBackdrop = speech.listeningSourceBackdrop
            }
            heldChromePage = store.pendingPresentationSourcePage
        } else {
            generationOrigin = nil
            generationBackdrop = nil
            if reveal == nil { heldChromePage = nil }
            rearmBackdropAfterQuiet(delayMilliseconds: 900)
        }
    }

    func handleDockStateChange(old: DockState, state: DockState) {
        if old == .listening { lastListeningExit = Date() }
        if old == .keyboard { lastKeyboardExit = Date() }
        guard state == .idle else { return }
        rearmBackdropAfterQuiet(delayMilliseconds: 800)
    }

    func rearmBackdropAfterQuiet(delayMilliseconds: Int) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard store.dockState == .idle, !store.isGenerating, reveal == nil,
                  !store.canRetryCurrentGeneration,
                  speech.phase == .idle else { return }
            speech.captureListeningBackdrop()
        }
    }

    static let minimumHold: TimeInterval = 1.1
    static let dockLeadBeforeFront: TimeInterval = 0.47
}
