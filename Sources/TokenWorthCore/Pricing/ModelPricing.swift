import Foundation

public struct ModelPricing: Codable, Sendable, Equatable, Identifiable {
    public var id: String { modelID }
    public var modelID: String
    public var provider: ProviderID
    public var inputPerMillion: Double
    public var outputPerMillion: Double
    public var cacheReadPerMillion: Double
    public var cacheWritePerMillion: Double
    public var longContextThreshold: Int?
    public var longContextInputMultiplier: Double?
    public var longContextOutputMultiplier: Double?

    public init(
        modelID: String,
        provider: ProviderID,
        inputPerMillion: Double,
        outputPerMillion: Double,
        cacheReadPerMillion: Double? = nil,
        cacheWritePerMillion: Double? = nil,
        longContextThreshold: Int? = nil,
        longContextInputMultiplier: Double? = nil,
        longContextOutputMultiplier: Double? = nil
    ) {
        self.modelID = modelID
        self.provider = provider
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.cacheReadPerMillion = cacheReadPerMillion ?? (inputPerMillion * 0.1)
        self.cacheWritePerMillion = cacheWritePerMillion ?? inputPerMillion
        self.longContextThreshold = longContextThreshold
        self.longContextInputMultiplier = longContextInputMultiplier
        self.longContextOutputMultiplier = longContextOutputMultiplier
    }
}
