import PhotosUI
import SwiftUI
import EmblemCore

extension DockView {
    var holdToTalk: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($voicePressActive) { _, isPressed, _ in
                isPressed = true
            }
            .onChanged { value in
                guard voiceFinalizationTask == nil else { return }
                if holdStartedAt == nil {
                    guard store.canStartNewResponse else { return }
                    holdStartedAt = Date()
                    startListening()
                }
                if speech.phase == .held, value.translation.height < -60 {
                    speech.phase = .locked
                }
            }
            .onEnded { _ in
                endHoldIfNeeded()
            }
    }

    func endHoldIfNeeded() {
        guard let started = holdStartedAt else { return }
        holdStartedAt = nil
        guard speech.phase == .held else { return }
        if Date().timeIntervalSince(started) < 0.3 {
            speech.phase = .locked
            return
        }
        if !speech.isRunning {
            voiceStartTask?.cancel()
            voiceStartTask = nil
            speech.prepareForFreshSegment()
            speech.phase = .idle
            store.dockState = .idle
            return
        }
        beginVoiceFinalization(.send)
    }

    private func startListening() {
        speech.captureListeningBackdrop()
        speech.prepareForFreshSegment()
        speech.phase = .held
        store.dockState = .listening
        VoiceOutput.shared.stop()
        voiceStartTask?.cancel()
        voiceStartTask = Task {
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled else { return }
            guard store.dockState == .listening,
                  speech.phase == .held || speech.phase == .locked,
                  voiceFinalizationTask == nil
            else { return }
            guard speech.isAvailable else {
                speech.phase = .idle
                if store.dockState == .listening { store.dockState = .keyboard }
                return
            }
            await speech.start()
            guard store.dockState == .listening,
                  speech.phase == .held || speech.phase == .locked,
                  voiceFinalizationTask == nil
            else { return }
            if !speech.isRunning, store.dockState == .listening {
                speech.phase = .idle
                store.dockState = .idle
            }
            voiceStartTask = nil
        }
    }

    func beginVoiceFinalization(_ intent: VoiceFinalizationIntent) {
        guard voiceFinalizationTask == nil else { return }
        holdStartedAt = nil
        voiceStartTask?.cancel()
        voiceStartTask = nil

        voiceFinalizationTask = Task { @MainActor in
            let walkBack = Task {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 80 : 180))
            }
            let segment = await speech.finish()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            await walkBack.value
            speech.insertIntoDraft(segment)

            switch intent {
            case .edit:
                if speech.draft.isEmpty {
                    speech.phase = .idle
                    store.dockState = .idle
                } else {
                    speech.phase = .editing
                }
            case .send:
                let text = speech.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    speech.draft = ""
                    speech.phase = .idle
                    store.dockState = .idle
                } else if store.send(text) {
                    speech.draft = ""
                    speech.phase = .idle
                } else {
                    speech.phase = .editing
                    store.dockState = .listening
                }
            }
            voiceFinalizationTask = nil
        }
    }
}
