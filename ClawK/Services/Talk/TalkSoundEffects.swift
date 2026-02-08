//
//  TalkSoundEffects.swift
//  ClawK
//
//  Synthesized sound effects for Talk Mode state transitions
//

import AVFoundation
import os

private let logger = Logger(subsystem: "ai.openclaw.clawk", category: "talk-sfx")

@MainActor
final class TalkSoundEffects {
    static let shared = TalkSoundEffects()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let sampleRate: Double = 44100
    private var isSetUp = false

    var enabled = true

    private init() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
    }

    private func ensureRunning() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            isSetUp = true
        } catch {
            logger.error("Failed to start SFX engine: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Soft ascending two-tone — listening started
    func playListenStart() {
        guard enabled else { return }
        playTones([
            Tone(frequency: 880, duration: 0.06, volume: 0.15),
            Tone(frequency: 1320, duration: 0.08, volume: 0.12),
        ])
    }

    /// Single soft tone — now thinking
    func playThinkingStart() {
        guard enabled else { return }
        playTones([
            Tone(frequency: 660, duration: 0.08, volume: 0.10),
        ])
    }

    /// Gentle ascending chime — speaking started
    func playSpeakingStart() {
        guard enabled else { return }
        playTones([
            Tone(frequency: 523, duration: 0.06, volume: 0.08),
            Tone(frequency: 659, duration: 0.06, volume: 0.10),
            Tone(frequency: 784, duration: 0.10, volume: 0.08),
        ])
    }

    /// Soft completion tone — back to idle
    func playIdle() {
        guard enabled else { return }
        playTones([
            Tone(frequency: 440, duration: 0.10, volume: 0.06),
        ])
    }

    /// Error buzz — low tone
    func playError() {
        guard enabled else { return }
        playTones([
            Tone(frequency: 220, duration: 0.12, volume: 0.15),
            Tone(frequency: 196, duration: 0.12, volume: 0.12),
        ])
    }

    // MARK: - Tone Generation

    private struct Tone {
        let frequency: Double
        let duration: Double
        let volume: Float
    }

    private func playTones(_ tones: [Tone]) {
        ensureRunning()

        let totalDuration = tones.reduce(0.0) { $0 + $1.duration }
        let totalFrames = Int(totalDuration * sampleRate)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else { return }
        buffer.frameLength = AVAudioFrameCount(totalFrames)

        guard let channelData = buffer.floatChannelData?[0] else { return }

        var frameOffset = 0
        for tone in tones {
            let toneFrames = Int(tone.duration * sampleRate)
            let fadeFrames = min(Int(0.005 * sampleRate), toneFrames / 4)

            for i in 0..<toneFrames {
                let phase = 2.0 * Double.pi * tone.frequency * Double(i) / sampleRate
                var sample = Float(sin(phase)) * tone.volume

                if i < fadeFrames {
                    sample *= Float(i) / Float(fadeFrames)
                }
                let fadeOutStart = toneFrames - fadeFrames
                if i > fadeOutStart {
                    sample *= Float(toneFrames - i) / Float(fadeFrames)
                }

                channelData[frameOffset + i] = sample
            }
            frameOffset += toneFrames
        }

        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        playerNode.stop()
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        playerNode.play()
    }
}
