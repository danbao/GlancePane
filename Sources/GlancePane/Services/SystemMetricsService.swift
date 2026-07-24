import Foundation

final class SystemMetricsService {
    private let cpuCollector = CPUCollector()
    private let gpuCollector = GPUCollector()
    private let memoryCollector = MemoryCollector()
    private let storageCollector = StorageCollector()
    private let networkCollector = NetworkCollector()
    private let powerCollector = PowerCollector()
    private let thermalCollector: ThermalCollecting
    private let hostCollector = HostCollector()
    private let processCollector = ProcessCollector()

    private var snapshot: SystemSnapshot = .empty
    private var lastRefresh: [SystemMetricGroup: Date] = [:]
    private var lastProcessRefresh: Date?

    init(thermalCollector: ThermalCollecting = ThermalCollector()) {
        self.thermalCollector = thermalCollector
    }

    func sample(config: AppConfig, force: Bool = false, at now: Date = Date()) -> SystemSnapshot {
        var didRefresh = false

        if config.system.enabledGroups.contains(.vitals) {
            if shouldRefresh(.vitals, config: config, now: now, force: force) {
                snapshot.cpu = cpuCollector.sample()
                snapshot.memory = memoryCollector.sample()
                snapshot.host = hostCollector.sample()
                snapshot.metricStates[.vitals] = snapshot.memory.totalBytes > 0 ? .active(at: now) : .unavailable
                lastRefresh[.vitals] = now
                didRefresh = true
            }
        } else {
            snapshot.cpu = .empty
            snapshot.memory = .empty
            snapshot.host = .empty
            snapshot.metricStates[.vitals] = .disabled
            lastRefresh[.vitals] = nil
        }

        if config.system.enabledGroups.contains(.storage) {
            if shouldRefresh(.storage, config: config, now: now, force: force) {
                snapshot.storage = storageCollector.sample()
                snapshot.metricStates[.storage] = snapshot.storage.totalBytes > 0 ? .active(at: now) : .unavailable
                lastRefresh[.storage] = now
                didRefresh = true
            }
        } else {
            snapshot.storage = .empty
            snapshot.metricStates[.storage] = .disabled
            lastRefresh[.storage] = nil
        }

        if config.system.enabledGroups.contains(.gpu) {
            if shouldRefresh(.gpu, config: config, now: now, force: force) {
                snapshot.gpu = gpuCollector.sample()
                snapshot.metricStates[.gpu] = snapshot.gpu.isAvailable ? .active(at: now) : .unavailable
                lastRefresh[.gpu] = now
                didRefresh = true
            }
        } else {
            snapshot.gpu = .unavailable
            snapshot.metricStates[.gpu] = .disabled
            lastRefresh[.gpu] = nil
        }

        if config.system.enabledGroups.contains(.network) {
            if shouldRefresh(.network, config: config, now: now, force: force) {
                snapshot.network = networkCollector.sample()
                snapshot.metricStates[.network] = .active(at: now)
                lastRefresh[.network] = now
                didRefresh = true
            }
        } else {
            snapshot.network = .empty
            snapshot.metricStates[.network] = .disabled
            lastRefresh[.network] = nil
        }

        if config.system.enabledGroups.contains(.power) {
            if shouldRefresh(.power, config: config, now: now, force: force) {
                snapshot.power = powerCollector.sample()
                snapshot.metricStates[.power] = snapshot.power.isAvailable ? .active(at: now) : .unavailable
                lastRefresh[.power] = now
                didRefresh = true
            }
        } else {
            snapshot.power = .unavailable
            snapshot.metricStates[.power] = .disabled
            lastRefresh[.power] = nil
        }

        if config.system.enabledGroups.contains(.thermals) {
            if shouldRefresh(.thermals, config: config, now: now, force: force) {
                snapshot.thermal = thermalCollector.sample(enabled: true)
                snapshot.metricStates[.thermals] = snapshot.thermal.hasAnyValue ? .active(at: now) : .unavailable
                lastRefresh[.thermals] = now
                didRefresh = true
            }
        } else {
            snapshot.thermal = .unavailable
            snapshot.metricStates[.thermals] = .disabled
            lastRefresh[.thermals] = nil
        }

        if config.system.processes.enabled {
            let interval = config.system.processes.refreshIntervalSeconds
            if force || lastProcessRefresh == nil || now.timeIntervalSince(lastProcessRefresh!) >= interval {
                snapshot.processes = processCollector.sample(limit: config.system.processes.limit, at: now)
                lastProcessRefresh = now
                didRefresh = true
            }
        } else {
            snapshot.processes = []
            lastProcessRefresh = nil
        }

        if didRefresh {
            snapshot.capturedAt = now
        }
        return snapshot
    }

    func handleSystemWake() {
        thermalCollector.resetConnection()
        lastRefresh[.thermals] = nil
    }

    private func shouldRefresh(_ group: SystemMetricGroup, config: AppConfig, now: Date, force: Bool) -> Bool {
        if force {
            return true
        }

        guard config.system.enabledGroups.contains(group) else {
            return false
        }

        guard let last = lastRefresh[group] else {
            return true
        }

        let interval = config.system.refreshIntervalsSeconds[group] ?? SystemMetricGroup.defaultRefreshIntervals[group] ?? config.system.defaultRefreshIntervalSeconds
        return now.timeIntervalSince(last) >= max(1, interval)
    }
}
