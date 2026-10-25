import CoreLocation
import Foundation

public struct MapBlock: Codable, Hashable {
    public struct Place: Codable, Hashable {
        public var name: String
        public var locality: String?
        public var searchQuery: String
        public var icon: Icon?
        public var rating: String?
        public var caption: String?
        public var price: String?
        public var category: String?
        public var metadata: [String]?
        public var lat: Double?
        public var lng: Double?
        public var address: String?

        public init(name: String, locality: String? = nil, searchQuery: String,
             icon: Icon? = nil, rating: String? = nil, caption: String? = nil,
             price: String? = nil, category: String? = nil, metadata: [String]? = nil,
             lat: Double? = nil, lng: Double? = nil, address: String? = nil) {
            self.lat = lat
            self.lng = lng
            self.address = address
            self.name = name
            self.locality = locality
            self.searchQuery = searchQuery
            self.icon = icon
            self.rating = rating
            self.caption = caption
            self.price = price
            self.category = category
            self.metadata = metadata
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            locality = try c.decodeIfPresent(String.self, forKey: .locality)
            searchQuery = try c.decode(String.self, forKey: .searchQuery)
            icon = try c.decodeIfPresent(Icon.self, forKey: .icon)
            rating = try c.decodeIfPresent(String.self, forKey: .rating)
            caption = try c.decodeIfPresent(String.self, forKey: .caption)
            price = try c.decodeIfPresent(String.self, forKey: .price)
            category = try? c.decodeIfPresent(String.self, forKey: .category)
            metadata = try? c.decodeIfPresent([String].self, forKey: .metadata)
            lat = try? c.decodeIfPresent(Double.self, forKey: .lat)
            lng = try? c.decodeIfPresent(Double.self, forKey: .lng)
            address = try? c.decodeIfPresent(String.self, forKey: .address)
        }

        public var coordinate: CLLocationCoordinate2D? {
            guard let lat, let lng, abs(lat) <= 90, abs(lng) <= 180 else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }
    public var id: String
    public var title: String?
    public var style: String?
    public var thin: Bool?
    public var places: [Place]
}

public struct RouteBlock: Codable, Hashable {
    public enum Mode: String, Codable, Hashable, CaseIterable { case driving, walking, transit, cycling }
    public struct Destination: Codable, Hashable {
        public var name: String
        public var locality: String?
        public var searchQuery: String
    }
    public var id: String
    public var destination: Destination
    public var mode: Mode

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        destination = try c.decode(Destination.self, forKey: .destination)
        mode = Mode(rawValue: (try? c.decode(String.self, forKey: .mode)) ?? "") ?? .driving
    }
}
