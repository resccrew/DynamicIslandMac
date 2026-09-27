import XCTest
@testable import IslandLogic

/// Arithmetic the expanded cards rely on, checked against the tokens.
final class DesignCardsTests: XCTestCase {
    private let defaultCardWidth = 280.0

    func testCardFrameMargins() {
        XCTAssertEqual(DS.Space.cardSide, 27)
        XCTAssertEqual(DS.Space.cardTopBelowNotch, 6)
        XCTAssertEqual(DS.Space.cardBottom, 12)
    }

    func testTransportRowFitsBesideArtwork() {
        let textColumn = defaultCardWidth - 2 * DS.Space.cardSide - DS.Card.lead - DS.Space.leadGap
        let row = 4 * DS.Button.secondaryHitFrame + DS.Button.primary
        XCTAssertLessThanOrEqual(row, textColumn)
    }

    func testAgendaRowTextAlignsWithHeaderText() {
        // Header: icon column + lead gap; rows use the same two tokens.
        XCTAssertEqual(DS.Card.headerIconColumn + DS.Space.leadGap, 42)
    }

    func testEveryControlMeetsMinimumHitArea() {
        XCTAssertGreaterThanOrEqual(DS.Button.secondaryHitFrame, DS.Button.minHitArea)
        XCTAssertGreaterThanOrEqual(DS.Button.primary, DS.Button.minHitArea)
    }

    func testAgendaFitsThePanel() {
        // Cutout 38 + top gap + header + sectionGap, then events (3 rows of
        // xl height, rowGap between), sectionGap, the "Напоминания" caption
        // (≈13pt) + rowGap + 3 rows, and the bottom margin.
        let row = DS.Space.xl
        let events = 3 * row + 2 * DS.Space.rowGap
        let caption = 13.0
        let reminders = caption + DS.Space.rowGap + 3 * row + 2 * DS.Space.rowGap
        let total = 38 + DS.Space.cardTopBelowNotch + DS.Button.primary + DS.Space.sectionGap
            + events + DS.Space.sectionGap + reminders + DS.Space.cardBottom
        XCTAssertLessThanOrEqual(total, DS.Card.maxExpandedHeight)
    }

    func testGlanceBodyHoldsOnePrimaryRow() {
        let body = DS.Space.cardTopBelowNotch + DS.Button.primary + DS.Space.cardBottom
        XCTAssertEqual(body, 50)
    }
}

final class GlanceWidthTests: XCTestCase {
    private let glanceWidth = 306.0
    private let minimumTextWidth = 125.0

    func testTextKeepsRoomBesideTheRoundActionButton() {
        let beforeButton = glanceWidth - 2 * DS.Space.cardSide - DS.Card.headerIconColumn - DS.Space.leadGap
        let room = beforeButton - DS.Space.leadGap - DS.Button.primary
        XCTAssertGreaterThanOrEqual(room, minimumTextWidth)
    }

    func testActionSymbols() {
        XCTAssertEqual(GlanceActionSymbol.name(for: "Подключиться"), "video.fill")
        XCTAssertEqual(GlanceActionSymbol.name(for: "Выполнено"), "checkmark")
        XCTAssertEqual(GlanceActionSymbol.name(for: "Открыть Часы"), "clock")
        XCTAssertEqual(GlanceActionSymbol.name(for: "Открыть"), "arrow.up.right")
        XCTAssertEqual(GlanceActionSymbol.name(for: "что-то новое"), "arrow.up.right")
    }
}

final class MotionPeriodTests: XCTestCase {
    func testIndeterminatePeriodIsWholeMicroBeats() {
        let beats = DS.Motion.indeterminatePeriod / DS.Motion.microDuration
        XCTAssertEqual(beats, beats.rounded(), accuracy: 1e-9)
    }
}
