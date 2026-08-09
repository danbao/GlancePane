import Foundation

struct WeatherSnapshot: Codable, Equatable {
    let provider: WeatherProvider
    let locationName: String
    let locationID: String?
    let longitude: Double
    let latitude: Double
    let timeZoneIdentifier: String?
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
        timeZoneIdentifier: nil,
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

    private enum CodingKeys: String, CodingKey {
        case provider
        case locationName
        case locationID
        case longitude
        case latitude
        case timeZoneIdentifier
        case current
        case hourly
        case daily
        case minutely
        case precipitationSummary
        case airQuality
        case attributionURL
        case updatedAt
        case isCached
        case errorMessage
    }
}

extension WeatherSnapshot {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(WeatherProvider.self, forKey: .provider)
        locationName = try container.decode(String.self, forKey: .locationName)
        locationID = try container.decodeIfPresent(String.self, forKey: .locationID)
        longitude = try container.decode(Double.self, forKey: .longitude)
        latitude = try container.decode(Double.self, forKey: .latitude)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        current = try container.decodeIfPresent(CurrentWeather.self, forKey: .current)
        hourly = try container.decodeIfPresent([HourlyWeather].self, forKey: .hourly) ?? []
        daily = try container.decodeIfPresent([DailyWeather].self, forKey: .daily) ?? []
        minutely = try container.decodeIfPresent([MinutelyPrecipitation].self, forKey: .minutely) ?? []
        precipitationSummary = try container.decodeIfPresent(String.self, forKey: .precipitationSummary)
            ?? "No minute rain data"
        airQuality = try container.decodeIfPresent(AirQuality.self, forKey: .airQuality)
        attributionURL = try container.decodeIfPresent(String.self, forKey: .attributionURL)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isCached = try container.decodeIfPresent(Bool.self, forKey: .isCached) ?? false
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
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
