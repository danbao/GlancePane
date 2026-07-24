import Foundation

struct WeatherSnapshot: Codable, Equatable {
    let provider: WeatherProvider
    let locationName: String
    let locationID: String?
    let longitude: Double
    let latitude: Double
    let current: CurrentWeather?
    let hourly: [HourlyWeather]
    let minutely: [MinutelyPrecipitation]
    let precipitationSummary: String
    let attributionURL: String?
    let updatedAt: Date
    var isCached: Bool
    var errorMessage: String?

    static let empty = WeatherSnapshot(
        provider: .qweather,
        locationName: AppConfig.default.weather.location.name,
        locationID: nil,
        longitude: 0,
        latitude: 0,
        current: nil,
        hourly: [],
        minutely: [],
        precipitationSummary: "Waiting for weather",
        attributionURL: nil,
        updatedAt: Date.distantPast,
        isCached: false,
        errorMessage: nil
    )
}

struct CurrentWeather: Codable, Equatable {
    let observedAt: Date?
    let temperatureCelsius: Double?
    let feelsLikeCelsius: Double?
    let condition: String
    let icon: String?
    let humidityPercent: Double?
    let windDirection: String?
    let windSpeedKph: Double?
    let precipitationMillimeters: Double?
}

struct HourlyWeather: Codable, Equatable, Identifiable {
    var id: Date { forecastAt }

    let forecastAt: Date
    let temperatureCelsius: Double?
    let condition: String
    let icon: String?
    let precipitationProbabilityPercent: Double?
    let precipitationMillimeters: Double?
}

struct MinutelyPrecipitation: Codable, Equatable, Identifiable {
    var id: Date { forecastAt }

    let forecastAt: Date
    let precipitationMillimeters: Double
    let type: String
}
