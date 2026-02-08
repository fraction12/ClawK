//
//  TalkSpeechRecognizer.swift
//  ClawK
//
//  Speech recognition with silence detection for Talk Mode
//

import Speech
import AVFoundation
import os

private let logger = Logger(subsystem: "ai.openclaw.clawk", category: "talk-speech")

@MainActor
class TalkSpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecognizing = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?

    var silenceThreshold: TimeInterval = 1.5
    var onSilenceDetected: ((String) -> Void)?

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startRecognition(audioEngine: TalkAudioEngine) throws {
        stopRecognition()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.recognitionRequest = request

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            logger.error("Speech recognizer not available")
            throw NSError(domain: "TalkSpeechRecognizer", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Speech recognizer not available"])
        }

        try audioEngine.start { [weak request] buffer in
            request?.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let result = result {
                    self.transcript = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                    if result.isFinal { self.handleFinalResult() }
                }
                if let error = error {
                    logger.warning("Recognition error: \(error.localizedDescription, privacy: .public)")
                    self.stopRecognition()
                }
            }
        }
        isRecognizing = true
        logger.info("Speech recognition started")
    }

    func stopRecognition() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        isRecognizing = false
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleFinalResult() }
        }
    }

    private func handleFinalResult() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        recognitionRequest?.endAudio()
        logger.debug("Silence detected, finalizing transcript (\(text.count) chars)")
        onSilenceDetected?(text)
    }
}
