//
//  HeartbeatModels.swift
//  ClawK
//
//  Models for heartbeat monitoring and system status
//

import Foundation

// MARK: - Heartbeat Configuration (from Gateway health API)

/// Heartbeat configuration from Gateway health API
struct HeartbeatConfig: Codable {
    let enabled: Bool
    let every: String
    let everyMs: Int64?
    let model: String?
    let target: String?
    
    /// Safe accessor — returns 0 when everyMs is null (disabled agents)
    var effectiveEveryMs: Int64 {
        everyMs ?? 0
    }
    
    static let disabled = HeartbeatConfig(
        enabled: false,
        every: "0",
        everyMs: 0,
        model: nil,
        target: nil
    )
}

// MARK: - Heartbeat History (for 24-hour graph)

struct HeartbeatHistory: Codable, Identifiable {
    var id: Date { timestamp }
    let timestamp: Date
    let status: String  // "HEARTBEAT_OK" or "HEARTBEAT_ALERT"
    let contextPercent: Double
    let sessionsChecked: Int
    let sessionsActive: Int
    let memoryEventsLogged: Int
    let statusDescription: String
}

// MARK: - Heartbeat

struct HeartbeatStatus: Codable {
    let lastCheck: Date?
    let nextCheck: Date?
    let status: HeartbeatState
    let intervalMinutes: Int
    let recentChecks: [HeartbeatCheck]
    let issues: [HeartbeatIssue]
    
    // Summary data from structured heartbeat response
    let sessionsChecked: Int?
    let sessionsActive: Int?
    let memoryEventsLogged: Int?
    let contextPercent: Double?
    let statusDescription: String?
    
    static let empty = HeartbeatStatus(
        lastCheck: nil,
        nextCheck: nil,
        status: .unknown,
        intervalMinutes: 30,
        recentChecks: [],
        issues: [],
        sessionsChecked: nil,
        sessionsActive: nil,
        memoryEventsLogged: nil,
        contextPercent: nil,
        statusDescription: nil
    )
}

enum HeartbeatState: String, Codable {
    case ok = "ok"
    case alert = "alert"
    case critical = "critical"
    case unknown = "unknown"
    
    var emoji: String {
        switch self {
        case .ok: return "✓"
        case .alert: return "⚠"
        case .critical: return "❌"
        case .unknown: return "?"
        }
    }
    
    var label: String {
        switch self {
        case .ok: return "OK"
        case .alert: return "Alert"
        case .critical: return "Critical"
        case .unknown: return "Unknown"
        }
    }
}

struct HeartbeatCheck: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let status: HeartbeatState
    let durationMs: Int?
    
    init(id: String = UUID().uuidString, timestamp: Date, status: HeartbeatState, durationMs: Int? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.status = status
        self.durationMs = durationMs
    }
}

struct HeartbeatIssue: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let severity: HeartbeatState
    let detectedAt: Date
    
    init(id: String = UUID().uuidString, title: String, description: String, severity: HeartbeatState, detectedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.description = description
        self.severity = severity
        self.detectedAt = detectedAt
    }
}

// MARK: - System Status

struct SystemStatus: Codable {
    let gatewayConnected: Bool
    let gatewayLatencyMs: Int?
    let nodeCount: Int
    let connectedNodes: Int
    /// Seconds since last session activity (not actual system uptime)
    let lastActivitySeconds: Int?
    let lastHealthCheck: Date?
    
    /// Formatted string for last activity time
    var lastActivityFormatted: String {
        guard let seconds = lastActivitySeconds else { return "Unknown" }
        if seconds < 60 {
            return "Just now"
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m ago"
        }
        return "\(minutes)m ago"
    }
    
    // Deprecated: use lastActivityFormatted
    var uptimeFormatted: String { lastActivityFormatted }
    
    static let empty = SystemStatus(
        gatewayConnected: false,
        gatewayLatencyMs: nil,
        nodeCount: 0,
        connectedNodes: 0,
        lastActivitySeconds: nil,
        lastHealthCheck: nil
    )
}

// MARK: - Memory Vitals Models

struct ContextPressure: Codable {
    let currentTokens: Int
    let maxTokens: Int
    let lastFlush: Date?
    
    var usagePercent: Double {
        guard maxTokens > 0 else { return 0 }
        return Double(currentTokens) / Double(maxTokens) * 100
    }
    
    var level: PressureLevel {
        if usagePercent >= 90 { return .critical }
        if usagePercent >= 70 { return .warning }
        return .normal
    }
    
    static let empty = ContextPressure(currentTokens: 0, maxTokens: 1_000_000, lastFlush: nil)
}

enum PressureLevel {
    case normal
    case warning
    case critical
    
    var label: String {
        switch self {
        case .normal: return "Healthy"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

struct MemoryFileStatus: Identifiable, Codable {
    let id: String
    let path: String
    let name: String
    let sizeBytes: Int
    let tokens: Int
    let entryCount: Int?
    let lastModified: Date?
    let status: FileHealthStatus
    
    var sizeFormatted: String {
        if sizeBytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(sizeBytes) / 1024 / 1024)
        } else if sizeBytes >= 1024 {
            return String(format: "%.1f KB", Double(sizeBytes) / 1024)
        }
        return "\(sizeBytes) B"
    }
    
    var tokensFormatted: String {
        if tokens >= 1000 {
            return String(format: "%.1fK", Double(tokens) / 1000)
        }
        return "\(tokens)"
    }
}

enum FileHealthStatus: String, Codable {
    case healthy = "healthy"
    case needsAttention = "needs_attention"
    case stale = "stale"
    case missing = "missing"
    
    var emoji: String {
        switch self {
        case .healthy: return "✓"
        case .needsAttention: return "⚠"
        case .stale: return "🕐"
        case .missing: return "❌"
        }
    }
    
    var label: String {
        switch self {
        case .healthy: return "Healthy"
        case .needsAttention: return "Needs Attention"
        case .stale: return "Stale"
        case .missing: return "Missing"
        }
    }
}

struct ArchiveHealth: Codable {
    let currentMonthFolder: String
    let currentMonthFileCount: Int
    let lastMonthlySummary: SummaryInfo?
    let lastQuarterlySummary: SummaryInfo?
    let totalArchiveSizeBytes: Int
    let nextCompressionDue: Date?
    
    var totalArchiveSizeFormatted: String {
        if totalArchiveSizeBytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(totalArchiveSizeBytes) / 1024 / 1024)
        } else if totalArchiveSizeBytes >= 1024 {
            return String(format: "%.1f KB", Double(totalArchiveSizeBytes) / 1024)
        }
        return "\(totalArchiveSizeBytes) B"
    }
    
    static let empty = ArchiveHealth(
        currentMonthFolder: "",
        currentMonthFileCount: 0,
        lastMonthlySummary: nil,
        lastQuarterlySummary: nil,
        totalArchiveSizeBytes: 0,
        nextCompressionDue: nil
    )
}

struct SummaryInfo: Codable {
    let name: String
    let date: Date?
    let sizeBytes: Int
    
    var sizeFormatted: String {
        if sizeBytes >= 1024 {
            return String(format: "%.1f KB", Double(sizeBytes) / 1024)
        }
        return "\(sizeBytes) B"
    }
}

struct CurationSchedule: Codable {
    let dailyCuration: Date?
    let weeklyMaintenance: Date?
    let monthlyCompression: Date?
    let isOnSchedule: Bool
    let dailyDescription: String
    let weeklyDescription: String
    let monthlyDescription: String
    let scheduleIssue: String?
    
    init(dailyCuration: Date? = nil, weeklyMaintenance: Date? = nil, monthlyCompression: Date? = nil,
         isOnSchedule: Bool = true, dailyDescription: String = "8:30 PM", 
         weeklyDescription: String = "Sunday", monthlyDescription: String = "1st of month",
         scheduleIssue: String? = nil) {
        self.dailyCuration = dailyCuration
        self.weeklyMaintenance = weeklyMaintenance
        self.monthlyCompression = monthlyCompression
        self.isOnSchedule = isOnSchedule
        self.dailyDescription = dailyDescription
        self.weeklyDescription = weeklyDescription
        self.monthlyDescription = monthlyDescription
        self.scheduleIssue = scheduleIssue
    }
    
    static let empty = CurationSchedule()
}

struct MemoryActivity: Codable {
    let searchesToday: Int
    let entriesAddedToday: Int
    let lastMemoryWrite: Date?
    let mostActiveFiles: [String]
    
    static let empty = MemoryActivity(
        searchesToday: 0,
        entriesAddedToday: 0,
        lastMemoryWrite: nil,
        mostActiveFiles: []
    )
}
