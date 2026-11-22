import Foundation

public enum ThresholdLevel: String, Sendable, Equatable {
    case normal   // < 65%
    case warning  // 65% ..< 85%
    case critical // >= 85%

    public static func forFraction(_ fraction: Double) -> ThresholdLevel {
        if fraction >= 0.85 {
            return .critical
        } else if fraction >= 0.65 {
            return .warning
        } else {
            return .normal
        }
    }
}

public struct CostUsageResponse: Decodable, Sendable, Equatable {
    public let usage: Double
    public let limit: Double
    public let currency: String?
    public let asOf: String?

    public init(usage: Double, limit: Double, currency: String? = nil, asOf: String? = nil) {
        self.usage = usage
        self.limit = limit
        self.currency = currency
        self.asOf = asOf
    }
}

public struct UsageSnapshot: Sendable, Equatable {
    public let usage: Double
    public let limit: Double
    public let fetchedAt: Date

    public init(usage: Double, limit: Double, fetchedAt: Date = Date()) {
        self.usage = usage
        self.limit = limit
        self.fetchedAt = fetchedAt
    }

    public init(response: CostUsageResponse, fetchedAt: Date = Date()) {
        self.usage = response.usage
        self.limit = response.limit
        self.fetchedAt = fetchedAt
    }

    /// Unclamped usage ratio (`usage / limit`). Returns 0 if `limit <= 0`.
    public var fraction: Double {
        guard limit > 0 else { return 0 }
        return max(0, usage / limit)
    }

    /// Clamped usage ratio in `0.0 ... 1.0` for visual progress rendering.
    public var clampedFraction: Double {
        min(max(fraction, 0), 1)
    }

    /// Usage percentage (e.g. `96.5` for `0.965`).
    public var percentage: Double {
        fraction * 100.0
    }

    /// Remaining budget (`limit - usage`). Negative when over limit.
    public var remaining: Double {
        limit - usage
    }

    public var isOverLimit: Bool {
        usage > limit
    }

    public var thresholdLevel: ThresholdLevel {
        ThresholdLevel.forFraction(fraction)
    }

    public var formattedUsage: String {
        Self.formatUSD(usage)
    }

    public var formattedLimit: String {
        Self.formatUSD(limit)
    }

    public var formattedPercentage: String {
        String(format: "%.1f%%", locale: Self.posixLocale, percentage)
    }

    public var formattedRemaining: String {
        Self.formatUSD(abs(remaining))
    }

    public var remainingLine: String {
        if isOverLimit {
            return "Over limit: \(formattedRemaining)"
        } else {
            return "Remaining: \(formattedRemaining)"
        }
    }

    public var tooltipSummary: String {
        "ELM API: \(formattedUsage) / \(formattedLimit) (\(formattedPercentage)) — \(remainingLine)"
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    public static func formatUSD(_ value: Double) -> String {
        let sign = value < 0 ? "-" : ""
        return "\(sign)$\(String(format: "%.2f", locale: posixLocale, abs(value)))"
    }
}
