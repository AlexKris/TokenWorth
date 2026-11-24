import Foundation

public enum SwitchCapability: String, Codable, Sendable, Equatable {
    case readOnly
    case isolatedDirectory
    case keychainSwap
}

public struct AccountProfile: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: String
    public var provider: ProviderID
    public var displayName: String
    public var email: String?
    public var planName: String
    public var monthlySubscriptionUSD: Double?
    public var isActive: Bool
    public var customLogDirectory: String?
    public var credentialPath: String?
    public var externalQuotaCommand: String?
    public var externalQuotaFilePath: String?
    public var switchCapability: SwitchCapability

    public init(
        id: String = UUID().uuidString,
        provider: ProviderID,
        displayName: String,
        email: String? = nil,
        planName: String,
        monthlySubscriptionUSD: Double? = nil,
        isActive: Bool = true,
        customLogDirectory: String? = nil,
        credentialPath: String? = nil,
        externalQuotaCommand: String? = nil,
        externalQuotaFilePath: String? = nil,
        switchCapability: SwitchCapability = .readOnly
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.email = email
        self.planName = planName
        self.monthlySubscriptionUSD = monthlySubscriptionUSD
        self.isActive = isActive
        self.customLogDirectory = customLogDirectory
        self.credentialPath = credentialPath
        self.externalQuotaCommand = externalQuotaCommand
        self.externalQuotaFilePath = externalQuotaFilePath
        self.switchCapability = switchCapability
    }

    public func maskedEmailDisplay(masked: Bool) -> String {
        let raw = (email?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? displayName
        guard masked else { return raw }

        if let atIndex = raw.firstIndex(of: "@") {
            let local = String(raw[..<atIndex])
            let domain = String(raw[raw.index(after: atIndex)...])
            let maskedLocal = Self.maskComponent(local, bulletCount: 5)
            let maskedDomain = Self.maskComponent(domain, bulletCount: 6)
            return "\(maskedLocal)@\(maskedDomain)"
        }
        return raw
    }

    private static func maskComponent(_ component: String, bulletCount: Int) -> String {
        guard let first = component.first else { return String(repeating: "•", count: bulletCount) }
        return "\(first)\(String(repeating: "•", count: bulletCount))"
    }
}
