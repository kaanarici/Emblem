import SwiftUI
import MapKit
import EmblemCore

@Observable @MainActor
final class MapPresentation: Identifiable {
    let id = UUID()
    let parent: GeneratedPage
    let block: MapBlock
    let model: MapBlockViewModel
    let interaction: BlockInteraction
    var selectedPlaceID: String?
    var visibleRegion: MKCoordinateRegion?

    init(parent: GeneratedPage, block: MapBlock, model: MapBlockViewModel, interaction: BlockInteraction) {
        self.parent = parent
        self.block = block
        self.model = model
        self.interaction = interaction
    }

    var isCardVisible: Bool { selectedPin != nil }
    var selectedPin: MapBlockViewModel.Pin? {
        model.pins.first { $0.id == selectedPlaceID }
    }
    var mapTransitionID: String { Self.transitionID(parent: parent, blockID: block.id) }
    static func transitionID(parent: GeneratedPage, blockID: String) -> String {
        "map:\(parent.id.uuidString):\(blockID)"
    }
    var shareText: String {
        ([block.title].compactMap { $0 } + block.places.map { place in
            [place.name, place.locality].compactMap { $0 }.joined(separator: ", ")
        }).joined(separator: "\n")
    }
    func card(for pin: MapBlockViewModel.Pin) -> CardCarousel.Card {
        let locality = pin.place.locality.map { " in \($0)" } ?? ""
        return CardCarousel.Card(
            image: MapBlockView.cardPhoto(pin.place), title: pin.name,
            caption: pin.place.caption,
            prompt: "Tell me more about \(pin.name)\(locality) (\(pin.place.searchQuery)): what it's like, what to order or do there, and what to know before going.")
    }
    func expansionBlockID(for pin: MapBlockViewModel.Pin) -> String {
        "\(block.id):place:\(pin.sourceIndex)"
    }
    func transitionID(for pin: MapBlockViewModel.Pin) -> String {
        "\(parent.id.uuidString):\(PageExpansionSource.cardKey(blockID: expansionBlockID(for: pin), card: card(for: pin)))"
    }
    func select(_ pin: MapBlockViewModel.Pin) {
        selectedPlaceID = pin.id
        model.select(pin)
    }
    @discardableResult
    func openPlace(_ pin: MapBlockViewModel.Pin, in store: ConversationStore) -> Bool {
        guard interaction.allowsStoreMutation else { return false }
        return store.openExpansion(card: card(for: pin), blockID: expansionBlockID(for: pin), from: parent)
    }
}

private struct PresentExpandedMapKey: EnvironmentKey {
    static let defaultValue: (@MainActor (MapPresentation) -> Void)? = nil
}
extension EnvironmentValues {
    var presentExpandedMap: (@MainActor (MapPresentation) -> Void)? {
        get { self[PresentExpandedMapKey.self] }
        set { self[PresentExpandedMapKey.self] = newValue }
    }
}
