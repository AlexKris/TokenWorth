import Foundation

public struct AntigravityQuotaProvider: QuotaProvider {
    public let provider: ProviderID = .antigravity

    public init() {}

    public func fetchQuota(for account: AccountProfile, settings: AppSettings) async -> AccountQuotaSnapshot {
        if let snapshot = ExternalQuotaBridge.fetchIfConfigured(
            for: account,
            defaultFilePath: AppPaths.antigravityQuotaFile
        ) {
            return snapshot
        }

        return AccountQuotaSnapshot(
            accountID: account.id,
            provider: .antigravity,
            planName: account.planName,
            groups: [],
            fetchedAt: Date(),
            status: .notConfigured("Configure local quota JSON or OpenUsage bridge in Settings")
        )
    }

    public static func decodeAntigravityJSON(
        data: Data,
        account: AccountProfile,
        fetchedAt: Date = Date()
    ) -> AccountQuotaSnapshot {
        ExternalQuotaBridge.decodePayload(data: data, account: account, fetchedAt: fetchedAt)
    }
}
