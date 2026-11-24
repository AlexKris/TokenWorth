import Foundation
import Testing
@testable import TokenWorthCore

@Suite("UsageAggregator & DemoDataFactory")
struct UsageAggregatorTests {
    @Test("Aggregates multi-provider events by time range, model, daily bucket, and ROI")
    func aggregatesRangesAndROI() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-11-24T12:00:00Z")!

        let accounts = [
            AccountProfile(id: "c1", provider: .claude, displayName: "Claude", planName: "Max", monthlySubscriptionUSD: 100),
            AccountProfile(id: "x1", provider: .codex, displayName: "Codex", planName: "Pro", monthlySubscriptionUSD: 20)
        ]

        let events = [
            UsageEvent(
                id: "e1",
                provider: .claude,
                accountID: "c1",
                model: "claude-opus-4-6",
                timestamp: now.addingTimeInterval(-3600), // today
                tokens: TokenCounts(input: 100_000, output: 20_000, cacheRead: 1_000_000, cacheWrite: 0)
            ),
            UsageEvent(
                id: "e2",
                provider: .codex,
                accountID: "x1",
                model: "gpt-5.3-codex",
                timestamp: now.addingTimeInterval(-3 * 86400), // 3 days ago
                tokens: TokenCounts(input: 1_000_000, output: 100_000)
            ),
            UsageEvent(
                id: "e3",
                provider: .claude,
                accountID: "c1",
                model: "claude-opus-4-6",
                timestamp: now.addingTimeInterval(-20 * 86400), // 20 days ago
                tokens: TokenCounts(input: 500_000, output: 50_000)
            )
        ]

        let agg = UsageAggregator()

        let today = agg.summarize(events: events, accounts: accounts, range: .today, now: now, calendar: calendar)
        #expect(today.eventCount == 1)
        // Opus 4.6: 0.1M*$5 + 0.02M*$25 + 1.0M*$0.50 = $0.50 + $0.50 + $0.50 = $1.50
        #expect(abs(today.totalCost.totalUSD - 1.50) < 0.0001)
        // Cache savings: 1.0M * ($5.00 - $0.50) = $4.50
        #expect(abs(today.totalCost.cacheSavingsUSD - 4.50) < 0.0001)

        let sevenDays = agg.summarize(events: events, accounts: accounts, range: .last7Days, now: now, calendar: calendar)
        #expect(sevenDays.eventCount == 2)
        #expect(sevenDays.dailySeries.count == 2)
        #expect(sevenDays.byModel.count == 2)

        let thirtyDays = agg.summarize(events: events, accounts: accounts, range: .last30Days, now: now, calendar: calendar)
        #expect(thirtyDays.eventCount == 3)
        #expect(thirtyDays.roiMultiple != nil)
    }

    @Test("DemoDataFactory yields valid quota cards and 14-day events")
    func demoFactoryIntegrity() {
        let now = Date()
        let accounts = DemoDataFactory.demoAccounts()
        let snapshots = DemoDataFactory.demoQuotaSnapshots(for: accounts, now: now)
        let events = DemoDataFactory.demoUsageEvents(accounts: accounts, now: now)

        #expect(accounts.count == 5)
        #expect(snapshots.count == 5)
        #expect(events.count == 70)

        let summary = UsageAggregator().summarize(events: events, accounts: accounts, range: .last30Days, now: now)
        #expect(summary.totalCost.totalUSD > 10)
        #expect(summary.byProvider.count == 4)
        #expect(summary.dailySeries.count == 14)
    }
}
