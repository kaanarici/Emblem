import SwiftUI
import UIKit
import EmblemCore

extension RootView {
    func performAction(_ action: Action) {
        guard let page = store.currentPage,
              store.blockInteraction(for: page).allowsActivation else { return }
        if action.native == "directions", let destination = action.destination {
            directionsTarget = destination
        } else if let key = action.conversation {
            store.restoreConversation(key: key)
        } else if let id = action.openAutomation {
            store.openAutomation(id: id)
        } else if let spec = action.automation {
            store.createAutomation(spec)
        } else if let spec = action.calendar {
            store.createCalendarEvent(spec)
        } else if let prompt = action.prompt {
            generationOrigin = lastTouch.point
            generationBackdrop = store.canRetryCurrentGeneration
                ? speech.listeningSourceBackdrop
                : speech.capturePageBackdrop()
            if !store.send(prompt, expansion: action.expansion == true) { generationOrigin = nil }
        } else if let urlString = action.url, let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}
