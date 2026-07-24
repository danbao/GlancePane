import SwiftUI

struct SystemPageView: View {
    let snapshot: SystemSnapshot
    let history: SystemHistory
    let units: AppearanceUnitsConfig
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let gap = DashboardLayout.gap * scale
            let topHeight = (proxy.size.height - gap) * 0.52
            let bottomHeight = max(0, proxy.size.height - topHeight - gap)
            let topWidth = max(0, proxy.size.width - gap)
            let bottomWidth = max(0, proxy.size.width - gap * 2)

            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    MemoryOverviewPanel(snapshot: snapshot, history: history, theme: theme, scale: scale)
                        .frame(width: topWidth * 0.44)
                    EnvironmentOverviewPanel(snapshot: snapshot, history: history, units: units, theme: theme, scale: scale)
                }
                .frame(height: topHeight)

                HStack(spacing: gap) {
                    NetworkOverviewPanel(snapshot: snapshot, history: history, units: units, theme: theme, scale: scale)
                        .frame(width: bottomWidth * 0.31)
                    StorageOverviewPanel(snapshot: snapshot, history: history, units: units, theme: theme, scale: scale)
                        .frame(width: bottomWidth * 0.27)
                    HealthOverviewPanel(snapshot: snapshot, theme: theme, scale: scale)
                }
                .frame(height: bottomHeight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct MemoryOverviewPanel: View {
    let snapshot: SystemSnapshot
    let history: SystemHistory
    let theme: ScreenTheme
    let scale: CGFloat

    private var memory: MemoryStats { snapshot.memory }
    private var state: SystemMetricState { snapshot.state(for: .vitals) }

    var body: some View {
        MonitorPanel(
            title: "Memory",
            status: state.isActive ? memory.pressure.rawValue.uppercased() : state.title,
            statusColor: state.isActive ? pressureColor : theme.secondaryText,
            theme: theme,
            scale: scale
        ) {
            VStack(alignment: .leading, spacing: 10 * scale) {
                HStack(alignment: .firstTextBaseline, spacing: 12 * scale) {
                    MonitorHeroValue(
                        value: state.isActive ? "\(Int(memory.usage * 100))%" : "N/A",
                        size: 96,
                        color: pressureColor,
                        scale: scale
                    )
                    Text("USED")
                        .font(.system(size: 18 * scale, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }

                HStack(spacing: 22 * scale) {
                    CompactMetric(label: "USED", value: bytes(memory.usedBytes), color: theme.primaryText, scale: scale)
                    CompactMetric(label: "FREE", value: bytes(memory.freeBytes), color: theme.green, scale: scale)
                    CompactMetric(label: "SWAP", value: bytes(memory.swapUsedBytes), color: theme.amber, scale: scale)
                }

                Spacer(minLength: 0)

                HistorySparkline(
                    primary: history.samples.map(\.memoryUsage),
                    primaryColor: pressureColor,
                    fixedMaximum: 1
                )
                .frame(height: 72 * scale)
            }
        }
    }

    private func bytes(_ value: UInt64) -> String {
        state.isActive ? value.formattedBytes() : "N/A"
    }

    private var pressureColor: Color {
        guard state.isActive else { return theme.secondaryText }
        switch memory.pressure {
        case .normal: return theme.green
        case .warning: return theme.amber
        case .critical: return theme.red
        case .unknown: return theme.secondaryText
        }
    }
}

private struct EnvironmentOverviewPanel: View {
    let snapshot: SystemSnapshot
    let history: SystemHistory
    let units: AppearanceUnitsConfig
    let theme: ScreenTheme
    let scale: CGFloat

    private var state: SystemMetricState { snapshot.state(for: .thermals) }
    private var powerState: SystemMetricState { snapshot.state(for: .power) }
    private var primaryTemperature: Double? { snapshot.thermal.primaryTemperatureCelsius }
    private var gpuTemperature: Double? { snapshot.thermal.gpuTemperatureCelsius ?? snapshot.gpu.temperatureCelsius }

    var body: some View {
        MonitorPanel(
            title: "Thermals & Power",
            status: statusTitle,
            statusColor: statusColor,
            theme: theme,
            scale: scale
        ) {
            VStack(alignment: .leading, spacing: 9 * scale) {
                if let primaryTemperature {
                    HStack(alignment: .firstTextBaseline, spacing: 12 * scale) {
                        MonitorHeroValue(
                            value: primaryTemperature.formattedTemperature(unit: units.temperature),
                            size: 88,
                            color: theme.primaryText,
                            scale: scale
                        )
                        Text("HOTTEST CPU CORE")
                            .font(.system(size: DashboardTypography.label * scale, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(2)
                    }

                    HistorySparkline(
                        primary: history.samples.map(\.temperatureCelsius),
                        primaryColor: theme.amber,
                        fixedMaximum: 120
                    )
                    .frame(height: 72 * scale)
                } else {
                    HStack(spacing: 18 * scale) {
                        Image(systemName: thermalSymbol)
                            .font(.system(size: 64 * scale, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(statusColor)
                            .frame(width: 68 * scale)
                        VStack(alignment: .leading, spacing: 4 * scale) {
                            Text(snapshot.host.thermalState.rawValue.uppercased())
                                .font(.system(size: 58 * scale, weight: .bold, design: .rounded))
                                .foregroundStyle(statusColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Text(state.availability == .disabled ? "SENSORS DISABLED" : "SYSTEM THERMAL STATE")
                                .font(.system(size: DashboardTypography.label * scale, weight: .semibold))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 16 * scale) {
                    CompactMetric(label: "GPU", value: gpuTemperature?.formattedTemperature(unit: units.temperature) ?? "--", color: theme.blue, scale: scale, valueSize: 22)
                    CompactMetric(label: "FAN", value: fanValue, color: theme.green, scale: scale, valueSize: 22)
                    CompactMetric(label: "POWER", value: powerValue, color: theme.amber, scale: scale, valueSize: 22)
                    CompactMetric(label: snapshot.power.hasBattery ? "BATTERY" : "MODE", value: powerModeValue, color: powerModeColor, scale: scale, valueSize: 22)
                }
            }
        }
    }

    private var statusTitle: String {
        if state.availability == .disabled { return "DISABLED" }
        return "PRESSURE \(snapshot.host.thermalState.rawValue.uppercased())"
    }

    private var statusColor: Color {
        if state.availability == .disabled { return theme.secondaryText }
        switch snapshot.host.thermalState {
        case .nominal: return theme.green
        case .fair, .serious: return theme.amber
        case .critical: return theme.red
        case .unknown: return theme.secondaryText
        }
    }

    private var thermalSymbol: String {
        switch snapshot.host.thermalState {
        case .nominal: return "thermometer.low"
        case .fair: return "thermometer.medium"
        case .serious, .critical: return "thermometer.high"
        case .unknown: return "thermometer.variable"
        }
    }

    private var fanValue: String {
        guard let speed = snapshot.thermal.fanSpeedRPM else { return "--" }
        return "\(Int(speed.rounded())) RPM"
    }

    private var powerValue: String {
        guard let watts = snapshot.thermal.powerWatts else { return "--" }
        return watts >= 100 ? "\(Int(watts.rounded())) W" : String(format: "%.1f W", watts)
    }

    private var powerModeValue: String {
        guard powerState.isActive else {
            return powerState.availability == .disabled ? "DISABLED" : "--"
        }
        if snapshot.power.hasBattery, let level = snapshot.power.batteryLevel {
            let suffix = snapshot.power.isCharging ? " CHG" : ""
            return "\(Int(level * 100))%\(suffix)"
        }
        return snapshot.power.lowPowerModeEnabled ? "LOW POWER" : "AC POWER"
    }

    private var powerModeColor: Color {
        guard powerState.isActive else { return theme.secondaryText }
        return snapshot.power.lowPowerModeEnabled ? theme.amber : theme.green
    }
}

private struct NetworkOverviewPanel: View {
    let snapshot: SystemSnapshot
    let history: SystemHistory
    let units: AppearanceUnitsConfig
    let theme: ScreenTheme
    let scale: CGFloat

    private var network: NetworkStats { snapshot.network }
    private var state: SystemMetricState { snapshot.state(for: .network) }

    var body: some View {
        MonitorPanel(
            title: "Network",
            status: state.isActive ? (network.isConnected ? "ONLINE" : "OFFLINE") : state.title,
            statusColor: networkStatusColor,
            theme: theme,
            scale: scale
        ) {
            VStack(alignment: .leading, spacing: 8 * scale) {
                HStack(spacing: 12 * scale) {
                    CompactMetric(label: "DOWN", value: speed(network.downBytesPerSecond), color: theme.blue, scale: scale, valueSize: 34)
                    CompactMetric(label: "UP", value: speed(network.upBytesPerSecond), color: theme.red, scale: scale, valueSize: 34)
                }

                HistorySparkline(
                    primary: history.samples.map(\.networkDownBytesPerSecond),
                    secondary: history.samples.map(\.networkUpBytesPerSecond),
                    primaryColor: theme.blue,
                    secondaryColor: theme.red
                )
                .frame(height: 100 * scale)

                Text(networkLine)
                    .font(.system(size: DashboardTypography.body * scale, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(state.isActive ? (network.privateIPAddress ?? "NO ADDRESS") : "--")
                    .font(.system(size: DashboardTypography.body * scale, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func speed(_ value: Double) -> String {
        state.isActive ? value.formattedDataRate(unit: units.dataRate) : "N/A"
    }

    private var networkLine: String {
        guard state.isActive else { return state.title }
        var parts = [network.interfaceKind, network.primaryInterface, network.ssid].compactMap { $0 }
        if let latency = network.latencyMilliseconds { parts.append("\(Int(latency.rounded()))MS") }
        return parts.isEmpty ? "NO INTERFACE" : parts.joined(separator: "  ")
    }

    private var networkStatusColor: Color {
        guard state.isActive else { return theme.secondaryText }
        return network.isConnected ? theme.green : theme.red
    }
}

private struct StorageOverviewPanel: View {
    let snapshot: SystemSnapshot
    let history: SystemHistory
    let units: AppearanceUnitsConfig
    let theme: ScreenTheme
    let scale: CGFloat

    private var storage: StorageStats { snapshot.storage }
    private var state: SystemMetricState { snapshot.state(for: .storage) }

    var body: some View {
        MonitorPanel(
            title: "Storage",
            status: state.isActive ? nil : state.title,
            statusColor: theme.secondaryText,
            theme: theme,
            scale: scale
        ) {
            VStack(alignment: .leading, spacing: 7 * scale) {
                HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                    MonitorHeroValue(
                        value: state.isActive ? "\(Int(storage.usage * 100))%" : "N/A",
                        size: 58,
                        color: theme.primaryText,
                        scale: scale
                    )
                    Text("USED")
                        .font(.system(size: DashboardTypography.label * scale, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }

                HistorySparkline(
                    primary: history.samples.map(\.storageReadBytesPerSecond),
                    secondary: history.samples.map(\.storageWriteBytesPerSecond),
                    primaryColor: theme.green,
                    secondaryColor: theme.amber
                )
                .frame(height: 90 * scale)

                HStack(spacing: 12 * scale) {
                    CompactMetric(label: "READ", value: speed(storage.readBytesPerSecond), color: theme.green, scale: scale, valueSize: 22)
                    CompactMetric(label: "WRITE", value: speed(storage.writeBytesPerSecond), color: theme.amber, scale: scale, valueSize: 22)
                }

                Text(storageCapacity)
                    .font(.system(size: DashboardTypography.label * scale, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func speed(_ value: Double) -> String {
        state.isActive ? value.formattedDataRate(unit: units.dataRate) : "N/A"
    }

    private var storageCapacity: String {
        state.isActive
            ? "\(storage.usedBytes.formattedBytes()) / \(storage.totalBytes.formattedBytes())"
            : "-- / --"
    }
}

private struct HealthOverviewPanel: View {
    let snapshot: SystemSnapshot
    let theme: ScreenTheme
    let scale: CGFloat

    private var statusColor: Color {
        switch snapshot.health.severity {
        case .normal: return hasPendingCheck ? theme.secondaryText : theme.green
        case .warning: return theme.amber
        case .critical: return theme.red
        }
    }

    private var hasPendingCheck: Bool {
        snapshot.health.checks.contains { $0.state == .pending }
    }

    var body: some View {
        MonitorPanel(
            title: "Health",
            status: statusTitle,
            statusColor: statusColor,
            theme: theme,
            scale: scale
        ) {
            VStack(alignment: .leading, spacing: 9 * scale) {
                HStack(spacing: 10 * scale) {
                    Image(systemName: healthSymbol)
                        .font(.system(size: 29 * scale, weight: .semibold))
                        .foregroundStyle(statusColor)
                    VStack(alignment: .leading, spacing: 1 * scale) {
                        Text(headline)
                            .font(.system(size: 34 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(detail)
                            .font(.system(size: DashboardTypography.label * scale, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Divider().overlay(theme.border)

                if snapshot.health.checks.isEmpty {
                    Spacer(minLength: 0)
                    Text("WAITING FOR HEALTH CHECKS")
                        .font(.system(size: DashboardTypography.label * scale, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                    Spacer(minLength: 0)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12 * scale), GridItem(.flexible())],
                        alignment: .leading,
                        spacing: 16 * scale
                    ) {
                        ForEach(snapshot.health.checks) { check in
                            HealthCheckCell(check: check, theme: theme, scale: scale)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
            }
        }
    }

    private var statusTitle: String {
        switch snapshot.health.severity {
        case .normal: return hasPendingCheck ? "CHECKING" : "GOOD"
        case .warning: return "WARNING"
        case .critical: return "CRITICAL"
        }
    }

    private var headline: String {
        guard !snapshot.health.issues.isEmpty else { return hasPendingCheck ? "VERIFYING" : "ALL CLEAR" }
        if snapshot.health.severity == .critical, let issue = snapshot.health.issues.first {
            return issue.title
        }
        return snapshot.health.issues.count == 1 ? "1 WARNING" : "\(snapshot.health.issues.count) ISSUES"
    }

    private var detail: String {
        guard let issue = snapshot.health.issues.first else {
            let normalCount = snapshot.health.checks.filter { $0.state == .normal }.count
            let unavailableCount = snapshot.health.checks.filter { $0.state == .unavailable }.count
            let pendingCount = snapshot.health.checks.filter { $0.state == .pending }.count
            if unavailableCount > 0 || pendingCount > 0 {
                var parts = ["\(normalCount) OK"]
                if pendingCount > 0 { parts.append("\(pendingCount) PENDING") }
                if unavailableCount > 0 { parts.append("\(unavailableCount) N/A") }
                return parts.joined(separator: "  ")
            }
            return "\(normalCount) CHECKS HEALTHY"
        }
        return "\(issue.title)  \(issue.detail)"
    }

    private var healthSymbol: String {
        if hasPendingCheck { return "clock.fill" }
        return snapshot.health.severity == .normal
            ? "checkmark.circle.fill"
            : "exclamationmark.triangle.fill"
    }
}

private struct HealthCheckCell: View {
    let check: HealthCheck
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 8 * scale) {
            Image(systemName: check.symbolName)
                .font(.system(size: 17 * scale, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 21 * scale)
            VStack(alignment: .leading, spacing: 1 * scale) {
                Text(check.title)
                    .font(.system(size: 16 * scale, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                Text(check.value)
                    .font(.system(size: 22 * scale, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(minHeight: 52 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var color: Color {
        switch check.state {
        case .normal: return theme.green
        case .pending: return theme.secondaryText
        case .warning: return theme.amber
        case .critical: return theme.red
        case .unavailable: return theme.secondaryText
        }
    }
}

private struct CompactMetric: View {
    let label: String
    let value: String
    let color: Color
    let scale: CGFloat
    var valueSize: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            Text(label)
                .font(.system(size: DashboardTypography.label * scale, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
            Text(value)
                .font(.system(size: valueSize * scale, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
