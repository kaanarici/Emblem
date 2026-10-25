import SwiftUI
import EmblemCore

struct WeatherView: View {
    let block: WeatherBlock
    @State private var selectedDate: String?
    @Environment(\.blockInteraction) private var blockInteraction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(block: WeatherBlock) {
        self.block = block
        _selectedDate = State(initialValue: block.focusDay == block.forecast.first?.date ? nil : block.focusDay)
    }

    private var selectedDay: WeatherBlock.DayForecast? {
        guard let selectedDate else { return nil }
        return block.forecast.first { $0.id == selectedDate }
    }

    private var forecast: [WeatherBlock.DayForecast] {
        block.forecast
    }

    private var hours: [WeatherBlock.HourForecast] {
        if let day = selectedDay { return day.hours }
        let now = block.current.observedAt.flatMap { Int($0.dropFirst(11).prefix(2)) } ?? 0
        let today = forecast.first?.hours ?? []
        let start = today.lastIndex { $0.hour <= now } ?? 0
        return Array((today.dropFirst(start) + forecast.dropFirst().flatMap(\.hours)).prefix(24))
    }

    private var condition: WeatherCondition { selectedDay?.condition ?? block.current.condition }
    private var temperature: Double { selectedDay?.high ?? block.current.tempC }
    private var high: Double { selectedDay?.high ?? block.current.high }
    private var low: Double { selectedDay?.low ?? block.current.low }
    private var isDay: Bool { selectedDay != nil || block.current.isDay != false }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 0) {
                    summary

                    if !hours.isEmpty {
                        hourlyForecast
                            .padding(.top, 52)
                    }
                }
                .id(selectedDate)
                .transition(.opacity)
            }

            if !forecast.isEmpty {
                weeklyForecast
                    .padding(.top, hours.isEmpty ? 44 : 49)
            }
        }
        .padding(.top, 80 / 3)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
    }

    private var summary: some View {
        VStack(spacing: 0) {
            WeatherConditionArtwork(condition: condition, isDay: isDay, size: 128)

            Text(block.location)
                .font(.system(size: 24, weight: .medium))
                .tracking(-7.0 / 12.0)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 40)

            Text(degrees(temperature))
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Theme.ink)
                .offset(x: 12)
                .frame(height: 72)
                .padding(.top, 10 / 3)
                .accessibilityLabel(degrees(temperature))

            Text(WeatherConditionArtwork.title(condition, isDay: isDay))
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .padding(.top, 7)

            Text("H: \(degrees(high)) L: \(degrees(low))")
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .padding(.top, 6)

            if let detail = detailLine {
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var hourlyForecast: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                    VStack(spacing: 0) {
                        WeatherConditionArtwork(condition: hour.condition, isDay: hour.isDay, size: 40)

                        Text(degrees(hour.tempC))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.top, 9)

                        Text(index == 0 && selectedDay == nil ? "Now" : String(format: "%02d", hour.hour))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(.top, 4)
                    }
                    .frame(width: 72)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("weather-hourly-\(block.id)")
    }

    private var weeklyForecast: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("This week")
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 32)

            if let text = weeklySummary {
                Text(text)
                    .font(.system(size: 16))
                    .lineSpacing(22 - UIFont.systemFont(ofSize: 16).lineHeight)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
                    .padding(.top, 7)
            }

            VStack(spacing: 4) {
                ForEach(Array(forecast.enumerated()), id: \.element.id) { index, day in
                    forecastRow(day, index: index)
                }
            }
            .compositingGroup()
            .modifier(RestingElevation(elevation: Self.dayElevation))
            .padding(.horizontal, 28)
            .padding(.top, 26)
        }
    }

    private static let dayElevation = CardElevation(corner: 22, ambient: (0.12, 8, 4), contact: (0.04, 1, 1))

    private func forecastRow(_ day: WeatherBlock.DayForecast, index: Int) -> some View {
        let selected = selectedDay?.id == day.id
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: index == 0 ? 22 : 6,
            bottomLeadingRadius: index == forecast.count - 1 ? 22 : 6,
            bottomTrailingRadius: index == forecast.count - 1 ? 22 : 6,
            topTrailingRadius: index == 0 ? 22 : 6,
            style: .continuous)

        return Button {
            guard blockInteraction.allowsActivation else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
                selectedDate = index == 0 ? nil : day.id
            }
        } label: {
            HStack(spacing: 0) {
                Text(Self.weekdayLabel(date: day.date, fallback: day.day))
                    .font(.system(size: day.day == "Today" ? 14 : 16, weight: .semibold))
                    .tracking(day.day == "Today" ? -0.25 : 0)
                    .frame(width: 60, alignment: .leading)

                WeatherConditionArtwork(condition: day.condition, size: 30)
                    .frame(width: 32)
                    .offset(x: -2)
                    .padding(.trailing, 6)

                Text(WeatherConditionArtwork.title(day.condition))
                    .font(.system(size: 16))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(degrees(day.high))
                    .font(.system(size: 16))
                    .frame(width: 48, alignment: .trailing)

                Text(degrees(day.low))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(InputPalette.optionStroke, lineWidth: 4 / 3).opacity(selected ? 1 : 0))
            .contentShape(shape)
        }
        .blockActivationControl()
        .buttonStyle(.pressable)
        .accessibilityIdentifier("weather-day-\(day.id)")
        .accessibilityLabel(
            "\(day.day), \(WeatherConditionArtwork.title(day.condition)), high \(degrees(day.high)), low \(degrees(day.low))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var weeklySummary: String? {
        guard forecast.count > 1 else { return nil }
        let highs = forecast.map(\.high)
        guard let minimum = highs.min(), let maximum = highs.max() else { return nil }
        let range = "Highs from \(degrees(minimum)) to \(degrees(maximum)) across the forecast."
        let wet = forecast.filter { [.drizzle, .rain, .snow, .thunderstorm].contains($0.condition) }
        if wet.count == 1, let day = wet.first {
            return "\(day.condition.label) on \(day.day). \(range)"
        }
        return range
    }

    private var detailLine: String? {
        let values: [String?]
        if let day = selectedDay {
            values = [
                day.day,
                day.precipitationProbability.map { "Rain \(percent($0))" },
                (day.windKph ?? block.current.windKph).map { "Wind \(whole($0)) km/h" },
            ]
        } else {
            let rain = [block.current.precipitationProbability, hours.map(\.precipitationProbability).max()]
                .compactMap { $0 }.max()
            values = [
                block.current.feelsLikeC.map { "Feels \(degrees($0))" },
                rain.map { "Rain \(percent($0))" },
                block.current.windKph.map { "Wind \(whole($0)) km/h" },
            ]
        }
        let text = values.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    private static func weekdayLabel(date: String?, fallback: String) -> String {
        let label = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.caseInsensitiveCompare("Today") == .orderedSame { return "Today" }
        if let date {
            let parser = DateFormatter()
            parser.calendar = Calendar(identifier: .gregorian)
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = TimeZone(secondsFromGMT: 0)
            parser.dateFormat = "yyyy-MM-dd"
            parser.isLenient = false
            if let value = parser.date(from: date), parser.string(from: value) == date {
                parser.dateFormat = "EEE"
                return parser.string(from: value)
            }
        }
        let weekdays = [
            "monday": "Mon", "tuesday": "Tue", "wednesday": "Wed",
            "thursday": "Thu", "friday": "Fri", "saturday": "Sat", "sunday": "Sun",
            "mon": "Mon", "tue": "Tue", "wed": "Wed", "thu": "Thu",
            "fri": "Fri", "sat": "Sat", "sun": "Sun",
        ]
        return weekdays[label.lowercased()] ?? fallback
    }

    private func whole(_ value: Double) -> String { String(Int(value.rounded())) }
    private func degrees(_ value: Double) -> String { "\(whole(value))°" }
    private func percent(_ value: Double) -> String { "\(whole(value))%" }
}

private struct WeatherConditionArtwork: View {
    let condition: WeatherCondition
    var isDay = true
    let size: CGFloat

    var body: some View {
        OriginalWeatherArtwork(condition: condition, isDay: isDay, size: size)
    }

    static func title(_ condition: WeatherCondition, isDay: Bool = true) -> String {
        condition == .clear && isDay ? "Sunny" : condition.label
    }
}

extension WeatherCondition {
    var sfSymbol: String {
        switch self {
        case .clear: "sun.max.fill"
        case .partlyCloudy: "cloud.sun.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .wind: "wind"
        }
    }

    var label: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly cloudy"
        case .cloudy: "Cloudy"
        case .fog: "Foggy"
        case .drizzle: "Drizzle"
        case .rain: "Rain"
        case .snow: "Snow"
        case .thunderstorm: "Thunderstorms"
        case .wind: "Windy"
        }
    }
}
