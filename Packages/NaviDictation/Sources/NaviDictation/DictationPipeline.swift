import AVFoundation
import Foundation

public enum DictationPipeline {
    public enum Cleanup: String, CaseIterable, Sendable {
        case none
        case rules
        case apple
    }

    public static func clean(_ raw: String, with cleanup: Cleanup) async -> String {
        switch cleanup {
        case .none: raw
        case .rules: TextCleanup.clean(raw)
        case .apple: await TextCleaner().clean(raw)
        }
    }

    public static var appleModelIsReady: Bool { TextCleaner.modelIsAvailable }

    public enum Speech: String, CaseIterable, Sendable {
        case best
        case apple
        case parakeet
    }

    public static func prepareParakeet() async throws {
        try await ParakeetModel.shared.prepare()
    }

    public static func transcribe(file url: URL, with speech: Speech = .best) async throws -> String {
        let file = try AVAudioFile(forReading: url)
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        let format = file.processingFormat
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { break }
            try file.read(into: buffer)
            if buffer.frameLength == 0 { break }
            continuation.yield(AudioChunk(buffer: buffer))
        }
        continuation.finish()
        let engine: any SpeechEngine = switch speech {
        case .best: await SpeechEngines.best()
        case .apple: await SpeechEngines.apple()
        case .parakeet: ParakeetEngine()
        }
        return try await engine.transcribe(audio: stream)
    }
}
