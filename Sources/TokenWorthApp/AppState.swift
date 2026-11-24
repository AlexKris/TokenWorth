import Foundation
import Observation
import AppKit
import TokenWorthCore

enum AppTab: Hashable, Identifiable {
    case overview
    case provider(ProviderID)

    var id: String {
        switch self {
        case .overview: return "overview"
        case .provider(let provider): return provider.rawValue
        }
    }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .provider(let provider): return provider.displayName
        }
    }

    var sfSymbolName: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .provider(let provider): return provider.sfSymbolName
        }
    }

    static var allTabs: [AppTab] {
        [.overview] + ProviderID.allCases.map { .provider($0) }
    }
}

enum ActiveModal: Equatable {
    case settings
    case addAccount
}

@Observable
@MainActor
final class AppState {
    var settings: AppSettings
    var selectedTab: AppTab = .overview
    var selectedTimeRange: TimeRange = .last7Days {
        didSet { recomputeSummary() }
    }
    var activeModal: ActiveModal?

    var quotaSnapshots: [String: AccountQuotaSnapshot] = [:]
    var cachedEvents: [UsageEvent] = []
    var usageSummary: UsageSummary = UsageSummary(range: .last7Days)
    var todayCostUSD: Double = 0
    var isRefreshing: Bool = false
    var lastRefreshDate: Date?
    var statusToast: String?

    let settingsDraft = SettingsDraftModel()
    let addAccountDraft = AddAccountDraftModel()

    private let settingsStore: SettingsStore
    private let logCache = IncrementalLogCache()
    private let pollingEngine = QuotaPollingEngine()
    private var catalog: PricingCatalog
    private var pollingTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init(settingsStore: SettingsStore = SettingsStore()) {
        self.settingsStore = settingsStore
        let loaded = settingsStore.load()
        self.settings = loaded
        self.catalog = PricingCatalog.loadWithOverrides(customPath: loaded.customPricingPath)
        startPollingLoop()
    }

    var effectiveAccounts: [AccountProfile] {
        settings.useDemoData ? DemoDataFactory.demoAccounts() : settings.accounts
    }

    var activeProviderFilter: ProviderID? {
        if case .provider(let p) = selectedTab { return p }
        return nil
    }

    var highestQuotaPercent: Double? {
        let values = quotaSnapshots.values
            .filter { $0.status.isHealthy }
            .flatMap { $0.groups.flatMap(\.windows) }
            .map(\.usedPercent)
        return values.max()
    }

    var menuBarLabelText: String? {
        switch settings.menuBarMode {
        case .iconOnly:
            return nil
        case .highestQuota:
            guard let highest = highestQuotaPercent else { return nil }
            return TokenWorthFormatter.formatPercent(highest)
        case .todayCost:
            return TokenWorthFormatter.formatCurrency(
                usd: todayCostUSD,
                currency: settings.currency,
                usdToCnyRate: settings.usdToCnyRate
            )
        }
    }

    func accounts(for provider: ProviderID) -> [AccountProfile] {
        effectiveAccounts.filter { $0.provider == provider }
    }

    func accountUsage(for accountID: String) -> AccountUsageRow? {
        usageSummary.byAccount.first { $0.accountID == accountID }
    }

    func providerUsage(for provider: ProviderID) -> ProviderUsageRow? {
        usageSummary.byProvider.first { $0.provider == provider }
    }

    func formatCurrency(_ usd: Double) -> String {
        TokenWorthFormatter.formatCurrency(
            usd: usd,
            currency: settings.currency,
            usdToCnyRate: settings.usdToCnyRate
        )
    }

    func startPollingLoop() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.refreshAll(force: false)
                let interval = UInt64(max(30, self.settings.refreshIntervalSeconds)) * 1_000_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    func refreshAll(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let accounts = effectiveAccounts
        let currentSettings = settings

        async let quotaTask = pollingEngine.refreshAll(
            accounts: accounts,
            settings: currentSettings,
            force: force
        )
        async let eventsTask: [UsageEvent] = {
            if currentSettings.useDemoData {
                return DemoDataFactory.demoUsageEvents(accounts: accounts)
            }
            return await self.logCache.scanAll(accounts: accounts)
        }()

        let (snapshots, events) = await (quotaTask, eventsTask)
        self.quotaSnapshots = snapshots
        self.cachedEvents = events
        self.lastRefreshDate = Date()
        recomputeSummary()
    }

    func selectTab(_ tab: AppTab) {
        selectedTab = tab
        recomputeSummary()
    }

    func openSettings() {
        settingsDraft.load(from: settings)
        activeModal = .settings
    }

    func openAddAccount() {
        let defaultProvider = activeProviderFilter ?? .claude
        addAccountDraft.reset(defaultProvider: defaultProvider)
        activeModal = .addAccount
    }

    func recomputeSummary() {
        let aggregator = UsageAggregator(calculator: CostCalculator(catalog: catalog))
        let accounts = effectiveAccounts
        usageSummary = aggregator.summarize(
            events: cachedEvents,
            accounts: accounts,
            range: selectedTimeRange,
            providerFilter: activeProviderFilter
        )
        let todaySummary = aggregator.summarize(
            events: cachedEvents,
            accounts: accounts,
            range: .today
        )
        todayCostUSD = todaySummary.totalCost.totalUSD
    }

    func updateSettings(_ newSettings: AppSettings) {
        let intervalChanged = newSettings.refreshIntervalSeconds != settings.refreshIntervalSeconds
        let pricingChanged = newSettings.customPricingPath != settings.customPricingPath
        settings = newSettings
        if pricingChanged {
            catalog = PricingCatalog.loadWithOverrides(customPath: newSettings.customPricingPath)
        }
        do {
            try settingsStore.save(newSettings)
        } catch {
            showToast("Failed to save settings: \(error.localizedDescription)")
        }
        if intervalChanged {
            startPollingLoop()
        } else {
            Task { await refreshAll(force: true) }
        }
    }

    func addAccount(_ profile: AccountProfile) {
        var updated = settings
        if updated.useDemoData {
            updated.useDemoData = false
        }
        updated.accounts.append(profile)
        updateSettings(updated)
        selectedTab = .provider(profile.provider)
        activeModal = nil
        showToast("Added \(profile.displayName)")
    }

    func removeAccount(id: String) {
        var updated = settings
        updated.accounts.removeAll { $0.id == id }
        updateSettings(updated)
    }

    func notifySwitchPreview(account: AccountProfile) {
        showToast("Phase 1 is read-only — \(account.provider.displayName) account switching lands in Phase 2")
    }

    func writeAntigravityQuotaTemplate() {
        let url = AppPaths.antigravityQuotaFile
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let now = Date()
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            let template: [String: Any] = [
                "accounts": [
                    [
                        "accountID": accounts(for: .antigravity).first?.id ?? "antigravity-default",
                        "planName": "Google AI Ultra",
                        "groups": [
                            [
                                "title": "Gemini Models",
                                "windows": [
                                    ["label": "7d", "durationSeconds": 604800, "usedPercent": 1, "resetsAt": iso.string(from: now.addingTimeInterval(6 * 86400 + 23 * 3600))],
                                    ["label": "5h", "durationSeconds": 18000, "usedPercent": 2, "resetsAt": iso.string(from: now.addingTimeInterval(4 * 3600 + 50 * 60))]
                                ]
                            ],
                            [
                                "title": "Claude and GPT models",
                                "windows": [
                                    ["label": "7d", "durationSeconds": 604800, "usedPercent": 3, "resetsAt": iso.string(from: now.addingTimeInterval(3 * 86400 + 5 * 3600))],
                                    ["label": "5h", "durationSeconds": 18000, "usedPercent": 0, "resetsAt": iso.string(from: now.addingTimeInterval(4 * 3600 + 59 * 60))]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: template, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            showToast("Template created at \(url.lastPathComponent)")
            Task { await refreshAll(force: true) }
        } catch {
            showToast("Failed to write template: \(error.localizedDescription)")
        }
    }

    func openAppSupportFolder() {
        let dir = AppPaths.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func showToast(_ message: String) {
        statusToast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled {
                self?.statusToast = nil
            }
        }
    }
}
