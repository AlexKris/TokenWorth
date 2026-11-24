import Foundation

public struct TokenCounts: Codable, Sendable, Equatable {
    /// Uncached input tokens billed at standard input rate.
    public var input: Int
    /// Total billable output tokens (includes reasoning/thinking when billed at output rate).
    public var output: Int
    /// Cached prompt input read tokens billed at cache-read rate.
    public var cacheRead: Int
    /// Prompt cache creation tokens billed at cache-write rate.
    public var cacheWrite: Int
    /// Informational subset of `output` used for internal reasoning/thinking (never billed twice).
    public var reasoning: Int

    public init(
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheWrite: Int = 0,
        reasoning: Int = 0
    ) {
        self.input = max(0, input)
        self.output = max(0, output)
        self.cacheRead = max(0, cacheRead)
        self.cacheWrite = max(0, cacheWrite)
        self.reasoning = max(0, reasoning)
    }

    public static let zero = TokenCounts()

    public var total: Int {
        input + cacheRead + cacheWrite + output
    }

    public var totalInputSide: Int {
        input + cacheRead + cacheWrite
    }

    public var cacheHitRate: Double {
        let denom = totalInputSide
        guard denom > 0 else { return 0 }
        return Double(cacheRead) / Double(denom)
    }

    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            reasoning: lhs.reasoning + rhs.reasoning
        )
    }
}

public struct UsageEvent: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var provider: ProviderID
    public var accountID: String
    public var model: String
    public var timestamp: Date
    public var tokens: TokenCounts
    public var sessionID: String?
    public var sourceFile: String?

    public init(
        id: String,
        provider: ProviderID,
        accountID: String,
        model: String,
        timestamp: Date,
        tokens: TokenCounts,
        sessionID: String? = nil,
        sourceFile: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.accountID = accountID
        self.model = model
        self.timestamp = timestamp
        self.tokens = tokens
        self.sessionID = sessionID
        self.sourceFile = sourceFile
    }
}

public struct CostBreakdown: Codable, Sendable, Equatable {
    public var inputUSD: Double
    public var outputUSD: Double
    public var cacheReadUSD: Double
    public var cacheWriteUSD: Double
    public var cacheSavingsUSD: Double
    public var isEstimatedOrUnpriced: Bool

    public init(
        inputUSD: Double = 0,
        outputUSD: Double = 0,
        cacheReadUSD: Double = 0,
        cacheWriteUSD: Double = 0,
        cacheSavingsUSD: Double = 0,
        isEstimatedOrUnpriced: Bool = false
    ) {
        self.inputUSD = inputUSD
        self.outputUSD = outputUSD
        self.cacheReadUSD = cacheReadUSD
        self.cacheWriteUSD = cacheWriteUSD
        self.cacheSavingsUSD = cacheSavingsUSD
        self.isEstimatedOrUnpriced = isEstimatedOrUnpriced
    }

    public static let zero = CostBreakdown()

    public var totalUSD: Double {
        inputUSD + outputUSD + cacheReadUSD + cacheWriteUSD
    }

    public static func + (lhs: CostBreakdown, rhs: CostBreakdown) -> CostBreakdown {
        CostBreakdown(
            inputUSD: lhs.inputUSD + rhs.inputUSD,
            outputUSD: lhs.outputUSD + rhs.outputUSD,
            cacheReadUSD: lhs.cacheReadUSD + rhs.cacheReadUSD,
            cacheWriteUSD: lhs.cacheWriteUSD + rhs.cacheWriteUSD,
            cacheSavingsUSD: lhs.cacheSavingsUSD + rhs.cacheSavingsUSD,
            isEstimatedOrUnpriced: lhs.isEstimatedOrUnpriced || rhs.isEstimatedOrUnpriced
        )
    }
}

public enum TimeRange: String, CaseIterable, Codable, Sendable, Identifiable {
    case today
    case last7Days = "7d"
    case last30Days = "30d"
    case allTime = "all"

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .today: return "Today"
        case .last7Days: return "7D"
        case .last30Days: return "30D"
        case .allTime: return "All"
        }
    }

    public func startDate(relativeTo now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return startOfToday
        case .last7Days:
            return calendar.date(byAdding: .day, value: -6, to: startOfToday)
        case .last30Days:
            return calendar.date(byAdding: .day, value: -29, to: startOfToday)
        case .allTime:
            return nil
        }
    }
}

public struct ModelUsageRow: Codable, Sendable, Identifiable, Equatable {
    public var id: String { "\(provider.rawValue):\(model)" }
    public var provider: ProviderID
    public var model: String
    public var eventCount: Int
    public var tokens: TokenCounts
    public var cost: CostBreakdown

    public init(
        provider: ProviderID,
        model: String,
        eventCount: Int,
        tokens: TokenCounts,
        cost: CostBreakdown
    ) {
        self.provider = provider
        self.model = model
        self.eventCount = eventCount
        self.tokens = tokens
        self.cost = cost
    }
}

public struct DailyProviderCost: Codable, Sendable, Identifiable, Equatable {
    public var id: String { provider.rawValue }
    public var provider: ProviderID
    public var tokens: TokenCounts
    public var costUSD: Double

    public init(provider: ProviderID, tokens: TokenCounts, costUSD: Double) {
        self.provider = provider
        self.tokens = tokens
        self.costUSD = costUSD
    }
}

public struct DailyUsagePoint: Codable, Sendable, Identifiable, Equatable {
    public var id: String { dateKey }
    public var dateKey: String
    public var date: Date
    public var tokens: TokenCounts
    public var cost: CostBreakdown
    public var providerBreakdown: [DailyProviderCost]

    public init(
        dateKey: String,
        date: Date,
        tokens: TokenCounts,
        cost: CostBreakdown,
        providerBreakdown: [DailyProviderCost]
    ) {
        self.dateKey = dateKey
        self.date = date
        self.tokens = tokens
        self.cost = cost
        self.providerBreakdown = providerBreakdown
    }
}

public struct ProviderUsageRow: Codable, Sendable, Identifiable, Equatable {
    public var id: String { provider.rawValue }
    public var provider: ProviderID
    public var eventCount: Int
    public var tokens: TokenCounts
    public var cost: CostBreakdown
    public var monthlySubscriptionUSD: Double
    public var roiMultiple: Double?

    public init(
        provider: ProviderID,
        eventCount: Int,
        tokens: TokenCounts,
        cost: CostBreakdown,
        monthlySubscriptionUSD: Double,
        roiMultiple: Double?
    ) {
        self.provider = provider
        self.eventCount = eventCount
        self.tokens = tokens
        self.cost = cost
        self.monthlySubscriptionUSD = monthlySubscriptionUSD
        self.roiMultiple = roiMultiple
    }
}

public struct AccountUsageRow: Codable, Sendable, Identifiable, Equatable {
    public var id: String { accountID }
    public var accountID: String
    public var provider: ProviderID
    public var eventCount: Int
    public var tokens: TokenCounts
    public var cost: CostBreakdown

    public init(
        accountID: String,
        provider: ProviderID,
        eventCount: Int,
        tokens: TokenCounts,
        cost: CostBreakdown
    ) {
        self.accountID = accountID
        self.provider = provider
        self.eventCount = eventCount
        self.tokens = tokens
        self.cost = cost
    }
}

public struct UsageSummary: Codable, Sendable, Equatable {
    public var range: TimeRange
    public var generatedAt: Date
    public var eventCount: Int
    public var totalTokens: TokenCounts
    public var totalCost: CostBreakdown
    public var totalMonthlySubscriptionUSD: Double
    public var roiMultiple: Double?
    public var byProvider: [ProviderUsageRow]
    public var byAccount: [AccountUsageRow]
    public var byModel: [ModelUsageRow]
    public var dailySeries: [DailyUsagePoint]

    public init(
        range: TimeRange,
        generatedAt: Date = Date(),
        eventCount: Int = 0,
        totalTokens: TokenCounts = .zero,
        totalCost: CostBreakdown = .zero,
        totalMonthlySubscriptionUSD: Double = 0,
        roiMultiple: Double? = nil,
        byProvider: [ProviderUsageRow] = [],
        byAccount: [AccountUsageRow] = [],
        byModel: [ModelUsageRow] = [],
        dailySeries: [DailyUsagePoint] = []
    ) {
        self.range = range
        self.generatedAt = generatedAt
        self.eventCount = eventCount
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.totalMonthlySubscriptionUSD = totalMonthlySubscriptionUSD
        self.roiMultiple = roiMultiple
        self.byProvider = byProvider
        self.byAccount = byAccount
        self.byModel = byModel
        self.dailySeries = dailySeries
    }
}
