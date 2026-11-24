import Foundation
import Observation
import TokenWorthCore

@Observable
@MainActor
final class SettingsDraftModel {
    var settings: AppSettings = AppSettings()
    var cnyRateText: String = "7.25"

    func load(from current: AppSettings) {
        self.settings = current
        self.cnyRateText = String(format: "%.2f", current.usdToCnyRate)
    }

    func buildSettings() -> AppSettings {
        var result = settings
        if let parsedRate = Double(cnyRateText), parsedRate > 0 {
            result.usdToCnyRate = parsedRate
        }
        return result
    }
}

@Observable
@MainActor
final class AddAccountDraftModel {
    var provider: ProviderID = .claude
    var displayName: String = ""
    var email: String = ""
    var planName: String = ProviderID.claude.defaultPlanName
    var monthlyFeeText: String = String(format: "%.2f", ProviderID.claude.defaultMonthlySubscriptionUSD)
    var customLogDir: String = ""
    var credentialPath: String = ""
    var externalQuotaFilePath: String = ""
    var externalQuotaCommand: String = ""
    var isActive: Bool = true

    func reset(defaultProvider: ProviderID = .claude) {
        provider = defaultProvider
        displayName = ""
        email = ""
        planName = defaultProvider.defaultPlanName
        monthlyFeeText = String(format: "%.2f", defaultProvider.defaultMonthlySubscriptionUSD)
        customLogDir = ""
        credentialPath = ""
        externalQuotaFilePath = ""
        externalQuotaCommand = ""
        isActive = true
    }

    func applyProviderDefaults(_ newProvider: ProviderID) {
        planName = newProvider.defaultPlanName
        monthlyFeeText = String(format: "%.2f", newProvider.defaultMonthlySubscriptionUSD)
    }

    func buildProfile() -> AccountProfile {
        let finalName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(provider.displayName) Account"
            : displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalPlan = planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.defaultPlanName
            : planName.trimmingCharacters(in: .whitespacesAndNewlines)

        return AccountProfile(
            id: "\(provider.rawValue)-\(UUID().uuidString.prefix(8))",
            provider: provider,
            displayName: finalName,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            planName: finalPlan,
            monthlySubscriptionUSD: Double(monthlyFeeText),
            isActive: isActive,
            customLogDirectory: Self.emptyToNil(customLogDir),
            credentialPath: Self.emptyToNil(credentialPath),
            externalQuotaCommand: Self.emptyToNil(externalQuotaCommand),
            externalQuotaFilePath: Self.emptyToNil(externalQuotaFilePath),
            switchCapability: (provider == .claude || provider == .codex) ? .isolatedDirectory : .readOnly
        )
    }

    private static func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
