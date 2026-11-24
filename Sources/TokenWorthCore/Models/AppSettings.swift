import Foundation

public enum CurrencyDisplay: String, Codable, Sendable, CaseIterable, Identifiable {
    case usd = "USD"
    case cny = "CNY"

    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .usd: return "$"
        case .cny: return "¥"
        }
    }
}

public enum MenuBarDisplayMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case highestQuota = "Highest Quota"
    case todayCost = "Today Cost"
    case iconOnly = "Icon Only"

    public var id: String { rawValue }
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var accounts: [AccountProfile]
    public var refreshIntervalSeconds: Int
    public var currency: CurrencyDisplay
    public var usdToCnyRate: Double
    public var maskEmails: Bool
    public var menuBarMode: MenuBarDisplayMode
    public var allowKeychainReads: Bool
    public var useDemoData: Bool
    public var customPricingPath: String?

    public init(
        accounts: [AccountProfile] = AppSettings.defaultAccounts(),
        refreshIntervalSeconds: Int = 180,
        currency: CurrencyDisplay = .usd,
        usdToCnyRate: Double = 7.25,
        maskEmails: Bool = true,
        menuBarMode: MenuBarDisplayMode = .highestQuota,
        allowKeychainReads: Bool = false,
        useDemoData: Bool = false,
        customPricingPath: String? = nil
    ) {
        self.accounts = accounts
        self.refreshIntervalSeconds = max(30, refreshIntervalSeconds)
        self.currency = currency
        self.usdToCnyRate = max(0.01, usdToCnyRate)
        self.maskEmails = maskEmails
        self.menuBarMode = menuBarMode
        self.allowKeychainReads = allowKeychainReads
        self.useDemoData = useDemoData
        self.customPricingPath = customPricingPath
    }

    public static func defaultAccounts() -> [AccountProfile] {
        [
            AccountProfile(
                id: "claude-default",
                provider: .claude,
                displayName: "Claude Code",
                email: nil,
                planName: "Claude Max",
                monthlySubscriptionUSD: 100.0,
                isActive: true,
                switchCapability: .isolatedDirectory
            ),
            AccountProfile(
                id: "codex-default",
                provider: .codex,
                displayName: "Codex CLI",
                email: nil,
                planName: "ChatGPT Pro",
                monthlySubscriptionUSD: 20.0,
                isActive: true,
                switchCapability: .isolatedDirectory
            ),
            AccountProfile(
                id: "grok-default",
                provider: .grok,
                displayName: "Grok Build / Bot",
                email: nil,
                planName: "SuperGrok",
                monthlySubscriptionUSD: 30.0,
                isActive: true,
                switchCapability: .readOnly
            ),
            AccountProfile(
                id: "antigravity-default",
                provider: .antigravity,
                displayName: "Antigravity / Gemini",
                email: nil,
                planName: "Google AI Pro",
                monthlySubscriptionUSD: 19.99,
                isActive: true,
                switchCapability: .readOnly
            )
        ]
    }
}
