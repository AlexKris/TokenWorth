import Foundation

public enum ProviderID: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case claude
    case codex
    case grok
    case antigravity

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .grok: return "Grok"
        case .antigravity: return "Antigravity"
        }
    }

    public var subtitle: String {
        switch self {
        case .claude: return "Claude Code & Pro/Max"
        case .codex: return "Codex CLI & ChatGPT"
        case .grok: return "Grok Build / Bot"
        case .antigravity: return "Antigravity & Gemini"
        }
    }

    public var sfSymbolName: String {
        switch self {
        case .claude: return "sparkle"
        case .codex: return "terminal"
        case .grok: return "bolt.circle"
        case .antigravity: return "triangle"
        }
    }

    public var defaultPlanName: String {
        switch self {
        case .claude: return "Claude Max"
        case .codex: return "ChatGPT Pro"
        case .grok: return "SuperGrok"
        case .antigravity: return "Google AI Pro"
        }
    }

    public var defaultMonthlySubscriptionUSD: Double {
        switch self {
        case .claude: return 100.0
        case .codex: return 20.0
        case .grok: return 30.0
        case .antigravity: return 19.99
        }
    }
}
