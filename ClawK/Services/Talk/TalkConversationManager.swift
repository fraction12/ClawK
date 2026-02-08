//
//  TalkConversationManager.swift
//  ClawK
//
//  Central state machine orchestrating STT → Gateway → TTS pipeline
//

import Foundation
import NaturalLanguage
import os

private let logger = Logger(subsystem: "ai.openclaw.clawk", category: "talk-conversation")

@MainActor
class TalkConversationManager: ObservableObject {
    /// Single shared instance — used by TalkView, SettingsView, and overlay panel
    static let shared = TalkConversationManager()

    @Published var state: TalkConversationState = .idle
    @Published var userTranscript: String = ""
    @Published var claudeResponse: String = ""
    @Published var errorMessage: String?
    @Published var messages: [TalkChatMessage] = []

    private let maxHistoryMessages = 20

    let audioEngine = TalkAudioEngine()
    let speechRecognizer = TalkSpeechRecognizer()
    let gatewayWebSocket: GatewayWebSocket
    let ttsClient: TalkStreamingTTSClient
    let voiceActivityDetector = TalkVoiceActivityDetector()
    let ttsServerManager = TalkTTSServerManager()

    private var responseBuffer = ""
    private var lastSpokenIndex: String.Index?
    private var lastEnqueuedSentence: String?
    private var thinkingTimeoutTask: Task<Void, Never>?
    private var streamingTimeoutTask: Task<Void, Never>?

    /// Talk Mode settings from UserDefaults
    @Published var soundEffectsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundEffectsEnabled, forKey: "talkSoundEffects")
            TalkSoundEffects.shared.enabled = soundEffectsEnabled
        }
    }
    @Published var silenceThreshold: Double {
        didSet { UserDefaults.standard.set(silenceThreshold, forKey: "talkSilenceThreshold") }
    }
    @Published var interruptOnSpeech: Bool {
        didSet { UserDefaults.standard.set(interruptOnSpeech, forKey: "talkInterruptOnSpeech") }
    }

    private init() {
        // Load settings from UserDefaults
        let storedSilence = UserDefaults.standard.double(forKey: "talkSilenceThreshold")
        self.silenceThreshold = storedSilence > 0 ? storedSilence : 1.5
        self.soundEffectsEnabled = UserDefaults.standard.object(forKey: "talkSoundEffects") as? Bool ?? true
        self.interruptOnSpeech = UserDefaults.standard.object(forKey: "talkInterruptOnSpeech") as? Bool ?? true

        // Initialize gateway using GatewayConfig.shared
        self.gatewayWebSocket = GatewayWebSocket()

        // Initialize TTS client
        let ttsURL = UserDefaults.standard.string(forKey: "talkTTSServerURL") ?? "ws://localhost:8765"
        self.ttsClient = TalkStreamingTTSClient(ttsURL: ttsURL)

        TalkSoundEffects.shared.enabled = soundEffectsEnabled
        setupCallbacks()
        setupVoiceActivityDetector()
        setupAudioLevelForwarding()
        loadHistory()
    }

    // MARK: - Setup

    private func setupVoiceActivityDetector() {
        voiceActivityDetector.onSpeechDetected = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.state == .speaking else { return }
                // Bug 3 fix: Clean up speaking state fully before starting listening
                self.voiceActivityDetector.stopMonitoring()
                self.audioEngine.stop()
                self.ttsClient.stopPlayback()
                self.transition(to: .idle)
                self.startListening()
            }
        }
    }

    private func setupAudioLevelForwarding() {
        audioEngine.onAudioLevel = { [weak self] rms in
            self?.voiceActivityDetector.feedAudioLevel(rms)
        }
    }

    private func setupCallbacks() {
        speechRecognizer.onSilenceDetected = { [weak self] text in
            Task { @MainActor [weak self] in
                await self?.handleTranscript(text)
            }
        }

        gatewayWebSocket.onResponseChunk = { [weak self] content, done in
            Task { @MainActor [weak self] in
                self?.handleResponseChunk(content: content, done: done)
            }
        }

        ttsClient.onPlaybackFinished = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Bug 2 fix: Only transition to idle from .speaking, not from .thinking
                // (during .thinking, response may still be streaming)
                if self.state == .speaking {
                    self.transition(to: .idle)
                }
            }
        }

        ttsClient.onFirstSentencePlaying = { [weak self] in
            Task { @MainActor [weak self] in
                if self?.state == .thinking {
                    self?.transition(to: .speaking)
                }
            }
        }

        ttsClient.onSynthesisError = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.errorMessage = message
            }
        }
    }

    // MARK: - Public API

    func toggleListening() {
        switch state {
        case .idle:
            startListening()
        case .listening:
            stopListening()
        case .speaking:
            // Bug 3 fix: Stop VAD monitoring and audio engine before starting listening
            // to avoid "tap already installed" crash
            voiceActivityDetector.stopMonitoring()
            audioEngine.stop()
            ttsClient.stopPlayback()
            transition(to: .idle)
            startListening()
        case .thinking:
            break
        }
    }

    func startListening() {
        errorMessage = nil
        userTranscript = ""
        claudeResponse = ""
        responseBuffer = ""
        lastSpokenIndex = nil
        lastEnqueuedSentence = nil

        Task {
            let authorized = await TalkSpeechRecognizer.requestAuthorization()
            guard authorized else {
                errorMessage = "Speech recognition not authorized"
                TalkSoundEffects.shared.playError()
                return
            }

            speechRecognizer.silenceThreshold = silenceThreshold

            do {
                try speechRecognizer.startRecognition(audioEngine: audioEngine)
                transition(to: .listening)
            } catch {
                errorMessage = "Failed to start: \(error.localizedDescription)"
                TalkSoundEffects.shared.playError()
            }
        }
    }

    func stopListening() {
        speechRecognizer.stopRecognition()
        audioEngine.stop()
        transition(to: .idle)
    }

    func clearHistory() {
        messages.removeAll()
        userTranscript = ""
        claudeResponse = ""
        saveHistory()
    }

    func startTTSServer() {
        ttsServerManager.start()
    }

    func stopTTSServer() {
        ttsServerManager.stop()
    }

    // MARK: - Transcript Handling

    private func handleTranscript(_ text: String) async {
        userTranscript = text
        messages.append(TalkChatMessage(role: .user, text: text))
        trimHistory()
        saveHistory()

        speechRecognizer.stopRecognition()
        audioEngine.stop()
        transition(to: .thinking)

        ttsClient.prepareForStreaming()
        lastSpokenIndex = nil
        lastEnqueuedSentence = nil

        if !gatewayWebSocket.isConnected {
            gatewayWebSocket.connect()
            for _ in 0..<50 {
                try? await Task.sleep(for: .milliseconds(100))
                if gatewayWebSocket.isConnected { break }
            }
            guard gatewayWebSocket.isConnected else {
                errorMessage = "Could not connect to gateway"
                transition(to: .idle)
                TalkSoundEffects.shared.playError()
                return
            }
        }

        do {
            try await gatewayWebSocket.sendMessage(text)
        } catch {
            errorMessage = "Failed to send: \(error.localizedDescription)"
            transition(to: .idle)
            TalkSoundEffects.shared.playError()
        }
    }

    // MARK: - Response Handling

    private func handleResponseChunk(content: String, done: Bool) {
        claudeResponse = content

        // Bug 7 fix: Reset streaming timeout on every chunk
        resetStreamingTimeout()

        if done {
            streamingTimeoutTask?.cancel()
            streamingTimeoutTask = nil

            messages.append(TalkChatMessage(role: .assistant, text: content))
            trimHistory()
            saveHistory()
            claudeResponse = ""

            let unspoken = extractUnspokenText(from: content)
            if !unspoken.isEmpty && unspoken != lastEnqueuedSentence {
                lastEnqueuedSentence = unspoken
                ttsClient.enqueueSentence(unspoken)
            }
            ttsClient.finalizeQueue()

            if state == .thinking {
                transition(to: .speaking)
            }
        } else {
            extractAndEnqueueSentences(from: content)
        }
    }

    /// Bug 7: If no streaming chunk received within 30s, assume agent crashed
    private func resetStreamingTimeout() {
        streamingTimeoutTask?.cancel()
        streamingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            guard let self = self, self.state == .thinking || self.state == .speaking else { return }
            logger.warning("Streaming timed out — no data for 30s")
            self.errorMessage = "Streaming timed out"
            self.ttsClient.stopPlayback()
            self.transition(to: .idle)
            TalkSoundEffects.shared.playError()
        }
    }

    // MARK: - Sentence Extraction (NLTokenizer)

    private func extractAndEnqueueSentences(from fullText: String) {
        let startIndex = lastSpokenIndex ?? fullText.startIndex
        guard startIndex < fullText.endIndex else { return }

        let unprocessed = String(fullText[startIndex...])

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = unprocessed

        var sentencesFound: [(String, String.Index)] = []

        tokenizer.enumerateTokens(in: unprocessed.startIndex..<unprocessed.endIndex) { range, _ in
            let sentence = String(unprocessed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                if range.upperBound < unprocessed.endIndex {
                    sentencesFound.append((sentence, range.upperBound))
                }
            }
            return true
        }

        for (sentence, endInUnprocessed) in sentencesFound {
            lastEnqueuedSentence = sentence
            ttsClient.enqueueSentence(sentence)
            let offset = unprocessed.distance(from: unprocessed.startIndex, to: endInUnprocessed)
            lastSpokenIndex = fullText.index(startIndex, offsetBy: offset)
        }
    }

    private func extractUnspokenText(from fullText: String) -> String {
        let startIndex = lastSpokenIndex ?? fullText.startIndex
        guard startIndex < fullText.endIndex else { return "" }
        return String(fullText[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - State Transitions

    private func transition(to newState: TalkConversationState) {
        let old = state
        state = newState
        guard old != newState else { return }

        if old == .thinking {
            thinkingTimeoutTask?.cancel()
            thinkingTimeoutTask = nil
        }

        // VAD management during speaking
        if newState == .speaking && interruptOnSpeech {
            voiceActivityDetector.startMonitoring()
            do {
                try audioEngine.startMonitoring()
            } catch {
                logger.error("Failed to start audio monitoring: \(error.localizedDescription, privacy: .public)")
            }
        } else if old == .speaking {
            voiceActivityDetector.stopMonitoring()
            audioEngine.stop()
        }

        // Thinking timeout
        if newState == .thinking {
            thinkingTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                guard let self = self, self.state == .thinking else { return }
                logger.warning("Thinking state timed out after 30s")
                self.errorMessage = "Response timed out"
                self.ttsClient.stopPlayback()
                self.transition(to: .idle)
                TalkSoundEffects.shared.playError()
            }
        }

        // Sound effects
        switch newState {
        case .listening:
            TalkSoundEffects.shared.playListenStart()
        case .thinking:
            TalkSoundEffects.shared.playThinkingStart()
        case .speaking:
            TalkSoundEffects.shared.playSpeakingStart()
        case .idle:
            if old == .speaking {
                TalkSoundEffects.shared.playIdle()
            }
        }
    }

    // MARK: - History Persistence

    private func trimHistory() {
        if messages.count > maxHistoryMessages {
            messages.removeFirst(messages.count - maxHistoryMessages)
            saveHistory()
        }
    }

    private static var historyURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ClawK")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("talk_conversation_history.json")
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        try? data.write(to: Self.historyURL)
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: Self.historyURL),
              let loaded = try? JSONDecoder().decode([TalkChatMessage].self, from: data) else { return }
        messages = loaded
    }

    // MARK: - Export

    func exportConversation() -> String {
        var output = "ClawK Talk Mode - Conversation Export\n"
        output += "Date: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))\n"
        output += String(repeating: "=", count: 40) + "\n\n"
        for msg in messages {
            let role = msg.role == .user ? "You" : "Claude"
            let time = DateFormatter.localizedString(from: msg.timestamp, dateStyle: .none, timeStyle: .short)
            output += "[\(time)] \(role):\n\(msg.text)\n\n"
        }
        return output
    }
}
