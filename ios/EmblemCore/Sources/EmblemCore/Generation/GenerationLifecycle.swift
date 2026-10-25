import Foundation

public struct GenerationRunID: Hashable, Sendable {
    let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct GenerationFailure: Equatable, Sendable {
    let code: String
    public let message: String
    let retryable: Bool

    public init(code: String, message: String, retryable: Bool) {
        self.code = code
        self.message = message
        self.retryable = retryable
    }
}

public enum GenerationTerminalOutcome: Equatable, Sendable {
    case completed(runID: GenerationRunID, persisted: Bool?)
    case failed(runID: GenerationRunID, failure: GenerationFailure)
    case cancelled(runID: GenerationRunID)

    var runID: GenerationRunID {
        switch self {
        case .completed(let runID, _), .failed(let runID, _), .cancelled(let runID):
            runID
        }
    }
}

enum GenerationLifecycle: Equatable, Sendable {
    struct Active: Equatable, Sendable {
        let runID: GenerationRunID
        var statusText: String?
    }

    enum Event: Equatable, Sendable {
        case status(String)
        case completed(persisted: Bool?)
        case failed(GenerationFailure)
        case cancelled
    }

    case idle
    case active(Active)
    case cancelling(runID: GenerationRunID)
    case terminal(GenerationTerminalOutcome)

    var isActive: Bool {
        switch self {
        case .active, .cancelling: true
        case .idle, .terminal: false
        }
    }

    var isGenerating: Bool {
        if case .active = self { return true }
        return false
    }

    var activeRunID: GenerationRunID? {
        guard case .active(let active) = self else { return nil }
        return active.runID
    }

    var statusText: String? {
        guard case .active(let active) = self else { return nil }
        return active.statusText
    }

    var terminalOutcome: GenerationTerminalOutcome? {
        guard case .terminal(let outcome) = self else { return nil }
        return outcome
    }

    func acceptsEvents(for runID: GenerationRunID) -> Bool {
        activeRunID == runID
    }

    @discardableResult
    mutating func begin(runID: GenerationRunID) -> Bool {
        guard !isActive else { return false }
        self = .active(Active(runID: runID, statusText: nil))
        return true
    }

    @discardableResult
    mutating func beginCancellation(runID: GenerationRunID) -> Bool {
        guard case .active(let active) = self, active.runID == runID else { return false }
        self = .cancelling(runID: runID)
        return true
    }

    @discardableResult
    mutating func apply(_ event: Event, to runID: GenerationRunID) -> Bool {
        if case .cancelling(let cancellingRunID) = self {
            guard cancellingRunID == runID else { return false }
            switch event {
            case .completed(let persisted):
                self = .terminal(.completed(runID: runID, persisted: persisted))
            case .failed(let failure):
                self = .terminal(.failed(runID: runID, failure: failure))
            case .cancelled:
                self = .terminal(.cancelled(runID: runID))
            case .status:
                return false
            }
            return true
        }

        guard case .active(var active) = self, active.runID == runID else { return false }

        switch event {
        case .status(let text):
            active.statusText = text.isEmpty ? nil : text
            self = .active(active)
        case .completed(let persisted):
            self = .terminal(.completed(runID: runID, persisted: persisted))
        case .failed(let failure):
            self = .terminal(.failed(runID: runID, failure: failure))
        case .cancelled:
            self = .terminal(.cancelled(runID: runID))
        }
        return true
    }
}
