import SwiftUI
import MapKit
import CoreLocation
import EmblemCore

@MainActor @Observable
final class MapBlockViewModel: NSObject, CLLocationManagerDelegate {
    struct Pin: Identifiable {
        let id: String
        let sourceIndex: Int
        let place: MapBlock.Place
        let mapItem: MKMapItem

        var name: String { place.name }
        var coordinate: CLLocationCoordinate2D { mapItem.location.coordinate }
    }

    var camera: MapCameraPosition = .automatic
    var pins: [Pin] = []
    private(set) var fitRegion: MKCoordinateRegion?
    private(set) var isFitted = false
    private(set) var fitRevision = 0
    var medianLatitude: Double {
        let sorted = pins.map(\.coordinate.latitude).sorted()
        guard !sorted.isEmpty else { return 0 }
        return (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
    }
    private var thin = false
    var selectedID: String?

    var selectedPin: Pin? { pins.first { $0.id == selectedID } }

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadedQueries: [String] = []
    @ObservationIgnored private var requestedQueries: [String] = []

    private let locationManager = CLLocationManager()
    private static let fallbackRadiusMeters: CLLocationDistance = 25_000
    private static let distanceFormatter = MKDistanceFormatter()

    func select(_ pin: Pin) { select(id: pin.id) }

    func select(id: String) {
        guard selectedID != id, pins.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    func distanceText(to pin: Pin) -> String? {
        guard let user = locationManager.location else { return nil }
        return Self.distanceFormatter.string(fromDistance: user.distance(from: pin.mapItem.location))
    }

    func load(_ places: [MapBlock.Place], thin: Bool) async {
        self.thin = thin
        requestedQueries = places.map(\.searchQuery)
        while let loadTask { await loadTask.value }
        let queries = places.map(\.searchQuery)
        if !queries.starts(with: loadedQueries) {
            pins = []
            loadedQueries = []
        }
        guard queries.count > loadedQueries.count else { return }
        let start = loadedQueries.count
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let verified = places.compactMap(\.coordinate).map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            }
            for (sourceIndex, place) in places.enumerated().dropFirst(start) {
                let mapItem: MKMapItem
                if let coordinate = place.coordinate {
                    mapItem = MKMapItem(
                        location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                        address: nil)
                    mapItem.name = place.name
                } else if let item = await PlaceResolver.resolve(
                    name: place.name, locality: place.locality, query: place.searchQuery, address: place.address),
                    verified.isEmpty || verified.contains(where: {
                        $0.distance(from: item.location) <= Self.fallbackRadiusMeters
                    }) {
                    mapItem = item
                } else {
                    continue
                }
                self.pins.append(Pin(id: "\(place.searchQuery)#\(sourceIndex)",
                                     sourceIndex: sourceIndex, place: place, mapItem: mapItem))
            }
            self.loadedQueries = queries
            if self.requestedQueries == queries { self.fitCamera() }
            self.loadTask = nil
        }
        loadTask = task
        await task.value
    }

    private func fitCamera() {
        let lats = pins.map(\.coordinate.latitude)
        let lons = pins.map(\.coordinate.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max()
        else { return }
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.6, 0.012),
                longitudeDelta: max((maxLon - minLon) * 1.6, 0.012)))
        fitRegion = region
        let latitudeDelta = region.span.latitudeDelta * (thin ? 1.4 : 1.3)
        let center = CLLocationCoordinate2D(
            latitude: region.center.latitude + latitudeDelta * (thin ? 0.015 : 0.09),
            longitude: region.center.longitude)
        camera = .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(
            latitudeDelta: latitudeDelta,
            longitudeDelta: region.span.longitudeDelta * (thin ? 1.1 : 1))))
        isFitted = true
        fitRevision += 1
    }

    func openDirections(for pin: Pin) {
        let destination = MKMapItem(location: pin.mapItem.location, address: nil)
        destination.name = pin.name
        MKMapItem.openMaps(
            with: [destination],
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }

    func locateTapped() {
        locationManager.delegate = self
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            centerOnUser()
        default:
            break
        }
    }

    private func centerOnUser() {
        withAnimation(.smooth(duration: 0.5)) {
            camera = .userLocation(fallback: camera)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.centerOnUser()
            }
        }
    }
}
