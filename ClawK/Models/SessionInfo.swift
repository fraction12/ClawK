//
//  SessionInfo.swift
//  ClawK
//
//  Session info model matching gateway API response
//

import Foundation

struct SessionInfo: Codable, Identifiable {
    let key: String
    let kind: String?
    let channel: String?
    let label: String?
    let displayName: String?
    let deliveryContext: DeliveryContext?
    let updatedAt: Int64?
    let sessionId: String
    let model: String?
    let contextTokens: Int?
    let totalTokens: Int
    let systemSent: Bool?
    let abortedLastRun: Bool?
    let lastChannel: String?
    let lastTo: String?
    let lastAccountId: String?
    let transcriptPath: String?
    
    var id: String { sessionId }
    
    var lastUpdatedDate: Date? {
        guard let ms = updatedAt else { return nil }
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }
    
    var contextUsagePercent: Double {
        guard let total = contextTokens, total > 0 else { return 0 }
        return Double(totalTokens) / Double(total) * 100
    }
    
    var modelShortName: String {
        guard let model = model else { return "—" }
        // Extract just the model name without provider
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return model.components(separatedBy: "/").last ?? model
    }
    
    var sessionType: SessionType {
        if key.contains("subagent") { return .subagent }
        if key.contains("cron") { return .cron }
        if key.contains(":main") { return .main }
        return .other
    }
    
    var friendlyName: String {
        // Priority 1: Use label if present
        if let label = label, !label.isEmpty {
            return label
        }
        // Priority 2: Use displayName if present
        if let displayName = displayName, !displayName.isEmpty {
            return displayName
        }
        // Priority 3: For subagents, extract UUID suffix for identification
        if sessionType == .subagent {
            // Session key format: "agent:main:subagent:uuid-uuid-uuid-uuid"
            // Extract last 8 characters of UUID for readability
            let parts = key.components(separatedBy: ":")
            if let uuidPart = parts.last, uuidPart.count >= 8 {
                let suffix = String(uuidPart.suffix(8))
                return "Subagent (\(suffix))"
            }
            return "Subagent"
        }
        // Priority 4: For crons, try to extract job name
        if sessionType == .cron {
            // Session key format might include cron identifier
            let parts = key.components(separatedBy: ":")
            if parts.count > 2 {
                let cronPart = parts.dropFirst(2).joined(separator: ":")
                if !cronPart.isEmpty && cronPart.count < 40 {
                    return "Cron: \(cronPart)"
                }
            }
            return "Cron Job"
        }
        return sessionType.rawValue.capitalized
    }
}

struct DeliveryContext: Codable {
    let channel: String?
    let to: String?
    let accountId: String?
}

enum SessionType: String {
    case main = "main"
    case subagent = "subagent"
    case cron = "cron"
    case other = "other"
}

// MARK: - Session Icon Helper

extension SessionInfo {
    /// Returns the appropriate SF Symbol icon for a session key
    static func icon(for key: String) -> String {
        if key.contains("telegram") {
            return "paperplane.circle.fill"
        } else if key == AppConfiguration.shared.mainSessionKey {
            return "brain"
        } else {
            return "bubble.left.circle.fill"
        }
    }
}

// MARK: - API Response
struct SessionsListResponse: Codable {
    let count: Int
    let sessions: [SessionInfo]
}
