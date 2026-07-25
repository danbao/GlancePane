import Foundation

struct WeatherSnapshot: Codable, Equatable {
    let provider: WeatherProvider
    let locationName: String
    let locationID: String?
    let longitude: Double
    let latitude: Double
    let current: CurrentWeather?
    let hourly: [HourlyWeather]
    let daily: [DailyWeather]
    let minutely: [MinutelyPrecipitation]
    let precipitationSummary: String
    let airQuality: AirQuality?
    let attributionURL: String?
    let updatedAt: Date
    var isCached: Bool
    var errorMessage: String?

    static let empty = WeatherSnapshot(
        provider: .openMeteo,
        locationName: AppConfig.default.weather.location.name,
        locationID: nil,
        longitude: 0,
        latitude: 0,
        current: nil,
        hourly: [],
        daily: [],
        minutely: [],
        precipitationSummary: "Waiting for weather",
        airQuality: nil,
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

struct DailyWeather: Codable, Equatable, Identifiable {
    var id: Date { date }

    let date: Date
    let tempMax: Double?
    let tempMin: Double?
    let condition: String
    let icon: String?
    let precipitationProbabilityPercent: Double?
    let precipitationMillimeters: Double?
}

struct AirQuality: Codable, Equatable {
    let aqi: Double?
    let category: String
    let primaryPollutantName: String?
    let pm25: Double?
    let pm10: Double?
    let ozone: Double?
    let nitrogenDioxide: Double?

    static let unknownCategory = "N/A"
}
