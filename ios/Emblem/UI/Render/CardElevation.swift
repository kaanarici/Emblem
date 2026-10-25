import SwiftUI
import EmblemCore

struct ExpansionZoomSource: ViewModifier {
    let card: CardCarousel.Card
    let blockID: String
    let elevation: CardElevation
    var drawsRestingShadow = true
    @Environment(\.renderedPage) private var renderedPage
    @Environment(\.expansionNamespace) private var expansionNamespace

    func body(content: Content) -> some View {
        content.modifier(CardZoomSource(
            id: renderedPage.map { "\($0.id.uuidString):" + PageExpansionSource.cardKey(blockID: blockID, card: card) },
            namespace: expansionNamespace, elevation: elevation, drawsRestingShadow: drawsRestingShadow))
    }
}

struct ExpandsIntoSubpage: ViewModifier {
    @Environment(\.blockInteraction) private var blockInteraction
    let card: CardCarousel.Card
    let blockID: String
    var contentStyle: PageExpansionSource.ContentStyle = .article
    var elevation: CardElevation? = nil
    @Environment(ConversationStore.self) private var store
    @Environment(\.renderedPage) private var renderedPage

    func body(content: Content) -> some View {
        Button {
            guard blockInteraction.allowsStoreMutation else { return }
            guard let renderedPage else { return }
            _ = store.openExpansion(card: card, blockID: blockID, from: renderedPage,
                                    contentStyle: contentStyle)
        } label: {
            if let elevation {
                content.modifier(ExpansionZoomSource(card: card, blockID: blockID, elevation: elevation,
                                                     drawsRestingShadow: false))
            } else {
                content
            }
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

    static func media(_ corner: CGFloat) -> CardElevation {
        CardElevation(corner: corner, ambient: (0.13, 12, 5), contact: (0.05, 1.3, 1))
    }

    static func flat(_ corner: CGFloat) -> CardElevation {
        CardElevation(corner: corner, ambient: (0, 0, 0), contact: (0, 0, 0))
    }

    var castsShadow: Bool { ambient.opacity > 0 || contact.opacity > 0 }
}

struct CardZoomSource: ViewModifier {
    let id: String?
    let namespace: Namespace.ID?
    let elevation: CardElevation
    var drawsRestingShadow = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        let resting = RestingElevation(elevation: drawsRestingShadow ? elevation : nil)
        if !reduceMotion, let id, let namespace {
            content
                .matchedTransitionSource(id: id, in: namespace) { source in
                    source.clipShape(RoundedRectangle(cornerRadius: elevation.corner, style: .continuous))
                }
                .modifier(resting)
        } else {
            content.modifier(resting)
        }
    }
}

struct RestingElevation: ViewModifier {
    let elevation: CardElevation?

    func body(content: Content) -> some View {
        if let elevation, elevation.castsShadow {
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
