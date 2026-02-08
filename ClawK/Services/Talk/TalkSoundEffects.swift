//
//  TalkSoundEffects.swift
//  ClawK
//
//  Synthesized sound effects for Talk Mode state transitions
//  Bug 6 fix: Uses NSSound with in-memory WAV data instead of a separate AVAudioEngine
//  to avoid conflicting with TalkStreamingTTSClient's audio engine.
//

import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "ai.openclaw.clawk", category: "talk-sfx")

@MainActor
final class TalkSoundEffects {
    static let shared = TalkSoundEffects()

    private let sampleRate: Double = 44100

    var enabled = true

    private init() {}

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
        let totalDuration = tones.reduce(0.0) { $0 + $1.duration }
        let totalFrames = Int(totalDuration * sampleRate)

        // Generate PCM samples
        var samples = [Float](repeating: 0, count: totalFrames)
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

                samples[frameOffset + i] = sample
            }
            frameOffset += toneFrames
        }

        // Convert Float samples to 16-bit PCM
        var pcmData = Data(capacity: totalFrames * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var int16 = Int16(clamped * Float(Int16.max))
            pcmData.append(Data(bytes: &int16, count: 2))
        }

        // Build WAV header + data
        guard let wavData = buildWAV(pcmData: pcmData, sampleRate: UInt32(sampleRate), channels: 1, bitsPerSample: 16) else { return }

        // Play via NSSound (no AVAudioEngine needed)
        if let sound = NSSound(data: wavData) {
            sound.play()
        }
    }

    private func buildWAV(pcmData: Data, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data? {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let chunkSize = 36 + dataSize

        var wav = Data()
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(littleEndian: chunkSize)
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(littleEndian: UInt32(16))          // subchunk1 size
        wav.append(littleEndian: UInt16(1))           // PCM format
        wav.append(littleEndian: channels)
        wav.append(littleEndian: sampleRate)
        wav.append(littleEndian: byteRate)
        wav.append(littleEndian: blockAlign)
        wav.append(littleEndian: bitsPerSample)
        wav.append(contentsOf: "data".utf8)
        wav.append(littleEndian: dataSize)
        wav.append(pcmData)
        return wav
    }
}

// MARK: - Data Helper

private extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: MemoryLayout<T>.size))
    }
}
