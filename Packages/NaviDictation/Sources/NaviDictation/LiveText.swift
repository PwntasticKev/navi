import Foundation

enum LiveText {
    static let previewWindow: TimeInterval = 10
    static let previewInterval: Duration = .milliseconds(600)
    static let minimumAudio: TimeInterval = 0.5

    static func tailStart(frameCounts: [Int], sampleRate: Double, window: TimeInterval) -> (index: Int, clipped: Bool) {
        guard sampleRate > 0 else { return (0, false) }
        let limit = Int(window * sampleRate)
        var total = 0
        for index in frameCounts.indices.reversed() {
            total += frameCounts[index]
            if total >= limit { return (index, index > 0) }
        }
        return (0, false)
    }

    static func trimmed(_ text: String, clipped: Bool) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clipped else { return text }
        guard let space = text.firstIndex(where: \.isWhitespace) else { return "" }
        return text[space...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func combine(finished: [String], volatile: String) -> String {
        (finished + [volatile])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
