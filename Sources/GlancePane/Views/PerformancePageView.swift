import SwiftUI

struct PerformancePageView: View {
    let snapshot: SystemSnapshot
    let history: SystemHistory
    let units: AppearanceUnitsConfig
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let gap = DashboardLayout.gap * scale
            let leftWidth = (proxy.size.width - gap) * 0.62

            HStack(spacing: gap) {
                PerformanceCPUView(snapshot: snapshot, history: history, theme: theme, scale: scale)
                    .frame(width: leftWidth)

                VStack(spacing: gap) {
                    PerformanceGPUView(snapshot: snapshot, history: history, units: units, theme: theme, scale: scale)
                        .frame(height: (proxy.size.height - gap) * 0.43)
                    PerformanceProcessesView(snapshot: snapshot, theme: theme, scale: scale)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct PerformanceCPUView: View {
    let snapshot: SystemSnapshot
    let history: SystemHistory
    let theme: ScreenTheme
    let scale: CGFloat

    private var state: SystemMetricState { snapshot.state(for: .vitals) }

    var body: some View {
        MonitorPanel(
            title: "CPU Performance",
            status: state.isActive ? "LIVE" : state.title,
            statusColor: state.isActive ? theme.green : theme.secondaryText,
            theme: theme,
            scale: scale
        ) {
            VStack(alignment: .leading, spacing: 12 * scale) {
                HStack(alignment: .firstTextBaseline, spacing: 14 * scale) {
                    MonitorHeroValue(
                        value: state.isActive ? "\(Int(snapshot.cpu.totalUsage * 100))%" : "N/A",
                        size: 90,
                        color: theme.primaryText,
                        scale: scale
                    )
                    PerformanceLegend(label: "USER", value: snapshot.cpu.userUsage, color: theme.blue, scale: scale)
                    PerformanceLegend(label: "SYSTEM", value: snapshot.cpu.systemUsage, color: theme.red, scale: scale)
                    Spacer(minLength: 0)
                }

                HistorySparkline(
                    primary: history.samples.map(\.cpuUser),
                    secondary: history.samples.map(\.cpuSystem),
                    primaryColor: theme.blue,
                    secondaryColor: theme.red,
                    fixedMaximum: 1
                )
                .frame(height: 190 * scale)

                Text("CORE ACTIVITY")
                    .font(.system(size: DashboardTypography.label * scale, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)

                if !snapshot.cpu.performanceCoreUsage.isEmpty || !snapshot.cpu.efficiencyCoreUsage.isEmpty {
                    CoreGroupBars(
                        title: "PERFORMANCE",
                        values: snapshot.cpu.performanceCoreUsage,
                        color: theme.blue,
                        theme: theme,
                        scale: scale
                    )
                    CoreGroupBars(
                        title: "EFFICIENCY",
                        values: snapshot.cpu.efficiencyCoreUsage,
                        color: theme.green,
                        theme: theme,
                        scale: scale
                    )
                } else {
                    CoreGroupBars(
                        title: "CORES",
                        values: snapshot.cpu.unknownCoreUsage.isEmpty ? snapshot.cpu.perCoreUsage : snapshot.cpu.unknownCoreUsage,
                        color: theme.amber,
                        theme: theme,
                        scale: scale
                    )
                }

                Spacer(minLength: 8 * scale)
                HStack(spacing: 18 * scale) {
                    CPUFooterMetric(label: "P AVG", value: average(snapshot.cpu.performanceCoreUsage), color: theme.blue, scale: scale)
                    CPUFooterMetric(label: "E AVG", value: average(snapshot.cpu.efficiencyCoreUsage), color: theme.green, scale: scale)
                    CPUFooterMetric(label: "LOAD 1M", value: String(format: "%.2f", snapshot.host.loadAverage1Minute), color: theme.amber, scale: scale)
                    CPUFooterMetric(label: "UPTIME", value: snapshot.host.uptimeSeconds.formattedUptime(), color: theme.secondaryText, scale: scale)
                }
            }
        }
    }

    private func average(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "N/A" }
        return "\(Int(values.reduce(0, +) / Double(values.count) * 100))%"
    }
}

private struct PerformanceGPUView: View {
    let snapshot: SystemSnapshot
    let history: SystemHistory
    let units: AppearanceUnitsConfig
    let theme: ScreenTheme
    let scale: CGFloat

    private var state: SystemMetricState { snapshot.state(for: .gpu) }

    var body: some View {
        MonitorPanel(
            title: "GPU",
            status: state.isActive ? "LIVE" : state.title,
            statusColor: state.isActive ? theme.green : theme.secondaryText,
            theme: theme,
            scale: scale
        ) {
            VStack(alignment: .leading, spacing: 7 * scale) {
                HStack(alignment: .firstTextBaseline, spacing: 10 * scale) {
                    MonitorHeroValue(
                        value: snapshot.gpu.usage.map { "\(Int($0 * 100))%" } ?? "N/A",
                        size: 64,
                        color: theme.blue,
                        scale: scale
                    )
                    Text(snapshot.gpu.model ?? "GPU")
                        .font(.system(size: DashboardTypography.label * scale, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HistorySparkline(
                    primary: history.samples.map(\.gpuUsage),
                    primaryColor: theme.blue,
                    fixedMaximum: 1
                )
                .frame(height: 48 * scale)

                HStack(spacing: 15 * scale) {
                    GPUDetail(label: "MEM", value: snapshot.gpu.memoryBytes?.formattedBytes() ?? "N/A", scale: scale)
                    GPUDetail(label: "TEMP", value: snapshot.gpu.temperatureCelsius?.formattedTemperature(unit: units.temperature) ?? "N/A", scale: scale)
                    GPUDetail(label: "CLOCK", value: frequency, scale: scale)
                }
            }
        }
    }

    private var frequency: String {
        guard let value = snapshot.gpu.frequencyMHz else { return "N/A" }
        return value >= 1_000 ? String(format: "%.2fGHz", value / 1_000) : "\(Int(value))MHz"
    }
}

private struct PerformanceProcessesView: View {
    let snapshot: SystemSnapshot
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        MonitorPanel(title: "Top Processes", theme: theme, scale: scale) {
            VStack(spacing: 0) {
                HStack {
                    Text("PROCESS")
                    Spacer(minLength: 0)
                    Text("CPU")
                        .frame(width: 68 * scale, alignment: .trailing)
                    Text("MEMORY")
                        .frame(width: 92 * scale, alignment: .trailing)
                }
                .font(.system(size: DashboardTypography.status * scale, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .padding(.bottom, 5 * scale)

                if snapshot.processes.isEmpty {
                    Spacer(minLength: 0)
                    Text("COLLECTING PROCESS DATA")
                        .font(.system(size: DashboardTypography.label * scale, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                    Spacer(minLength: 0)
                } else {
                    ForEach(snapshot.processes.prefix(4)) { process in
                        HStack(spacing: 8 * scale) {
                            Text(process.name)
                                .font(.system(size: DashboardTypography.body * scale, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 4 * scale)
                            Text(String(format: "%.0f%%", process.cpuPercent))
                                .foregroundStyle(process.cpuPercent >= 100 ? theme.amber : theme.blue)
                                .frame(width: 68 * scale, alignment: .trailing)
                            Text(process.memoryBytes.formattedBytes())
                                .foregroundStyle(theme.secondaryText)
                                .frame(width: 92 * scale, alignment: .trailing)
                        }
                        .font(.system(size: 22 * scale, weight: .medium, design: .monospaced))
                        .frame(maxHeight: .infinity)
                        if process.id != snapshot.processes.prefix(4).last?.id {
                            Divider().overlay(theme.border)
                        }
                    }
                }
            }
        }
    }
}

private struct PerformanceLegend: View {
    let label: String
    let value: Double
    let color: Color
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2 * scale) {
            Text(label)
                .font(.system(size: DashboardTypography.label * scale, weight: .semibold))
                .foregroundStyle(color)
            Text("\(Int(value * 100))%")
                .font(.system(size: DashboardTypography.metric * scale, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

private struct CoreGroupBars: View {
    let title: String
    let values: [Double]
    let color: Color
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 12 * scale) {
            Text(title)
                .font(.system(size: DashboardTypography.label * scale, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 142 * scale, alignment: .leading)

            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 3 * scale) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.06))
                            Capsule()
                                .fill(value > 0.85 ? theme.red : value > 0.6 ? theme.amber : color)
                                .frame(width: proxy.size.width * max(0.025, min(1, value)))
                        }
                    }
                    .frame(height: 13 * scale)
                    Text("\(index + 1)")
                        .font(.system(size: DashboardTypography.status * scale, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 40 * scale)
    }
}

private struct GPUDetail: View {
    let label: String
    let value: String
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2 * scale) {
            Text(label)
                .font(.system(size: DashboardTypography.label * scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 22 * scale, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CPUFooterMetric: View {
    let label: String
    let value: String
    let color: Color
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            Text(label)
                .font(.system(size: DashboardTypography.label * scale, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 28 * scale, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
