import Foundation

struct SystemConfig: Codable, Equatable {
    var enabledGroups: Set<SystemMetricGroup>
    var defaultRefreshIntervalSeconds: TimeInterval
    var refreshIntervalsSeconds: [SystemMetricGroup: TimeInterval]
    var history: HistoryConfig
    var processes: ProcessMonitoringConfig
    var networkQuality: NetworkQualityConfig
    var thresholds: HealthThresholdsConfig

    private enum CodingKeys: String, CodingKey {
        case enabledGroups
        case defaultRefreshIntervalSeconds
        case refreshIntervalsSeconds
        case history
        case processes
        case networkQuality
        case thresholds
    }

    static let `default` = SystemConfig(
        enabledGroups: [.vitals, .gpu, .thermals, .power, .network, .storage],
        defaultRefreshIntervalSeconds: 2,
        refreshIntervalsSeconds: SystemMetricGroup.defaultRefreshIntervals,
        history: .default,
        processes: .default,
        networkQuality: .default,
        thresholds: .default
    )

    init(
        enabledGroups: Set<SystemMetricGroup>,
        defaultRefreshIntervalSeconds: TimeInterval,
        refreshIntervalsSeconds: [SystemMetricGroup: TimeInterval],
        history: HistoryConfig = .default,
        processes: ProcessMonitoringConfig = .default,
        networkQuality: NetworkQualityConfig = .default,
        thresholds: HealthThresholdsConfig = .default
    ) {
        self.enabledGroups = enabledGroups
        self.defaultRefreshIntervalSeconds = defaultRefreshIntervalSeconds
        self.refreshIntervalsSeconds = refreshIntervalsSeconds
        self.history = history
        self.processes = processes
        self.networkQuality = networkQuality
        self.thresholds = thresholds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SystemConfig.default

        let groups = try container.decodeIfPresent([SystemMetricGroup].self, forKey: .enabledGroups)
        enabledGroups = Set(groups ?? Array(defaults.enabledGroups))
        defaultRefreshIntervalSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .defaultRefreshIntervalSeconds)
            ?? defaults.defaultRefreshIntervalSeconds

        if let stringIntervals = try? container.decode([String: TimeInterval].self, forKey: .refreshIntervalsSeconds) {
            refreshIntervalsSeconds = Dictionary(
                uniqueKeysWithValues: stringIntervals.compactMap { key, value in
                    guard let group = SystemMetricGroup(rawValue: key) else { return nil }
                    return (group, value)
                }
            )
        } else {
            refreshIntervalsSeconds = defaults.refreshIntervalsSeconds
        }
        history = try container.decodeIfPresent(HistoryConfig.self, forKey: .history) ?? .default
        processes = try container.decodeIfPresent(ProcessMonitoringConfig.self, forKey: .processes) ?? .default
        networkQuality = try container.decodeIfPresent(NetworkQualityConfig.self, forKey: .networkQuality) ?? .default
        thresholds = try container.decodeIfPresent(HealthThresholdsConfig.self, forKey: .thresholds) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let groups = SystemMetricGroup.allCases.filter { enabledGroups.contains($0) }
        try container.encode(groups, forKey: .enabledGroups)
        try container.encode(defaultRefreshIntervalSeconds, forKey: .defaultRefreshIntervalSeconds)

        let intervals = Dictionary(
            uniqueKeysWithValues: SystemMetricGroup.allCases.compactMap { group -> (String, TimeInterval)? in
                guard let value = refreshIntervalsSeconds[group] else { return nil }
                return (group.rawValue, value)
            }
        )
        try container.encode(intervals, forKey: .refreshIntervalsSeconds)
        try container.encode(history, forKey: .history)
        try container.encode(processes, forKey: .processes)
        try container.encode(networkQuality, forKey: .networkQuality)
        try container.encode(thresholds, forKey: .thresholds)
    }

    func normalized() -> SystemConfig {
        var copy = self
        if !copy.defaultRefreshIntervalSeconds.isFinite || copy.defaultRefreshIntervalSeconds < 1 {
            copy.defaultRefreshIntervalSeconds = Self.default.defaultRefreshIntervalSeconds
        }

        if copy.enabledGroups.isEmpty {
            copy.enabledGroups = Self.default.enabledGroups
        }

        for group in SystemMetricGroup.allCases {
            let fallback = SystemMetricGroup.defaultRefreshIntervals[group] ?? copy.defaultRefreshIntervalSeconds
            let value = copy.refreshIntervalsSeconds[group] ?? fallback
            copy.refreshIntervalsSeconds[group] = value.isFinite ? max(1, value) : fallback
        }

        copy.history = copy.history.normalized()
        copy.processes = copy.processes.normalized()
        copy.networkQuality = copy.networkQuality.normalized()
        copy.thresholds = copy.thresholds.normalized()

        return copy
    }
}
struct HistoryConfig: Codable, Equatable {
    var enabled: Bool
    var durationSeconds: TimeInterval
    var sampleIntervalSeconds: TimeInterval

    static let `default` = HistoryConfig(enabled: true, durationSeconds: 600, sampleIntervalSeconds: 2)

    func normalized() -> HistoryConfig {
        var copy = self
        let allowedDurations: [TimeInterval] = [600, 1_800, 3_600]
        copy.durationSeconds = allowedDurations.min(by: {
            abs($0 - copy.durationSeconds) < abs($1 - copy.durationSeconds)
        }) ?? Self.default.durationSeconds
        if !copy.sampleIntervalSeconds.isFinite || copy.sampleIntervalSeconds < 1 {
            copy.sampleIntervalSeconds = Self.default.sampleIntervalSeconds
        }
        copy.sampleIntervalSeconds = min(copy.sampleIntervalSeconds, 30)
        return copy
    }
}

struct ProcessMonitoringConfig: Codable, Equatable {
    var enabled: Bool
    var refreshIntervalSeconds: TimeInterval
    var limit: Int

    static let `default` = ProcessMonitoringConfig(enabled: true, refreshIntervalSeconds: 5, limit: 5)

    func normalized() -> ProcessMonitoringConfig {
        var copy = self
        if !copy.refreshIntervalSeconds.isFinite || copy.refreshIntervalSeconds < 2 {
            copy.refreshIntervalSeconds = Self.default.refreshIntervalSeconds
        }
        copy.limit = min(10, max(1, copy.limit))
        return copy
    }
}

struct NetworkQualityConfig: Codable, Equatable {
    var enabled: Bool
    var host: String
    var port: UInt16
    var intervalSeconds: TimeInterval
    var timeoutSeconds: TimeInterval

    static let `default` = NetworkQualityConfig(
        enabled: false,
        host: "1.1.1.1",
        port: 443,
        intervalSeconds: 15,
        timeoutSeconds: 3
    )

    func normalized() -> NetworkQualityConfig {
        var copy = self
        copy.host = copy.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.host.isEmpty { copy.host = Self.default.host }
        if copy.port == 0 { copy.port = Self.default.port }
        if !copy.intervalSeconds.isFinite || copy.intervalSeconds < 5 {
            copy.intervalSeconds = Self.default.intervalSeconds
        }
        if !copy.timeoutSeconds.isFinite || copy.timeoutSeconds < 0.5 {
            copy.timeoutSeconds = Self.default.timeoutSeconds
        }
        copy.timeoutSeconds = min(copy.timeoutSeconds, copy.intervalSeconds)
        return copy
    }
}

struct HealthThresholdsConfig: Codable, Equatable {
    var cpuHighPercent: Double
    var cpuSustainSeconds: TimeInterval
    var diskFreePercent: Double
    var networkOfflineSeconds: TimeInterval

    static let `default` = HealthThresholdsConfig(
        cpuHighPercent: 85,
        cpuSustainSeconds: 30,
        diskFreePercent: 10,
        networkOfflineSeconds: 15
    )

    func normalized() -> HealthThresholdsConfig {
        var copy = self
        copy.cpuHighPercent = min(100, max(1, copy.cpuHighPercent.isFinite ? copy.cpuHighPercent : Self.default.cpuHighPercent))
        copy.cpuSustainSeconds = max(1, copy.cpuSustainSeconds.isFinite ? copy.cpuSustainSeconds : Self.default.cpuSustainSeconds)
        copy.diskFreePercent = min(99, max(1, copy.diskFreePercent.isFinite ? copy.diskFreePercent : Self.default.diskFreePercent))
        copy.networkOfflineSeconds = max(1, copy.networkOfflineSeconds.isFinite ? copy.networkOfflineSeconds : Self.default.networkOfflineSeconds)
        return copy
    }
}
