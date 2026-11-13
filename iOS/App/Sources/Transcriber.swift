import Foundation
import os

struct Transcript: Sendable {
    let raw: String
    let cleaned: String
}

enum Transcriber {
    static let liveWindowSeconds = 15.0
    private static let logger = Logger(subsystem: "com.donovanhiland.navi.ios", category: "Transcriber")

    static func livePass(_ audio: CapturedAudio) async throws -> String {
        let samples = try ParakeetEngine.samples(of: audio.buffers)
        guard samples.count > 8_000 else { return "" }
        return try await ParakeetModel.shared.transcribe(samples)
    }

    static func finish(_ audio: CapturedAudio) async throws -> Transcript {
        let start = ContinuousClock.now
        let engine = await SpeechEngines.best()
        let raw = try await engine.transcribe(audio: audio.stream())
        let heard = ContinuousClock.now
        guard !raw.isEmpty else { return Transcript(raw: "", cleaned: "") }
        let cleaned = await TextCleaner().clean(raw)
        let speech = heard - start
        let cleanup = ContinuousClock.now - heard
        logger.info("Speech \(speech, privacy: .public), cleanup \(cleanup, privacy: .public), audio \(audio.seconds, privacy: .public) s")
        return Transcript(raw: raw, cleaned: cleaned)
    }
}
