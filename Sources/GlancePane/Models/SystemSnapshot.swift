import Foundation

struct SystemSnapshot: Equatable {
    var cpu: CPUStats
    var gpu: GPUStats
    var memory: MemoryStats
    var storage: StorageStats
    var network: NetworkStats
    var power: PowerStats
    var thermal: ThermalStats
    var host: HostStats
    var processes: [ProcessStats]
    var health: SystemHealth
    var metricStates: [SystemMetricGroup: SystemMetricState]
    var capturedAt: Date

    static let empty = SystemSnapshot(
        cpu: .empty,
        gpu: .unavailable,
        memory: .empty,
        storage: .empty,
        network: .empty,
        power: .unavailable,
        thermal: .unavailable,
        host: .empty,
        processes: [],
        health: .normal,
        metricStates: Dictionary(
            uniqueKeysWithValues: SystemMetricGroup.allCases.map { ($0, .disabled) }
        ),
        capturedAt: Date()
    )

    func state(for group: SystemMetricGroup) -> SystemMetricState {
        metricStates[group] ?? .disabled
    }
}

enum SystemMetricAvailability: String, Equatable {
    case active
    case disabled
    case unavailable
}

struct SystemMetricState: Equatable {
    var availability: SystemMetricAvailability
    var updatedAt: Date?

    static let disabled = SystemMetricState(availability: .disabled, updatedAt: nil)
    static let unavailable = SystemMetricState(availability: .unavailable, updatedAt: nil)

    static func active(at date: Date) -> SystemMetricState {
        SystemMetricState(availability: .active, updatedAt: date)
    }

    var isActive: Bool {
        availability == .active
    }

    var title: String {
        switch availability {
        case .active: return "LIVE"
        case .disabled: return "DISABLED"
        case .unavailable: return "N/A"
        }
    }
}

struct HostStats: Equatable {
    var loadAverage1Minute: Double
    var loadAverage5Minutes: Double
    var loadAverage15Minutes: Double
    var uptimeSeconds: TimeInterval
    var thermalState: SystemThermalState = .nominal

    static let empty = HostStats(
        loadAverage1Minute: 0,
        loadAverage5Minutes: 0,
        loadAverage15Minutes: 0,
        uptimeSeconds: 0,
        thermalState: .nominal
    )
}

enum SystemThermalState: String, Equatable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

struct CPUStats: Equatable {
    var totalUsage: Double
    var userUsage: Double
    var systemUsage: Double
    var idleUsage: Double
    var perCoreUsage: [Double]
    var performanceCoreUsage: [Double] = []
    var efficiencyCoreUsage: [Double] = []
    var unknownCoreUsage: [Double] = []

    static let empty = CPUStats(
        totalUsage: 0,
        userUsage: 0,
        systemUsage: 0,
        idleUsage: 1,
        perCoreUsage: [],
        performanceCoreUsage: [],
        efficiencyCoreUsage: [],
        unknownCoreUsage: []
    )
}

struct GPUStats: Equatable {
    var isAvailable: Bool
    var model: String?
    var usage: Double?
    var memoryBytes: UInt64?
    var temperatureCelsius: Double?
    var frequencyMHz: Double?

    static let unavailable = GPUStats(
        isAvailable: false,
        model: nil,
        usage: nil,
        memoryBytes: nil,
        temperatureCelsius: nil,
        frequencyMHz: nil
    )
}

struct MemoryStats: Equatable {
    var totalBytes: UInt64
    var usedBytes: UInt64
    var freeBytes: UInt64
    var activeBytes: UInt64
    var inactiveBytes: UInt64
    var wiredBytes: UInt64
    var compressedBytes: UInt64
    var swapUsedBytes: UInt64
    var swapTotalBytes: UInt64
    var pressure: MemoryPressure

    static let empty = MemoryStats(
        totalBytes: 0,
        usedBytes: 0,
        freeBytes: 0,
        activeBytes: 0,
        inactiveBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        swapUsedBytes: 0,
        swapTotalBytes: 0,
        pressure: .normal
    )

    var usage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    var swapUsage: Double {
        guard swapTotalBytes > 0 else { return 0 }
        return Double(swapUsedBytes) / Double(swapTotalBytes)
    }
}

enum MemoryPressure: String, Equatable {
    case normal
    case warning
    case critical
    case unknown
}

struct StorageStats: Equatable {
    var usedBytes: UInt64
    var totalBytes: UInt64
    var readBytesPerSecond: Double
    var writeBytesPerSecond: Double

    static let empty = StorageStats(
        usedBytes: 0,
        totalBytes: 0,
        readBytesPerSecond: 0,
        writeBytesPerSecond: 0
    )

    var usage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}

struct NetworkStats: Equatable {
    var primaryInterface: String?
    var privateIPAddress: String?
    var ssid: String?
    var isConnected: Bool
    var downBytesPerSecond: Double
    var upBytesPerSecond: Double
    var interfaceKind: String? = nil
    var wifiRSSI: Int? = nil
    var transmitRateMbps: Double? = nil
    var latencyMilliseconds: Double? = nil

    static let empty = NetworkStats(
        primaryInterface: nil,
        privateIPAddress: nil,
        ssid: nil,
        isConnected: false,
        downBytesPerSecond: 0,
        upBytesPerSecond: 0,
        interfaceKind: nil,
        wifiRSSI: nil,
        transmitRateMbps: nil,
        latencyMilliseconds: nil
    )
}

struct ProcessStats: Equatable, Identifiable {
    var pid: Int32
    var name: String
    var cpuPercent: Double
    var memoryBytes: UInt64

    var id: Int32 { pid }
}

enum HealthSeverity: Int, Equatable, Comparable {
    case normal = 0
    case warning = 1
    case critical = 2

    static func < (lhs: HealthSeverity, rhs: HealthSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct HealthIssue: Equatable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var severity: HealthSeverity
}

enum HealthCheckState: Equatable {
    case normal
    case pending
    case unavailable
    case warning
    case critical
}

struct HealthCheck: Equatable, Identifiable {
    var id: String
    var title: String
    var value: String
    var symbolName: String
    var state: HealthCheckState
}

struct SystemHealth: Equatable {
    var severity: HealthSeverity
    var issues: [HealthIssue]
    var checks: [HealthCheck] = []

    static let normal = SystemHealth(severity: .normal, issues: [], checks: [])

    var summary: String {
        issues.first?.title ?? "ALL SYSTEMS NORMAL"
    }
}

struct PowerStats: Equatable {
    var isAvailable: Bool
    var source: String
    var batteryLevel: Double?
    var isCharging: Bool
    var isCharged: Bool
    var timeRemainingMinutes: Int?
    var cycleCount: Int?
    var healthPercent: Int?
    var adapterWatts: Int?
    var hasBattery: Bool = false
    var lowPowerModeEnabled: Bool = false

    static let unavailable = PowerStats(
        isAvailable: false,
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
}

struct ThermalStats: Equatable {
    var isEnabled: Bool
    var cpuTemperatureCelsius: Double?
    var gpuTemperatureCelsius: Double?
    var socTemperatureCelsius: Double?
    var gpuUsage: Double?
    var gpuFrequencyMHz: Double?
    var fanSpeedRPM: Double?
    var powerWatts: Double?

    static let unavailable = ThermalStats(
        isEnabled: false,
        cpuTemperatureCelsius: nil,
        gpuTemperatureCelsius: nil,
        socTemperatureCelsius: nil,
        gpuUsage: nil,
        gpuFrequencyMHz: nil,
        fanSpeedRPM: nil,
        powerWatts: nil
    )

    var hasAnyValue: Bool {
        cpuTemperatureCelsius != nil ||
            gpuTemperatureCelsius != nil ||
            socTemperatureCelsius != nil ||
            gpuUsage != nil ||
            gpuFrequencyMHz != nil ||
            fanSpeedRPM != nil ||
            powerWatts != nil
    }

    var primaryTemperatureCelsius: Double? {
        [cpuTemperatureCelsius, socTemperatureCelsius]
            .compactMap { $0 }
            .max()
    }
}
