import Foundation

public struct QuotaWindow: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var label: String
    public var durationSeconds: TimeInterval
    public var usedPercent: Double
    public var resetsAt: Date?

    public init(
        id: String,
        label: String,
        durationSeconds: TimeInterval,
        usedPercent: Double,
        resetsAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.durationSeconds = durationSeconds
        self.usedPercent = min(max(usedPercent, 0), 100)
        self.resetsAt = resetsAt
    }

    public func pacePercent(at now: Date = Date()) -> Double? {
        guard let resetsAt, durationSeconds > 0 else { return nil }
        let windowStart = resetsAt.addingTimeInterval(-durationSeconds)
        let elapsed = now.timeIntervalSince(windowStart)
        let ratio = (elapsed / durationSeconds) * 100.0
        return min(max(ratio, 0.0), 100.0)
    }

    public func resetSummary(at now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let resetsAt else { return "reset unknown" }
        let remainingSeconds = max(0, resetsAt.timeIntervalSince(now))
        let totalMinutes = Int(remainingSeconds / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if days >= 1 {
            formatter.dateFormat = "MMM d HH:mm"
            return "resets \(days)d \(hours)h · \(formatter.string(from: resetsAt))"
        } else if hours >= 1 {
            formatter.dateFormat = "HH:mm"
            return "resets \(hours)h \(minutes)m · \(formatter.string(from: resetsAt))"
        } else if minutes > 0 {
            formatter.dateFormat = "HH:mm"
            return "resets \(minutes)m · \(formatter.string(from: resetsAt))"
        } else {
            formatter.dateFormat = "HH:mm"
            return "resets soon · \(formatter.string(from: resetsAt))"
        }
    }
}

public struct QuotaGroup: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var windows: [QuotaWindow]

    public init(id: String, title: String, windows: [QuotaWindow]) {
        self.id = id
        self.title = title
        self.windows = windows
    }
}

public enum QuotaFetchStatus: Codable, Sendable, Equatable {
    case live
    case cached
    case demo
    case notConfigured(String)
    case error(String)

    public var isHealthy: Bool {
        switch self {
        case .live, .cached, .demo:
            return true
        case .notConfigured, .error:
            return false
        }
    }

    public var statusMessage: String? {
        switch self {
        case .live:
            return nil
        case .cached:
            return "Using cached quota (rate-limit/offline)"
        case .demo:
            return "Demo data"
        case .notConfigured(let reason):
            return reason
        case .error(let message):
            return message
        }
    }
}

public struct AccountQuotaSnapshot: Codable, Sendable, Identifiable, Equatable {
    public var id: String { accountID }
    public var accountID: String
    public var provider: ProviderID
    public var planName: String?
    public var groups: [QuotaGroup]
    public var extraUsageUSD: Double?
    public var extraUsageLimitUSD: Double?
    public var fetchedAt: Date
    public var status: QuotaFetchStatus

    public init(
        accountID: String,
        provider: ProviderID,
        planName: String? = nil,
        groups: [QuotaGroup] = [],
        extraUsageUSD: Double? = nil,
        extraUsageLimitUSD: Double? = nil,
        fetchedAt: Date = Date(),
        status: QuotaFetchStatus
    ) {
        self.accountID = accountID
        self.provider = provider
        self.planName = planName
        self.groups = groups
        self.extraUsageUSD = extraUsageUSD
        self.extraUsageLimitUSD = extraUsageLimitUSD
        self.fetchedAt = fetchedAt
        self.status = status
    }

    public var maxUsedPercent: Double {
        groups.flatMap(\.windows).map(\.usedPercent).max() ?? 0
    }
}
