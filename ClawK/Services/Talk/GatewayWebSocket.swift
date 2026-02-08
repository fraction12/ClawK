//
//  GatewayWebSocket.swift
//  ClawK
//
//  WebSocket gateway client for Talk Mode streaming chat
//

import Foundation
import os

private let logger = Logger(subsystem: "ai.openclaw.clawk", category: "talk-gateway")

@MainActor
class GatewayWebSocket: ObservableObject {
    @Published var isConnected = false
    @Published var lastError: String?
    @Published var connectionState: ConnectionState = .disconnected
    @Published var reconnectAttempt: Int = 0

    enum ConnectionState: String, Sendable {
        case disconnected = "Disconnected"
        case connecting = "Connecting..."
        case connected = "Connected"
        case reconnecting = "Reconnecting..."
    }

    private enum CircuitState {
        case closed
        case open(reopenAt: Date)
        case halfOpen
    }
    private var circuitState: CircuitState = .closed
    private let circuitOpenDuration: TimeInterval = 60
    private let circuitOpenThreshold = 5

    private var sessionKey: String
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var pendingRequests: [String: (Result<Any?, Error>) -> Void] = [:]
    private var connectNonce: String?
    private var instanceId: String

    /// Called with (content, isDone) for each streaming chunk
    var onResponseChunk: ((String, Bool) -> Void)?

    private var currentRunId: String?
    private var currentStreamText: String = ""

    private var autoReconnectEnabled = true
    private var reconnectTask: Task<Void, Never>?
    private let maxReconnectDelay: TimeInterval = 30
    private let baseReconnectDelay: TimeInterval = 1

    private var heartbeatTask: Task<Void, Never>?
    private let heartbeatInterval: TimeInterval = 25

    private var handshakeTimeoutTask: Task<Void, Never>?
    private let handshakeTimeout: TimeInterval = 10

    /// Derive WebSocket URL from GatewayConfig HTTP URL
    private var wsURL: String {
        let base = GatewayConfig.shared.baseURL
        if base.hasPrefix("https://") {
            return "wss://" + base.dropFirst("https://".count)
        } else if base.hasPrefix("http://") {
            return "ws://" + base.dropFirst("http://".count)
        }
        return "ws://" + base
    }

    private var token: String {
        GatewayConfig.shared.token ?? ""
    }

    init(sessionKey: String = "agent:main:clawk-talk") {
        self.sessionKey = sessionKey
        self.instanceId = UUID().uuidString
    }

    func connect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        connectionState = .connecting

        guard let url = URL(string: wsURL) else {
            lastError = "Invalid gateway URL"
            connectionState = .disconnected
            return
        }

        var request = URLRequest(url: url)
        request.setValue("http://127.0.0.1:18789", forHTTPHeaderField: "Origin")

        let session = URLSession(configuration: .default)
        self.urlSession = session
        let task = session.webSocketTask(with: request)
        self.webSocket = task
        task.resume()

        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = Task { [weak self] in
            guard let self = self else { return }
            let timeout = self.handshakeTimeout
            do {
                try await Task.sleep(for: .seconds(timeout))
            } catch { return }
            guard !Task.isCancelled, !self.isConnected else { return }
            logger.warning("Handshake timed out")
            self.webSocket?.cancel(with: .goingAway, reason: nil)
            self.handleDisconnect(error: NSError(
                domain: "GatewayWebSocket",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Handshake timed out"]
            ))
        }

        listenForMessages()
    }

    func disconnect() {
        autoReconnectEnabled = false
        reconnectTask?.cancel()
        reconnectTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
        connectionState = .disconnected
        pendingRequests.removeAll()
    }

    func sendMessage(_ text: String) async throws {
        guard isConnected else {
            throw GatewayError.networkError(NSError(
                domain: "GatewayWebSocket",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not connected to gateway"]
            ))
        }

        let reqId = UUID().uuidString
        currentRunId = reqId
        currentStreamText = ""

        let params: [String: Any] = [
            "sessionKey": sessionKey,
            "message": text,
            "deliver": false,
            "idempotencyKey": reqId
        ]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sendRequest(method: "chat.send", params: params, id: reqId) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func listenForMessages() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    self.listenForMessages()
                case .failure(let error):
                    self.handleDisconnect(error: error)
                }
            }
        }
    }

    private func handleDisconnect(error: Error) {
        let wasConnected = isConnected
        isConnected = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        webSocket = nil

        let pending = pendingRequests
        pendingRequests.removeAll()
        for (_, callback) in pending {
            callback(.failure(error))
        }

        if autoReconnectEnabled {
            connectionState = .reconnecting
            lastError = "Connection lost. Reconnecting..."
            scheduleReconnect(wasConnected: wasConnected)
        } else {
            connectionState = .disconnected
            lastError = "WebSocket error: \(error.localizedDescription)"
        }
    }

    private func scheduleReconnect(wasConnected: Bool) {
        reconnectTask?.cancel()

        if wasConnected {
            reconnectAttempt = 0
            circuitState = .closed
        }

        reconnectTask = Task { [weak self] in
            guard let self = self else { return }

            switch self.circuitState {
            case .open(let reopenAt):
                let waitTime = reopenAt.timeIntervalSinceNow
                if waitTime > 0 {
                    self.lastError = "Gateway unreachable. Will retry in \(Int(ceil(waitTime)))s."
                    do { try await Task.sleep(for: .seconds(waitTime)) } catch { return }
                    guard !Task.isCancelled else { return }
                }
                self.circuitState = .halfOpen
                self.connect()
                return
            case .halfOpen:
                self.circuitState = .open(reopenAt: Date().addingTimeInterval(self.circuitOpenDuration))
                self.lastError = "Gateway unreachable. Will retry in \(Int(self.circuitOpenDuration))s."
                self.scheduleReconnect(wasConnected: false)
                return
            case .closed:
                break
            }

            if self.reconnectAttempt >= self.circuitOpenThreshold {
                self.circuitState = .open(reopenAt: Date().addingTimeInterval(self.circuitOpenDuration))
                self.lastError = "Gateway unreachable after \(self.reconnectAttempt) attempts."
                self.scheduleReconnect(wasConnected: false)
                return
            }

            let delay = min(
                self.baseReconnectDelay * pow(2, Double(self.reconnectAttempt)),
                self.maxReconnectDelay
            )
            self.reconnectAttempt += 1

            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }

            logger.info("Reconnect attempt \(self.reconnectAttempt)")
            self.connect()
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            guard let self = self else { return }
            let interval = self.heartbeatInterval
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
                guard !Task.isCancelled else { return }
                self.webSocket?.sendPing { error in
                    if let error = error {
                        Task { @MainActor [weak self] in
                            self?.handleDisconnect(error: error)
                        }
                    }
                }
            }
        }
    }

    private static let jsonDecoder = JSONDecoder()

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        if let incoming = try? Self.jsonDecoder.decode(TalkGatewayIncoming.self, from: data) {
            handleTypedMessage(incoming)
        } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String {
            handleMessageFallback(type: type, json: json)
        }
    }

    private func handleTypedMessage(_ msg: TalkGatewayIncoming) {
        switch msg.type {
        case "event":
            guard let event = msg.event else { return }
            switch event {
            case "connect.challenge":
                connectNonce = msg.payload?.nonce
                sendConnectRequest()
            case "chat":
                handleChatEvent(msg.payload)
            default:
                break
            }
        case "res":
            guard let id = msg.id else { return }
            let ok = msg.ok ?? false
            if let callback = pendingRequests.removeValue(forKey: id) {
                if ok {
                    callback(.success(nil))
                } else {
                    let errMsg = msg.error?.message ?? "Request failed"
                    callback(.failure(NSError(
                        domain: "GatewayWebSocket",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: errMsg]
                    )))
                }
            }
            if ok, let payload = msg.payload, payload.snapshot != nil {
                completeHandshake()
            }
        default:
            break
        }
    }

    private func handleMessageFallback(type: String, json: [String: Any]) {
        switch type {
        case "event":
            guard let event = json["event"] as? String else { return }
            let payload = json["payload"] as? [String: Any]
            switch event {
            case "connect.challenge":
                connectNonce = payload?["nonce"] as? String
                sendConnectRequest()
            case "chat":
                handleChatEventFallback(payload)
            default:
                break
            }
        case "res":
            guard let id = json["id"] as? String else { return }
            let ok = json["ok"] as? Bool ?? false
            if let callback = pendingRequests.removeValue(forKey: id) {
                if ok {
                    callback(.success(json["payload"]))
                } else {
                    let errMsg = (json["error"] as? [String: Any])?["message"] as? String ?? "Request failed"
                    callback(.failure(NSError(
                        domain: "GatewayWebSocket",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: errMsg]
                    )))
                }
            }
            if ok, let payload = json["payload"] as? [String: Any], payload["snapshot"] != nil {
                completeHandshake()
            }
        default:
            break
        }
    }

    private func completeHandshake() {
        isConnected = true
        connectionState = .connected
        lastError = nil
        reconnectAttempt = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        circuitState = .closed
        autoReconnectEnabled = true
        startHeartbeat()
    }

    private func handleChatEvent(_ payload: TalkGatewayPayload?) {
        guard let payload = payload else { return }
        let state = payload.state ?? ""
        switch state {
        case "delta":
            if let msg = payload.message, let text = msg.content?.textValue ?? msg.text {
                currentStreamText = text
                onResponseChunk?(text, false)
            }
        case "final":
            if let msg = payload.message, let text = msg.content?.textValue ?? msg.text {
                currentStreamText = text
            }
            if !currentStreamText.isEmpty {
                onResponseChunk?(currentStreamText, true)
            }
            currentRunId = nil
            currentStreamText = ""
        case "error":
            let errorMsg = payload.errorMessage ?? "Chat error"
            lastError = errorMsg
            onResponseChunk?(errorMsg, true)
            currentRunId = nil
            currentStreamText = ""
        case "aborted":
            currentRunId = nil
            currentStreamText = ""
        default:
            break
        }
    }

    private func handleChatEventFallback(_ payload: [String: Any]?) {
        guard let payload = payload else { return }
        let state = payload["state"] as? String ?? ""
        switch state {
        case "delta":
            if let message = payload["message"] as? [String: Any],
               let text = extractTextFallback(from: message) {
                currentStreamText = text
                onResponseChunk?(text, false)
            }
        case "final":
            if let message = payload["message"] as? [String: Any],
               let text = extractTextFallback(from: message) {
                currentStreamText = text
            }
            if !currentStreamText.isEmpty {
                onResponseChunk?(currentStreamText, true)
            }
            currentRunId = nil
            currentStreamText = ""
        case "error":
            let errorMsg = payload["errorMessage"] as? String ?? "Chat error"
            lastError = errorMsg
            onResponseChunk?(errorMsg, true)
            currentRunId = nil
            currentStreamText = ""
        case "aborted":
            currentRunId = nil
            currentStreamText = ""
        default:
            break
        }
    }

    private func extractTextFallback(from message: [String: Any]) -> String? {
        if let content = message["content"] as? [[String: Any]] {
            let texts = content.compactMap { block -> String? in
                block["type"] as? String == "text" ? block["text"] as? String : nil
            }
            if !texts.isEmpty { return texts.joined(separator: "\n") }
        }
        if let content = message["content"] as? String { return content }
        if let text = message["text"] as? String { return text }
        return nil
    }

    private func sendConnectRequest() {
        let params: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 3,
            "client": [
                "id": "cli",
                "version": "1.0.0",
                "platform": "macOS",
                "mode": "cli",
                "instanceId": instanceId
            ] as [String: Any],
            "role": "operator",
            "scopes": ["operator.admin", "operator.approvals", "operator.pairing"],
            "caps": [] as [String],
            "auth": [
                "token": token
            ]
        ]

        sendRequest(method: "connect", params: params, id: UUID().uuidString) { [weak self] result in
            Task { @MainActor [weak self] in
                if case .failure(let error) = result {
                    self?.lastError = "Connect failed: \(error.localizedDescription)"
                    self?.isConnected = false
                }
            }
        }
    }

    private func sendRequest(
        method: String,
        params: [String: Any],
        id: String,
        completion: @escaping (Result<Any?, Error>) -> Void
    ) {
        let request: [String: Any] = [
            "type": "req",
            "id": id,
            "method": method,
            "params": params
        ]

        pendingRequests[id] = completion

        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let text = String(data: data, encoding: .utf8) else {
            pendingRequests.removeValue(forKey: id)
            completion(.failure(NSError(
                domain: "GatewayWebSocket",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request"]
            )))
            return
        }

        webSocket?.send(.string(text)) { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.pendingRequests.removeValue(forKey: id)
                    completion(.failure(error))
                }
            }
        }
    }
}
