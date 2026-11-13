import Testing
@testable import NaviPad

struct CleanupDiffTests {
    @Test func marksFillerAsRemovedAndRewritesAsAdded() {
        let pieces = CleanupDiff.pieces(
            raw: "yeah still on let's do like um ten thirty at the park",
            cleaned: "Yeah, still on. Let's do 10:30 at the park."
        )
        #expect(pieces == [
            .same("Yeah, still on. Let's do"),
            .removed("like um ten thirty"),
            .added("10:30"),
            .same("at the park."),
        ])
    }

    @Test func identicalTextIsOneSamePiece() {
        #expect(CleanupDiff.pieces(raw: "Hi there.", cleaned: "Hi there.") == [.same("Hi there.")])
    }

    @Test func emptySides() {
        #expect(CleanupDiff.pieces(raw: "", cleaned: "") == [])
        #expect(CleanupDiff.pieces(raw: "", cleaned: "Hi.") == [.added("Hi.")])
        #expect(CleanupDiff.pieces(raw: "um", cleaned: "") == [.removed("um")])
    }
}
