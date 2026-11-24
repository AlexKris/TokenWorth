import Foundation

public struct UsageAggregator: Sendable {
    public let calculator: CostCalculator

    public init(calculator: CostCalculator = CostCalculator()) {
        self.calculator = calculator
    }

    public func summarize(
        events: [UsageEvent],
        accounts: [AccountProfile],
        range: TimeRange,
        providerFilter: ProviderID? = nil,
        accountFilter: String? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsageSummary {
        let cutoff = range.startDate(relativeTo: now, calendar: calendar)

        let filtered = events.filter { event in
            if let cutoff, event.timestamp < cutoff {
                return false
            }
            if let providerFilter, event.provider != providerFilter {
                return false
            }
            if let accountFilter, event.accountID != accountFilter {
                return false
            }
            return true
        }

        let matchingAccounts = accounts.filter { acct in
            if let providerFilter, acct.provider != providerFilter { return false }
            if let accountFilter, acct.id != accountFilter { return false }
            return true
        }

        var monthlySubByProvider: [ProviderID: Double] = [:]
        var totalMonthlySub = 0.0
        for acct in matchingAccounts {
            let fee = acct.monthlySubscriptionUSD ?? 0.0
            monthlySubByProvider[acct.provider, default: 0.0] += fee
            totalMonthlySub += fee
        }

        var totalTokens = TokenCounts.zero
        var totalCost = CostBreakdown.zero

        struct ProviderAcc {
            var count = 0
            var tokens = TokenCounts.zero
            var cost = CostBreakdown.zero
        }
        var providerMap: [ProviderID: ProviderAcc] = [:]

        struct AccountAcc {
            var provider: ProviderID
            var count = 0
            var tokens = TokenCounts.zero
            var cost = CostBreakdown.zero
        }
        var accountMap: [String: AccountAcc] = [:]

        struct ModelKey: Hashable {
            let provider: ProviderID
            let model: String
        }
        struct ModelAcc {
            var count = 0
            var tokens = TokenCounts.zero
            var cost = CostBreakdown.zero
        }
        var modelMap: [ModelKey: ModelAcc] = [:]

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        struct DayAcc {
            var date: Date
            var tokens = TokenCounts.zero
            var cost = CostBreakdown.zero
            var byProvider: [ProviderID: (TokenCounts, Double)] = [:]
        }
        var dayMap: [String: DayAcc] = [:]

        for event in filtered {
            let cost = calculator.cost(for: event)
            totalTokens = totalTokens + event.tokens
            totalCost = totalCost + cost

            var pAcc = providerMap[event.provider] ?? ProviderAcc()
            pAcc.count += 1
            pAcc.tokens = pAcc.tokens + event.tokens
            pAcc.cost = pAcc.cost + cost
            providerMap[event.provider] = pAcc

            var aAcc = accountMap[event.accountID] ?? AccountAcc(provider: event.provider)
            aAcc.count += 1
            aAcc.tokens = aAcc.tokens + event.tokens
            aAcc.cost = aAcc.cost + cost
            accountMap[event.accountID] = aAcc

            let mKey = ModelKey(provider: event.provider, model: event.model)
            var mAcc = modelMap[mKey] ?? ModelAcc()
            mAcc.count += 1
            mAcc.tokens = mAcc.tokens + event.tokens
            mAcc.cost = mAcc.cost + cost
            modelMap[mKey] = mAcc

            let dayStart = calendar.startOfDay(for: event.timestamp)
            let dayKey = dateFormatter.string(from: dayStart)
            var dAcc = dayMap[dayKey] ?? DayAcc(date: dayStart)
            dAcc.tokens = dAcc.tokens + event.tokens
            dAcc.cost = dAcc.cost + cost
            let existingProv = dAcc.byProvider[event.provider] ?? (.zero, 0.0)
            dAcc.byProvider[event.provider] = (existingProv.0 + event.tokens, existingProv.1 + cost.totalUSD)
            dayMap[dayKey] = dAcc
        }

        let byProvider: [ProviderUsageRow] = providerMap.map { provider, acc in
            let subFee = monthlySubByProvider[provider] ?? 0
            let roi = subFee > 0 ? (acc.cost.totalUSD / subFee) : nil
            return ProviderUsageRow(
                provider: provider,
                eventCount: acc.count,
                tokens: acc.tokens,
                cost: acc.cost,
                monthlySubscriptionUSD: subFee,
                roiMultiple: roi
            )
        }
        .sorted {
            if $0.cost.totalUSD != $1.cost.totalUSD {
                return $0.cost.totalUSD > $1.cost.totalUSD
            }
            return $0.tokens.total > $1.tokens.total
        }

        let byAccount: [AccountUsageRow] = accountMap.map { accountID, acc in
            AccountUsageRow(
                accountID: accountID,
                provider: acc.provider,
                eventCount: acc.count,
                tokens: acc.tokens,
                cost: acc.cost
            )
        }
        .sorted { $0.cost.totalUSD > $1.cost.totalUSD }

        let byModel: [ModelUsageRow] = modelMap.map { key, acc in
            ModelUsageRow(
                provider: key.provider,
                model: key.model,
                eventCount: acc.count,
                tokens: acc.tokens,
                cost: acc.cost
            )
        }
        .sorted {
            if $0.cost.totalUSD != $1.cost.totalUSD {
                return $0.cost.totalUSD > $1.cost.totalUSD
            }
            return $0.tokens.total > $1.tokens.total
        }

        let providerOrder = Dictionary(uniqueKeysWithValues: ProviderID.allCases.enumerated().map { ($1, $0) })
        let dailySeries: [DailyUsagePoint] = dayMap.map { key, acc in
            let slices = acc.byProvider.map { prov, vals in
                DailyProviderCost(provider: prov, tokens: vals.0, costUSD: vals.1)
            }
            .sorted { (providerOrder[$0.provider] ?? 99) < (providerOrder[$1.provider] ?? 99) }

            return DailyUsagePoint(
                dateKey: key,
                date: acc.date,
                tokens: acc.tokens,
                cost: acc.cost,
                providerBreakdown: slices
            )
        }
        .sorted { $0.date < $1.date }

        let totalROI: Double? = totalMonthlySub > 0 ? (totalCost.totalUSD / totalMonthlySub) : nil

        return UsageSummary(
            range: range,
            generatedAt: now,
            eventCount: filtered.count,
            totalTokens: totalTokens,
            totalCost: totalCost,
            totalMonthlySubscriptionUSD: totalMonthlySub,
            roiMultiple: totalROI,
            byProvider: byProvider,
            byAccount: byAccount,
            byModel: byModel,
            dailySeries: dailySeries
        )
    }
}
