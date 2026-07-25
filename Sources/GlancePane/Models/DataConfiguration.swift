import Foundation

struct AgentsConfig: Codable, Equatable {
    var codex: CodexAgentConfig

    static let `default` = AgentsConfig(codex: .default)

    private enum CodingKeys: String, CodingKey {
        case codex
    }

    init(codex: CodexAgentConfig) {
        self.codex = codex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        codex = try container.decodeIfPresent(CodexAgentConfig.self, forKey: .codex) ?? .default
    }

    func normalized() -> AgentsConfig {
        var copy = self
        copy.codex = copy.codex.normalized()
        return copy
    }
}
struct CodexAgentConfig: Codable, Equatable {
    var enabled: Bool
    var executablePath: String?
    var codexHomePath: String?
    var showProjectNames: Bool
    var recentSessionCount: Int

    static let `default` = CodexAgentConfig(
        enabled: true,
        executablePath: nil,
        codexHomePath: nil,
        showProjectNames: false,
        recentSessionCount: 3
    )

    private enum CodingKeys: String, CodingKey {
        case enabled
        case executablePath
        case codexHomePath
        case showProjectNames
        case recentSessionCount
    }

    init(
        enabled: Bool,
        executablePath: String?,
        codexHomePath: String?,
        showProjectNames: Bool,
        recentSessionCount: Int
    ) {
        self.enabled = enabled
        self.executablePath = executablePath
        self.codexHomePath = codexHomePath
        self.showProjectNames = showProjectNames
        self.recentSessionCount = recentSessionCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CodexAgentConfig.default
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        executablePath = try container.decodeIfPresent(String.self, forKey: .executablePath)
        codexHomePath = try container.decodeIfPresent(String.self, forKey: .codexHomePath)
        showProjectNames = try container.decodeIfPresent(Bool.self, forKey: .showProjectNames) ?? defaults.showProjectNames
        recentSessionCount = try container.decodeIfPresent(Int.self, forKey: .recentSessionCount) ?? defaults.recentSessionCount
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        if let executablePath {
            try container.encode(executablePath, forKey: .executablePath)
        } else {
            try container.encodeNil(forKey: .executablePath)
        }
        if let codexHomePath {
            try container.encode(codexHomePath, forKey: .codexHomePath)
        } else {
            try container.encodeNil(forKey: .codexHomePath)
        }
        try container.encode(showProjectNames, forKey: .showProjectNames)
        try container.encode(recentSessionCount, forKey: .recentSessionCount)
    }

    func normalized() -> CodexAgentConfig {
        var copy = self
        copy.executablePath = copy.executablePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.codexHomePath = copy.codexHomePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.executablePath?.isEmpty == true { copy.executablePath = nil }
        if copy.codexHomePath?.isEmpty == true { copy.codexHomePath = nil }
        copy.recentSessionCount = min(3, max(1, copy.recentSessionCount))
        return copy
    }
}

struct MarketConfig: Codable, Equatable {
    var enabled: Bool
    var symbols: [String]
    var refreshIntervalSeconds: TimeInterval

    static let `default` = MarketConfig(
        enabled: true,
        symbols: ["AAPL", "MSFT", "NVDA", "TSLA", "SPY", "QQQ", "^IXIC", "BTC-USD"],
        refreshIntervalSeconds: 60
    )

    func normalized() -> MarketConfig {
        var copy = self
        var seen = Set<String>()
        copy.symbols = copy.symbols
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }

        if copy.symbols.isEmpty {
            copy.symbols = Self.default.symbols
        }

        if !copy.refreshIntervalSeconds.isFinite || copy.refreshIntervalSeconds < 5 {
            copy.refreshIntervalSeconds = Self.default.refreshIntervalSeconds
        }

        return copy
    }
}

struct WeatherConfig: Codable, Equatable {
    var provider: WeatherProvider
    var location: WeatherLocationConfig
    var refreshIntervalSeconds: TimeInterval
    var qweather: QWeatherConfig

    static let `default` = WeatherConfig(
        provider: .openMeteo,
        location: .default,
        refreshIntervalSeconds: 600,
        qweather: .default
    )

    func normalized() -> WeatherConfig {
        var copy = self
        copy.location = copy.location.normalized()
        copy.qweather = copy.qweather.normalized()
        if !copy.refreshIntervalSeconds.isFinite || copy.refreshIntervalSeconds < 60 {
            copy.refreshIntervalSeconds = Self.default.refreshIntervalSeconds
        }
        return copy
    }

    /// Schema v7 migration: the default provider changed from QWeather to Open-Meteo.
    /// Preserve QWeather for existing users who have configured QWeather credentials,
    /// so the default change does not silently switch their data source.
    func migratingLegacyWeatherProvider() -> WeatherConfig {
        guard provider == .openMeteo else { return self }
        let host = qweather.apiHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyID = qweather.keyID.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectID = qweather.projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !keyID.isEmpty, !projectID.isEmpty else { return self }
        var copy = self
        copy.provider = .qweather
        return copy
    }
}

struct WeatherLocationConfig: Codable, Equatable {
    var name: String
    var longitude: Double?
    var latitude: Double?

    static let `default` = WeatherLocationConfig(
        name: "",
        longitude: nil,
        latitude: nil
    )

    var isConfigured: Bool {
        !name.isEmpty || (longitude != nil && latitude != nil)
    }

    func normalized() -> WeatherLocationConfig {
        var copy = self
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let longitude = copy.longitude,
           !longitude.isFinite || longitude < -180 || longitude > 180 {
            copy.longitude = nil
        }

        if let latitude = copy.latitude,
           !latitude.isFinite || latitude < -90 || latitude > 90 {
            copy.latitude = nil
        }

        return copy
    }
}

struct QWeatherConfig: Codable, Equatable {
    var apiHost: String
    var keyID: String
    var projectID: String
    var privateKeyPath: String

    static let `default` = QWeatherConfig(
        apiHost: "",
        keyID: "",
        projectID: "",
        privateKeyPath: "~/.glancepane/qweather/ed25519-private.pem"
    )

    func normalized() -> QWeatherConfig {
        var copy = self
        copy.apiHost = copy.apiHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        copy.keyID = copy.keyID.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.projectID = copy.projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.privateKeyPath = copy.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.privateKeyPath.isEmpty {
            copy.privateKeyPath = Self.default.privateKeyPath
        }
        return copy
    }
}

enum WeatherProvider: String, Codable, CaseIterable, Equatable {
    case openMeteo
    case qweather

    var attributionPrefix: String {
        switch self {
        case .openMeteo: return "OPEN-METEO"
        case .qweather: return "QWEATHER"
        }
    }
}
