import Foundation

public struct ModelPricing: Equatable, Sendable {
    public var match: String
    public var inputPerMillion: Double
    public var cachedInputPerMillion: Double
    public var outputPerMillion: Double

    public init(
        match: String,
        inputPerMillion: Double,
        cachedInputPerMillion: Double,
        outputPerMillion: Double
    ) {
        self.match = match
        self.inputPerMillion = inputPerMillion
        self.cachedInputPerMillion = cachedInputPerMillion
        self.outputPerMillion = outputPerMillion
    }
}

public enum UsageCostEstimator {
    public static let pricingSource = "OpenAI API pricing, checked 2026-05-25"

    public static let defaultPricing: [ModelPricing] = [
        ModelPricing(match: "gpt-5.5", inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.0),
        ModelPricing(match: "gpt-5.4-mini", inputPerMillion: 0.25, cachedInputPerMillion: 0.025, outputPerMillion: 2.0),
        ModelPricing(match: "gpt-5.4", inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.0),
        ModelPricing(match: "gpt-5.2-codex", inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.0),
        ModelPricing(match: "gpt-5.2", inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.0),
        ModelPricing(match: "gpt-5.1-codex-max", inputPerMillion: 15.0, cachedInputPerMillion: 15.0, outputPerMillion: 120.0),
        ModelPricing(match: "gpt-5.1-codex", inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.0),
        ModelPricing(match: "gpt-5.1", inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.0),
        ModelPricing(match: "gpt-5-codex", inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.0),
        ModelPricing(match: "gpt-5", inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.0),
        ModelPricing(match: "gpt-4.1", inputPerMillion: 2.0, cachedInputPerMillion: 0.5, outputPerMillion: 8.0),
        ModelPricing(match: "gpt-4o-mini", inputPerMillion: 0.15, cachedInputPerMillion: 0.075, outputPerMillion: 0.60),
        ModelPricing(match: "gpt-4o", inputPerMillion: 2.50, cachedInputPerMillion: 1.25, outputPerMillion: 10.0)
    ]

    public static func pricing(for model: String) -> ModelPricing? {
        let normalized = model.lowercased()
        return defaultPricing.first { normalized.contains($0.match) }
    }

    public static func estimateUSD(for usage: TokenUsage, model: String) -> Double {
        guard let pricing = pricing(for: model) else {
            return 0
        }

        let cachedInput = max(0, usage.cachedInput)
        let uncachedInput = max(0, usage.input - cachedInput)
        let output = max(0, usage.output + usage.reasoning)
        let inputCost = Double(uncachedInput) * pricing.inputPerMillion / 1_000_000
        let cachedCost = Double(cachedInput) * pricing.cachedInputPerMillion / 1_000_000
        let outputCost = Double(output) * pricing.outputPerMillion / 1_000_000
        return inputCost + cachedCost + outputCost
    }
}
