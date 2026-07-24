import Foundation
import SwiftUI

enum DashboardLayout {
    static let referenceSize = CGSize(width: 1280, height: 720)
    static let panelCornerRadius: CGFloat = 8
    static let pagePadding: CGFloat = 14
    static let gap: CGFloat = 12
    static let panelHorizontalPadding: CGFloat = 16
    static let panelVerticalPadding: CGFloat = 14
}

enum DashboardTypography {
    static let panelTitle: CGFloat = 20
    static let status: CGFloat = 16
    static let label: CGFloat = 18
    static let body: CGFloat = 20
    static let metric: CGFloat = 24
    static let chartTick: CGFloat = 16
    static let attribution: CGFloat = 12
}

struct SectionPanel<Content: View>: View {
    let title: String
    let theme: ScreenTheme
    let scale: CGFloat
    let content: Content

    init(title: String, theme: ScreenTheme, scale: CGFloat, @ViewBuilder content: () -> Content) {
        self.title = title
        self.theme = theme
        self.scale = scale
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardLayout.gap * scale) {
            Text(title.uppercased())
                .font(.system(size: DashboardTypography.panelTitle * scale, weight: .black, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            content
        }
        .padding(.horizontal, DashboardLayout.panelHorizontalPadding * scale)
        .padding(.vertical, DashboardLayout.panelVerticalPadding * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: DashboardLayout.panelCornerRadius * scale)
                .stroke(theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.panelCornerRadius * scale))
    }
}

struct InlineMetricPair: View {
    let label: String
    let value: String
    let color: Color
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            Text(label)
                .font(.system(size: DashboardTypography.label * scale, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
            Text(value)
                .font(.system(size: DashboardTypography.metric * scale, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InlineMetricRow: View {
    let label: String
    let value: String
    let color: Color
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 10 * scale) {
            Text(label)
                .font(.system(size: DashboardTypography.label * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .frame(width: 82 * scale, alignment: .leading)
                .lineLimit(1)
            Text(value)
                .font(.system(size: DashboardTypography.metric * scale, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
        }
    }
}

struct StatusPill: View {
    let title: String
    let color: Color
    let scale: CGFloat

    var body: some View {
        Text(title)
            .font(.system(size: DashboardTypography.status * scale, weight: .black, design: .rounded))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 11 * scale)
            .padding(.vertical, 7 * scale)
            .background(color.opacity(0.12))
            .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 1))
            .clipShape(Capsule())
    }
}

struct MonitorPanel<Content: View>: View {
    let title: String
    let status: String?
    let statusColor: Color
    let theme: ScreenTheme
    let scale: CGFloat
    let content: Content

    init(
        title: String,
        status: String? = nil,
        statusColor: Color = .secondary,
        theme: ScreenTheme,
        scale: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.status = status
        self.statusColor = statusColor
        self.theme = theme
        self.scale = scale
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardLayout.gap * scale) {
            HStack(spacing: 8 * scale) {
                Text(title.uppercased())
                    .font(.system(size: DashboardTypography.panelTitle * scale, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let status {
                    Text(status)
                        .font(.system(size: DashboardTypography.status * scale, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
            }
            content
        }
        .padding(.horizontal, DashboardLayout.panelHorizontalPadding * scale)
        .padding(.vertical, DashboardLayout.panelVerticalPadding * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: DashboardLayout.panelCornerRadius * scale)
                .stroke(statusColor.opacity(status == nil ? 0 : 0.35), lineWidth: status == nil ? 0 : 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardLayout.panelCornerRadius * scale)
                .stroke(theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.panelCornerRadius * scale))
    }
}

struct MonitorHeroValue: View {
    let value: String
    let size: CGFloat
    let color: Color
    let scale: CGFloat

    var body: some View {
        Text(value)
            .font(.system(size: size * scale, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .monospacedDigit()
    }
}

struct HistorySparkline: View {
    let primary: [Double?]
    let secondary: [Double?]
    let primaryColor: Color
    let secondaryColor: Color
    let fixedMaximum: Double?

    init(
        primary: [Double?],
        secondary: [Double?] = [],
        primaryColor: Color,
        secondaryColor: Color = .clear,
        fixedMaximum: Double? = nil
    ) {
        self.primary = primary
        self.secondary = secondary
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.fixedMaximum = fixedMaximum
    }

    var body: some View {
        Canvas { context, size in
            let count = max(primary.count, secondary.count)
            guard count > 1 else {
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: size.height - 1))
                baseline.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                context.stroke(baseline, with: .color(.white.opacity(0.08)), lineWidth: 1)
                return
            }

            for fraction in [0.25, 0.5, 0.75] {
                var grid = Path()
                let y = size.height * fraction
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(.white.opacity(0.045)), lineWidth: 1)
            }

            let values = (primary + secondary).compactMap { $0 }
            let dynamicMaximum = max(values.max() ?? 0, 0.000_001) * 1.12
            let maximum = max(fixedMaximum ?? dynamicMaximum, 0.000_001)
            draw(primary, color: primaryColor, maximum: maximum, count: count, context: &context, size: size)
            draw(secondary, color: secondaryColor, maximum: maximum, count: count, context: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    private func draw(
        _ values: [Double?],
        color: Color,
        maximum: Double,
        count: Int,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        guard !values.isEmpty else { return }
        var path = Path()
        var hasCurrentSegment = false
        for index in 0..<count {
            guard values.indices.contains(index), let value = values[index] else {
                hasCurrentSegment = false
                continue
            }
            let x = size.width * CGFloat(index) / CGFloat(max(1, count - 1))
            let normalized = min(1, max(0, value / maximum))
            let point = CGPoint(x: x, y: size.height * (1 - normalized))
            if hasCurrentSegment {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                hasCurrentSegment = true
            }
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

struct ScreenTheme {
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let green: Color
    let red: Color
    let amber: Color
    let blue: Color
    let border: Color
    let panelBackground: Color
    let tileBackground: Color
    let background: LinearGradient

    init(themeName: ThemeName) {
        switch themeName {
        case .midnight:
            primaryText = Color(red: 0.94, green: 0.98, blue: 0.96)
            secondaryText = Color(red: 0.55, green: 0.65, blue: 0.68)
            accent = Color(red: 0.11, green: 0.86, blue: 0.72)
            green = Color(red: 0.18, green: 0.85, blue: 0.45)
            red = Color(red: 0.98, green: 0.28, blue: 0.32)
            amber = Color(red: 1.00, green: 0.68, blue: 0.22)
            blue = Color(red: 0.36, green: 0.65, blue: 1.00)
            border = Color.white.opacity(0.13)
            panelBackground = Color(red: 0.05, green: 0.07, blue: 0.075).opacity(0.96)
            tileBackground = Color.white.opacity(0.055)
            background = LinearGradient(
                colors: [Color.black, Color(red: 0.02, green: 0.06, blue: 0.055), Color(red: 0.08, green: 0.055, blue: 0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .graphite:
            primaryText = Color(red: 0.95, green: 0.95, blue: 0.92)
            secondaryText = Color(red: 0.64, green: 0.66, blue: 0.63)
            accent = Color(red: 0.86, green: 0.88, blue: 0.58)
            green = Color(red: 0.26, green: 0.80, blue: 0.42)
            red = Color(red: 0.95, green: 0.25, blue: 0.30)
            amber = Color(red: 0.95, green: 0.72, blue: 0.24)
            blue = Color(red: 0.45, green: 0.66, blue: 0.88)
            border = Color.white.opacity(0.14)
            panelBackground = Color(red: 0.075, green: 0.075, blue: 0.07).opacity(0.96)
            tileBackground = Color.white.opacity(0.06)
            background = LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.08, blue: 0.075), Color(red: 0.12, green: 0.105, blue: 0.065)],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
        case .terminal:
            primaryText = Color(red: 0.80, green: 1.0, blue: 0.82)
            secondaryText = Color(red: 0.42, green: 0.68, blue: 0.45)
            accent = Color(red: 0.28, green: 1.0, blue: 0.44)
            green = Color(red: 0.28, green: 1.0, blue: 0.44)
            red = Color(red: 1.0, green: 0.32, blue: 0.32)
            amber = Color(red: 0.92, green: 0.78, blue: 0.30)
            blue = Color(red: 0.42, green: 0.82, blue: 0.95)
            border = Color.green.opacity(0.18)
            panelBackground = Color(red: 0.015, green: 0.045, blue: 0.025).opacity(0.97)
            tileBackground = Color.green.opacity(0.035)
            background = LinearGradient(
                colors: [Color.black, Color(red: 0.01, green: 0.045, blue: 0.02), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

func temperature(_ value: Double?) -> String {
    guard let value else { return "N/A" }
    return "\(Int(value.rounded()))°C"
}

func percent(_ value: Double?) -> String {
    guard let value else { return "N/A" }
    return "\(Int(value.rounded()))%"
}

func rain(_ value: Double?) -> String {
    guard let value else { return "N/A" }
    if value >= 10 { return String(format: "%.0fMM", value) }
    if value >= 1 { return String(format: "%.1fMM", value) }
    return String(format: "%.2fMM", value)
}

extension DateFormatter {
    static func cached(format: String) -> DateFormatter {
        let key = "GlancePane.DateFormatter.\(format)" as NSString
        if let existing = Thread.current.threadDictionary[key] as? DateFormatter {
            return existing
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        Thread.current.threadDictionary[key] = formatter
        return formatter
    }
}

extension UInt64 {
    func formattedBytes() -> String {
        ByteCountFormatter.glanceDeckFormatter.string(fromByteCount: Int64(self))
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Double {
    func formattedBytesPerSecond() -> String {
        let value = max(0, self)
        if value < 1 { return "0 KB/s" }
        return "\(ByteCountFormatter.glanceDeckFormatter.string(fromByteCount: Int64(value)))/s"
    }

    func formattedDataRate(unit: DataRateUnit) -> String {
        switch unit {
        case .bytes:
            return formattedBytesPerSecond()
        case .bits:
            let bits = max(0, self) * 8
            if bits >= 1_000_000_000 { return String(format: "%.1f Gb/s", bits / 1_000_000_000) }
            if bits >= 1_000_000 { return String(format: "%.1f Mb/s", bits / 1_000_000) }
            if bits >= 1_000 { return String(format: "%.0f Kb/s", bits / 1_000) }
            return "\(Int(bits.rounded())) b/s"
        }
    }

    func formattedTemperature(unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius:
            return "\(Int(rounded()))°C"
        case .fahrenheit:
            return "\(Int((self * 9 / 5 + 32).rounded()))°F"
        }
    }

    func formattedPrice() -> String {
        let fractionDigits = self >= 1000 ? 0 : self >= 100 ? 1 : 2
        return formatted(
            .number
                .grouping(.automatic)
                .precision(.fractionLength(fractionDigits))
        )
    }

    func formattedPercent() -> String {
        String(format: "%.2f%%", self)
    }
}

extension TimeInterval {
    func formattedUptime() -> String {
        let totalMinutes = max(0, Int(self / 60))
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)D \(hours)H" }
        if hours > 0 { return "\(hours)H \(minutes)M" }
        return "\(minutes)M"
    }
}

extension ByteCountFormatter {
    static let glanceDeckFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}
