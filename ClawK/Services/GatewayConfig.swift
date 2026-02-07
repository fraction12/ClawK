//
//  GatewayConfig.swift
//  ClawK
//
//  Shared gateway configuration and token loading
//

import Foundation

/// Centralized gateway configuration
class GatewayConfig: ObservableObject {
    static let shared = GatewayConfig()
    
    /// UserDefaults key for custom gateway URL
    private static let customURLKey = "customGatewayURL"
    
    /// UserDefaults key for gateway token
    private static let tokenKey = "gatewayToken"
    
    /// Path to OpenClaw config file (derived from AppConfiguration)
    private static var openclawConfigPath: String {
        AppConfiguration.shared.configPath
    }
    
    /// Default gateway host
    let defaultHost: String = "127.0.0.1"
    
    /// Default gateway port (discovered from openclaw.json, fallback 18789)
    var defaultPort: Int {
        AppConfiguration.shared.discoveredPort
    }
    
    /// Default gateway URL
    var defaultURL: String {
        "http://\(defaultHost):\(defaultPort)"
    }
    
    /// Custom gateway URL override (stored in UserDefaults)
    @Published var customURL: String {
        didSet {
            UserDefaults.standard.set(customURL, forKey: Self.customURLKey)
        }
    }
    
    /// Gateway token (stored in UserDefaults)
    @Published var storedToken: String {
        didSet {
            UserDefaults.standard.set(storedToken, forKey: Self.tokenKey)
        }
    }
    
    /// Whether custom URL is being used
    var isUsingCustomURL: Bool {
        !customURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Full gateway URL (custom if set, otherwise default)
    var baseURL: String {
        let custom = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? defaultURL : custom
    }
    
    /// Gateway token (from UserDefaults, or auto-loaded from OpenClaw config)
    var token: String? {
        let trimmed = storedToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    /// Whether token is configured
    var hasToken: Bool {
        token != nil
    }
    
    private init() {
        self.customURL = UserDefaults.standard.string(forKey: Self.customURLKey) ?? ""
        self.storedToken = UserDefaults.standard.string(forKey: Self.tokenKey) ?? ""
        
        // Auto-load token from OpenClaw config if not set
        if storedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let configToken = Self.loadTokenFromOpenClawConfig() {
                self.storedToken = configToken
                // Persist to UserDefaults for future launches
                UserDefaults.standard.set(configToken, forKey: Self.tokenKey)
            }
        }
    }
    
    /// Reset to default URL
    func resetToDefault() {
        customURL = ""
    }
    
    /// Reload token from OpenClaw config file
    func reloadFromConfig() {
        if let configToken = Self.loadTokenFromOpenClawConfig() {
            self.storedToken = configToken
        }
    }
    
    /// Load gateway token — tries multiple sources in order
    private static func loadTokenFromOpenClawConfig() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        
        // 1. Try ~/.openclaw/gateway.token file (standard location)
        let tokenFilePath = "\(home)/.openclaw/gateway.token"
        if let tokenData = try? String(contentsOfFile: tokenFilePath, encoding: .utf8) {
            let trimmed = tokenData.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        
        // 2. Try gateway.auth.token in openclaw.json
        let path = NSString(string: openclawConfigPath).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        
        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let gateway = json["gateway"] as? [String: Any],
           let auth = gateway["auth"] as? [String: Any],
           let token = auth["token"] as? String {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        
        return nil
    }
}
