import Foundation

@MainActor
public struct BlockInteraction {
    public struct State: Equatable, Sendable {
        let isCurrentPage: Bool
        let isPageStreaming: Bool
        let isGenerating: Bool
        let isGenerationActive: Bool

        fileprivate var allowsActivation: Bool {
            let isCancelling = isGenerationActive && !isGenerating
            return isCurrentPage && !isGenerating && (!isPageStreaming || isCancelling)
        }

        fileprivate var allowsStoreMutation: Bool {
            allowsActivation && !isGenerationActive
        }

        public init(isCurrentPage: Bool, isPageStreaming: Bool, isGenerating: Bool, isGenerationActive: Bool) {
            self.isCurrentPage = isCurrentPage
            self.isPageStreaming = isPageStreaming
            self.isGenerating = isGenerating
            self.isGenerationActive = isGenerationActive
        }
    }

    private let readState: @MainActor () -> State

    public init(state: @escaping @MainActor () -> State) {
        readState = state
    }

    public var allowsActivation: Bool { readState().allowsActivation }
    public var allowsStoreMutation: Bool { readState().allowsStoreMutation }

    @discardableResult
    public func performActivation(_ action: () -> Void) -> Bool {
        guard readState().allowsActivation else { return false }
        action()
        return true
    }

    @discardableResult
    public func performStoreMutation(_ action: () -> Void) -> Bool {
        guard readState().allowsStoreMutation else { return false }
        action()
        return true
    }
}
