import XCTest
@testable import IslandLogic

final class CollapsedWidthTests: XCTestCase {
    private let fillet = DS.Radius.fillet

    func testEveryEarIsTheTokenWidthOnAnyNotch() {
        for notch in [0.0, 185, 190, 210] {
            let window = CollapsedGeometry.windowWidth(notchWidth: notch, fillet: fillet)
            XCTAssertEqual(window, notch + 2 * DS.Ear.width + 2 * fillet)
            XCTAssertEqual(
                CollapsedGeometry.earWidth(islandWidth: window, fillet: fillet, notchWidth: notch),
                DS.Ear.width
            )
        }
    }

    func testWidthDoesNotDependOnContentKind() {
        // The width takes only the notch and fillet: nothing about the
        // content (media, timer, call, agenda, activity) can enter it.
        let widths = (0..<5).map { _ in CollapsedGeometry.windowWidth(notchWidth: 185, fillet: fillet) }
        XCTAssertEqual(Set(widths).count, 1)
    }

    func testEarWidthNeverNegative() {
        XCTAssertEqual(CollapsedGeometry.earWidth(islandWidth: 100, fillet: fillet, notchWidth: 185), 0)
    }

    func testContentFitsTheEarMinusItsInset() {
        XCTAssertEqual(CollapsedGeometry.contentWidth, DS.Ear.width - DS.Ear.inset)
    }
}

final class PeekSymmetryTests: XCTestCase {
    private let fillet = DS.Radius.fillet
    private let notch = 185.0

    private var collapsedWidth: Double { CollapsedGeometry.windowWidth(notchWidth: notch, fillet: fillet) }
    private var growth: Double { CollapsedGeometry.defaultPeekWidthGrowth }

    func testPeekWidensEachEarByHalfTheGrowth() {
        let peek = CollapsedGeometry.earWidth(islandWidth: collapsedWidth + growth, fillet: fillet, notchWidth: notch)
        XCTAssertEqual(peek, DS.Ear.width + growth / 2)
    }

    func testContentStaysWhereItWasWhenPeekGrows() {
        let collapsedEar = CollapsedGeometry.earWidth(islandWidth: collapsedWidth, fillet: fillet, notchWidth: notch)
        let peekEar = CollapsedGeometry.earWidth(islandWidth: collapsedWidth + growth, fillet: fillet, notchWidth: notch)
        let content = 22.0
        // Distance from the notch edge to the content's near edge.
        let collapsedGap = collapsedEar - CollapsedGeometry.contentInset(earWidth: collapsedEar) - content
        let peekGap = peekEar - CollapsedGeometry.contentInset(earWidth: peekEar) - content
        XCTAssertEqual(collapsedGap, peekGap)
    }

    func testInsetIsTheTokenWhenCollapsedAndNeverSmaller() {
        XCTAssertEqual(CollapsedGeometry.contentInset(earWidth: DS.Ear.width), DS.Ear.inset)
        XCTAssertEqual(CollapsedGeometry.contentInset(earWidth: 10), DS.Ear.inset)
    }

    func testPeekGrowthSitsOnTheSpacingScale() {
        XCTAssertTrue(DS.Space.scale.contains(growth / 2))
        XCTAssertTrue(DS.Space.scale.contains(CollapsedGeometry.defaultPeekHeightGrowth))
    }

    func testContentRowIgnoresPeekHeight() {
        let collapsed = CollapsedGeometry.height(notchHeight: 32)
        XCTAssertEqual(CollapsedGeometry.contentRowHeight(collapsedHeight: collapsed), collapsed)
    }
}

final class CollapsedShapeTests: XCTestCase {
    func testHeightIsNotchPlusOneStepOfTheScale() {
        XCTAssertEqual(CollapsedGeometry.height(notchHeight: 32), 32 + DS.Space.s)
    }

    func testBottomRadiusIsHalfTheHeightAndNeverClamped() {
        let fillet = DS.Radius.fillet
        for notchHeight in [24.0, 32, 37] {
            let collapsed = CollapsedGeometry.height(notchHeight: notchHeight)
            let peek = collapsed + CollapsedGeometry.defaultPeekHeightGrowth
            for height in [collapsed, peek] {
                let radius = CollapsedGeometry.bottomRadius(collapsedLike: height)
                XCTAssertEqual(radius, height / 2)
                // `NotchShape` clamps to `height - fillet`; half the height fits.
                if height >= 2 * fillet {
                    XCTAssertLessThanOrEqual(radius, height - fillet)
                }
            }
        }
    }

    func testOneExponentForEveryCorner() {
        XCTAssertEqual(CollapsedGeometry.shapeExponent, 2.2)
    }

    func testTextShrinksButNotBelowTheFloor() {
        XCTAssertGreaterThan(CollapsedGeometry.minTextScale, 0)
        XCTAssertLessThan(CollapsedGeometry.minTextScale, 1)
        // Ear text is never cut, and the floor stays gentle.
        XCTAssertGreaterThanOrEqual(CollapsedGeometry.minTextScale, 0.85)
    }
}

final class EarTextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let clock: (Date) -> String = { date in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func label(startIn: Double, lasts: Double) -> AgendaFormat.CollapsedLabel {
        AgendaFormat.collapsedLabel(
            start: now.addingTimeInterval(startIn), end: now.addingTimeInterval(startIn + lasts), now: now
        )
    }

    func testAgendaFormatsAreCompact() {
        XCTAssertEqual(EarText.agenda(label(startIn: -60, lasts: 28 * 60 + 60), clock: clock), "28 мин")
        XCTAssertEqual(EarText.agenda(label(startIn: -60, lasts: 2 * 3600), clock: clock), "до \(clock(now.addingTimeInterval(7140)))")
        XCTAssertEqual(EarText.agenda(label(startIn: 300, lasts: 1800), clock: clock), clock(now.addingTimeInterval(300)))
    }

    func testEveryAgendaLabelFitsTheEar() {
        // Minutes left: 1...60 (ceil can reach 60), plus both clock forms.
        for minutes in 1...60 {
            let text = EarText.agenda(.minutesLeft(minutes), clock: clock)
            XCTAssertTrue(EarText.fits(text), text)
            XCTAssertFalse(text.contains("ещё"), text)
        }
        for hour in 0..<24 {
            for minute in [0, 9, 59] {
                let date = Date(timeIntervalSince1970: Double(hour * 3600 + minute * 60))
                for label in [AgendaFormat.CollapsedLabel.startsAt(date), .endsAt(date)] {
                    let text = EarText.agenda(label, clock: clock)
                    XCTAssertTrue(EarText.fits(text), text)
                }
            }
        }
    }

    func testOverdueReminderIsPlainTime() {
        // A reminder due at 04:07 reads exactly that, and it fits.
        let due = Date(timeIntervalSince1970: 4 * 3600 + 7 * 60)
        XCTAssertEqual(clock(due), "04:07")
        XCTAssertTrue(EarText.fits(clock(due)))
    }

    func testTimerAndCallClocksFitAtTheirLongest() {
        for seconds in [0.0, 59, 3599, 3600, 3725, 36000, 86399] {
            let text = FormatTime.clock(seconds)
            XCTAssertTrue(EarText.fits(text), text)
        }
        XCTAssertEqual(FormatTime.clock(3725), "1:02:05")
    }

    func testEstimatorRejectsTheOldLabel() {
        XCTAssertFalse(EarText.fits("ещё 28 мин"))
    }

    func testMostLabelsNeedNoScalingAtAll() {
        XCTAssertLessThanOrEqual(EarText.estimatedWidth("28 мин"), CollapsedGeometry.contentWidth)
        XCTAssertLessThanOrEqual(EarText.estimatedWidth("1:02:05"), CollapsedGeometry.contentWidth)
    }
}
