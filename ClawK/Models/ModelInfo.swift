//
//  ModelInfo.swift
//  ClawK
//
//  Model information from OpenClaw Gateway
//

import Foundation

struct ModelInfo: Codable, Identifiable {
    let id: String
    let contextWindow: Int?
    let supportsVision: Bool?
    let supportsFunctionCalling: Bool?
    let tags: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id = "key"          // Gateway API returns "key", map to id
        case contextWindow
        case supportsVision
        case supportsFunctionCalling
        case tags
    }
    
    /// Effective context window with sensible defaults per model family
    var effectiveContextWindow: Int {
        if let cw = contextWindow { return cw }
        // Known defaults when gateway doesn't return contextWindow
        if id.contains("opus-4-6") { return 1_000_000 }
        if id.contains("opus") { return 200_000 }
        if id.contains("sonnet") { return 200_000 }
        if id.contains("haiku") { return 200_000 }
        return 200_000
    }
}
