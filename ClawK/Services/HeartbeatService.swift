//
//  HeartbeatService.swift
//  ClawK
//
//  Ground truth heartbeat status service using Gateway health API.
//
//  DATA SOURCES:
//  - Configuration: `openclaw gateway health --json` → agents[].heartbeat
//    Returns: enabled, every, everyMs (interval in milliseconds)
//
//  - Last Run Time: ~/.openclaw/agents/main/sessions/sessions.json
//    Field: lastHeartbeatSentAt (Unix timestamp in milliseconds)
//    Note: Gateway scheduler writes this, NOT the heartbeat LLM
//
//  EXTERNAL MONITORING PRINCIPLE:
//  The heartbeat LLM never self-reports its own health. Instead:
//  1. Gateway scheduler runs heartbeat → writes timestamp to sessions.json
//  2. This service READS that timestamp (external observation)
//  3. Calculates staleness by comparing to expected interval
//  This prevents: "I'm healthy!" from a stuck/hallucinating LLM.
//
//  STATUS THRESHOLDS:
//  - ratio = elapsed_time / interval
//  - ratio ≤ 1.5: OK (within expected window + 50% buffer)
//  - ratio ≤ 2.0: Alert (late but within tolerance)
//  - ratio > 2.0: Critical (significantly overdue)
//
//  SPRINT: Heartbeat Config Integration (2026-02-04)
//  See: ~/.openclaw/workspace/sprint/heartbeat-config-sprint/
//

import Foundation

/// Service for calculating heartbeat status from Gateway health data (ground truth)
class HeartbeatService {
    
    /// Shared instance
    static let shared = HeartbeatService()
    
    // MARK: - Context Window Defaults
    
    /// Default context window for unknown models
    private let defaultContextWindow = 200_000
    
    // MARK: - Heartbeat Config Extraction
    
    /// Extract heartbeat config from Gateway health response.
    ///
    /// Data Source: `openclaw gateway health --json` → agents[].heartbeat
    ///
    /// Returns config for the default agent (or first agent if no default).
    /// Config includes: enabled, every (human string), everyMs (milliseconds)
    func getHeartbeatConfig(from health: GatewayClient.GatewayHealthResponse) -> HeartbeatConfig? {
        guard let agents = health.agents, !agents.isEmpty else {
            return nil
        }
        
        // Prefer the default agent, fallback to first
        let agent = agents.first { $0.isDefault == true } ?? agents.first
        return agent?.heartbeat
    }
    
    // MARK: - Last Heartbeat Timestamp
    
    /// Read last heartbeat timestamp from BOTH sessions.json and JSONL files.
    ///
    /// Data Sources:
    /// 1. sessions.json: lastHeartbeatSentAt (Unix ms) - Gateway scheduler writes this
    /// 2. JSONL parsing: HeartbeatHistoryService finds HEARTBEAT_OK/ALERT responses
    ///
    /// IMPORTANT: sessions.json can become stale if Gateway doesn't update it
    /// after each heartbeat run. JSONL is the source of truth for when the LLM
    /// actually responded. We return the MORE RECENT of the two sources.
    ///
    /// This ensures we always show the most accurate "last check" time,
    /// regardless of which data source is fresher.
    func getLastHeartbeatSent() -> Date? {
        var sessionsJsonDate: Date?
        var jsonlDate: Date?
        
        // Source 1: sessions.json lastHeartbeatSentAt
        let sessionsPath = URL(fileURLWithPath: AppConfiguration.shared.sessionsIndexPath)
        
        if let data = try? Data(contentsOf: sessionsPath),
           let sessions = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var latestTimestamp: Int64 = 0
            for (_, sessionData) in sessions {
                guard let session = sessionData as? [String: Any],
                      let timestamp = session["lastHeartbeatSentAt"] as? Int64,
                      timestamp > latestTimestamp else {
                    continue
                }
                latestTimestamp = timestamp
            }
            if latestTimestamp > 0 {
                sessionsJsonDate = Date(timeIntervalSince1970: Double(latestTimestamp) / 1000.0)
            }
        }
        
        // Source 2: JSONL parsing (actual heartbeat response timestamps)
        jsonlDate = HeartbeatHistoryService.shared.getLastHeartbeatTime()
        
        // Return the MORE RECENT of the two sources
        // This handles stale sessions.json while still using it as a fallback
        switch (sessionsJsonDate, jsonlDate) {
        case (nil, nil):
            return nil
        case (let date?, nil):
            return date
        case (nil, let date?):
            return date
        case (let date1?, let date2?):
            return date1 > date2 ? date1 : date2
        }
    }
    
    // MARK: - Status Calculation
    
    /// Determine heartbeat status from Gateway config + sessions.json.
    ///
    /// Priority chain (first match wins):
    /// 1. API error → .critical "Can't Connect"
    /// 2. No config → .unknown "Not Set Up"
    /// 3. Disabled → .unknown "Paused"
    /// 4. No lastHeartbeat → .unknown "Starting Up"
    /// 5. ratio ≤ 1.5 → .ok "Running Fine"
    /// 6. ratio ≤ 2.0 → .alert "Running Late"
    /// 7. ratio > 2.0 → .critical "Something's Wrong"
    ///
    /// Ratio calculation: elapsed_time / interval_ms
    /// Thresholds chosen to give ~50% buffer before alerting.
    func determineStatus(
        config: HeartbeatConfig?,
        lastHeartbeatSent: Date?,
        apiError: Error?,
        now: Date = Date()
    ) -> ClawKStatusState {
        
        // Priority 1: API error (can't connect to Gateway)
        if let error = apiError {
            let isTimeout = (error as? GatewayError)?.isTimeout ?? false
            let subtitle = isTimeout ? "Connection timed out" : "Unable to connect"
            
            return ClawKStatusState(
                status: .critical,
                statusMessage: "Can't Connect",
                statusSubtitle: subtitle,
                lastCheck: nil,
                nextCheck: nil,
                intervalMinutes: 30,
                contextPercent: nil,
                activeSessions: 0,
                memoryEvents: 0,
                isStale: true,
                lastError: error.localizedDescription
            )
        }
        
        // Priority 2: No config found (heartbeat not configured)
        guard let config = config else {
            return ClawKStatusState(
                status: .unknown,
                statusMessage: "Not Set Up",
                statusSubtitle: "Heartbeat not configured in Gateway",
                lastCheck: nil,
                nextCheck: nil,
                intervalMinutes: 30,
                contextPercent: nil,
                activeSessions: 0,
                memoryEvents: 0,
                isStale: false,
                lastError: nil
            )
        }
        
        // Get interval from config
        let intervalMs = config.everyMs
        let intervalMinutes = Int(intervalMs / 60_000)
        
        // Priority 3: Heartbeat disabled in config
        guard config.enabled else {
            return ClawKStatusState(
                status: .unknown,
                statusMessage: "Paused",
                statusSubtitle: "Automatic checks are off",
                lastCheck: lastHeartbeatSent,
                nextCheck: nil,
                intervalMinutes: intervalMinutes,
                contextPercent: nil,
                activeSessions: 0,
                memoryEvents: 0,
                isStale: false,
                lastError: nil
            )
        }
        
        // Priority 4: No lastHeartbeatSentAt (never ran or first run)
        guard let lastSent = lastHeartbeatSent else {
            // Calculate expected first run time (now + interval)
            let nextCheck = now.addingTimeInterval(Double(intervalMs) / 1000.0)
            return ClawKStatusState(
                status: .unknown,
                statusMessage: "Starting Up",
                statusSubtitle: "Waiting for first check",
                lastCheck: nil,
                nextCheck: nextCheck,
                intervalMinutes: intervalMinutes,
                contextPercent: nil,
                activeSessions: 0,
                memoryEvents: 0,
                isStale: false,
                lastError: nil
            )
        }
        
        // Priority 5: Ratio check (normal operation)
        let elapsed = now.timeIntervalSince(lastSent)
        let intervalSeconds = Double(intervalMs) / 1000.0
        let ratio = elapsed / intervalSeconds
        
        // Calculate next check time
        let nextCheck = lastSent.addingTimeInterval(intervalSeconds)
        
        let status: ClawKHeartbeatState
        let message: String
        let subtitle: String
        let isStale: Bool
        
        if ratio <= 1.5 {
            // OK — within expected window
            status = .ok
            message = "Running Fine"
            subtitle = "Checked \(formatTimeAgo(lastSent, now: now))"
            isStale = false
        } else if ratio <= 2.0 {
            // Alert — late but not critical
            status = .alert
            message = "Running Late"
            subtitle = "Last check was \(formatTimeAgo(lastSent, now: now))"
            isStale = true
        } else {
            // Critical — significantly overdue
            status = .critical
            message = "Something's Wrong"
            subtitle = "Hasn't checked in over \(formatTimeAgo(lastSent, now: now, useOver: false))"
            isStale = true
        }
        
        return ClawKStatusState(
            status: status,
            statusMessage: message,
            statusSubtitle: subtitle,
            lastCheck: lastSent,
            nextCheck: nextCheck,
            intervalMinutes: intervalMinutes,
            contextPercent: nil,  // Populated by caller
            activeSessions: 0,     // Populated by caller
            memoryEvents: 0,       // Populated by caller
            isStale: isStale,
            lastError: nil
        )
    }
    
    // MARK: - Context Percentage
    
    /// Calculate context percentage from sessions (ground truth from sessions API)
    /// Filters out cron and subagent sessions, uses most recent active session
    func calculateContextPercent(
        sessions: [SessionInfo],
        models: [ModelInfo],
        now: Date = Date()
    ) -> (percent: Double?, activeCount: Int, mostRecentSession: SessionInfo?) {
        
        // Filter out cron and subagent sessions
        let filtered = sessions.filter { session in
            !session.key.contains("cron:") && !session.key.contains("subagent")
        }
        
        // Filter to sessions active in last 24 hours
        let staleThreshold: Int64 = 24 * 60 * 60 * 1000  // 24h in ms
        let cutoff = Int64(now.timeIntervalSince1970 * 1000) - staleThreshold
        
        let activeSessions = filtered.filter { session in
            guard let updatedAt = session.updatedAt else { return false }
            return updatedAt > cutoff
        }
        
        // Sort by updatedAt DESC and take first
        let sorted = activeSessions.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
        
        guard let mostRecent = sorted.first else {
            return (nil, 0, nil)
        }
        
        // Get context window for the model
        let maxTokens = contextWindow(for: mostRecent.model, models: models)
        
        guard maxTokens > 0 else {
            return (nil, activeSessions.count, mostRecent)
        }
        
        let percent = (Double(mostRecent.totalTokens) / Double(maxTokens)) * 100.0
        
        return (percent, activeSessions.count, mostRecent)
    }
    
    /// Get context window for a model using model catalog
    func contextWindow(for modelId: String?, models: [ModelInfo] = []) -> Int {
        guard let modelId = modelId else { return defaultContextWindow }
        
        // Try model catalog first (same logic as AppState.contextWindow)
        if let model = models.first(where: { $0.id == modelId }) {
            return model.effectiveContextWindow
        }
        
        // Fallback heuristics for known model families
        if modelId.contains("opus-4-6") {
            return 1_000_000
        } else if modelId.contains("claude-4") || modelId.contains("claude-3-5-sonnet") {
            return 200_000
        } else if modelId.contains("gpt-4") {
            return 128_000
        }
        
        return defaultContextWindow
    }
    
    // MARK: - Memory Events Count
    
    /// Count memory events from today's daily log file (ground truth from file system)
    /// Delegates to HeartbeatHistoryService to avoid duplication
    func countMemoryEvents(for date: Date = Date()) -> Int {
        return HeartbeatHistoryService.shared.countDailyMemoryEvents(for: date)
    }
    
    // MARK: - Time Formatting
    
    /// Format time ago string per spec
    func formatTimeAgo(_ date: Date, now: Date = Date(), useOver: Bool = true) -> String {
        let elapsed = now.timeIntervalSince(date)
        let minutes = Int(elapsed / 60)
        let hours = minutes / 60
        
        if minutes < 1 {
            return "just now"
        } else if minutes < 60 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else if hours < 24 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else {
            return useOver ? "over a day ago" : "a day"
        }
    }
    
}

// MARK: - ClawK Status State

/// Complete state for the ClawK Status card (ground truth data)
struct ClawKStatusState: Equatable {
    let status: ClawKHeartbeatState
    let statusMessage: String
    let statusSubtitle: String
    let lastCheck: Date?
    let nextCheck: Date?
    let intervalMinutes: Int
    var contextPercent: Double?
    var activeSessions: Int
    var memoryEvents: Int
    let isStale: Bool
    let lastError: String?
    
    static let empty = ClawKStatusState(
        status: .unknown,
        statusMessage: "Loading...",
        statusSubtitle: "Checking status",
        lastCheck: nil,
        nextCheck: nil,
        intervalMinutes: 30,
        contextPercent: nil,
        activeSessions: 0,
        memoryEvents: 0,
        isStale: false,
        lastError: nil
    )
}

// MARK: - ClawK Heartbeat State Enum

/// Heartbeat state with associated display properties
enum ClawKHeartbeatState: Equatable {
    case ok
    case alert
    case critical
    case unknown
    
    var icon: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .alert: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
    
    var emoji: String {
        switch self {
        case .ok: return "✓"
        case .alert: return "⚠"
        case .critical: return "✕"
        case .unknown: return "?"
        }
    }
}
