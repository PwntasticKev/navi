import Foundation
import Testing
@testable import NaviPad

struct PadStateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func offIsNeverWarm() {
        #expect(!PadState.off.isWarm(at: now))
    }

    @Test func readyStaysWarmUntilItsEnd() {
        let state = PadState.off.ready(until: now.addingTimeInterval(60))
        #expect(state.isWarm(at: now))
        #expect(!state.isWarm(at: now.addingTimeInterval(61)))
        #expect(state.acceptsStart)
    }

    @Test func listeningIsWarmEvenPastTheEnd() {
        let state = PadState.off.listening(at: now, until: now)
        #expect(state.isWarm(at: now.addingTimeInterval(3_600)))
        #expect(!state.acceptsStart)
    }

    @Test func wordsAndLevelOnlyChangeWhileListening() {
        let ready = PadState.off.ready(until: now)
        #expect(ready.heard("hello") == ready)
        #expect(ready.withLevel(0.5) == ready)
        let listening = ready.listening(at: now, until: now).heard("hello").withLevel(4)
        #expect(listening.words == "hello")
        #expect(listening.level == 1)
    }

    @Test func doneKeepsTheWindowAndCarriesTheResult() {
        let id = UUID()
        let until = now.addingTimeInterval(900)
        let state = PadState.off.listening(at: now, until: until).heard("um hi").cleaning()
            .done(raw: "um hi", cleaned: "Hi.", id: id)
        #expect(state.phase == .done)
        #expect(state.cleaned == "Hi.")
        #expect(state.resultID == id)
        #expect(state.readyUntil == until)
        #expect(state.acceptsStart)
    }

    @Test func cancelGoesBackToReady() {
        let until = now.addingTimeInterval(900)
        let state = PadState.off.listening(at: now, until: until).heard("x").cancelled()
        #expect(state.phase == .ready)
        #expect(state.words.isEmpty)
        #expect(state.readyUntil == until)
    }

    @Test func extendNeverShortensTheWindow() {
        let state = PadState.off.ready(until: now.addingTimeInterval(900))
        #expect(state.extended(until: now).readyUntil == now.addingTimeInterval(900))
        #expect(state.extended(until: now.addingTimeInterval(1_000)).readyUntil == now.addingTimeInterval(1_000))
    }

    @Test func storeRoundTripsAndReadsOffWhenEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PadStore(directory: directory)
        #expect(try store.read() == .off)
        let state = PadState.off.listening(at: now, until: now).heard("hello there")
        try store.write(state)
        #expect(try store.read() == state)
    }

    @Test func signalNamesUseThePrefix() {
        #expect(PadSignal.start.name(prefix: "group.x") == "group.x.pad.start")
        #expect(Set(PadSignal.allCases.map { $0.name(prefix: "p") }).count == PadSignal.allCases.count)
    }
}
