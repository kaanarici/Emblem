import SwiftUI
import EmblemCore

struct WeatherView: View {
    let block: WeatherBlock

    @Environment(ConversationStore.self) private var store
    @Environment(\.renderedPage) private var renderedPage
    @Environment(\.expansionNamespace) private var expansionNamespace
    @Environment(\.blockInteraction) private var blockInteraction

    private var focusedDay: WeatherBlock.DayForecast? {
        guard let id = block.focusDay else { return nil }
        return block.forecast.first { $0.id == id || $0.day == id }
    }

    private var forecast: [WeatherBlock.DayForecast] {
        block.forecast
    }

    private var hours: [WeatherBlock.HourForecast] {
        guard let day = focusedDay else { return block.hourly ?? [] }
        guard let date = day.date else { return [] }
        return (block.hourly ?? []).filter { $0.time.hasPrefix(date) }
    }

    private var condition: WeatherCondition { focusedDay?.condition ?? block.current.condition }
    private var temperature: Double { focusedDay?.high ?? block.current.tempC }
    private var high: Double { focusedDay?.high ?? block.current.high }
    private var low: Double { focusedDay?.low ?? block.current.low }
    private var isDay: Bool { focusedDay != nil || block.current.isDay != false }

    var body: some View {
        VStack(spacing: 0) {
            if let day = focusedDay {
                Text(dateTitle(day))
                    .font(.system(size: 20))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
            }

            summary

            if !hours.isEmpty {
                hourlyForecast
                    .padding(.top, 52)
            }

            if !forecast.isEmpty {
                weeklyForecast
                    .padding(.top, hours.isEmpty ? 44 : 49)
            }
        }
        .padding(.top, focusedDay == nil ? 80 / 3 : 0)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background(Theme.responsePaper)
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
                ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                    VStack(spacing: 0) {
                        WeatherConditionArtwork(
                            condition: hour.condition, isDay: hour.isDay != false, size: 40)

                        Text(degrees(hour.tempC))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.top, 9)

                        Text(index == 0 && focusedDay == nil ? "Now" : timeLabel(hour.time))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(.top, 4)

                        if block.focus == .precipitation,
                           let probability = hour.precipitationProbability {
                            Text(percent(probability))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.inkSecondary)
                                .padding(.top, 6)
                        }
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
            .padding(.horizontal, 28)
            .padding(.top, 26)
        }
    }

    private static let dayElevation = CardElevation(corner: 6, ambient: (0.12, 8, 4), contact: (0.04, 1, 1))

    private func forecastRow(_ day: WeatherBlock.DayForecast, index: Int) -> some View {
        let card = expansionCard(day)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: index == 0 ? 22 : 6,
            bottomLeadingRadius: index == forecast.count - 1 ? 22 : 6,
            bottomTrailingRadius: index == forecast.count - 1 ? 22 : 6,
            topTrailingRadius: index == 0 ? 22 : 6,
            style: .continuous)

        return Button {
            guard blockInteraction.allowsStoreMutation else { return }
            openDay(card)
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

                if block.focus == .precipitation,
                   let probability = day.precipitationProbability {
                    Text(percent(probability))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.trailing, 8)
                }

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
            .contentShape(shape)
            .modifier(CardZoomSource(
                id: transitionID(card), namespace: expansionNamespace,
                elevation: Self.dayElevation, drawsRestingShadow: false))
        }
        .blockStoreMutationControl()
        .buttonStyle(WeatherDayPressStyle(elevation: Self.dayElevation))
        .accessibilityIdentifier("weather-day-\(day.id)")
        .accessibilityLabel(
            "\(day.day), \(WeatherConditionArtwork.title(day.condition)), high \(degrees(day.high)), low \(degrees(day.low))")
    }

    private func expansionCard(_ day: WeatherBlock.DayForecast) -> CardCarousel.Card {
        let date = day.date ?? day.day
        let focus: String
        switch block.focus {
        case .precipitation: focus = " Include precipitation probabilities and amounts."
        case .outdoors: focus = " Include wind, UV, sunrise and sunset for outdoor plans."
        default: focus = ""
        }
        return CardCarousel.Card(
            image: nil, imageURL: nil,
            icon: Icon(emoji: WeatherConditionArtwork.emoji(day.condition)),
            title: "\(block.location) · \(dateTitle(day))",
            caption: "\(WeatherConditionArtwork.title(day.condition)) · \(degrees(day.high)) \(degrees(day.low))",
            prompt: "Show the weather for \(block.location) on \(date). Focus on this date with its hourly forecast and the upcoming daily forecast.\(focus)",
            conversation: nil, automation: nil)
    }

    private func transitionID(_ card: CardCarousel.Card) -> String? {
        guard let renderedPage else { return nil }
        return "\(renderedPage.id.uuidString):" + PageExpansionSource.cardKey(blockID: block.id, card: card)
    }

    private func openDay(_ card: CardCarousel.Card) {
        guard let renderedPage else { return }
        store.openExpansion(card: card, blockID: block.id, from: renderedPage, contentStyle: .weather)
    }

    private var weeklySummary: String? {
        if let summary = block.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }
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

    private var precipitationProbability: Double? {
        [block.current.precipitationProbability,
         block.hourly?.compactMap(\.precipitationProbability).max()]
            .compactMap { $0 }.max()
    }

    private var detailLine: String? {
        let day = focusedDay
        let values: [String?]
        switch block.focus {
        case .precipitation:
            let probability = day?.precipitationProbability ?? precipitationProbability
            values = [
                probability.map { "Rain \(percent($0))" },
                day == nil ? block.current.precipitationMm.map { "\(whole($0)) mm" } : nil,
            ]
        case .outdoors:
            let forecast = day ?? block.forecast.first
            values = [
                (forecast?.windKph ?? block.current.windKph).map { "Wind \(whole($0)) km/h" },
                forecast?.uvIndex.map { "UV \(whole($0))" },
                forecast?.sunrise.map { "Sunrise \(timeLabel($0))" },
                forecast?.sunset.map { "Sunset \(timeLabel($0))" },
            ]
        default:
            values = [
                day == nil ? block.current.feelsLikeC.map { "Feels \(degrees($0))" } : nil,
                (day?.precipitationProbability ?? precipitationProbability).map { "Rain \(percent($0))" },
                (day?.windKph ?? block.current.windKph).map { "Wind \(whole($0)) km/h" },
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

    private func dateTitle(_ day: WeatherBlock.DayForecast) -> String {
        guard let date = day.date else { return day.day }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let value = parser.date(from: date) else { return day.day }
        let display = DateFormatter()
        display.locale = Locale(identifier: "en_US")
        display.timeZone = parser.timeZone
        display.dateFormat = "MMMM d, yyyy"
        return display.string(from: value)
    }

    private func timeLabel(_ value: String) -> String {
        guard let time = value.split(separator: "T").last,
              let hour = time.split(separator: ":").first,
              let number = Int(hour) else { return "–" }
        let minutes = time.split(separator: ":").dropFirst().first.map(String.init) ?? "00"
        if minutes == "00" { return String(format: "%02d", number) }
        return String(format: "%02d:%@", number, minutes)
    }

    private func whole(_ value: Double) -> String { String(Int(value.rounded())) }
    private func degrees(_ value: Double) -> String { "\(whole(value))°" }
    private func percent(_ value: Double) -> String { "\(whole(value))%" }
}

private struct WeatherDayPressStyle: ButtonStyle {
    let elevation: CardElevation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(RestingElevation(elevation: elevation))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { old, new in
                isEnabled && !old && new
            }
    }
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

    static func emoji(_ condition: WeatherCondition, isDay: Bool = true) -> String {
        switch condition {
        case .clear: isDay ? "☀️" : "🌙"
        case .partlyCloudy: isDay ? "🌤️" : "☁️"
        case .cloudy: "☁️"
        case .fog: "🌫️"
        case .drizzle: "🌦️"
        case .rain: "🌧️"
        case .snow: "🌨️"
        case .thunderstorm: "⛈️"
        case .wind: "💨"
        }
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
