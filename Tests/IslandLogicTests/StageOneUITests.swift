import XCTest
@testable import IslandLogic

final class FormatTimeTests: XCTestCase {
    func testUnderAnHourIsMinutesSeconds() {
        XCTAssertEqual(FormatTime.clock(0), "0:00")
        XCTAssertEqual(FormatTime.clock(65), "1:05")
        XCTAssertEqual(FormatTime.clock(3599.9), "59:59")
    }

    func testFromAnHourIsHoursMinutesSeconds() {
        XCTAssertEqual(FormatTime.clock(3600), "1:00:00")
        XCTAssertEqual(FormatTime.clock(3725), "1:02:05")
        XCTAssertEqual(FormatTime.clock(36_000 + 61), "10:01:01")
    }

    func testInvalidInputReadsZero() {
        XCTAssertEqual(FormatTime.clock(-5), "0:00")
        XCTAssertEqual(FormatTime.clock(.nan), "0:00")
        XCTAssertEqual(FormatTime.clock(.infinity), "0:00")
    }

    func testPlaybackAtStartShowsWholeLength() {
        let text = FormatTime.playback(position: 0, duration: 200)
        XCTAssertEqual(text.elapsed, "0:00")
        XCTAssertEqual(text.remaining, "3:20")
    }

    func testPlaybackPartsAlwaysSumToLength() {
        for position in stride(from: 0.0, through: 200, by: 0.37) {
            let text = FormatTime.playback(position: position, duration: 200)
            XCTAssertEqual(seconds(text.elapsed) + seconds(text.remaining), 200, "at \(position)")
        }
    }

    func testPlaybackClampsPastEnd() {
        let text = FormatTime.playback(position: 250, duration: 200)
        XCTAssertEqual(text.elapsed, "3:20")
        XCTAssertEqual(text.remaining, "0:00")
    }

    func testPlaybackFractionalDurationRounds() {
        XCTAssertEqual(FormatTime.playback(position: 0, duration: 199.6).remaining, "3:20")
    }

    private func seconds(_ text: String) -> Int {
        text.split(separator: ":").reduce(0) { $0 * 60 + Int($1)! }
    }
}

final class LyricsParserTests: XCTestCase {
    func testParsesSimpleLines() {
        let lines = LyricsParser.parse("[00:01.50] Hello\n[01:02.00]World")
        XCTAssertEqual(lines, [LyricLine(time: 1.5, text: "Hello"), LyricLine(time: 62, text: "World")])
    }

    func testRepeatedStampsOnOneLineExpandAndSort() {
        let lines = LyricsParser.parse("[00:10.00][00:30.00] Chorus\n[00:20.00] Verse")
        XCTAssertEqual(lines.map(\.time), [10, 20, 30])
        XCTAssertEqual(lines.map(\.text), ["Chorus", "Verse", "Chorus"])
    }

    func testEmptyTextLinesAreKeptAsGaps() {
        let lines = LyricsParser.parse("[00:05.00] One\n[00:09.00]\n\n[00:12.00] Two")
        XCTAssertEqual(lines.map(\.text), ["One", "", "Two"])
    }

    func testBrokenAndMetadataLinesAreSkipped() {
        let lrc = "[ar:Artist]\n[ti:Title]\nno stamp here\n[aa:bb] junk\n[00:03.00 unclosed\n[00:04.00] Ok"
        XCTAssertEqual(LyricsParser.parse(lrc), [LyricLine(time: 4, text: "Ok")])
    }

    func testWindowsLineEndings() {
        XCTAssertEqual(LyricsParser.parse("[00:01.00] A\r\n[00:02.00] B\r\n").map(\.text), ["A", "B"])
    }

    func testEmptyInput() {
        XCTAssertEqual(LyricsParser.parse(""), [])
    }

    func testClosestDurationWins() {
        XCTAssertEqual(LyricsParser.closestDurationIndex([180, 204, 250], to: 200), 1)
    }

    func testMissingDurationLosesToKnownOne() {
        XCTAssertEqual(LyricsParser.closestDurationIndex([nil, 190], to: 200), 1)
        XCTAssertEqual(LyricsParser.closestDurationIndex([nil], to: 200), 0)
    }

    func testNoCandidates() {
        XCTAssertNil(LyricsParser.closestDurationIndex([], to: 200))
    }
}

final class AgendaFormatTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testNotStartedShowsStart() {
        let label = AgendaFormat.collapsedLabel(start: start, end: start + 1800, now: start - 60)
        XCTAssertEqual(label, .startsAt(start))
    }

    func testUnderWayShowsMinutesLeftRoundedUp() {
        let label = AgendaFormat.collapsedLabel(start: start, end: start + 1800, now: start + 30)
        XCTAssertEqual(label, .minutesLeft(30))
    }

    func testLastSecondsStillShowOneMinute() {
        let label = AgendaFormat.collapsedLabel(start: start, end: start + 1800, now: start + 1799)
        XCTAssertEqual(label, .minutesLeft(1))
    }

    func testLongEventShowsEndTime() {
        let end = start + 3 * 3600
        XCTAssertEqual(AgendaFormat.collapsedLabel(start: start, end: end, now: start + 60), .endsAt(end))
    }

    func testDueReminderStaysListedDuringMeeting() {
        let listed = AgendaFormat.listedReminders(["overdue", "later"], nowReminder: "overdue", hasNowEvent: true)
        XCTAssertEqual(listed, ["overdue", "later"])
    }

    func testDueReminderMovesToHeaderWithoutMeeting() {
        let listed = AgendaFormat.listedReminders(["overdue", "later"], nowReminder: "overdue", hasNowEvent: false)
        XCTAssertEqual(listed, ["later"])
    }

    func testNoDueReminderKeepsAll() {
        XCTAssertEqual(AgendaFormat.listedReminders(["a", "b"], nowReminder: nil, hasNowEvent: false), ["a", "b"])
    }
}
