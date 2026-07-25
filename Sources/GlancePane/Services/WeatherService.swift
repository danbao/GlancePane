import CryptoKit
import Foundation

final class WeatherService {
    private let cacheURL: URL
    private let client: HTTPClient
    private var cachedToken: CachedQWeatherToken?

    init(cacheURL: URL, client: HTTPClient? = nil) {
        self.cacheURL = cacheURL

        if let client {
            self.client = client
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 14
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.httpAdditionalHeaders = [
                "User-Agent": "GlancePane/0.1"
            ]
            self.client = URLSessionHTTPClient(configuration: config)
        }
    }

    func loadCached() -> WeatherSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL),
              var snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
        else { return nil }

        snapshot.isCached = true
        return snapshot
    }

    func fetch(config: AppConfig) async -> Result<WeatherSnapshot, WeatherFetchError> {
        guard config.weather.location.isConfigured else {
            return .failure(.setupRequired("Set a weather location in GlancePane Settings"))
        }

        switch config.weather.provider {
        case .qweather:
            return await fetchQWeather(config: config)
        case .openMeteo:
            return await fetchOpenMeteo(config: config)
        }
    }

    private func fetchQWeather(config: AppConfig) async -> Result<WeatherSnapshot, WeatherFetchError> {
        let apiHost = config.weather.qweather.apiHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiHost.isEmpty else {
            return .failure(.setupRequired("Set weather.qweather.apiHost in ~/.glancepane/config.json"))
        }

        let jwt: String
        do {
            jwt = try Self.effectiveJWT(config: config, cachedToken: &cachedToken)
        } catch WeatherServiceError.setupRequired(let message) {
            return .failure(.setupRequired(message))
        } catch {
            return .failure(.setupRequired(error.localizedDescription))
        }

        let cached = loadCached()
        guard let location = await resolveLocation(
            config: config,
            apiHost: apiHost,
            jwt: jwt,
            cached: cached
        ) else {
            return .failure(.setupRequired("Set a valid weather name or coordinates in GlancePane Settings"))
        }

        do {
            let snapshot = try await fetchQWeatherSnapshot(
                config: config,
                apiHost: apiHost,
                jwt: jwt,
                location: location,
                cached: cached
            )
            writeCache(snapshot)
            return .success(snapshot)
        } catch {
            if var cached {
                cached.errorMessage = error.localizedDescription
                cached.isCached = true
                return .failure(.usingCache(cached, error.localizedDescription))
            }
            return .failure(.network(error.localizedDescription))
        }
    }

    private func fetchQWeatherSnapshot(
        config: AppConfig,
        apiHost: String,
        jwt: String,
        location: ResolvedWeatherLocation,
        cached: WeatherSnapshot?
    ) async throws -> WeatherSnapshot {
        var current = cached?.current
        var hourly = cached?.hourly ?? []
        var daily = cached?.daily ?? []
        var minutely = cached?.minutely ?? []
        var summary = cached?.precipitationSummary ?? "No minute rain data"
        var airQuality = cached?.airQuality
        var attributionURL = cached?.attributionURL
        var errors: [Error] = []

        do {
            let result = try await fetchNow(apiHost: apiHost, jwt: jwt, location: location.weatherQuery)
            current = result.current
            attributionURL = result.attributionURL ?? attributionURL
        } catch {
            errors.append(error)
        }

        do {
            let result = try await fetchHourly(apiHost: apiHost, jwt: jwt, location: location.weatherQuery)
            hourly = result.hourly
            attributionURL = result.attributionURL ?? attributionURL
        } catch {
            errors.append(error)
        }

        do {
            let result = try await fetchDaily(apiHost: apiHost, jwt: jwt, location: location.weatherQuery)
            daily = result.daily
            attributionURL = result.attributionURL ?? attributionURL
        } catch {
            errors.append(error)
        }

        do {
            let result = try await fetchMinutely(apiHost: apiHost, jwt: jwt, location: location.coordinateQuery)
            minutely = result.minutely
            summary = result.summary
            attributionURL = result.attributionURL ?? attributionURL
        } catch WeatherServiceError.noData {
            minutely = []
            summary = "No minute rain data"
        } catch {
            errors.append(error)
        }

        do {
            airQuality = try await fetchAirQuality(
                apiHost: apiHost,
                jwt: jwt,
                longitude: location.longitude,
                latitude: location.latitude
            )
        } catch {
            errors.append(error)
        }

        guard current != nil || !hourly.isEmpty || !minutely.isEmpty || !daily.isEmpty || airQuality != nil else {
            throw errors.first ?? WeatherServiceError.emptyResponse
        }

        return WeatherSnapshot(
            provider: config.weather.provider,
            locationName: location.name,
            locationID: location.id,
            longitude: location.longitude,
            latitude: location.latitude,
            current: current,
            hourly: hourly,
            daily: daily,
            minutely: minutely,
            precipitationSummary: summary,
            airQuality: airQuality,
            attributionURL: attributionURL,
            updatedAt: Date(),
            isCached: false,
            errorMessage: errors.first?.localizedDescription
        )
    }

    private func fetchOpenMeteo(config: AppConfig) async -> Result<WeatherSnapshot, WeatherFetchError> {
        let cached = loadCached()
        guard let location = await resolveOpenMeteoLocation(config: config, cached: cached) else {
            return .failure(.setupRequired("Set a valid weather name or coordinates in GlancePane Settings"))
        }

        do {
            let snapshot = try await fetchOpenMeteoSnapshot(
                config: config,
                location: location,
                cached: cached
            )
            writeCache(snapshot)
            return .success(snapshot)
        } catch {
            if var cached {
                cached.errorMessage = error.localizedDescription
                cached.isCached = true
                return .failure(.usingCache(cached, error.localizedDescription))
            }
            return .failure(.network(error.localizedDescription))
        }
    }

    private func fetchOpenMeteoSnapshot(
        config: AppConfig,
        location: ResolvedWeatherLocation,
        cached: WeatherSnapshot?
    ) async throws -> WeatherSnapshot {
        var current = cached?.current
        var hourly = cached?.hourly ?? []
        var daily = cached?.daily ?? []
        var airQuality = cached?.airQuality
        var errors: [Error] = []
        let attributionURL = cached?.attributionURL ?? Self.openMeteoAttributionURL

        do {
            let result = try await fetchOpenMeteoForecast(longitude: location.longitude, latitude: location.latitude)
            current = result.current
            hourly = result.hourly
            daily = result.daily
        } catch {
            errors.append(error)
        }

        do {
            airQuality = try await fetchOpenMeteoAirQuality(longitude: location.longitude, latitude: location.latitude)
        } catch {
            errors.append(error)
        }

        guard current != nil || !hourly.isEmpty || !daily.isEmpty || airQuality != nil else {
            throw errors.first ?? WeatherServiceError.emptyResponse
        }

        return WeatherSnapshot(
            provider: .openMeteo,
            locationName: location.name,
            locationID: location.id,
            longitude: location.longitude,
            latitude: location.latitude,
            current: current,
            hourly: hourly,
            daily: daily,
            minutely: [],
            precipitationSummary: "No minute rain data",
            airQuality: airQuality,
            attributionURL: attributionURL,
            updatedAt: Date(),
            isCached: false,
            errorMessage: errors.first?.localizedDescription
        )
    }

    private func resolveOpenMeteoLocation(
        config: AppConfig,
        cached: WeatherSnapshot?
    ) async -> ResolvedWeatherLocation? {
        let configuredName = config.weather.location.name
        if let cached,
           (!configuredName.isEmpty && cached.locationName == configuredName)
            || coordinatesMatch(cached: cached, config: config.weather.location),
           cached.longitude.isFinite,
           cached.latitude.isFinite {
            return ResolvedWeatherLocation(
                name: cached.locationName,
                id: cached.locationID,
                longitude: cached.longitude,
                latitude: cached.latitude
            )
        }

        if !configuredName.isEmpty {
            do {
                let response = try await requestUnauthed(
                    OpenMeteoGeoResponse.self,
                    host: Self.openMeteoGeocodingHost,
                    path: "/v1/search",
                    queryItems: [
                        URLQueryItem(name: "name", value: configuredName),
                        URLQueryItem(name: "count", value: "5"),
                        URLQueryItem(name: "language", value: "en"),
                        URLQueryItem(name: "format", value: "json")
                    ]
                )

                if let item = response.results?.first,
                   item.latitude.isFinite,
                   item.longitude.isFinite {
                    return ResolvedWeatherLocation(
                        name: item.name ?? configuredName,
                        id: item.id.map(String.init),
                        longitude: item.longitude,
                        latitude: item.latitude
                    )
                }
            } catch {
                NSLog("GlancePane Open-Meteo location lookup fallback: \(error)")
            }
        }

        guard let longitude = config.weather.location.longitude,
              let latitude = config.weather.location.latitude else {
            return nil
        }
        return ResolvedWeatherLocation(
            name: configuredName.isEmpty ? "Configured Location" : configuredName,
            id: nil,
            longitude: longitude,
            latitude: latitude
        )
    }

    private func fetchOpenMeteoForecast(
        longitude: Double,
        latitude: Double
    ) async throws -> (current: CurrentWeather?, hourly: [HourlyWeather], daily: [DailyWeather]) {
        let response = try await requestUnauthed(
            OpenMeteoForecastResponse.self,
            host: Self.openMeteoForecastHost,
            path: "/v1/forecast",
            queryItems: [
                URLQueryItem(name: "latitude", value: String(latitude)),
                URLQueryItem(name: "longitude", value: String(longitude)),
                URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m,precipitation"),
                URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,precipitation"),
                URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum"),
                URLQueryItem(name: "forecast_days", value: "7"),
                URLQueryItem(name: "timezone", value: "auto")
            ]
        )

        let current: CurrentWeather?
        if let currentData = response.current {
            current = CurrentWeather(
                observedAt: Self.openMeteoDateValue(currentData.time),
                temperatureCelsius: currentData.temperature_2m,
                feelsLikeCelsius: currentData.apparent_temperature,
                condition: Self.wmoConditionText(currentData.weather_code),
                icon: Self.weatherCodeIcon(currentData.weather_code),
                humidityPercent: currentData.relative_humidity_2m,
                windDirection: Self.windDirectionText(currentData.wind_direction_10m),
                windSpeedKph: currentData.wind_speed_10m,
                precipitationMillimeters: currentData.precipitation
            )
        } else {
            current = nil
        }

        let hourly: [HourlyWeather]
        if let hourlyData = response.hourly {
            let times = hourlyData.time ?? []
            var built: [HourlyWeather] = []
            built.reserveCapacity(times.count)
            for index in times.indices {
                guard let forecastAt = Self.openMeteoDateValue(times[index]) else { continue }
                built.append(HourlyWeather(
                    forecastAt: forecastAt,
                    temperatureCelsius: hourlyData.temperature_2m?[index],
                    condition: Self.wmoConditionText(hourlyData.weather_code?[index]),
                    icon: Self.weatherCodeIcon(hourlyData.weather_code?[index]),
                    precipitationProbabilityPercent: hourlyData.precipitation_probability?[index],
                    precipitationMillimeters: hourlyData.precipitation?[index]
                ))
            }
            hourly = built
        } else {
            hourly = []
        }

        let daily: [DailyWeather]
        if let dailyData = response.daily {
            let times = dailyData.time ?? []
            var built: [DailyWeather] = []
            built.reserveCapacity(times.count)
            for index in times.indices {
                guard let date = Self.openMeteoDateValue(times[index]) else { continue }
                built.append(DailyWeather(
                    date: date,
                    tempMax: dailyData.temperature_2m_max?[index],
                    tempMin: dailyData.temperature_2m_min?[index],
                    condition: Self.wmoConditionText(dailyData.weather_code?[index]),
                    icon: Self.weatherCodeIcon(dailyData.weather_code?[index]),
                    precipitationProbabilityPercent: dailyData.precipitation_probability_max?[index],
                    precipitationMillimeters: dailyData.precipitation_sum?[index]
                ))
            }
            daily = built
        } else {
            daily = []
        }

        return (current, hourly, daily)
    }

    private func fetchOpenMeteoAirQuality(
        longitude: Double,
        latitude: Double
    ) async throws -> AirQuality? {
        let response = try await requestUnauthed(
            OpenMeteoAirQualityResponse.self,
            host: Self.openMeteoAirQualityHost,
            path: "/v1/air-quality",
            queryItems: [
                URLQueryItem(name: "latitude", value: String(latitude)),
                URLQueryItem(name: "longitude", value: String(longitude)),
                URLQueryItem(name: "current", value: "us_aqi,pm2_5,pm10,ozone,nitrogen_dioxide"),
                URLQueryItem(name: "timezone", value: "auto")
            ]
        )

        guard let current = response.current else { return nil }
        let aqi = current.us_aqi
        return AirQuality(
            aqi: aqi,
            category: Self.usAqiCategory(aqi),
            primaryPollutantName: Self.dominantOpenMeteoPollutant(current),
            pm25: current.pm2_5,
            pm10: current.pm10,
            ozone: current.ozone,
            nitrogenDioxide: current.nitrogen_dioxide
        )
    }

    private func fetchDaily(apiHost: String, jwt: String, location: String) async throws -> (daily: [DailyWeather], attributionURL: String?) {
        let response = try await request(
            QWeatherDailyResponse.self,
            apiHost: apiHost,
            path: "/v7/weather/7d",
            queryItems: [
                URLQueryItem(name: "location", value: location),
                URLQueryItem(name: "lang", value: "zh")
            ],
            jwt: jwt
        )
        try ensureSuccess(response.code, context: "daily")

        let daily = (response.daily ?? []).compactMap { item -> DailyWeather? in
            guard let date = Self.dateValue(item.fxDate) else { return nil }
            return DailyWeather(
                date: date,
                tempMax: Self.doubleValue(item.tempMax),
                tempMin: Self.doubleValue(item.tempMin),
                condition: item.textDay ?? "N/A",
                icon: item.iconDay,
                precipitationProbabilityPercent: nil,
                precipitationMillimeters: Self.doubleValue(item.precip)
            )
        }

        return (daily, response.fxLink)
    }

    private func fetchAirQuality(
        apiHost: String,
        jwt: String,
        longitude: Double,
        latitude: Double
    ) async throws -> AirQuality? {
        let latText = String(format: "%.2f", latitude)
        let lonText = String(format: "%.2f", longitude)
        let path = "/airquality/v1/current/\(latText)/\(lonText)"

        let response = try await requestPathParams(
            QWeatherAirResponse.self,
            apiHost: apiHost,
            path: path,
            queryItems: [URLQueryItem(name: "lang", value: "en")],
            jwt: jwt
        )

        guard let index = response.indexes?.first(where: { $0.code == "us-epa" })
            ?? response.indexes?.first else {
            return nil
        }

        let primaryName = response.pollutants?.first(where: { $0.code == index.primaryPollutant?.code })?.name
            ?? index.primaryPollutant?.name
        let pollutants = Dictionary(
            uniqueKeysWithValues: (response.pollutants ?? []).compactMap { pollutant -> (String, Double)? in
                guard let value = pollutant.concentration?.value else { return nil }
                return (pollutant.code, value)
            }
        )

        return AirQuality(
            aqi: index.aqi,
            category: index.category ?? AirQuality.unknownCategory,
            primaryPollutantName: primaryName,
            pm25: pollutants["pm2p5"],
            pm10: pollutants["pm10"],
            ozone: pollutants["o3"],
            nitrogenDioxide: pollutants["no2"]
        )
    }

    private func resolveLocation(
        config: AppConfig,
        apiHost: String,
        jwt: String,
        cached: WeatherSnapshot?
    ) async -> ResolvedWeatherLocation? {
        let configuredName = config.weather.location.name
        if let cached,
           (!configuredName.isEmpty && cached.locationName == configuredName)
            || coordinatesMatch(cached: cached, config: config.weather.location),
           cached.longitude.isFinite,
           cached.latitude.isFinite {
            return ResolvedWeatherLocation(
                name: cached.locationName,
                id: cached.locationID,
                longitude: cached.longitude,
                latitude: cached.latitude
            )
        }

        if !configuredName.isEmpty {
            do {
                let response = try await request(
                    QWeatherGeoResponse.self,
                    apiHost: apiHost,
                    path: "/geo/v2/city/lookup",
                    queryItems: [
                        URLQueryItem(name: "location", value: configuredName),
                        URLQueryItem(name: "number", value: "5"),
                        URLQueryItem(name: "lang", value: "zh")
                    ],
                    jwt: jwt
                )
                try ensureSuccess(response.code, context: "geo")

                if let item = bestGeoLocation(from: response.location ?? [], requestedName: configuredName),
                   let longitude = Self.doubleValue(item.lon),
                   let latitude = Self.doubleValue(item.lat) {
                    return ResolvedWeatherLocation(
                        name: configuredName,
                        id: item.id,
                        longitude: longitude,
                        latitude: latitude
                    )
                }
            } catch {
                NSLog("GlancePane weather location lookup fallback: \(error)")
            }
        }

        guard let longitude = config.weather.location.longitude,
              let latitude = config.weather.location.latitude else {
            return nil
        }
        return ResolvedWeatherLocation(
            name: configuredName.isEmpty ? "Configured Location" : configuredName,
            id: nil,
            longitude: longitude,
            latitude: latitude
        )
    }

    private func coordinatesMatch(
        cached: WeatherSnapshot,
        config: WeatherLocationConfig
    ) -> Bool {
        guard let longitude = config.longitude, let latitude = config.latitude else {
            return false
        }
        return abs(cached.longitude - longitude) < 0.0001
            && abs(cached.latitude - latitude) < 0.0001
    }

    private func fetchNow(apiHost: String, jwt: String, location: String) async throws -> (current: CurrentWeather, attributionURL: String?) {
        let response = try await request(
            QWeatherNowResponse.self,
            apiHost: apiHost,
            path: "/v7/weather/now",
            queryItems: [
                URLQueryItem(name: "location", value: location),
                URLQueryItem(name: "lang", value: "zh")
            ],
            jwt: jwt
        )
        try ensureSuccess(response.code, context: "now")

        guard let now = response.now else {
            throw WeatherServiceError.emptyResponse
        }
        return (
            CurrentWeather(
                observedAt: Self.dateValue(now.obsTime),
                temperatureCelsius: Self.doubleValue(now.temp),
                feelsLikeCelsius: Self.doubleValue(now.feelsLike),
                condition: now.text ?? "N/A",
                icon: now.icon,
                humidityPercent: Self.doubleValue(now.humidity),
                windDirection: now.windDir,
                windSpeedKph: Self.doubleValue(now.windSpeed),
                precipitationMillimeters: Self.doubleValue(now.precip)
            ),
            response.fxLink
        )
    }

    private func fetchHourly(apiHost: String, jwt: String, location: String) async throws -> (hourly: [HourlyWeather], attributionURL: String?) {
        let response = try await request(
            QWeatherHourlyResponse.self,
            apiHost: apiHost,
            path: "/v7/weather/24h",
            queryItems: [
                URLQueryItem(name: "location", value: location),
                URLQueryItem(name: "lang", value: "zh")
            ],
            jwt: jwt
        )
        try ensureSuccess(response.code, context: "hourly")

        let hourly = (response.hourly ?? []).compactMap { item -> HourlyWeather? in
            guard let forecastAt = Self.dateValue(item.fxTime) else { return nil }
            return HourlyWeather(
                forecastAt: forecastAt,
                temperatureCelsius: Self.doubleValue(item.temp),
                condition: item.text ?? "N/A",
                icon: item.icon,
                precipitationProbabilityPercent: Self.doubleValue(item.pop),
                precipitationMillimeters: Self.doubleValue(item.precip)
            )
        }

        return (hourly, response.fxLink)
    }

    private func fetchMinutely(apiHost: String, jwt: String, location: String) async throws -> (minutely: [MinutelyPrecipitation], summary: String, attributionURL: String?) {
        let response = try await request(
            QWeatherMinutelyResponse.self,
            apiHost: apiHost,
            path: "/v7/minutely/5m",
            queryItems: [
                URLQueryItem(name: "location", value: location),
                URLQueryItem(name: "lang", value: "zh")
            ],
            jwt: jwt
        )

        if response.code == "204" {
            throw WeatherServiceError.noData
        }
        try ensureSuccess(response.code, context: "minutely")

        let minutely = (response.minutely ?? []).compactMap { item -> MinutelyPrecipitation? in
            guard let forecastAt = Self.dateValue(item.fxTime) else { return nil }
            return MinutelyPrecipitation(
                forecastAt: forecastAt,
                precipitationMillimeters: Self.doubleValue(item.precip) ?? 0,
                type: item.type ?? "rain"
            )
        }

        return (minutely, response.summary ?? "No minute rain data", response.fxLink)
    }

    private func request<T: Decodable>(
        _ type: T.Type,
        apiHost: String,
        path: String,
        queryItems: [URLQueryItem],
        jwt: String
    ) async throws -> T {
        guard var components = URLComponents(string: normalizedAPIHost(apiHost)) else {
            throw URLError(.badURL)
        }

        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue(Self.authorizationHeader(jwt: jwt), forHTTPHeaderField: "Authorization")

        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(type, from: data)
    }

    /// QWeather v1 air-quality API uses path params (lat/lon in path) and HTTP-status
    /// error signalling (no top-level `code` field), unlike the v7 endpoints.
    private func requestPathParams<T: Decodable>(
        _ type: T.Type,
        apiHost: String,
        path: String,
        queryItems: [URLQueryItem],
        jwt: String
    ) async throws -> T {
        guard var components = URLComponents(string: normalizedAPIHost(apiHost)) else {
            throw URLError(.badURL)
        }

        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue(Self.authorizationHeader(jwt: jwt), forHTTPHeaderField: "Authorization")

        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(type, from: data)
    }

    /// Open-Meteo endpoints are unauthenticated (no JWT, no Authorization header).
    private func requestUnauthed<T: Decodable>(
        _ type: T.Type,
        host: String,
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> T {
        guard var components = URLComponents(string: Self.normalizedHost(host)) else {
            throw URLError(.badURL)
        }

        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let request = URLRequest(url: url)
        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(type, from: data)
    }

    private func writeCache(_ snapshot: WeatherSnapshot) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try SecureFileStore.write(encoder.encode(snapshot), to: cacheURL)
        } catch {
            NSLog("GlancePane failed to write weather cache: \(error)")
        }
    }

    private func bestGeoLocation(from locations: [QWeatherGeoLocation], requestedName: String) -> QWeatherGeoLocation? {
        let normalizedRequest = Self.normalizedLocationName(requestedName)

        return locations.max { left, right in
            scoreGeoLocation(left, normalizedRequest: normalizedRequest)
                < scoreGeoLocation(right, normalizedRequest: normalizedRequest)
        }
    }

    private func scoreGeoLocation(_ location: QWeatherGeoLocation, normalizedRequest: String) -> Int {
        let normalizedName = Self.normalizedLocationName(location.name)
        let normalizedAdmin = Self.normalizedLocationName(location.adm2 ?? "")
        var score = 0

        if !normalizedName.isEmpty && normalizedRequest.contains(normalizedName) {
            score += normalizedName.count * 10
        }

        if !normalizedAdmin.isEmpty && normalizedRequest.contains(normalizedAdmin) {
            score += normalizedAdmin.count * 2
        }

        if !normalizedName.isEmpty && normalizedName == normalizedAdmin {
            score -= 8
        }

        return score
    }

    private func ensureSuccess(_ code: String, context: String) throws {
        guard code == "200" else {
            throw WeatherServiceError.apiCode(code, context)
        }
    }

    private func normalizedAPIHost(_ apiHost: String) -> String {
        if apiHost.hasPrefix("http://") || apiHost.hasPrefix("https://") {
            return apiHost
        }
        return "https://\(apiHost)"
    }

    private static let openMeteoForecastHost = "api.open-meteo.com"
    private static let openMeteoAirQualityHost = "air-quality-api.open-meteo.com"
    private static let openMeteoGeocodingHost = "geocoding-api.open-meteo.com"
    private static let openMeteoAttributionURL = "https://open-meteo.com/"

    private static func normalizedHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    private static func openMeteoDateValue(_ value: String?) -> Date? {
        guard let value else { return nil }
        return openMeteoDateTimeFormatter.date(from: value)
            ?? openMeteoDateOnlyFormatter.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
    }

    private static let openMeteoDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()

    private static let openMeteoDateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Stores the WMO weather code as the icon identifier so the UI mapper can
    /// resolve it to an SF Symbol regardless of provider.
    static func weatherCodeIcon(_ code: Double?) -> String? {
        guard let code = code.map(Int.init) else { return nil }
        return "wmo:\(code)"
    }

    /// Maps WMO weather interpretation codes (Open-Meteo) to short condition text.
    /// Also serves as the canonical icon identifier for the Open-Meteo provider.
    static func wmoConditionText(_ code: Double?) -> String {
        guard let code = code.map(Int.init) else { return "N/A" }
        switch code {
        case 0: return "Clear sky"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45: return "Fog"
        case 48: return "Rime fog"
        case 51: return "Light drizzle"
        case 53: return "Moderate drizzle"
        case 55: return "Dense drizzle"
        case 56: return "Light freezing drizzle"
        case 57: return "Dense freezing drizzle"
        case 61: return "Slight rain"
        case 63: return "Moderate rain"
        case 65: return "Heavy rain"
        case 66: return "Light freezing rain"
        case 67: return "Heavy freezing rain"
        case 71: return "Slight snow"
        case 73: return "Moderate snow"
        case 75: return "Heavy snow"
        case 77: return "Snow grains"
        case 80: return "Slight rain showers"
        case 81: return "Moderate rain showers"
        case 82: return "Violent rain showers"
        case 85: return "Slight snow showers"
        case 86: return "Heavy snow showers"
        case 95: return "Thunderstorm"
        case 96: return "Thunderstorm with hail"
        case 99: return "Heavy thunderstorm with hail"
        default: return "N/A"
        }
    }

    static func usAqiCategory(_ aqi: Double?) -> String {
        guard let aqi else { return AirQuality.unknownCategory }
        switch aqi {
        case ..<51: return "Good"
        case ..<101: return "Moderate"
        case ..<151: return "Unhealthy for Sensitive"
        case ..<201: return "Unhealthy"
        case ..<301: return "Very Unhealthy"
        default: return "Hazardous"
        }
    }

    private static func dominantOpenMeteoPollutant(_ current: OpenMeteoAirQualityCurrent) -> String? {
        let candidates: [(value: Double?, name: String)] = [
            (current.pm2_5, "PM2.5"),
            (current.pm10, "PM10"),
            (current.ozone, "Ozone"),
            (current.nitrogen_dioxide, "NO₂")
        ]
        return candidates.compactMap { entry in
            entry.value.map { (entry.name, $0) }
        }.max(by: { $0.1 < $1.1 })?.0
    }

    private static func windDirectionText(_ degrees: Double?) -> String? {
        guard let degrees = degrees?.truncatingRemainder(dividingBy: 360) else { return nil }
        let sectors = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                       "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees / 22.5).rounded()) % 16
        return sectors[index]
    }

    private static func effectiveJWT(config: AppConfig, cachedToken: inout CachedQWeatherToken?) throws -> String {
        let environmentJWT = ProcessInfo.processInfo.environment["GLANCEPANE_QWEATHER_JWT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !environmentJWT.isEmpty {
            return environmentJWT
        }

        let keyID = environmentValue("GLANCEPANE_QWEATHER_KID", fallback: config.weather.qweather.keyID)
        guard !keyID.isEmpty else {
            throw WeatherServiceError.setupRequired("Set weather.qweather.keyID in ~/.glancepane/config.json")
        }

        let projectID = environmentValue("GLANCEPANE_QWEATHER_PROJECT_ID", fallback: config.weather.qweather.projectID)
        guard !projectID.isEmpty else {
            throw WeatherServiceError.setupRequired("Set weather.qweather.projectID in ~/.glancepane/config.json")
        }

        let privateKeyPath = environmentValue("GLANCEPANE_QWEATHER_PRIVATE_KEY_PATH", fallback: config.weather.qweather.privateKeyPath)
        guard !privateKeyPath.isEmpty else {
            throw WeatherServiceError.setupRequired("Set weather.qweather.privateKeyPath in ~/.glancepane/config.json")
        }

        let now = Date()
        if let cachedToken,
           cachedToken.keyID == keyID,
           cachedToken.projectID == projectID,
           cachedToken.privateKeyPath == privateKeyPath,
           cachedToken.expiresAt.timeIntervalSince(now) > 300 {
            return cachedToken.token
        }

        let token = try makeQWeatherJWT(
            keyID: keyID,
            projectID: projectID,
            privateKeyPath: privateKeyPath,
            now: now
        )
        cachedToken = token
        NSLog("GlancePane generated QWeather JWT expiring at \(token.expiresAt)")
        return token.token
    }

    private static func authorizationHeader(jwt: String) -> String {
        if jwt.lowercased().hasPrefix("bearer ") {
            return jwt
        }
        return "Bearer \(jwt)"
    }

    private static func makeQWeatherJWT(
        keyID: String,
        projectID: String,
        privateKeyPath: String,
        now: Date
    ) throws -> CachedQWeatherToken {
        let issuedAt = Int(now.timeIntervalSince1970) - 30
        let expiresAt = issuedAt + 86_400
        let header = QWeatherJWTHeader(alg: "EdDSA", kid: keyID)
        let payload = QWeatherJWTPayload(sub: projectID, iat: issuedAt, exp: expiresAt)
        let encoder = JSONEncoder()

        let headerPart = try encoder.encode(header).base64URLEncodedString()
        let payloadPart = try encoder.encode(payload).base64URLEncodedString()
        let signingInput = "\(headerPart).\(payloadPart)"
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyRawRepresentation(at: privateKeyPath))
        let signature = try privateKey.signature(for: Data(signingInput.utf8)).base64URLEncodedString()
        let token = "\(signingInput).\(signature)"

        return CachedQWeatherToken(
            keyID: keyID,
            projectID: projectID,
            privateKeyPath: privateKeyPath,
            token: token,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(expiresAt))
        )
    }

    private static func privateKeyRawRepresentation(at path: String) throws -> Data {
        let url = URL(fileURLWithPath: expandedPath(path))
        let pem = try String(contentsOf: url, encoding: .utf8)
        let base64 = pem
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("-----") }
            .joined()

        guard let der = Data(base64Encoded: base64) else {
            throw WeatherServiceError.invalidPrivateKey("Private key is not valid PEM base64")
        }

        if der.count == 32 {
            return der
        }

        if let raw = ed25519RawPrivateKey(fromPKCS8DER: der) {
            return raw
        }

        throw WeatherServiceError.invalidPrivateKey("Unable to extract Ed25519 private key bytes")
    }

    private static func ed25519RawPrivateKey(fromPKCS8DER der: Data) -> Data? {
        let bytes = [UInt8](der)
        guard bytes.count >= 34 else { return nil }

        for index in stride(from: bytes.count - 34, through: 0, by: -1) {
            guard bytes[index] == 0x04, bytes[index + 1] == 0x20 else {
                continue
            }
            return Data(bytes[(index + 2)..<(index + 34)])
        }

        return nil
    }

    private static func expandedPath(_ path: String) -> String {
        if path == "~" {
            return NSHomeDirectory()
        }
        if path.hasPrefix("~/") {
            return NSHomeDirectory() + String(path.dropFirst())
        }
        return path
    }

    private static func environmentValue(_ name: String, fallback: String) -> String {
        let environment = ProcessInfo.processInfo.environment[name]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !environment.isEmpty {
            return environment
        }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func doubleValue(_ value: String?) -> Double? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.lowercased() != "n/a"
        else { return nil }
        return Double(value)
    }

    private static func dateValue(_ value: String?) -> Date? {
        guard let value else { return nil }
        return qweatherDateFormatter.date(from: value)
            ?? qweatherDateTimeFormatter.date(from: value)
            ?? qweatherDateOnlyFormatter.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
    }

    private static func normalizedLocationName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "省", with: "")
            .replacingOccurrences(of: "市", with: "")
            .replacingOccurrences(of: "区", with: "")
            .replacingOccurrences(of: "县", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static let qweatherDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
        return formatter
    }()

    private static let qweatherDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter
    }()

    private static let qweatherDateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum WeatherFetchError: Error, Equatable {
    case setupRequired(String)
    case network(String)
    case usingCache(WeatherSnapshot, String)
}

private struct ResolvedWeatherLocation {
    let name: String
    let id: String?
    let longitude: Double
    let latitude: Double

    var weatherQuery: String {
        id ?? coordinateQuery
    }

    var coordinateQuery: String {
        "\(Self.format(longitude)),\(Self.format(latitude))"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}

private struct CachedQWeatherToken {
    let keyID: String
    let projectID: String
    let privateKeyPath: String
    let token: String
    let expiresAt: Date
}

private struct QWeatherJWTHeader: Encodable {
    let alg: String
    let kid: String
}

private struct QWeatherJWTPayload: Encodable {
    let sub: String
    let iat: Int
    let exp: Int
}

private enum WeatherServiceError: Error, LocalizedError {
    case setupRequired(String)
    case apiCode(String, String)
    case emptyResponse
    case noData
    case invalidPrivateKey(String)

    var errorDescription: String? {
        switch self {
        case .setupRequired(let message):
            return message
        case .apiCode(let code, let context):
            return "QWeather \(context) returned code \(code)"
        case .emptyResponse:
            return "QWeather returned no usable weather data"
        case .noData:
            return "QWeather returned no minute precipitation data"
        case .invalidPrivateKey(let message):
            return message
        }
    }
}

private struct QWeatherGeoResponse: Decodable {
    let code: String
    let location: [QWeatherGeoLocation]?
}

private struct QWeatherGeoLocation: Decodable {
    let name: String
    let id: String
    let lat: String?
    let lon: String?
    let adm2: String?
}

private struct QWeatherNowResponse: Decodable {
    let code: String
    let fxLink: String?
    let now: QWeatherNow?
}

private struct QWeatherNow: Decodable {
    let obsTime: String?
    let temp: String?
    let feelsLike: String?
    let icon: String?
    let text: String?
    let windDir: String?
    let windSpeed: String?
    let humidity: String?
    let precip: String?
}

private struct QWeatherHourlyResponse: Decodable {
    let code: String
    let fxLink: String?
    let hourly: [QWeatherHourly]?
}

private struct QWeatherHourly: Decodable {
    let fxTime: String?
    let temp: String?
    let icon: String?
    let text: String?
    let pop: String?
    let precip: String?
}

private struct QWeatherMinutelyResponse: Decodable {
    let code: String
    let fxLink: String?
    let summary: String?
    let minutely: [QWeatherMinutely]?
}

private struct QWeatherMinutely: Decodable {
    let fxTime: String?
    let precip: String?
    let type: String?
}

private struct QWeatherDailyResponse: Decodable {
    let code: String
    let fxLink: String?
    let daily: [QWeatherDaily]?
}

private struct QWeatherDaily: Decodable {
    let fxDate: String?
    let tempMax: String?
    let tempMin: String?
    let iconDay: String?
    let textDay: String?
    let precip: String?
}

private struct QWeatherAirResponse: Decodable {
    let indexes: [QWeatherAirIndex]?
    let pollutants: [QWeatherAirPollutant]?
}

private struct QWeatherAirIndex: Decodable {
    let code: String?
    let name: String?
    let aqi: Double?
    let aqiDisplay: String?
    let category: String?
    let primaryPollutant: QWeatherAirPrimaryPollutant?
}

private struct QWeatherAirPrimaryPollutant: Decodable {
    let code: String?
    let name: String?
}

private struct QWeatherAirPollutant: Decodable {
    let code: String
    let name: String?
    let concentration: QWeatherAirConcentration?
}

private struct QWeatherAirConcentration: Decodable {
    let value: Double?
    let unit: String?
}

// MARK: - Open-Meteo DTOs

private struct OpenMeteoGeoResponse: Decodable {
    let results: [OpenMeteoGeoLocation]?
}

private struct OpenMeteoGeoLocation: Decodable {
    let id: Int?
    let name: String?
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?
}

private struct OpenMeteoForecastResponse: Decodable {
    let current: OpenMeteoForecastCurrent?
    let hourly: OpenMeteoForecastHourly?
    let daily: OpenMeteoForecastDaily?
}

private struct OpenMeteoForecastCurrent: Decodable {
    let time: String?
    let temperature_2m: Double?
    let relative_humidity_2m: Double?
    let apparent_temperature: Double?
    let weather_code: Double?
    let wind_speed_10m: Double?
    let wind_direction_10m: Double?
    let precipitation: Double?
}

private struct OpenMeteoForecastHourly: Decodable {
    let time: [String]?
    let temperature_2m: [Double]?
    let weather_code: [Double]?
    let precipitation_probability: [Double]?
    let precipitation: [Double]?
}

private struct OpenMeteoForecastDaily: Decodable {
    let time: [String]?
    let weather_code: [Double]?
    let temperature_2m_max: [Double]?
    let temperature_2m_min: [Double]?
    let precipitation_probability_max: [Double]?
    let precipitation_sum: [Double]?
}

private struct OpenMeteoAirQualityResponse: Decodable {
    let current: OpenMeteoAirQualityCurrent?
}

private struct OpenMeteoAirQualityCurrent: Decodable {
    let us_aqi: Double?
    let pm2_5: Double?
    let pm10: Double?
    let ozone: Double?
    let nitrogen_dioxide: Double?
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
