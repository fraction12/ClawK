//
//  HeartbeatHistoryService.swift
//  ClawK
//
//  Reads heartbeat data directly from session JSONL files (source of truth)
//  Replaces fragile SUMMARY line parsing with direct file access
//

import Foundation

/// A single heartbeat entry parsed from session JSONL
struct HeartbeatEntry: Codable {
    let timestamp: Date
    let status: String  // "HEARTBEAT_OK" or "HEARTBEAT_ALERT"
    let contextPercent: Double?
    let sessionsChecked: Int?
    let sessionsActive: Int?
    let statusDescription: String?
}

/// Errors that can occur when loading heartbeat history
enum HeartbeatHistoryError: LocalizedError {
    case sessionsIndexNotFound
    case sessionsIndexParseError
    case mainSessionNotFound
    case sessionFileNotFound(sessionId: String)
    case sessionFileReadError(path: String)
    
    var errorDescription: String? {
        switch self {
        case .sessionsIndexNotFound:
            return "Session index file not found"
        case .sessionsIndexParseError:
            return "Could not parse session index"
        case .mainSessionNotFound:
            return "Main session not configured"
        case .sessionFileNotFound(let sessionId):
            return "Session file not found: \(sessionId)"
        case .sessionFileReadError(let path):
            return "Could not read session file: \(path)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .sessionsIndexNotFound, .sessionsIndexParseError, .mainSessionNotFound:
            return "Check that OpenClaw Gateway is running and has been used at least once."
        case .sessionFileNotFound, .sessionFileReadError:
            return "The session file may have been moved or deleted. Try restarting the Gateway."
        }
    }
}

/// Result type for heartbeat history loading
struct HeartbeatHistoryResult {
    let entries: [HeartbeatEntry]
    let error: HeartbeatHistoryError?
    
    var isSuccess: Bool { error == nil }
    
    static func success(_ entries: [HeartbeatEntry]) -> HeartbeatHistoryResult {
        HeartbeatHistoryResult(entries: entries, error: nil)
    }
    
    static func failure(_ error: HeartbeatHistoryError) -> HeartbeatHistoryResult {
        HeartbeatHistoryResult(entries: [], error: error)
    }
}

/// Service for reading heartbeat history directly from session JSONL files
class HeartbeatHistoryService {
    
    /// Shared instance
    static let shared = HeartbeatHistoryService()
    
    /// Path to the main session JSONL file (legacy - returns nil on error)
    private var mainSessionPath: URL? {
        try? getMainSessionPath()
    }
    
    /// Get path to the main session JSONL file with proper error handling
    /// - Throws: HeartbeatHistoryError with specific failure reason
    /// - Returns: URL to the main session JSONL file
    private func getMainSessionPath() throws -> URL {
        let config = AppConfiguration.shared
        let sessionsDir = URL(fileURLWithPath: config.sessionsPath)
        
        // Read sessions.json to find the main session's sessionId
        let sessionsIndexPath = sessionsDir.appendingPathComponent("sessions.json")
        
        guard FileManager.default.fileExists(atPath: sessionsIndexPath.path) else {
        debugLog("HeartbeatHistoryService: sessions.json not found at \(sessionsIndexPath.path)")
            throw HeartbeatHistoryError.sessionsIndexNotFound
        }
        
        guard let data = try? Data(contentsOf: sessionsIndexPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        debugLog("HeartbeatHistoryService: Could not parse sessions.json")
            throw HeartbeatHistoryError.sessionsIndexParseError
        }
        
        // sessions.json is a flat dictionary where keys are session keys (e.g., "agent:main:main")
        // and values are session objects containing sessionId
        let mainSessionKey = AppConfiguration.shared.mainSessionKey
        guard let mainSession = json[mainSessionKey] as? [String: Any],
              let sessionId = mainSession["sessionId"] as? String else {
        debugLog("HeartbeatHistoryService: Could not find \(mainSessionKey) in sessions.json")
        debugLog("HeartbeatHistoryService: Available keys: \(json.keys.joined(separator: ", "))")
            throw HeartbeatHistoryError.mainSessionNotFound
        }
        
        debugLog("HeartbeatHistoryService: Found main session ID: \(sessionId)")
        
        // Return path to main session JSONL
        let mainSessionFile = sessionsDir.appendingPathComponent("\(sessionId).jsonl")
        
        guard FileManager.default.fileExists(atPath: mainSessionFile.path) else {
        debugLog("HeartbeatHistoryService: Main session file does not exist: \(mainSessionFile.path)")
            throw HeartbeatHistoryError.sessionFileNotFound(sessionId: sessionId)
        }
        
        debugLog("HeartbeatHistoryService: Main session file found: \(mainSessionFile.path)")
        return mainSessionFile
    }
    
    /// Load heartbeat history from the main session JSONL
    /// - Parameter limit: Maximum number of entries to return (default 96 = 24h @ 15min)
    /// - Returns: Array of HeartbeatEntry sorted by timestamp (oldest first)
    func loadHeartbeatHistory(limit: Int = 96) -> [HeartbeatEntry] {
        debugLog("HeartbeatHistoryService: loadHeartbeatHistory() called with limit \(limit)")
        
        guard let sessionPath = mainSessionPath else {
        debugLog("HeartbeatHistoryService: Could not find main session JSONL - mainSessionPath returned nil")
            return []
        }
        
        debugLog("HeartbeatHistoryService: Loading from \(sessionPath.path)")
        let entries = parseHeartbeatsFromJSONL(at: sessionPath, limit: limit)
        debugLog("HeartbeatHistoryService: loadHeartbeatHistory() returning \(entries.count) entries")
        return entries
    }
    
    /// Load heartbeat history with detailed result for UI error display
    /// Preferred over loadHeartbeatHistory() when error feedback is needed
    /// - Parameter limit: Maximum number of entries to return (default 96 = 24h @ 15min)
    /// - Returns: HeartbeatHistoryResult with entries and optional error
    func loadHeartbeatHistoryWithResult(limit: Int = 96) -> HeartbeatHistoryResult {
        debugLog("HeartbeatHistoryService: loadHeartbeatHistoryWithResult() called with limit \(limit)")
        
        do {
            let sessionPath = try getMainSessionPath()
        debugLog("HeartbeatHistoryService: Loading from \(sessionPath.path)")
            let entries = parseHeartbeatsFromJSONL(at: sessionPath, limit: limit)
        debugLog("HeartbeatHistoryService: Returning \(entries.count) entries")
            return .success(entries)
        } catch let error as HeartbeatHistoryError {
        debugLog("HeartbeatHistoryService: Error loading history: \(error.localizedDescription)")
            return .failure(error)
        } catch {
        debugLog("HeartbeatHistoryService: Unexpected error: \(error)")
            return .failure(.sessionsIndexParseError)
        }
    }
    
    /// Load heartbeat history from a specific session JSONL file
    /// - Parameters:
    ///   - sessionId: The session UUID
    ///   - limit: Maximum entries to return
    /// - Returns: Array of HeartbeatEntry
    func loadHeartbeatHistory(sessionId: String, limit: Int = 96) -> [HeartbeatEntry] {
        let sessionPath = URL(fileURLWithPath: AppConfiguration.shared.sessionFilePath(sessionId: sessionId))
        
        return parseHeartbeatsFromJSONL(at: sessionPath, limit: limit)
    }
    
    /// Get the timestamp of the last heartbeat run
    func getLastHeartbeatTime() -> Date? {
        let entries = loadHeartbeatHistory(limit: 10)
        let lastTime = entries.last?.timestamp
        debugLog("HeartbeatHistoryService: getLastHeartbeatTime() = \(lastTime?.description ?? "nil")")
        return lastTime
    }
    
    /// Calculate the next heartbeat time based on last run and interval
    /// - Parameter intervalMinutes: Heartbeat interval in minutes (default 30)
    /// - Returns: Estimated next heartbeat time
    func getNextHeartbeatTime(intervalMinutes: Int = 30) -> Date? {
        guard let lastTime = getLastHeartbeatTime() else {
            return nil
        }
        
        let intervalSeconds = Double(intervalMinutes * 60)
        var nextTime = lastTime.addingTimeInterval(intervalSeconds)
        
        // If calculated time is in the past, project forward
        let now = Date()
        if nextTime < now {
            let secondsSinceLast = now.timeIntervalSince(lastTime)
            let cyclesPassed = ceil(secondsSinceLast / intervalSeconds)
            nextTime = lastTime.addingTimeInterval(cyclesPassed * intervalSeconds)
        }
        
        return nextTime
    }
    
    // MARK: - Private Parsing Methods
    
    /// Parse heartbeat entries from a JSONL file
    private func parseHeartbeatsFromJSONL(at url: URL, limit: Int) -> [HeartbeatEntry] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
        debugLog("HeartbeatHistoryService: Could not read file at \(url.path)")
            return []
        }
        
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        debugLog("HeartbeatHistoryService: Parsing \(lines.count) lines from JSONL")
        
        var entries: [HeartbeatEntry] = []
        var pendingHeartbeatPrompt: (timestamp: Date, line: String)?
        var heartbeatPromptsFound = 0
        var heartbeatResponsesFound = 0
        
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            
            // Look for message entries
            guard json["type"] as? String == "message",
                  let message = json["message"] as? [String: Any],
                  let role = message["role"] as? String else {
                continue
            }
            
            // Get timestamp from the message
            let timestamp: Date?
            if let ts = message["timestamp"] as? Double {
                timestamp = Date(timeIntervalSince1970: ts / 1000.0)
            } else if let ts = json["timestamp"] as? String {
                timestamp = ISO8601DateFormatter().date(from: ts)
            } else {
                timestamp = nil
            }
            
            // Track user heartbeat prompts
            if role == "user" {
                if let content = message["content"] as? [[String: Any]],
                   let textContent = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String {
                    if textContent.contains("Read HEARTBEAT.md") || textContent.contains("HEARTBEAT") {
                        pendingHeartbeatPrompt = (timestamp ?? Date(), line)
                        heartbeatPromptsFound += 1
                    }
                } else if let text = message["content"] as? String {
                    if text.contains("Read HEARTBEAT.md") || text.contains("HEARTBEAT") {
                        pendingHeartbeatPrompt = (timestamp ?? Date(), line)
                        heartbeatPromptsFound += 1
                    }
                }
            }
            
            // Parse assistant heartbeat responses
            if role == "assistant", pendingHeartbeatPrompt != nil {
                if let entry = parseAssistantHeartbeatResponse(message: message, timestamp: timestamp) {
                    entries.append(entry)
                    heartbeatResponsesFound += 1
                    pendingHeartbeatPrompt = nil  // Only clear when we found a valid heartbeat
                }
                // Don't clear pendingHeartbeatPrompt if this assistant message
                // doesn't contain HEARTBEAT_OK/ALERT - there may be more messages
            }
        }
        
        debugLog("HeartbeatHistoryService: Found \(heartbeatPromptsFound) heartbeat prompts, \(heartbeatResponsesFound) valid responses")
        
        // Sort by timestamp and limit
        entries.sort { $0.timestamp < $1.timestamp }
        
        debugLog("HeartbeatHistoryService: Total entries before filtering: \(entries.count)")
        
        // Filter to last 24 hours
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let beforeFilterCount = entries.count
        entries = entries.filter { $0.timestamp > cutoff }
        debugLog("HeartbeatHistoryService: After 24h filter: \(entries.count) (removed \(beforeFilterCount - entries.count))")
        
        // Return most recent entries up to limit
        if entries.count > limit {
            entries = Array(entries.suffix(limit))
        }
        
        debugLog("HeartbeatHistoryService: Final count: \(entries.count)")
        if let lastEntry = entries.last {
        debugLog("HeartbeatHistoryService: Last entry timestamp: \(lastEntry.timestamp), status: \(lastEntry.status)")
        }
        
        return entries
    }
    
    /// Parse an assistant message to extract heartbeat data
    private func parseAssistantHeartbeatResponse(message: [String: Any], timestamp: Date?) -> HeartbeatEntry? {
        // Extract text content from message
        var textContent = ""
        
        if let content = message["content"] as? [[String: Any]] {
            for block in content {
                if block["type"] as? String == "text",
                   let text = block["text"] as? String {
                    textContent += text + "\n"
                }
            }
        } else if let text = message["content"] as? String {
            textContent = text
        }
        
        // Must contain HEARTBEAT_OK or HEARTBEAT_ALERT
        guard textContent.contains("HEARTBEAT_OK") || textContent.contains("HEARTBEAT_ALERT") else {
            // Debug: log if we expected this to be a heartbeat response
            if textContent.contains("HEARTBEAT") {
        debugLog("HeartbeatHistoryService: Found HEARTBEAT but not OK/ALERT in: \(String(textContent.prefix(100)))...")
            }
            return nil
        }
        
        debugLog("HeartbeatHistoryService: Parsing valid heartbeat response at \(timestamp?.description ?? "nil")")
        
        // Determine status
        let status = textContent.contains("HEARTBEAT_OK") ? "HEARTBEAT_OK" : "HEARTBEAT_ALERT"
        
        // Parse SUMMARY line if present
        var sessionsChecked: Int?
        var sessionsActive: Int?
        var contextPercent: Double?
        var statusDescription: String?
        
        if let summaryRange = textContent.range(of: "SUMMARY: ") {
            let afterSummary = String(textContent[summaryRange.upperBound...])
            let summaryLine = afterSummary.components(separatedBy: "\n").first ?? afterSummary
            
            // Parse "Sessions: X checked, Y active | Context: Main Z%, Telegram W% | Status: ..."
            let parts = summaryLine.components(separatedBy: " | ")
            
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                
                // Sessions: X checked, Y active
                if trimmed.hasPrefix("Sessions:") {
                    let sessionsStr = trimmed.replacingOccurrences(of: "Sessions:", with: "")
                    if let match = sessionsStr.range(of: #"(\d+)\s*checked"#, options: .regularExpression) {
                        let numStr = sessionsStr[match].filter { $0.isNumber }
                        sessionsChecked = Int(numStr)
                    }
                    if let match = sessionsStr.range(of: #"(\d+)\s*active"#, options: .regularExpression) {
                        let numStr = sessionsStr[match].filter { $0.isNumber }
                        sessionsActive = Int(numStr)
                    }
                }
                
                // Context: Main X%, Telegram Y% OR Context: X%
                else if trimmed.hasPrefix("Context:") {
                    let contextStr = trimmed.replacingOccurrences(of: "Context:", with: "")
                    // Look for "Main X%" pattern first
                    if let mainMatch = contextStr.range(of: #"Main\s+(\d+(?:\.\d+)?)\s*%"#, options: .regularExpression) {
                        let numStr = contextStr[mainMatch]
                            .replacingOccurrences(of: "Main", with: "")
                            .replacingOccurrences(of: "%", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        contextPercent = Double(numStr)
                    } else {
                        // Fallback: just extract first percentage
                        let numStr = contextStr
                            .replacingOccurrences(of: "%", with: "")
                            .trimmingCharacters(in: .whitespaces)
                            .components(separatedBy: CharacterSet.decimalDigits.inverted)
                            .joined()
                        if let firstNum = numStr.components(separatedBy: " ").first {
                            contextPercent = Double(firstNum)
                        }
                    }
                }
                
                // Status: description
                else if trimmed.hasPrefix("Status:") {
                    statusDescription = trimmed
                        .replacingOccurrences(of: "Status:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        // Use message timestamp or fall back to now
        let entryTimestamp = timestamp ?? Date()
        
        return HeartbeatEntry(
            timestamp: entryTimestamp,
            status: status,
            contextPercent: contextPercent,
            sessionsChecked: sessionsChecked,
            sessionsActive: sessionsActive,
            statusDescription: statusDescription
        )
    }
    
    /// Count memory events logged today by parsing daily log file
    /// - Parameter date: The date to check (defaults to today)
    /// - Returns: Number of "## HH:MM" entries in the daily log
    func countDailyMemoryEvents(for date: Date = Date()) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        // Path to daily log file
        let memoryPath = URL(fileURLWithPath: AppConfiguration.shared.dailyLogPath(for: date))
        
        guard let content = try? String(contentsOf: memoryPath, encoding: .utf8) else {
            return 0
        }
        
        // Count "## HH:MM" headers
        var count = 0
        
        let parts = content.components(separatedBy: "\n## ")
        for part in parts.dropFirst() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 5 {
                let prefix = String(trimmed.prefix(5))
                if prefix.contains(":") && prefix.first?.isNumber == true {
                    count += 1
                }
            }
        }
        
        // Check if file starts with "## HH:MM"
        if content.hasPrefix("## ") {
            let firstLine = content.components(separatedBy: "\n").first ?? ""
            if firstLine.count >= 8 {
                let afterHash = String(firstLine.dropFirst(3))
                if afterHash.count >= 5 && afterHash.contains(":") && afterHash.first?.isNumber == true {
                    count += 1
                }
            }
        }
        
        return count
    }
}
