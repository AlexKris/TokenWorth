import Foundation

public enum DemoDataFactory {
    public static func demoAccounts() -> [AccountProfile] {
        [
            AccountProfile(
                id: "claude-demo",
                provider: .claude,
                displayName: "Claude Max",
                email: "dev.claude@gmail.com",
                planName: "Claude Max",
                monthlySubscriptionUSD: 100.0,
                isActive: true,
                switchCapability: .isolatedDirectory
            ),
            AccountProfile(
                id: "codex-demo",
                provider: .codex,
                displayName: "Codex Pro",
                email: "dev.codex@gmail.com",
                planName: "ChatGPT Pro",
                monthlySubscriptionUSD: 20.0,
                isActive: true,
                switchCapability: .isolatedDirectory
            ),
            AccountProfile(
                id: "grok-demo",
                provider: .grok,
                displayName: "SuperGrok",
                email: "dev.grok@x.ai",
                planName: "SuperGrok",
                monthlySubscriptionUSD: 30.0,
                isActive: true,
                switchCapability: .readOnly
            ),
            AccountProfile(
                id: "antigravity-pro-demo",
                provider: .antigravity,
                displayName: "Google AI Pro",
                email: "xiaoming@gmail.com",
                planName: "Google AI Pro",
                monthlySubscriptionUSD: 19.99,
                isActive: false,
                switchCapability: .readOnly
            ),
            AccountProfile(
                id: "antigravity-ultra-demo",
                provider: .antigravity,
                displayName: "Google AI Ultra",
                email: "tokenworth@gmail.com",
                planName: "Google AI Ultra",
                monthlySubscriptionUSD: 249.99,
                isActive: true,
                switchCapability: .readOnly
            )
        ]
    }

    public static func demoQuotaSnapshots(for accounts: [AccountProfile], now: Date = Date()) -> [String: AccountQuotaSnapshot] {
        var result: [String: AccountQuotaSnapshot] = [:]
        let day: TimeInterval = 24 * 3600
        let hour: TimeInterval = 3600

        for account in accounts {
            switch account.provider {
            case .antigravity:
                if account.planName.lowercased().contains("ultra") || account.isActive {
                    result[account.id] = AccountQuotaSnapshot(
                        accountID: account.id,
                        provider: .antigravity,
                        planName: account.planName,
                        groups: [
                            QuotaGroup(
                                id: "gemini-models",
                                title: "Gemini Models",
                                windows: [
                                    QuotaWindow(id: "7d", label: "7d", durationSeconds: 7 * day, usedPercent: 1, resetsAt: now.addingTimeInterval(6 * day + 23 * hour + 180)),
                                    QuotaWindow(id: "5h", label: "5h", durationSeconds: 5 * hour, usedPercent: 2, resetsAt: now.addingTimeInterval(4 * hour + 50 * 60))
                                ]
                            ),
                            QuotaGroup(
                                id: "claude-gpt-models",
                                title: "Claude and GPT models",
                                windows: [
                                    QuotaWindow(id: "7d-cg", label: "7d", durationSeconds: 7 * day, usedPercent: 3, resetsAt: now.addingTimeInterval(3 * day + 5 * hour)),
                                    QuotaWindow(id: "5h-cg", label: "5h", durationSeconds: 5 * hour, usedPercent: 0, resetsAt: now.addingTimeInterval(4 * hour + 59 * 60))
                                ]
                            )
                        ],
                        fetchedAt: now,
                        status: .demo
                    )
                } else {
                    result[account.id] = AccountQuotaSnapshot(
                        accountID: account.id,
                        provider: .antigravity,
                        planName: account.planName,
                        groups: [
                            QuotaGroup(
                                id: "gemini-models-pro",
                                title: "Gemini Models",
                                windows: [
                                    QuotaWindow(id: "7d", label: "7d", durationSeconds: 7 * day, usedPercent: 0, resetsAt: now.addingTimeInterval(6 * day + 23 * hour + 300)),
                                    QuotaWindow(id: "5h", label: "5h", durationSeconds: 5 * hour, usedPercent: 0, resetsAt: now.addingTimeInterval(4 * hour + 59 * 60))
                                ]
                            )
                        ],
                        fetchedAt: now,
                        status: .demo
                    )
                }

            case .claude:
                result[account.id] = AccountQuotaSnapshot(
                    accountID: account.id,
                    provider: .claude,
                    planName: account.planName,
                    groups: [
                        QuotaGroup(
                            id: "claude-all",
                            title: "All Claude Models",
                            windows: [
                                QuotaWindow(id: "7d", label: "7d", durationSeconds: 7 * day, usedPercent: 42, resetsAt: now.addingTimeInterval(3 * day + 14 * hour)),
                                QuotaWindow(id: "5h", label: "5h", durationSeconds: 5 * hour, usedPercent: 18, resetsAt: now.addingTimeInterval(2 * hour + 40 * 60))
                            ]
                        ),
                        QuotaGroup(
                            id: "claude-models",
                            title: "Model Quotas",
                            windows: [
                                QuotaWindow(id: "sonnet-7d", label: "Sonnet", durationSeconds: 7 * day, usedPercent: 26, resetsAt: now.addingTimeInterval(3 * day + 14 * hour)),
                                QuotaWindow(id: "opus-7d", label: "Opus", durationSeconds: 7 * day, usedPercent: 54, resetsAt: now.addingTimeInterval(3 * day + 14 * hour))
                            ]
                        )
                    ],
                    extraUsageUSD: 14.50,
                    extraUsageLimitUSD: 100.0,
                    fetchedAt: now,
                    status: .demo
                )

            case .codex:
                result[account.id] = AccountQuotaSnapshot(
                    accountID: account.id,
                    provider: .codex,
                    planName: account.planName,
                    groups: [
                        QuotaGroup(
                            id: "codex-limits",
                            title: "Codex Limits",
                            windows: [
                                QuotaWindow(id: "7d", label: "7d", durationSeconds: 7 * day, usedPercent: 31, resetsAt: now.addingTimeInterval(4 * day + 6 * hour)),
                                QuotaWindow(id: "5h", label: "5h", durationSeconds: 5 * hour, usedPercent: 12, resetsAt: now.addingTimeInterval(3 * hour + 15 * 60))
                            ]
                        ),
                        QuotaGroup(
                            id: "codex-review",
                            title: "Code Review",
                            windows: [
                                QuotaWindow(id: "review", label: "7d", durationSeconds: 7 * day, usedPercent: 8, resetsAt: now.addingTimeInterval(4 * day + 6 * hour))
                            ]
                        )
                    ],
                    fetchedAt: now,
                    status: .demo
                )

            case .grok:
                result[account.id] = AccountQuotaSnapshot(
                    accountID: account.id,
                    provider: .grok,
                    planName: account.planName,
                    groups: [
                        QuotaGroup(
                            id: "grok-limits",
                            title: "Grok Build & Subscription",
                            windows: [
                                QuotaWindow(id: "7d", label: "7d", durationSeconds: 7 * day, usedPercent: 24, resetsAt: now.addingTimeInterval(5 * day + 2 * hour)),
                                QuotaWindow(id: "5h", label: "5h", durationSeconds: 5 * hour, usedPercent: 9, resetsAt: now.addingTimeInterval(4 * hour + 5 * 60))
                            ]
                        )
                    ],
                    extraUsageUSD: 6.20,
                    extraUsageLimitUSD: 50.0,
                    fetchedAt: now,
                    status: .demo
                )
            }
        }

        return result
    }

    public static func demoUsageEvents(
        accounts: [AccountProfile],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [UsageEvent] {
        var activeIDByProvider: [ProviderID: String] = [:]
        for acct in accounts {
            if acct.isActive || activeIDByProvider[acct.provider] == nil {
                activeIDByProvider[acct.provider] = acct.id
            }
        }

        let claudeID = activeIDByProvider[.claude] ?? "claude-demo"
        let codexID = activeIDByProvider[.codex] ?? "codex-demo"
        let grokID = activeIDByProvider[.grok] ?? "grok-demo"
        let antigravityID = activeIDByProvider[.antigravity] ?? "antigravity-ultra-demo"

        var events: [UsageEvent] = []
        let todayStart = calendar.startOfDay(for: now)

        for dayOffset in 0..<14 {
            guard let dayDate = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart) else { continue }
            let wave = 1.0 + Double((dayOffset * 3) % 5) * 0.22
            let tsClaude = dayDate.addingTimeInterval(10 * 3600)
            let tsCodex = dayDate.addingTimeInterval(11 * 3600)
            let tsGemini = dayDate.addingTimeInterval(14 * 3600)
            let tsGrok = dayDate.addingTimeInterval(16 * 3600)

            // Keep today's timestamps <= now so `.today` looks natural.
            let safeTS: (Date) -> Date = { candidate in
                candidate > now ? now.addingTimeInterval(-600) : candidate
            }

            events.append(UsageEvent(
                id: "demo-claude-opus-\(dayOffset)",
                provider: .claude,
                accountID: claudeID,
                model: "claude-opus-4-6",
                timestamp: safeTS(tsClaude),
                tokens: TokenCounts(
                    input: Int(22_000 * wave),
                    output: Int(28_000 * wave),
                    cacheRead: Int(640_000 * wave),
                    cacheWrite: Int(45_000 * wave),
                    reasoning: Int(9_000 * wave)
                ),
                sessionID: "demo-session-c-\(dayOffset)"
            ))

            events.append(UsageEvent(
                id: "demo-claude-sonnet-\(dayOffset)",
                provider: .claude,
                accountID: claudeID,
                model: "claude-sonnet-4-6",
                timestamp: safeTS(tsClaude.addingTimeInterval(1800)),
                tokens: TokenCounts(
                    input: Int(38_000 * wave),
                    output: Int(42_000 * wave),
                    cacheRead: Int(520_000 * wave),
                    cacheWrite: Int(28_000 * wave),
                    reasoning: Int(6_000 * wave)
                ),
                sessionID: "demo-session-cs-\(dayOffset)"
            ))

            events.append(UsageEvent(
                id: "demo-codex-\(dayOffset)",
                provider: .codex,
                accountID: codexID,
                model: "gpt-5.3-codex",
                timestamp: safeTS(tsCodex),
                tokens: TokenCounts(
                    input: Int(45_000 * wave),
                    output: Int(24_000 * wave),
                    cacheRead: Int(310_000 * wave),
                    cacheWrite: 0,
                    reasoning: Int(8_500 * wave)
                ),
                sessionID: "demo-session-x-\(dayOffset)"
            ))

            events.append(UsageEvent(
                id: "demo-gemini-\(dayOffset)",
                provider: .antigravity,
                accountID: antigravityID,
                model: dayOffset % 2 == 0 ? "gemini-4-neon" : "gemini-4-argon",
                timestamp: safeTS(tsGemini),
                tokens: TokenCounts(
                    input: Int(65_000 * wave),
                    output: Int(34_000 * wave),
                    cacheRead: Int(240_000 * wave),
                    cacheWrite: 0,
                    reasoning: Int(11_000 * wave)
                ),
                sessionID: "demo-session-g-\(dayOffset)"
            ))

            events.append(UsageEvent(
                id: "demo-grok-\(dayOffset)",
                provider: .grok,
                accountID: grokID,
                model: dayOffset % 3 == 0 ? "grok-4.7" : "grok-build-0.1",
                timestamp: safeTS(tsGrok),
                tokens: TokenCounts(
                    input: Int(52_000 * wave),
                    output: Int(26_000 * wave),
                    cacheRead: Int(180_000 * wave),
                    cacheWrite: 0,
                    reasoning: Int(7_200 * wave)
                ),
                sessionID: "demo-session-k-\(dayOffset)"
            ))
        }

        return events.sorted { $0.timestamp < $1.timestamp }
    }
}
