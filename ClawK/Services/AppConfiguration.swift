//
//  AppConfiguration.swift
//  ClawK
//
//  Centralized configuration with auto-discovery of OpenClaw installation.
//  Replaces all hardcoded paths, ports, agent names, and personal references.
//

import Foundation
import Combine

/// Centralized configuration singleton that auto-discovers the user's OpenClaw installation.
/// All file paths, gateway URLs, and agent names derive from this single source of truth.
class AppConfiguration: ObservableObject {
    nonisolated(unsafe) static let shared = AppConfiguration()
    
    // MARK: - UserDefaults Keys
    private static let agentNameKey = "appConfig.agentName"
    private static let gatewayURLOverrideKey = "appConfig.gatewayURLOverride"
    private static let refreshIntervalKey = "appConfig.refreshInterval"
    
    // MARK: - Discovered Paths (read-only after discovery)
    
    /// OpenClaw home directory (e.g., ~/.openclaw)
    @Published private(set) var openclawHome: String = ""
    
    /// Workspace path from openclaw.json agents.defaults.workspace
    @Published private(set) var workspacePath: String = ""
    
    /// Memory directory path (workspace/memory)
    @Published private(set) var memoryPath: String = ""
    
    /// Memory SQLite database path (~/.openclaw/memory/{agentName}.sqlite)
    @Published private(set) var memoryDbPath: String = ""
    
    /// Sessions directory path (~/.openclaw/agents/{agentName}/sessions)
    @Published private(set) var sessionsPath: String = ""
    
    /// OpenClaw config file path (~/.openclaw/openclaw.json)
    @Published private(set) var configPath: String = ""
    
    /// Discovered gateway port from openclaw.json
    @Published private(set) var discoveredPort: Int = 18789
    
    // MARK: - User Settings (persisted in UserDefaults)
    
    /// Gateway URL - auto-discovered, but overridable by user
    @Published var gatewayURL: String = "http://127.0.0.1:18789" {
        didSet {
            // Only persist if user explicitly overrides (non-empty means override)
            // Empty string means "use discovered"
        }
    }
    
    /// Agent name - defaults to "main", configurable
    @Published var agentName: String = "main" {
        didSet {
            UserDefaults.standard.set(agentName, forKey: Self.agentNameKey)
            // Re-derive agent-dependent paths
            rederivePaths()
        }
    }
    
    /// Refresh interval in seconds
    @Published var refreshInterval: TimeInterval = 30 {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: Self.refreshIntervalKey)
        }
    }
    
    // MARK: - State
    
    /// Whether configuration has been successfully discovered
    @Published private(set) var isConfigured: Bool = false
    
    /// Error message if discovery failed
    @Published private(set) var configError: String?
    
    /// Detailed error type for UI to show appropriate screen
    @Published private(set) var errorType: ConfigErrorType = .none
    
    // MARK: - Convenience Computed Properties
    
    /// Session key for the main session: "agent:{agentName}:main"
    var mainSessionKey: String {
        "agent:\(agentName):main"
    }
    
    /// Session key prefix for telegram sessions: "agent:{agentName}:telegram:"
    var telegramSessionKeyPrefix: String {
        "agent:\(agentName):telegram:"
    }
    
    /// Session key prefix for subagent sessions: "agent:{agentName}:subagent:"
    var subagentSessionKeyPrefix: String {
        "agent:\(agentName):subagent:"
    }
    
    /// Path to sessions.json index file
    var sessionsIndexPath: String {
        "\(sessionsPath)/sessions.json"
    }
    
    /// Path to MEMORY.md (at workspace root, not in memory folder)
    var memoryMdPath: String {
        "\(workspacePath)/MEMORY.md"
    }
    
    /// Path to Python embeddings script (optional - may not exist on all installs)
    var embeddingsScriptPath: String {
        "\(workspacePath)/scripts/memory_embeddings.py"
    }
    
    /// Path to Python venv (optional - may not exist on all installs)
    var pythonVenvPath: String {
        "\(workspacePath)/.venv/bin/python"
    }
    
    /// Path to CONTEXT-FLUSH.md
    var contextFlushLogPath: String {
        "\(memoryPath)/CONTEXT-FLUSH.md"
    }
    
    // MARK: - Error Types
    
    enum ConfigErrorType {
        case none
        case openclawNotInstalled    // ~/.openclaw doesn't exist
        case configNotFound          // openclaw.json missing
        case configParseError        // openclaw.json invalid
        case gatewayNotRunning       // Gateway unreachable (detected separately)
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load persisted settings
        let savedAgent = UserDefaults.standard.string(forKey: Self.agentNameKey)
        if let agent = savedAgent, !agent.isEmpty {
            self.agentName = agent
        }
        
        let savedInterval = UserDefaults.standard.double(forKey: Self.refreshIntervalKey)
        if savedInterval > 0 {
            self.refreshInterval = savedInterval
        }
        
        // Auto-discover on init
        discover()
    }
    
    // MARK: - Auto-Discovery
    
    /// Discover OpenClaw installation and populate all paths.
    /// Safe to call multiple times (e.g., from a "Re-discover" button).
    func discover() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        
        // Step 1: Find ~/.openclaw
        let openclawDir = "\(home)/.openclaw"
        guard fm.fileExists(atPath: openclawDir) else {
            configError = "OpenClaw not found at ~/.openclaw. Please install OpenClaw first."
            errorType = .openclawNotInstalled
            isConfigured = false
            // Still set reasonable defaults so the app doesn't crash
            setDefaults(home: home)
            return
        }
        
        self.openclawHome = openclawDir
        self.configPath = "\(openclawDir)/openclaw.json"
        
        // Step 2: Parse openclaw.json
        guard fm.fileExists(atPath: configPath) else {
            configError = "Configuration file not found at \(configPath)."
            errorType = .configNotFound
            isConfigured = false
            setDefaults(home: home)
            return
        }
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            configError = "Could not parse \(configPath). File may be corrupted."
            errorType = .configParseError
            isConfigured = false
            setDefaults(home: home)
            return
        }
        
        // Step 3: Extract gateway port
        if let gateway = json["gateway"] as? [String: Any],
           let port = gateway["port"] as? Int {
            self.discoveredPort = port
        }
        // Construct gateway URL from discovered port (unless user has an override in GatewayConfig)
        self.gatewayURL = "http://127.0.0.1:\(discoveredPort)"
        
        // Step 4: Extract workspace path
        if let agents = json["agents"] as? [String: Any],
           let defaults = agents["defaults"] as? [String: Any],
           let workspace = defaults["workspace"] as? String {
            self.workspacePath = workspace
        } else {
            // Fallback: standard workspace path
            self.workspacePath = "\(openclawDir)/workspace"
        }
        
        // Step 5: Derive all other paths
        rederivePaths()
        
        // Step 6: Mark as configured
        configError = nil
        errorType = .none
        isConfigured = true
    }
    
    // MARK: - Private Helpers
    
    /// Set default paths using home directory (used when discovery fails partially)
    private func setDefaults(home: String) {
        let openclawDir = "\(home)/.openclaw"
        self.openclawHome = openclawDir
        self.configPath = "\(openclawDir)/openclaw.json"
        self.workspacePath = "\(openclawDir)/workspace"
        rederivePaths()
    }
    
    /// Re-derive paths that depend on agentName or workspacePath
    private func rederivePaths() {
        self.memoryPath = "\(workspacePath)/memory"
        self.memoryDbPath = "\(openclawHome)/memory/\(agentName).sqlite"
        self.sessionsPath = "\(openclawHome)/agents/\(agentName)/sessions"
    }
    
    // MARK: - Helper: Session Path for a specific session ID
    
    /// Get the full path to a session JSONL file
    func sessionFilePath(sessionId: String) -> String {
        "\(sessionsPath)/\(sessionId).jsonl"
    }
    
    /// Get the full path to a daily memory log file
    func dailyLogPath(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        return "\(memoryPath)/\(dateString).md"
    }
}
