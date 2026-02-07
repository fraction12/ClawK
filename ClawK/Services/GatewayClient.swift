//
//  GatewayClient.swift
//  ClawK
//
//  HTTP client for OpenClaw Gateway API
//

import Foundation

enum GatewayError: LocalizedError {
    case invalidURL
    case unauthorized
    case notFound
    case serverError(String)
    case decodingError(Error)
    case networkError(Error)
    case timeout
    case noToken
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid gateway URL"
        case .unauthorized:
            return "Unauthorized - check gateway token"
        case .notFound:
            return "Endpoint not found"
        case .serverError(let message):
            return "Server error: \(message)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .timeout:
            return "Connection timed out"
        case .noToken:
            return "No gateway token configured"
        }
    }
    
    /// Check if this is a timeout error
    var isTimeout: Bool {
        if case .timeout = self { return true }
        return false
    }
}

actor GatewayClient {
    private var baseURL: URL {
        URL(string: GatewayConfig.shared.baseURL) ?? URL(string: "http://127.0.0.1:18789")!
    }
    private var token: String {
        GatewayConfig.shared.token ?? ""
    }
    private let session: URLSession
    
    // MARK: - Memory Search Tracking
    
    /// Get today's memory search count from actual gateway session logs
    nonisolated static func fetchMemorySearchCount() -> Int {
        let fm = FileManager.default
        let sessionsPath = AppConfiguration.shared.sessionsPath
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())
        
        var count = 0
        
        // Read all .jsonl files in sessions directory
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsPath) else {
            return 0
        }
        
        for file in files where file.hasSuffix(".jsonl") {
            let filePath = "\(sessionsPath)/\(file)"
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                continue
            }
            
            // Count lines with toolCall type, memory_search, and today's date
            for line in content.components(separatedBy: "\n") {
                if line.contains("\"type\":\"toolCall\"") &&
                   line.contains("memory_search") &&
                   line.contains(today) {
                    count += 1
                }
            }
        }
        
        return count
    }
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Tool Invocation
    
    private func invokeToolRaw(tool: String, action: String? = nil, args: [String: Any] = [:]) async throws -> Data {
        guard !token.isEmpty else {
            throw GatewayError.noToken
        }
        
        let url = baseURL.appendingPathComponent("tools/invoke")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["tool": tool]
        if let action = action {
            var argsWithAction = args
            argsWithAction["action"] = action
            body["args"] = argsWithAction
        } else if !args.isEmpty {
            body["args"] = args
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GatewayError.serverError("Invalid response")
            }
            
            switch httpResponse.statusCode {
            case 200:
                return data
            case 401:
                throw GatewayError.unauthorized
            case 404:
                throw GatewayError.notFound
            default:
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw GatewayError.serverError(message)
                }
                throw GatewayError.serverError("HTTP \(httpResponse.statusCode)")
            }
        } catch let error as GatewayError {
            throw error
        } catch {
            // Check for timeout errors specifically
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain &&
               (nsError.code == NSURLErrorTimedOut ||
                nsError.code == NSURLErrorNetworkConnectionLost) {
                throw GatewayError.timeout
            }
            throw GatewayError.networkError(error)
        }
    }
    
    // MARK: - Cron Jobs
    
    func fetchCronJobs() async throws -> [CronJob] {
        let data = try await invokeToolRaw(tool: "cron", action: "list")
        
        // Parse the response structure
        struct ToolResponse: Codable {
            let ok: Bool
            let result: ResultPayload?
            let error: ErrorPayload?
        }
        
        struct ResultPayload: Codable {
            let details: CronListResponse?
        }
        
        struct ErrorPayload: Codable {
            let message: String?
            let type: String?
        }
        
        do {
            let response = try JSONDecoder().decode(ToolResponse.self, from: data)
            
            if let error = response.error {
                throw GatewayError.serverError(error.message ?? "Unknown error")
            }
            
            return response.result?.details?.jobs ?? []
        } catch let error as GatewayError {
            throw error
        } catch {
            throw GatewayError.decodingError(error)
        }
    }
    
    // MARK: - Models
    
    func fetchModels() async throws -> [ModelInfo] {
        // Use exec to run openclaw models list --json
        let data = try await invokeToolRaw(tool: "exec", args: ["command": "openclaw models list --json"])
        
        struct ToolResponse: Codable {
            let ok: Bool
            let result: ResultPayload?
        }
        
        struct ResultPayload: Codable {
            let details: ExecResponse?
        }
        
        struct ExecResponse: Codable {
            let stdout: String?
        }
        
        struct ModelsListResponse: Codable {
            let models: [ModelInfo]
        }
        
        do {
            let response = try JSONDecoder().decode(ToolResponse.self, from: data)
            guard let stdout = response.result?.details?.stdout else {
                return []
            }
            
            // Parse the JSON output from openclaw models list
            let modelsResponse = try JSONDecoder().decode(ModelsListResponse.self, from: Data(stdout.utf8))
            return modelsResponse.models
        } catch {
            // Fallback: return empty array if parsing fails
            return []
        }
    }
    
    // MARK: - Sessions
    
    func fetchSessions() async throws -> [SessionInfo] {
        let data = try await invokeToolRaw(tool: "sessions_list")
        
        struct ToolResponse: Codable {
            let ok: Bool
            let result: ResultPayload?
        }
        
        struct ResultPayload: Codable {
            let details: SessionsListResponse?
        }
        
        do {
            let response = try JSONDecoder().decode(ToolResponse.self, from: data)
            return response.result?.details?.sessions ?? []
        } catch {
            throw GatewayError.decodingError(error)
        }
    }
    
    // MARK: - Health Check
    
    func healthCheck() async -> Bool {
        do {
            _ = try await fetchSessions()
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Send Message
    
    struct SendMessageResponse: Codable {
        let ok: Bool
        let result: SendMessageResult?
        let error: ErrorPayload?
        
        struct SendMessageResult: Codable {
            let details: MessageDetails?
        }
        
        struct MessageDetails: Codable {
            let delivered: Bool?
            let sessionKey: String?
        }
        
        struct ErrorPayload: Codable {
            let message: String?
        }
    }
    
    func sendMessage(_ message: String, toSession sessionKey: String? = nil) async throws -> Bool {
        var args: [String: Any] = ["message": message]
        if let key = sessionKey {
            args["sessionKey"] = key
        }
        
        let data = try await invokeToolRaw(tool: "sessions_send", args: args)
        
        do {
            let response = try JSONDecoder().decode(SendMessageResponse.self, from: data)
            
            if let error = response.error {
                throw GatewayError.serverError(error.message ?? "Failed to send message")
            }
            
            return response.result?.details?.delivered ?? response.ok
        } catch let error as GatewayError {
            throw error
        } catch {
            // If decoding fails but we got here, assume success
            return true
        }
    }
    
    // MARK: - Session History
    
    struct SessionHistoryResponse: Codable {
        let ok: Bool
        let result: SessionHistoryResult?
        let error: ErrorPayload?
        
        struct SessionHistoryResult: Codable {
            let details: SessionHistoryDetails?
        }
        
        struct SessionHistoryDetails: Codable {
            let sessionKey: String?
            let messages: [SessionMessage]?
        }
        
        struct ErrorPayload: Codable {
            let message: String?
        }
    }
    
    struct SessionMessage: Codable {
        let role: String
        let content: [MessageContent]
        let timestamp: Double?  // Unix timestamp in milliseconds
        
        struct MessageContent: Codable {
            let type: String
            let text: String?
        }
        
        /// Extract text from content array
        var textContent: String? {
            // Concatenate ALL text blocks, not just the first one
            // (heartbeat responses often have multiple text blocks)
            let textBlocks = content.compactMap { block -> String? in
                guard block.type == "text" else { return nil }
                return block.text
            }
            return textBlocks.isEmpty ? nil : textBlocks.joined(separator: "\n")
        }
        
        /// Convert timestamp to Date
        var date: Date? {
            guard let ts = timestamp else { return nil }
            return Date(timeIntervalSince1970: ts / 1000.0)
        }
    }
    
    func fetchSessionHistory(sessionKey: String, limit: Int = 50) async throws -> [SessionMessage] {
        let data = try await invokeToolRaw(
            tool: "sessions_history",
            args: ["sessionKey": sessionKey, "limit": limit]
        )
        
        let response = try JSONDecoder().decode(SessionHistoryResponse.self, from: data)
        
        if let error = response.error {
            throw GatewayError.serverError(error.message ?? "Failed to fetch session history")
        }
        
        return response.result?.details?.messages ?? []
    }
    
    // MARK: - Canvas
    
    struct CanvasSnapshotResponse: Codable {
        let ok: Bool
        let result: CanvasSnapshotResult?
        let error: ErrorPayload?
        
        struct CanvasSnapshotResult: Codable {
            let content: [ContentItem]?
            
            struct ContentItem: Codable {
                let type: String
                let text: String?
                let data: String?  // base64 image data
                let mimeType: String?
            }
        }
        
        struct ErrorPayload: Codable {
            let message: String?
        }
    }
    
    struct CanvasActionResponse: Codable {
        let ok: Bool
        let error: ErrorPayload?
        
        struct ErrorPayload: Codable {
            let message: String?
        }
    }
    
    func canvasSnapshot(target: String = "host") async throws -> Data {
        let data = try await invokeToolRaw(tool: "canvas", action: "snapshot", args: ["outputFormat": "png", "target": target])
        
        let response = try JSONDecoder().decode(CanvasSnapshotResponse.self, from: data)
        
        if let error = response.error {
            throw GatewayError.serverError(error.message ?? "Snapshot failed")
        }
        
        // The image is base64 encoded in content[1].data
        guard let content = response.result?.content,
              content.count > 1,
              let base64 = content[1].data,
              let imageData = Data(base64Encoded: base64) else {
            throw GatewayError.serverError("No image data in response")
        }
        
        return imageData
    }
    
    func canvasPresent(url: String? = nil, target: String = "host") async throws {
        var args: [String: Any] = ["target": target]
        if let url = url {
            args["url"] = url
        }
        
        let data = try await invokeToolRaw(tool: "canvas", action: "present", args: args)
        
        let response = try JSONDecoder().decode(CanvasActionResponse.self, from: data)
        
        if let error = response.error {
            throw GatewayError.serverError(error.message ?? "Present failed")
        }
    }
    
    func canvasHide(target: String = "host") async throws {
        let data = try await invokeToolRaw(tool: "canvas", action: "hide", args: ["target": target])
        
        let response = try JSONDecoder().decode(CanvasActionResponse.self, from: data)
        
        if let error = response.error {
            throw GatewayError.serverError(error.message ?? "Hide failed")
        }
    }
    
    func canvasNavigate(url: String, target: String = "host") async throws {
        let data = try await invokeToolRaw(tool: "canvas", action: "navigate", args: ["url": url, "target": target])
        
        let response = try JSONDecoder().decode(CanvasActionResponse.self, from: data)
        
        if let error = response.error {
            throw GatewayError.serverError(error.message ?? "Navigate failed")
        }
    }
    
    // MARK: - Canvas Eval (JavaScript Execution)
    
    struct CanvasEvalResponse: Codable {
        let ok: Bool
        let result: CanvasEvalResult?
        let error: ErrorPayload?
        
        struct CanvasEvalResult: Codable {
            // H2 Fix: Actual API response has 'content' array, not 'output'
            // content: [{"type": "text", "text": "result_value"}]
            // details: {"result": "result_value"}
            let content: [ContentItem]?
            let details: EvalDetails?
            
            struct ContentItem: Codable {
                let type: String
                let text: String?
            }
        }
        
        struct EvalDetails: Codable {
            let result: String?
        }
        
        struct ErrorPayload: Codable {
            let message: String?
        }
    }
    
    func canvasEval(javaScript: String, target: String = "host") async throws -> String {
        let data = try await invokeToolRaw(tool: "canvas", action: "eval", args: ["javaScript": javaScript, "target": target])
        
        let response = try JSONDecoder().decode(CanvasEvalResponse.self, from: data)
        
        if let error = response.error {
            throw GatewayError.serverError(error.message ?? "Eval failed")
        }
        
        // H2 Fix: Prefer details.result, fallback to content[0].text
        if let result = response.result?.details?.result {
            return result
        }
        if let content = response.result?.content,
           let firstText = content.first(where: { $0.type == "text" })?.text {
            return firstText
        }
        return ""
    }
    
    // MARK: - Memory Search
    
    struct MemorySearchResponse: Codable {
        let ok: Bool
        let result: MemorySearchResult?
        let error: ErrorPayload?
        
        struct MemorySearchResult: Codable {
            let output: String?
            let details: MemorySearchDetails?
        }
        
        struct MemorySearchDetails: Codable {
            let results: [MemorySearchHit]?
            let count: Int?
        }
        
        struct ErrorPayload: Codable {
            let message: String?
        }
    }
    
    struct MemorySearchHit: Codable {
        let content: String?
        let score: Double?
        let metadata: [String: String]?
    }
    
    func searchMemory(query: String, limit: Int = 10) async throws -> [MemorySearchHit] {
        let data = try await invokeToolRaw(
            tool: "memory_search",
            args: ["query": query, "limit": limit]
        )
        
        // Note: Search count now tracked from actual session logs via fetchMemorySearchCount()
        
        do {
            let response = try JSONDecoder().decode(MemorySearchResponse.self, from: data)
            
            if let error = response.error {
                throw GatewayError.serverError(error.message ?? "Memory search failed")
            }
            
            return response.result?.details?.results ?? []
        } catch let error as GatewayError {
            throw error
        } catch {
            throw GatewayError.decodingError(error)
        }
    }
    
    // MARK: - Nodes Status
    
    struct NodesStatusResponse: Codable {
        let ok: Bool
        let result: NodesStatusResult?
        let error: ErrorPayload?
        
        struct NodesStatusResult: Codable {
            let details: NodesStatusDetails?
            let output: String?
        }
        
        struct NodesStatusDetails: Codable {
            let nodes: [NodeInfo]?
            let count: Int?
        }
        
        struct ErrorPayload: Codable {
            let message: String?
        }
    }
    
    struct NodeInfo: Codable {
        let id: String?
        let name: String?
        let platform: String?
        let connected: Bool?
        let lastSeen: Int64?
        let capabilities: [String]?
    }
    
    func fetchNodesStatus() async throws -> (total: Int, connected: Int, nodes: [NodeInfo]) {
        let data = try await invokeToolRaw(tool: "nodes", action: "status")
        
        // First try to decode as structured response
        do {
            let response = try JSONDecoder().decode(NodesStatusResponse.self, from: data)
            
            if let error = response.error {
                throw GatewayError.serverError(error.message ?? "Failed to fetch nodes status")
            }
            
            if let details = response.result?.details, let nodes = details.nodes {
                let connected = nodes.filter { $0.connected == true }.count
                return (total: nodes.count, connected: connected, nodes: nodes)
            }
            
            // Fallback: parse output string if details not available
            if let output = response.result?.output {
                // Parse text output like "1 node(s) paired, 1 connected"
                return parseNodesOutput(output)
            }
            
            return (total: 0, connected: 0, nodes: [])
        } catch let error as GatewayError {
            throw error
        } catch {
            // Try parsing as plain text output
            if let output = String(data: data, encoding: .utf8) {
                return parseNodesOutput(output)
            }
            throw GatewayError.decodingError(error)
        }
    }
    
    private func parseNodesOutput(_ output: String) -> (total: Int, connected: Int, nodes: [NodeInfo]) {
        // Parse text like "1 node(s) paired" or similar
        var total = 0
        var connected = 0
        
        // Look for patterns like "X node(s)" or "X connected"
        let lines = output.lowercased().components(separatedBy: "\n")
        for line in lines {
            if line.contains("node") {
                // Extract numbers from the line
                let numbers = line.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .compactMap { Int($0) }
                    .filter { $0 > 0 }
                
                if !numbers.isEmpty {
                    if line.contains("paired") || line.contains("total") {
                        total = numbers.first ?? 0
                    }
                    if line.contains("connected") || line.contains("online") {
                        connected = numbers.last ?? numbers.first ?? 0
                    }
                }
            }
        }
        
        // If we only found one number, assume it's both total and connected
        if total == 0 && connected > 0 {
            total = connected
        }
        if connected == 0 && total > 0 && output.contains("connected") {
            connected = total
        }
        
        return (total: total, connected: connected, nodes: [])
    }
    
    // MARK: - Gateway Health (Heartbeat Config)
    
    /// Response from gateway health --json
    struct GatewayHealthResponse: Codable {
        let heartbeatSeconds: Int?
        let agents: [AgentHealth]?
        
        struct AgentHealth: Codable {
            let agentId: String
            let isDefault: Bool?
            let heartbeat: HeartbeatConfig?
        }
    }
    
    /// Fetch Gateway health status including heartbeat config
    /// 
    /// Runs `openclaw gateway health --json` directly via Process.
    /// This bypasses the HTTP API which requires authentication and
    /// doesn't expose the exec tool.
    func fetchGatewayHealth() async throws -> GatewayHealthResponse {
        // Run CLI command directly via Process (no HTTP API needed)
        let result = await Self.runOpenClawCommand(["gateway", "health", "--json"])
        
        if let error = result.error {
            throw GatewayError.serverError(error)
        }
        
        guard !result.stdout.isEmpty else {
            throw GatewayError.serverError("Empty response from gateway health")
        }
        
        // Parse the health JSON
        let healthData = Data(result.stdout.utf8)
        do {
            return try JSONDecoder().decode(GatewayHealthResponse.self, from: healthData)
        } catch {
            throw GatewayError.decodingError(error)
        }
    }
    
    // MARK: - CLI Execution Helper
    
    /// Result from running a CLI command
    struct CLIResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
        var error: String? {
            if exitCode != 0 {
                return stderr.isEmpty ? "Command failed with exit code \(exitCode)" : stderr
            }
            return nil
        }
    }
    
    /// Run an openclaw CLI command directly via Process
    /// This is used for commands that aren't available through the HTTP API
    nonisolated static func runOpenClawCommand(_ arguments: [String]) async -> CLIResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                
                // Try to find openclaw in common locations
                let possiblePaths = [
                    "/opt/homebrew/bin/openclaw",
                    "/usr/local/bin/openclaw",
                    "/usr/bin/openclaw"
                ]
                
                var openclawPath: String?
                for path in possiblePaths {
                    if FileManager.default.fileExists(atPath: path) {
                        openclawPath = path
                        break
                    }
                }
                
                guard let executablePath = openclawPath else {
                    let result = CLIResult(
                        stdout: "",
                        stderr: "openclaw not found in PATH",
                        exitCode: 1
                    )
                    continuation.resume(returning: result)
                    return
                }
                
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                // Set PATH environment variable to include homebrew
                var env = ProcessInfo.processInfo.environment
                if let path = env["PATH"] {
                    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(path)"
                } else {
                    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                }
                process.environment = env
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                    
                    let result = CLIResult(
                        stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                        stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                        exitCode: process.terminationStatus
                    )
                    continuation.resume(returning: result)
                } catch {
                    let result = CLIResult(
                        stdout: "",
                        stderr: "Failed to run command: \(error.localizedDescription)",
                        exitCode: 1
                    )
                    continuation.resume(returning: result)
                }
            }
        }
    }
}
