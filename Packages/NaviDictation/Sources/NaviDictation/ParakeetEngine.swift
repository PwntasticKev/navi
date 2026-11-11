// Adapted from Hex, ios/HEXMobile/ParakeetTranscriber.swift
// https://github.com/anomalyco/hex at 53164934130a (2026-11-07)
//
// MIT License. Copyright (c) 2026 Christopher Langton.
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
// associated documentation files (the "Software"), to deal in the Software without restriction,
// including without limitation the rights to use, copy, modify, merge, publish, distribute,
// sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions: The above copyright notice and this
// permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.

@preconcurrency import AVFoundation
import FluidAudio
import Foundation
import os

/// Parakeet TDT v3 speech-to-text on the Neural Engine, through FluidAudio. Hex's default engine.
///
/// The model (about 0.5 GB) downloads once from Hugging Face, then everything runs on this Mac.
/// Until it is ready, the app uses Apple's speech engine.
actor ParakeetModel {
    static let shared = ParakeetModel()
    static let version: AsrModelVersion = .v3

    private static let logger = Logger(subsystem: "com.donovanhiland.navi", category: "Parakeet")
    private var manager: AsrManager?
    private var loading: Task<AsrManager, any Error>?
    /// One transcription at a time: `AsrManager` awaits inside a run, so calls could interleave.
    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// True when the model files are on disk. Loading them still takes a moment.
    nonisolated static var isDownloaded: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: version), version: version)
    }

    var isLoaded: Bool { manager != nil }

    /// Downloads (first time only) and loads the model. Safe to call many times.
    @discardableResult
    func prepare() async throws -> AsrManager {
        if let manager { return manager }
        if let loading { return try await loading.value }
        let task = Task { () throws -> AsrManager in
            let models = try await AsrModels.downloadAndLoad(version: Self.version)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        loading = task
        do {
            let manager = try await task.value
            self.manager = manager
            loading = nil
            Self.logger.info("Parakeet is ready")
            return manager
        } catch {
            loading = nil
            Self.logger.error("Parakeet could not load: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Transcribes 16 kHz mono samples. Waits for a run in progress to finish first.
    func transcribe(_ samples: [Float]) async throws -> String {
        let manager = try await prepare()
        await takeTurn()
        defer { endTurn() }
        return try await run(samples, on: manager)
    }

    /// A live text preview: skipped (nil) when the model is not loaded or is busy, so a preview never
    /// delays the final text.
    func preview(_ samples: [Float]) async -> String? {
        guard let manager, !isBusy else { return nil }
        isBusy = true
        defer { endTurn() }
        return try? await run(samples, on: manager)
    }

    private func run(_ samples: [Float], on manager: AsrManager) async throws -> String {
        let layers = await manager.decoderLayerCount
        var state = TdtDecoderState.make(decoderLayers: layers)
        let result = try await manager.transcribe(samples, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func takeTurn() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Hands the turn to the next caller in line, or frees it.
    private func endTurn() {
        if waiting.isEmpty {
            isBusy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}

/// The mic buffers of one dictation, shared between the reader and the live text preview.
private final class BufferStore: @unchecked Sendable {
    private let buffers = OSAllocatedUnfairLock(uncheckedState: [AVAudioPCMBuffer]())

    func append(_ buffer: AVAudioPCMBuffer) {
        buffers.withLock { $0.append(buffer) }
    }

    var all: [AVAudioPCMBuffer] { buffers.withLock { $0 } }
}

/// A `SpeechEngine` that collects the whole utterance, then runs Parakeet once, like Hex.
///
/// For live text, Parakeet also reads the newest few seconds again every `LiveText.previewInterval`
/// while the user talks. The text that gets typed still comes from the one pass over everything.
struct ParakeetEngine: SpeechEngine {
    func transcribe(audio: AsyncStream<AudioChunk>, onPartial: PartialHandler?) async throws -> String {
        let store = BufferStore()
        let preview = onPartial.map { onPartial in
            Task.detached(priority: .userInitiated) { await Self.runPreviews(of: store, onPartial: onPartial) }
        }
        for await chunk in audio { store.append(chunk.buffer) }
        preview?.cancel()
        try Task.checkCancellation()
        guard let joined = Self.join(store.all) else { return "" }
        let samples = try AudioConverter().resampleBuffer(joined)
        // Less than a tenth of a second is a tap, not speech.
        guard samples.count > 1600 else { return "" }
        return try await ParakeetModel.shared.transcribe(samples)
    }

    /// Reads the newest audio again and again until cancelled, and reports what it heard.
    private static func runPreviews(of store: BufferStore, onPartial: PartialHandler) async {
        let converter = AudioConverter()
        var lastCount = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: LiveText.previewInterval)
            let buffers = store.all
            guard buffers.count != lastCount, let format = buffers.first?.format else { continue }
            lastCount = buffers.count
            let (start, clipped) = LiveText.tailStart(
                frameCounts: buffers.map { Int($0.frameLength) },
                sampleRate: format.sampleRate,
                window: LiveText.previewWindow
            )
            guard let joined = join(Array(buffers[start...])),
                  let samples = try? converter.resampleBuffer(joined),
                  Double(samples.count) >= LiveText.minimumAudio * 16000,
                  let text = await ParakeetModel.shared.preview(samples),
                  !Task.isCancelled
            else { continue }
            onPartial(LiveText.trimmed(text, clipped: clipped))
        }
    }

    /// Joins buffers of one format into one buffer, so resampling has no seams.
    static func join(_ buffers: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        guard let first = buffers.first else { return nil }
        let format = first.format
        let total = buffers.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        guard total > 0, let joined = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total) else { return nil }
        var offset = 0
        for buffer in buffers where buffer.format == format {
            let frames = Int(buffer.frameLength)
            let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
            let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let target = UnsafeMutableAudioBufferListPointer(joined.mutableAudioBufferList)
            for index in 0 ..< min(source.count, target.count) {
                guard let from = source[index].mData, let to = target[index].mData else { continue }
                // `mBytesPerFrame` is per buffer: one channel when non-interleaved, all channels when interleaved.
                memcpy(to.advanced(by: offset * bytesPerFrame), from, frames * bytesPerFrame)
            }
            offset += frames
        }
        joined.frameLength = AVAudioFrameCount(offset)
        return joined
    }
}
