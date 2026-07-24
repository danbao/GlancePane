import SwiftUI

struct WeatherPageView: View {
    let snapshot: WeatherSnapshot
    let status: FeedStatus
    let config: AppConfig
    let theme: ScreenTheme
    let scale: CGFloat

    private var hasWeatherData: Bool {
        snapshot.current != nil || !snapshot.hourly.isEmpty || !snapshot.minutely.isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            let gap = DashboardLayout.gap * scale
            let topHeight = (proxy.size.height - gap) * 0.61
            let bottomHeight = max(0, proxy.size.height - topHeight - gap)

            if hasWeatherData {
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        WeatherHeroPanel(snapshot: snapshot, status: status, unit: config.appearance.units.temperature, theme: theme, scale: scale)
                            .frame(width: proxy.size.width * 0.46)
                        WeatherNowcastPanel(snapshot: snapshot, theme: theme, scale: scale)
                    }
                    .frame(height: topHeight)

                    WeatherHourlyStrip(hourly: snapshot.hourly, unit: config.appearance.units.temperature, theme: theme, scale: scale)
                        .frame(height: bottomHeight)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                WeatherSetupPanel(status: status, config: config, snapshot: snapshot, theme: theme, scale: scale)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

private struct WeatherHeroPanel: View {
    let snapshot: WeatherSnapshot
    let status: FeedStatus
    let unit: TemperatureUnit
    let theme: ScreenTheme
    let scale: CGFloat

    private var current: CurrentWeather? { snapshot.current }

    var body: some View {
        SectionPanel(title: "Current", theme: theme, scale: scale) {
            VStack(alignment: .leading, spacing: 10 * scale) {
                HStack(spacing: 9 * scale) {
                    StatusPill(title: status.title.uppercased(), color: statusColor, scale: scale)
                    Text("UPDATED \(observedText)")
                        .font(.system(size: DashboardTypography.status * scale, weight: .black, design: .monospaced))
                        .foregroundStyle(theme.secondaryText.opacity(0.62))
                        .lineLimit(1)
                    Spacer(minLength: 6 * scale)
                    Text(snapshot.locationName.uppercased())
                        .font(.system(size: 24 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(alignment: .center, spacing: 16 * scale) {
                    WeatherIconView(
                        iconCode: current?.icon,
                        condition: current?.condition,
                        size: 132 * scale,
                        theme: theme
                    )
                    .frame(width: 138 * scale, height: 138 * scale)
                    .clipped()

                    VStack(alignment: .leading, spacing: 4 * scale) {
                        WeatherHeroTemperatureValue(value: current?.temperatureCelsius, unit: unit, theme: theme, scale: scale)

                        Text(current?.condition.uppercased() ?? "N/A")
                            .font(.system(size: 48 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }

                HStack(spacing: 8 * scale) {
                    WeatherMetricBadge(label: "FEELS", value: formattedTemperature(current?.feelsLikeCelsius), color: theme.blue, theme: theme, scale: scale)
                    WeatherMetricBadge(label: "HUMID", value: percent(current?.humidityPercent), color: theme.green, theme: theme, scale: scale)
                    WeatherMetricBadge(label: "RAIN", value: rain(current?.precipitationMillimeters), color: theme.amber, theme: theme, scale: scale)
                    WeatherMetricBadge(label: "WIND KM/H", value: windBadgeText, color: theme.secondaryText, theme: theme, scale: scale)
                }

                if let error = snapshot.errorMessage, !error.isEmpty {
                    Text(error.uppercased())
                        .font(.system(size: DashboardTypography.status * scale, weight: .black, design: .monospaced))
                        .foregroundStyle(theme.amber)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private var statusColor: Color {
        switch status {
        case .live: return theme.green
        case .partial, .cached, .setup: return theme.amber
        case .offline: return theme.red
        default: return theme.blue
        }
    }

    private var windBadgeText: String {
        let direction = current?.windDirection ?? "N/A"
        guard let speed = current?.windSpeedKph else { return direction }
        return "\(direction) \(Int(speed.rounded()))"
    }

    private var observedText: String {
        guard let observedAt = current?.observedAt else {
            return DateFormatter.cached(format: "HH:mm:ss").string(from: snapshot.updatedAt)
        }
        return DateFormatter.cached(format: "HH:mm").string(from: observedAt)
    }

    private func formattedTemperature(_ value: Double?) -> String {
        value?.formattedTemperature(unit: unit) ?? "N/A"
    }
}

private struct WeatherNowcastPanel: View {
    let snapshot: WeatherSnapshot
    let theme: ScreenTheme
    let scale: CGFloat

    private var minutely: [MinutelyPrecipitation] { Array(snapshot.minutely.prefix(24)) }
    private var maxRain: Double { minutely.map(\.precipitationMillimeters).max() ?? 0 }
    private var hasMinuteRain: Bool { maxRain > 0.01 }
    private var isDryMinuteForecast: Bool { !minutely.isEmpty && !hasMinuteRain }

    var body: some View {
        SectionPanel(title: "2H Nowcast", theme: theme, scale: scale) {
            if isDryMinuteForecast {
                dryContent
            } else {
                rainContent
            }
        }
    }

    private var dryContent: some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            HStack(alignment: .firstTextBaseline) {
                Text("2H DRY")
                    .font(.system(size: 60 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(theme.green)
                Spacer()
                Text("5 MIN NOWCAST")
                    .font(.system(size: 16 * scale, weight: .black, design: .monospaced))
                    .foregroundStyle(theme.blue)
            }

            Spacer(minLength: 0)

            HStack(spacing: 24 * scale) {
                Image(systemName: "cloud.sun.fill")
                    .symbolRenderingMode(.multicolor)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96 * scale, height: 96 * scale)

                Text("未来两小时无降水")
                    .font(.system(size: 50 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(theme.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
            attribution
        }
    }

    private var rainContent: some View {
        VStack(alignment: .leading, spacing: 13 * scale) {
            HStack(alignment: .top) {
                Text(nowcastTitle)
                    .font(.system(size: 58 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(nowcastColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 12 * scale)

                VStack(alignment: .trailing, spacing: 6 * scale) {
                    Text(snapshot.minutely.isEmpty ? "HOURLY" : "5 MIN")
                        .font(.system(size: 17 * scale, weight: .black, design: .monospaced))
                        .foregroundStyle(theme.blue)
                    Text(peakText)
                        .font(.system(size: 33 * scale, weight: .black, design: .monospaced))
                        .foregroundStyle(nowcastColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            Group {
                if !minutely.isEmpty {
                    WeatherMinutelyRainChart(points: minutely, theme: theme, scale: scale)
                } else if !snapshot.hourly.isEmpty {
                    WeatherHourlyRainChart(hourly: Array(snapshot.hourly.prefix(12)), theme: theme, scale: scale)
                } else {
                    Text("NO RAIN DATA")
                        .font(.system(size: 36 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.top, 8 * scale)

            Text(nowcastSubtitle.uppercased())
                .font(.system(size: 46 * scale, weight: .black, design: .rounded))
                .foregroundStyle(nowcastColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 0)

            attribution
        }
    }

    private var attribution: some View {
        Text("QWEATHER \(snapshot.attributionURL ?? "https://www.qweather.com")")
            .font(.system(size: DashboardTypography.attribution * scale, weight: .black, design: .monospaced))
            .foregroundStyle(theme.secondaryText.opacity(0.75))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private var nowcastTitle: String {
        !minutely.isEmpty ? "RAIN SOON" : "RAIN TREND"
    }

    private var nowcastSubtitle: String {
        if !minutely.isEmpty && hasMinuteRain { return firstRainText }
        return snapshot.precipitationSummary.isEmpty ? "未来两小时降水趋势" : snapshot.precipitationSummary
    }

    private var firstRainText: String {
        guard let first = minutely.first(where: { $0.precipitationMillimeters > 0.01 }) else {
            return snapshot.precipitationSummary
        }

        let minutes = max(0, Int(first.forecastAt.timeIntervalSince(Date()) / 60))
        if minutes <= 5 { return "现在附近有零星降水" }
        return "约 \(minutes) 分钟后可能有雨"
    }

    private var peakText: String {
        if !minutely.isEmpty { return "PEAK \(rain(maxRain))" }
        let peak = snapshot.hourly.prefix(12).compactMap(\.precipitationMillimeters).max() ?? 0
        return "PEAK \(rain(peak))"
    }

    private var nowcastColor: Color {
        if maxRain >= 2 { return theme.red }
        if maxRain >= 0.2 { return theme.amber }
        if maxRain > 0.01 { return theme.blue }
        return theme.green
    }
}

private struct WeatherMinutelyRainChart: View {
    let points: [MinutelyPrecipitation]
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let maxRain = Swift.max(points.map(\.precipitationMillimeters).max() ?? 0, 0.3)
            let spacing = 5 * scale
            let totalSpacing = CGFloat(Swift.max(points.count - 1, 0)) * spacing
            let width = Swift.max(5 * scale, (proxy.size.width - totalSpacing) / CGFloat(Swift.max(points.count, 1)))

            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(theme.border.opacity(0.45)).frame(height: 1)
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(points) { point in
                        let ratio = CGFloat(point.precipitationMillimeters / maxRain)
                        RoundedRectangle(cornerRadius: 3 * scale)
                            .fill(rainColor(point.precipitationMillimeters))
                            .frame(width: width, height: Swift.max(4 * scale, proxy.size.height * ratio))
                    }
                }
            }
        }
        .frame(height: 96 * scale)
        .frame(maxWidth: .infinity)
    }

    private func rainColor(_ value: Double) -> Color {
        if value >= 2 { return theme.red }
        if value >= 0.6 { return theme.amber }
        if value > 0 { return theme.blue }
        return theme.secondaryText.opacity(0.24)
    }
}

private struct WeatherHourlyRainChart: View {
    let hourly: [HourlyWeather]
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let maxRain = Swift.max(hourly.compactMap(\.precipitationMillimeters).max() ?? 0, 0.8)

            HStack(alignment: .bottom, spacing: 8 * scale) {
                ForEach(hourly) { item in
                    let precipitation = item.precipitationMillimeters ?? 0
                    VStack(spacing: 6 * scale) {
                        RoundedRectangle(cornerRadius: 3 * scale)
                            .fill(precipitation > 0 ? theme.blue : theme.secondaryText.opacity(0.22))
                            .frame(height: max(5 * scale, proxy.size.height * 0.72 * CGFloat(precipitation / maxRain)))
                        Text(DateFormatter.cached(format: "HH").string(from: item.forecastAt))
                            .font(.system(size: DashboardTypography.chartTick * scale, weight: .black, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(height: 96 * scale)
        .frame(maxWidth: .infinity)
    }
}

private struct WeatherHourlyStrip: View {
    let hourly: [HourlyWeather]
    let unit: TemperatureUnit
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        SectionPanel(title: "Hourly", theme: theme, scale: scale) {
            if hourly.isEmpty {
                Text("WAITING FOR HOURLY FORECAST")
                    .font(.system(size: 28 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8 * scale) {
                    ForEach(Array(hourly.prefix(8))) { item in
                        WeatherHourlyForecastTile(item: item, unit: unit, theme: theme, scale: scale)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct WeatherHourlyForecastTile: View {
    let item: HourlyWeather
    let unit: TemperatureUnit
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 4 * scale) {
            Text(DateFormatter.cached(format: "HH:mm").string(from: item.forecastAt))
                .font(.system(size: 20 * scale, weight: .black, design: .monospaced))
                .foregroundStyle(theme.secondaryText)

            WeatherIconView(iconCode: item.icon, condition: item.condition, size: 58 * scale, theme: theme)

            Text(item.temperatureCelsius?.formattedTemperature(unit: unit) ?? "N/A")
                .font(.system(size: 40 * scale, weight: .black, design: .monospaced))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(percent(item.precipitationProbabilityPercent))
                .font(.system(size: 17 * scale, weight: .black, design: .monospaced))
                .foregroundStyle((item.precipitationProbabilityPercent ?? 0) >= 40 ? theme.blue : theme.secondaryText)
                .lineLimit(1)
            Text(rain(item.precipitationMillimeters))
                .font(.system(size: 18 * scale, weight: .black, design: .monospaced))
                .foregroundStyle((item.precipitationMillimeters ?? 0) > 0 ? theme.blue : theme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 6 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.panelCornerRadius * scale))
    }
}

private struct WeatherMetricBadge: View {
    let label: String
    let value: String
    let color: Color
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            Text(label)
                .font(.system(size: DashboardTypography.label * scale, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(value)
                .font(.system(size: 34 * scale, weight: .black, design: .monospaced))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
        }
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 8 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.panelCornerRadius * scale))
    }
}

private struct WeatherIconView: View {
    let iconCode: String?
    let condition: String?
    let size: CGFloat
    let theme: ScreenTheme

    var body: some View {
        Image(systemName: WeatherIconMapper.symbolName(for: iconCode, condition: condition))
            .symbolRenderingMode(.multicolor)
            .resizable()
            .scaledToFit()
            .foregroundStyle(theme.accent)
            .frame(width: size, height: size)
    }
}

enum WeatherIconMapper {
    static func symbolName(for iconCode: String?, condition: String?) -> String {
        guard let code = iconCode.flatMap(Int.init) else { return symbolFromCondition(condition) }

        switch code {
        case 100: return "sun.max.fill"
        case 101, 102, 103: return "cloud.sun.fill"
        case 104: return "cloud.fill"
        case 150: return "moon.stars.fill"
        case 151, 152, 153: return "cloud.moon.fill"
        case 300, 305, 309, 314: return "cloud.drizzle.fill"
        case 301, 306, 307, 315, 316, 350, 351, 399: return "cloud.rain.fill"
        case 308, 310, 311, 312, 317, 318: return "cloud.heavyrain.fill"
        case 302, 303: return "cloud.bolt.rain.fill"
        case 304, 313, 404, 405, 406: return "cloud.sleet.fill"
        case 400, 401, 407, 408, 409, 456, 457, 499: return "cloud.snow.fill"
        case 402, 403, 410: return "snowflake"
        case 500, 501, 502, 509, 510, 511, 512, 513, 514, 515: return "cloud.fog.fill"
        case 503, 504, 507, 508: return "wind"
        case 900: return "thermometer.sun.fill"
        case 901: return "thermometer.snowflake"
        default: return symbolFromCondition(condition)
        }
    }

    private static func symbolFromCondition(_ condition: String?) -> String {
        let text = condition ?? ""
        if text.contains("雷") { return "cloud.bolt.rain.fill" }
        if text.contains("雨") { return "cloud.rain.fill" }
        if text.contains("雪") { return "cloud.snow.fill" }
        if text.contains("雾") || text.contains("霾") || text.contains("沙") || text.contains("尘") { return "cloud.fog.fill" }
        if text.contains("晴") { return "sun.max.fill" }
        if text.contains("云") || text.contains("阴") { return "cloud.fill" }
        return "questionmark.circle.fill"
    }
}

private struct WeatherHeroTemperatureValue: View {
    let value: Double?
    let unit: TemperatureUnit
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(displayValue)
                .font(.system(size: 128 * scale, weight: .black, design: .monospaced))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()

            if value != nil {
                Text(unit == .celsius ? "°C" : "°F")
                    .font(.system(size: 64 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(theme.primaryText)
            }
        }
    }

    private var displayValue: String {
        guard let value else { return "N/A" }
        let converted = unit == .celsius ? value : value * 9 / 5 + 32
        return "\(Int(converted.rounded()))"
    }
}

private struct WeatherSetupPanel: View {
    let status: FeedStatus
    let config: AppConfig
    let snapshot: WeatherSnapshot
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        SectionPanel(title: "Weather", theme: theme, scale: scale) {
            VStack(alignment: .leading, spacing: 22 * scale) {
                StatusPill(title: status.title.uppercased(), color: theme.amber, scale: scale)

                Text("QWEATHER SETUP")
                    .font(.system(size: 68 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(theme.primaryText)

                Text(config.weather.location.name.isEmpty ? "LOCATION NOT SET" : config.weather.location.name.uppercased())
                    .font(.system(size: 30 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(theme.accent)

                VStack(alignment: .leading, spacing: 10 * scale) {
                    InlineMetricRow(label: "HOST", value: config.weather.qweather.apiHost.isEmpty ? "MISSING" : "READY", color: config.weather.qweather.apiHost.isEmpty ? theme.red : theme.green, scale: scale)
                    InlineMetricRow(label: "KID", value: hasKeyID ? "READY" : "MISSING", color: hasKeyID ? theme.green : theme.red, scale: scale)
                    InlineMetricRow(label: "SUB", value: hasProjectID ? "READY" : "MISSING", color: hasProjectID ? theme.green : theme.red, scale: scale)
                    InlineMetricRow(label: "KEY", value: hasPrivateKey ? "READY" : "MISSING", color: hasPrivateKey ? theme.green : theme.red, scale: scale)
                    InlineMetricRow(label: "CONFIG", value: "~/.glancepane/config.json", color: theme.secondaryText, scale: scale)
                }

                if let error = snapshot.errorMessage, !error.isEmpty {
                    Text(error.uppercased())
                        .font(.system(size: 16 * scale, weight: .black, design: .monospaced))
                        .foregroundStyle(theme.amber)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var hasKeyID: Bool { hasValue(config.weather.qweather.keyID, environment: "GLANCEPANE_QWEATHER_KID") }
    private var hasProjectID: Bool { hasValue(config.weather.qweather.projectID, environment: "GLANCEPANE_QWEATHER_PROJECT_ID") }

    private var hasPrivateKey: Bool {
        let path = environmentValue("GLANCEPANE_QWEATHER_PRIVATE_KEY_PATH", fallback: config.weather.qweather.privateKeyPath)
        return !path.isEmpty && FileManager.default.fileExists(atPath: expandedPath(path))
    }

    private func hasValue(_ value: String, environment: String) -> Bool {
        !environmentValue(environment, fallback: value).isEmpty
    }

    private func environmentValue(_ name: String, fallback: String) -> String {
        let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback.trimmingCharacters(in: .whitespacesAndNewlines) : value
    }

    private func expandedPath(_ path: String) -> String {
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") { return NSHomeDirectory() + String(path.dropFirst()) }
        return path
    }
}
