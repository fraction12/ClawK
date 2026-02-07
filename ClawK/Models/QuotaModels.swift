//
//  QuotaModels.swift
//  ClawK
//
//  Claude usage tracking models - supports Claude Desktop App API + CLI local files
//

import Foundation
import SwiftUI

// MARK: - Pace Status

/// Pace status for quota usage
enum PaceStatus: String {
    case underPace = "under pace"
    case onTrack = "on track"
    case overPace = "over pace"
    case atRisk = "at risk"
    case unknown = "calculating"
    
    var color: Color {
        switch self {
        case .underPace: return .green
        case .onTrack: return .blue
        case .overPace: return .orange
        case .atRisk: return .red
        case .unknown: return .secondary
        }
    }
    
    var icon: String {
        switch self {
        case .underPace: return "📉"
        case .onTrack: return "📊"
        case .overPace: return "📈"
        case .atRisk: return "⚠️"
        case .unknown: return "⏱"
        }
    }
}

// MARK: - Data Source

/// Where usage data was sourced from (priority order)
enum QuotaDataSource: String, Codable {
    case claudeDesktopApp = "Claude Desktop"  // Highest priority: API via desktop app cookies
    case localFiles = "Local Files"           // CLI usage from local JSONL files
    case none = "No Data"                     // No data available
    
    var icon: String {
        switch self {
        case .claudeDesktopApp: return "🖥️"
        case .localFiles: return "📁"
        case .none: return "⚠️"
        }
    }
    
    var description: String {
        switch self {
        case .claudeDesktopApp: return "Claude Desktop"
        case .localFiles: return "CLI Usage (Local)"
        case .none: return "No Data"
        }
    }
}

// MARK: - Tokens By Model

/// Token usage breakdown by model family
struct TokensByModel {
    let sonnet: Int
    let opus: Int
    let haiku: Int
    
    var total: Int { sonnet + opus + haiku }
    
    /// Format token count for display
    static func format(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Quota Windows (from Claude API)

/// A usage window (session or weekly)
struct QuotaWindow {
    /// Percentage used (0-100)
    let percentUsed: Double
    
    /// When this window resets
    let resetsAt: Date?
    
    /// Window duration hint (for pace calculations)
    /// - "session" for 5-hour windows
    /// - "weekly" for 7-day windows
    var windowType: String = "weekly"
    
    /// Formatted percentage
    var percentFormatted: String {
        String(format: "%.0f%%", percentUsed)
    }
    
    /// Percentage remaining
    var percentRemaining: Double {
        max(0, 100 - percentUsed)
    }
    
    /// Formatted time until reset
    var resetFormatted: String {
        guard let reset = resetsAt else { return "—" }
        let interval = reset.timeIntervalSinceNow
        guard interval > 0 else { return "Now" }
        
        let days = Int(interval / 86400)
        let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    /// Window duration in seconds
    var windowDuration: TimeInterval {
        if windowType == "session" {
            return 5 * 3600  // 5 hours
        } else {
            return 7 * 24 * 3600  // 7 days
        }
    }
    
    /// Time elapsed since window started (in seconds)
    var timeElapsed: TimeInterval? {
        guard let reset = resetsAt else { return nil }
        let timeUntilReset = reset.timeIntervalSinceNow
        guard timeUntilReset > 0 else { return windowDuration }
        return windowDuration - timeUntilReset
    }
    
    /// Percentage of time elapsed in the window (0-100)
    var timeElapsedPercent: Double? {
        guard let elapsed = timeElapsed else { return nil }
        return (elapsed / windowDuration) * 100
    }
    
    /// Pace: ratio of usage to time elapsed (percentage)
    /// Returns nil if time elapsed is too short (<24h for weekly, <30min for session)
    var pace: Double? {
        guard let elapsed = timeElapsed else { return nil }
        
        // Minimum elapsed time before showing pace
        let minElapsed: TimeInterval = windowType == "session" ? 1800 : 86400  // 30min or 24h
        guard elapsed >= minElapsed else { return nil }
        
        guard let elapsedPercent = timeElapsedPercent, elapsedPercent > 0 else { return nil }
        return (percentUsed / elapsedPercent) * 100
    }
    
    /// Pace status based on current pace
    var paceStatus: PaceStatus {
        guard let pace = pace else { return .unknown }
        
        switch pace {
        case ..<90: return .underPace
        case 90..<110: return .onTrack
        case 110..<130: return .overPace
        default: return .atRisk
        }
    }
    
    /// Whether pace should be displayed (enough time elapsed)
    var shouldShowPace: Bool {
        return pace != nil && windowType == "weekly"
    }
    
    /// Explanation of why pace isn't shown (for tooltips)
    var paceNotAvailableReason: String? {
        guard windowType == "weekly" else { return nil }  // Only for weekly
        guard pace == nil else { return nil }  // Pace is available
        
        guard let elapsed = timeElapsed else {
            return "Waiting for usage data..."
        }
        
        let minElapsed: TimeInterval = 86400  // 24h
        let remaining = minElapsed - elapsed
        
        if remaining > 0 {
            let hours = Int(remaining / 3600)
            return "Pace will appear in ~\(hours)h (needs 24h of data)"
        }
        
        return nil
    }
    
    static let empty = QuotaWindow(percentUsed: 0, resetsAt: nil)
}

// MARK: - Claude Max Quota

/// Unified usage data (supports both percentage-based API and token-based local files)
struct ClaudeMaxQuota {
    /// Data source used for this reading
    let dataSource: QuotaDataSource
    
    // MARK: - Percentage-Based (from Claude API)
    
    /// Session (5-hour) window usage
    let sessionWindow: QuotaWindow
    
    /// Weekly (7-day) window usage
    let weeklyWindow: QuotaWindow
    
    /// Weekly Opus-specific usage (if available)
    let weeklyOpusWindow: QuotaWindow?
    
    /// Weekly Sonnet-specific usage (if available)
    let weeklySonnetWindow: QuotaWindow?
    
    // MARK: - Token-Based (from CLI local files)
    
    /// Total tokens used (all models combined) - for CLI tracking
    let totalTokensUsed: Int
    
    /// Breakdown by model
    let tokensByModel: TokensByModel
    
    /// Total messages sent
    let messageCount: Int
    
    /// Total sessions
    let sessionCount: Int
    
    /// Last CLI session timestamp
    let lastSessionDate: Date?
    
    // MARK: - Account Info
    
    /// Account email (if available from API)
    let accountEmail: String?
    
    /// Plan type (Pro, Max, etc.)
    let planType: String?
    
    /// Organization ID
    let organizationId: String?
    
    // MARK: - Metadata
    
    /// When this data was fetched
    let lastUpdated: Date
    
    // MARK: - Convenience Accessors
    
    var hasData: Bool {
        dataSource != .none && (sessionWindow.percentUsed > 0 || weeklyWindow.percentUsed > 0 || totalTokensUsed > 0)
    }
    
    /// Has percentage-based quota data (from API)
    var hasPercentageData: Bool {
        dataSource == .claudeDesktopApp
    }
    
    /// Is data stale (>5 min old)
    var isStale: Bool {
        Date().timeIntervalSince(lastUpdated) > 300
    }
    
    /// Formatted time since last session
    var lastSessionFormatted: String {
        guard let lastSession = lastSessionDate else { return "Never" }
        let interval = Date().timeIntervalSince(lastSession)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
    
    /// Estimated weekly reset (for local files fallback)
    var weeklyResetAt: Date? {
        if let reset = weeklyWindow.resetsAt {
            return reset
        }
        // Calculate next Monday for CLI data
        let now = Date()
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        comps.weekday = 2 // Monday
        comps.hour = 0
        comps.minute = 0
        if let nextMonday = calendar.date(from: comps) {
            return nextMonday > now ? nextMonday : calendar.date(byAdding: .day, value: 7, to: nextMonday)
        }
        return nil
    }
    
    /// Formatted weekly reset time (for backwards compatibility)
    var weeklyResetFormatted: String {
        weeklyWindow.resetFormatted
    }
    
    // MARK: - Empty/Default
    
    static let empty = ClaudeMaxQuota(
        dataSource: .none,
        sessionWindow: .empty,
        weeklyWindow: .empty,
        weeklyOpusWindow: nil,
        weeklySonnetWindow: nil,
        totalTokensUsed: 0,
        tokensByModel: TokensByModel(sonnet: 0, opus: 0, haiku: 0),
        messageCount: 0,
        sessionCount: 0,
        lastSessionDate: nil,
        accountEmail: nil,
        planType: nil,
        organizationId: nil,
        lastUpdated: Date()
    )
}

// MARK: - API Response Models (for Claude Web API)

/// Response from /api/organizations
struct ClaudeOrganizationsResponse: Codable {
    let uuid: String
    let name: String?
}

/// Response from /api/organizations/{id}/usage
/// Actual API format: { "five_hour": { "utilization": 30.0, "resets_at": "..." }, ... }
struct ClaudeUsageResponse: Codable {
    let five_hour: UsageWindow?
    let seven_day: UsageWindow?
    let seven_day_opus: UsageWindow?
    let seven_day_sonnet: UsageWindow?
    let extra_usage: ExtraUsage?
    
    struct UsageWindow: Codable {
        let utilization: Double?
        let resets_at: String?
    }
    
    struct ExtraUsage: Codable {
        let spend: Double?
        let limit: Double?
    }
}

/// Response from /api/account
struct ClaudeAccountResponse: Codable {
    let email: String?
    let memberships: [Membership]?
    
    struct Membership: Codable {
        let organization: Organization?
        
        struct Organization: Codable {
            let uuid: String?
            let name: String?
            let billing_type: String?
            let capabilities: [String]?
        }
    }
}

// QuotaError is defined in QuotaService.swift
