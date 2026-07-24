import Foundation

final class HealthEvaluator {
    private var cpuHighSince: Date?
    private var networkOfflineSince: Date?

    func evaluate(
        snapshot: SystemSnapshot,
        thresholds: HealthThresholdsConfig,
        at now: Date = Date()
    ) -> SystemHealth {
        let thresholds = thresholds.normalized()
        var issues: [HealthIssue] = []
        var checks: [HealthCheck] = []

        evaluateCPU(snapshot: snapshot, thresholds: thresholds, now: now, issues: &issues)
        checks.append(memoryCheck(snapshot: snapshot, issues: &issues))
        checks.append(storageCheck(snapshot: snapshot, thresholds: thresholds, issues: &issues))
        checks.append(networkCheck(snapshot: snapshot, thresholds: thresholds, now: now, issues: &issues))
        checks.append(thermalCheck(snapshot: snapshot, issues: &issues))
        if snapshot.power.hasBattery {
            checks.append(batteryCheck(snapshot: snapshot, issues: &issues))
        }

        issues.sort { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.id < rhs.id
        }
        let checkSeverity = checks.compactMap(healthSeverity(for:)).max() ?? .normal
        let issueSeverity = issues.map(\.severity).max() ?? .normal
        return SystemHealth(severity: max(checkSeverity, issueSeverity), issues: issues, checks: checks)
    }

    func reset() {
        cpuHighSince = nil
        networkOfflineSince = nil
    }

    private func evaluateCPU(
        snapshot: SystemSnapshot,
        thresholds: HealthThresholdsConfig,
        now: Date,
        issues: inout [HealthIssue]
    ) {
        guard snapshot.state(for: .vitals).isActive,
              snapshot.cpu.totalUsage * 100 >= thresholds.cpuHighPercent
        else {
            cpuHighSince = nil
            return
        }

        cpuHighSince = cpuHighSince ?? now
        guard let cpuHighSince,
              now.timeIntervalSince(cpuHighSince) >= thresholds.cpuSustainSeconds
        else { return }

        issues.append(
            HealthIssue(
                id: "cpu",
                title: "HIGH CPU LOAD",
                detail: "\(Int(snapshot.cpu.totalUsage * 100))% for \(Int(now.timeIntervalSince(cpuHighSince)))s",
                severity: .warning
            )
        )
    }

    private func memoryCheck(snapshot: SystemSnapshot, issues: inout [HealthIssue]) -> HealthCheck {
        guard snapshot.state(for: .vitals).isActive else {
            return unavailableCheck(id: "memory", title: "MEMORY", symbol: "memorychip")
        }

        let state: HealthCheckState
        switch snapshot.memory.pressure {
        case .normal:
            state = .normal
        case .warning:
            state = .warning
            issues.append(HealthIssue(id: "memory", title: "MEMORY PRESSURE", detail: "Warning", severity: .warning))
        case .critical:
            state = .critical
            issues.append(HealthIssue(id: "memory", title: "MEMORY PRESSURE", detail: "Critical", severity: .critical))
        case .unknown:
            state = .unavailable
        }

        return HealthCheck(
            id: "memory",
            title: "MEMORY",
            value: snapshot.memory.pressure.rawValue.uppercased(),
            symbolName: "memorychip",
            state: state
        )
    }

    private func storageCheck(
        snapshot: SystemSnapshot,
        thresholds: HealthThresholdsConfig,
        issues: inout [HealthIssue]
    ) -> HealthCheck {
        guard snapshot.state(for: .storage).isActive, snapshot.storage.totalBytes > 0 else {
            return unavailableCheck(id: "storage", title: "STORAGE", symbol: "internaldrive")
        }

        let freePercent = Double(snapshot.storage.totalBytes - min(snapshot.storage.usedBytes, snapshot.storage.totalBytes))
            / Double(snapshot.storage.totalBytes) * 100
        let state: HealthCheckState = freePercent < 3 ? .critical : freePercent < thresholds.diskFreePercent ? .warning : .normal
        if state == .warning || state == .critical {
            issues.append(
                HealthIssue(
                    id: "storage",
                    title: "LOW DISK SPACE",
                    detail: "\(Int(freePercent.rounded()))% free",
                    severity: state == .critical ? .critical : .warning
                )
            )
        }

        return HealthCheck(
            id: "storage",
            title: "STORAGE",
            value: "\(Int(freePercent.rounded()))% FREE",
            symbolName: "internaldrive",
            state: state
        )
    }

    private func networkCheck(
        snapshot: SystemSnapshot,
        thresholds: HealthThresholdsConfig,
        now: Date,
        issues: inout [HealthIssue]
    ) -> HealthCheck {
        guard snapshot.state(for: .network).isActive else {
            networkOfflineSince = nil
            return unavailableCheck(id: "network", title: "NETWORK", symbol: "network")
        }

        guard snapshot.network.isConnected else {
            networkOfflineSince = networkOfflineSince ?? now
            let offlineDuration = now.timeIntervalSince(networkOfflineSince ?? now)
            let isSustained = offlineDuration >= thresholds.networkOfflineSeconds
            if isSustained {
                issues.append(
                    HealthIssue(
                        id: "network",
                        title: "NETWORK OFFLINE",
                        detail: "\(Int(offlineDuration))s",
                        severity: .warning
                    )
                )
            }
            return HealthCheck(
                id: "network",
                title: "NETWORK",
                value: isSustained ? "OFFLINE" : "OFFLINE \(Int(offlineDuration))S",
                symbolName: "network.slash",
                state: isSustained ? .warning : .pending
            )
        }

        networkOfflineSince = nil
        let value = snapshot.network.latencyMilliseconds.map { "\(Int($0.rounded()))MS" } ?? "ONLINE"
        return HealthCheck(id: "network", title: "NETWORK", value: value, symbolName: "network", state: .normal)
    }

    private func thermalCheck(snapshot: SystemSnapshot, issues: inout [HealthIssue]) -> HealthCheck {
        guard snapshot.state(for: .vitals).isActive else {
            return unavailableCheck(id: "thermal", title: "THERMAL", symbol: "thermometer.medium")
        }

        let state: HealthCheckState
        switch snapshot.host.thermalState {
        case .nominal:
            state = .normal
        case .fair:
            state = .warning
            issues.append(HealthIssue(id: "thermal", title: "THERMALS ELEVATED", detail: "Fair", severity: .warning))
        case .serious:
            state = .warning
            issues.append(HealthIssue(id: "thermal", title: "THERMAL PRESSURE", detail: "Serious", severity: .warning))
        case .critical:
            state = .critical
            issues.append(HealthIssue(id: "thermal", title: "THERMAL PRESSURE", detail: "Critical", severity: .critical))
        case .unknown:
            state = .unavailable
        }

        return HealthCheck(
            id: "thermal",
            title: "THERMAL",
            value: "PRESSURE \(snapshot.host.thermalState.rawValue.uppercased())",
            symbolName: "thermometer.medium",
            state: state
        )
    }

    private func batteryCheck(snapshot: SystemSnapshot, issues: inout [HealthIssue]) -> HealthCheck {
        guard snapshot.state(for: .power).isActive else {
            return unavailableCheck(id: "battery", title: "BATTERY", symbol: "battery.50percent")
        }

        guard let health = snapshot.power.healthPercent else {
            return HealthCheck(
                id: "battery",
                title: "BATTERY",
                value: "HEALTH N/A",
                symbolName: "battery.75percent",
                state: .unavailable
            )
        }

        let state: HealthCheckState
        if health < 60 {
            state = .critical
        } else if health < 80 {
            state = .warning
        } else {
            state = .normal
        }

        if state == .warning || state == .critical {
            issues.append(
                HealthIssue(
                    id: "battery",
                    title: "BATTERY HEALTH",
                    detail: "\(health)% capacity",
                    severity: state == .critical ? .critical : .warning
                )
            )
        }

        return HealthCheck(
            id: "battery",
            title: "BATTERY",
            value: "\(health)% HEALTH",
            symbolName: "battery.75percent",
            state: state
        )
    }

    private func unavailableCheck(id: String, title: String, symbol: String) -> HealthCheck {
        HealthCheck(id: id, title: title, value: "N/A", symbolName: symbol, state: .unavailable)
    }

    private func healthSeverity(for check: HealthCheck) -> HealthSeverity? {
        switch check.state {
        case .normal, .pending, .unavailable: return nil
        case .warning: return .warning
        case .critical: return .critical
        }
    }
}
