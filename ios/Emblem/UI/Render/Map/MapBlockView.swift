import SwiftUI
import MapKit
import CoreLocation
import EmblemCore

struct MapBlockView: View {
    let block: MapBlock
    @Environment(\.renderedPage) private var renderedPage
    @Environment(\.blockInteraction) private var interaction
    @Environment(\.presentExpandedMap) private var presentMap
    @Environment(\.expansionNamespace) private var namespace
    @State private var model = MapBlockViewModel()
    @State private var presentation: MapPresentation?
    @State private var camera: MapCameraPosition = .automatic
    @State private var projectedPins: [String: CGPoint] = [:]

    private var thin: Bool { block.thin == true }
    private var cornerRadius: CGFloat { thin ? 20 : 22 }

    var body: some View {
        MapReader { proxy in
            ZStack {
                Map(position: $camera, interactionModes: []) {}
                    .mapStyle(placeMapStyle(block.style, pointsOfInterest: false))
                    .onMapCameraChange(frequency: .continuous) { _ in project(proxy) }
                    .opacity(model.isFitted ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Button { openMap(selecting: nil) } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .blockActivationControl()
                .disabled(presentMap == nil || renderedPage == nil)
                .accessibilityLabel("Expand map\(block.title.map { ": \($0)" } ?? "")")
                if model.isFitted {
                    let layout = PlaceMapLayout(model.pins, at: projectedPins, selectedID: nil)
                    ForEach(model.pins) { pin in
                        if let point = projectedPins[pin.id] {
                            let role = layout.role(pin.id)
                            Button { openMap(selecting: role == .marker ? pin : nil) } label: {
                                if thin {
                                    PlaceDot()
                                } else {
                                    PlaceMarker(pin: pin, card: nil, selected: false,
                                                showsLabel: layout.labeled.contains(pin.id), role: role)
                                }
                            }
                            .buttonStyle(.plain)
                            .blockActivationControl()
                            .disabled(presentMap == nil || renderedPage == nil)
                            .accessibilityLabel("Select \(pin.name)")
                            .position(point)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .background(Theme.card)
            .onChange(of: model.fitRevision, initial: true) { _, _ in
                guard model.isFitted, let region = model.fitRegion else { return }
                camera = .region(thin ? region.stripCrop(latitude: model.medianLatitude) : region)
            }
            .onChange(of: model.pins.map(\.id)) { _, _ in project(proxy) }
        }
        .animation(.easeOut(duration: 0.25), value: model.isFitted)
        .modifier(MapCardShape(thin: thin))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .modifier(CardZoomSource(
            id: renderedPage.map { MapPresentation.transitionID(parent: $0, blockID: block.id) },
            namespace: namespace,
            elevation: thin ? CardElevation(
                corner: cornerRadius, ambient: (0.1, 14, 5), contact: (0, 0, 0)) : .flat(cornerRadius)))
        .padding(.horizontal, 28)
        .task(id: streamedPlaces.map(\.searchQuery)) {
            await model.load(streamedPlaces, thin: thin)
            await ImageLoader.shared.prefetch(block.places.map(Self.cardPhoto), maxPixelSize: 1200, limit: 3)
        }
    }

    private var streamedPlaces: [MapBlock.Place] {
        renderedPage?.isStreamingDraft(block.id) == true ? Array(block.places.dropLast()) : block.places
    }

    private func project(_ proxy: MapProxy) {
        projectedPins = Dictionary(uniqueKeysWithValues: model.pins.compactMap { pin in
            proxy.convert(pin.coordinate, to: .local).map { (pin.id, $0) }
        })
    }

    private func openMap(selecting pin: MapBlockViewModel.Pin?) {
        guard interaction.allowsActivation, let interaction, let parent = renderedPage, let presentMap else { return }
        let session: MapPresentation
        if let current = presentation, current.parent === parent, current.block.id == block.id {
            session = current
        } else {
            session = MapPresentation(parent: parent, block: block, model: model, interaction: interaction)
            presentation = session
        }
        session.selectedPlaceID = pin?.id
        if let pin { session.select(pin) }
        presentMap(session)
    }

    static func cardPhoto(_ place: MapBlock.Place) -> ImageSpec {
        if let image = place.icon?.image, image.kind == .photo { return image.targeting(.landscape) }
        return ImageSpec(query: place.searchQuery, kind: .photo, aspect: .landscape)
    }
}
