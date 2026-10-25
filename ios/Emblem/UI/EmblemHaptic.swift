import SwiftUI

enum EmblemHaptic {
    static let select = SensoryFeedback.selection
    static let toggle = SensoryFeedback.impact(weight: .light)
    static let increase = SensoryFeedback.increase
    static let decrease = SensoryFeedback.decrease
    static let listenStart = SensoryFeedback.impact(weight: .medium)
    static let listenLock = SensoryFeedback.impact(weight: .light)
    static let listenStop = SensoryFeedback.impact(flexibility: .soft, intensity: 0.7)
    static let send = SensoryFeedback.impact(weight: .light)
    static let saved = SensoryFeedback.success
    static let removed = SensoryFeedback.impact(weight: .light)
    static let copied = SensoryFeedback.success
    static let allCorrect = SensoryFeedback.success
    static let needsAnswer = SensoryFeedback.warning
    static let failed = SensoryFeedback.error
}
