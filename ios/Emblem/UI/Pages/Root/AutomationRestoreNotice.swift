import SwiftUI
import UIKit
import EmblemCore

struct AutomationRestoreNotice: View {
    @Environment(ConversationStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if store.openingAutomationID != nil {
                ProgressView()
                    .controlSize(.regular)
                    .tint(Theme.inkSecondary)
                    .accessibilityLabel("Opening automation")
                    .accessibilityIdentifier("automation-restore-progress")
                    .allowsHitTesting(false)
                    .transition(progressTransition)
            }

            VStack {
                if let id = store.automationOpenFailureID {
                    HStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                        Text("Automation couldn’t open")
                        Spacer(minLength: 8)
                        Button { store.openAutomation(id: id) } label: {
                            Text("Retry").fontWeight(.semibold)
                        }
                        .buttonStyle(.pressable)
                        Button { store.dismissAutomationOpenFailure() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 28, height: 28)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Dismiss automation error")
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .padding(.leading, 16)
                    .padding(.trailing, 10)
                    .frame(minHeight: 48)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .transition(noticeTransition)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, 62)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.18), value: store.openingAutomationID)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.18), value: store.automationOpenFailureID)
    }

    private var noticeTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    private var progressTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)
    }
}
