@preconcurrency import AVFoundation
import Foundation
import os

struct CapturedAudio: @unchecked Sendable {
    let buffers: [AVAudioPCMBuffer]

    var seconds: Double {
        buffers.reduce(0) { $0 + Double($1.frameLength) / $1.format.sampleRate }
    }

    func stream() -> AsyncStream<AudioChunk> {
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        for buffer in buffers { continuation.yield(AudioChunk(buffer: buffer)) }
        continuation.finish()
        return stream
    }
}

final class Recorder: @unchecked Sendable {
    static let preRollSeconds = 0.3

    private struct State {
        var capturing = false
        var buffers: [AVAudioPCMBuffer] = []
        var preRoll: [AVAudioPCMBuffer] = []
        var preRollFrames = 0
        var level = 0.0
    }

    private let engine = AVAudioEngine()
    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    var isRunning: Bool { engine.isRunning }
    var level: Double { state.withLockUnchecked { $0.level } }

    func start() throws {
        guard !engine.isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw DictationError.noMicrophone }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.receive(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        state.withLockUnchecked { $0 = State() }
    }

    func beginCapture() {
        state.withLockUnchecked { state in
            state.buffers = state.preRoll
            state.capturing = true
        }
    }

    func endCapture() -> CapturedAudio {
        state.withLockUnchecked { state in
            let captured = CapturedAudio(buffers: state.buffers)
            state.buffers = []
            state.capturing = false
            return captured
        }
    }

    func recent(seconds: Double) -> CapturedAudio {
        state.withLockUnchecked { state in
            var kept: [AVAudioPCMBuffer] = []
            var total = 0.0
            for buffer in state.buffers.reversed() {
                guard total < seconds else { break }
                kept.append(buffer)
                total += Double(buffer.frameLength) / buffer.format.sampleRate
            }
            return CapturedAudio(buffers: kept.reversed())
        }
    }

    private func receive(_ buffer: AVAudioPCMBuffer) {
        let loudness = Self.loudness(of: buffer)
        let keep = Int(buffer.format.sampleRate * Self.preRollSeconds)
        state.withLockUnchecked { state in
            state.level = loudness > state.level ? loudness : state.level * 0.82 + loudness * 0.18
            if state.capturing { state.buffers.append(buffer) }
            state.preRoll.append(buffer)
            state.preRollFrames += Int(buffer.frameLength)
            while let first = state.preRoll.first, state.preRollFrames - Int(first.frameLength) >= keep {
                state.preRollFrames -= Int(first.frameLength)
                state.preRoll.removeFirst()
            }
        }
    }

    static func loudness(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count { sum += channel[index] * channel[index] }
        let rms = sqrt(sum / Float(count))
        let decibels = 20 * log10(max(Double(rms), 1e-6))
        return min(max((decibels + 55) / 45, 0), 1)
    }
}

enum AudioSessionSetup {
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
    }

    static func deactivate() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
