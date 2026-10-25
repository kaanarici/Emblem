import SwiftUI
import MapKit
import CoreLocation
import EmblemCore

struct AreaReading: Equatable {
    var center: CLLocationCoordinate2D
    var meters: Double
    var locality: String?
    var spot: String?

    static func == (a: Self, b: Self) -> Bool {
        a.center.latitude == b.center.latitude && a.center.longitude == b.center.longitude
            && a.meters == b.meters && a.locality == b.locality && a.spot == b.spot
    }
}

enum AreaSelection: Hashable {
    case nearYou
    case spot(String)

    static var debugLaunch: AreaSelection? {
        #if DEBUG
        ProcessInfo.processInfo.environment["EMBLEM_AREA_SELECT"].map(AreaSelection.spot)
        #else
        nil
        #endif
    }
}

struct AreaLensMap: View {
    let spots: [AreaSpot]
    let lensCenter: CGFloat
    @Binding var selection: AreaSelection?
    var onReading: (AreaReading) -> Void

    static let lensFraction: CGFloat = 0.926

    @State private var position: MapCameraPosition = .automatic
    @State private var camera: MapCamera?
    @State private var settledCamera: MapCamera?
    @State private var reading: AreaReading?
    @State private var geocode: Task<Void, Never>?
    @State private var location = CLLocationManager()
    @State private var started = false
    @State private var projected: [String: CGPoint] = [:]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let lensY = height * lensCenter
            let mapHeight = 2 * max(lensY, height - lensY)
            let diameter = width * Self.lensFraction
            MapReader { proxy in
                ZStack {
                    Map(position: $position, interactionModes: [.pan, .zoom]) {
                        UserAnnotation()
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .mapControls {}
                    .onMapCameraChange(frequency: .continuous) { context in
                        follow(context.camera)
                        project(proxy)
                    }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        settle(context.camera, proxy: proxy, diameter: diameter,
                               center: CGPoint(x: width / 2, y: mapHeight / 2))
                    }

                    AreaVeil(diameter: diameter)
                        .allowsHitTesting(false)

                    pins
                        .frame(width: width, height: mapHeight)
                        .allowsHitTesting(false)

                    AreaRim(diameter: diameter)
                        .allowsHitTesting(false)

                    AreaArcLabel(reading: reading, radius: diameter / 2 + 5)
                        .opacity(isSettled ? 1 : 0)
                        .animation(.easeOut(duration: isSettled ? 0.3 : 0.12), value: isSettled)
                        .allowsHitTesting(false)
                }
                .frame(width: width, height: mapHeight)
            }
            .frame(width: width, height: mapHeight)
            .offset(y: lensY - mapHeight / 2)
            .frame(width: width, height: height, alignment: .top)
            .clipped()
            .onChange(of: width, initial: true) { _, width in
                start(width: width, diameter: width * Self.lensFraction)
            }
            .onChange(of: selection) { _, selection in fly(to: selection, width: width, diameter: diameter) }
        }
    }

    private var isSettled: Bool {
        guard let camera, let settledCamera, reading != nil else { return false }
        return camera.isNear(settledCamera)
    }

    private func start(width: CGFloat, diameter: CGFloat) {
        guard !started, width > 0 else { return }
        started = true
        if case .spot(let label) = selection, let spot = spots.first(where: { $0.label == label }) {
            position = Self.region(spot.coordinate, meters: spot.km * 2000, width: width, diameter: diameter)
        } else if selection == .nearYou || spots.isEmpty {
            flyNearYou(width: width, diameter: diameter, animated: false)
        } else {
            position = Self.overview(spots, width: width, diameter: diameter)
        }
    }

    private func fly(to selection: AreaSelection?, width: CGFloat, diameter: CGFloat) {
        switch selection {
        case .spot(let label):
            guard let spot = spots.first(where: { $0.label == label }),
                  settledCamera.map({ !$0.centerCoordinate.isNear(spot.coordinate) }) ?? true
            else { return }
            withAnimation(.smooth(duration: 1.1)) {
                position = Self.region(spot.coordinate, meters: spot.km * 2000, width: width, diameter: diameter)
            }
        case .nearYou:
            flyNearYou(width: width, diameter: diameter, animated: true)
        case nil:
            break
        }
    }

    private func flyNearYou(width: CGFloat, diameter: CGFloat, animated: Bool) {
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
        let target: MapCameraPosition = location.location.map {
            Self.region($0.coordinate, meters: 10_000, width: width, diameter: diameter)
        } ?? .userLocation(fallback: .automatic)
        if animated {
            withAnimation(.smooth(duration: 1.1)) { position = target }
        } else {
            position = target
        }
    }

    private func follow(_ next: MapCamera) {
        camera = next
    }

    private func settle(_ final: MapCamera, proxy: MapProxy, diameter: CGFloat, center: CGPoint) {
        guard started else { return }
        follow(final)
        settledCamera = final
        guard let left = proxy.convert(CGPoint(x: center.x - diameter / 2, y: center.y), from: .local),
              let right = proxy.convert(CGPoint(x: center.x + diameter / 2, y: center.y), from: .local)
        else { return }
        let meters = CLLocation(latitude: left.latitude, longitude: left.longitude)
            .distance(from: CLLocation(latitude: right.latitude, longitude: right.longitude))
        let centerCoordinate = final.centerCoordinate
        if case .spot(let label) = selection, let spot = spots.first(where: { $0.label == label }),
           CLLocation(spot.coordinate).distance(from: CLLocation(centerCoordinate)) > meters * 0.2 {
            selection = nil
        }
        let spot: String? = if case .spot(let label) = selection { label } else { nil }
        let keepLocality = reading.map {
            CLLocation($0.center).distance(from: CLLocation(centerCoordinate)) < meters * 0.1
                && abs($0.meters - meters) < meters * 0.1
        } ?? false
        let next = AreaReading(center: centerCoordinate, meters: meters,
                               locality: keepLocality ? reading?.locality : nil, spot: spot)
        reading = next
        onReading(next)
        guard !keepLocality else { return }
        geocode?.cancel()
        geocode = Task {
            let locality = await Self.locality(at: centerCoordinate, meters: meters)
            guard !Task.isCancelled, let current = reading,
                  CLLocation(current.center).distance(from: CLLocation(centerCoordinate)) < meters * 0.1
            else { return }
            reading?.locality = locality
            if let reading { onReading(reading) }
        }
    }

    static func locality(at coordinate: CLLocationCoordinate2D, meters: Double) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(coordinate)),
              let address = try? await request.mapItems.first?.addressRepresentations
        else { return nil }
        let names = meters > 80_000
            ? [address.regionName, address.cityWithContext(.short)]
            : [address.cityWithContext(.short), address.cityName, address.regionName]
        return names.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }

    static func region(_ center: CLLocationCoordinate2D, meters: Double, width: CGFloat,
                       diameter: CGFloat) -> MapCameraPosition {
        let across = meters * Double(width / diameter)
        return .region(MKCoordinateRegion(center: center, latitudinalMeters: across * 0.5,
                                          longitudinalMeters: across))
    }

    static func overview(_ spots: [AreaSpot], width: CGFloat, diameter: CGFloat) -> MapCameraPosition {
        let center = CLLocationCoordinate2D(
            latitude: spots.map(\.lat).reduce(0, +) / Double(spots.count),
            longitude: spots.map(\.lng).reduce(0, +) / Double(spots.count))
        let reach = spots.map { CLLocation($0.coordinate).distance(from: CLLocation(center)) + $0.km * 500 }
            .max() ?? 0
        let meters = reach * 2.1
        guard meters > 20_000, let lead = spots.first else {
            return region(center, meters: max(3_000, meters), width: width, diameter: diameter)
        }
        return region(lead.coordinate, meters: 20_000, width: width, diameter: diameter)
    }

    private var layout: PlaceMapLayout {
        PlaceMapLayout(spots.map { .init(id: $0.label, name: $0.label, category: nil) },
                       at: projected, selectedID: chosen)
    }

    private var chosen: String? {
        if isSettled, case .spot(let label) = selection { label } else { nil }
    }

    private var pins: some View {
        let layout = layout
        return ZStack {
            ForEach(spots, id: \.label) { spot in
                if let point = projected[spot.label] {
                    marker(spot, layout: layout).position(point)
                }
            }
        }
    }

    private func marker(_ spot: AreaSpot, layout: PlaceMapLayout) -> some View {
        PlaceMarker(
            name: spot.label, category: nil, icon: Icon(sfSymbol: spot.glyph),
            artwork: spot.icon.flatMap { $0.isEmpty ? nil : .object(Icon(
                sfSymbol: spot.glyph, image: ImageSpec(query: $0, kind: .object))) },
            selected: chosen == spot.label,
            showsLabel: layout.labeled.contains(spot.label),
            role: layout.role(spot.label), absorbed: layout.absorbed(spot.label),
            balloonDiameter: 85, labelScale: 1.25)
            .allowsHitTesting(false)
    }

    private func project(_ proxy: MapProxy) {
        projected = Dictionary(spots.compactMap { spot in
            proxy.convert(spot.coordinate, to: .local).map { (spot.label, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }
}

extension AreaSpot {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

extension CLLocation {
    convenience init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension CLLocationCoordinate2D {
    func isNear(_ other: CLLocationCoordinate2D) -> Bool {
        abs(latitude - other.latitude) < 1e-6 && abs(longitude - other.longitude) < 1e-6
    }
}

extension MapCamera {
    func isNear(_ other: MapCamera) -> Bool {
        centerCoordinate.isNear(other.centerCoordinate) && abs(distance - other.distance) < max(1, distance * 1e-4)
    }
}

private struct AreaVeil: View {
    let diameter: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.addRect(CGRect(origin: .zero, size: geometry.size))
                path.addEllipse(in: CGRect(x: (geometry.size.width - diameter) / 2,
                                           y: (geometry.size.height - diameter) / 2,
                                           width: diameter, height: diameter))
            }
            .fill(Color(uiColor: .systemBackground).opacity(0.5), style: FillStyle(eoFill: true))
        }
    }
}

private struct AreaRim: View {
    let diameter: CGFloat

    var body: some View {
        Color.clear
            .frame(width: diameter, height: diameter)
            .glassEffect(.clear, in: Circle())
            .mask {
                RadialGradient(stops: [.init(color: .clear, location: 0.72),
                                       .init(color: .black, location: 0.88)],
                               center: .center, startRadius: 0, endRadius: diameter / 2)
            }
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.2), lineWidth: 0.75)
                    .frame(width: diameter, height: diameter)
            }
    }
}

private struct Ring: Shape {
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(ellipseIn: rect)
        path.addPath(Path(ellipseIn: rect.insetBy(dx: width, dy: width)).reversed)
        return path
    }
}

private extension Path {
    var reversed: Path { Path(UIBezierPath(cgPath: cgPath).reversing().cgPath) }
}
