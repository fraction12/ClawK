//
//  CostEstimator.swift
//  ClawK
//
//  Estimates API costs based on model and token usage
//

import Foundation

struct CostEstimator {
    // MARK: - Configuration Keys
    
    /// UserDefaults key for output ratio percentage
    static let outputRatioKey = "costEstimatorOutputRatio"
    
    /// Available output ratio presets
    static let outputRatioOptions: [(label: String, value: Double)] = [
        ("20% (minimal output)", 0.20),
        ("30% (typical conversation)", 0.30),
        ("40% (code generation)", 0.40)
    ]
    
    /// Current output ratio from UserDefaults (default 30%)
    static var outputRatio: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: outputRatioKey)
            return stored > 0 ? stored : 0.30
        }
        set {
            UserDefaults.standard.set(newValue, forKey: outputRatioKey)
        }
    }
    
    /// Output ratio as percentage string for display
    static var outputRatioLabel: String {
        return "\(Int(outputRatio * 100))%"
    }
    
    // Anthropic pricing (per 1M tokens) as of Feb 2026
    // These are approximate - actual costs depend on input/output ratio
    static let pricing: [String: (input: Double, output: Double)] = [
        // Claude 3.5 models
        "opus": (input: 15.0, output: 75.0),
        "claude-opus-4": (input: 15.0, output: 75.0),
        "claude-opus-4-5": (input: 15.0, output: 75.0),
        
        "sonnet": (input: 3.0, output: 15.0),
        "claude-sonnet-4": (input: 3.0, output: 15.0),
        "claude-sonnet-4-5": (input: 3.0, output: 15.0),
        
        "haiku": (input: 0.25, output: 1.25),
        "claude-haiku-4": (input: 0.25, output: 1.25),
        "claude-haiku-4-5": (input: 0.25, output: 1.25),
        
        // Legacy/fallback
        "claude-3-opus": (input: 15.0, output: 75.0),
        "claude-3-sonnet": (input: 3.0, output: 15.0),
        "claude-3-haiku": (input: 0.25, output: 1.25),
    ]
    
    /// Estimate cost for a session based on model and total tokens
    /// Uses configurable output ratio from UserDefaults
    static func estimateCost(model: String?, totalTokens: Int) -> Double {
        let normalizedModel = normalizeModelName(model)
        
        // Get pricing or default to Sonnet
        let (inputRate, outputRate) = pricing[normalizedModel] ?? pricing["sonnet"]!
        
        // Use configurable output ratio
        let inputTokens = Double(totalTokens) * (1.0 - outputRatio)
        let outputTokens = Double(totalTokens) * outputRatio
        
        // Calculate cost
        let inputCost = (inputTokens / 1_000_000) * inputRate
        let outputCost = (outputTokens / 1_000_000) * outputRate
        
        return inputCost + outputCost
    }
    
    /// Estimate daily cost based on current usage rate
    static func estimateDailyCost(sessions: [SessionInfo]) -> Double {
        return sessions.reduce(0) { total, session in
            total + estimateCost(model: session.model, totalTokens: session.totalTokens ?? 0)
        }
    }
    
    /// Format cost as currency string with disclaimer
    static func formatCost(_ cost: Double, includeDisclaimer: Bool = false) -> String {
        var result: String
        if cost < 0.01 {
            result = "<$0.01"
        } else if cost < 1.0 {
            result = String(format: "$%.2f", cost)
        } else if cost < 10.0 {
            result = String(format: "$%.2f", cost)
        } else {
            result = String(format: "$%.0f", cost)
        }
        
        if includeDisclaimer {
            result += "*"
        }
        return result
    }
    
    /// Get cost disclaimer text
    static var disclaimer: String {
        return "* Estimate assumes \(outputRatioLabel) output tokens"
    }
    
    /// Get a model tier for display
    static func getModelTier(_ model: String?) -> String {
        let normalized = normalizeModelName(model)
        if normalized.contains("opus") { return "💎 Opus" }
        if normalized.contains("haiku") { return "⚡ Haiku" }
        return "✨ Sonnet"
    }
    
    private static func normalizeModelName(_ model: String?) -> String {
        guard let model = model?.lowercased() else { return "sonnet" }
        
        // Extract model name from full path like "anthropic/claude-sonnet-4-5"
        let components = model.components(separatedBy: "/")
        let modelName = components.last ?? model
        
        if modelName.contains("opus") { return "opus" }
        if modelName.contains("haiku") { return "haiku" }
        if modelName.contains("sonnet") { return "sonnet" }
        
        return modelName
    }
}
