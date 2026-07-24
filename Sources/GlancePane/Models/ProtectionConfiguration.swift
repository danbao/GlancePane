import Foundation

enum BurnInProtectionMode: String, Codable, CaseIterable, Equatable {
    case off
    case subtle
    case strong
}
struct ProtectionConfig: Codable, Equatable {
    var mode: BurnInProtectionMode
    var pixelShift: PixelShiftProtectionConfig
    var dim: DimProtectionConfig
    var rest: RestProtectionConfig
    var wakeOnPointer: Bool

    private enum CodingKeys: String, CodingKey {
        case mode
        case pixelShift
        case dim
        case rest
        case wakeOnPointer

        case pixelShiftPixels
        case pixelShiftIntervalSeconds
        case dimAfterSeconds
        case dimOpacity
        case restAfterSeconds
        case restDurationSeconds
    }

    static let `default` = ProtectionConfig(
        mode: .strong,
        pixelShift: .default,
        dim: .default,
        rest: .default,
        wakeOnPointer: true
    )

    init(
        mode: BurnInProtectionMode,
        pixelShift: PixelShiftProtectionConfig,
        dim: DimProtectionConfig,
        rest: RestProtectionConfig,
        wakeOnPointer: Bool
    ) {
        self.mode = mode
        self.pixelShift = pixelShift
        self.dim = dim
        self.rest = rest
        self.wakeOnPointer = wakeOnPointer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ProtectionConfig.default

        mode = try container.decodeIfPresent(BurnInProtectionMode.self, forKey: .mode) ?? defaults.mode
        pixelShift = try container.decodeIfPresent(PixelShiftProtectionConfig.self, forKey: .pixelShift)
            ?? PixelShiftProtectionConfig(
                pixels: try container.decodeIfPresent(Double.self, forKey: .pixelShiftPixels)
                    ?? defaults.pixelShift.pixels,
                intervalSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .pixelShiftIntervalSeconds)
                    ?? defaults.pixelShift.intervalSeconds
            )
        dim = try container.decodeIfPresent(DimProtectionConfig.self, forKey: .dim)
            ?? DimProtectionConfig(
                afterSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .dimAfterSeconds)
                    ?? defaults.dim.afterSeconds,
                opacity: try container.decodeIfPresent(Double.self, forKey: .dimOpacity)
                    ?? defaults.dim.opacity
            )
        rest = try container.decodeIfPresent(RestProtectionConfig.self, forKey: .rest)
            ?? RestProtectionConfig(
                afterSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .restAfterSeconds)
                    ?? defaults.rest.afterSeconds,
                durationSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .restDurationSeconds)
                    ?? defaults.rest.durationSeconds
            )
        wakeOnPointer = try container.decodeIfPresent(Bool.self, forKey: .wakeOnPointer) ?? defaults.wakeOnPointer
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(pixelShift, forKey: .pixelShift)
        try container.encode(dim, forKey: .dim)
        try container.encode(rest, forKey: .rest)
        try container.encode(wakeOnPointer, forKey: .wakeOnPointer)
    }

    func normalized() -> ProtectionConfig {
        var copy = self
        copy.pixelShift = copy.pixelShift.normalized()
        copy.dim = copy.dim.normalized()
        copy.rest = copy.rest.normalized()
        return copy
    }
}

struct PixelShiftProtectionConfig: Codable, Equatable {
    var pixels: Double
    var intervalSeconds: TimeInterval

    static let `default` = PixelShiftProtectionConfig(pixels: 10, intervalSeconds: 60)

    func normalized() -> PixelShiftProtectionConfig {
        var copy = self
        if !copy.pixels.isFinite || copy.pixels < 0 {
            copy.pixels = Self.default.pixels
        }
        if !copy.intervalSeconds.isFinite || copy.intervalSeconds < 1 {
            copy.intervalSeconds = Self.default.intervalSeconds
        }
        return copy
    }
}

struct DimProtectionConfig: Codable, Equatable {
    var afterSeconds: TimeInterval
    var opacity: Double

    static let `default` = DimProtectionConfig(afterSeconds: 600, opacity: 0.45)

    func normalized() -> DimProtectionConfig {
        var copy = self
        if !copy.afterSeconds.isFinite || copy.afterSeconds < 0 {
            copy.afterSeconds = Self.default.afterSeconds
        }
        if !copy.opacity.isFinite {
            copy.opacity = Self.default.opacity
        }
        copy.opacity = min(0.95, max(0, copy.opacity))
        return copy
    }
}

struct RestProtectionConfig: Codable, Equatable {
    var afterSeconds: TimeInterval
    var durationSeconds: TimeInterval

    static let `default` = RestProtectionConfig(afterSeconds: 2700, durationSeconds: 180)

    func normalized() -> RestProtectionConfig {
        var copy = self
        if !copy.afterSeconds.isFinite || copy.afterSeconds < 1 {
            copy.afterSeconds = Self.default.afterSeconds
        }
        if !copy.durationSeconds.isFinite || copy.durationSeconds < 1 {
            copy.durationSeconds = Self.default.durationSeconds
        }
        return copy
    }
}

enum ThemeName: String, Codable, CaseIterable, Equatable {
    case midnight
    case graphite
    case terminal
}

enum SystemMetricGroup: String, Codable, CaseIterable, Hashable {
    case vitals
    case gpu
    case thermals
    case power
    case network
    case storage

    var title: String {
        switch self {
        case .vitals: return "Vitals"
        case .gpu: return "GPU"
        case .thermals: return "Thermals"
        case .power: return "Power"
        case .network: return "Network"
        case .storage: return "Storage"
        }
    }

    static let defaultRefreshIntervals: [SystemMetricGroup: TimeInterval] = [
        .vitals: 2,
        .gpu: 2,
        .storage: 2,
        .network: 2,
        .power: 10,
        .thermals: 10
    ]
}

enum LegacyMetricGroup: String, Codable, Hashable {
    case vitals
    case thermals
    case power
    case network
    case storage
    case market
}
