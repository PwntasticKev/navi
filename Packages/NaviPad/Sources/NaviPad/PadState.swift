import Foundation

public struct PadState: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case off
        case ready
        case listening
        case cleaning
        case done
        case failed
    }

    public static let readyLength: TimeInterval = 15 * 60
    public static let off = PadState()

    public private(set) var phase: Phase
    public private(set) var words: String
    public private(set) var cleaned: String?
    public private(set) var resultID: UUID?
    public private(set) var startedAt: Date?
    public private(set) var readyUntil: Date?
    public private(set) var level: Double
    public private(set) var message: String?

    public init(
        phase: Phase = .off, words: String = "", cleaned: String? = nil, resultID: UUID? = nil,
        startedAt: Date? = nil, readyUntil: Date? = nil, level: Double = 0, message: String? = nil
    ) {
        self.phase = phase
        self.words = words
        self.cleaned = cleaned
        self.resultID = resultID
        self.startedAt = startedAt
        self.readyUntil = readyUntil
        self.level = level
        self.message = message
    }

    public var acceptsStart: Bool {
        phase == .ready || phase == .done || phase == .failed
    }

    public func isWarm(at now: Date) -> Bool {
        switch phase {
        case .off: false
        case .listening, .cleaning: true
        case .ready, .done, .failed: (readyUntil ?? .distantPast) > now
        }
    }

    public func ready(until: Date) -> PadState {
        PadState(phase: .ready, readyUntil: until)
    }

    public func extended(until: Date) -> PadState {
        var next = self
        next.readyUntil = max(until, readyUntil ?? until)
        return next
    }

    public func listening(at start: Date, until: Date) -> PadState {
        PadState(phase: .listening, startedAt: start, readyUntil: until)
    }

    public func heard(_ text: String) -> PadState {
        guard phase == .listening else { return self }
        var next = self
        next.words = text
        return next
    }

    public func withLevel(_ value: Double) -> PadState {
        guard phase == .listening else { return self }
        var next = self
        next.level = min(max(value, 0), 1)
        return next
    }

    public func cleaning() -> PadState {
        guard phase == .listening else { return self }
        var next = self
        next.phase = .cleaning
        next.level = 0
        return next
    }

    public func done(raw: String, cleaned text: String, id: UUID) -> PadState {
        PadState(
            phase: .done, words: raw, cleaned: text, resultID: id,
            startedAt: startedAt, readyUntil: readyUntil
        )
    }

    public func failed(_ reason: String) -> PadState {
        PadState(phase: .failed, words: words, startedAt: startedAt, readyUntil: readyUntil, message: reason)
    }

    public func cancelled() -> PadState {
        PadState(phase: .ready, readyUntil: readyUntil)
    }

    public func turnedOff(message reason: String? = nil) -> PadState {
        PadState(phase: .off, message: reason)
    }
}
