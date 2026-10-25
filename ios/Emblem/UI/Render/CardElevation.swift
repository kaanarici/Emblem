import SwiftUI
import EmblemCore

struct ExpandsIntoSubpage: ViewModifier {
    @Environment(\.blockInteraction) private var blockInteraction
    let card: CardCarousel.Card
    let blockID: String
    var contentStyle: PageExpansionSource.ContentStyle = .article
    var elevation: CardElevation? = nil
    @Environment(ConversationStore.self) private var store
    @Environment(\.renderedPage) private var renderedPage
    @Environment(\.expansionNamespace) private var expansionNamespace

    private var transitionID: String? {
        guard let renderedPage else { return nil }
        return "\(renderedPage.id.uuidString):" +
            PageExpansionSource.cardKey(blockID: blockID, card: card)
    }

    func body(content: Content) -> some View {
        Button {
            guard blockInteraction.allowsStoreMutation else { return }
            guard let renderedPage else { return }
            _ = store.openExpansion(card: card, blockID: blockID, from: renderedPage,
                                    contentStyle: contentStyle)
        } label: {
            content.modifier(CardZoomSource(id: transitionID, namespace: expansionNamespace,
                                            elevation: elevation, drawsRestingShadow: false))
        }
        .blockStoreMutationControl()
        .buttonStyle(PressableStyle(elevation: elevation))
        .disabled(card.title.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}

struct CardElevation {
    var corner: CGFloat
    var ambient: (opacity: Double, radius: CGFloat, y: CGFloat) = (0.10, 16, 6)
    var contact: (opacity: Double, radius: CGFloat, y: CGFloat) = (0.06, 1, 0.5)

    static func rounded(_ corner: CGFloat) -> CardElevation {
        CardElevation(corner: corner)
    }
}

struct CardZoomSource: ViewModifier {
    let id: String?
    let namespace: Namespace.ID?
    var elevation: CardElevation? = nil
    var drawsRestingShadow = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        let resting = RestingElevation(elevation: drawsRestingShadow ? elevation : nil)
        if !reduceMotion, let id, let namespace {
            if let elevation {
                content
                    .matchedTransitionSource(id: id, in: namespace) { source in
                        source.clipShape(RoundedRectangle(cornerRadius: elevation.corner, style: .continuous))
                            .shadow(color: .black.opacity(elevation.ambient.opacity),
                                    radius: elevation.ambient.radius, y: elevation.ambient.y)
                            .shadow(color: .black.opacity(elevation.contact.opacity),
                                    radius: elevation.contact.radius, y: elevation.contact.y)
                    }
                    .modifier(resting)
            } else {
                content.matchedTransitionSource(id: id, in: namespace) { source in
                    source
                }
            }
        } else {
            content.modifier(resting)
        }
    }
}

struct RestingElevation: ViewModifier {
    let elevation: CardElevation?

    func body(content: Content) -> some View {
        if let elevation {
            content
                .shadow(color: .black.opacity(elevation.ambient.opacity),
                        radius: elevation.ambient.radius, y: elevation.ambient.y)
                .shadow(color: .black.opacity(elevation.contact.opacity),
                        radius: elevation.contact.radius, y: elevation.contact.y)
        } else {
            content
        }
    }
}
