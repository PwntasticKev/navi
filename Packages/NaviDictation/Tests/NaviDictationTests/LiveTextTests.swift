import Testing
@testable import NaviDictation

@Suite("LiveText")
struct LiveTextTests {
    @Test("short audio is read whole and not clipped")
    func shortAudio() {
        let start = LiveText.tailStart(frameCounts: [100, 100, 100], sampleRate: 100, window: 10)
        #expect(start.index == 0)
        #expect(!start.clipped)
    }

    @Test("long audio keeps only the newest window")
    func longAudio() {
        let start = LiveText.tailStart(frameCounts: Array(repeating: 100, count: 20), sampleRate: 100, window: 5)
        #expect(start.index == 15)
        #expect(start.clipped)
    }

    @Test("audio exactly one window long is not clipped")
    func exactWindow() {
        let start = LiveText.tailStart(frameCounts: [250, 250], sampleRate: 100, window: 5)
        #expect(start.index == 0)
        #expect(!start.clipped)
    }

    @Test("no buffers or no sample rate reads from the start")
    func empty() {
        #expect(LiveText.tailStart(frameCounts: [], sampleRate: 100, window: 5).index == 0)
        #expect(LiveText.tailStart(frameCounts: [100], sampleRate: 0, window: 5).index == 0)
    }

    @Test("clipped text drops the first word, which may be cut")
    func trimmed() {
        #expect(LiveText.trimmed("lo there friend", clipped: true) == "there friend")
        #expect(LiveText.trimmed(" hello there ", clipped: false) == "hello there")
        #expect(LiveText.trimmed("hello", clipped: true) == "")
    }

    @Test("finished segments come before the current guess")
    func combine() {
        #expect(LiveText.combine(finished: ["Hello there.", " How are"], volatile: "you doing ") == "Hello there. How are you doing")
        #expect(LiveText.combine(finished: [], volatile: "") == "")
        #expect(LiveText.combine(finished: ["One."], volatile: "") == "One.")
    }
}
