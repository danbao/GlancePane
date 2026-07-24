import Foundation

final class ConfigStore {
    private let fileManager: FileManager
    private let homeDirectoryURL: URL
    let configDirectoryURL: URL
    let legacyConfigDirectoryURLs: [URL]
    let configURL: URL
    let stockCacheURL: URL
    let weatherCacheURL: URL
    let codexUsageCacheURL: URL

    init(fileManager: FileManager = .default) {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let appSupportBase = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")

        self.fileManager = fileManager
        homeDirectoryURL = home
        configDirectoryURL = home.appendingPathComponent(".glancepane", isDirectory: true)
        legacyConfigDirectoryURLs = [
            home.appendingPathComponent(".glancedeck", isDirectory: true),
            appSupportBase.appendingPathComponent("GlanceDeck", isDirectory: true),
            appSupportBase.appendingPathComponent("SmartScreen", isDirectory: true)
        ]
        configURL = configDirectoryURL.appendingPathComponent("config.json")
        stockCacheURL = configDirectoryURL.appendingPathComponent("stock-cache.json")
        weatherCacheURL = configDirectoryURL.appendingPathComponent("weather-cache.json")
        codexUsageCacheURL = configDirectoryURL.appendingPathComponent("codex-usage-cache.json")
    }

    init(
        configDirectoryURL: URL,
        legacyConfigDirectoryURLs: [URL] = [],
        homeDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL ?? configDirectoryURL.deletingLastPathComponent()
        self.configDirectoryURL = configDirectoryURL
        self.legacyConfigDirectoryURLs = legacyConfigDirectoryURLs
        configURL = configDirectoryURL.appendingPathComponent("config.json")
        stockCacheURL = configDirectoryURL.appendingPathComponent("stock-cache.json")
        weatherCacheURL = configDirectoryURL.appendingPathComponent("weather-cache.json")
        codexUsageCacheURL = configDirectoryURL.appendingPathComponent("codex-usage-cache.json")
    }

    func load() -> AppConfig {
        ensureDirectory()
        migrateLegacyFilesIfNeeded()
        secureExistingFiles()

        guard let data = try? Data(contentsOf: configURL) else {
            save(.default)
            return .default
        }

        do {
            let isLegacyConfig = Self.isLegacyConfig(data)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            var normalized = config.normalized()
            normalized = migrateLegacyQWeatherKeyIfNeeded(in: normalized)
            if isLegacyConfig {
                backupLegacyConfig()
            }
            save(normalized)
            return normalized
        } catch {
            let backup = configURL.deletingLastPathComponent()
                .appendingPathComponent("config.invalid-\(Int(Date().timeIntervalSince1970)).json")
            try? SecureFileStore.copy(from: configURL, to: backup, fileManager: fileManager)
            save(.default)
            return .default
        }
    }

    private static func isLegacyConfig(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        let groupedKeys: Set<String> = [
            "display",
            "appearance",
            "interaction",
            "pages",
            "system",
            "agents",
            "market",
            "weather",
            "protection"
        ]
        let legacyKeys: Set<String> = [
            "targetDisplayName",
            "stockSymbols",
            "weatherProvider",
            "weatherLocationName",
            "weatherLongitude",
            "weatherLatitude",
            "qweatherApiHost",
            "qweatherKeyID",
            "qweatherProjectID",
            "qweatherPrivateKeyPath",
            "weatherRefreshIntervalSeconds",
            "refreshIntervalSeconds",
            "theme",
            "mousePassthrough",
            "enabledMetricGroups",
            "metricRefreshIntervals",
            "burnInProtection",
            "pageOrder",
            "enabledPages",
            "autoPageRotationEnabled",
            "autoPageRotationIntervalSeconds"
        ]

        let keys = Set(object.keys)
        let schemaVersion = object["schemaVersion"] as? Int ?? 1
        if schemaVersion < AppConfig.default.schemaVersion {
            return true
        }
        if let interaction = object["interaction"] as? [String: Any],
           interaction["mousePassthrough"] != nil {
            return true
        }
        return keys.isDisjoint(with: groupedKeys) && !keys.isDisjoint(with: legacyKeys)
    }

    private func backupLegacyConfig() {
        let backup = configURL.deletingLastPathComponent()
            .appendingPathComponent("config.legacy-\(Int(Date().timeIntervalSince1970)).json")
        try? SecureFileStore.copy(from: configURL, to: backup, fileManager: fileManager)
    }

    func save(_ config: AppConfig) {
        ensureDirectory()

        do {
            try export(config, to: configURL)
        } catch {
            NSLog("GlancePane failed to write config: \(error)")
        }
    }

    func importConfig(from url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppConfig.self, from: data).normalized()
    }

    func export(_ config: AppConfig, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config.normalized())
        let isAppConfig = url.standardizedFileURL.path.hasPrefix(
            configDirectoryURL.standardizedFileURL.path + "/"
        )
        try SecureFileStore.write(
            data,
            to: url,
            secureParent: isAppConfig,
            fileManager: fileManager
        )
    }

    private func ensureDirectory() {
        do {
            try SecureFileStore.ensurePrivateDirectory(at: configDirectoryURL, fileManager: fileManager)
        } catch {
            NSLog("GlancePane failed to create config directory: \(error)")
        }
    }

    private func migrateLegacyFilesIfNeeded() {
        copyLegacyFileIfNeeded(named: "config.json")
        copyLegacyFileIfNeeded(named: "stock-cache.json")
        copyLegacyFileIfNeeded(named: "weather-cache.json")
        copyLegacyFileIfNeeded(named: "codex-usage-cache.json")
    }

    private func secureExistingFiles() {
        let knownFiles = [configURL, stockCacheURL, weatherCacheURL, codexUsageCacheURL]
        for url in knownFiles where fileManager.fileExists(atPath: url.path) {
            try? SecureFileStore.secureFile(at: url, fileManager: fileManager)
        }

        guard let names = try? fileManager.contentsOfDirectory(atPath: configDirectoryURL.path) else {
            return
        }
        for name in names
        where name.hasPrefix("config.legacy-") || name.hasPrefix("config.invalid-") {
            let url = configDirectoryURL.appendingPathComponent(name)
            try? SecureFileStore.secureFile(at: url, fileManager: fileManager)
        }
    }

    private func copyLegacyFileIfNeeded(named fileName: String) {
        let destination = configDirectoryURL.appendingPathComponent(fileName)
        guard !fileManager.fileExists(atPath: destination.path) else {
            return
        }

        guard let source = legacyConfigDirectoryURLs
            .map({ $0.appendingPathComponent(fileName) })
            .first(where: { fileManager.fileExists(atPath: $0.path) })
        else { return }

        do {
            try SecureFileStore.copy(from: source, to: destination, fileManager: fileManager)
        } catch {
            NSLog("GlancePane failed to migrate \(fileName): \(error)")
        }
    }

    private func migrateLegacyQWeatherKeyIfNeeded(in config: AppConfig) -> AppConfig {
        let legacyPath = "~/.glancedeck/qweather/ed25519-private.pem"
        guard config.weather.qweather.privateKeyPath == legacyPath else {
            return config
        }

        let source = homeDirectoryURL
            .appendingPathComponent(".glancedeck/qweather/ed25519-private.pem")
        let destination = configDirectoryURL
            .appendingPathComponent("qweather/ed25519-private.pem")
        guard fileManager.fileExists(atPath: source.path) else {
            return config
        }

        do {
            if !fileManager.fileExists(atPath: destination.path) {
                try SecureFileStore.copy(from: source, to: destination, fileManager: fileManager)
            } else {
                try SecureFileStore.secureFile(at: destination, fileManager: fileManager)
            }
            var migrated = config
            migrated.weather.qweather.privateKeyPath = "~/.glancepane/qweather/ed25519-private.pem"
            return migrated
        } catch {
            NSLog("GlancePane failed to migrate QWeather private key: \(error)")
            return config
        }
    }
}

extension AppConfig {
    func normalized() -> AppConfig {
        var copy = self

        copy.schemaVersion = AppConfig.default.schemaVersion

        copy.display.targetName = copy.display.targetName.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.display.targetName.isEmpty {
            copy.display.targetName = AppConfig.default.display.targetName
        }

        copy.pages = copy.pages.normalized()
        copy.system = copy.system.normalized()
        copy.agents = copy.agents.normalized()
        copy.market = copy.market.normalized()
        copy.weather = copy.weather.normalized()
        copy.protection = copy.protection.normalized()

        return copy
    }
}
