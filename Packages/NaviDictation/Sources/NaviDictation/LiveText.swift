import Foundation

/// The words the pill shows while the user talks. Like Hex's live text, it is only shown, never
/// pasted or kept: the final text still comes from one full pass over the whole recording.
enum LiveText {
    /// Seconds of the newest audio that Parakeet reads again for each preview. The pill shows only
    /// the newest words, so a long dictation costs no more to preview than a short one.
    static let previewWindow: TimeInterval = 10
    /// Time between two Parakeet previews.
    static let previewInterval: Duration = .milliseconds(600)
    /// Less audio than this (in seconds) gives no preview yet.
    static let minimumAudio: TimeInterval = 0.5

    /// The index of the first buffer to read so the preview covers at most `window` seconds, and
    /// whether older audio was left out (then the first word heard may be cut in half).
    static func tailStart(frameCounts: [Int], sampleRate: Double, window: TimeInterval) -> (index: Int, clipped: Bool) {
        guard sampleRate > 0 else { return (0, false) }
        let limit = Int(window * sampleRate)
        var total = 0
        for index in frameCounts.indices.reversed() {
            total += frameCounts[index]
            // This buffer fills the window. Older buffers are left out.
            if total >= limit { return (index, index > 0) }
        }
        return (0, false)
    }

    /// Text from audio that starts mid-speech: drops the first word, which may be cut in half.
    static func trimmed(_ text: String, clipped: Bool) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clipped else { return text }
        guard let space = text.firstIndex(where: \.isWhitespace) else { return "" }
        return text[space...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Finished segments, then the engine's current guess for the words after them.
    static func combine(finished: [String], volatile: String) -> String {
        (finished + [volatile])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
