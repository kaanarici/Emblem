import SwiftUI
import MapKit
import CoreLocation
import EmblemCore

struct ExpandedMapView: View {
    let session: MapPresentation
    let close: () -> Void
    @Environment(ConversationStore.self) private var store
    @Environment(\.expansionNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsOverview = false
    @State private var projectedPins: [String: CGPoint] = [:]
    @State private var laneScrolling = false
    @State private var laneSettledAt = Date.distantPast
    @State private var mapSize = CGSize.zero
    @State private var mapCamera: MapCamera?
    @State private var revealsInitialSelection = true

    private var thin: Bool { session.block.thin == true }

    private var overviewText: String? {
        session.parent.blocks.lazy.compactMap { block -> String? in
            if case .text(let text) = block, text.style == .intro { return text.body }
            return nil
        }.first ?? session.block.title
    }

    private var motion: Animation {
        let base: Animation = reduceMotion ? .easeOut(duration: 0.16) : .spring(duration: 0.36, bounce: 0.12)
        return base
    }
    var body: some View {
        @Bindable var model = session.model
        let layout = PlaceMapLayout(model.pins, at: projectedPins, selectedID: session.selectedPlaceID)
        ZStack {
            MapReader { proxy in
                Map(position: $model.camera) {
                    UserAnnotation()
                    ForEach(model.pins) { pin in
                        let role = layout.role(pin.id)
                        Annotation(pin.name, coordinate: pin.coordinate, anchor: .center) {
                            Button {
                                guard session.interaction.allowsActivation else { return }
                                if role == .marker || session.selectedPlaceID == pin.id {
                                    withAnimation(motion) { session.select(pin) }
                                } else {
                                    zoom(into: layout.members[pin.id] ?? [pin.id])
                                }
                            } label: {
                                PlaceMarker(pin: pin, card: session.card(for: pin),
                                            selected: session.selectedPlaceID == pin.id,
                                            showsLabel: layout.labeled.contains(pin.id),
                                            role: role, absorbed: layout.absorbed(pin.id))
                            }
                            .buttonStyle(.plain)
                            .disabled(!session.interaction.allowsActivation || role == .hidden)
                            .accessibilityLabel(clusterLabel(role, members: layout.members[pin.id]) ?? "Select \(pin.name)")
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(placeMapStyle(session.block.style, pointsOfInterest: true))
                .mapControls {}
                .onGeometryChange(for: CGSize.self, of: \.size) { mapSize = $0 }
                .onMapCameraChange(frequency: .continuous) { context in
                    mapCamera = context.camera
                    projectedPins = Dictionary(uniqueKeysWithValues: model.pins.compactMap { pin in
                        proxy.convert(pin.coordinate, to: .global).map { (pin.id, $0) }
                    })
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    session.visibleRegion = context.region
                    if revealsInitialSelection {
                        revealsInitialSelection = false
                        reveal(session.selectedPlaceID, proxy: proxy)
                    }
                }
                .onChange(of: session.selectedPlaceID) { _, id in reveal(id, proxy: proxy) }
            }
            .ignoresSafeArea()
            VStack {
                if thin { rail } else { squareBar }
                Spacer(minLength: 0)
                if session.isCardVisible {
                    cardLane
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if thin {
                    listViewButton
                        .padding(.bottom, 72)
                        .transition(.opacity)
                }
            }
        }
        .animation(motion, value: session.selectedPlaceID)
        .animation(motion, value: showsOverview)
        .environment(\.renderedPage, session.parent)
        .environment(\.blockInteraction, session.interaction)
        .onAppear {
            if let region = session.visibleRegion { model.camera = .region(region) }
        }
        .task { await session.model.load(session.block.places, thin: thin) }
        .accessibilityIdentifier("expanded-place-map")
    }

    private func clusterLabel(_ role: PlaceMapLayout.Role, members: [String]?) -> String? {
        guard case .cluster(let count) = role, let members else { return nil }
        let names = session.model.pins.filter { members.contains($0.id) }.map(\.place.displayName)
        return "\(count) places: \(names.joined(separator: ", ")). Zoom in"
    }

    private func zoom(into ids: [String]) {
        let coordinates = session.model.pins.filter { ids.contains($0.id) }.map(\.coordinate)
        guard let minLat = coordinates.map(\.latitude).min(), let maxLat = coordinates.map(\.latitude).max(),
              let minLon = coordinates.map(\.longitude).min(), let maxLon = coordinates.map(\.longitude).max()
        else { return }
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 3.2, 0.004),
                                    longitudeDelta: max((maxLon - minLon) * 3.2, 0.004))
        let lift = session.isCardVisible ? span.latitudeDelta * 0.22 : 0
        move(to: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 - lift, longitude: (minLon + maxLon) / 2),
            span: span)))
    }

    private func move(to position: MapCameraPosition) {
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.45)) { session.model.camera = position }
        }
    }

    private func reveal(_ id: String?, proxy: MapProxy) {
        guard let id, let point = projectedPins[id], let camera = mapCamera, mapSize != .zero else { return }
        let top: CGFloat = 200
        let bottom = mapSize.height - 390
        let horizontal: ClosedRange<CGFloat> = 80...(mapSize.width - 80)
        guard bottom > top, !(top...bottom).contains(point.y) || !horizontal.contains(point.x) else { return }
        let target = CGPoint(x: mapSize.width / 2, y: (top + bottom) / 2)
        let center = CGPoint(x: mapSize.width / 2 + point.x - target.x, y: mapSize.height / 2 + point.y - target.y)
        guard let coordinate = proxy.convert(center, from: .global) else { return }
        move(to: .camera(MapCamera(centerCoordinate: coordinate, distance: camera.distance,
                                   heading: camera.heading, pitch: camera.pitch)))
    }

    private var listViewButton: some View {
        Button(action: close) {
            HStack(spacing: 14) {
                ListViewMark()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 17, height: 16)
                Text("List view").font(.system(size: 16, weight: .semibold))
            }
            .padding(.leading, 13.5)
            .padding(.trailing, 15.5)
            .frame(height: 43)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .glassEffect(.clear.interactive(), in: .capsule)
        .accessibilityLabel("List view")
        .accessibilityIdentifier("map-list-view")
    }

    private var shareButton: some View {
        ShareLink(item: session.shareText) {
            ChromeGlyph(symbol: .share).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .blockActivationControl()
        .accessibilityLabel("Share map")
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var locationButton: some View {
        railButton("Show my location", action: { session.model.locateTapped() }) {
            Image(systemName: "location").font(.system(size: 20, weight: .regular))
        }
    }

    private var squareBar: some View {
        VStack(alignment: .trailing, spacing: 7) {
            HStack {
                Button(action: close) { CloseGlyph().frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close map")
                    .accessibilityIdentifier("map-close")
                    .glassEffect(.regular.interactive(), in: .circle)
                Spacer(minLength: 12)
                shareButton
            }
            .padding(.horizontal, 20)
            locationButton.padding(.trailing, 20)
        }
        .foregroundStyle(.primary)
    }

    private func railButton(_ label: String, action: @escaping () -> Void, @ViewBuilder glyph: () -> some View) -> some View {
        Button {
            guard session.interaction.allowsActivation else { return }
            action()
        } label: {
            glyph().frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .blockActivationControl()
        .accessibilityLabel(label)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var rail: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if let overviewText { overviewButton(overviewText) }
            shareButton
            locationButton
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.top, 55)
    }

    private func overviewButton(_ text: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: showsOverview ? 20 : 22, style: .circular)
        return Button {
            guard session.interaction.allowsActivation else { return }
            withAnimation(motion) { showsOverview.toggle() }
        } label: {
            ZStack(alignment: .topTrailing) {
                if showsOverview {
                    Text(text)
                        .font(.system(size: 16))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 13)
                        .padding(.bottom, 14)
                        .transition(.opacity)
                } else {
                    ChromeGlyph(symbol: .bubbleChat)
                        .frame(width: 44, height: 44)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: showsOverview ? .infinity : 44, alignment: .trailing)
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .blockActivationControl()
        .glassEffect(.regular.interactive(), in: shape)
        .accessibilityLabel(showsOverview ? text : "Show overview")
        .accessibilityIdentifier("map-overview")
    }

    private var cardLane: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(session.model.pins) { pin in
                        placeCard(pin).containerRelativeFrame(.horizontal).id(pin.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(get: { session.selectedPlaceID }, set: { id in
                guard let pin = session.model.pins.first(where: { $0.id == id }) else { return }
                withAnimation(motion) { session.select(pin) }
            }), anchor: .center)
            .onScrollPhaseChange { _, phase in
                laneScrolling = phase != .idle
                if phase == .idle { laneSettledAt = .now }
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                if let id = session.selectedPlaceID { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func placeCard(_ pin: MapBlockViewModel.Pin) -> some View {
        VStack(alignment: .leading, spacing: 0) {
                CardArtworkView(card: session.card(for: pin), maxPixelSize: 1200)
                    .frame(height: 176)
                    .frame(maxWidth: .infinity)
                    .clipped()
                VStack(alignment: .leading, spacing: 0) {
                    Text(pin.place.displayName).font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let caption = pin.place.caption {
                        Text(caption).font(.system(size: 16))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineSpacing(2)
                            .lineLimit(2, reservesSpace: true)
                            .padding(.top, 5)
                    }
                    let metadata = metadata(for: pin)
                    if !metadata.isEmpty {
                        Text(metadata.joined(separator: " · "))
                            .font(.system(size: 14)).foregroundStyle(Theme.inkSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 15)
                .padding(.bottom, 17)
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            guard !laneScrolling, Date.now.timeIntervalSince(laneSettledAt) > 0.2 else { return }
            _ = session.openPlace(pin, in: store)
        }
        .blockStoreMutationControl()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(pin.name), \(pin.place.caption ?? "Place details")")
        .accessibilityHint("Opens generated place detail")
        .modifier(CardZoomSource(
            id: session.transitionID(for: pin), namespace: namespace,
            elevation: CardElevation(
                corner: 22, ambient: (0.12, 16, 6), contact: (0, 0, 0))))
        .contextMenu {
            Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") {
                guard session.interaction.allowsActivation else { return }
                session.model.openDirections(for: pin)
            }.disabled(!session.interaction.allowsActivation)
            if let distance = session.model.distanceText(to: pin) { Text(distance) }
        }
        .padding(.horizontal, 16)
        .accessibilityAction(named: "Directions") {
            guard session.interaction.allowsActivation else { return }
            session.model.openDirections(for: pin)
        }
        .accessibilityAction(named: "Deselect place") {
            guard session.interaction.allowsActivation else { return }
            withAnimation(motion) { session.selectedPlaceID = nil }
        }
    }

    private func metadata(for pin: MapBlockViewModel.Pin) -> [String] {
        var values = pin.place.metadata ?? []
        if values.isEmpty, let category = pin.place.category { values.append(category) }
        for value in [pin.place.rating, pin.place.price].compactMap({ $0 }) where !values.contains(value) {
            values.append(value)
        }
        return values
    }
}

let markerOrange = LinearGradient(
    colors: [Color(red: 1, green: 0.66, blue: 0.33), Color(red: 0.98, green: 0.55, blue: 0.18)],
    startPoint: .top, endPoint: .bottom)
