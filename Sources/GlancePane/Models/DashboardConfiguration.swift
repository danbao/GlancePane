import Foundation

struct DisplayConfig: Codable, Equatable {
    var targetName: String

    static let `default` = DisplayConfig(targetName: "")
}
struct AppearanceConfig: Codable, Equatable {
    var theme: ThemeName
    var units: AppearanceUnitsConfig

    private enum CodingKeys: String, CodingKey {
        case theme
        case units
    }

    static let `default` = AppearanceConfig(theme: .midnight, units: .default)

    init(theme: ThemeName, units: AppearanceUnitsConfig = .default) {
        self.theme = theme
        self.units = units
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(ThemeName.self, forKey: .theme) ?? Self.default.theme
        units = try container.decodeIfPresent(AppearanceUnitsConfig.self, forKey: .units) ?? .default
    }
}

struct AppearanceUnitsConfig: Codable, Equatable {
    var temperature: TemperatureUnit
    var dataRate: DataRateUnit

    static let `default` = AppearanceUnitsConfig(temperature: .celsius, dataRate: .bytes)
}

enum TemperatureUnit: String, Codable, CaseIterable, Equatable {
    case celsius
    case fahrenheit
}

enum DataRateUnit: String, Codable, CaseIterable, Equatable {
    case bytes
    case bits
}

struct InteractionConfig: Codable, Equatable {
    var clickNavigationEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case clickNavigationEnabled
        case mousePassthrough
    }

    static let `default` = InteractionConfig(clickNavigationEnabled: true)

    init(clickNavigationEnabled: Bool) {
        self.clickNavigationEnabled = clickNavigationEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let enabled = try container.decodeIfPresent(Bool.self, forKey: .clickNavigationEnabled) {
            clickNavigationEnabled = enabled
            return
        }

        // Older configs only described window passthrough. Click navigation was
        // still active in that implementation, so preserve the effective behavior.
        if container.contains(.mousePassthrough) {
            clickNavigationEnabled = true
            return
        }

        clickNavigationEnabled = Self.default.clickNavigationEnabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clickNavigationEnabled, forKey: .clickNavigationEnabled)
    }
}

struct PagesConfig: Codable, Equatable {
    var order: [DashboardPage]
    var enabled: Set<DashboardPage>
    var rotation: PageRotationConfig

    static let `default` = PagesConfig(
        order: DashboardPage.defaultOrder,
        enabled: Set(DashboardPage.defaultOrder),
        rotation: .default
    )

    func normalized() -> PagesConfig {
        var copy = self
        let previousDefaultPages: Set<DashboardPage> = [.clock, .system, .market, .weather]
        let hadPerformancePage = copy.order.contains(.performance)
        let hadAllPreviousDefaultsEnabled = previousDefaultPages.isSubset(of: copy.enabled)
        let hadEnabledPages = !copy.enabled.isEmpty
        if !hadPerformancePage, let systemIndex = copy.order.firstIndex(of: .system) {
            copy.order.insert(.performance, at: systemIndex + 1)
        }
        if !copy.order.contains(.agents) {
            let insertionIndex = copy.order.firstIndex(of: .performance).map { $0 + 1 } ?? copy.order.count
            copy.order.insert(.agents, at: insertionIndex)
        }
        copy.order = DashboardPage.normalizedOrder(copy.order)
        if !hadPerformancePage && hadEnabledPages && hadAllPreviousDefaultsEnabled {
            copy.enabled.insert(.performance)
        }

        let enabledPagesInOrder = copy.order.filter { copy.enabled.contains($0) }
        copy.enabled = Set(enabledPagesInOrder.isEmpty ? [.clock] : enabledPagesInOrder)
        copy.rotation = copy.rotation.normalized()
        return copy
    }

    func migratingAgents(fromSchemaVersion schemaVersion: Int) -> PagesConfig {
        var copy = self
        let expectedPages: Set<DashboardPage> = schemaVersion < 2
            ? [.clock, .system, .market, .weather]
            : [.clock, .system, .performance, .market, .weather]
        let hadAgentsPage = copy.order.contains(.agents)
        let hadEnabledPages = !copy.enabled.isEmpty
        let hadAllExpectedPagesEnabled = expectedPages.isSubset(of: copy.enabled)

        var seen = Set<DashboardPage>()
        let legacyBaseOrder: [DashboardPage] = [.clock, .system, .market, .weather]
        copy.order = (copy.order.filter { $0 != .agents } + legacyBaseOrder)
            .filter { seen.insert($0).inserted }
        if !copy.order.contains(.performance) {
            let performanceIndex = copy.order.firstIndex(of: .system).map { $0 + 1 } ?? copy.order.count
            copy.order.insert(.performance, at: performanceIndex)
        }
        let insertionIndex = copy.order.firstIndex(of: .performance).map { $0 + 1 } ?? copy.order.count
        copy.order.insert(.agents, at: insertionIndex)
        if !hadAgentsPage && hadEnabledPages && hadAllExpectedPagesEnabled {
            if schemaVersion < 2 {
                copy.enabled.insert(.performance)
            }
            copy.enabled.insert(.agents)
        }
        return copy
    }
}

struct PageRotationConfig: Codable, Equatable {
    var enabled: Bool
    var intervalSeconds: TimeInterval

    static let `default` = PageRotationConfig(enabled: true, intervalSeconds: 30)

    func normalized() -> PageRotationConfig {
        var copy = self
        if !copy.intervalSeconds.isFinite || copy.intervalSeconds < 5 {
            copy.intervalSeconds = Self.default.intervalSeconds
        }
        return copy
    }
}
