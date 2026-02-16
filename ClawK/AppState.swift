//
//  AppState.swift
//  ClawK
//
//  Global state management for the app
//

import SwiftUI
import Combine
import AppKit
// Widget support removed

// MARK: - Extensions

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

// MARK: - Canvas State

struct CanvasState {
    var isActive: Bool = false
    var target: String = "host"
    var currentURL: String?
    var windowSize: String?
    var snapshotData: Data?
    var snapshotTimestamp: Date?
    var lastUpdate: Date?
    var error: String?
    var isLoading: Bool = false
    var activityLog: [CanvasActivityEntry] = []
    
    /// Maximum snapshot data size to keep in memory (2MB)
    static let maxSnapshotSize = 2 * 1024 * 1024
    
    static let empty = CanvasState()
    
    /// Clear snapshot data if it exceeds size limit
    mutating func trimSnapshotIfNeeded() {
        if let data = snapshotData, data.count > Self.maxSnapshotSize {
            // Data too large - clear it to save memory
            snapshotData = nil
            debugLog("Canvas: Snapshot data cleared (exceeded \(Self.maxSnapshotSize) bytes)")
        }
    }
}

struct CanvasActivityEntry: Identifiable {
    let id = UUID()
    let action: String
    let timestamp: Date
    let success: Bool
    let details: String?
}

@MainActor
class AppState: ObservableObject {
    // MARK: - Published State
    @Published var cronJobs: [CronJob] = []
    @Published var sessions: [SessionInfo] = []
    @Published var models: [ModelInfo] = []
    @Published var isLoading = false
    @Published var isInitialLoad = true  // True until first successful refresh
    @Published var isManualRefresh = false  // True only during manual refresh button clicks
    @Published var isConnected = false
    @Published var lastError: String?
    @Published var lastRefresh: Date?
    @Published var heartbeatStatus: HeartbeatStatus = .empty
    @Published var heartbeatHistory: [HeartbeatHistory] = []
    @Published var systemStatus: SystemStatus = .empty
    
    // MARK: - New Ground Truth Status (ClawK Status Card)
    @Published var clawkStatus: ClawKStatusState = .empty
    @Published var canvasState: CanvasState = .empty
    
    // MARK: - Persistent Settings
    /// Monochrome mode toggle (persisted across app restarts)
    @AppStorage("isMonochrome") var isMonochrome = false
    
    // MARK: - Claude CLI Usage
    @Published var quotaStatus: ClaudeMaxQuota?
    @Published var quotaError: String?
    
    // MARK: - Context Window Cache
    /// Cache for context window lookups to avoid repeated linear searches
    private var contextWindowCache: [String: Int] = [:]
    private var contextWindowCacheModelCount: Int = 0
    
    // MARK: - Heartbeat History Optimization
    /// Track if heartbeat history needs saving (dirty flag)
    private var heartbeatHistoryNeedsSave = false
    /// Last save timestamp to throttle writes
    private var lastHeartbeatHistorySave: Date?
    /// Minimum interval between saves (5 minutes)
    private static let heartbeatSaveInterval: TimeInterval = 300
    
    // MARK: - Widget Export Optimization
    // Widget support removed
    
    // MARK: - Heartbeat History Persistence
    private let heartbeatHistoryKey = "heartbeatHistory"
    private let maxHistoryEntries = 96  // 24 hours at 15-min intervals
    private let heartbeatMigrationKey = "heartbeatHistoryMigration_v3"  // Increment to re-run migration (v3: memory events graph)
    
    // MARK: - Settings
    /// Default polling interval in seconds
    private static let defaultPollingInterval: Double = 5.0
    private static let pollingIntervalRange: ClosedRange<Double> = 1...30
    
    /// Polling interval in seconds (synced with UserDefaults)
    /// Returns default of 5.0 if not set (UserDefaults returns 0.0 for missing keys)
    var pollingInterval: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: "pollingInterval")
            // UserDefaults returns 0.0 for missing Double keys - use default instead
            if stored <= 0 {
                return Self.defaultPollingInterval
            }
            return stored.clamped(to: Self.pollingIntervalRange)
        }
        set {
            let clamped = newValue.clamped(to: Self.pollingIntervalRange)
            UserDefaults.standard.set(clamped, forKey: "pollingInterval")
        }
    }
    
    // MARK: - Gateway Client
    private let gateway: GatewayClient
    private var refreshTask: Task<Void, Never>?
    
    // MARK: - Computed Properties
    // MARK: - Skeleton Loading Helpers
    
    /// Standardized skeleton state check - shows skeleton during initial load when data is empty
    func showSkeleton<T: Collection>(for data: T) -> Bool {
        isInitialLoad && data.isEmpty
    }
    
    /// Skeleton state for optional data
    func showSkeleton<T>(for data: T?) -> Bool {
        isInitialLoad && data == nil
    }
    
    var runningJobs: [CronJob] {
        cronJobs.filter { $0.isRunning }
    }
    
    var upcomingJobs: [CronJob] {
        cronJobs
            .filter { $0.isEnabled && !$0.isRunning }
            .sorted { ($0.state?.nextRunAtMs ?? 0) < ($1.state?.nextRunAtMs ?? 0) }
    }
    
    var mainSession: SessionInfo? {
        sessions.first { $0.key == AppConfiguration.shared.mainSessionKey }
    }
    
    /// Telegram session - the primary user-facing interaction point
    /// Matches sessions with key pattern "agent:{agentName}:telegram:*"
    var telegramSession: SessionInfo? {
        sessions
            .filter { $0.key.hasPrefix(AppConfiguration.shared.telegramSessionKeyPrefix) }
            .sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
            .first
    }
    
    var activeSubagents: [SessionInfo] {
        sessions.filter { $0.key.contains("subagent") }
    }
    
    /// Active main conversation sessions (excludes cron, subagents)
    /// Sorted by most recent activity first
    var activeMainSessions: [SessionInfo] {
        sessions
            .filter { session in
                // Exclude cron sessions
                guard !session.key.contains("cron:") else { return false }
                // Exclude subagents
                guard !session.key.contains("subagent") else { return false }
                // Include main conversation sessions
                return true
            }
            .sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
    }
    
    var totalTokensUsed: Int {
        sessions.reduce(0) { $0 + ($1.totalTokens ?? 0) }
    }
    
    /// Get actual context window for a model (from model catalog)
    /// Uses caching to avoid repeated linear searches through models array
    func contextWindow(for modelId: String?) -> Int {
        guard let modelId = modelId else { return 200_000 }
        
        // Invalidate cache if models array changed
        if models.count != contextWindowCacheModelCount {
            contextWindowCache.removeAll()
            contextWindowCacheModelCount = models.count
        }
        
        // Check cache first
        if let cached = contextWindowCache[modelId] {
            return cached
        }
        
        // Try to find the model in the catalog
        // Session model may be "claude-opus-4-6" while catalog has "anthropic/claude-opus-4-6"
        let result: Int
        if let model = models.first(where: { $0.id == modelId || $0.id.hasSuffix("/\(modelId)") || modelId.hasSuffix("/\($0.id)") }) {
            result = model.effectiveContextWindow
        } else if modelId.contains("opus-4-6") {
            result = 200_000  // Claude Opus 4.6
        } else if modelId.contains("claude-4") || modelId.contains("claude-3-5-sonnet") {
            result = 200_000  // Claude 4.x and 3.5 models
        } else if modelId.contains("gpt-4") {
            result = 128_000
        } else {
            result = 200_000  // Conservative default
        }
        
        // Cache the result
        contextWindowCache[modelId] = result
        return result
    }
    
    // MARK: - Initialization
    init() {
        self.gateway = GatewayClient()
        loadHeartbeatHistory()
    }
    
    // MARK: - Heartbeat History Management
    
    /// Load heartbeat history from UserDefaults
    private func loadHeartbeatHistory() {
        // Check if we need to run migration (v3: switching to memory events graph)
        if !UserDefaults.standard.bool(forKey: heartbeatMigrationKey) {
            // Clear old history when switching graph type
            // Old data showed context%, new graph shows memory events
            UserDefaults.standard.removeObject(forKey: heartbeatHistoryKey)
            UserDefaults.standard.set(true, forKey: heartbeatMigrationKey)
            debugLog("Heartbeat history migration v3: cleared for memory events graph")
            return  // Start fresh
        }
        
        guard let data = UserDefaults.standard.data(forKey: heartbeatHistoryKey) else { return }
        do {
            let history = try JSONDecoder().decode([HeartbeatHistory].self, from: data)
            // Filter to only keep last 24 hours
            let cutoff = Date().addingTimeInterval(-24 * 3600)
            self.heartbeatHistory = history.filter { $0.timestamp > cutoff }
        } catch {
            debugLog("Failed to load heartbeat history: \(error)")
        }
    }
    
    /// Save heartbeat history to UserDefaults (throttled to avoid excessive writes)
    /// - Parameter force: If true, save immediately regardless of throttle
    private func saveHeartbeatHistory(force: Bool = false) {
        // Mark as needing save
        heartbeatHistoryNeedsSave = true
        
        // Check if we should save now (throttle)
        if !force, let lastSave = lastHeartbeatHistorySave {
            let elapsed = Date().timeIntervalSince(lastSave)
            if elapsed < Self.heartbeatSaveInterval {
                return  // Too soon, skip this save
            }
        }
        
        // Perform save
        guard heartbeatHistoryNeedsSave else { return }
        
        do {
            let data = try JSONEncoder().encode(heartbeatHistory)
            UserDefaults.standard.set(data, forKey: heartbeatHistoryKey)
            lastHeartbeatHistorySave = Date()
            heartbeatHistoryNeedsSave = false
        } catch {
            debugLog("Failed to save heartbeat history: \(error)")
        }
    }
    
    /// Force save any pending heartbeat history (call on app termination)
    func flushHeartbeatHistory() {
        saveHeartbeatHistory(force: true)
    }
    
    /// Record a new heartbeat entry to history
    private func recordHeartbeatEntry() {
        guard let status = heartbeatStatus.lastCheck else { return }
        
        // Check if we already have an entry for this timestamp (within 1 minute)
        let recentCutoff = status.addingTimeInterval(-60)
        if heartbeatHistory.contains(where: { $0.timestamp > recentCutoff }) {
            return  // Skip duplicate
        }
        
        // Calculate context percent from actual telegram session tokens (ground truth)
        // This is more reliable than parsing heartbeat response SUMMARY lines
        var contextPercent: Double = 0
        
        if let telegram = telegramSession {
            let tokens = telegram.totalTokens ?? 0
            let maxTokens = contextWindow(for: telegram.model)
            if maxTokens > 0 && tokens > 0 {
                contextPercent = (Double(tokens) / Double(maxTokens)) * 100.0
            }
        }

        // Fall back to heartbeat-parsed value if no telegram session data
        if contextPercent == 0 {
            if let parsedPercent = heartbeatStatus.contextPercent, parsedPercent > 0 {
                contextPercent = parsedPercent
            }
        }
        
        // Calculate memory events using HeartbeatHistoryService (ground truth from files)
        let memoryEvents = HeartbeatHistoryService.shared.countDailyMemoryEvents(for: status)
        
        let entry = HeartbeatHistory(
            timestamp: status,
            status: heartbeatStatus.status == .ok ? "HEARTBEAT_OK" : "HEARTBEAT_ALERT",
            contextPercent: contextPercent,
            sessionsChecked: heartbeatStatus.sessionsChecked ?? sessions.count,
            sessionsActive: heartbeatStatus.sessionsActive ?? activeMainSessions.count,
            memoryEventsLogged: memoryEvents,
            statusDescription: heartbeatStatus.statusDescription ?? ""
        )
        
        heartbeatHistory.append(entry)
        
        // Keep only last 24 hours (max 96 entries)
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        heartbeatHistory.removeAll { $0.timestamp < cutoff }
        
        // Trim to max entries if needed
        if heartbeatHistory.count > maxHistoryEntries {
            heartbeatHistory = Array(heartbeatHistory.suffix(maxHistoryEntries))
        }
        
        // Sort by timestamp
        heartbeatHistory.sort { $0.timestamp < $1.timestamp }
        
        // Persist
        saveHeartbeatHistory()
    }
    
    // MARK: - Data Fetching
    func startPolling() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                // Read interval from UserDefaults (default 5s if not set)
                let interval = pollingInterval > 0 ? pollingInterval : 5.0
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }
    
    func stopPolling() {
        refreshTask?.cancel()
        refreshTask = nil
    }
    
    /// Trigger a manual refresh (shows loading indicators)
    func manualRefresh() async {
        isManualRefresh = true
        defer { isManualRefresh = false }
        await refresh()
    }
    
    func refresh() async {
        // Only show loading indicator on initial load or manual refresh
        // Background auto-polling should be silent
        let shouldShowLoading = isInitialLoad || isManualRefresh
        if shouldShowLoading {
            isLoading = true
        }
        defer { 
            if shouldShowLoading {
                isLoading = false
            }
            // Widget export removed
        }
        
        // Measure gateway latency
        let startTime = Date()
        
        do {
            // Fetch models (only once or when empty)
            if models.isEmpty {
                do {
                    let modelsResult = try await gateway.fetchModels()
                    self.models = modelsResult
                } catch {
                    // Silently fail - we'll use hardcoded defaults in contextWindow(for:)
                    debugLog("Failed to fetch models: \(error)")
                }
            }
            
            // Fetch cron jobs
            let cronResult = try await gateway.fetchCronJobs()
            self.cronJobs = cronResult
            
            // Fetch sessions
            let sessionsResult = try await gateway.fetchSessions()
            self.sessions = sessionsResult
            
            // Calculate latency from first API call
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            
            // Update heartbeat status from cron jobs
            await updateHeartbeatStatus()
            
            // Update system status (including nodes)
            await updateSystemStatus(latencyMs: latencyMs)
            
            // Update Claude Max quota (async, doesn't block main refresh)
            await refreshQuota()
            
            // Only update published properties when values change to prevent UI flash
            if !self.isConnected {
                self.isConnected = true
            }
            if self.lastError != nil {
                self.lastError = nil
            }
            // Mark initial load as complete after first successful refresh
            if self.isInitialLoad {
                self.isInitialLoad = false
            }
            // Only update lastRefresh if it's been at least 5 seconds (reduces UI noise)
            if let lastRefresh = self.lastRefresh {
                if Date().timeIntervalSince(lastRefresh) >= 5.0 {
                    self.lastRefresh = Date()
                }
            } else {
                self.lastRefresh = Date()
            }
        } catch {
            if self.isConnected {
                self.isConnected = false
            }
            if self.lastError != error.localizedDescription {
                self.lastError = error.localizedDescription
            }
        }
    }
    
    // Widget data export removed
    
    // MARK: - Heartbeat & System Status
    
    private func updateHeartbeatStatus() async {
        // Calculate ground truth status using HeartbeatService
        await updateClawKStatus()
        
        // Fetch heartbeat data from main session (legacy - for backward compatibility)
        await fetchHeartbeatFromSession()
        
        // Record entry to history (will skip duplicates)
        recordHeartbeatEntry()
    }
    
    /// Update ClawK Status using ground truth from Gateway config + sessions.json
    private func updateClawKStatus() async {
        let service = HeartbeatService.shared
        
        // Fetch heartbeat config from Gateway health API (ground truth)
        var config: HeartbeatConfig? = nil
        var apiError: Error? = nil
        
        if isConnected {
            do {
                let health = try await gateway.fetchGatewayHealth()
                config = service.getHeartbeatConfig(from: health)
            } catch {
                apiError = error
            }
        } else {
            apiError = GatewayError.serverError("Not connected")
        }
        
        // Get last heartbeat timestamp from sessions.json (ground truth)
        let lastHeartbeatSent = service.getLastHeartbeatSent()
        
        // Calculate status from config + lastHeartbeatSent (ground truth)
        var status = service.determineStatus(
            config: config,
            lastHeartbeatSent: lastHeartbeatSent,
            apiError: apiError,
            now: Date()
        )
        
        // Calculate context percent and active sessions from sessions API (ground truth)
        let (contextPercent, activeCount, _) = service.calculateContextPercent(
            sessions: sessions,
            models: models,
            now: Date()
        )
        status.contextPercent = contextPercent
        status.activeSessions = activeCount
        
        // Count memory events from file system (ground truth)
        status.memoryEvents = service.countMemoryEvents()
        
        // Update published state
        self.clawkStatus = status
    }
    
    /// Fetch and parse heartbeat data from main session JSONL (source of truth)
    /// Uses HeartbeatHistoryService to read directly from session files
    private func fetchHeartbeatFromSession() async {
        // Load heartbeat history from JSONL files (ground truth)
        let heartbeatService = HeartbeatHistoryService.shared
        let entries = heartbeatService.loadHeartbeatHistory(limit: 20)
        
        // Convert entries to HeartbeatCheck format
        var recentChecks: [HeartbeatCheck] = entries.map { entry in
            HeartbeatCheck(
                timestamp: entry.timestamp,
                status: entry.status == "HEARTBEAT_OK" ? .ok : .alert
            )
        }
        
        // Sort by most recent first and limit to 10
        recentChecks.sort { $0.timestamp > $1.timestamp }
        recentChecks = Array(recentChecks.prefix(10))
        
        // Get last heartbeat data
        let lastHeartbeatTime = heartbeatService.getLastHeartbeatTime()
        let lastEntry = entries.last
        
        // Context% comes from sessions_list (more reliable than SUMMARY parsing)
        // This is already calculated in recordHeartbeatEntry() from telegram session tokens
        let sessionsChecked = lastEntry?.sessionsChecked ?? sessions.count
        let sessionsActive = lastEntry?.sessionsActive ?? activeMainSessions.count
        let statusDescription = lastEntry?.statusDescription
        
        // Context percent: prefer live calculation from sessions_list
        var contextPercent: Double? = nil
        if let telegram = telegramSession {
            let tokens = telegram.totalTokens ?? 0
            let maxTokens = contextWindow(for: telegram.model)
            if maxTokens > 0 && tokens > 0 {
                contextPercent = (Double(tokens) / Double(maxTokens)) * 100.0
            }
        }
        // Fall back to parsed value if live calculation fails
        if contextPercent == nil {
            contextPercent = lastEntry?.contextPercent
        }
        
        // Calculate next check - prefer actual cron schedule if available
        var nextCheck: Date? = nil
        var heartbeatInterval = 30 // Default 30 minutes
        
        // Look for heartbeat cron job to get actual next run time
        let heartbeatCron = self.cronJobs.first { job in
            let name = job.name.lowercased()
            return job.isEnabled && (name.contains("heartbeat") || name.contains("heart"))
        }
        
        // Get interval from cron schedule if available
        if let everyMs = heartbeatCron?.schedule.everyMs {
            heartbeatInterval = Int(everyMs / 60000)
        }
        
        if let cron = heartbeatCron, let nextRunAtMs = cron.state?.nextRunAtMs {
            // Use actual cron schedule - most reliable source
            nextCheck = Date(timeIntervalSince1970: Double(nextRunAtMs) / 1000)
        } else {
            // Fall back to HeartbeatHistoryService calculation
            nextCheck = heartbeatService.getNextHeartbeatTime(intervalMinutes: heartbeatInterval)
        }
        
        // Determine overall status from most recent check
        let overallStatus: HeartbeatState = recentChecks.first?.status ?? .unknown
        
        // Check for issues - if last heartbeat was >35 minutes ago
        var issues: [HeartbeatIssue] = []
        if let last = lastHeartbeatTime {
            let timeSinceLastCheck = Date().timeIntervalSince(last)
            if timeSinceLastCheck > 35 * 60 {
                issues.append(HeartbeatIssue(
                    title: "Heartbeat Overdue",
                    description: "Last heartbeat was \(Int(timeSinceLastCheck / 60)) minutes ago",
                    severity: .alert
                ))
            }
        }
        
        // Memory events from direct file count (not SUMMARY parsing)
        let memoryEventsLogged = heartbeatService.countDailyMemoryEvents()
        
        // Update on main actor
        await MainActor.run {
            self.heartbeatStatus = HeartbeatStatus(
                lastCheck: lastHeartbeatTime,
                nextCheck: nextCheck,
                status: overallStatus,
                intervalMinutes: heartbeatInterval,
                recentChecks: recentChecks,
                issues: issues,
                sessionsChecked: sessionsChecked,
                sessionsActive: sessionsActive,
                memoryEventsLogged: memoryEventsLogged,
                contextPercent: contextPercent,
                statusDescription: statusDescription
            )
        }
    }
    
    private func updateSystemStatus(latencyMs: Int? = nil) async {
        // Calculate time since last session activity (not actual uptime)
        let lastActivitySeconds = mainSession.flatMap { session in
            session.lastUpdatedDate.map { Int(Date().timeIntervalSince($0)) }
        }
        
        // Fetch nodes status
        var nodeCount = 0
        var connectedNodes = 0
        
        do {
            let nodesResult = try await gateway.fetchNodesStatus()
            nodeCount = nodesResult.total
            connectedNodes = nodesResult.connected
        } catch {
            // Silently fail - nodes status will show 0/0
            debugLog("Failed to fetch nodes status: \(error)")
        }
        
        systemStatus = SystemStatus(
            gatewayConnected: isConnected,
            gatewayLatencyMs: latencyMs,
            nodeCount: nodeCount,
            connectedNodes: connectedNodes,
            lastActivitySeconds: lastActivitySeconds,
            lastHealthCheck: lastRefresh
        )
    }
    
    // MARK: - Claude Max Quota
    
    /// Refresh Claude CLI usage data
    func refreshQuota() async {
        let quota = await QuotaService.shared.fetchQuota()
        
        await MainActor.run {
            // Always update quota status
            self.quotaStatus = quota
            
            // Set error message based on data source
            if quota.dataSource == .none {
                self.quotaError = "No quota data available. Check Console.app for errors (filter: QuotaService)"
            } else if quota.dataSource == .localFiles && !quota.hasPercentageData {
                self.quotaError = "CLI usage only. Desktop App API failed - check Console.app logs."
            } else {
                self.quotaError = nil
            }
        }
    }
    
    /// Force refresh quota (bypass any caching)
    func forceRefreshQuota() async {
        let quota = await QuotaService.shared.fetchQuota()
        await MainActor.run {
            self.quotaStatus = quota
        }
    }
    
    // MARK: - Send Message
    
    func sendMessage(_ message: String) async throws {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Find main session key
        let targetKey = mainSession?.key
        
        let success = try await gateway.sendMessage(message, toSession: targetKey)
        if !success {
            throw GatewayError.serverError("Message delivery failed")
        }
    }
    
    // MARK: - Canvas Methods
    
    private func logCanvasActivity(_ action: String, success: Bool, details: String? = nil) {
        let entry = CanvasActivityEntry(
            action: action,
            timestamp: Date(),
            success: success,
            details: details
        )
        canvasState.activityLog.insert(entry, at: 0)
        // Keep only last 20 entries
        if canvasState.activityLog.count > 20 {
            canvasState.activityLog = Array(canvasState.activityLog.prefix(20))
        }
    }
    
    func refreshCanvas() async {
        canvasState.isLoading = true
        defer { canvasState.isLoading = false }
        
        // Try to get canvas status via snapshot (lightweight check)
        do {
            let imageData = try await gateway.canvasSnapshot(target: canvasState.target)
            
            // Success means canvas is active
            canvasState.isActive = true
            canvasState.snapshotData = imageData
            canvasState.snapshotTimestamp = Date()
            canvasState.lastUpdate = Date()
            canvasState.error = nil
            
            // Trim oversized snapshots to save memory
            canvasState.trimSnapshotIfNeeded()
            
            // Extract size from image
            if let nsImage = NSImage(data: imageData) {
                let width = Int(nsImage.size.width)
                let height = Int(nsImage.size.height)
                canvasState.windowSize = "\(width) × \(height)"
            }
        } catch {
            // Snapshot failed - but don't immediately mark as inactive
            // (canvas might still be loading)
            canvasState.lastUpdate = Date()
            
            // Don't show error for common "not ready" cases
            let errorMsg = error.localizedDescription
            if errorMsg.contains("404") || errorMsg.contains("not found") || 
               errorMsg.contains("No canvas") || errorMsg.contains("No image data") {
                canvasState.error = nil
                // Keep previous active state - canvas might still be loading
            } else {
                canvasState.error = errorMsg
            }
        }
    }
    
    /// Waits for canvas to be ready using exponential backoff.
    /// Checks readiness by attempting a lightweight JavaScript evaluation.
    /// - Parameters:
    ///   - maxAttempts: Maximum number of retry attempts (default: 5)
    ///   - baseDelayMs: Initial delay in milliseconds (default: 200)
    /// - Returns: true if canvas became ready, false if max attempts exceeded
    private func waitForCanvasReady(maxAttempts: Int = 5, baseDelayMs: UInt64 = 200) async -> Bool {
        for attempt in 1...maxAttempts {
            do {
                // Use a simple JS eval as readiness check - faster than snapshot
                _ = try await gateway.canvasEval(javaScript: "document.readyState", target: canvasState.target)
                return true
            } catch {
                // Canvas not ready - wait with exponential backoff
                let delayMs = baseDelayMs * UInt64(1 << (attempt - 1)) // 200, 400, 800, 1600, 3200ms
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                
                if attempt == maxAttempts {
                    debugLog("Canvas: Window not ready after \(maxAttempts) attempts")
                }
            }
        }
        return false
    }
    
    /// Attempts to navigate the canvas with retry logic.
    /// - Parameters:
    ///   - url: Target URL to navigate to
    ///   - maxRetries: Maximum retry attempts (default: 3)
    /// - Returns: true if navigation succeeded, false otherwise
    private func navigateWithRetry(to url: String, maxRetries: Int = 3) async -> Bool {
        for attempt in 1...maxRetries {
            do {
                try await gateway.canvasNavigate(url: url, target: canvasState.target)
                return true
            } catch {
                debugLog("Canvas: Navigate attempt \(attempt)/\(maxRetries) failed: \(error.localizedDescription)")
                
                if attempt < maxRetries {
                    // Wait before retry: 500ms, 1000ms, 2000ms
                    let delayMs = UInt64(500 * (1 << (attempt - 1)))
                    try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                }
            }
        }
        return false
    }
    
    func canvasPresent(url: String? = nil) async {
        canvasState.isLoading = true
        defer { canvasState.isLoading = false }
        
        do {
            try await gateway.canvasPresent(url: url, target: canvasState.target)
            canvasState.isActive = true
            canvasState.error = nil
            if let url = url {
                canvasState.currentURL = url
            }
            logCanvasActivity("Present", success: true, details: url)
            
            // Navigate to URL if provided (with proper readiness check and retry)
            if let url = url, !url.isEmpty && url != "about:blank" {
                // Wait for canvas window to be ready before navigating
                let isReady = await waitForCanvasReady(maxAttempts: 5, baseDelayMs: 200)
                
                if isReady {
                    // Attempt navigation with retries
                    let navigated = await navigateWithRetry(to: url, maxRetries: 3)
                    
                    if navigated {
                        logCanvasActivity("Navigate", success: true, details: url)
                    } else {
                        // Navigation failed after retries - log but don't block
                        logCanvasActivity("Navigate", success: false, details: "Failed after retries: \(url)")
                        canvasState.error = "Navigation failed - page may not have loaded correctly"
                    }
                } else {
                    // Canvas didn't become ready - log the issue
                    logCanvasActivity("Navigate", success: false, details: "Canvas not ready for: \(url)")
                    canvasState.error = "Canvas window not ready for navigation"
                }
            }
            
            // Wait for page content to load before snapshot (reduced from 4s)
            // The readiness check above ensures the window is ready, so 2s for content is sufficient
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await refreshCanvas()
        } catch {
            canvasState.error = error.localizedDescription
            logCanvasActivity("Present", success: false, details: error.localizedDescription)
        }
    }
    
    func canvasHide() async {
        canvasState.isLoading = true
        defer { canvasState.isLoading = false }
        
        do {
            try await gateway.canvasHide(target: canvasState.target)
            canvasState.isActive = false
            canvasState.snapshotData = nil
            canvasState.error = nil
            canvasState.lastUpdate = Date()
            logCanvasActivity("Hide", success: true)
        } catch {
            canvasState.error = error.localizedDescription
            logCanvasActivity("Hide", success: false, details: error.localizedDescription)
        }
    }
    
    func canvasNavigate(to urlString: String) async {
        canvasState.isLoading = true
        defer { canvasState.isLoading = false }
        
        do {
            try await gateway.canvasNavigate(url: urlString, target: canvasState.target)
            canvasState.currentURL = urlString
            canvasState.error = nil
            logCanvasActivity("Navigate", success: true, details: urlString)
            
            // Give page time to load, then refresh
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await refreshCanvas()
        } catch {
            canvasState.error = error.localizedDescription
            logCanvasActivity("Navigate", success: false, details: error.localizedDescription)
        }
    }
    
    func canvasTakeSnapshot() async {
        canvasState.isLoading = true
        defer { canvasState.isLoading = false }
        
        do {
            let imageData = try await gateway.canvasSnapshot(target: canvasState.target)
            canvasState.snapshotData = imageData
            canvasState.snapshotTimestamp = Date()
            canvasState.error = nil
            
            // Update window size
            if let nsImage = NSImage(data: imageData) {
                let width = Int(nsImage.size.width)
                let height = Int(nsImage.size.height)
                canvasState.windowSize = "\(width) × \(height)"
            }
            
            // Trim oversized snapshots to save memory
            canvasState.trimSnapshotIfNeeded()
            
            logCanvasActivity("Snapshot", success: true)
        } catch {
            canvasState.error = error.localizedDescription
            logCanvasActivity("Snapshot", success: false, details: error.localizedDescription)
        }
    }
    
    func canvasExecuteJS(_ javaScript: String) async -> String? {
        canvasState.isLoading = true
        defer { canvasState.isLoading = false }
        
        do {
            let result = try await gateway.canvasEval(javaScript: javaScript, target: canvasState.target)
            canvasState.error = nil
            logCanvasActivity("Execute JS", success: true, details: String(javaScript.prefix(50)))
            return result
        } catch {
            canvasState.error = error.localizedDescription
            logCanvasActivity("Execute JS", success: false, details: error.localizedDescription)
            return nil
        }
    }
    
    func setCanvasTarget(_ target: String) {
        canvasState.target = target
        // Clear snapshot when target changes
        canvasState.snapshotData = nil
        canvasState.isActive = false
        // M3 Fix: Check new target's state after changing
        Task { await refreshCanvas() }
    }
    
    func dismissCanvasError() {
        canvasState.error = nil
    }
}
