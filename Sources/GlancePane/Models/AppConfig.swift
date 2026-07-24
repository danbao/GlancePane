import Foundation

enum DashboardPage: String, Codable, CaseIterable, Hashable {
    case clock
    case system
    case performance
    case agents
    case market
    case weather

    var title: String {
        switch self {
        case .clock:
            return "Clock"
        case .system:
            return "System"
        case .performance:
            return "Performance"
        case .agents:
            return "Agents"
        case .market:
            return "Market"
        case .weather:
            return "Weather"
        }
    }

    var symbolName: String {
        switch self {
        case .clock:
            return "clock"
        case .system:
            return "desktopcomputer"
        case .performance:
            return "gauge.with.dots.needle.67percent"
        case .agents:
            return "terminal.fill"
        case .market:
            return "chart.line.uptrend.xyaxis"
        case .weather:
            return "cloud.sun"
        }
    }

    static let defaultOrder: [DashboardPage] = [.clock, .system, .performance, .agents, .market, .weather]

    static func normalizedOrder(_ pages: [DashboardPage]) -> [DashboardPage] {
        var seen = Set<DashboardPage>()
        var normalized: [DashboardPage] = []

        for page in pages where seen.insert(page).inserted {
            normalized.append(page)
        }

        for page in defaultOrder where seen.insert(page).inserted {
            normalized.append(page)
        }

        return normalized
    }
}
struct AppConfig: Codable, Equatable {
    var schemaVersion: Int
    var display: DisplayConfig
    var appearance: AppearanceConfig
    var interaction: InteractionConfig
    var pages: PagesConfig
    var system: SystemConfig
    var agents: AgentsConfig
    var market: MarketConfig
    var weather: WeatherConfig
    var protection: ProtectionConfig

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case display
        case appearance
        case interaction
        case pages
        case system
        case agents
        case market
        case weather
        case protection

        case targetDisplayName
        case stockSymbols
        case weatherProvider
        case weatherLocationName
        case weatherLongitude
        case weatherLatitude
        case qweatherApiHost
        case qweatherKeyID
        case qweatherProjectID
        case qweatherPrivateKeyPath
        case weatherRefreshIntervalSeconds
        case refreshIntervalSeconds
        case theme
        case mousePassthrough
        case enabledMetricGroups
        case metricRefreshIntervals
        case burnInProtection
        case pageOrder
        case enabledPages
        case autoPageRotationEnabled
        case autoPageRotationIntervalSeconds
    }

    static let `default` = AppConfig(
        schemaVersion: 5,
        display: .default,
        appearance: .default,
        interaction: .default,
        pages: .default,
        system: .default,
        agents: .default,
        market: .default,
        weather: .default,
        protection: .default
    )

    init(
        schemaVersion: Int = 5,
        display: DisplayConfig,
        appearance: AppearanceConfig,
        interaction: InteractionConfig,
        pages: PagesConfig,
        system: SystemConfig,
        agents: AgentsConfig,
        market: MarketConfig,
        weather: WeatherConfig,
        protection: ProtectionConfig
    ) {
        self.schemaVersion = schemaVersion
        self.display = display
        self.appearance = appearance
        self.interaction = interaction
        self.pages = pages
        self.system = system
        self.agents = agents
        self.market = market
        self.weather = weather
        self.protection = protection
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfig.default

        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1

        display = try container.decodeIfPresent(DisplayConfig.self, forKey: .display)
            ?? DisplayConfig(
                targetName: try container.decodeIfPresent(String.self, forKey: .targetDisplayName)
                    ?? defaults.display.targetName
            )

        appearance = try container.decodeIfPresent(AppearanceConfig.self, forKey: .appearance)
            ?? AppearanceConfig(
                theme: try container.decodeIfPresent(ThemeName.self, forKey: .theme)
                    ?? defaults.appearance.theme
            )

        let legacyMousePassthrough = try container.decodeIfPresent(Bool.self, forKey: .mousePassthrough)
        interaction = try container.decodeIfPresent(InteractionConfig.self, forKey: .interaction)
            ?? InteractionConfig(
                clickNavigationEnabled: legacyMousePassthrough == nil
                    ? defaults.interaction.clickNavigationEnabled
                    : true
            )

        let legacyPageOrder = try container.decodeIfPresent([String].self, forKey: .pageOrder)?
            .compactMap(DashboardPage.init(rawValue:))
        let legacyEnabledPages = try container.decodeIfPresent([String].self, forKey: .enabledPages)?
            .compactMap(DashboardPage.init(rawValue:))
        let legacyRotationEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoPageRotationEnabled)
        let legacyRotationInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .autoPageRotationIntervalSeconds)
        pages = try container.decodeIfPresent(PagesConfig.self, forKey: .pages)
            ?? PagesConfig(
                order: legacyPageOrder ?? defaults.pages.order,
                enabled: Set(legacyEnabledPages ?? Array(defaults.pages.enabled)),
                rotation: PageRotationConfig(
                    enabled: legacyRotationEnabled ?? defaults.pages.rotation.enabled,
                    intervalSeconds: legacyRotationInterval ?? defaults.pages.rotation.intervalSeconds
                )
            )
        if schemaVersion < 3 {
            pages = pages.migratingAgents(fromSchemaVersion: schemaVersion)
        }

        let legacyGroupValues = try container.decodeIfPresent([String].self, forKey: .enabledMetricGroups)
        let legacyGroups = legacyGroupValues?.compactMap(SystemMetricGroup.init(rawValue:))
        let legacyMarketEnabled = legacyGroupValues?.contains("market")
        let legacyIntervals = try Self.decodeLegacyIntervals(from: container)
        let systemIntervals: [SystemMetricGroup: TimeInterval] = Dictionary(
            uniqueKeysWithValues: legacyIntervals.compactMap { key, value in
                guard let group = SystemMetricGroup(rawValue: key) else { return nil }
                return (group, value)
            }
        )
        system = try container.decodeIfPresent(SystemConfig.self, forKey: .system)
            ?? SystemConfig(
                enabledGroups: Set(legacyGroups ?? Array(defaults.system.enabledGroups)),
                defaultRefreshIntervalSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .refreshIntervalSeconds)
                    ?? defaults.system.defaultRefreshIntervalSeconds,
                refreshIntervalsSeconds: systemIntervals.isEmpty ? defaults.system.refreshIntervalsSeconds : systemIntervals
            )
        if schemaVersion < 2, system.enabledGroups.contains(.vitals) {
            system.enabledGroups.insert(.gpu)
        }
        if schemaVersion < 4 {
            system.enabledGroups.insert(.thermals)
            system.refreshIntervalsSeconds[.thermals] = SystemMetricGroup.defaultRefreshIntervals[.thermals]
        }

        agents = try container.decodeIfPresent(AgentsConfig.self, forKey: .agents) ?? defaults.agents

        market = try container.decodeIfPresent(MarketConfig.self, forKey: .market)
            ?? MarketConfig(
                enabled: legacyMarketEnabled ?? defaults.market.enabled,
                symbols: try container.decodeIfPresent([String].self, forKey: .stockSymbols)
                    ?? defaults.market.symbols,
                refreshIntervalSeconds: legacyIntervals["market"] ?? defaults.market.refreshIntervalSeconds
            )

        let legacyLocation = WeatherLocationConfig(
            name: try container.decodeIfPresent(String.self, forKey: .weatherLocationName)
                ?? defaults.weather.location.name,
            longitude: try container.decodeIfPresent(Double.self, forKey: .weatherLongitude),
            latitude: try container.decodeIfPresent(Double.self, forKey: .weatherLatitude)
        )
        let legacyQWeather = QWeatherConfig(
            apiHost: try container.decodeIfPresent(String.self, forKey: .qweatherApiHost)
                ?? defaults.weather.qweather.apiHost,
            keyID: try container.decodeIfPresent(String.self, forKey: .qweatherKeyID)
                ?? defaults.weather.qweather.keyID,
            projectID: try container.decodeIfPresent(String.self, forKey: .qweatherProjectID)
                ?? defaults.weather.qweather.projectID,
            privateKeyPath: try container.decodeIfPresent(String.self, forKey: .qweatherPrivateKeyPath)
                ?? defaults.weather.qweather.privateKeyPath
        )
        weather = try container.decodeIfPresent(WeatherConfig.self, forKey: .weather)
            ?? WeatherConfig(
                provider: try container.decodeIfPresent(WeatherProvider.self, forKey: .weatherProvider)
                    ?? defaults.weather.provider,
                location: legacyLocation,
                refreshIntervalSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .weatherRefreshIntervalSeconds)
                    ?? defaults.weather.refreshIntervalSeconds,
                qweather: legacyQWeather
            )

        protection = try container.decodeIfPresent(ProtectionConfig.self, forKey: .protection)
            ?? (try container.decodeIfPresent(ProtectionConfig.self, forKey: .burnInProtection) ?? defaults.protection)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(display, forKey: .display)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(interaction, forKey: .interaction)
        try container.encode(pages, forKey: .pages)
        try container.encode(system, forKey: .system)
        try container.encode(agents, forKey: .agents)
        try container.encode(market, forKey: .market)
        try container.encode(weather, forKey: .weather)
        try container.encode(protection, forKey: .protection)
    }

    private static func decodeLegacyIntervals(from container: KeyedDecodingContainer<CodingKeys>) throws -> [String: TimeInterval] {
        if let stringIntervals = try? container.decode([String: TimeInterval].self, forKey: .metricRefreshIntervals) {
            return stringIntervals
        }

        if let enumIntervals = try? container.decode([LegacyMetricGroup: TimeInterval].self, forKey: .metricRefreshIntervals) {
            return Dictionary(uniqueKeysWithValues: enumIntervals.map { ($0.key.rawValue, $0.value) })
        }

        return [:]
    }
}
