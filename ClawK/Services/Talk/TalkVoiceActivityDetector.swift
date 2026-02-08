//
//  TalkVoiceActivityDetector.swift
//  ClawK
//
//  Voice activity detection to interrupt TTS when user speaks
//

import Foundation
import os

private let logger = Logger(subsystem: "ai.openclaw.clawk", category: "talk-vad")

@MainActor
class TalkVoiceActivityDetector {
    var speechThreshold: Float = 0.06
    var requiredConsecutiveFrames: Int = 4
    var gracePeriodSeconds: TimeInterval = 0.8
    var onSpeechDetected: (() -> Void)?

    private var isMonitoring = false
    private var consecutiveFramesAboveThreshold = 0
    private var startTime: Date?

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        consecutiveFramesAboveThreshold = 0
        startTime = Date()
        logger.debug("VAD monitoring started (threshold: \(self.speechThreshold), frames: \(self.requiredConsecutiveFrames))")
    }

    func stopMonitoring() {
        isMonitoring = false
        consecutiveFramesAboveThreshold = 0
        startTime = nil
    }

    func feedAudioLevel(_ rms: Float) {
        guard isMonitoring else { return }
        guard let start = startTime, Date().timeIntervalSince(start) > gracePeriodSeconds else { return }

        if rms > speechThreshold {
            consecutiveFramesAboveThreshold += 1
            if consecutiveFramesAboveThreshold >= requiredConsecutiveFrames {
                logger.info("Speech detected during TTS playback, triggering interruption")
                stopMonitoring()
                onSpeechDetected?()
            }
        } else {
            consecutiveFramesAboveThreshold = 0
        }
    }
}
