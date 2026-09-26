import XCTest
@testable import IslandLogic

final class IslandVisibilityTests: XCTestCase {
    func testPausedWhileOpenStays() {
        // Expanded (click-opened) and hover (peek) both count as open.
        XCTAssertTrue(IslandVisibility.showsMedia(isPlaying: false, hasTrack: true, isOpen: true, hideWhenPaused: true))
    }

    func testPausedAndClosedHides() {
        XCTAssertFalse(IslandVisibility.showsMedia(isPlaying: false, hasTrack: true, isOpen: false, hideWhenPaused: true))
    }

    func testPlayingShows() {
        XCTAssertTrue(IslandVisibility.showsMedia(isPlaying: true, hasTrack: true, isOpen: false, hideWhenPaused: true))
    }

    func testPausedHoveredRowIsRenderedAndOpaque() {
        let media = IslandVisibility.showsMedia(isPlaying: false, hasTrack: true, isOpen: true, hideWhenPaused: true)
        XCTAssertTrue(IslandVisibility.rendersCollapsedContent(isIslandVisible: false, showsMedia: media))
        XCTAssertEqual(IslandVisibility.opacity(isHidden: false), 1)
    }

    func testPausedClosedRowIsNotRenderedAndFades() {
        let media = IslandVisibility.showsMedia(isPlaying: false, hasTrack: true, isOpen: false, hideWhenPaused: true)
        XCTAssertFalse(IslandVisibility.rendersCollapsedContent(isIslandVisible: false, showsMedia: media))
        XCTAssertEqual(IslandVisibility.opacity(isHidden: true), 0)
    }

    func testNoTrackNeverShowsMedia() {
        XCTAssertFalse(IslandVisibility.showsMedia(isPlaying: true, hasTrack: false, isOpen: true, hideWhenPaused: false))
    }
}

final class PausedIslandStaysTests: XCTestCase {
    func testPausedWithSourcePresentStaysVisibleByDefault() {
        XCTAssertTrue(IslandVisibility.mediaVisible(isPlaying: false, hasTrack: true, hideWhenPaused: false))
        XCTAssertTrue(IslandVisibility.showsMedia(isPlaying: false, hasTrack: true, isOpen: false, hideWhenPaused: false))
        XCTAssertTrue(IslandVisibility.rendersCollapsedContent(isIslandVisible: true, showsMedia: true))
    }

    func testHideWhenPausedRestoresOldRules() {
        XCTAssertFalse(IslandVisibility.mediaVisible(isPlaying: false, hasTrack: true, hideWhenPaused: true))
        XCTAssertFalse(IslandVisibility.showsMedia(isPlaying: false, hasTrack: true, isOpen: false, hideWhenPaused: true))
        XCTAssertTrue(IslandVisibility.showsMedia(isPlaying: false, hasTrack: true, isOpen: true, hideWhenPaused: true))
    }

    func testSourceGoneHides() {
        for hide in [false, true] {
            XCTAssertFalse(IslandVisibility.mediaVisible(isPlaying: false, hasTrack: false, hideWhenPaused: hide))
            XCTAssertFalse(IslandVisibility.showsMedia(isPlaying: false, hasTrack: false, isOpen: false, hideWhenPaused: hide))
        }
    }

    func testPlayingIsVisible() {
        for hide in [false, true] {
            XCTAssertTrue(IslandVisibility.mediaVisible(isPlaying: true, hasTrack: true, hideWhenPaused: hide))
        }
    }
}

final class NowPlayingArbiterTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testNewPlayingSourceBeatsPausedOld() {
        var arbiter = NowPlayingArbiter()
        arbiter.report(id: "chrome", isPlaying: false, at: t0)
        XCTAssertEqual(arbiter.report(id: "spotify", isPlaying: true, at: t0 + 1), "spotify")
    }

    func testMostRecentlyStartedPlayingWins() {
        var arbiter = NowPlayingArbiter()
        arbiter.report(id: "chrome", isPlaying: true, at: t0)
        XCTAssertEqual(arbiter.report(id: "spotify", isPlaying: true, at: t0 + 1), "spotify")
        // Chrome keeps reporting while playing, but it started earlier.
        XCTAssertEqual(arbiter.report(id: "chrome", isPlaying: true, at: t0 + 2), "spotify")
    }

    func testPausedOldUpdateDoesNotSteal() {
        var arbiter = NowPlayingArbiter()
        arbiter.report(id: "chrome", isPlaying: false, at: t0)
        arbiter.report(id: "spotify", isPlaying: true, at: t0 + 1)
        XCTAssertEqual(arbiter.report(id: "chrome", isPlaying: false, at: t0 + 2), "spotify")
    }

    func testStalePlayingSourceGivesWayAfterGrace() {
        var arbiter = NowPlayingArbiter(staleAfter: 3)
        arbiter.report(id: "spotify", isPlaying: true, at: t0)
        arbiter.report(id: "chrome", isPlaying: false, at: t0 + 1)
        XCTAssertEqual(arbiter.winner(at: t0 + 2), "spotify")
        XCTAssertEqual(arbiter.winner(at: t0 + 10), "chrome")
    }

    func testPausingTheCurrentSourceKeepsIt() {
        var arbiter = NowPlayingArbiter()
        arbiter.report(id: "spotify", isPlaying: true, at: t0)
        XCTAssertEqual(arbiter.report(id: "spotify", isPlaying: false, at: t0 + 1), "spotify")
    }

    func testResumeCountsAsNewStart() {
        var arbiter = NowPlayingArbiter()
        arbiter.report(id: "chrome", isPlaying: true, at: t0)
        arbiter.report(id: "spotify", isPlaying: true, at: t0 + 1)
        arbiter.report(id: "chrome", isPlaying: false, at: t0 + 2)
        XCTAssertEqual(arbiter.report(id: "chrome", isPlaying: true, at: t0 + 3), "chrome")
    }

    func testEmptyAndReset() {
        var arbiter = NowPlayingArbiter()
        XCTAssertNil(arbiter.winner(at: t0))
        arbiter.report(id: "spotify", isPlaying: true, at: t0)
        arbiter.reset()
        XCTAssertNil(arbiter.winner(at: t0))
    }
}
