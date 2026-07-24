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
        guard config.weather.provider == .qweather else {
            return .failure(.setupRequired("Unsupported weather provider"))
        }
        guard config.weather.location.isConfigured else {
            return .failure(.setupRequired("Set a weather location in GlancePane Settings"))
        }

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
        var minutely = cached?.minutely ?? []
        var summary = cached?.precipitationSummary ?? "No minute rain data"
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

        guard current != nil || !hourly.isEmpty || !minutely.isEmpty else {
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
            minutely: minutely,
            precipitationSummary: summary,
            attributionURL: attributionURL,
            updatedAt: Date(),
            isCached: false,
            errorMessage: errors.first?.localizedDescription
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

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
