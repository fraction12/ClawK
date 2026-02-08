//
//  TalkStreamingTTSClient.swift
//  ClawK
//
//  Streaming TTS client with incremental MP3 decode and buffer scheduling
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

    /// Track total scheduled buffers and completed buffers to know when done
    private var scheduledBufferCount = 0
    private var completedBufferCount = 0
    /// Continuation to signal when all buffers for all sentences have finished playing
    private var allDoneContinuation: CheckedContinuation<Void, Never>?

    init(ttsURL: String = "ws://localhost:8766") {
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
        logger.info("TTS WebSocket connecting to \(self.ttsURL, privacy: .public)")
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
        scheduledBufferCount = 0
        completedBufferCount = 0
        allDoneContinuation?.resume()
        allDoneContinuation = nil
        logger.info("TTS playback stopped")
    }

    func prepareForStreaming() {
        stopPlayback()
        stopRequested = false
        firstSentencePlayed = false
        queueFinalized = false
        scheduledBufferCount = 0
        completedBufferCount = 0
        ensureConnected()
    }

    func shutdown() {
        stopPlayback()
        disconnectWebSocket()
    }

    // MARK: - Streaming Queue Processing

    private func startProcessingQueue() {
        isProcessingQueue = true
        processingTask = Task { [weak self] in
            guard let self = self else { return }

            // Ensure engine is running
            if !self.engine.isRunning {
                do {
                    try self.engine.start()
                } catch {
                    logger.error("Failed to start audio engine: \(error.localizedDescription, privacy: .public)")
                    self.isProcessingQueue = false
                    self.onPlaybackFinished?()
                    return
                }
            }
            self.playerNode.play()
            self.isPlaying = true

            while !Task.isCancelled && !self.stopRequested {
                if !self.sentenceQueue.isEmpty {
                    let sentence = self.sentenceQueue.removeFirst()
                    let success = await self.streamSentence(sentence)
                    if !success && !self.stopRequested {
                        // Fallback
                        if !self.firstSentencePlayed {
                            self.firstSentencePlayed = true
                            self.onFirstSentencePlaying?()
                        }
                        await self.speakFallback(sentence)
                    }
                } else if self.queueFinalized {
                    break
                } else {
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }
            }

            guard !self.stopRequested else { return }

            // Wait for all scheduled buffers to finish playing
            if self.scheduledBufferCount > self.completedBufferCount {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.allDoneContinuation = continuation
                    // Check again in case they all completed while we were setting up
                    if self.scheduledBufferCount <= self.completedBufferCount || self.stopRequested {
                        self.allDoneContinuation = nil
                        continuation.resume()
                    }
                }
            }

            guard !self.stopRequested else { return }
            self.isProcessingQueue = false
            self.isPlaying = false
            if self.engine.isRunning { self.engine.stop() }
            self.onPlaybackFinished?()
        }
    }

    // MARK: - Stream a single sentence incrementally

    /// Streams MP3 chunks from WebSocket, decodes incrementally, schedules PCM buffers on playerNode.
    /// Returns true if at least some audio was scheduled, false on total failure.
    private func streamSentence(_ text: String) async -> Bool {
        ensureConnected()
        guard let ws = webSocket else { return false }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clawk-tts-\(UUID().uuidString).mp3")
        var accumulatedData = Data()
        var framesAlreadyScheduled: AVAudioFramePosition = 0
        var anyAudioScheduled = false
        // Decode every N chunks to amortize overhead
        let decodeInterval = 3
        var chunksSinceLastDecode = 0

        func decodeAndScheduleNewFrames() {
            guard !accumulatedData.isEmpty else { return }
            do {
                try accumulatedData.write(to: tempURL)
                let file = try AVAudioFile(forReading: tempURL)
                let totalFrames = file.length
                let newFrames = totalFrames - framesAlreadyScheduled
                guard newFrames > 0 else { return }

                file.framePosition = framesAlreadyScheduled
                let format = file.processingFormat

                // Reconnect playerNode if format changed (first time)
                if !anyAudioScheduled {
                    self.engine.connect(self.playerNode, to: self.engine.mainMixerNode, format: format)
                    if !self.engine.isRunning {
                        try self.engine.start()
                    }
                    if !self.playerNode.isPlaying {
                        self.playerNode.play()
                    }
                }

                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(newFrames)) else { return }
                try file.read(into: buffer)

                self.scheduledBufferCount += 1
                let bufferIndex = self.scheduledBufferCount
                nonisolated(unsafe) let unsafeSelf = self
                self.playerNode.scheduleBuffer(buffer) {
                    DispatchQueue.main.async {
                        unsafeSelf.completedBufferCount += 1
                        if unsafeSelf.completedBufferCount >= unsafeSelf.scheduledBufferCount {
                            unsafeSelf.allDoneContinuation?.resume()
                            unsafeSelf.allDoneContinuation = nil
                        }
                    }
                }

                framesAlreadyScheduled = totalFrames
                anyAudioScheduled = true

                if !self.firstSentencePlayed {
                    self.firstSentencePlayed = true
                    self.onFirstSentencePlaying?()
                }
            } catch {
                // Partial MP3 may not be decodable yet — that's OK, we'll try again with more data
                logger.debug("Incremental decode attempt: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            try await ws.send(.string(text))

            while !Task.isCancelled && !stopRequested {
                let message = try await ws.receive()
                if !isConnected { isConnected = true }

                switch message {
                case .data(let chunk):
                    if chunk == Data("END".utf8) {
                        // Final decode pass
                        decodeAndScheduleNewFrames()
                        cleanup()
                        return anyAudioScheduled
                    }
                    accumulatedData.append(chunk)
                    chunksSinceLastDecode += 1
                    if chunksSinceLastDecode >= decodeInterval {
                        chunksSinceLastDecode = 0
                        decodeAndScheduleNewFrames()
                    }
                case .string(let str):
                    if str == "END" {
                        decodeAndScheduleNewFrames()
                        cleanup()
                        return anyAudioScheduled
                    }
                    if let data = str.data(using: .utf8),
                       let json = try? JSONDecoder().decode([String: String].self, from: data),
                       json["error"] != nil {
                        logger.error("TTS server returned error for sentence")
                        cleanup()
                        return false
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            logger.warning("TTS connection error: \(error.localizedDescription, privacy: .public)")
            cleanup()
            // Reconnect for next sentence
            disconnectWebSocket()
            ensureConnected()
            return anyAudioScheduled
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: tempURL)
        }

        cleanup()
        return anyAudioScheduled
    }

    // MARK: - Fallback

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
}
