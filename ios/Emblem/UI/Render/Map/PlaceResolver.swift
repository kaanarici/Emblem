import SwiftUI
import MapKit
import CoreLocation
import EmblemCore

@MainActor
enum PlaceResolver {
    private struct ResolutionKey: Hashable {
        let name: String
        let locality: String?
        let query: String
    }
    private static var cache: [ResolutionKey: MKMapItem] = [:]
    private static var localityCache: [String: CLLocationCoordinate2D] = [:]
    private static let localityRadiusMeters: CLLocationDistance = 60_000

    static func resolve(_ target: DirectionsTarget) async -> MKMapItem? {
        await resolve(name: target.name, locality: target.locality, query: target.query)
    }

    static func resolve(name: String, locality: String?, query: String, address: String? = nil) async -> MKMapItem? {
        let key = ResolutionKey(name: name, locality: locality, query: query)
        if let cached = cache[key] { return cached }
        let anchor = await localityCenter(locality)
        var resolved: MKMapItem?
        if let address = address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty,
           normalized(address) != normalized(locality ?? ""),
           let item = try? await MKGeocodingRequest(addressString: address)?.mapItems.first,
           isNear(item, anchor) {
            item.name = name
            resolved = item
        }
        let queries = [query, [name, locality].compactMap { $0 }.joined(separator: ", "), name]
        var seen: Set<String> = []
        for text in queries where resolved == nil && seen.insert(text).inserted {
            resolved = await search(text, name: name, locality: locality, anchor: anchor)
        }
        if let resolved { cache[key] = resolved }
        return resolved
    }

    private static func search(_ text: String, name: String, locality: String?,
                               anchor: CLLocationCoordinate2D?) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let anchor {
            request.region = MKCoordinateRegion(
                center: anchor,
                latitudinalMeters: localityRadiusMeters,
                longitudinalMeters: localityRadiusMeters)
        }
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        return response.mapItems
            .map { item -> (item: MKMapItem, score: Int) in
                guard isNear(item, anchor) else { return (item, 0) }
                var value = score(item, name: name, locality: locality, anchored: anchor != nil)
                if value > 0, let anchor, distance(item, anchor) < 15_000 { value += 2 }
                return (item, value)
            }
            .filter { $0.score > 0 }
            .max { $0.score < $1.score }?.item
    }

    private static func isNear(_ item: MKMapItem, _ anchor: CLLocationCoordinate2D?) -> Bool {
        anchor.map { distance(item, $0) <= localityRadiusMeters } ?? true
    }

    private static func distance(_ item: MKMapItem, _ anchor: CLLocationCoordinate2D) -> CLLocationDistance {
        item.location.distance(from: CLLocation(latitude: anchor.latitude, longitude: anchor.longitude))
    }

    private static func localityCenter(_ locality: String?) async -> CLLocationCoordinate2D? {
        guard let locality = locality?.trimmingCharacters(in: .whitespacesAndNewlines),
              !locality.isEmpty else { return nil }
        if let cached = localityCache[locality] { return cached }
        let item = try? await MKGeocodingRequest(addressString: locality)?.mapItems.first
        guard let coordinate = item?.location.coordinate else { return nil }
        localityCache[locality] = coordinate
        return coordinate
    }

    private static func score(_ item: MKMapItem, name: String, locality: String?, anchored: Bool) -> Int {
        let expectedName = normalized(name)
        let actualName = normalized(item.name ?? "")
        guard !expectedName.isEmpty, !actualName.isEmpty else { return 0 }
        var value = actualName == expectedName ? 8
            : actualName.contains(expectedName) || expectedName.contains(actualName) ? 4
            : sharesDistinctiveWords(expectedName, actualName) ? 3 : 0
        guard value > 0 else { return 0 }
        if let locality {
            let expectedLocality = normalized(locality)
            let representation = item.addressRepresentations
            let localityRepresentations = [
                representation?.cityName,
                representation?.cityWithContext,
                representation?.regionName,
                representation?.fullAddress(includingRegion: true, singleLine: true),
            ].compactMap { $0 }.map(normalized)
            let matchesLocality = localityRepresentations.contains {
                $0 == expectedLocality || $0.contains(expectedLocality) || expectedLocality.contains($0)
            }
            if matchesLocality { value += 4 } else if !anchored { return 0 }
        }
        return value
    }

    private static let genericWords: Set<String> = [
        "the", "a", "an", "of", "and", "de", "da", "do", "la", "le", "el", "hotel", "restaurant", "cafe", "bar",
    ]

    private static func sharesDistinctiveWords(_ expected: String, _ actual: String) -> Bool {
        let words = Set(expected.split(separator: " ").map(String.init)).subtracting(genericWords)
        let candidate = Set(actual.split(separator: " ").map(String.init))
        guard !words.isEmpty else { return false }
        return Double(words.intersection(candidate).count) / Double(words.count) >= 0.5
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

func placeMapStyle(_ style: String?, pointsOfInterest: Bool) -> MapStyle {
    switch style {
    case "satellite": .imagery(elevation: .realistic)
    case "hybrid": .hybrid(elevation: .realistic, pointsOfInterest: pointsOfInterest ? .all : .excludingAll)
    default: .standard(emphasis: .muted, pointsOfInterest: pointsOfInterest ? .all : .excludingAll)
    }
}
