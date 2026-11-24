import Foundation

public struct CostCalculator: Sendable {
    public let catalog: PricingCatalog

    public init(catalog: PricingCatalog = .default) {
        self.catalog = catalog
    }

    public func cost(for event: UsageEvent) -> CostBreakdown {
        cost(for: event.tokens, modelName: event.model)
    }

    public func cost(for tokens: TokenCounts, modelName: String) -> CostBreakdown {
        guard let pricing = catalog.resolve(modelName: modelName) else {
            return CostBreakdown(isEstimatedOrUnpriced: true)
        }

        let promptTokens = tokens.totalInputSide
        var inputMultiplier = 1.0
        var outputMultiplier = 1.0

        if let threshold = pricing.longContextThreshold, promptTokens > threshold {
            inputMultiplier = pricing.longContextInputMultiplier ?? 1.0
            outputMultiplier = pricing.longContextOutputMultiplier ?? 1.0
        }

        let perMillion = 1_000_000.0
        let inputUSD = (Double(tokens.input) / perMillion) * pricing.inputPerMillion * inputMultiplier
        let outputUSD = (Double(tokens.output) / perMillion) * pricing.outputPerMillion * outputMultiplier
        let cacheReadUSD = (Double(tokens.cacheRead) / perMillion) * pricing.cacheReadPerMillion * inputMultiplier
        let cacheWriteUSD = (Double(tokens.cacheWrite) / perMillion) * pricing.cacheWritePerMillion * inputMultiplier

        let cacheSavingsPerToken = max(0.0, (pricing.inputPerMillion - pricing.cacheReadPerMillion) * inputMultiplier)
        let cacheSavingsUSD = (Double(tokens.cacheRead) / perMillion) * cacheSavingsPerToken

        return CostBreakdown(
            inputUSD: inputUSD,
            outputUSD: outputUSD,
            cacheReadUSD: cacheReadUSD,
            cacheWriteUSD: cacheWriteUSD,
            cacheSavingsUSD: cacheSavingsUSD,
            isEstimatedOrUnpriced: false
        )
    }
}

public enum TokenWorthFormatter {
    public static func formatCurrency(usd: Double, currency: CurrencyDisplay, usdToCnyRate: Double) -> String {
        let converted = currency == .cny ? usd * usdToCnyRate : usd
        let symbol = currency.symbol
        if abs(converted) >= 1000 {
            return String(format: "%@%.0f", symbol, converted)
        } else if abs(converted) >= 10 {
            return String(format: "%@%.2f", symbol, converted)
        } else if abs(converted) >= 0.01 || converted == 0 {
            return String(format: "%@%.2f", symbol, converted)
        } else {
            return String(format: "%@%.4f", symbol, converted)
        }
    }

    public static func formatTokens(_ count: Int) -> String {
        let absCount = abs(count)
        let sign = count < 0 ? "-" : ""
        switch absCount {
        case 1_000_000_000...:
            return String(format: "%@%.2fB", sign, Double(absCount) / 1_000_000_000.0)
        case 1_000_000...:
            return String(format: "%@%.2fM", sign, Double(absCount) / 1_000_000.0)
        case 1_000...:
            return String(format: "%@%.1fK", sign, Double(absCount) / 1_000.0)
        default:
            return "\(count)"
        }
    }

    public static func formatPercent(_ value: Double) -> String {
        let clamped = min(max(value, 0), 100)
        if abs(clamped - clamped.rounded()) < 0.05 {
            return "\(Int(clamped.rounded()))%"
        }
        return String(format: "%.1f%%", clamped)
    }

    public static func formatRelativeTime(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 15 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
