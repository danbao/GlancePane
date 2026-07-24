import AppKit
import Darwin
import Foundation
import SwiftUI
import notify

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    let file: String
    let line: Int

    var description: String {
        "\(file):\(line): \(message)"
    }
}

struct TestCase {
    let name: String
    let run: () async throws -> Void

    init(_ name: String, run: @escaping () async throws -> Void) {
        self.name = name
        self.run = run
    }
}

@main
struct GlancePaneTestRunner {
    static func main() async {
        let tests = [
            TestCase("default config writes grouped schema") {
                try testDefaultConfigWritesGroupedSchema()
            },
            TestCase("default config protects private data") {
                try testPrivacySafeDefaultsAndPermissions()
            },
            TestCase("legacy flat config migrates and normalizes") {
                try testLegacyFlatConfigMigratesAndNormalizes()
            },
            TestCase("legacy grouped interaction migrates") {
                try testLegacyGroupedInteractionMigrates()
            },
            TestCase("schema v1 enables performance and agents for default pages") {
                try testSchemaV1EnablesPerformanceForDefaultPages()
            },
            TestCase("schema v2 agents migration preserves page choices") {
                try testSchemaV2AgentsMigrationPreservesPageChoices()
            },
            TestCase("schema v3 enables low frequency thermals") {
                try testSchemaV3EnablesLowFrequencyThermals()
            },
            TestCase("legacy directory files copy when missing") {
                try testLegacyDirectoryFilesCopyWhenMissing()
            },
            TestCase("legacy QWeather key migrates securely") {
                try testLegacyQWeatherKeyMigratesSecurely()
            },
            TestCase("invalid config backs up and resets") {
                try testInvalidConfigBacksUpAndResets()
            },
            TestCase("config import export round trips") {
                try testConfigImportExportRoundTrip()
            },
            TestCase("empty enabled pages recover clock") {
                try testEmptyEnabledPagesRecoverClock()
            },
            TestCase("dashboard visible page navigation") {
                try await testDashboardVisiblePageNavigation()
            },
            TestCase("dashboard page ordering") {
                try await testDashboardPageOrdering()
            },
            TestCase("stock cache filters symbols") {
                try testStockCacheFiltersSymbols()
            },
            TestCase("stock fetch skips empty symbols") {
                try await testStockFetchSkipsEmptySymbols()
            },
            TestCase("weather cache reads cached snapshot") {
                try testWeatherCacheReadsCachedSnapshot()
            },
            TestCase("weather fetch reports missing setup") {
                try await testWeatherFetchReportsMissingSetup()
            },
            TestCase("weather fetch keeps partial cached data") {
                try await testWeatherFetchKeepsPartialCachedData()
            },
            TestCase("weather icons map common conditions") {
                try testWeatherIconsMapCommonConditions()
            },
            TestCase("codex usage formats and fills daily history") {
                try testCodexUsageFormattingAndHistory()
            },
            TestCase("codex sessions parse incrementally without content") {
                try testCodexSessionCollectorIncrementalParsing()
            },
            TestCase("codex app server handles out of order responses") {
                try await testCodexAppServerOutOfOrderResponses()
            },
            TestCase("codex app server gives initialization a stable timeout") {
                try await testCodexAppServerInitializationTimeoutIsIndependent()
            },
            TestCase("codex app server maps unlimited and auth failure") {
                try await testCodexAppServerUnlimitedAndAuthFailure()
            },
            TestCase("codex usage service caches and stops") {
                try await testCodexUsageServiceCachesAndStops()
            },
            TestCase("hiding agents page stops Codex service") {
                try await testHidingAgentsPageStopsCodexService()
            },
            TestCase("codex app server reports timeout and exit") {
                try await testCodexAppServerTimeoutAndExit()
            },
            TestCase("codex app server closes readers safely") {
                try await testCodexAppServerReaderShutdown()
            },
            TestCase("mouse shield owns only inside-start gestures") {
                try testMouseClickShieldOwnership()
            },
            TestCase("window lifecycle defers changes while session is inactive") {
                try testWindowLifecycleDefersWhileSessionInactive()
            },
            TestCase("window lifecycle restores once after wake and unlock") {
                try testWindowLifecycleWakeAndUnlockOrdering()
            },
            TestCase("window lifecycle defers retries while screens sleep") {
                try testWindowLifecycleDefersRetriesWhileScreensSleep()
            },
            TestCase("window lifecycle stays hidden when launched while locked") {
                try testWindowLifecycleStartsLocked()
            },
            TestCase("window lifecycle waits for unlock after display wake") {
                try testWindowLifecycleWaitsForUnlockAfterWake()
            },
            TestCase("window lifecycle keeps session and screen lock independent") {
                try testWindowLifecycleSeparatesSessionAndScreenLock()
            },
            TestCase("screen lock monitor maps Darwin state values") {
                try testScreenLockMonitorStateMapping()
            },
            TestCase("screen lock monitor registers and stops") {
                try testScreenLockMonitorRegistration()
            },
            TestCase("screen lock monitor rechecks state on unlock edge") {
                try testScreenLockMonitorUnlockEdge()
            },
            TestCase("cpu tick delta handles counter rollover") {
                try testCPUTickDeltaRollover()
            },
            TestCase("cpu topology groups performance and efficiency cores") {
                try testCPUCoreGrouping()
            },
            TestCase("process cpu percent handles first sample and deltas") {
                try testProcessCPUPercent()
            },
            TestCase("metric history records sleep gaps and trims") {
                try testMetricHistoryGapsAndTrimming()
            },
            TestCase("health evaluator requires sustained warnings") {
                try testHealthEvaluatorSustainedWarnings()
            },
            TestCase("health evaluator builds status matrix") {
                try testHealthEvaluatorBuildsStatusMatrix()
            },
            TestCase("smc adapter decodes caches and reconnects") {
                try testSMCAdapterDecodesCachesAndReconnects()
            },
            TestCase("thermal sampling throttles and reconnects after wake") {
                try testThermalSamplingThrottlesAndReconnectsAfterWake()
            },
            TestCase("settings and login item use live state") {
                try await testSettingsAndLoginItemLiveState()
            },
            TestCase("login item migrates legacy main app registration") {
                try testLoginItemMigratesLegacyRegistration()
            },
            TestCase("relaunch policy distinguishes quit from crash") {
                try testRelaunchPolicySuppression()
            },
            TestCase("network probe is injectable and optional") {
                try await testNetworkProbeIsInjectableAndOptional()
            },
            TestCase("disabled system metrics clear stale values") {
                try testDisabledSystemMetricsClearStaleValues()
            },
            TestCase("stock fetch preserves per-symbol cache") {
                try await testStockFetchPreservesPerSymbolCache()
            },
            TestCase("config reload ignores stale stock response") {
                try await testConfigReloadIgnoresStaleStockResponse()
            },
            TestCase("dashboard pages render at 1280x720") {
                try await testDashboardPageSnapshots()
            }
        ]

        var failures = 0
        for test in tests {
            do {
                try await test.run()
                print("PASS \(test.name)")
            } catch {
                failures += 1
                print("FAIL \(test.name): \(error)")
            }
        }

        if failures > 0 {
            print("\n\(failures) GlancePane test(s) failed")
            exit(1)
        }

        print("\nAll \(tests.count) GlancePane tests passed")
    }
}

private func testDefaultConfigWritesGroupedSchema() throws {
    let directory = try makeTestDirectory("default-config")
    let store = ConfigStore(configDirectoryURL: directory)

    let config = store.load()
    try expectEqual(config, AppConfig.default)
    try expect(FileManager.default.fileExists(atPath: store.configURL.path), "config.json should be written")

    let object = try jsonObject(at: store.configURL)
    try expect(object["display"] != nil, "grouped display key should be present")
    try expect(object["pages"] != nil, "grouped pages key should be present")
    try expectEqual(object["schemaVersion"] as? Int, 5)
    try expect(object["agents"] != nil, "grouped agents key should be present")
    let agents = object["agents"] as? [String: Any]
    let codex = agents?["codex"] as? [String: Any]
    try expect(codex?["executablePath"] is NSNull, "automatic executable path should be written as null")
    try expect(codex?["codexHomePath"] is NSNull, "automatic Codex Home should be written as null")
    try expect(object["targetDisplayName"] == nil, "legacy flat display key should not be written")
    try expect(object["stockSymbols"] == nil, "legacy flat market key should not be written")
}

private func testPrivacySafeDefaultsAndPermissions() throws {
    let directory = try makeTestDirectory("private-defaults")
    let store = ConfigStore(configDirectoryURL: directory)
    try writeString("{}", to: store.stockCacheURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.stockCacheURL.path)
    let config = store.load()

    try expectEqual(config.display.targetName, "")
    try expectEqual(config.weather.location.name, "")
    try expectEqual(config.weather.location.longitude, nil)
    try expectEqual(config.weather.location.latitude, nil)
    try expectEqual(config.agents.codex.showProjectNames, false)
    try expectEqual(config.weather.qweather.privateKeyPath, "~/.glancepane/qweather/ed25519-private.pem")
    try expectEqual(posixPermissions(at: directory), 0o700)
    try expectEqual(posixPermissions(at: store.configURL), 0o600)
    try expectEqual(posixPermissions(at: store.stockCacheURL), 0o600)

    let cacheURL = directory.appendingPathComponent("permission-cache.json")
    try SecureFileStore.write(Data("{}".utf8), to: cacheURL)
    try expectEqual(posixPermissions(at: cacheURL), 0o600)

    let exportURL = directory.deletingLastPathComponent()
        .appendingPathComponent("export-\(UUID().uuidString).json")
    try store.export(config, to: exportURL)
    defer { try? FileManager.default.removeItem(at: exportURL) }
    try expectEqual(posixPermissions(at: exportURL), 0o600)
}

private func testLegacyFlatConfigMigratesAndNormalizes() throws {
    let directory = try makeTestDirectory("legacy-config")
    let store = ConfigStore(configDirectoryURL: directory)
    let legacyJSON = """
    {
      "targetDisplayName": " Portable ",
      "stockSymbols": [" aapl ", "MSFT", ""],
      "weatherProvider": "qweather",
      "weatherLocationName": " Sample District ",
      "weatherLongitude": 999,
      "weatherLatitude": -999,
      "qweatherApiHost": " https://api.qweather.com/ ",
      "qweatherKeyID": " kid ",
      "qweatherProjectID": " project ",
      "qweatherPrivateKeyPath": " /tmp/key.pem ",
      "weatherRefreshIntervalSeconds": 5,
      "refreshIntervalSeconds": 0,
      "theme": "terminal",
      "mousePassthrough": false,
      "enabledMetricGroups": ["vitals", "market", "network", "bogus"],
      "metricRefreshIntervals": {
        "vitals": 0,
        "network": 3,
        "market": 4
      },
      "burnInProtection": {
        "mode": "strong",
        "pixelShiftPixels": -1,
        "pixelShiftIntervalSeconds": 0,
        "dimAfterSeconds": -1,
        "dimOpacity": 2,
        "restAfterSeconds": 0,
        "restDurationSeconds": 0,
        "wakeOnPointer": false
      },
      "pageOrder": ["market", "clock", "market", "bogus"],
      "enabledPages": [],
      "autoPageRotationEnabled": true,
      "autoPageRotationIntervalSeconds": 1
    }
    """
    try writeString(legacyJSON, to: store.configURL)

    let config = store.load()

    try expectEqual(config.display.targetName, "Portable")
    try expectEqual(config.appearance.theme, .terminal)
    try expectEqual(config.interaction.clickNavigationEnabled, true)
    try expectEqual(config.pages.order, [.market, .clock, .system, .performance, .agents, .weather])
    try expectEqual(config.pages.enabled, [.clock])
    try expectEqual(config.pages.rotation.enabled, true)
    try expectEqual(config.pages.rotation.intervalSeconds, AppConfig.default.pages.rotation.intervalSeconds)

    try expectEqual(config.system.enabledGroups, [.vitals, .gpu, .thermals, .network])
    try expectEqual(config.system.defaultRefreshIntervalSeconds, AppConfig.default.system.defaultRefreshIntervalSeconds)
    try expectEqual(config.system.refreshIntervalsSeconds[.vitals], 1)
    try expectEqual(config.system.refreshIntervalsSeconds[.network], 3)

    try expectEqual(config.market.enabled, true)
    try expectEqual(config.market.symbols, ["AAPL", "MSFT"])
    try expectEqual(config.market.refreshIntervalSeconds, AppConfig.default.market.refreshIntervalSeconds)

    try expectEqual(config.weather.location.name, "Sample District")
    try expectEqual(config.weather.location.longitude, AppConfig.default.weather.location.longitude)
    try expectEqual(config.weather.location.latitude, AppConfig.default.weather.location.latitude)
    try expectEqual(config.weather.refreshIntervalSeconds, AppConfig.default.weather.refreshIntervalSeconds)
    try expectEqual(config.weather.qweather.apiHost, "https://api.qweather.com")
    try expectEqual(config.weather.qweather.keyID, "kid")
    try expectEqual(config.weather.qweather.projectID, "project")
    try expectEqual(config.weather.qweather.privateKeyPath, "/tmp/key.pem")

    try expectEqual(config.protection.pixelShift.pixels, AppConfig.default.protection.pixelShift.pixels)
    try expectEqual(config.protection.pixelShift.intervalSeconds, AppConfig.default.protection.pixelShift.intervalSeconds)
    try expectEqual(config.protection.dim.afterSeconds, AppConfig.default.protection.dim.afterSeconds)
    try expectEqual(config.protection.dim.opacity, 0.95)
    try expectEqual(config.protection.rest.afterSeconds, AppConfig.default.protection.rest.afterSeconds)
    try expectEqual(config.protection.rest.durationSeconds, AppConfig.default.protection.rest.durationSeconds)
    try expectEqual(config.protection.wakeOnPointer, false)

    try expectEqual(files(in: directory, prefix: "config.legacy-").count, 1)
    let saved = try jsonObject(at: store.configURL)
    try expect(saved["display"] != nil, "migrated config should be grouped")
    try expect(saved["targetDisplayName"] == nil, "migrated config should drop flat keys")
}

private func testSchemaV1EnablesPerformanceForDefaultPages() throws {
    let directory = try makeTestDirectory("schema-v1-performance")
    let store = ConfigStore(configDirectoryURL: directory)
    try writeString(
        """
        {
          "pages": {
            "enabled": ["clock", "system", "market", "weather"],
            "order": ["clock", "system", "market", "weather"],
            "rotation": { "enabled": true, "intervalSeconds": 30 }
          }
        }
        """,
        to: store.configURL
    )

    let config = store.load()
    try expectEqual(config.schemaVersion, 5)
    try expectEqual(config.pages.order, DashboardPage.defaultOrder)
    try expect(config.pages.enabled.contains(.performance), "performance should be enabled for an unchanged v1 page set")
    try expect(config.pages.enabled.contains(.agents), "agents should be enabled for an unchanged v1 page set")
    try expectEqual(files(in: directory, prefix: "config.legacy-").count, 1)
}

private func testSchemaV2AgentsMigrationPreservesPageChoices() throws {
    let defaultDirectory = try makeTestDirectory("schema-v2-agents-default")
    let defaultStore = ConfigStore(configDirectoryURL: defaultDirectory)
    try writeString(
        """
        {
          "schemaVersion": 2,
          "pages": {
            "enabled": ["clock", "system", "performance", "market", "weather"],
            "order": ["clock", "system", "performance", "market", "weather"],
            "rotation": { "enabled": true, "intervalSeconds": 30 }
          }
        }
        """,
        to: defaultStore.configURL
    )

    let migratedDefault = defaultStore.load()
    try expectEqual(migratedDefault.schemaVersion, 5)
    try expectEqual(migratedDefault.pages.order, DashboardPage.defaultOrder)
    try expect(migratedDefault.pages.enabled.contains(.agents), "unchanged v2 pages should enable agents")

    let customDirectory = try makeTestDirectory("schema-v2-agents-custom")
    let customStore = ConfigStore(configDirectoryURL: customDirectory)
    try writeString(
        """
        {
          "schemaVersion": 2,
          "pages": {
            "enabled": ["clock", "system", "performance", "weather"],
            "order": ["system", "clock", "performance", "market", "weather"],
            "rotation": { "enabled": true, "intervalSeconds": 30 }
          }
        }
        """,
        to: customStore.configURL
    )

    let migratedCustom = customStore.load()
    try expectEqual(migratedCustom.pages.order, [.system, .clock, .performance, .agents, .market, .weather])
    try expect(!migratedCustom.pages.enabled.contains(.agents), "custom page visibility should not be changed")
    try expect(!migratedCustom.pages.enabled.contains(.market), "hidden market page should remain hidden")
}

private func testSchemaV3EnablesLowFrequencyThermals() throws {
    let directory = try makeTestDirectory("schema-v3-thermals")
    let store = ConfigStore(configDirectoryURL: directory)
    try writeString(
        """
        {
          "schemaVersion": 3,
          "system": {
            "enabledGroups": ["vitals", "gpu", "power", "network", "storage"],
            "defaultRefreshIntervalSeconds": 2,
            "refreshIntervalsSeconds": {
              "vitals": 2,
              "gpu": 2,
              "power": 10,
              "network": 2,
              "storage": 2,
              "thermals": 8
            }
          }
        }
        """,
        to: store.configURL
    )

    let config = store.load()
    try expectEqual(config.schemaVersion, 5)
    try expect(config.system.enabledGroups.contains(.thermals), "v3 migration should enable thermals")
    try expectEqual(config.system.refreshIntervalsSeconds[.thermals], 10)
    try expectEqual(files(in: directory, prefix: "config.legacy-").count, 1)
}

private func testLegacyGroupedInteractionMigrates() throws {
    let directory = try makeTestDirectory("legacy-interaction")
    let store = ConfigStore(configDirectoryURL: directory)
    try writeString(
        """
        {
          "interaction": {
            "mousePassthrough": true
          }
        }
        """,
        to: store.configURL
    )

    let config = store.load()
    try expectEqual(config.interaction.clickNavigationEnabled, true)
    try expectEqual(files(in: directory, prefix: "config.legacy-").count, 1)

    let object = try jsonObject(at: store.configURL)
    let interaction = object["interaction"] as? [String: Any]
    try expectEqual(interaction?["clickNavigationEnabled"] as? Bool, true)
    try expect(interaction?["mousePassthrough"] == nil, "legacy interaction key should not be written")
}

private func testLegacyDirectoryFilesCopyWhenMissing() throws {
    let directory = try makeTestDirectory("legacy-current")
    let legacyDirectory = try makeTestDirectory("legacy-source")
    let store = ConfigStore(configDirectoryURL: directory, legacyConfigDirectoryURLs: [legacyDirectory])
    var config = AppConfig.default
    config.display.targetName = "Legacy Display"

    try writeJSON(config, to: legacyDirectory.appendingPathComponent("config.json"))
    try writeString("{\"quotes\":[],\"fetchedAt\":0}", to: legacyDirectory.appendingPathComponent("stock-cache.json"))
    try writeString("{\"provider\":\"qweather\"}", to: legacyDirectory.appendingPathComponent("weather-cache.json"))

    let loaded = store.load()

    try expectEqual(loaded.display.targetName, "Legacy Display")
    try expect(FileManager.default.fileExists(atPath: store.stockCacheURL.path), "stock cache should be copied")
    try expect(FileManager.default.fileExists(atPath: store.weatherCacheURL.path), "weather cache should be copied")
}

private func testLegacyQWeatherKeyMigratesSecurely() throws {
    let home = try makeTestDirectory("legacy-key-home")
    let legacyDirectory = home.appendingPathComponent(".glancedeck", isDirectory: true)
    let legacyKey = legacyDirectory.appendingPathComponent("qweather/ed25519-private.pem")
    try writeString("private-key-fixture", to: legacyKey)

    let legacyConfig = AppConfig(
        display: .default,
        appearance: .default,
        interaction: .default,
        pages: .default,
        system: .default,
        agents: .default,
        market: .default,
        weather: WeatherConfig(
            provider: .qweather,
            location: WeatherLocationConfig(name: "Sample District", longitude: 120, latitude: 30),
            refreshIntervalSeconds: 600,
            qweather: QWeatherConfig(
                apiHost: "api.example.test",
                keyID: "fixture-kid",
                projectID: "fixture-project",
                privateKeyPath: "~/.glancedeck/qweather/ed25519-private.pem"
            )
        ),
        protection: .default
    )
    try writeJSON(legacyConfig, to: legacyDirectory.appendingPathComponent("config.json"))

    let destination = home.appendingPathComponent(".glancepane", isDirectory: true)
    let store = ConfigStore(
        configDirectoryURL: destination,
        legacyConfigDirectoryURLs: [legacyDirectory],
        homeDirectoryURL: home
    )
    let migrated = store.load()
    let migratedKey = destination.appendingPathComponent("qweather/ed25519-private.pem")

    try expectEqual(migrated.weather.qweather.privateKeyPath, "~/.glancepane/qweather/ed25519-private.pem")
    try expect(FileManager.default.fileExists(atPath: migratedKey.path), "legacy private key should migrate")
    try expectEqual(posixPermissions(at: migratedKey), 0o600)
    try expectEqual(posixPermissions(at: migratedKey.deletingLastPathComponent()), 0o700)
}

private func testInvalidConfigBacksUpAndResets() throws {
    let directory = try makeTestDirectory("invalid-config")
    let store = ConfigStore(configDirectoryURL: directory)
    try writeString("{ this is not json", to: store.configURL)

    let config = store.load()

    try expectEqual(config, AppConfig.default)
    try expectEqual(files(in: directory, prefix: "config.invalid-").count, 1)
    try expect(FileManager.default.fileExists(atPath: store.configURL.path), "replacement config should be written")
}

private func testConfigImportExportRoundTrip() throws {
    let directory = try makeTestDirectory("config-round-trip")
    let store = ConfigStore(configDirectoryURL: directory)
    let exportURL = directory.appendingPathComponent("export.json")
    var config = AppConfig.default
    config.appearance.theme = .graphite
    config.system.history.durationSeconds = 1_800
    config.system.networkQuality.enabled = true

    try store.export(config, to: exportURL)
    let imported = try store.importConfig(from: exportURL)

    try expectEqual(imported, config.normalized())
}

private func testEmptyEnabledPagesRecoverClock() throws {
    let directory = try makeTestDirectory("empty-pages")
    let store = ConfigStore(configDirectoryURL: directory)
    var config = AppConfig.default
    config.pages.enabled = []
    config.pages.order = DashboardPage.defaultOrder

    store.save(config)
    let loaded = store.load()

    try expectEqual(loaded.pages.enabled, [.clock])
    try expectEqual(loaded.pages.order, DashboardPage.defaultOrder)
}

private func testDashboardVisiblePageNavigation() async throws {
    try await MainActor.run {
        let directory = try makeTestDirectory("page-navigation")
        let store = ConfigStore(configDirectoryURL: directory)
        var config = AppConfig.default
        config.pages.order = [.system, .clock, .market, .weather]
        config.pages.enabled = [.system, .clock, .weather]
        let model = DashboardModel(config: config, configStore: store, displayManager: DisplayManager())

        try expectEqual(model.visiblePages, [.system, .clock, .weather])
        try expectEqual(model.page, .system)
        try expectEqual(model.pageDisplayTitle, "SYSTEM 1/3")

        model.showNextPage()
        try expectEqual(model.page, .clock)
        try expectEqual(model.pageDisplayTitle, "CLOCK 2/3")

        model.showNextPage()
        try expectEqual(model.page, .weather)
        try expectEqual(model.pageDisplayTitle, "WEATHER 3/3")

        model.showNextPage()
        try expectEqual(model.page, .system)

        model.showPreviousPage()
        try expectEqual(model.page, .weather)

        model.setPage(.weather, enabled: false)
        try expectEqual(model.page, .system)
        try expectEqual(model.visiblePages, [.system, .clock])

        model.setPage(.system, enabled: false)
        try expectEqual(model.visiblePages, [.clock])
        try expectEqual(model.page, .clock)

        model.setPage(.clock, enabled: false)
        try expectEqual(model.visiblePages, [.clock])
        try expectEqual(model.page, .clock)

        model.showNextPage()
        try expectEqual(model.page, .clock)
        model.showPreviousPage()
        try expectEqual(model.page, .clock)
    }
}

private func testDashboardPageOrdering() async throws {
    try await MainActor.run {
        let directory = try makeTestDirectory("page-ordering")
        let store = ConfigStore(configDirectoryURL: directory)
        let model = DashboardModel(config: AppConfig.default, configStore: store, displayManager: DisplayManager())

        model.showPage(.market)
        try expectEqual(model.page, .market)
        try expectEqual(model.canMoveCurrentPageEarlier, true)
        try expectEqual(model.canMoveCurrentPageLater, true)

        model.moveCurrentPageEarlier()
        try expectEqual(model.config.pages.order, [.clock, .system, .performance, .market, .agents, .weather])
        try expectEqual(model.pageDisplayTitle, "MARKET 4/6")

        model.moveCurrentPageLater()
        try expectEqual(model.config.pages.order, DashboardPage.defaultOrder)
        try expectEqual(model.pageDisplayTitle, "MARKET 5/6")

        model.resetPageOrder()
        try expectEqual(model.config.pages.order, DashboardPage.defaultOrder)
    }
}

private func testStockCacheFiltersSymbols() throws {
    let directory = try makeTestDirectory("stock-cache")
    let store = ConfigStore(configDirectoryURL: directory)
    let snapshot = StockSnapshot(
        quotes: [
            makeQuote(symbol: "AAPL", name: "Apple"),
            makeQuote(symbol: "MSFT", name: "Microsoft")
        ],
        fetchedAt: Date(timeIntervalSince1970: 100)
    )
    try writeJSON(snapshot, to: store.stockCacheURL)

    let service = StockService(cacheURL: store.stockCacheURL)
    let quotes = service.loadCached(symbols: ["MSFT", "TSLA"])

    try expectEqual(quotes.map(\.symbol), ["MSFT"])
    try expectEqual(quotes.first?.isCached, true)
}

private func testStockFetchSkipsEmptySymbols() async throws {
    let directory = try makeTestDirectory("empty-stock-fetch")
    let store = ConfigStore(configDirectoryURL: directory)
    let service = StockService(cacheURL: store.stockCacheURL)

    let result = await service.fetch(symbols: [" ", ""])

    switch result {
    case .success(let quotes):
        try expectEqual(quotes, [])
    case .failure(let error):
        throw TestFailure(message: "expected success for empty symbols, got \(error)", file: #fileID, line: #line)
    }
}

private func testWeatherCacheReadsCachedSnapshot() throws {
    let directory = try makeTestDirectory("weather-cache")
    let store = ConfigStore(configDirectoryURL: directory)
    let snapshot = makeWeatherSnapshot()
    try writeJSON(snapshot, to: store.weatherCacheURL)

    let service = WeatherService(cacheURL: store.weatherCacheURL)
    let cached = service.loadCached()

    try expectEqual(cached?.isCached, true)
    try expectEqual(cached?.locationName, "Sample District")
    try expectEqual(cached?.current?.condition, "多云")
}

private func testWeatherFetchReportsMissingSetup() async throws {
    let directory = try makeTestDirectory("weather-setup")
    let store = ConfigStore(configDirectoryURL: directory)
    let service = WeatherService(cacheURL: store.weatherCacheURL)
    var config = AppConfig.default
    config.weather.location = WeatherLocationConfig(name: "Sample District", longitude: 120, latitude: 30)
    config.weather.qweather.apiHost = ""

    let result = await service.fetch(config: config)

    switch result {
    case .failure(.setupRequired(let message)):
        try expect(message.contains("apiHost"), "setup message should mention apiHost")
    case .success:
        throw TestFailure(message: "expected setupRequired failure", file: #fileID, line: #line)
    case .failure(let error):
        throw TestFailure(message: "expected setupRequired failure, got \(error)", file: #fileID, line: #line)
    }
}

private func testWeatherFetchKeepsPartialCachedData() async throws {
    let directory = try makeTestDirectory("weather-partial")
    let store = ConfigStore(configDirectoryURL: directory)
    try writeJSON(makeWeatherSnapshot(), to: store.weatherCacheURL)

    let client = MockHTTPClient { request in
        switch request.url?.path {
        case "/v7/weather/now":
            throw URLError(.timedOut)
        case "/v7/weather/24h":
            return try httpResponse(
                for: request,
                json: """
                {
                  "code": "200",
                  "hourly": [
                    {
                      "fxTime": "2026-07-10T10:00+08:00",
                      "temp": "31",
                      "text": "晴",
                      "icon": "100",
                      "pop": "0",
                      "precip": "0.0"
                    }
                  ],
                  "fxLink": "https://www.qweather.com"
                }
                """
            )
        case "/v7/minutely/5m":
            return try httpResponse(for: request, json: "{\"code\":\"204\"}")
        default:
            throw URLError(.badURL)
        }
    }

    setenv("GLANCEPANE_QWEATHER_JWT", "test-token", 1)
    defer { unsetenv("GLANCEPANE_QWEATHER_JWT") }

    var config = AppConfig.default
    config.weather.location = WeatherLocationConfig(name: "Sample District", longitude: 120, latitude: 30)
    config.weather.qweather.apiHost = "https://example.test"
    let service = WeatherService(cacheURL: store.weatherCacheURL, client: client)
    let result = await service.fetch(config: config)

    switch result {
    case .success(let snapshot):
        try expectEqual(snapshot.current?.condition, "多云")
        try expectEqual(snapshot.hourly.first?.condition, "晴")
        try expect(snapshot.errorMessage != nil, "partial snapshot should retain the request error")
    case .failure(let error):
        throw TestFailure(message: "expected partial weather success, got \(error)", file: #fileID, line: #line)
    }
}

private func testWeatherIconsMapCommonConditions() throws {
    try expectEqual(WeatherIconMapper.symbolName(for: "100", condition: nil), "sun.max.fill")
    try expectEqual(WeatherIconMapper.symbolName(for: "150", condition: nil), "moon.stars.fill")
    try expectEqual(WeatherIconMapper.symbolName(for: "104", condition: nil), "cloud.fill")
    try expectEqual(WeatherIconMapper.symbolName(for: "301", condition: nil), "cloud.rain.fill")
    try expectEqual(WeatherIconMapper.symbolName(for: "308", condition: nil), "cloud.heavyrain.fill")
    try expectEqual(WeatherIconMapper.symbolName(for: "302", condition: nil), "cloud.bolt.rain.fill")
    try expectEqual(WeatherIconMapper.symbolName(for: "400", condition: nil), "cloud.snow.fill")
    try expectEqual(WeatherIconMapper.symbolName(for: "500", condition: nil), "cloud.fog.fill")
    try expectEqual(WeatherIconMapper.symbolName(for: "503", condition: nil), "wind")
    try expectEqual(WeatherIconMapper.symbolName(for: "900", condition: nil), "thermometer.sun.fill")
    try expectEqual(WeatherIconMapper.symbolName(for: nil, condition: "雷阵雨"), "cloud.bolt.rain.fill")
    try expectEqual(WeatherIconMapper.symbolName(for: nil, condition: "多云"), "cloud.fill")
    try expectEqual(WeatherIconMapper.symbolName(for: nil, condition: nil), "questionmark.circle.fill")
}

private func testCodexUsageFormattingAndHistory() throws {
    try expectEqual(Int64(842).formattedTokenCount(), "842")
    try expectEqual(Int64(84_200).formattedTokenCount(), "84.2K")
    try expectEqual(Int64(91_600_000).formattedTokenCount(), "91.6M")
    try expectEqual(Int64(25_300_000_000).formattedTokenCount(), "25.3B")
    try expectEqual(codexUsageSeverity(for: 0.69), .normal)
    try expectEqual(codexUsageSeverity(for: 0.70), .warning)
    try expectEqual(codexUsageSeverity(for: 0.85), .critical)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 10))!
    let account = CodexAccountUsage(
        lifetimeTokens: 1_000,
        peakDailyTokens: 500,
        longestRunningTurnSeconds: 60,
        currentStreakDays: 2,
        longestStreakDays: 3,
        dailyUsage: [
            CodexDailyUsage(date: "2026-07-11", tokens: 100),
            CodexDailyUsage(date: "2026-07-13", tokens: 300)
        ]
    )
    let recent = account.recentDailyUsage(days: 14, now: now, calendar: calendar)
    try expectEqual(recent.count, 14)
    try expectEqual(recent.first?.date, "2026-06-30")
    try expectEqual(recent.last?.date, "2026-07-13")
    try expectEqual(recent.first(where: { $0.date == "2026-07-12" })?.tokens, 0)
    try expectEqual(account.todayTokens(now: now, calendar: calendar), 300)
}

private func testCodexSessionCollectorIncrementalParsing() throws {
    let home = try makeTestDirectory("codex-session-home")
    let directory = home.appendingPathComponent("sessions/2026/07/13", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let logURL = directory.appendingPathComponent("rollout-test.jsonl")
    let now = Date()
    let firstTimestamp = iso8601Timestamp(now)
    let ignoredTimestamp = iso8601Timestamp(now.addingTimeInterval(3_600))
    let initial = """
    {"timestamp":"\(firstTimestamp)","type":"session_meta","payload":{"id":"session-1","cwd":"/tmp/SecretProject","source":"vscode"}}
    {"timestamp":"\(firstTimestamp)","type":"turn_context","payload":{"model":"gpt-5.6","cwd":"/tmp/SecretProject"}}
    {"timestamp":"\(firstTimestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":900000},"last_token_usage":{"input_tokens":50000,"cached_input_tokens":40000,"output_tokens":1000,"reasoning_output_tokens":300,"total_tokens":51000},"model_context_window":200000}}}
    {"timestamp":"\(ignoredTimestamp)","type":"response_item","payload":{"text":"private prompt content token_count"}}

    """
    try writeString(initial, to: logURL)

    let collector = CodexSessionCollector(
        codexHomeURL: home,
        discoveryIntervalSeconds: 0,
        initialTailByteLimit: 16_384
    )
    var sessions = collector.collect(limit: 3, showProjectNames: true, now: now.addingTimeInterval(1))
    try expectEqual(sessions.count, 1)
    try expectEqual(sessions[0].id, "session-1")
    try expectEqual(sessions[0].projectName, "SecretProject")
    try expectEqual(sessions[0].model, "gpt-5.6")
    try expectEqual(sessions[0].contextTokens, 51_000)
    try expectEqual(sessions[0].contextWindow, 200_000)
    try expectEqual(sessions[0].contextPercent, 26)
    try expectEqual(sessions[0].sessionTotalTokens, 900_000)
    try expectEqual(sessions[0].isActive, true)
    try expect(abs(sessions[0].updatedAt.timeIntervalSince(now)) < 1, "ignored response content must not advance session activity")

    let secondTimestamp = iso8601Timestamp(now.addingTimeInterval(20))
    let update = """
    {"timestamp":"\(secondTimestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":950000},"last_token_usage":{"input_tokens":100000,"cached_input_tokens":80000,"output_tokens":2000,"reasoning_output_tokens":500,"total_tokens":102000},"model_context_window":200000}}}
    """
    try appendString(update, to: logURL)
    sessions = collector.collect(limit: 3, showProjectNames: true, now: now.addingTimeInterval(21))
    try expectEqual(sessions[0].contextTokens, 51_000)

    try appendString("\n", to: logURL)
    sessions = collector.collect(limit: 3, showProjectNames: false, now: now.addingTimeInterval(22))
    try expectEqual(sessions[0].contextTokens, 102_000)
    try expectEqual(sessions[0].contextPercent, 51)
    try expectEqual(sessions[0].projectName, "SESSION 1")

    let secondLogURL = directory.appendingPathComponent("rollout-second.jsonl")
    let secondSessionTimestamp = iso8601Timestamp(now.addingTimeInterval(-60))
    try writeString(
        """
        {"timestamp":"\(secondSessionTimestamp)","type":"session_meta","payload":{"id":"session-2","cwd":"/tmp/SecondProject"}}
        {"timestamp":"\(secondSessionTimestamp)","type":"turn_context","payload":{"model":"gpt-5.5-codex","cwd":"/tmp/SecondProject"}}
        {"timestamp":"\(secondSessionTimestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":300000},"last_token_usage":{"input_tokens":20000,"cached_input_tokens":10000,"output_tokens":1000,"reasoning_output_tokens":100,"total_tokens":21000},"model_context_window":200000}}}

        """,
        to: secondLogURL
    )
    let staleLogURL = directory.appendingPathComponent("rollout-stale.jsonl")
    let staleTimestamp = iso8601Timestamp(now.addingTimeInterval(-90_000))
    try writeString(
        """
        {"timestamp":"\(staleTimestamp)","type":"session_meta","payload":{"id":"session-stale","cwd":"/tmp/StaleProject"}}
        {"timestamp":"\(staleTimestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1000},"last_token_usage":{"total_tokens":1000},"model_context_window":200000}}}

        """,
        to: staleLogURL
    )

    sessions = collector.collect(limit: 3, showProjectNames: true, now: now.addingTimeInterval(23))
    try expectEqual(sessions.map(\.id), ["session-1", "session-2"])
    try expect(!sessions.contains(where: { $0.id == "session-stale" }), "sessions older than 24 hours must be hidden")

    let rotatedTimestamp = iso8601Timestamp(now.addingTimeInterval(30))
    try writeString(
        """
        {"timestamp":"\(rotatedTimestamp)","type":"session_meta","payload":{"id":"session-rotated","cwd":"/tmp/Rotated"}}
        {"timestamp":"\(rotatedTimestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":4000},"last_token_usage":{"total_tokens":2000},"model_context_window":100000}}}

        """,
        to: logURL
    )
    sessions = collector.collect(limit: 3, showProjectNames: true, now: now.addingTimeInterval(31))
    try expectEqual(sessions.first?.id, "session-rotated")
    try expectEqual(sessions.first?.contextPercent, 2)
}

private func testCodexAppServerOutOfOrderResponses() async throws {
    let script = try makeExecutableScript(
        "codex-app-server-out-of-order",
        body: """
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*([0-9]+).*/\\1/')
          method=$(printf '%s' "$line" | sed -E 's/.*"method"[[:space:]]*:[[:space:]]*"([^"]+)".*/\\1/')
          case "$method" in
            initialize)
              printf '{"id":%s,"result":{"userAgent":"mock","codexHome":"/tmp","platformFamily":"unix","platformOs":"macos"}}\\n' "$id"
              ;;
            account/usage/read)
              (sleep 0.15; printf '{"id":%s,"result":{"summary":{"lifetimeTokens":1234,"peakDailyTokens":500,"longestRunningTurnSec":60,"currentStreakDays":2,"longestStreakDays":4},"dailyUsageBuckets":[{"startDate":"2026-07-13","tokens":300}]}}\\n' "$id") &
              ;;
            account/rateLimits/read)
              printf '{"id":%s,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1783900000},"secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":1784000000},"credits":{"hasCredits":true,"unlimited":false,"balance":"10"},"planType":"plus"}}}\\n' "$id"
              ;;
          esac
        done
        wait
        """
    )
    let client = CodexAppServerClient(executableURL: script, requestTimeoutSeconds: 2)
    try await client.start()
    async let accountRequest = client.fetchUsage()
    async let limitsRequest = client.fetchRateLimits()
    let (account, limits) = try await (accountRequest, limitsRequest)
    await client.stop()

    try expectEqual(account.lifetimeTokens, 1_234)
    try expectEqual(account.dailyUsage.first?.tokens, 300)
    try expectEqual(limits.planType, "plus")
    try expectEqual(limits.primary?.usedPercent, 25)
    try expectEqual(limits.secondary?.durationMinutes, 10_080)
}

private func testCodexAppServerInitializationTimeoutIsIndependent() async throws {
    let script = try makeExecutableScript(
        "codex-app-server-slow-initialize",
        body: """
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*([0-9]+).*/\\1/')
          method=$(printf '%s' "$line" | sed -E 's/.*"method"[[:space:]]*:[[:space:]]*"([^"]+)".*/\\1/')
          case "$method" in
            initialize)
              sleep 0.25
              printf '{"id":%s,"result":{"userAgent":"mock","codexHome":"/tmp","platformFamily":"unix","platformOs":"macos"}}\n' "$id"
              ;;
            account/usage/read)
              printf '{"id":%s,"result":{"summary":{"lifetimeTokens":1,"peakDailyTokens":1,"longestRunningTurnSec":1,"currentStreakDays":1,"longestStreakDays":1},"dailyUsageBuckets":[]}}\n' "$id"
              ;;
          esac
        done
        """
    )
    let client = CodexAppServerClient(
        executableURL: script,
        requestTimeoutSeconds: 0.1,
        initializationTimeoutSeconds: 5
    )

    try await client.start()
    let usage = try await client.fetchUsage()
    try expectEqual(usage.lifetimeTokens, 1)
    await client.stop()
}

private func testCodexAppServerUnlimitedAndAuthFailure() async throws {
    let script = try makeExecutableScript(
        "codex-app-server-auth",
        body: """
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*([0-9]+).*/\\1/')
          method=$(printf '%s' "$line" | sed -E 's/.*"method"[[:space:]]*:[[:space:]]*"([^"]+)".*/\\1/')
          case "$method" in
            initialize)
              printf '{"id":%s,"result":{"userAgent":"mock","codexHome":"/tmp","platformFamily":"unix","platformOs":"macos"}}\\n' "$id"
              ;;
            account/rateLimits/read)
              printf '{"id":%s,"result":{"rateLimits":{"credits":{"hasCredits":true,"unlimited":true,"balance":null},"planType":"pro"}}}\\n' "$id"
              ;;
            account/usage/read)
              printf '{"id":%s,"error":{"code":-32000,"message":"Not logged in"}}\\n' "$id"
              ;;
          esac
        done
        """
    )
    let client = CodexAppServerClient(executableURL: script, requestTimeoutSeconds: 2)
    try await client.start()
    let limits = try await client.fetchRateLimits()
    try expectEqual(limits.isUnlimited, true)
    try expectEqual(limits.planType, "pro")

    do {
        _ = try await client.fetchUsage()
        try expect(false, "authentication failure should be surfaced")
    } catch let error as CodexAppServerError {
        try expectEqual(error.errorDescription, "Not logged in")
    }
    await client.stop()
}

@MainActor
private func testCodexUsageServiceCachesAndStops() async throws {
    let directory = try makeTestDirectory("codex-usage-service")
    let cacheURL = directory.appendingPathComponent("codex-usage-cache.json")
    let client = MockCodexAccountClient(
        account: makeCodexAccountUsage(endingAt: Date()),
        rateLimits: CodexRateLimits(
            planType: "pro",
            isUnlimited: true,
            hasCredits: true,
            creditBalance: nil,
            primary: nil,
            secondary: nil
        )
    )
    let service = CodexUsageService(
        cacheURL: cacheURL,
        makeClient: { _ in client },
        resolveExecutable: { _, _ in URL(fileURLWithPath: "/tmp/mock-codex") }
    )
    var config = CodexAgentConfig.default
    config.codexHomePath = directory.path
    let runConfig = config
    var updates: [CodexUsageSnapshot] = []
    let runTask = Task {
        await service.run(config: runConfig) { snapshot in
            updates.append(snapshot)
        }
    }

    for _ in 0..<50 where !updates.contains(where: { $0.status == .live }) {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    try expect(updates.contains(where: { $0.status == .live }), "service should publish live account usage")
    await service.stop()
    runTask.cancel()
    await runTask.value

    let counts = await client.callCounts()
    try expectEqual(counts.starts, 1)
    try expectEqual(counts.usage, 1)
    try expectEqual(counts.rateLimits, 1)
    try expect(counts.stops >= 1, "stopping the service must stop its app-server client")

    let cachedObject = try jsonObject(at: cacheURL)
    try expectEqual(cachedObject.keys.sorted(), ["account", "rateLimits", "updatedAt"])
    try expect(cachedObject["sessions"] == nil, "session metadata must never be cached")

    let fallbackService = CodexUsageService(
        cacheURL: cacheURL,
        resolveExecutable: { _, _ in nil }
    )
    var fallbackSnapshot: CodexUsageSnapshot?
    let fallbackTask = Task {
        await fallbackService.run(config: config) { snapshot in
            fallbackSnapshot = snapshot
        }
    }
    for _ in 0..<50 where fallbackSnapshot == nil {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    try expectEqual(fallbackSnapshot?.status, .cached)
    try expectEqual(fallbackSnapshot?.message, "Codex CLI not found")
    try expectEqual(fallbackSnapshot?.sessions, [])
    await fallbackService.stop()
    fallbackTask.cancel()
    await fallbackTask.value

    var disabledConfig = config
    disabledConfig.enabled = false
    var disabledSnapshot: CodexUsageSnapshot?
    await fallbackService.run(config: disabledConfig) { snapshot in
        disabledSnapshot = snapshot
    }
    try expectEqual(disabledSnapshot?.status, .disabled)

    let slowClient = MockCodexAccountClient(
        account: makeCodexAccountUsage(endingAt: Date()),
        rateLimits: CodexRateLimits(planType: nil, isUnlimited: false, hasCredits: false, creditBalance: nil, primary: nil, secondary: nil),
        startDelayNanoseconds: 5_000_000_000
    )
    let slowService = CodexUsageService(
        cacheURL: directory.appendingPathComponent("slow-cache.json"),
        makeClient: { _ in slowClient },
        resolveExecutable: { _, _ in URL(fileURLWithPath: "/tmp/mock-codex") }
    )
    let slowTask = Task {
        await slowService.run(config: runConfig) { _ in }
    }
    for _ in 0..<50 {
        let counts = await slowClient.callCounts()
        if counts.starts > 0 { break }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    await slowService.stop()
    slowTask.cancel()
    await slowTask.value
    let slowCounts = await slowClient.callCounts()
    try expect(slowCounts.stops >= 1, "stopping during handshake must terminate the client")
}

@MainActor
private func testHidingAgentsPageStopsCodexService() async throws {
    let directory = try makeTestDirectory("codex-dashboard-stop")
    let store = ConfigStore(configDirectoryURL: directory)
    let client = MockCodexAccountClient(
        account: makeCodexAccountUsage(endingAt: Date()),
        rateLimits: CodexRateLimits(planType: nil, isUnlimited: false, hasCredits: false, creditBalance: nil, primary: nil, secondary: nil),
        startDelayNanoseconds: 5_000_000_000
    )
    let service = CodexUsageService(
        cacheURL: store.codexUsageCacheURL,
        makeClient: { _ in client },
        resolveExecutable: { _, _ in URL(fileURLWithPath: "/tmp/mock-codex") }
    )
    var config = AppConfig.default
    config.pages.enabled = [.clock, .agents]
    config.market.enabled = false
    config.agents.codex.codexHomePath = directory.path
    let model = DashboardModel(
        config: config,
        configStore: store,
        displayManager: DisplayManager(),
        codexUsageServiceFactory: { service }
    )
    model.start()

    for _ in 0..<50 {
        let counts = await client.callCounts()
        if counts.starts > 0 { break }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    model.setPage(.agents, enabled: false)
    for _ in 0..<50 {
        let counts = await client.callCounts()
        if counts.stops > 0 { break }
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    let counts = await client.callCounts()
    try expect(counts.stops >= 1, "hiding Agents must stop the active Codex client")
    try expectEqual(model.codexUsage.status, .disabled)
    model.stop()
}

private func testCodexAppServerTimeoutAndExit() async throws {
    let timeoutScript = try makeExecutableScript(
        "codex-app-server-timeout",
        body: """
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*([0-9]+).*/\\1/')
          method=$(printf '%s' "$line" | sed -E 's/.*"method"[[:space:]]*:[[:space:]]*"([^"]+)".*/\\1/')
          case "$method" in
            initialize)
              printf '{"id":%s,"result":{"userAgent":"mock","codexHome":"/tmp","platformFamily":"unix","platformOs":"macos"}}\\n' "$id"
              ;;
          esac
        done
        """
    )
    let timeoutClient = CodexAppServerClient(executableURL: timeoutScript, requestTimeoutSeconds: 2)
    try await timeoutClient.start()
    do {
        _ = try await timeoutClient.fetchUsage()
        try expect(false, "ignored request should time out")
    } catch let error as CodexAppServerError {
        try expectEqual(error.errorDescription, CodexAppServerError.timedOut("account/usage/read").errorDescription)
    }
    await timeoutClient.stop()

    let exitScript = try makeExecutableScript(
        "codex-app-server-exit",
        body: """
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*([0-9]+).*/\\1/')
          method=$(printf '%s' "$line" | sed -E 's/.*"method"[[:space:]]*:[[:space:]]*"([^"]+)".*/\\1/')
          case "$method" in
            initialize)
              printf '{"id":%s,"result":{"userAgent":"mock","codexHome":"/tmp","platformFamily":"unix","platformOs":"macos"}}\\n' "$id"
              ;;
            account/usage/read) exit 7 ;;
          esac
        done
        """
    )
    let exitClient = CodexAppServerClient(executableURL: exitScript, requestTimeoutSeconds: 1)
    try await exitClient.start()
    do {
        _ = try await exitClient.fetchUsage()
        try expect(false, "exited process should fail pending request")
    } catch {
        try expect(error.localizedDescription.contains("status 7"), "process exit status should be reported")
    }
    await exitClient.stop()
}

private func testCodexAppServerReaderShutdown() async throws {
    let script = try makeExecutableScript(
        "mock-codex-reader-shutdown",
        body: """
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id"[[:space:]]*:[[:space:]]*([0-9]+).*/\\1/')
          method=$(printf '%s' "$line" | sed -E 's/.*"method"[[:space:]]*:[[:space:]]*"([^"]+)".*/\\1/')
          if [ "$method" = "initialize" ]; then
            printf '{"id":%s,"result":{"userAgent":"mock","codexHome":"/tmp","platformFamily":"unix","platformOs":"macos"}}\\n' "$id"
          fi
        done
        """
    )

    for _ in 0..<8 {
        let client = CodexAppServerClient(executableURL: script, requestTimeoutSeconds: 3)
        try await client.start()
        await client.stop()
    }
}

private func testMouseClickShieldOwnership() throws {
    var state = MouseClickShieldState()

    try expectEqual(state.shouldSwallow(eventType: .leftMouseDown, isInside: false), false)
    try expectEqual(state.shouldSwallow(eventType: .leftMouseDragged, isInside: true), false)
    try expectEqual(state.shouldSwallow(eventType: .leftMouseUp, isInside: true), false)

    try expectEqual(state.shouldSwallow(eventType: .leftMouseDown, isInside: true), true)
    try expectEqual(state.shouldSwallow(eventType: .leftMouseDragged, isInside: false), true)
    try expectEqual(state.shouldSwallow(eventType: .leftMouseUp, isInside: false), true)
    try expectEqual(state.shouldSwallow(eventType: .leftMouseUp, isInside: true), false)

    try expectEqual(state.shouldSwallow(eventType: .rightMouseDown, isInside: true), true)
    try expectEqual(state.shouldSwallow(eventType: .rightMouseDragged, isInside: false), true)
    try expectEqual(state.shouldSwallow(eventType: .rightMouseUp, isInside: false), true)

    _ = state.shouldSwallow(eventType: .leftMouseDown, isInside: true)
    _ = state.shouldSwallow(eventType: .rightMouseDown, isInside: true)
    state.reset()
    try expectEqual(state.shouldSwallow(eventType: .leftMouseUp, isInside: true), false)
    try expectEqual(state.shouldSwallow(eventType: .rightMouseUp, isInside: true), false)
}

private func testWindowLifecycleDefersWhileSessionInactive() throws {
    var state = DashboardWindowLifecycleState()

    try expectEqual(state.handle(.repositionRequested), [.repositionAndShow])
    try expectEqual(state.handle(.sessionResigned), [.hide])
    try expectEqual(state.handle(.repositionRequested), [])
    try expectEqual(state.handle(.repositionRequested), [])
    try expect(state.hasPendingReposition, "inactive screen changes should remain pending")
    try expect(!state.canPresentWindow, "inactive session must block presentation")

    try expectEqual(state.handle(.sessionBecameActive), [.repositionAndShow])
    try expectEqual(state.handle(.sessionBecameActive), [])
    try expect(!state.hasPendingReposition, "restoring should consume the pending reposition")
}

private func testWindowLifecycleWakeAndUnlockOrdering() throws {
    var wakeFirst = DashboardWindowLifecycleState()
    try expectEqual(wakeFirst.handle(.repositionRequested), [.repositionAndShow])
    try expectEqual(wakeFirst.handle(.sessionResigned), [.hide])
    try expectEqual(wakeFirst.handle(.screensSlept), [])
    try expectEqual(wakeFirst.handle(.screensWoke), [])
    try expectEqual(wakeFirst.handle(.sessionBecameActive), [.repositionAndShow])
    try expectEqual(wakeFirst.handle(.repositionRequested), [.reposition])

    var unlockFirst = DashboardWindowLifecycleState()
    try expectEqual(unlockFirst.handle(.repositionRequested), [.repositionAndShow])
    try expectEqual(unlockFirst.handle(.screensSlept), [.hide])
    try expectEqual(unlockFirst.handle(.sessionResigned), [])
    try expectEqual(unlockFirst.handle(.sessionBecameActive), [])
    try expectEqual(unlockFirst.handle(.screensWoke), [.repositionAndShow])
    try expectEqual(unlockFirst.handle(.screensWoke), [])
}

private func testWindowLifecycleDefersRetriesWhileScreensSleep() throws {
    var state = DashboardWindowLifecycleState()
    try expectEqual(state.handle(.repositionRequested), [.repositionAndShow])
    try expectEqual(state.handle(.screensSlept), [.hide])

    try expectEqual(state.handle(.repositionRequested), [])
    try expectEqual(state.handle(.repositionRequested), [])
    try expectEqual(state.handle(.repositionRequested), [])
    try expect(state.hasPendingReposition, "display retries should stay pending while screens sleep")

    try expectEqual(state.handle(.screensWoke), [.repositionAndShow])
    try expectEqual(state.handle(.screensWoke), [])
}

private func testWindowLifecycleStartsLocked() throws {
    var state = DashboardWindowLifecycleState(isScreenLocked: true)

    try expect(!state.canPresentWindow, "initial lock state must block presentation")
    try expectEqual(state.handle(.repositionRequested), [])
    try expect(state.hasPendingReposition, "initial reposition should remain pending while locked")

    try expectEqual(state.handle(.screenLockChanged(false)), [.repositionAndShow])
    try expectEqual(state.handle(.screenLockChanged(false)), [])
}

private func testWindowLifecycleWaitsForUnlockAfterWake() throws {
    var state = DashboardWindowLifecycleState()

    try expectEqual(state.handle(.repositionRequested), [.repositionAndShow])
    try expectEqual(state.handle(.screenLockChanged(true)), [.hide])
    try expectEqual(state.handle(.screensSlept), [])
    try expectEqual(state.handle(.screensWoke), [])
    try expectEqual(state.handle(.repositionRequested), [])
    try expect(state.isScreenLocked, "screen wake must not clear the lock state")
    try expect(state.hasPendingReposition, "wake reposition should remain pending until unlock")

    try expectEqual(state.handle(.screenLockChanged(false)), [.repositionAndShow])
    try expectEqual(state.handle(.screenLockChanged(false)), [])
}

private func testWindowLifecycleSeparatesSessionAndScreenLock() throws {
    var state = DashboardWindowLifecycleState()

    try expectEqual(state.handle(.repositionRequested), [.repositionAndShow])
    try expectEqual(state.handle(.screenLockChanged(true)), [.hide])
    try expectEqual(state.handle(.sessionResigned), [])
    try expectEqual(state.handle(.screenLockChanged(false)), [])
    try expect(!state.canPresentWindow, "unlock must not activate a resigned user session")
    try expectEqual(state.handle(.sessionBecameActive), [.repositionAndShow])

    try expectEqual(state.handle(.sessionResigned), [.hide])
    try expectEqual(state.handle(.screenLockChanged(true)), [])
    try expectEqual(state.handle(.sessionBecameActive), [])
    try expect(!state.canPresentWindow, "active session must not override screen lock")
    try expectEqual(state.handle(.screenLockChanged(false)), [.repositionAndShow])
}

private func testScreenLockMonitorStateMapping() throws {
    try expectEqual(ScreenLockMonitor.isLocked(stateValue: 0), false)
    try expectEqual(ScreenLockMonitor.isLocked(stateValue: 1), true)
    try expectEqual(ScreenLockMonitor.isLocked(stateValue: UInt64.max), true)
    try expectEqual(
        ScreenLockMonitor.defaultEdgeNotificationNames,
        ["com.apple.sessionagent.screenIsUnlocked"]
    )
}

private func testScreenLockMonitorRegistration() throws {
    let monitor = ScreenLockMonitor(
        notificationName: "dev.danbao.glancepane.tests.screen-lock.\(UUID().uuidString)",
        edgeNotificationNames: []
    )
    let initialState = try monitor.start { _ in }
    try expectEqual(initialState, false)
    monitor.stop()
    monitor.stop()
}

private func testScreenLockMonitorUnlockEdge() throws {
    let stateName = "dev.danbao.glancepane.tests.screen-lock-state.\(UUID().uuidString)"
    let unlockName = "dev.danbao.glancepane.tests.screen-unlocked.\(UUID().uuidString)"
    let callbackReceived = DispatchSemaphore(value: 0)
    let monitor = ScreenLockMonitor(
        notificationName: stateName,
        edgeNotificationNames: [unlockName],
        callbackQueue: DispatchQueue(label: "dev.danbao.glancepane.tests.screen-lock-callback")
    )

    _ = try monitor.start { isLocked in
        if !isLocked {
            callbackReceived.signal()
        }
    }

    try expectEqual(notify_post(unlockName), UInt32(0))
    try expectEqual(callbackReceived.wait(timeout: .now() + 2), .success)
    monitor.stop()
}

private func testCPUTickDeltaRollover() throws {
    try expectEqual(CPUCollector.tickDelta(current: 25, previous: 10), 15)
    try expectEqual(CPUCollector.tickDelta(current: Int32.min, previous: Int32.max), 1)
    try expectEqual(CPUCollector.tickDelta(current: 0, previous: -1), 1)
}

private func testCPUCoreGrouping() throws {
    let values = (0..<10).map { Double($0) / 10 }
    let grouped = CPUCollector.coreGroups(values: values, performanceCount: 4, efficiencyCount: 6)
    try expectEqual(grouped.performance, Array(values.prefix(4)))
    try expectEqual(grouped.efficiency, Array(values.dropFirst(4)))
    try expectEqual(grouped.unknown, [])

    let unknown = CPUCollector.coreGroups(values: values, performanceCount: 3, efficiencyCount: 3)
    try expectEqual(unknown.performance, [])
    try expectEqual(unknown.efficiency, [])
    try expectEqual(unknown.unknown, values)
}

private func testProcessCPUPercent() throws {
    try expectEqual(ProcessCollector.cpuPercent(current: 2_000_000_000, previous: nil, elapsedSeconds: 1), 0)
    try expectEqual(ProcessCollector.cpuPercent(current: 2_000_000_000, previous: 1_000_000_000, elapsedSeconds: 2), 50)
    try expectEqual(ProcessCollector.cpuPercent(current: 500, previous: 1_000, elapsedSeconds: 1), 0)
}

private func testMetricHistoryGapsAndTrimming() throws {
    let store = MetricHistoryStore()
    var snapshot = SystemSnapshot.empty
    snapshot.cpu = CPUStats(totalUsage: 0.5, userUsage: 0.3, systemUsage: 0.2, idleUsage: 0.5, perCoreUsage: [])
    snapshot.memory.totalBytes = 100
    snapshot.memory.usedBytes = 50
    snapshot.metricStates[.vitals] = .active(at: Date(timeIntervalSince1970: 0))

    let config = HistoryConfig(enabled: true, durationSeconds: 600, sampleIntervalSeconds: 2)
    let first = store.record(snapshot: snapshot, config: config, at: Date(timeIntervalSince1970: 100))
    try expectEqual(first.samples.count, 1)

    let skipped = store.record(snapshot: snapshot, config: config, at: Date(timeIntervalSince1970: 101))
    try expectEqual(skipped.samples.count, 1)

    let afterSleep = store.record(snapshot: snapshot, config: config, at: Date(timeIntervalSince1970: 110))
    try expectEqual(afterSleep.samples.count, 3)
    try expectEqual(afterSleep.samples[1].cpuUser, nil)

    let trimmed = store.record(snapshot: snapshot, config: config, at: Date(timeIntervalSince1970: 711))
    try expect(trimmed.samples.allSatisfy { $0.timestamp >= Date(timeIntervalSince1970: 111) }, "old history should be trimmed")
}

private func testHealthEvaluatorSustainedWarnings() throws {
    let evaluator = HealthEvaluator()
    var snapshot = SystemSnapshot.empty
    snapshot.cpu.totalUsage = 0.95
    snapshot.memory.totalBytes = 100
    snapshot.storage = StorageStats(
        usedBytes: 95,
        totalBytes: 100,
        readBytesPerSecond: 0,
        writeBytesPerSecond: 0
    )
    snapshot.network.isConnected = false
    snapshot.metricStates[.vitals] = .active(at: Date())
    snapshot.metricStates[.storage] = .active(at: Date())
    snapshot.metricStates[.network] = .active(at: Date())
    let thresholds = HealthThresholdsConfig(cpuHighPercent: 85, cpuSustainSeconds: 30, diskFreePercent: 10, networkOfflineSeconds: 15)

    let start = Date(timeIntervalSince1970: 1_000)
    let initial = evaluator.evaluate(snapshot: snapshot, thresholds: thresholds, at: start)
    try expect(initial.issues.contains(where: { $0.id == "storage" }), "disk warning should be immediate")
    try expect(!initial.issues.contains(where: { $0.id == "cpu" }), "cpu warning should wait for sustain time")
    try expect(!initial.issues.contains(where: { $0.id == "network" }), "network warning should wait for sustain time")

    let sustained = evaluator.evaluate(snapshot: snapshot, thresholds: thresholds, at: start.addingTimeInterval(31))
    try expect(sustained.issues.contains(where: { $0.id == "cpu" }), "sustained cpu should warn")
    try expect(sustained.issues.contains(where: { $0.id == "network" }), "sustained offline state should warn")

    let networkEvaluator = HealthEvaluator()
    var networkOnly = SystemSnapshot.empty
    networkOnly.network.isConnected = false
    networkOnly.metricStates[.network] = .active(at: start)
    let networkInitial = networkEvaluator.evaluate(snapshot: networkOnly, thresholds: thresholds, at: start)
    try expectEqual(networkInitial.severity, .normal)
    try expectEqual(networkInitial.checks.first(where: { $0.id == "network" })?.state, .pending)

    let networkWarning = networkEvaluator.evaluate(snapshot: networkOnly, thresholds: thresholds, at: start.addingTimeInterval(16))
    try expectEqual(networkWarning.severity, .warning)
    try expectEqual(networkWarning.checks.first(where: { $0.id == "network" })?.state, .warning)
}

private func testHealthEvaluatorBuildsStatusMatrix() throws {
    let evaluator = HealthEvaluator()
    var snapshot = SystemSnapshot.empty
    snapshot.memory.totalBytes = 100
    snapshot.memory.usedBytes = 50
    snapshot.memory.pressure = .normal
    snapshot.storage = StorageStats(usedBytes: 60, totalBytes: 100, readBytesPerSecond: 0, writeBytesPerSecond: 0)
    snapshot.network.isConnected = true
    snapshot.network.latencyMilliseconds = 18
    snapshot.host.thermalState = .nominal
    let sampledAt = Date(timeIntervalSince1970: 2_000)
    snapshot.metricStates[.vitals] = .active(at: sampledAt)
    snapshot.metricStates[.storage] = .active(at: sampledAt)
    snapshot.metricStates[.network] = .active(at: sampledAt)

    let normal = evaluator.evaluate(snapshot: snapshot, thresholds: .default, at: sampledAt)
    try expectEqual(normal.severity, .normal)
    try expectEqual(normal.checks.map(\.id), ["memory", "storage", "network", "thermal"])
    try expectEqual(normal.checks.first(where: { $0.id == "storage" })?.value, "40% FREE")
    try expectEqual(normal.checks.first(where: { $0.id == "network" })?.value, "18MS")
    try expect(!normal.checks.contains(where: { $0.id == "cpu" }), "normal CPU should stay on the Performance page")

    snapshot.power = PowerStats(
        isAvailable: true,
        source: "Battery Power",
        batteryLevel: 0.72,
        isCharging: false,
        isCharged: false,
        timeRemainingMinutes: 180,
        cycleCount: 480,
        healthPercent: nil,
        adapterWatts: nil,
        hasBattery: true,
        lowPowerModeEnabled: true
    )
    snapshot.metricStates[.power] = .active(at: sampledAt)
    let unknownBattery = evaluator.evaluate(snapshot: snapshot, thresholds: .default, at: sampledAt)
    try expectEqual(unknownBattery.checks.first(where: { $0.id == "battery" })?.state, .unavailable)

    snapshot.host.thermalState = .fair
    snapshot.power.healthPercent = 75
    let warning = evaluator.evaluate(snapshot: snapshot, thresholds: .default, at: sampledAt)
    try expectEqual(warning.severity, .warning)
    try expect(warning.issues.contains(where: { $0.id == "thermal" }), "fair thermal state should be visible")
    try expect(warning.issues.contains(where: { $0.id == "battery" }), "degraded battery health should be visible")
    try expectEqual(warning.checks.first(where: { $0.id == "battery" })?.state, .warning)
}

private func testSMCAdapterDecodesCachesAndReconnects() throws {
    try expectEqual(SMCValueDecoder.decode(SMCEncodedValue(dataType: "sp78", bytes: [45, 128])), 45.5)
    try expectEqual(SMCValueDecoder.decode(SMCEncodedValue(dataType: "fpe2", bytes: [0x1F, 0x40])), 2_000)
    try expectEqual(SMCValueDecoder.decode(SMCEncodedValue(dataType: "ui32", bytes: [0, 0, 1, 0])), 256)
    try expectEqual(SMCValueDecoder.decode(smcFloat(12.5)), 12.5)
    try expectEqual(SMCValueDecoder.decode(SMCEncodedValue(dataType: "nope", bytes: [0, 0])), nil)

    let reader = MockSMCValueReader(
        keys: ["Tp01", "Tp05", "Tg0G", "F0Ac", "PSTR", "TZZZ"],
        values: [
            "Tp01": SMCEncodedValue(dataType: "sp78", bytes: [52, 0]),
            "Tp05": SMCEncodedValue(dataType: "sp78", bytes: [65, 0]),
            "Tg0G": SMCEncodedValue(dataType: "sp78", bytes: [49, 0]),
            "F0Ac": SMCEncodedValue(dataType: "fpe2", bytes: [0x1A, 0x90]),
            "PSTR": smcFloat(12.5)
        ]
    )
    let adapter = SMCSensorAdapter(reader: reader, chipName: "Apple M4")
    let first = adapter.sample()
    try expectEqual(first.cpuTemperatureCelsius, 65)
    try expectEqual(first.gpuTemperatureCelsius, 49)
    try expectEqual(first.fanSpeedRPM, 1_700)
    try expectEqual(first.powerWatts, 12.5)
    try expectEqual(reader.availableKeysCallCount, 1)

    _ = adapter.sample()
    try expectEqual(reader.availableKeysCallCount, 1)
    try expectEqual(reader.reconnectCallCount, 0)

    let reconnectingReader = MockSMCValueReader(keys: ["Tp01"], values: [:])
    reconnectingReader.valuesAfterReconnect = [
        "Tp01": SMCEncodedValue(dataType: "sp78", bytes: [48, 0])
    ]
    let recovered = SMCSensorAdapter(reader: reconnectingReader, chipName: "Apple M4").sample()
    try expectEqual(recovered.cpuTemperatureCelsius, 48)
    try expectEqual(reconnectingReader.reconnectCallCount, 1)
    try expectEqual(reconnectingReader.availableKeysCallCount, 2)

    let m4Reader = MockSMCValueReader(
        keys: ["Tp0e", "Tp0f"],
        values: ["Tp0e": smcFloat(90), "Tp0f": smcFloat(109.5)]
    )
    let m4Sample = SMCSensorAdapter(reader: m4Reader, chipName: "Apple M4").sample()
    try expectEqual(m4Sample.cpuTemperatureCelsius, 90)

    let m2Reader = MockSMCValueReader(
        keys: ["Tp0e", "Tp0f"],
        values: ["Tp0e": smcFloat(90), "Tp0f": smcFloat(109.5)]
    )
    let m2Sample = SMCSensorAdapter(reader: m2Reader, chipName: "Apple M2 Pro").sample()
    try expectEqual(m2Sample.cpuTemperatureCelsius, 109.5)

    try expect(!SMCSensorAdapter.isValidTemperature(5), "implausible temperature should be rejected")
    try expect(!SMCSensorAdapter.isValidTemperature(130), "over-range temperature should be rejected")
    try expect(!SMCSensorAdapter.isValidFanSpeed(30_000), "over-range fan speed should be rejected")
    try expect(!SMCSensorAdapter.isValidPower(0), "zero power should be rejected")
}

private func testThermalSamplingThrottlesAndReconnectsAfterWake() throws {
    var config = AppConfig.default
    config.system.enabledGroups = [.thermals]
    config.system.refreshIntervalsSeconds[.thermals] = 10
    config.system.processes.enabled = false

    let collector = MockThermalCollector()
    let service = SystemMetricsService(thermalCollector: collector)
    let start = Date(timeIntervalSince1970: 1_000)

    _ = service.sample(config: config, at: start)
    _ = service.sample(config: config, at: start.addingTimeInterval(9))
    try expectEqual(collector.sampleCallCount, 1)

    _ = service.sample(config: config, at: start.addingTimeInterval(10))
    try expectEqual(collector.sampleCallCount, 2)

    service.handleSystemWake()
    _ = service.sample(config: config, at: start.addingTimeInterval(11))
    try expectEqual(collector.resetCallCount, 1)
    try expectEqual(collector.sampleCallCount, 3)
}

@MainActor
private func testSettingsAndLoginItemLiveState() async throws {
    let login = MockLoginItemService(status: .disabled)
    var savedConfig: AppConfig?
    let model = SettingsViewModel(
        config: .default,
        displays: [],
        loginStatus: login.status,
        onConfigChange: { savedConfig = $0 },
        onLoginChange: { enabled in try login.setEnabled(enabled) },
        onOpenLoginSettings: {},
        onOpenConfigFolder: {},
        onImportConfig: {},
        onExportConfig: {},
        onResetConfig: {}
    )

    model.binding(\.appearance.theme).wrappedValue = .terminal
    try expectEqual(savedConfig?.appearance.theme, .terminal)
    model.setLaunchAtLogin(true)
    model.updateLoginStatus(login.status)
    try expectEqual(model.loginStatus, .enabled)
    try expectEqual(login.setCalls, [true])
}

@MainActor
private func testLoginItemMigratesLegacyRegistration() throws {
    let watchdog = MockAppService(status: .notRegistered)
    let legacy = MockAppService(status: .enabled)
    let service = LoginItemService(watchdogService: watchdog, legacyMainAppService: legacy)

    try service.prepareForLaunch()

    try expectEqual(watchdog.registerCalls, 1)
    try expectEqual(legacy.unregisterCalls, 1)
    try expectEqual(service.status, .enabled)

    try service.setEnabled(false)
    try expectEqual(watchdog.unregisterCalls, 1)
    try expectEqual(service.status, .disabled)

    let awaitingApproval = MockAppService(
        status: .notRegistered,
        statusAfterRegister: .requiresApproval
    )
    let retainedLegacy = MockAppService(status: .enabled)
    let approvalService = LoginItemService(
        watchdogService: awaitingApproval,
        legacyMainAppService: retainedLegacy
    )
    try approvalService.prepareForLaunch()
    try expectEqual(retainedLegacy.unregisterCalls, 0)
    try expectEqual(approvalService.status, .requiresApproval)
}

private func testRelaunchPolicySuppression() throws {
    let directory = try makeTestDirectory("relaunch-policy")
    let policy = RelaunchPolicy(configDirectoryURL: directory, sessionIdentifier: "session-a")

    try expect(!policy.isSuppressed, "a fresh installation should permit relaunch")
    try policy.suppress()
    try expect(policy.isSuppressed, "an explicit quit should suppress watchdog relaunch")
    let nextLoginPolicy = RelaunchPolicy(configDirectoryURL: directory, sessionIdentifier: "session-b")
    try expect(!nextLoginPolicy.isSuppressed, "quit suppression must not survive a new login session")
    policy.resume()
    try expect(!policy.isSuppressed, "a manual launch should resume watchdog protection")
}

@MainActor
private func testNetworkProbeIsInjectableAndOptional() async throws {
    let directory = try makeTestDirectory("network-probe")
    let store = ConfigStore(configDirectoryURL: directory)
    let probe = MockNetworkProbe(latency: 24)
    var config = AppConfig.default
    config.pages.enabled = [.system]
    config.market.enabled = false
    config.system.networkQuality.enabled = false
    let model = DashboardModel(
        config: config,
        configStore: store,
        displayManager: DisplayManager(),
        networkProbeService: probe
    )

    model.start()
    try await Task.sleep(nanoseconds: 80_000_000)
    let disabledCalls = await probe.callCount
    try expectEqual(disabledCalls, 0)

    config.system.networkQuality.enabled = true
    model.apply(config: config)
    try await Task.sleep(nanoseconds: 120_000_000)
    model.stop()
    let enabledCalls = await probe.callCount
    try expect(enabledCalls >= 1, "enabled network probe should run")
    try expectEqual(model.snapshot.network.latencyMilliseconds, 24)
}

private func testDisabledSystemMetricsClearStaleValues() throws {
    let service = SystemMetricsService()
    var config = AppConfig.default
    let initial = service.sample(config: config, force: true)

    try expectEqual(initial.state(for: .network).availability, .active)
    try expect(initial.storage.totalBytes > 0, "storage should contain a live sample")

    config.system.enabledGroups = [.vitals]
    let disabled = service.sample(config: config, force: true)

    try expectEqual(disabled.state(for: .network), .disabled)
    try expectEqual(disabled.state(for: .storage), .disabled)
    try expectEqual(disabled.state(for: .power), .disabled)
    try expectEqual(disabled.network, .empty)
    try expectEqual(disabled.storage, .empty)
    try expectEqual(disabled.power, .unavailable)
}

private func testStockFetchPreservesPerSymbolCache() async throws {
    let directory = try makeTestDirectory("partial-stock")
    let store = ConfigStore(configDirectoryURL: directory)
    try writeJSON(
        StockSnapshot(
            quotes: [makeQuote(symbol: "MSFT", name: "Microsoft")],
            fetchedAt: Date(timeIntervalSince1970: 100)
        ),
        to: store.stockCacheURL
    )

    let client = MockHTTPClient { request in
        if request.url?.path == "/v7/finance/quote" {
            return try httpResponse(
                for: request,
                json: yahooBatchJSON(symbol: "AAPL", price: 125)
            )
        }
        throw URLError(.cannotConnectToHost)
    }
    let service = StockService(cacheURL: store.stockCacheURL, client: client)
    let result = await service.fetch(symbols: ["AAPL", "MSFT"])

    switch result {
    case .success(let quotes):
        try expectEqual(quotes.map(\.symbol), ["AAPL", "MSFT"])
        try expectEqual(quotes.map(\.isCached), [false, true])
    case .failure(let error):
        throw TestFailure(message: "expected partial success, got \(error)", file: #fileID, line: #line)
    }
}

@MainActor
private func testConfigReloadIgnoresStaleStockResponse() async throws {
    let directory = try makeTestDirectory("stock-cancellation")
    let store = ConfigStore(configDirectoryURL: directory)
    let client = MockHTTPClient { request in
        guard request.url?.path == "/v7/finance/quote" else {
            throw URLError(.cannotConnectToHost)
        }

        let symbol = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "symbols" })?
            .value ?? "UNKNOWN"
        if symbol == "OLD" {
            try await Task.sleep(nanoseconds: 350_000_000)
        }
        return try httpResponse(for: request, json: yahooBatchJSON(symbol: symbol, price: symbol == "NEW" ? 200 : 100))
    }

    var config = AppConfig.default
    config.pages.enabled = [.market]
    config.market.symbols = ["OLD"]
    let stockService = StockService(cacheURL: store.stockCacheURL, client: client)
    let model = DashboardModel(
        config: config,
        configStore: store,
        displayManager: DisplayManager(),
        stockService: stockService
    )
    model.start()
    defer { model.stop() }

    try await Task.sleep(nanoseconds: 50_000_000)
    var reloaded = config
    reloaded.market.symbols = ["NEW"]
    model.apply(config: reloaded)

    try await Task.sleep(nanoseconds: 550_000_000)
    try expectEqual(model.quotes.map(\.symbol), ["NEW"])
    try expectEqual(model.stockStatus, .live)
}

@MainActor
private func testDashboardPageSnapshots() async throws {
    _ = NSApplication.shared
    let theme = ScreenTheme(themeName: .midnight)
    let fixedDate = Date(timeIntervalSince1970: 1_783_635_600)

    try await renderSnapshot(
        ClockPageView(date: fixedDate, theme: theme, scale: 1),
        named: "clock",
        pagePadding: 0
    )

    var system = SystemSnapshot.empty
    system.cpu = CPUStats(
        totalUsage: 0.42,
        userUsage: 0.25,
        systemUsage: 0.17,
        idleUsage: 0.58,
        perCoreUsage: [0.72, 0.66, 0.54, 0.81, 0.25, 0.32, 0.18, 0.42, 0.36, 0.29],
        performanceCoreUsage: [0.72, 0.66, 0.54, 0.81],
        efficiencyCoreUsage: [0.25, 0.32, 0.18, 0.42, 0.36, 0.29],
        unknownCoreUsage: []
    )
    system.gpu = GPUStats(
        isAvailable: true,
        model: "Apple M4",
        usage: 0.51,
        memoryBytes: 1_637_564_416,
        temperatureCelsius: nil,
        frequencyMHz: nil
    )
    system.memory = MemoryStats(
        totalBytes: 24_000_000_000,
        usedBytes: 16_000_000_000,
        freeBytes: 8_000_000_000,
        activeBytes: 8_000_000_000,
        inactiveBytes: 2_000_000_000,
        wiredBytes: 4_000_000_000,
        compressedBytes: 2_000_000_000,
        swapUsedBytes: 500_000_000,
        swapTotalBytes: 2_000_000_000,
        pressure: .normal
    )
    system.network = NetworkStats(
        primaryInterface: "en0",
        privateIPAddress: "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
        ssid: "GlancePane Studio Network With A Long Name",
        isConnected: true,
        downBytesPerSecond: 4_000_000,
        upBytesPerSecond: 700_000,
        interfaceKind: "WI-FI",
        wifiRSSI: -48,
        transmitRateMbps: 866,
        latencyMilliseconds: 18
    )
    system.storage = StorageStats(usedBytes: 300_000_000_000, totalBytes: 500_000_000_000, readBytesPerSecond: 8_000_000, writeBytesPerSecond: 2_000_000)
    system.host = HostStats(loadAverage1Minute: 1.2, loadAverage5Minutes: 1.0, loadAverage15Minutes: 0.8, uptimeSeconds: 90_000)
    system.power = PowerStats(
        isAvailable: true,
        source: "AC Power",
        batteryLevel: nil,
        isCharging: false,
        isCharged: false,
        timeRemainingMinutes: nil,
        cycleCount: nil,
        healthPercent: nil,
        adapterWatts: nil,
        hasBattery: false,
        lowPowerModeEnabled: false
    )
    system.thermal = ThermalStats(
        isEnabled: true,
        cpuTemperatureCelsius: 54,
        gpuTemperatureCelsius: 49,
        socTemperatureCelsius: 51,
        gpuUsage: nil,
        gpuFrequencyMHz: nil,
        fanSpeedRPM: 1_720,
        powerWatts: 12.4
    )
    let sampledAt = Date()
    system.metricStates[.vitals] = .active(at: sampledAt)
    system.metricStates[.network] = .active(at: sampledAt)
    system.metricStates[.storage] = .active(at: sampledAt)
    system.metricStates[.gpu] = .active(at: sampledAt)
    system.metricStates[.power] = .active(at: sampledAt)
    system.metricStates[.thermals] = .active(at: sampledAt)
    system.processes = [
        ProcessStats(pid: 10, name: "com.apple.WebKit.GPU-and-Networking-Process-With-A-Long-Name", cpuPercent: 31, memoryBytes: 780_000_000),
        ProcessStats(pid: 11, name: "Safari Networking", cpuPercent: 18, memoryBytes: 1_240_000_000),
        ProcessStats(pid: 12, name: "GlancePane", cpuPercent: 5, memoryBytes: 110_000_000),
        ProcessStats(pid: 13, name: "kernel_task", cpuPercent: 4, memoryBytes: 420_000_000),
        ProcessStats(pid: 14, name: "Finder", cpuPercent: 2, memoryBytes: 180_000_000)
    ]
    system.health = HealthEvaluator().evaluate(snapshot: system, thresholds: .default, at: sampledAt)
    let systemHistory = makeSystemHistory(endingAt: fixedDate)
    try await renderSnapshot(
        SystemPageView(snapshot: system, history: systemHistory, units: .default, theme: theme, scale: 1),
        named: "system-no-battery"
    )

    var unavailableSensors = system
    unavailableSensors.thermal = .unavailable
    unavailableSensors.metricStates[.thermals] = .unavailable
    unavailableSensors.health = HealthEvaluator().evaluate(snapshot: unavailableSensors, thresholds: .default, at: sampledAt)
    try await renderSnapshot(
        SystemPageView(snapshot: unavailableSensors, history: systemHistory, units: .default, theme: theme, scale: 1),
        named: "system-sensors-unavailable"
    )

    var batterySystem = system
    batterySystem.power = PowerStats(
        isAvailable: true,
        source: "AC Power",
        batteryLevel: 0.82,
        isCharging: true,
        isCharged: false,
        timeRemainingMinutes: 45,
        cycleCount: 120,
        healthPercent: 94,
        adapterWatts: 67,
        hasBattery: true,
        lowPowerModeEnabled: false
    )
    batterySystem.metricStates[.power] = .active(at: sampledAt)
    batterySystem.health = HealthEvaluator().evaluate(snapshot: batterySystem, thresholds: .default, at: sampledAt)
    try await renderSnapshot(
        SystemPageView(snapshot: batterySystem, history: systemHistory, units: .default, theme: theme, scale: 1),
        named: "system-battery"
    )

    var warningSystem = system
    warningSystem.memory.pressure = .critical
    warningSystem.storage.usedBytes = 485_000_000_000
    warningSystem.host.thermalState = .serious
    warningSystem.health = HealthEvaluator().evaluate(snapshot: warningSystem, thresholds: .default, at: sampledAt)
    try await renderSnapshot(
        SystemPageView(snapshot: warningSystem, history: systemHistory, units: .default, theme: theme, scale: 1),
        named: "system-health-warning"
    )

    try await renderSnapshot(
        PerformancePageView(snapshot: system, history: systemHistory, units: .default, theme: theme, scale: 1),
        named: "performance-m4"
    )

    var unavailableGPU = system
    unavailableGPU.gpu = .unavailable
    unavailableGPU.metricStates[.gpu] = .unavailable
    try await renderSnapshot(
        PerformancePageView(snapshot: unavailableGPU, history: systemHistory, units: .default, theme: theme, scale: 1),
        named: "performance-gpu-unavailable"
    )

    let codexAccount = makeCodexAccountUsage(endingAt: sampledAt)
    let codexSessions = [
        makeCodexSession(id: "current", project: "Session 1", model: "gpt-5.6-codex-extra-long-model-name", contextPercent: 62, updatedAt: sampledAt, isActive: true),
        makeCodexSession(id: "recent-1", project: "Session 2", model: "gpt-5.5-codex", contextPercent: 78, updatedAt: sampledAt.addingTimeInterval(-1_800), isActive: false),
        makeCodexSession(id: "recent-2", project: "Session 3", model: "gpt-5.4", contextPercent: 31, updatedAt: sampledAt.addingTimeInterval(-7_200), isActive: false)
    ]
    let unlimitedCodex = CodexUsageSnapshot(
        account: codexAccount,
        rateLimits: CodexRateLimits(planType: "pro", isUnlimited: true, hasCredits: true, creditBalance: nil, primary: nil, secondary: nil),
        sessions: codexSessions,
        status: .live,
        message: nil,
        updatedAt: sampledAt
    )
    try await renderSnapshot(
        AgentsPageView(snapshot: unlimitedCodex, theme: theme, scale: 1),
        named: "agents-unlimited"
    )

    var limitedCodex = unlimitedCodex
    limitedCodex.rateLimits = CodexRateLimits(
        planType: "plus",
        isUnlimited: false,
        hasCredits: false,
        creditBalance: nil,
        primary: CodexRateLimitWindow(usedPercent: 72, durationMinutes: 300, resetsAt: sampledAt.addingTimeInterval(5_400)),
        secondary: CodexRateLimitWindow(usedPercent: 88, durationMinutes: 10_080, resetsAt: sampledAt.addingTimeInterval(172_800))
    )
    limitedCodex.sessions[0] = makeCodexSession(id: "current", project: "Session 1", model: "gpt-5.6", contextPercent: 91, updatedAt: sampledAt, isActive: true)
    try await renderSnapshot(
        AgentsPageView(snapshot: limitedCodex, theme: theme, scale: 1),
        named: "agents-limited"
    )

    var noSessionCodex = unlimitedCodex
    noSessionCodex.sessions = []
    try await renderSnapshot(
        AgentsPageView(snapshot: noSessionCodex, theme: theme, scale: 1),
        named: "agents-no-session"
    )

    var cachedCodex = unlimitedCodex
    cachedCodex.status = .cached
    cachedCodex.message = "Codex app-server is reconnecting"
    cachedCodex.sessions = Array(codexSessions.prefix(1))
    try await renderSnapshot(
        AgentsPageView(snapshot: cachedCodex, theme: theme, scale: 1),
        named: "agents-cached"
    )

    try await renderSnapshot(
        AgentsPageView(
            snapshot: CodexUsageSnapshot(account: nil, rateLimits: nil, sessions: [], status: .setup, message: "Codex CLI not found", updatedAt: nil),
            theme: theme,
            scale: 1
        ),
        named: "agents-cli-missing"
    )

    var quotes: [StockQuote] = []
    for index in 0..<12 {
        let symbol = index == 0 ? "BRK-B" : "SYM\(index)"
        let name = index == 0
            ? "International Business Machines and Holdings Incorporated"
            : "Example Company \(index)"
        let price = index == 0 ? 1_234_567.0 : 10_000.0 + Double(index)
        let isUp = index.isMultiple(of: 2)
        quotes.append(
            StockQuote(
                symbol: symbol,
                name: name,
                price: price,
                change: isUp ? 12 : -8,
                changePercent: isUp ? 1.2 : -0.8,
                currency: "USD",
                marketState: "REGULAR",
                updatedAt: fixedDate,
                isCached: index == 7
            )
        )
    }
    try await renderSnapshot(
        MarketPageView(quotes: quotes, configuredSymbolCount: 12, status: .partial, theme: theme, scale: 1),
        named: "market-12-symbols"
    )
    try await renderSnapshot(
        MarketPageView(quotes: Array(quotes.prefix(8)), configuredSymbolCount: 8, status: .live, theme: theme, scale: 1),
        named: "market-8-symbols"
    )

    try await renderSnapshot(
        WeatherPageView(snapshot: makeDryWeatherSnapshot(), status: .live, config: .default, theme: theme, scale: 1),
        named: "weather-dry"
    )
    try await renderSnapshot(
        WeatherPageView(snapshot: makeWeatherSnapshot(), status: .partial, config: .default, theme: theme, scale: 1),
        named: "weather-rain"
    )
    try await renderSnapshot(
        WeatherPageView(snapshot: .empty, status: .setup, config: .default, theme: theme, scale: 1),
        named: "weather-setup"
    )

    for themeName in [ThemeName.graphite, .terminal] {
        let variant = ScreenTheme(themeName: themeName)
        let suffix = themeName.rawValue
        try await renderSnapshot(
            SystemPageView(snapshot: system, history: systemHistory, units: .default, theme: variant, scale: 1),
            named: "system-\(suffix)"
        )
        try await renderSnapshot(
            PerformancePageView(snapshot: system, history: systemHistory, units: .default, theme: variant, scale: 1),
            named: "performance-\(suffix)"
        )
        try await renderSnapshot(
            AgentsPageView(snapshot: unlimitedCodex, theme: variant, scale: 1),
            named: "agents-\(suffix)"
        )
        try await renderSnapshot(
            MarketPageView(quotes: quotes, configuredSymbolCount: 12, status: .partial, theme: variant, scale: 1),
            named: "market-\(suffix)"
        )
        try await renderSnapshot(
            WeatherPageView(snapshot: makeWeatherSnapshot(), status: .partial, config: .default, theme: variant, scale: 1),
            named: "weather-\(suffix)"
        )
    }

    try await renderSnapshot(
        SystemPageView(snapshot: system, history: systemHistory, units: .default, theme: theme, scale: 1)
            .offset(x: 10, y: -10),
        named: "system-pixel-shift"
    )
}

@MainActor
private func renderSnapshot<V: View>(
    _ view: V,
    named name: String,
    pagePadding: CGFloat = DashboardLayout.pagePadding
) async throws {
    let size = NSSize(width: 1280, height: 720)
    let renderer = ImageRenderer(
        content: ZStack {
            Color.black
            view.padding(pagePadding)
        }
        .frame(width: size.width, height: size.height)
    )
    renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
    renderer.scale = 1

    guard let image = renderer.nsImage,
          let tiffData = image.tiffRepresentation,
          let representation = NSBitmapImageRep(data: tiffData)
    else {
        throw TestFailure(message: "could not render \(name) snapshot", file: #fileID, line: #line)
    }
    representation.size = size

    guard let png = representation.representation(using: .png, properties: [:]) else {
        throw TestFailure(message: "could not encode \(name) snapshot", file: #fileID, line: #line)
    }

    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .appendingPathComponent(".build/tests/snapshots", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try png.write(to: directory.appendingPathComponent("\(name).png"), options: [.atomic])

    try expectEqual(representation.pixelsWide, 1280)
    try expectEqual(representation.pixelsHigh, 720)
    try expect(png.count > 5_000, "\(name) snapshot appears blank")
}

private final class MockHTTPClient: HTTPClient {
    typealias Handler = (URLRequest) async throws -> (Data, URLResponse)

    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await handler(request)
    }
}

@MainActor
private final class MockLoginItemService: LoginItemManaging {
    var status: LoginItemStatus
    var setCalls: [Bool] = []

    init(status: LoginItemStatus) {
        self.status = status
    }

    func prepareForLaunch() throws {}

    func setEnabled(_ enabled: Bool) throws {
        setCalls.append(enabled)
        status = enabled ? .enabled : .disabled
    }

    func openSystemSettings() {}
}

@MainActor
private final class MockAppService: AppServiceControlling {
    var appServiceStatus: AppServiceStatus
    let statusAfterRegister: AppServiceStatus
    var registerCalls = 0
    var unregisterCalls = 0

    init(status: AppServiceStatus, statusAfterRegister: AppServiceStatus = .enabled) {
        appServiceStatus = status
        self.statusAfterRegister = statusAfterRegister
    }

    func registerService() throws {
        registerCalls += 1
        appServiceStatus = statusAfterRegister
    }

    func unregisterService() throws {
        unregisterCalls += 1
        appServiceStatus = .notRegistered
    }
}

private actor MockNetworkProbe: NetworkProbing {
    private var calls = 0
    let latency: Double?

    var callCount: Int { calls }

    init(latency: Double?) {
        self.latency = latency
    }

    func measureLatency(host: String, port: UInt16, timeoutSeconds: TimeInterval) async -> Double? {
        calls += 1
        return latency
    }
}

private actor MockCodexAccountClient: CodexAccountFetching {
    private let account: CodexAccountUsage
    private let rateLimits: CodexRateLimits
    private let startDelayNanoseconds: UInt64
    private var startCalls = 0
    private var usageCalls = 0
    private var rateLimitCalls = 0
    private var stopCalls = 0

    init(
        account: CodexAccountUsage,
        rateLimits: CodexRateLimits,
        startDelayNanoseconds: UInt64 = 0
    ) {
        self.account = account
        self.rateLimits = rateLimits
        self.startDelayNanoseconds = startDelayNanoseconds
    }

    func start() async throws {
        startCalls += 1
        if startDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: startDelayNanoseconds)
        }
    }

    func fetchUsage() async throws -> CodexAccountUsage {
        usageCalls += 1
        return account
    }

    func fetchRateLimits() async throws -> CodexRateLimits {
        rateLimitCalls += 1
        return rateLimits
    }

    func stop() async {
        stopCalls += 1
    }

    func callCounts() -> (starts: Int, usage: Int, rateLimits: Int, stops: Int) {
        (startCalls, usageCalls, rateLimitCalls, stopCalls)
    }
}

private func yahooBatchJSON(symbol: String, price: Double) -> String {
    """
    {
      "quoteResponse": {
        "result": [
          {
            "symbol": "\(symbol)",
            "shortName": "\(symbol) Company",
            "regularMarketPrice": \(price),
            "regularMarketPreviousClose": \(price - 1),
            "currency": "USD",
            "marketState": "REGULAR"
          }
        ]
      }
    }
    """
}

private func httpResponse(for request: URLRequest, json: String) throws -> (Data, URLResponse) {
    guard let url = request.url,
          let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else {
        throw URLError(.badURL)
    }
    return (Data(json.utf8), response)
}

private func makeTestDirectory(_ name: String) throws -> URL {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .appendingPathComponent(".build/tests/tmp", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let directory = root.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func writeString(_ value: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(value.utf8).write(to: url, options: [.atomic])
}

private func appendString(_ value: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(value.utf8))
}

private func iso8601Timestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func makeExecutableScript(_ name: String, body: String) throws -> URL {
    let directory = try makeTestDirectory(name)
    let url = directory.appendingPathComponent("mock-codex")
    try writeString("#!/bin/sh\nset -eu\n\(body)\n", to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url, options: [.atomic])
}

private func jsonObject(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw TestFailure(message: "expected JSON object at \(url.path)", file: #fileID, line: #line)
    }
    return object
}

private func files(in directory: URL, prefix: String) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
        .filter { $0.hasPrefix(prefix) }
        .sorted() ?? []
}

private func posixPermissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let permissions = attributes[.posixPermissions] as? NSNumber else {
        throw TestFailure(
            message: "missing POSIX permissions for \(url.path)",
            file: #fileID,
            line: #line
        )
    }
    return permissions.intValue & 0o777
}

private final class MockSMCValueReader: SMCValueReading {
    var keys: Set<String>
    var values: [String: SMCEncodedValue]
    var valuesAfterReconnect: [String: SMCEncodedValue]?
    private(set) var availableKeysCallCount = 0
    private(set) var reconnectCallCount = 0

    init(keys: Set<String>, values: [String: SMCEncodedValue]) {
        self.keys = keys
        self.values = values
    }

    func availableKeys() -> Set<String> {
        availableKeysCallCount += 1
        return keys
    }

    func readValue(for key: String) -> SMCEncodedValue? {
        values[key]
    }

    func reconnect() {
        reconnectCallCount += 1
        if let valuesAfterReconnect {
            values = valuesAfterReconnect
            self.valuesAfterReconnect = nil
        }
    }
}

private final class MockThermalCollector: ThermalCollecting {
    private(set) var sampleCallCount = 0
    private(set) var resetCallCount = 0

    func sample(enabled: Bool) -> ThermalStats {
        sampleCallCount += 1
        return ThermalStats(
            isEnabled: enabled,
            cpuTemperatureCelsius: 50,
            gpuTemperatureCelsius: nil,
            socTemperatureCelsius: nil,
            gpuUsage: nil,
            gpuFrequencyMHz: nil,
            fanSpeedRPM: nil,
            powerWatts: nil
        )
    }

    func resetConnection() {
        resetCallCount += 1
    }
}

private func smcFloat(_ value: Float) -> SMCEncodedValue {
    let bits = value.bitPattern
    return SMCEncodedValue(
        dataType: "flt ",
        bytes: [
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF)
        ]
    )
}

private func makeQuote(symbol: String, name: String) -> StockQuote {
    StockQuote(
        symbol: symbol,
        name: name,
        price: 100,
        change: 1,
        changePercent: 1,
        currency: "USD",
        marketState: "REGULAR",
        updatedAt: Date(timeIntervalSince1970: 100),
        isCached: false
    )
}

private func makeSystemHistory(endingAt endDate: Date) -> SystemHistory {
    let samples = (0..<120).map { index in
        let phase = Double(index) / 12
        return SystemHistorySample(
            timestamp: endDate.addingTimeInterval(TimeInterval(index - 119) * 5),
            cpuUser: 0.22 + sin(phase) * 0.12,
            cpuSystem: 0.12 + cos(phase * 0.8) * 0.06,
            memoryUsage: 0.62 + sin(phase * 0.25) * 0.04,
            gpuUsage: 0.35 + sin(phase * 1.3) * 0.22,
            networkDownBytesPerSecond: 2_000_000 + max(0, sin(phase)) * 8_000_000,
            networkUpBytesPerSecond: 300_000 + max(0, cos(phase * 0.7)) * 1_200_000,
            storageReadBytesPerSecond: max(0, sin(phase * 1.8)) * 18_000_000,
            storageWriteBytesPerSecond: max(0, cos(phase * 1.1)) * 7_000_000,
            temperatureCelsius: 50 + sin(phase * 0.45) * 5,
            powerWatts: 10 + max(0, sin(phase * 0.6)) * 9
        )
    }
    return SystemHistory(samples: samples, windowSeconds: 600)
}

private func makeCodexAccountUsage(endingAt endDate: Date) -> CodexAccountUsage {
    let calendar = Calendar.current
    let dailyUsage = (0..<14).compactMap { index -> CodexDailyUsage? in
        guard let date = calendar.date(byAdding: .day, value: index - 13, to: endDate) else { return nil }
        let tokens = Int64((index + 2) * (index.isMultiple(of: 3) ? 6_200_000 : 3_100_000))
        return CodexDailyUsage(date: CodexDailyUsage.dateKey(for: date, calendar: calendar), tokens: tokens)
    }
    return CodexAccountUsage(
        lifetimeTokens: 25_300_000_000,
        peakDailyTokens: dailyUsage.map(\.tokens).max(),
        longestRunningTurnSeconds: 4_820,
        currentStreakDays: 17,
        longestStreakDays: 42,
        dailyUsage: dailyUsage
    )
}

private func makeCodexSession(
    id: String,
    project: String,
    model: String,
    contextPercent: Int,
    updatedAt: Date,
    isActive: Bool
) -> CodexSessionUsage {
    let contextWindow: Int64 = 200_000
    let contextTokens = contextWindow * Int64(contextPercent) / 100
    return CodexSessionUsage(
        id: id,
        projectName: project,
        model: model,
        updatedAt: updatedAt,
        contextTokens: contextTokens,
        contextWindow: contextWindow,
        inputTokens: max(0, contextTokens - 4_200),
        cachedInputTokens: max(0, contextTokens * 7 / 10),
        outputTokens: 3_600,
        reasoningOutputTokens: 600,
        sessionTotalTokens: 91_600_000,
        isActive: isActive
    )
}

private func makeWeatherSnapshot() -> WeatherSnapshot {
    let hourly: [HourlyWeather] = (0..<12).map { index in
        let conditions = [("晴", "100"), ("多云", "101"), ("小雨", "305")]
        let condition = conditions[index % conditions.count]
        return HourlyWeather(
            forecastAt: Date(timeIntervalSince1970: 200 + Double(index * 3_600)),
            temperatureCelsius: 29 - Double(index % 4),
            condition: condition.0,
            icon: condition.1,
            precipitationProbabilityPercent: index.isMultiple(of: 3) ? 60 : 15,
            precipitationMillimeters: index.isMultiple(of: 3) ? 0.4 : 0
        )
    }
    let rainStart = Date().addingTimeInterval(600)
    var minutely: [MinutelyPrecipitation] = []
    for index in 0..<24 {
        let forecastAt = rainStart.addingTimeInterval(Double(index * 300))
        let precipitation = index < 2 ? 0.0 : Swift.min(0.1, Double(index - 1) * 0.01)
        minutely.append(
            MinutelyPrecipitation(
                forecastAt: forecastAt,
                precipitationMillimeters: precipitation,
                type: "rain"
            )
        )
    }

    return WeatherSnapshot(
        provider: .qweather,
        locationName: "Sample District",
        locationID: "sample-location",
        longitude: 120,
        latitude: 30,
        current: CurrentWeather(
            observedAt: Date(timeIntervalSince1970: 100),
            temperatureCelsius: 28,
            feelsLikeCelsius: 30,
            condition: "多云",
            icon: "101",
            humidityPercent: 70,
            windDirection: "东风",
            windSpeedKph: 12,
            precipitationMillimeters: 0
        ),
        hourly: hourly,
        minutely: minutely,
        precipitationSummary: "Rain soon",
        attributionURL: "https://www.qweather.com",
        updatedAt: Date(timeIntervalSince1970: 400),
        isCached: false,
        errorMessage: nil
    )
}

private func makeDryWeatherSnapshot() -> WeatherSnapshot {
    let base = makeWeatherSnapshot()
    let start = Date().addingTimeInterval(300)
    let minutely = (0..<24).map { index in
        MinutelyPrecipitation(
            forecastAt: start.addingTimeInterval(TimeInterval(index * 300)),
            precipitationMillimeters: 0,
            type: "rain"
        )
    }

    return WeatherSnapshot(
        provider: base.provider,
        locationName: base.locationName,
        locationID: base.locationID,
        longitude: base.longitude,
        latitude: base.latitude,
        current: base.current,
        hourly: base.hourly,
        minutely: minutely,
        precipitationSummary: "未来两小时无降水",
        attributionURL: base.attributionURL,
        updatedAt: Date(),
        isCached: false,
        errorMessage: nil
    )
}

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: String = #fileID,
    line: Int = #line
) throws {
    if !condition() {
        throw TestFailure(message: message, file: file, line: line)
    }
}

private func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    file: String = #fileID,
    line: Int = #line
) throws {
    if actual != expected {
        throw TestFailure(message: "expected \(expected), got \(actual)", file: file, line: line)
    }
}
