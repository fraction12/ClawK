//
//  TalkAudioEngine.swift
//  ClawK
//
//  AVAudioEngine wrapper for Talk Mode mic input
//

import AVFoundation
import os

private let logger = Logger(subsystem: "ai.openclaw.clawk", category: "talk-audio-engine")

@MainActor
class TalkAudioEngine: ObservableObject {
    @Published var audioLevel: Float = 0
    @Published var isRunning = false
    @Published var recentLevels: [Float] = Array(repeating: 0, count: 32)

    private let engine = AVAudioEngine()
    private var monitorOnly = false
    var onAudioLevel: ((Float) -> Void)?
    var inputNode: AVAudioInputNode { engine.inputNode }

    func start(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) throws {
        monitorOnly = false
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            if let data = channelData {
                for i in 0..<frameLength { sum += data[i] * data[i] }
            }
            let rms = sqrt(sum / Float(max(frameLength, 1)))

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.audioLevel = rms
                self.recentLevels.append(rms)
                if self.recentLevels.count > 32 {
                    self.recentLevels.removeFirst(self.recentLevels.count - 32)
                }
                self.onAudioLevel?(rms)
            }
            bufferHandler(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
        logger.info("Audio engine started with buffer handler")
    }

    func startMonitoring() throws {
        monitorOnly = true
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: recordingFormat) { [weak self] buffer, _ in
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            if let data = channelData { for i in 0..<frameLength { sum += data[i] * data[i] } }
            let rms = sqrt(sum / Float(max(frameLength, 1)))

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.audioLevel = rms
                self.onAudioLevel?(rms)
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
        logger.info("Audio engine started in monitor-only mode")
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        monitorOnly = false
        audioLevel = 0
        recentLevels = Array(repeating: 0, count: 32)
        logger.info("Audio engine stopped")
    }
}
