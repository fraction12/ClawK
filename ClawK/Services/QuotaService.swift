//
//  QuotaService.swift
//  ClawK
//
//  Claude usage tracking service - Desktop App API + Local file aggregation
//

import Foundation
import SQLite3
import Security

/// Service for tracking Claude usage from multiple sources
class QuotaService {
    
    // MARK: - Singleton
    
    static let shared = QuotaService()
    private init() {}
    
    // MARK: - Paths
    
    private var homeDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }
    
    private var claudeProjectsPath: URL {
        homeDir.appendingPathComponent(".claude/projects")
    }
    
    private var statsCachePath: URL {
        homeDir.appendingPathComponent(".claude/stats-cache.json")
    }
    
    private var claudeDesktopCookiesPath: URL {
        homeDir.appendingPathComponent("Library/Application Support/Claude/Cookies")
    }
    
    // MARK: - Main Fetch Method
    
    /// Fetch usage with priority: Desktop App API > Local Files
    func fetchQuota() async -> ClaudeMaxQuota {
        // Try Claude Desktop App API first (highest priority)
        do {
            let quota = try await fetchFromClaudeDesktopApp()
            debugLog("QuotaService: Loaded from Claude Desktop App - Session: \(quota.sessionWindow.percentUsed)%, Weekly: \(quota.weeklyWindow.percentUsed)%")
            return quota
        } catch {
            debugLog("QuotaService: Desktop App API failed: \(error.localizedDescription)")
        }
        
        // Fall back to local files
        do {
            let quota = try aggregateLocalUsage()
            debugLog("QuotaService: Loaded from local files - \(quota.totalTokensUsed) tokens")
            return quota
        } catch {
            debugLog("QuotaService: Local aggregation failed: \(error)")
        }
        
        // No data available
        return ClaudeMaxQuota.empty
    }
    
    // MARK: - Claude Desktop App API
    
    /// Fetch quota from Claude Desktop App via its session cookies
    private func fetchFromClaudeDesktopApp() async throws -> ClaudeMaxQuota {
        // Step 1: Get session key from Claude Desktop app cookies
        guard let sessionKey = try extractSessionKey() else {
            throw QuotaError.noSessionKey
        }
        
        debugLog("QuotaService: Got session key from Claude Desktop cookies")
        
        // Step 2: Get organization ID
        let orgId = try await fetchOrganizationId(sessionKey: sessionKey)
        debugLog("QuotaService: Got org ID: \(orgId)")
        
        // Step 3: Fetch usage data
        let usage = try await fetchUsage(sessionKey: sessionKey, orgId: orgId)
        
        // Step 4: Optionally fetch account info
        var accountEmail: String? = nil
        var planType: String? = nil
        
        do {
            let account = try await fetchAccount(sessionKey: sessionKey)
            accountEmail = account.email
            if let membership = account.memberships?.first,
               let org = membership.organization {
                planType = org.billing_type
            }
        } catch {
            debugLog("QuotaService: Account fetch failed (non-fatal): \(error)")
        }
        
        // Parse the usage response (API uses "utilization" and "resets_at")
        let sessionWindow = parseWindow(
            percentUsed: usage.five_hour?.utilization,
            resetAt: usage.five_hour?.resets_at,
            windowType: "session"
        )
        
        let weeklyWindow = parseWindow(
            percentUsed: usage.seven_day?.utilization,
            resetAt: usage.seven_day?.resets_at,
            windowType: "weekly"
        )
        
        // Opus-specific weekly window
        var weeklyOpusWindow: QuotaWindow? = nil
        if let opusPercent = usage.seven_day_opus?.utilization, opusPercent > 0 {
            weeklyOpusWindow = parseWindow(
                percentUsed: opusPercent,
                resetAt: usage.seven_day_opus?.resets_at,
                windowType: "weekly"
            )
        }
        
        // Sonnet-specific weekly window
        var weeklySonnetWindow: QuotaWindow? = nil
        if let sonnetPercent = usage.seven_day_sonnet?.utilization, sonnetPercent > 0 {
            weeklySonnetWindow = parseWindow(
                percentUsed: sonnetPercent,
                resetAt: usage.seven_day_sonnet?.resets_at,
                windowType: "weekly"
            )
        }
        
        return ClaudeMaxQuota(
            dataSource: .claudeDesktopApp,
            sessionWindow: sessionWindow,
            weeklyWindow: weeklyWindow,
            weeklyOpusWindow: weeklyOpusWindow,
            weeklySonnetWindow: weeklySonnetWindow,
            totalTokensUsed: 0,
            tokensByModel: TokensByModel(sonnet: 0, opus: 0, haiku: 0),
            messageCount: 0,
            sessionCount: 0,
            lastSessionDate: nil,
            accountEmail: accountEmail,
            planType: planType,
            organizationId: orgId,
            lastUpdated: Date()
        )
    }
    
    /// Extract sessionKey from Claude Desktop app's encrypted cookies
    /// Throws specific errors for different failure modes to enable better user feedback
    private func extractSessionKey() throws -> String? {
        let cookiesPath = claudeDesktopCookiesPath.path
        
        guard FileManager.default.fileExists(atPath: cookiesPath) else {
            debugLog("QuotaService: Claude cookies file not found at \(cookiesPath)")
            throw QuotaError.noCookiesFile
        }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(cookiesPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            debugLog("QuotaService: Could not open cookies database (may be locked by Claude Desktop)")
            throw QuotaError.cookiesDatabaseError
        }
        defer { sqlite3_close(db) }
        
        // Query for sessionKey cookie
        let query = """
            SELECT encrypted_value, value FROM cookies 
            WHERE host_key LIKE '%claude.ai' AND name = 'sessionKey'
            LIMIT 1
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw QuotaError.cookiesDatabaseError
        }
        defer { sqlite3_finalize(stmt) }
        
        // Track decryption failures for better error reporting
        var lastDecryptionFailure: DecryptionResult?
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            // Try encrypted value first
            if let blobPtr = sqlite3_column_blob(stmt, 0) {
                let blobSize = Int(sqlite3_column_bytes(stmt, 0))
                let encryptedData = Data(bytes: blobPtr, count: blobSize)
                
                // Electron cookies use Chrome's encryption format
                let result = decryptChromeCookie(encryptedData)
                switch result {
                case .success(let key), .unencrypted(let key):
                    return key
                case .keychainFailed:
                    throw QuotaError.keychainAccessFailed
                case .unsupportedVersion(let version):
                    debugLog("QuotaService: \(version) - Claude Desktop may have updated encryption")
                    throw QuotaError.decryptionFailed(reason: version)
                case .malformedData(let reason):
                    debugLog("QuotaService: Malformed cookie data: \(reason)")
                    lastDecryptionFailure = result
                case .decryptionFailed, .noSessionKeyInDecrypted:
                    lastDecryptionFailure = result
                }
            }
            
            // Try plain value as fallback
            if let valuePtr = sqlite3_column_text(stmt, 1) {
                let value = String(cString: valuePtr)
                if !value.isEmpty && value.hasPrefix("sk-ant-") {
                    return value
                }
            }
        }
        
        // If we got here with a decryption failure, throw appropriate error
        if let failure = lastDecryptionFailure {
            switch failure {
            case .decryptionFailed:
                throw QuotaError.decryptionFailed(reason: "AES decryption failed - encryption key may have changed")
            case .noSessionKeyInDecrypted:
                throw QuotaError.sessionExpired
            default:
                break
            }
        }
        
        return nil
    }
    
    /// Result type for decryption to provide detailed failure reasons
    private enum DecryptionResult {
        case success(String)
        case unencrypted(String)
        case unsupportedVersion(String)
        case keychainFailed
        case malformedData(String)
        case decryptionFailed
        case noSessionKeyInDecrypted
    }
    
    /// Decrypt Chrome/Electron cookie value on macOS
    /// Returns detailed result for better error handling upstream
    private func decryptChromeCookie(_ encryptedData: Data) -> DecryptionResult {
        // Chrome cookies on macOS use "v10" prefix + AES-128-CBC encrypted with Keychain password
        // Format: "v10" (3 bytes) + IV (16 bytes) + ciphertext
        
        guard encryptedData.count > 3 else {
            return .malformedData("Cookie data too short (\(encryptedData.count) bytes)")
        }
        
        // Check for version prefix (v10, v11 are supported)
        let prefix = String(data: encryptedData.prefix(3), encoding: .utf8)
        
        // v10/v11: Chrome's encrypted format
        // Other prefixes: might be unencrypted or newer unsupported version
        if prefix != "v10" && prefix != "v11" {
            // Check if it's unencrypted (starts with sk-ant-)
            if let str = String(data: encryptedData, encoding: .utf8), str.hasPrefix("sk-ant-") {
                return .unencrypted(str)
            }
            // Unknown version - could be newer encryption format (v12+?)
            let versionHex = encryptedData.prefix(3).map { String(format: "%02x", $0) }.joined()
            return .unsupportedVersion("Unknown cookie version: \(prefix ?? versionHex)")
        }
        
        // Get encryption key from Keychain (Chrome Safe Storage or Electron equivalent)
        // For Electron apps like Claude Desktop, the key is stored under "Claude Safe Storage"
        guard let key = getElectronEncryptionKey() else {
            debugLog("QuotaService: Could not get encryption key from Keychain")
            return .keychainFailed
        }
        
        // Extract IV and ciphertext - need at least prefix(3) + IV(16) + some ciphertext
        guard encryptedData.count > 19 else {
            return .malformedData("Encrypted data too short for IV extraction")
        }
        let iv = encryptedData[3..<19]
        let ciphertext = encryptedData[19...]
        
        // Decrypt using AES-128-CBC
        guard let decrypted = aesDecrypt(ciphertext: Data(ciphertext), key: key, iv: Data(iv)) else {
            debugLog("QuotaService: AES decryption failed (key may have changed)")
            return .decryptionFailed
        }
        
        // The decrypted data may have padding/garbage
        // Find the actual session key which starts with "sk-ant-"
        if let range = decrypted.range(of: Data("sk-ant-".utf8)) {
            let sessionKeyData = decrypted[range.lowerBound...]
            if let str = String(data: sessionKeyData, encoding: .utf8) {
                // Remove null bytes and control characters
                let cleaned = str.trimmingCharacters(in: .controlCharacters)
                    .components(separatedBy: "\0").first ?? ""
                if !cleaned.isEmpty {
                    return .success(cleaned)
                }
            }
        }
        
        return .noSessionKeyInDecrypted
    }
    
    /// Get Electron/Chrome encryption key from Keychain
    private func getElectronEncryptionKey() -> Data? {
        // Try Claude-specific key first
        let services = ["Claude Safe Storage", "Electron Safe Storage", "Chrome Safe Storage"]
        
        for service in services {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            
            if status == errSecSuccess, let passwordData = result as? Data {
                // Chrome/Electron stores the password as a string, use it directly for key derivation
                // Don't base64 decode - use the raw bytes as the password
                if let key = deriveKey(from: passwordData) {
                    debugLog("QuotaService: Derived key from \(service)")
                    return key
                }
            }
        }
        
        // Fallback: try with empty password (some Electron apps use this)
        if let key = deriveKey(from: Data()) {
            return key
        }
        
        return nil
    }
    
    /// Derive AES key using PBKDF2 (Chrome's cookie encryption method)
    private func deriveKey(from password: Data) -> Data? {
        let salt = "saltysalt".data(using: .utf8)!
        let iterations: UInt32 = 1003
        let keyLength = 16
        
        var derivedKey = [UInt8](repeating: 0, count: keyLength)
        
        let status = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                    password.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    iterations,
                    &derivedKey,
                    keyLength
                )
            }
        }
        
        guard status == kCCSuccess else { return nil }
        return Data(derivedKey)
    }
    
    /// AES-128-CBC decryption
    private func aesDecrypt(ciphertext: Data, key: Data, iv: Data) -> Data? {
        var decrypted = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var decryptedLength = 0
        
        let status = ciphertext.withUnsafeBytes { ciphertextBytes in
            key.withUnsafeBytes { keyBytes in
                iv.withUnsafeBytes { ivBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        key.count,
                        ivBytes.baseAddress,
                        ciphertextBytes.baseAddress,
                        ciphertext.count,
                        &decrypted,
                        decrypted.count,
                        &decryptedLength
                    )
                }
            }
        }
        
        guard status == kCCSuccess else { return nil }
        return Data(decrypted.prefix(decryptedLength))
    }
    
    /// Fetch organization ID from Claude API
    private func fetchOrganizationId(sessionKey: String) async throws -> String {
        guard let url = URL(string: "https://claude.ai/api/organizations") else {
            throw QuotaError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuotaError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw QuotaError.apiError(statusCode: httpResponse.statusCode)
        }
        
        // Response is an array of organizations
        let orgs = try JSONDecoder().decode([ClaudeOrganizationsResponse].self, from: data)
        
        guard let firstOrg = orgs.first else {
            throw QuotaError.emptyResponse
        }
        
        return firstOrg.uuid
    }
    
    /// Fetch usage data from Claude API
    private func fetchUsage(sessionKey: String, orgId: String) async throws -> ClaudeUsageResponse {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage") else {
            throw QuotaError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuotaError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw QuotaError.apiError(statusCode: httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
    }
    
    /// Fetch account info from Claude API
    private func fetchAccount(sessionKey: String) async throws -> ClaudeAccountResponse {
        guard let url = URL(string: "https://claude.ai/api/account") else {
            throw QuotaError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuotaError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw QuotaError.apiError(statusCode: httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(ClaudeAccountResponse.self, from: data)
    }
    
    /// Parse a quota window from API response
    private func parseWindow(percentUsed: Double?, resetAt: String?, windowType: String = "weekly") -> QuotaWindow {
        var resetDate: Date? = nil
        
        if let resetStr = resetAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            resetDate = formatter.date(from: resetStr)
            
            // Try without fractional seconds
            if resetDate == nil {
                formatter.formatOptions = [.withInternetDateTime]
                resetDate = formatter.date(from: resetStr)
            }
        }
        
        return QuotaWindow(
            percentUsed: percentUsed ?? 0,
            resetsAt: resetDate,
            windowType: windowType
        )
    }
    
    // MARK: - Local File Aggregation (Fallback)
    
    private func aggregateLocalUsage() throws -> ClaudeMaxQuota {
        let fm = FileManager.default
        
        var totalTokens: Int = 0
        var sonnetTokens: Int = 0
        var opusTokens: Int = 0
        var haikuTokens: Int = 0
        var lastSessionDate: Date? = nil
        var messageCount: Int = 0
        var sessionCount: Int = 0
        
        // Try stats-cache.json first (has good summary data)
        if fm.fileExists(atPath: statsCachePath.path) {
            do {
                let cacheData = try parseStatsCache()
                totalTokens = cacheData.totalTokens
                sonnetTokens = cacheData.sonnetTokens
                opusTokens = cacheData.opusTokens
                haikuTokens = cacheData.haikuTokens
                lastSessionDate = cacheData.lastSessionDate
                messageCount = cacheData.messageCount
                sessionCount = cacheData.sessionCount
                debugLog("QuotaService: Parsed stats-cache.json - \(totalTokens) total tokens")
            } catch {
                debugLog("QuotaService: Failed to parse stats-cache.json: \(error)")
            }
        }
        
        // Also scan JSONL files for more data (they might have newer sessions)
        if fm.fileExists(atPath: claudeProjectsPath.path) {
            let jsonlData = try aggregateFromJSONL()
            
            // Use JSONL data if it's more recent or has more tokens
            if let jsonlDate = jsonlData.lastSessionDate {
                if let existing = lastSessionDate {
                    if jsonlDate > existing {
                        lastSessionDate = jsonlDate
                    }
                } else {
                    lastSessionDate = jsonlDate
                }
            }
            
            // Take max of tokens (stats-cache should be accurate, but JSONL might have more)
            if jsonlData.totalTokens > totalTokens {
                totalTokens = jsonlData.totalTokens
                sonnetTokens = jsonlData.sonnetTokens
                opusTokens = jsonlData.opusTokens
                haikuTokens = jsonlData.haikuTokens
            }
            
            // Sum message/session counts
            if jsonlData.messageCount > messageCount {
                messageCount = jsonlData.messageCount
            }
            if jsonlData.sessionCount > sessionCount {
                sessionCount = jsonlData.sessionCount
            }
        }
        
        // If no data found at all
        if totalTokens == 0 && lastSessionDate == nil {
            throw QuotaError.noLocalData
        }
        
        // Calculate estimated weekly reset (next Monday)
        let now = Date()
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        comps.weekday = 2 // Monday
        comps.hour = 0
        comps.minute = 0
        var weeklyReset: Date? = nil
        if let nextMonday = calendar.date(from: comps) {
            weeklyReset = nextMonday > now ? nextMonday : calendar.date(byAdding: .day, value: 7, to: nextMonday)
        }
        
        // Build quota object with token counts
        return ClaudeMaxQuota(
            dataSource: .localFiles,
            sessionWindow: .empty,
            weeklyWindow: QuotaWindow(percentUsed: 0, resetsAt: weeklyReset),
            weeklyOpusWindow: nil,
            weeklySonnetWindow: nil,
            totalTokensUsed: totalTokens,
            tokensByModel: TokensByModel(
                sonnet: sonnetTokens,
                opus: opusTokens,
                haiku: haikuTokens
            ),
            messageCount: messageCount,
            sessionCount: sessionCount,
            lastSessionDate: lastSessionDate,
            accountEmail: nil,
            planType: nil,
            organizationId: nil,
            lastUpdated: Date()
        )
    }
    
    /// Parse Claude's stats-cache.json file
    private func parseStatsCache() throws -> LocalUsageData {
        let data = try Data(contentsOf: statsCachePath)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.parseError("Invalid stats-cache.json format")
        }
        
        var totalTokens: Int = 0
        var sonnetTokens: Int = 0
        var opusTokens: Int = 0
        var haikuTokens: Int = 0
        var lastSessionDate: Date? = nil
        
        // Extract model usage
        if let modelUsage = json["modelUsage"] as? [String: [String: Any]] {
            for (model, usage) in modelUsage {
                let input = usage["inputTokens"] as? Int ?? 0
                let output = usage["outputTokens"] as? Int ?? 0
                let cacheRead = usage["cacheReadInputTokens"] as? Int ?? 0
                let cacheWrite = usage["cacheCreationInputTokens"] as? Int ?? 0
                
                let modelTotal = input + output + cacheRead + cacheWrite
                totalTokens += modelTotal
                
                let modelLower = model.lowercased()
                if modelLower.contains("sonnet") {
                    sonnetTokens += modelTotal
                } else if modelLower.contains("opus") {
                    opusTokens += modelTotal
                } else if modelLower.contains("haiku") {
                    haikuTokens += modelTotal
                }
            }
        }
        
        // Get last session date from firstSessionDate or longestSession
        if let longestSession = json["longestSession"] as? [String: Any],
           let timestamp = longestSession["timestamp"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            lastSessionDate = formatter.date(from: timestamp)
        }
        
        // Also check lastComputedDate
        if let lastComputed = json["lastComputedDate"] as? String {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            if let date = dateFormatter.date(from: lastComputed) {
                // Use end of day for the lastComputedDate
                if let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: date) {
                    if let existing = lastSessionDate {
                        if endOfDay > existing {
                            lastSessionDate = endOfDay
                        }
                    } else {
                        lastSessionDate = endOfDay
                    }
                }
            }
        }
        
        let messageCount = json["totalMessages"] as? Int ?? 0
        let sessionCount = json["totalSessions"] as? Int ?? 0
        
        return LocalUsageData(
            totalTokens: totalTokens,
            sonnetTokens: sonnetTokens,
            opusTokens: opusTokens,
            haikuTokens: haikuTokens,
            lastSessionDate: lastSessionDate,
            messageCount: messageCount,
            sessionCount: sessionCount
        )
    }
    
    /// Aggregate usage from JSONL files
    private func aggregateFromJSONL() throws -> LocalUsageData {
        let fm = FileManager.default
        
        // Calculate 7 days ago for filtering
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        
        var totalTokens: Int = 0
        var sonnetTokens: Int = 0
        var opusTokens: Int = 0
        var haikuTokens: Int = 0
        var latestTimestamp: Date? = nil
        var messageCount: Int = 0
        var sessionIds: Set<String> = []
        
        // Recursively find all .jsonl files
        guard let enumerator = fm.enumerator(at: claudeProjectsPath, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return LocalUsageData(totalTokens: 0, sonnetTokens: 0, opusTokens: 0, haikuTokens: 0, lastSessionDate: nil, messageCount: 0, sessionCount: 0)
        }
        
        for case let file as URL in enumerator {
            guard file.pathExtension == "jsonl" else { continue }
            
            // Check file modification date
            let attrs = try? fm.attributesOfItem(atPath: file.path)
            let modDate = attrs?[.modificationDate] as? Date ?? Date.distantPast
            
            guard modDate > sevenDaysAgo else { continue }
            
            // Parse JSONL file
            let parsed = parseJSONLFile(file, after: sevenDaysAgo)
            totalTokens += parsed.totalTokens
            sonnetTokens += parsed.sonnetTokens
            opusTokens += parsed.opusTokens
            haikuTokens += parsed.haikuTokens
            messageCount += parsed.messageCount
            sessionIds.formUnion(parsed.sessionIds)
            
            if let ts = parsed.latestTimestamp {
                if let existing = latestTimestamp {
                    if ts > existing {
                        latestTimestamp = ts
                    }
                } else {
                    latestTimestamp = ts
                }
            }
        }
        
        return LocalUsageData(
            totalTokens: totalTokens,
            sonnetTokens: sonnetTokens,
            opusTokens: opusTokens,
            haikuTokens: haikuTokens,
            lastSessionDate: latestTimestamp,
            messageCount: messageCount,
            sessionCount: sessionIds.count
        )
    }
    
    private func parseJSONLFile(_ url: URL, after startDate: Date) -> ParsedJSONLData {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ParsedJSONLData()
        }
        
        var result = ParsedJSONLData()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let lines = content.components(separatedBy: "\n")
        
        for line in lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            
            // Track session IDs
            if let sessionId = json["sessionId"] as? String {
                result.sessionIds.insert(sessionId)
            }
            
            // Check timestamp
            var lineDate: Date? = nil
            if let timestamp = json["timestamp"] as? String {
                lineDate = formatter.date(from: timestamp)
                if let date = lineDate {
                    if date < startDate {
                        continue
                    }
                    if let existing = result.latestTimestamp {
                        if date > existing {
                            result.latestTimestamp = date
                        }
                    } else {
                        result.latestTimestamp = date
                    }
                }
            }
            
            // Extract usage from message.usage
            if let message = json["message"] as? [String: Any],
               let usage = message["usage"] as? [String: Any] {
                
                let input = usage["input_tokens"] as? Int ?? 0
                let output = usage["output_tokens"] as? Int ?? 0
                let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
                let cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
                
                let lineTotal = input + output + cacheRead + cacheWrite
                result.totalTokens += lineTotal
                result.messageCount += 1
                
                // Get model
                if let model = message["model"] as? String ?? json["model"] as? String {
                    let modelLower = model.lowercased()
                    if modelLower.contains("sonnet") {
                        result.sonnetTokens += lineTotal
                    } else if modelLower.contains("opus") {
                        result.opusTokens += lineTotal
                    } else if modelLower.contains("haiku") {
                        result.haikuTokens += lineTotal
                    }
                }
            }
        }
        
        return result
    }
    
    // MARK: - Helper Structs
    
    private struct LocalUsageData {
        let totalTokens: Int
        let sonnetTokens: Int
        let opusTokens: Int
        let haikuTokens: Int
        let lastSessionDate: Date?
        let messageCount: Int
        let sessionCount: Int
    }
    
    private struct ParsedJSONLData {
        var totalTokens: Int = 0
        var sonnetTokens: Int = 0
        var opusTokens: Int = 0
        var haikuTokens: Int = 0
        var latestTimestamp: Date? = nil
        var messageCount: Int = 0
        var sessionIds: Set<String> = []
    }
}

// MARK: - Errors

enum QuotaError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int)
    case emptyResponse
    case parseError(String)
    case noLocalData
    case commandFailed(String)
    case noSessionKey
    case noCookiesFile
    case cookiesDatabaseError
    case decryptionFailed(reason: String)
    case keychainAccessFailed
    case sessionExpired
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid API response"
        case .apiError(let code): return "API error: \(code)"
        case .emptyResponse: return "Empty response"
        case .parseError(let msg): return "Parse error: \(msg)"
        case .noLocalData: return "No local usage data found"
        case .commandFailed(let msg): return "Command failed: \(msg)"
        case .noSessionKey: return "Could not access Claude Desktop session. Please sign in to Claude Desktop app."
        case .noCookiesFile: return "Claude Desktop not installed or never signed in"
        case .cookiesDatabaseError: return "Could not read Claude Desktop cookies - app may be running"
        case .decryptionFailed(let reason): return "Cookie decryption failed: \(reason)"
        case .keychainAccessFailed: return "Could not access Keychain for Claude credentials"
        case .sessionExpired: return "Claude session expired. Please sign in to Claude Desktop app."
        }
    }
    
    /// User-friendly recovery suggestion
    var recoverySuggestion: String? {
        switch self {
        case .noSessionKey, .sessionExpired:
            return "Open Claude Desktop and sign in to your account."
        case .noCookiesFile:
            return "Install and sign in to Claude Desktop to enable quota tracking."
        case .cookiesDatabaseError:
            return "Try closing Claude Desktop and retrying."
        case .keychainAccessFailed:
            return "Check ClawK has Keychain access in System Settings > Privacy & Security."
        case .decryptionFailed:
            return "Claude Desktop may have updated its encryption format. Try reinstalling Claude Desktop."
        default:
            return nil
        }
    }
}

// MARK: - CommonCrypto Import

import CommonCrypto
