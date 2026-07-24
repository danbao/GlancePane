import Foundation

enum CodexUsageStatus: String, Codable, Equatable {
    case disabled
    case loading
    case live
    case cached
    case setup
    case error
}

enum CodexUsageSeverity: Equatable {
    case normal
    case warning
    case critical
}

struct CodexUsageSnapshot: Codable, Equatable {
    var account: CodexAccountUsage?
    var rateLimits: CodexRateLimits?
    var sessions: [CodexSessionUsage]
    var status: CodexUsageStatus
    var message: String?
    var updatedAt: Date?

    static let empty = CodexUsageSnapshot(
        account: nil,
        rateLimits: nil,
        sessions: [],
        status: .loading,
        message: nil,
        updatedAt: nil
    )
}

struct CodexAccountUsage: Codable, Equatable {
    var lifetimeTokens: Int64?
    var peakDailyTokens: Int64?
    var longestRunningTurnSeconds: Int64?
    var currentStreakDays: Int64?
    var longestStreakDays: Int64?
    var dailyUsage: [CodexDailyUsage]

    func todayTokens(now: Date = Date(), calendar: Calendar = .current) -> Int64 {
        let key = CodexDailyUsage.dateKey(for: now, calendar: calendar)
        return dailyUsage.first(where: { $0.date == key })?.tokens ?? 0
    }

    func recentDailyUsage(days: Int, now: Date = Date(), calendar: Calendar = .current) -> [CodexDailyUsage] {
        let count = max(1, days)
        let values = Dictionary(uniqueKeysWithValues: dailyUsage.map { ($0.date, $0.tokens) })
        let startOfToday = calendar.startOfDay(for: now)

        return (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: startOfToday) else { return nil }
            let key = CodexDailyUsage.dateKey(for: date, calendar: calendar)
            return CodexDailyUsage(date: key, tokens: values[key] ?? 0)
        }
    }
}

struct CodexDailyUsage: Codable, Equatable, Identifiable {
    var date: String
    var tokens: Int64

    var id: String { date }

    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

struct CodexRateLimits: Codable, Equatable {
    var planType: String?
    var isUnlimited: Bool
    var hasCredits: Bool
    var creditBalance: String?
    var primary: CodexRateLimitWindow?
    var secondary: CodexRateLimitWindow?
}

struct CodexRateLimitWindow: Codable, Equatable {
    var usedPercent: Double
    var durationMinutes: Int64?
    var resetsAt: Date?

    var usedFraction: Double {
        min(1, max(0, usedPercent / 100))
    }
}

struct CodexSessionUsage: Codable, Equatable, Identifiable {
    var id: String
    var projectName: String
    var model: String
    var updatedAt: Date
    var contextTokens: Int64
    var contextWindow: Int64
    var inputTokens: Int64
    var cachedInputTokens: Int64
    var outputTokens: Int64
    var reasoningOutputTokens: Int64
    var sessionTotalTokens: Int64
    var isActive: Bool

    var contextFraction: Double {
        guard contextWindow > 0 else { return 0 }
        return min(1, max(0, Double(contextTokens) / Double(contextWindow)))
    }

    var contextPercent: Int {
        Int((contextFraction * 100).rounded())
    }

    var cacheFraction: Double {
        guard inputTokens > 0 else { return 0 }
        return min(1, max(0, Double(cachedInputTokens) / Double(inputTokens)))
    }
}

func codexUsageSeverity(for fraction: Double) -> CodexUsageSeverity {
    if fraction >= 0.85 { return .critical }
    if fraction >= 0.70 { return .warning }
    return .normal
}

extension Int64 {
    func formattedTokenCount() -> String {
        let value = Double(Swift.max(0, self))
        let units: [(threshold: Double, suffix: String)] = [
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "K")
        ]

        for unit in units where value >= unit.threshold {
            let scaled = value / unit.threshold
            let format = scaled >= 100 ? "%.0f%@" : scaled >= 10 ? "%.1f%@" : "%.2f%@"
            return String(format: format, scaled, unit.suffix)
        }

        return String(Int64(value))
    }
}
