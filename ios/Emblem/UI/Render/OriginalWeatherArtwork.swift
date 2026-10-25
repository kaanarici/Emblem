import SwiftUI
import UIKit
import EmblemCore

struct OriginalWeatherArtwork: View {
    let condition: WeatherCondition
    var isDay = true
    let size: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(named: asset.name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: size * 0.8))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var asset: Asset {
        switch condition {
        case .clear: isDay ? .clearDay : .clearNight
        case .partlyCloudy: isDay ? .partlyCloudyDay : .partlyCloudyNight
        case .cloudy: .cloudy
        case .fog: .fog
        case .drizzle: .rain
        case .rain: .rain
        case .snow: .snow
        case .thunderstorm: .thunderstorm
        case .wind: .wind
        }
    }

    private var fallbackSymbol: String {
        switch condition {
        case .clear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        default: condition.sfSymbol
        }
    }

    private enum Asset: String {
        case clearDay = "EmblemWeatherSun"
        case clearNight = "EmblemWeatherMoon"
        case partlyCloudyDay = "EmblemWeatherPartlyDay"
        case partlyCloudyNight = "EmblemWeatherPartlyNight"
        case cloudy = "EmblemWeatherCloud"
        case fog = "EmblemWeatherFog"
        case rain = "EmblemWeatherRain"
        case snow = "EmblemWeatherSnow"
        case thunderstorm = "EmblemWeatherThunder"
        case wind = "EmblemWeatherWind"

        var name: String { rawValue }
    }
}
