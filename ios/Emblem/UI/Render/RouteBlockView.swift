import SwiftUI
import MapKit
import CoreLocation
import UIKit
import EmblemCore

struct DirectionsChooser: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let destination: DirectionsTarget
    let resolvedItem: MKMapItem?
    @Environment(\.dismiss) private var dismiss
    @State private var searchedItem: MKMapItem?
    @State private var resolving = false
    @State private var resolutionFinished: Bool

    init(destination: DirectionsTarget, resolvedItem: MKMapItem? = nil) {
        self.destination = destination
        self.resolvedItem = resolvedItem
        _resolutionFinished = State(initialValue: resolvedItem != nil)
    }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text("Get directions")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(modeLabel) to \(displayName)")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            .padding(.top, 18)

            VStack(spacing: 0) {
                row("Apple Maps", symbol: "map.fill") { openAppleMaps() }
                    .disabled(mapItem == nil)
                    .opacity(mapItem == nil && !resolving ? 0.45 : 1)
                Divider().padding(.horizontal, 18)
                row("Google Maps", symbol: "globe.americas.fill") {
                    if let appURL = googleURL(scheme: "comgooglemaps", host: ""),
                       UIApplication.shared.canOpenURL(appURL) {
                        open(appURL)
                    } else if let webURL = googleURL(
                        scheme: "https",
                        host: "www.google.com",
                        path: "/maps/dir/") {
                        open(webURL)
                    }
                }
                .disabled(!resolutionFinished)
                .opacity(resolutionFinished ? 1 : 0.45)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, Theme.contentMargin)
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .task(id: destination.id) {
            guard resolvedItem == nil else { return }
            resolving = true
            searchedItem = await PlaceResolver.resolve(destination)
            resolving = false
            resolutionFinished = true
        }
    }

    private var mapItem: MKMapItem? { resolvedItem ?? searchedItem }
    private var displayName: String { mapItem?.name ?? destination.name }
    private var googleDestination: String {
        guard let coordinate = mapItem?.location.coordinate else { return destination.query }
        return "\(coordinate.latitude),\(coordinate.longitude)"
    }
    private var modeLabel: String {
        switch destination.mode {
        case .driving: "Driving"
        case .walking: "Walking"
        case .transit: "Transit"
        case .cycling: "Cycling"
        }
    }
    private var appleMode: String {
        switch destination.mode {
        case .driving: MKLaunchOptionsDirectionsModeDriving
        case .walking: MKLaunchOptionsDirectionsModeWalking
        case .transit: MKLaunchOptionsDirectionsModeTransit
        case .cycling: MKLaunchOptionsDirectionsModeCycling
        }
    }
    private var googleMode: String { destination.mode.googleMapsMode }

    private func openAppleMaps() {
        guard let mapItem else { return }
        let destination = MKMapItem(location: mapItem.location, address: nil)
        destination.name = self.destination.name
        MKMapItem.openMaps(
            with: [.forCurrentLocation(), destination],
            launchOptions: [MKLaunchOptionsDirectionsModeKey: appleMode])
        dismiss()
    }

    private func googleURL(scheme: String, host: String, path: String = "") -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.queryItems = scheme == "https"
            ? [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "destination", value: googleDestination),
                URLQueryItem(name: "travelmode", value: googleMode),
            ]
            : [
                URLQueryItem(name: "daddr", value: googleDestination),
                URLQueryItem(name: "directionsmode", value: googleMode),
            ]
        return components.url
    }

    private func open(_ url: URL) {
        UIApplication.shared.open(url)
        dismiss()
    }

    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: { blockInteraction.performActivation(action) }) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 26)
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .blockActivationControl()
        .buttonStyle(.pressable)
    }
}

struct RouteBlockView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(\.renderedPage) private var renderedPage
    let block: RouteBlock
    @Environment(ConversationStore.self) private var store
    @State private var model = RouteBlockViewModel()
    @State private var expanded = false
    @State private var showChooser = false
    @Namespace private var modeNamespace

    static let routeOrange = Color(red: 0xF4 / 255, green: 0x65 / 255, blue: 0x0C / 255)
    private static let cornerRadius: CGFloat = 22

    private var isDraft: Bool { renderedPage?.isStreamingDraft(block.id) == true }

    private var directionsTarget: DirectionsTarget {
        DirectionsTarget(
            name: block.destination.name,
            locality: block.destination.locality,
            query: block.destination.searchQuery,
            mode: DirectionsTarget.Mode(rawValue: model.mode.rawValue) ?? .driving)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        Button {
            guard blockInteraction.allowsActivation, model.state == .ready else { return }
            expanded = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                mapCard
                tripDetails
            }
            .background(Theme.surface)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 1) }
            .background { shape.fill(Theme.surface).shadow(color: .black.opacity(0.08), radius: 12, y: 4) }
            .contentShape(shape)
        }
        .blockActivationControl()
        .buttonStyle(.pressable)
        .accessibilityLabel("Expand route to \(block.destination.name)")
        .accessibilityIdentifier("route-card")
        .padding(.horizontal, 28)
        .task(id: LoadKey(block: block, draft: isDraft)) {
            guard !isDraft else { return }
            await model.load(block, origin: store.locationSnapshot)
        }
        .fullScreenCover(isPresented: $expanded, onDismiss: { model.recenter() }) { fullRoute }
    }

    private struct LoadKey: Hashable {
        let block: RouteBlock
        let draft: Bool
    }

    @MapContentBuilder private var routeContent: some MapContent {
        UserAnnotation()
        if let destination = model.destination {
            Annotation(model.destinationItem?.name ?? block.destination.name, coordinate: destination) {
                badge
            }
        }
        if let polyline = model.routePolyline {
            MapPolyline(polyline)
                .stroke(Self.routeOrange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
    }

    private var mapCard: some View {
        ZStack {
            Theme.card
            Map(position: $model.camera, interactionModes: []) {
                routeContent
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .allowsHitTesting(false)
            .opacity(model.state == .ready ? 1 : 0)
            if case .failed(let message) = model.state {
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(height: 330)
        .clipped()
        .animation(.easeOut(duration: 0.25), value: model.state)
    }

    private var fullRoute: some View {
        ZStack(alignment: .top) {
            Map(position: $model.camera) {
                routeContent
            }
            .mapStyle(.standard(emphasis: .muted))
            .mapControls {}
            .ignoresSafeArea()

            HStack(alignment: .top) {
                chromeButton("Close route", gated: false) {
                    expanded = false
                } glyph: {
                    CloseGlyph()
                }
                .accessibilityIdentifier("route-close")
                Spacer(minLength: 12)
                chromeButton("Refit route") {
                    model.recenter()
                } glyph: {
                    Image(systemName: "location").font(.system(size: 20, weight: .regular))
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)

            VStack(spacing: 10) {
                Spacer(minLength: 0)
                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        modePicker
                        tripCard
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .task { await model.prefetchModes() }
        .sheet(isPresented: $showChooser) {
            DirectionsChooser(destination: directionsTarget, resolvedItem: model.destinationItem)
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(RouteBlock.Mode.allCases, id: \.self) { mode in
                let selected = model.mode == mode
                Button {
                    guard blockInteraction.allowsActivation else { return }
                    withAnimation(.spring(duration: 0.32, bounce: 0.12)) { model.mode = mode }
                    Task { await model.select(mode) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: RouteBlockViewModel.symbol(for: mode))
                            .font(.system(size: 14, weight: .semibold))
                        Text(model.shortTime(for: mode) ?? RouteBlockViewModel.label(for: mode))
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundStyle(selected ? Theme.onAccent : Theme.ink)
                    .opacity(model.isUnavailable(mode) && !selected ? 0.4 : 1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background {
                        if selected {
                            Capsule().fill(Theme.accentDark)
                                .matchedGeometryEffect(id: "mode", in: modeNamespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .blockActivationControl()
                .accessibilityLabel(RouteBlockViewModel.label(for: mode))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("route-mode-\(mode.rawValue)")
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }

    private var tripCard: some View {
        HStack(spacing: 14) {
            Image(systemName: model.modeSymbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.timeText ?? (model.isUnavailable(model.mode) ? "No \(RouteBlockViewModel.label(for: model.mode).lowercased()) route" : "–"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text(model.distanceText ?? " ")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 12)
            Button {
                guard blockInteraction.allowsActivation else { return }
                showChooser = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Directions")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.accentDark, in: Capsule())
            }
            .blockActivationControl()
            .buttonStyle(.pressable)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private func chromeButton(
        _ label: String,
        gated: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder glyph: () -> some View
    ) -> some View {
        Button {
            guard !gated || blockInteraction.allowsActivation else { return }
            action()
        } label: {
            glyph().frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(Self.routeOrange)
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
            Image(systemName: "mappin")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var tripDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trip details")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .textCase(.uppercase)
                .kerning(0.5)
            HStack(spacing: 24) {
                detail(icon: model.modeSymbol, label: model.timeText ?? "About 00 min")
                detail(icon: "point.topleft.down.to.point.bottomright.curvepath", label: model.distanceText ?? "0.0 mi")
                Spacer(minLength: 0)
            }
            .redacted(reason: model.timeText == nil ? .placeholder : [])
        }
        .padding(16)
    }

    private func detail(icon: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
    }
}

@MainActor @Observable
final class RouteBlockViewModel: NSObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case idle
        case locating
        case ready
        case failed(String)
    }

    struct Leg {
        let polyline: MKPolyline?
        let time: TimeInterval
        let distance: CLLocationDistance
    }

    var camera: MapCameraPosition = .automatic
    var destination: CLLocationCoordinate2D?
    var destinationItem: MKMapItem?
    var state: State = .idle
    var mode: RouteBlock.Mode = .driving
    private(set) var legs: [RouteBlock.Mode: Leg] = [:]
    private var unavailable: Set<RouteBlock.Mode> = []
    private var origin: CLLocationCoordinate2D?
    private var loadedKey: String?

    private let locationManager = CLLocationManager()

    var routePolyline: MKPolyline? { legs[mode]?.polyline }
    var timeText: String? { legs[mode].map { "About \(Self.formatTime($0.time))" } }
    var distanceText: String? { legs[mode].map { Self.formatDistance($0.distance) } }
    var modeSymbol: String { Self.symbol(for: mode) }

    func isUnavailable(_ mode: RouteBlock.Mode) -> Bool { unavailable.contains(mode) }
    func shortTime(for mode: RouteBlock.Mode) -> String? { legs[mode].map { Self.formatTime($0.time) } }

    func load(_ block: RouteBlock, origin snapshot: LocationSnapshot?) async {
        let key = "\(block.destination.searchQuery)|\(block.mode.rawValue)"
        guard loadedKey != key else { return }
        loadedKey = key
        mode = block.mode
        legs = [:]
        unavailable = []
        state = .locating

        guard let mapItem = await PlaceResolver.resolve(
            name: block.destination.name,
            locality: block.destination.locality,
            query: block.destination.searchQuery)
        else {
            state = .failed("Couldn't find \(block.destination.name).")
            loadedKey = nil
            return
        }
        destinationItem = mapItem
        destination = mapItem.location.coordinate

        if let snapshot {
            origin = CLLocationCoordinate2D(latitude: snapshot.latitude, longitude: snapshot.longitude)
            await compute(mode)
        } else {
            requestOwnLocation()
        }
    }

    func select(_ mode: RouteBlock.Mode) async {
        self.mode = mode
        if let leg = legs[mode] {
            fitCamera(leg)
        } else if !unavailable.contains(mode) {
            await compute(mode)
        }
    }

    func prefetchModes() async {
        for mode in RouteBlock.Mode.allCases where legs[mode] == nil && !unavailable.contains(mode) {
            await compute(mode)
        }
    }

    func recenter() {
        if let leg = legs[mode] { fitCamera(leg) }
    }

    private func requestOwnLocation() {
        locationManager.delegate = self
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        default:
            failLocating()
        }
    }

    private func compute(_ mode: RouteBlock.Mode) async {
        guard let origin, let destinationItem else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: origin.latitude, longitude: origin.longitude),
            address: nil)
        request.destination = destinationItem
        request.transportType = Self.transportType(for: mode)

        var leg: Leg?
        if let route = try? await MKDirections(request: request).calculate().routes.first {
            leg = Leg(polyline: route.polyline, time: route.expectedTravelTime, distance: route.distance)
        } else if let eta = try? await MKDirections(request: request).calculateETA() {
            leg = Leg(polyline: nil, time: eta.expectedTravelTime, distance: eta.distance)
        }
        guard let leg else {
            unavailable.insert(mode)
            if mode == self.mode, state != .ready {
                state = .failed("No \(Self.label(for: mode).lowercased()) route to the destination.")
                loadedKey = nil
            }
            return
        }
        legs[mode] = leg
        guard mode == self.mode else { return }
        fitCamera(leg)
        state = .ready
    }

    private func fitCamera(_ leg: Leg) {
        var rect = leg.polyline?.boundingMapRect ?? .null
        for coordinate in [origin, destination].compactMap({ $0 }) {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        guard !rect.isNull else { return }
        let padded = rect.insetBy(dx: -max(rect.width * 0.2, 400), dy: -max(rect.height * 0.2, 400))
        withAnimation(.smooth(duration: 0.6)) {
            camera = .rect(padded)
        }
    }

    private func failLocating() {
        state = .failed("Turn on location to see your route.")
        loadedKey = nil
    }

    private static func transportType(for mode: RouteBlock.Mode) -> MKDirectionsTransportType {
        switch mode {
        case .driving: .automobile
        case .walking: .walking
        case .transit: .transit
        case .cycling: .cycling
        }
    }

    static func symbol(for mode: RouteBlock.Mode) -> String {
        switch mode {
        case .driving: "car.fill"
        case .walking: "figure.walk"
        case .transit: "tram.fill"
        case .cycling: "bicycle"
        }
    }

    static func label(for mode: RouteBlock.Mode) -> String {
        switch mode {
        case .driving: "Drive"
        case .walking: "Walk"
        case .transit: "Transit"
        case .cycling: "Cycle"
        }
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .short
        formatter.zeroFormattingBehavior = .dropAll
        return (formatter.string(from: max(seconds, 60)) ?? "\(Int(seconds / 60)) min")
            .replacingOccurrences(of: ",", with: "")
    }

    private static func formatDistance(_ meters: CLLocationDistance) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.locationManager.requestLocation()
            case .denied, .restricted:
                self.failLocating()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            guard self.origin == nil, self.destinationItem != nil else { return }
            self.origin = coordinate
            await self.compute(self.mode)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if self.origin == nil { self.failLocating() }
        }
    }
}
