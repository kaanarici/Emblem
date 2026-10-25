import Observation
import SwiftUI

@Observable @MainActor
final class TablePresentationState {
    private(set) var activeID: UUID?
    private(set) var opacity = 1.0
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    @ObservationIgnored private var isDismissing = false

    func present(id: UUID) {
        restoreTask?.cancel()
        activeID = id
        isDismissing = false
        updateOpacity(0, animation: nil)
    }

    func dismiss(id: UUID, reduceMotion: Bool) {
        guard activeID == id, !isDismissing else { return }
        isDismissing = true
        if reduceMotion {
            reset()
            return
        }
        updateOpacity(1, animation: .easeInOut(duration: 0.28).delay(0.15))
        restoreTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(430)) }
            catch { return }
            guard let self, self.activeID == id else { return }
            self.activeID = nil
            self.isDismissing = false
            self.restoreTask = nil
        }
    }

    func didDismiss(id: UUID, reduceMotion: Bool) {
        dismiss(id: id, reduceMotion: reduceMotion)
    }

    func reset() {
        restoreTask?.cancel()
        restoreTask = nil
        activeID = nil
        isDismissing = false
        updateOpacity(1, animation: nil)
    }

    private func updateOpacity(_ value: Double, animation: Animation?) {
        var transaction = Transaction(animation: animation)
        transaction.disablesAnimations = false
        withTransaction(transaction) { opacity = value }
    }
}

private struct TablePresentationStateKey: EnvironmentKey {
    static let defaultValue: TablePresentationState? = nil
}

extension EnvironmentValues {
    var tablePresentation: TablePresentationState? {
        get { self[TablePresentationStateKey.self] }
        set { self[TablePresentationStateKey.self] = newValue }
    }
}
