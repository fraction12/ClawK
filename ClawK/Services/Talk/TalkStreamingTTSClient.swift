//
//  TalkStreamingTTSClient.swift
//  ClawK
//
//  Streaming TTS client with persistent WebSocket and sentence queue
//

import AppKit
import AVFoundation
import Foundation
import os

private let logger = Logger(subsystem: "ai.openclaw.clawk", category: "talk-tts")

@MainActor
class TalkStreamingTTSClient: ObservableObject {
    @Published var isPlaying = false
    @Published var isConnected = false

    private var ttsURL: String
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    private var sentenceQueue: [String] = []
    private var isProcessingQueue = false
    private var queueFinalized = false
    private var processingTask: Task<Void, Never>?
    private var stopRequested = false
    private let fallbackSpeaker = NSSpeechSynthesizer()

    var onPlaybackFinished: (() -> Void)?
    var onFirstSentencePlaying: (() -> Void)?
    var onSynthesisError: ((String) -> Void)?

    private var firstSentencePlayed = false

    init(ttsURL: String = "ws://localhost:8765") {
        self.ttsURL = ttsURL
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        Self.cleanupStaleTempFiles()
    }

    static func cleanupStaleTempFiles() {
        let tmpDir = NSTemporaryDirectory()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: tmpDir) else { return }
        for file in files where file.hasPrefix("clawk-tts-") && file.hasSuffix(".mp3") {
            let path = (tmpDir as NSString).appendingPathComponent(file)
            try? fm.removeItem(atPath: path)
        }
    }

    func ensureConnected() {
        guard webSocket == nil else { return }
        guard let url = URL(string: ttsURL) else {
            logger.error("Invalid TTS URL: \(self.ttsURL, privacy: .public)")
            return
        }
        let session = URLSession(configuration: .default)
        self.urlSession = session
        let task = session.webSocketTask(with: url)
        self.webSocket = task
        task.resume()
        isConnected = true
        logger.info("TTS WebSocket connected to \(self.ttsURL, privacy: .public)")
    }

    private func disconnectWebSocket() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
        logger.info("TTS WebSocket disconnected")
    }

    func enqueueSentence(_ sentence: String) {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sentenceQueue.append(trimmed)
        logger.debug("Enqueued sentence (\(trimmed.count) chars), queue depth: \(self.sentenceQueue.count)")
        if !isProcessingQueue { startProcessingQueue() }
    }

    func finalizeQueue() {
        queueFinalized = true
        if sentenceQueue.isEmpty && !isProcessingQueue {
            onPlaybackFinished?()
        }
    }

    func stopPlayback() {
        stopRequested = true
        processingTask?.cancel()
        processingTask = nil
        playerNode.stop()
        if engine.isRunning { engine.stop() }
        fallbackSpeaker.stopSpeaking()
        sentenceQueue.removeAll()
        isProcessingQueue = false
        queueFinalized = false
        firstSentencePlayed = false
        isPlaying = false
        logger.info("TTS playback stopped")
    }

    func prepareForStreaming() {
        stopPlayback()
        stopRequested = false
        firstSentencePlayed = false
        queueFinalized = false
        ensureConnected()
    }

    func shutdown() {
        stopPlayback()
        disconnectWebSocket()
    }

    private func startProcessingQueue() {
        isProcessingQueue = true
        processingTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled && !self.stopRequested {
                if self.sentenceQueue.isEmpty {
                    if self.queueFinalized { break }
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }
                let sentence = self.sentenceQueue.removeFirst()
                let audioData = await self.synthesizeSentence(sentence)
                guard !Task.isCancelled && !self.stopRequested else { break }
                if let data = audioData, !data.isEmpty {
                    if !self.firstSentencePlayed {
                        self.firstSentencePlayed = true
                        self.onFirstSentencePlaying?()
                    }
                    await self.playAudioDataAndWait(data)
                } else {
                    logger.warning("TTS synthesis failed for sentence, using fallback speaker")
                    if !self.firstSentencePlayed {
                        self.firstSentencePlayed = true
                        self.onFirstSentencePlaying?()
                    }
                    await self.speakFallback(sentence)
                }
            }
            guard !self.stopRequested else { return }
            self.isProcessingQueue = false
            self.isPlaying = false
            if self.engine.isRunning { self.engine.stop() }
            self.onPlaybackFinished?()
        }
    }

    private func synthesizeSentence(_ text: String) async -> Data? {
        return await withTaskGroup(of: Data?.self) { group in
            group.addTask { await self.synthesizeSentenceInternal(text) }
            group.addTask { try? await Task.sleep(for: .seconds(30)); return nil }
            if let result = await group.next() {
                group.cancelAll()
                if let data = result { return data }
                if let secondResult = await group.next() { return secondResult }
                return nil
            }
            return nil
        }
    }

    private func synthesizeSentenceInternal(_ text: String) async -> Data? {
        ensureConnected()
        guard let ws = webSocket else { return nil }
        var audioData = Data()
        do {
            try await ws.send(.string(text))
            while true {
                let message = try await ws.receive()
                switch message {
                case .data(let chunk):
                    if chunk == Data("END".utf8) { return audioData }
                    audioData.append(chunk)
                case .string(let str):
                    if str == "END" { return audioData }
                    if let data = str.data(using: .utf8),
                       let json = try? JSONDecoder().decode([String: String].self, from: data),
                       json["error"] != nil {
                        logger.error("TTS server returned error for sentence")
                        return nil
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            logger.warning("TTS connection error, reconnecting: \(error.localizedDescription, privacy: .public)")
            disconnectWebSocket()
            ensureConnected()
            guard let retryWs = webSocket else { return nil }
            do {
                audioData = Data()
                try await retryWs.send(.string(text))
                while true {
                    let message = try await retryWs.receive()
                    switch message {
                    case .data(let chunk):
                        if chunk == Data("END".utf8) { return audioData }
                        audioData.append(chunk)
                    case .string(let str):
                        if str == "END" { return audioData }
                    @unknown default:
                        break
                    }
                }
            } catch {
                logger.error("TTS retry failed: \(error.localizedDescription, privacy: .public)")
                disconnectWebSocket()
                return nil
            }
        }
    }

    private func speakFallback(_ text: String) async {
        fallbackSpeaker.setVoice(NSSpeechSynthesizer.defaultVoice)
        fallbackSpeaker.startSpeaking(text)
        isPlaying = true
        while fallbackSpeaker.isSpeaking {
            guard !stopRequested, !Task.isCancelled else {
                fallbackSpeaker.stopSpeaking()
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func playAudioDataAndWait(_ data: Data) async {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clawk-tts-\(UUID().uuidString).mp3")
        do {
            try data.write(to: tempURL)
            let file = try AVAudioFile(forReading: tempURL)
            let format = file.processingFormat
            let frameCount = UInt32(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                try? FileManager.default.removeItem(at: tempURL)
                return
            }
            try file.read(into: buffer)
            if !engine.isRunning {
                engine.connect(playerNode, to: engine.mainMixerNode, format: format)
                try engine.start()
            }
            isPlaying = true
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                playerNode.scheduleBuffer(buffer) {
                    Task { @MainActor in
                        try? FileManager.default.removeItem(at: tempURL)
                        continuation.resume()
                    }
                }
                playerNode.play()
            }
        } catch {
            logger.error("Failed to play audio data: \(error.localizedDescription, privacy: .public)")
            isPlaying = false
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
}
