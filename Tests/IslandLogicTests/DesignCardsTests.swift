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
        // Header row + section gap + 3 event rows (body text ≈ 15pt) + 3
        // reminder rows (28pt hit-frame) + 5 row gaps + margins under a
        // 38pt cutout.
        let header = DS.Button.primary
        let events = 3 * 15.0
        let reminders = 3 * DS.Button.secondaryHitFrame
        let gaps = 5 * DS.Space.rowGap
        let total = 38 + DS.Space.cardTopBelowNotch + header + DS.Space.sectionGap
            + events + reminders + gaps + DS.Space.cardBottom
        XCTAssertLessThanOrEqual(total, DS.Card.maxExpandedHeight)
    }

    func testGlanceBodyHoldsOnePrimaryRow() {
        let body = DS.Space.cardTopBelowNotch + DS.Button.primary + DS.Space.cardBottom
        XCTAssertEqual(body, 50)
    }
}
