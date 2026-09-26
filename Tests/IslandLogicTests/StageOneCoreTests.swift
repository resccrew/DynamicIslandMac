import XCTest
@testable import IslandLogic

final class TimerLogParserTests: XCTestCase {
    private let id = "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"

    private func entry(_ state: String, title: String = "", duration: Double = 300, fired: String = "(null)") -> String {
        "TimerID: \(id), Title: \(title), state:\(state), duration:\(duration), firedDate: \(fired), sound: x"
    }

    func testParsesEntry() {
        let entries = TimerLogParser.parseEntries(Substring(entry("Running", title: "Tea")))
        XCTAssertEqual(entries, [.init(id: id, title: "Tea", state: "Running", duration: 300, fired: false)])
    }

    func testSiriDefaultTitleIsBlankAndFiredDateDetected() {
        let entries = TimerLogParser.parseEntries(Substring(entry("Stopped", title: "CURRENT_TIMER", fired: "2026-09-23 11:05:35")))
        XCTAssertEqual(entries.first?.title, "")
        XCTAssertEqual(entries.first?.fired, true)
    }

    func testGarbageYieldsNoEntries() {
        XCTAssertTrue(TimerLogParser.parseEntries("TimerID: nope, state:Running").isEmpty)
    }

    func testParsesTriggerWithNarrowSpace() throws {
        let message = "\(id) has next trigger at date: \"Wednesday, September 23, 2026 at 11:05:35\u{202F}AM Central European Summer Time\""
        let trigger = try XCTUnwrap(TimerLogParser.parseTrigger(message))
        XCTAssertEqual(trigger.id, id)
        XCTAssertEqual(trigger.date, TimerLogParser.parseTimestamp("2026-09-23 11:05:35.000000+0200"))
    }

    func testUnknownZoneFallsBackToLocalTime() {
        let date = TimerLogParser.parseTriggerDate("Wednesday, September 23, 2026 at 11:05:35 AM Some Unknown Zone")
        var components = DateComponents(year: 2026, month: 9, day: 23, hour: 11, minute: 5, second: 35)
        components.timeZone = .current
        XCTAssertEqual(date, Calendar(identifier: .gregorian).date(from: components))
    }

    func testBadTriggerDateIsNil() {
        XCTAssertNil(TimerLogParser.parseTriggerDate("sometime soon"))
        XCTAssertNil(TimerLogParser.parseTimestamp("yesterday"))
    }
}

final class TimerLogStoreTests: XCTestCase {
    private let id = "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func change(_ state: String, fired: String = "(null)") -> String {
        "store changed fromTimers: … toTimers: TimerID: \(id), Title: Tea, state:\(state), duration:300.0, firedDate: \(fired), x"
    }

    func testRunningPausedRunning() throws {
        var store = TimerLogStore()
        XCTAssertTrue(store.handle(message: change("Running"), at: t0).changed)
        XCTAssertEqual(store.timers[id]?.fireDate, t0.addingTimeInterval(300))

        let paused = store.handle(message: change("Paused"), at: t0.addingTimeInterval(100))
        XCTAssertTrue(paused.changed)
        let timer = try XCTUnwrap(store.timers[id])
        XCTAssertTrue(timer.isPaused)
        XCTAssertEqual(timer.remaining(), 200, accuracy: 0.001)

        // Resumed 50s later: the 200s left carry over.
        _ = store.handle(message: change("Running"), at: t0.addingTimeInterval(150))
        XCTAssertEqual(store.timers[id]?.fireDate, t0.addingTimeInterval(350))
    }

    func testTriggerUpdatesRunningTimer() {
        var store = TimerLogStore()
        _ = store.handle(message: change("Running"), at: t0)
        let trigger = "\(id) has next trigger at date: \"Wednesday, September 23, 2026 at 11:05:35 AM Central European Summer Time\""
        XCTAssertTrue(store.handle(message: trigger, at: t0).changed)
        XCTAssertEqual(store.timers[id]?.fireDate, TimerLogParser.parseTimestamp("2026-09-23 11:05:35.000000+0200"))
    }

    func testFiredVersusCancelled() {
        var store = TimerLogStore()
        _ = store.handle(message: change("Running"), at: t0)
        let fired = store.handle(message: change("Stopped", fired: "2026-09-23 11:05:35"), at: t0.addingTimeInterval(300))
        XCTAssertEqual(fired.fired, ["Tea"])
        XCTAssertNil(store.timers[id])

        _ = store.handle(message: change("Running"), at: t0)
        let cancelled = store.handle(message: change("Stopped"), at: t0.addingTimeInterval(10))
        XCTAssertEqual(cancelled.fired, [])
        XCTAssertTrue(cancelled.changed)
        XCTAssertNil(store.timers[id])
    }

    func testStopOfUnknownTimerIsIgnored() {
        var store = TimerLogStore()
        XCTAssertEqual(store.handle(message: change("Stopped", fired: "x"), at: t0), .init())
    }

    func testUnrelatedLinesIgnoredAndExpiredDropped() {
        var store = TimerLogStore()
        XCTAssertFalse(store.handle(message: "scheduler: TimerID: \(id), Title: Tea, state:Running, duration:300.0, firedDate: (null), x", at: t0).changed)
        _ = store.handle(message: change("Running"), at: t0)
        store.dropExpired(now: t0.addingTimeInterval(301))
        XCTAssertTrue(store.timers.isEmpty)
    }
}

final class TimerRestartBackoffTests: XCTestCase {
    func testBacksOffThenGivesUpAndResetsOnSuccess() {
        var backoff = TimerRestartBackoff(base: 2, maxDelay: 10, maxFailures: 5)
        XCTAssertEqual(backoff.failed(), 2)
        XCTAssertEqual(backoff.failed(), 4)
        XCTAssertEqual(backoff.failed(), 8)
        XCTAssertEqual(backoff.failed(), 10)
        XCTAssertNil(backoff.failed())
        backoff.succeeded()
        XCTAssertEqual(backoff.failed(), 2)
    }
}

final class NowPlayingPayloadTests: XCTestCase {
    private func line(_ json: String) -> Data { Data(json.utf8) }

    func testEmptyPayloadMeansNothingPlaying() throws {
        let parsed = try XCTUnwrap(NowPlayingPayload.parse(line(#"{"type":"data","payload":{}}"#)))
        XCTAssertNil(parsed.value)
    }

    func testBrokenLineIsNil() {
        XCTAssertNil(NowPlayingPayload.parse(line("{not json")))
        XCTAssertNil(NowPlayingPayload.parse(line(#"{"type":"error","payload":{"title":"x"}}"#)))
    }

    func testParsesFieldsAndDropsInvalidDuration() throws {
        let json = #"{"type":"data","payload":{"title":"Song","artist":"A","playing":true,"elapsedTime":12.5,"duration":0,"bundleIdentifier":"com.spotify.client","timestamp":"2026-09-23T09:00:00Z"}}"#
        let info = try XCTUnwrap(NowPlayingPayload.parse(line(json))?.value)
        XCTAssertEqual(info.title, "Song")
        XCTAssertTrue(info.isPlaying)
        XCTAssertEqual(info.elapsed, 12.5)
        XCTAssertNil(info.duration)
        XCTAssertEqual(info.bundleID, "com.spotify.client")
        XCTAssertEqual(info.timestamp, ISO8601DateFormatter().date(from: "2026-09-23T09:00:00Z"))
    }

    func testFiniteDurationKept() throws {
        let info = try XCTUnwrap(NowPlayingPayload.parse(line(#"{"type":"data","payload":{"title":"x","duration":200.0}}"#))?.value)
        XCTAssertEqual(info.duration, 200)
    }

    private func info(title: String = "", artist: String = "", album: String = "", playing: Bool = false) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: artist, album: album, isPlaying: playing, elapsed: 0,
                       timestamp: Date(), duration: nil, bundleID: nil, artworkData: nil)
    }

    func testPausedBareEntryMeansSourceGone() {
        XCTAssertTrue(info().isSourceGone)
        XCTAssertFalse(info(playing: true).isSourceGone)
        XCTAssertFalse(info(title: "Paused song").isSourceGone)
        XCTAssertFalse(info(album: "Album").isSourceGone)
    }

    func testBrowserNameIsNeverTheArtist() {
        let labels = NowPlayingPayload.labels(for: info(title: "Video"), appName: "Google Chrome")
        XCTAssertEqual(labels.title, "Video")
        XCTAssertEqual(labels.artist, "")
    }

    func testAppNameStandsInForMissingTitle() {
        let labels = NowPlayingPayload.labels(for: info(playing: true), appName: "Safari")
        XCTAssertEqual(labels.title, "Safari")
        XCTAssertEqual(labels.artist, "")
    }

    func testArtistThenAlbumAsSubtitle() {
        XCTAssertEqual(NowPlayingPayload.labels(for: info(title: "S", artist: "A", album: "B"), appName: "X").artist, "A")
        XCTAssertEqual(NowPlayingPayload.labels(for: info(title: "S", album: "B"), appName: "X").artist, "B")
    }
}
