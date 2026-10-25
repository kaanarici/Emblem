import Foundation

public enum WeatherCondition: String, Codable, Hashable {
    case clear
    case partlyCloudy = "partly-cloudy"
    case cloudy
    case fog
    case drizzle
    case rain
    case snow
    case thunderstorm
    case wind

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = WeatherCondition(rawValue: raw) ?? .cloudy
    }
}

public struct WeatherBlock: Codable, Hashable {
    public struct Current: Codable, Hashable {
        public var observedAt: String?
        public var tempC: Double
        public var feelsLikeC: Double?
        public var condition: WeatherCondition
        public var high: Double
        public var low: Double
        public var humidityPct: Double?
        public var windKph: Double?
        public var precipitationMm: Double?
        public var precipitationProbability: Double?
        public var isDay: Bool?

        private enum CodingKeys: String, CodingKey {
            case observedAt, tempC, feels, feelsLikeC, condition, high, low
            case humid, humidityPct, windKph, precipitationMm, precipPct
            case precipitationProbability, isDay
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            observedAt = try? c.decode(String.self, forKey: .observedAt)
            tempC = try c.decode(Double.self, forKey: .tempC)
            feelsLikeC = (try? c.decode(Double.self, forKey: .feels))
                ?? (try? c.decode(Double.self, forKey: .feelsLikeC))
            condition = try c.decode(WeatherCondition.self, forKey: .condition)
            high = try c.decode(Double.self, forKey: .high)
            low = try c.decode(Double.self, forKey: .low)
            humidityPct = (try? c.decode(Double.self, forKey: .humid))
                ?? (try? c.decode(Double.self, forKey: .humidityPct))
            windKph = try? c.decode(Double.self, forKey: .windKph)
            precipitationMm = try? c.decode(Double.self, forKey: .precipitationMm)
            precipitationProbability = (try? c.decode(Double.self, forKey: .precipPct))
                ?? (try? c.decode(Double.self, forKey: .precipitationProbability))
            isDay = try? c.decode(Bool.self, forKey: .isDay)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(observedAt, forKey: .observedAt)
            try c.encode(tempC, forKey: .tempC)
            try c.encodeIfPresent(feelsLikeC, forKey: .feels)
            try c.encode(condition, forKey: .condition)
            try c.encode(high, forKey: .high)
            try c.encode(low, forKey: .low)
            try c.encodeIfPresent(humidityPct, forKey: .humid)
            try c.encodeIfPresent(windKph, forKey: .windKph)
            try c.encodeIfPresent(precipitationMm, forKey: .precipitationMm)
            try c.encodeIfPresent(precipitationProbability, forKey: .precipPct)
            try c.encodeIfPresent(isDay, forKey: .isDay)
        }
    }
    public struct HourForecast: Codable, Hashable {
        public var hour: Int
        public var tempC: Double
        public var condition: WeatherCondition
        public var precipitationProbability: Double
        public var isDay: Bool

        public init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            hour = try c.decode(Int.self)
            tempC = try c.decode(Double.self)
            condition = try c.decode(WeatherCondition.self)
            precipitationProbability = try c.decode(Double.self)
            isDay = try c.decode(Bool.self)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.unkeyedContainer()
            try c.encode(hour)
            try c.encode(tempC)
            try c.encode(condition)
            try c.encode(precipitationProbability)
            try c.encode(isDay)
        }
    }
    public struct DayForecast: Codable, Hashable, Identifiable {
        public var date: String?
        public var day: String
        public var condition: WeatherCondition
        public var high: Double
        public var low: Double
        public var precipitationProbability: Double?
        public var windKph: Double?
        public var uvIndex: Double?
        public var sunrise: String?
        public var sunset: String?
        public var hours: [HourForecast]
        public var id: String { date ?? day }

        private enum CodingKeys: String, CodingKey {
            case date, day, condition, high, low, precipPct
            case precipitationProbability, windKph, uvIndex, sunrise, sunset, hours
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date = try? c.decode(String.self, forKey: .date)
            day = try c.decode(String.self, forKey: .day)
            condition = try c.decode(WeatherCondition.self, forKey: .condition)
            high = try c.decode(Double.self, forKey: .high)
            low = try c.decode(Double.self, forKey: .low)
            precipitationProbability = (try? c.decode(Double.self, forKey: .precipPct))
                ?? (try? c.decode(Double.self, forKey: .precipitationProbability))
            windKph = try? c.decode(Double.self, forKey: .windKph)
            uvIndex = try? c.decode(Double.self, forKey: .uvIndex)
            sunrise = try? c.decode(String.self, forKey: .sunrise)
            sunset = try? c.decode(String.self, forKey: .sunset)
            hours = (try? c.decode([HourForecast].self, forKey: .hours)) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(date, forKey: .date)
            try c.encode(day, forKey: .day)
            try c.encode(condition, forKey: .condition)
            try c.encode(high, forKey: .high)
            try c.encode(low, forKey: .low)
            try c.encodeIfPresent(precipitationProbability, forKey: .precipPct)
            try c.encodeIfPresent(windKph, forKey: .windKph)
            try c.encodeIfPresent(uvIndex, forKey: .uvIndex)
            try c.encodeIfPresent(sunrise, forKey: .sunrise)
            try c.encodeIfPresent(sunset, forKey: .sunset)
            try c.encode(hours, forKey: .hours)
        }
    }
    public var id: String
    public var location: String
    public var focusDay: String?
    public var current: Current
    public var forecast: [DayForecast]
}
