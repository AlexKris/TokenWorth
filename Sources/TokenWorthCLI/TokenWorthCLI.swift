import Foundation
import TokenWorthCore

@main
struct TokenWorthCLI {
    enum Subcommand: String {
        case summary
        case models
        case daily
        case quota
        case pricing
        case help
    }

    struct Options {
        var command: Subcommand = .summary
        var range: TimeRange = .last7Days
        var provider: ProviderID?
        var useCNY: Bool = false
        var json: Bool = false
        var demo: Bool = false
        var query: String?
    }

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let options = parseOptions(args)

        if options.command == .help {
            printUsage()
            return
        }

        let settings = SettingsStore().load()
        let currency: CurrencyDisplay = options.useCNY ? .cny : settings.currency
        let rate = settings.usdToCnyRate
        let accounts = options.demo ? DemoDataFactory.demoAccounts() : settings.accounts
        let catalog = PricingCatalog.loadWithOverrides(customPath: settings.customPricingPath)
        let aggregator = UsageAggregator(calculator: CostCalculator(catalog: catalog))

        switch options.command {
        case .pricing:
            let matches = catalog.search(query: options.query)
            if options.json {
                printJSON(matches)
            } else {
                printPricingTable(matches)
            }

        case .quota:
            var effectiveSettings = settings
            if options.demo {
                effectiveSettings.useDemoData = true
            }
            let engine = QuotaPollingEngine()
            let filteredAccounts = accounts.filter { options.provider == nil || $0.provider == options.provider }
            let snapshots = await engine.refreshAll(accounts: filteredAccounts, settings: effectiveSettings, force: true)
            let ordered = filteredAccounts.compactMap { snapshots[$0.id] }
            if options.json {
                printJSON(ordered)
            } else {
                printQuotaTable(accounts: filteredAccounts, snapshots: snapshots, maskEmails: settings.maskEmails)
            }

        case .summary, .models, .daily:
            let events: [UsageEvent]
            if options.demo {
                events = DemoDataFactory.demoUsageEvents(accounts: accounts)
            } else {
                let cache = IncrementalLogCache()
                events = await cache.scanAll(accounts: accounts)
            }

            let summary = aggregator.summarize(
                events: events,
                accounts: accounts,
                range: options.range,
                providerFilter: options.provider
            )

            if options.json {
                switch options.command {
                case .summary:
                    printJSON(summary)
                case .models:
                    printJSON(summary.byModel)
                case .daily:
                    printJSON(summary.dailySeries)
                default:
                    break
                }
            } else {
                switch options.command {
                case .summary:
                    printSummary(summary, currency: currency, rate: rate)
                case .models:
                    printModelsTable(summary.byModel, currency: currency, rate: rate)
                case .daily:
                    printDailyTable(summary.dailySeries, currency: currency, rate: rate)
                default:
                    break
                }
            }

        case .help:
            printUsage()
        }
    }

    private static func parseOptions(_ args: [String]) -> Options {
        var opts = Options()
        var index = 0

        if let first = args.first, !first.hasPrefix("-") {
            if let cmd = Subcommand(rawValue: first.lowercased()) {
                opts.command = cmd
            } else if first == "help" {
                opts.command = .help
            }
            index = 1
        }

        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--help", "-h":
                opts.command = .help
            case "--json":
                opts.json = true
            case "--demo":
                opts.demo = true
            case "--cny":
                opts.useCNY = true
            case "--range":
                if index + 1 < args.count {
                    opts.range = parseRange(args[index + 1])
                    index += 1
                }
            case "--provider":
                if index + 1 < args.count {
                    let raw = args[index + 1].lowercased()
                    opts.provider = raw == "gemini" ? .antigravity : ProviderID(rawValue: raw)
                    index += 1
                }
            case "--query":
                if index + 1 < args.count {
                    opts.query = args[index + 1]
                    index += 1
                }
            default:
                break
            }
            index += 1
        }
        return opts
    }

    private static func parseRange(_ value: String) -> TimeRange {
        switch value.lowercased() {
        case "today", "1d": return .today
        case "7d", "week": return .last7Days
        case "30d", "month": return .last30Days
        case "all": return .allTime
        default: return .last7Days
        }
    }

    private static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    private static func printSummary(_ summary: UsageSummary, currency: CurrencyDisplay, rate: Double) {
        let costText = TokenWorthFormatter.formatCurrency(usd: summary.totalCost.totalUSD, currency: currency, usdToCnyRate: rate)
        let savedText = TokenWorthFormatter.formatCurrency(usd: summary.totalCost.cacheSavingsUSD, currency: currency, usdToCnyRate: rate)
        let roiText = summary.roiMultiple.map { String(format: "%.2fx", $0) } ?? "n/a"

        print("TokenWorth Summary [\(summary.range.displayTitle)]")
        print("==================================================")
        print("Events:         \(summary.eventCount)")
        print("Total Tokens:   \(TokenWorthFormatter.formatTokens(summary.totalTokens.total)) (In: \(TokenWorthFormatter.formatTokens(summary.totalTokens.input)), Out: \(TokenWorthFormatter.formatTokens(summary.totalTokens.output)), CacheR: \(TokenWorthFormatter.formatTokens(summary.totalTokens.cacheRead)), CacheW: \(TokenWorthFormatter.formatTokens(summary.totalTokens.cacheWrite)), Think: \(TokenWorthFormatter.formatTokens(summary.totalTokens.reasoning)))")
        print("API Equiv Cost: \(costText)")
        print("Cache Savings:  \(savedText) (Hit Rate: \(String(format: "%.1f%%", summary.totalTokens.cacheHitRate * 100)))")
        print("Sub ROI:        \(roiText)")
        print("")

        if summary.byProvider.isEmpty {
            print("No local usage logs found for this range. Try --demo to preview sample data.")
            return
        }

        print(pad("Provider", 14) + pad("Events", 8) + pad("Tokens", 12) + pad("API Cost", 12) + "ROI")
        print(String(repeating: "-", count: 54))
        for row in summary.byProvider {
            let rowCost = TokenWorthFormatter.formatCurrency(usd: row.cost.totalUSD, currency: currency, usdToCnyRate: rate)
            let rowROI = row.roiMultiple.map { String(format: "%.2fx", $0) } ?? "-"
            print(
                pad(row.provider.displayName, 14) +
                pad("\(row.eventCount)", 8) +
                pad(TokenWorthFormatter.formatTokens(row.tokens.total), 12) +
                pad(rowCost, 12) +
                rowROI
            )
        }
    }

    private static func printModelsTable(_ rows: [ModelUsageRow], currency: CurrencyDisplay, rate: Double) {
        if rows.isEmpty {
            print("No model usage found. Try --demo to preview sample data.")
            return
        }
        print(pad("Provider", 13) + pad("Model", 24) + pad("Tokens", 12) + pad("Cache%", 9) + "API Cost")
        print(String(repeating: "-", count: 68))
        for row in rows {
            let cost = TokenWorthFormatter.formatCurrency(usd: row.cost.totalUSD, currency: currency, usdToCnyRate: rate)
            let cachePct = String(format: "%.0f%%", row.tokens.cacheHitRate * 100)
            print(
                pad(row.provider.displayName, 13) +
                pad(row.model, 24) +
                pad(TokenWorthFormatter.formatTokens(row.tokens.total), 12) +
                pad(cachePct, 9) +
                cost
            )
        }
    }

    private static func printDailyTable(_ rows: [DailyUsagePoint], currency: CurrencyDisplay, rate: Double) {
        if rows.isEmpty {
            print("No daily usage data found. Try --demo to preview sample data.")
            return
        }
        print(pad("Date", 13) + pad("Tokens", 12) + pad("API Cost", 12) + "Cache Saved")
        print(String(repeating: "-", count: 48))
        for row in rows {
            let cost = TokenWorthFormatter.formatCurrency(usd: row.cost.totalUSD, currency: currency, usdToCnyRate: rate)
            let saved = TokenWorthFormatter.formatCurrency(usd: row.cost.cacheSavingsUSD, currency: currency, usdToCnyRate: rate)
            print(
                pad(row.dateKey, 13) +
                pad(TokenWorthFormatter.formatTokens(row.tokens.total), 12) +
                pad(cost, 12) +
                saved
            )
        }
    }

    private static func printQuotaTable(
        accounts: [AccountProfile],
        snapshots: [String: AccountQuotaSnapshot],
        maskEmails: Bool
    ) {
        for account in accounts {
            let header = "\(account.provider.displayName) · \(account.maskedEmailDisplay(masked: maskEmails)) [\(account.planName)]\(account.isActive ? " *Active" : "")"
            print(header)
            guard let snap = snapshots[account.id] else {
                print("  (no snapshot)")
                continue
            }
            if let msg = snap.status.statusMessage, snap.groups.isEmpty {
                print("  Status: \(msg)")
            } else {
                for group in snap.groups {
                    print("  \(group.title):")
                    for win in group.windows {
                        let pct = TokenWorthFormatter.formatPercent(win.usedPercent)
                        let pace = win.pacePercent().map { " (pace \(TokenWorthFormatter.formatPercent($0)))" } ?? ""
                        print("    \(pad(win.label, 8)) \(pad(pct, 6))\(pace)  \(win.resetSummary())")
                    }
                }
            }
            print("")
        }
    }

    private static func printPricingTable(_ models: [ModelPricing]) {
        print(pad("Provider", 13) + pad("Model", 24) + pad("In/1M", 10) + pad("CacheR", 10) + "Out/1M")
        print(String(repeating: "-", count: 66))
        for model in models {
            print(
                pad(model.provider.displayName, 13) +
                pad(model.modelID, 24) +
                pad(String(format: "$%.2f", model.inputPerMillion), 10) +
                pad(String(format: "$%.3f", model.cacheReadPerMillion), 10) +
                String(format: "$%.2f", model.outputPerMillion)
            )
        }
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        if text.count >= width { return String(text.prefix(width - 1)) + " " }
        return text + String(repeating: " ", count: width - text.count)
    }

    private static func printUsage() {
        print("""
        TokenWorth CLI — Local AI Quota, Token & API-Cost Tracker

        Usage:
          tokenworth <command> [options]

        Commands:
          summary   Aggregate token usage, API-equivalent cost, and ROI
          models    Break down token usage and API cost by model
          daily     Show daily token and cost series
          quota     Fetch read-only account quota windows
          pricing   List built-in and custom API model pricing
          help      Show this help message

        Options:
          --range <today|7d|30d|all>          Time range filter (default: 7d)
          --provider <claude|codex|grok|antigravity>
          --cny                               Display amounts in CNY
          --json                              Output machine-readable JSON
          --demo                              Use sample multi-account & usage data
          --query <text>                      Filter pricing list by model/provider
        """)
    }
}
