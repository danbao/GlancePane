import SwiftUI

struct AgentsPageView: View {
    let snapshot: CodexUsageSnapshot
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let gap = DashboardLayout.gap * scale
            let topHeight = max(0, (proxy.size.height - gap) * 0.56)
            let bottomHeight = max(0, proxy.size.height - gap - topHeight)
            let leftWidth = max(0, (proxy.size.width - gap) * 0.62)
            let rightWidth = max(0, proxy.size.width - gap - leftWidth)

            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    CodexCurrentSessionPanel(snapshot: snapshot, theme: theme, scale: scale)
                        .frame(width: leftWidth, height: topHeight)
                    CodexAllowancePanel(snapshot: snapshot, theme: theme, scale: scale)
                        .frame(width: rightWidth, height: topHeight)
                }
                HStack(spacing: gap) {
                    CodexActivityPanel(snapshot: snapshot, theme: theme, scale: scale)
                        .frame(width: leftWidth, height: bottomHeight)
                    CodexRecentSessionsPanel(snapshot: snapshot, theme: theme, scale: scale)
                        .frame(width: rightWidth, height: bottomHeight)
                }
            }
        }
    }
}

private struct CodexCurrentSessionPanel: View {
    let snapshot: CodexUsageSnapshot
    let theme: ScreenTheme
    let scale: CGFloat

    private var session: CodexSessionUsage? { snapshot.sessions.first }

    var body: some View {
        MonitorPanel(
            title: "Codex Context",
            status: session?.isActive == true ? "ACTIVE" : session == nil ? statusTitle : "IDLE",
            statusColor: session?.isActive == true ? theme.green : theme.secondaryText,
            theme: theme,
            scale: scale
        ) {
            if let session {
                VStack(alignment: .leading, spacing: 11 * scale) {
                    VStack(alignment: .leading, spacing: 2 * scale) {
                        Text(session.projectName)
                            .font(.system(size: 32 * scale, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(session.model.uppercased())
                            .font(.system(size: 18 * scale, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    HStack(alignment: .lastTextBaseline, spacing: 12 * scale) {
                        Text("\(session.contextPercent)%")
                            .font(.system(size: 100 * scale, weight: .bold, design: .monospaced))
                            .foregroundStyle(usageColor(session.contextFraction))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .monospacedDigit()
                        Text("CONTEXT")
                            .font(.system(size: 18 * scale, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.bottom, 12 * scale)
                    }

                    CodexProgressBar(fraction: session.contextFraction, color: usageColor(session.contextFraction), scale: scale)

                    HStack(spacing: 14 * scale) {
                        CodexSmallMetric(label: "INPUT", value: session.inputTokens.formattedTokenCount(), color: theme.blue, scale: scale)
                        CodexSmallMetric(label: "CACHED", value: session.cachedInputTokens.formattedTokenCount(), color: theme.green, scale: scale)
                        CodexSmallMetric(label: "OUTPUT", value: session.outputTokens.formattedTokenCount(), color: theme.amber, scale: scale)
                        CodexSmallMetric(label: "SESSION", value: session.sessionTotalTokens.formattedTokenCount(), color: theme.primaryText, scale: scale)
                    }

                    HStack(spacing: 6 * scale) {
                        Text("UPDATED")
                            .foregroundStyle(theme.secondaryText.opacity(0.65))
                        Text(session.updatedAt.formatted(.dateTime.hour().minute()))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .font(.system(size: DashboardTypography.status * scale, weight: .semibold, design: .monospaced))
                }
            } else {
                CodexEmptyState(
                    title: "NO RECENT SESSION",
                    detail: snapshot.message ?? "Start or resume a Codex task to see its context.",
                    theme: theme,
                    scale: scale
                )
            }
        }
    }

    private var statusTitle: String {
        switch snapshot.status {
        case .loading: return "CONNECTING"
        case .cached: return "CACHED"
        case .setup: return "SETUP"
        case .error: return "UNAVAILABLE"
        case .disabled: return "DISABLED"
        case .live: return "LIVE"
        }
    }

    private func usageColor(_ fraction: Double) -> Color {
        switch codexUsageSeverity(for: fraction) {
        case .normal: return theme.blue
        case .warning: return theme.amber
        case .critical: return theme.red
        }
    }
}

private struct CodexAllowancePanel: View {
    let snapshot: CodexUsageSnapshot
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        MonitorPanel(
            title: "Allowance",
            status: statusTitle,
            statusColor: statusColor,
            theme: theme,
            scale: scale
        ) {
            if snapshot.rateLimits?.isUnlimited == true {
                unlimitedContent
            } else if let limits = snapshot.rateLimits,
                      limits.primary != nil || limits.secondary != nil {
                limitedContent(limits)
            } else if let account = snapshot.account {
                accountOnlyContent(account)
            } else {
                CodexEmptyState(
                    title: snapshot.status == .loading ? "CONNECTING" : "USAGE UNAVAILABLE",
                    detail: snapshot.message ?? "Codex account data has not arrived yet.",
                    theme: theme,
                    scale: scale
                )
            }
        }
    }

    private var statusTitle: String? {
        switch snapshot.status {
        case .loading: return "CONNECTING"
        case .cached: return "CACHED"
        case .setup: return "SETUP"
        case .error: return "OFFLINE"
        case .disabled: return "DISABLED"
        case .live where snapshot.message != nil: return "PARTIAL"
        case .live:
            return snapshot.rateLimits?.planType?
                .replacingOccurrences(of: "_", with: " ")
                .uppercased()
        }
    }

    private var statusColor: Color {
        switch snapshot.status {
        case .cached:
            return theme.amber
        case .live where snapshot.message != nil:
            return theme.amber
        case .error, .setup:
            return theme.red
        case .disabled, .loading:
            return theme.secondaryText
        case .live:
            return theme.green
        }
    }

    private var unlimitedContent: some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            HStack(spacing: 10 * scale) {
                Image(systemName: "infinity")
                    .font(.system(size: 48 * scale, weight: .bold))
                    .foregroundStyle(theme.green)
                Text("UNLIMITED")
                    .font(.system(size: 31 * scale, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            if let account = snapshot.account {
                Text(account.todayTokens().formattedTokenCount())
                    .font(.system(size: 86 * scale, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .monospacedDigit()
                Text("TOKENS TODAY")
                    .font(.system(size: DashboardTypography.label * scale, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)

                HStack(spacing: 12 * scale) {
                    CodexSmallMetric(label: "LIFETIME", value: account.lifetimeTokens?.formattedTokenCount() ?? "N/A", color: theme.primaryText, scale: scale)
                    CodexSmallMetric(label: "STREAK", value: account.currentStreakDays.map { "\($0)D" } ?? "N/A", color: theme.amber, scale: scale)
                }
            }
        }
    }

    private func limitedContent(_ limits: CodexRateLimits) -> some View {
        VStack(alignment: .leading, spacing: 15 * scale) {
            if let primary = limits.primary {
                CodexLimitRow(window: primary, theme: theme, scale: scale)
            }
            if let secondary = limits.secondary {
                CodexLimitRow(window: secondary, theme: theme, scale: scale)
            }
            if let account = snapshot.account {
                HStack(spacing: 12 * scale) {
                    CodexSmallMetric(label: "TODAY", value: account.todayTokens().formattedTokenCount(), color: theme.accent, scale: scale)
                    CodexSmallMetric(label: "LIFETIME", value: account.lifetimeTokens?.formattedTokenCount() ?? "N/A", color: theme.primaryText, scale: scale)
                }
            }
        }
    }

    private func accountOnlyContent(_ account: CodexAccountUsage) -> some View {
        VStack(alignment: .leading, spacing: 14 * scale) {
            Text(account.todayTokens().formattedTokenCount())
                .font(.system(size: 86 * scale, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text("TOKENS TODAY")
                .font(.system(size: DashboardTypography.label * scale, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            HStack(spacing: 12 * scale) {
                CodexSmallMetric(label: "LIFETIME", value: account.lifetimeTokens?.formattedTokenCount() ?? "N/A", color: theme.primaryText, scale: scale)
                CodexSmallMetric(label: "PEAK", value: account.peakDailyTokens?.formattedTokenCount() ?? "N/A", color: theme.amber, scale: scale)
            }
        }
    }
}

private struct CodexActivityPanel: View {
    let snapshot: CodexUsageSnapshot
    let theme: ScreenTheme
    let scale: CGFloat

    private var values: [CodexDailyUsage] {
        snapshot.account?.recentDailyUsage(days: 14) ?? []
    }

    var body: some View {
        MonitorPanel(
            title: "14 Day Activity",
            status: snapshot.account.map { "TODAY \($0.todayTokens().formattedTokenCount())" },
            statusColor: theme.accent,
            theme: theme,
            scale: scale
        ) {
            if values.isEmpty {
                CodexEmptyState(title: "NO ACTIVITY DATA", detail: snapshot.message ?? "Waiting for Codex account usage.", theme: theme, scale: scale)
            } else {
                CodexDailyBarChart(values: values, theme: theme, scale: scale)
            }
        }
    }
}

private struct CodexRecentSessionsPanel: View {
    let snapshot: CodexUsageSnapshot
    let theme: ScreenTheme
    let scale: CGFloat

    private var sessions: [CodexSessionUsage] { Array(snapshot.sessions.dropFirst().prefix(2)) }

    var body: some View {
        MonitorPanel(
            title: "Recent Sessions",
            status: snapshot.sessions.isEmpty ? nil : "\(snapshot.sessions.count) FOUND",
            statusColor: theme.secondaryText,
            theme: theme,
            scale: scale
        ) {
            if sessions.isEmpty {
                CodexAccountFacts(account: snapshot.account, theme: theme, scale: scale)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        CodexRecentSessionRow(session: session, theme: theme, scale: scale)
                        if index < sessions.count - 1 {
                            Divider().overlay(theme.border).padding(.vertical, 10 * scale)
                        }
                    }
                }
            }
        }
    }
}

private struct CodexDailyBarChart: View {
    let values: [CodexDailyUsage]
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let maximum = max(1, values.map(\.tokens).max() ?? 1)
            HStack(alignment: .bottom, spacing: 8 * scale) {
                ForEach(Array(values.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 5 * scale) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2 * scale)
                            .fill(index == values.count - 1 ? theme.accent : theme.blue.opacity(0.72))
                            .frame(height: max(3 * scale, (proxy.size.height - 29 * scale) * CGFloat(Double(item.tokens) / Double(maximum))))
                        Text(dayLabel(item.date))
                            .font(.system(size: DashboardTypography.chartTick * scale, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.secondaryText.opacity(showsLabel(at: index) ? 0.9 : 0))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func dayLabel(_ date: String) -> String {
        String(date.suffix(2))
    }

    private func showsLabel(at index: Int) -> Bool {
        index.isMultiple(of: 2) == false || index == values.count - 1
    }
}

private struct CodexLimitRow: View {
    let window: CodexRateLimitWindow
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            HStack {
                Text(windowLabel)
                    .font(.system(size: DashboardTypography.label * scale, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.system(size: 28 * scale, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            CodexProgressBar(fraction: window.usedFraction, color: color, scale: scale)
            if let resetsAt = window.resetsAt {
                Text("RESETS \(resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    .font(.system(size: DashboardTypography.status * scale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.secondaryText.opacity(0.72))
            }
        }
    }

    private var windowLabel: String {
        switch window.durationMinutes {
        case 300: return "5 HOURS"
        case 10_080: return "7 DAYS"
        case .some(let minutes): return "\(minutes) MIN"
        case .none: return "ALLOWANCE"
        }
    }

    private var color: Color {
        switch codexUsageSeverity(for: window.usedFraction) {
        case .normal: return theme.green
        case .warning: return theme.amber
        case .critical: return theme.red
        }
    }
}

private struct CodexRecentSessionRow: View {
    let session: CodexSessionUsage
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            HStack(spacing: 8 * scale) {
                VStack(alignment: .leading, spacing: 2 * scale) {
                    Text(session.projectName)
                        .font(.system(size: DashboardTypography.body * scale, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(session.model.uppercased())
                        .font(.system(size: 15 * scale, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("\(session.contextPercent)%")
                    .font(.system(size: 32 * scale, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            CodexProgressBar(fraction: session.contextFraction, color: color, scale: scale)
            Text("SESSION \(session.sessionTotalTokens.formattedTokenCount())")
                .font(.system(size: DashboardTypography.status * scale, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.secondaryText.opacity(0.72))
        }
    }

    private var color: Color {
        switch codexUsageSeverity(for: session.contextFraction) {
        case .normal: return theme.blue
        case .warning: return theme.amber
        case .critical: return theme.red
        }
    }
}

private struct CodexAccountFacts: View {
    let account: CodexAccountUsage?
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        if let account {
            VStack(alignment: .leading, spacing: 13 * scale) {
                CodexFactRow(label: "PEAK DAY", value: account.peakDailyTokens?.formattedTokenCount() ?? "N/A", theme: theme, scale: scale)
                CodexFactRow(label: "CURRENT STREAK", value: account.currentStreakDays.map { "\($0) DAYS" } ?? "N/A", theme: theme, scale: scale)
                CodexFactRow(label: "LONGEST STREAK", value: account.longestStreakDays.map { "\($0) DAYS" } ?? "N/A", theme: theme, scale: scale)
                CodexFactRow(label: "LONGEST TURN", value: account.longestRunningTurnSeconds.map { TimeInterval($0).formattedUptime() } ?? "N/A", theme: theme, scale: scale)
            }
        } else {
            CodexEmptyState(title: "NO RECENT SESSIONS", detail: "Recent Codex contexts will appear here.", theme: theme, scale: scale)
        }
    }
}

private struct CodexFactRow: View {
    let label: String
    let value: String
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: DashboardTypography.status * scale, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: DashboardTypography.body * scale, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct CodexProgressBar: View {
    let fraction: Double
    let color: Color
    let scale: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }
        .frame(height: 11 * scale)
    }
}

private struct CodexSmallMetric: View {
    let label: String
    let value: String
    let color: Color
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            Text(label)
                .font(.system(size: DashboardTypography.status * scale, weight: .semibold))
                .foregroundStyle(color.opacity(0.9))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 26 * scale, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CodexEmptyState: View {
    let title: String
    let detail: String
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            Spacer(minLength: 0)
            Image(systemName: "terminal")
                .font(.system(size: 38 * scale, weight: .semibold))
                .foregroundStyle(theme.blue)
            Text(title)
                .font(.system(size: 32 * scale, weight: .bold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(detail)
                .font(.system(size: DashboardTypography.label * scale, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }
}
