import XCTest
@testable import IslandLogic

/// Mirrors `IslandSizePreset` in the app (compact/standard/large), which
/// cannot be imported here (it lives in the executable target): these three
/// ear widths are the actual values the picker sets.
private let presetEarWidths: [Double] = [48, 64, 80]

final class IslandSizeWidthReactsToPresetTests: XCTestCase {
    private let fillet = DS.Radius.fillet
    private let notch = 208.0

    /// The bug this preset exists to fix: picking a size must change the
    /// *resting* island, not just the card that opens on a click.
    func testEachPresetProducesADifferentCollapsedWidth() {
        let widths = presetEarWidths.map {
            CollapsedGeometry.windowWidth(notchWidth: notch, fillet: fillet, earWidth: $0)
        }
        XCTAssertEqual(Set(widths).count, presetEarWidths.count, "presets must not collapse to the same width")
        XCTAssertEqual(widths, widths.sorted(), "compact < standard < large")
    }

    func testStandardMatchesTheOldFixedWidth() {
        XCTAssertEqual(
            CollapsedGeometry.windowWidth(notchWidth: notch, fillet: fillet, earWidth: DS.Ear.width),
            CollapsedGeometry.windowWidth(notchWidth: notch, fillet: fillet)
        )
    }

    func testExpandedCardMatchesPeekForEveryPreset() {
        let growth = CollapsedGeometry.defaultPeekWidthGrowth
        for earWidth in presetEarWidths {
            let expanded = CollapsedGeometry.expandedWidth(notchWidth: notch, peekGrowth: growth, earWidth: earWidth)
            let peek = CollapsedGeometry.windowWidth(notchWidth: notch, fillet: fillet, earWidth: earWidth) + growth
            XCTAssertEqual(expanded + 2 * fillet, peek, "earWidth \(earWidth)")
        }
    }

    func testPeekStillGrowsSymmetricallyAtEveryPreset() {
        let growth = CollapsedGeometry.defaultPeekWidthGrowth
        for earWidth in presetEarWidths {
            let collapsedWindow = CollapsedGeometry.windowWidth(notchWidth: notch, fillet: fillet, earWidth: earWidth)
            let peekEar = CollapsedGeometry.earWidth(
                islandWidth: collapsedWindow + growth, fillet: fillet, notchWidth: notch
            )
            XCTAssertEqual(peekEar, earWidth + growth / 2, "earWidth \(earWidth)")
            // Content keeps its place: the inset grows by exactly the extra width.
            XCTAssertEqual(
                CollapsedGeometry.contentInset(earWidth: peekEar, baseEarWidth: earWidth),
                DS.Ear.inset + growth / 2
            )
        }
    }
}

final class IslandSizeTextNeverClipsTests: XCTestCase {
    private func agendaFits(_ label: AgendaFormat.CollapsedLabel, earWidth: Double) -> Bool {
        let clock: (Date) -> String = { _ in "14:30" }
        return EarText.fits(EarText.agenda(label, clock: clock, earWidth: earWidth), earWidth: earWidth)
    }

    func testAgendaMinutesLeftFitsEveryPreset() {
        for earWidth in presetEarWidths {
            for minutes in [1, 5, 9, 28, 59, 60] {
                XCTAssertTrue(agendaFits(.minutesLeft(minutes), earWidth: earWidth), "\(earWidth)pt / \(minutes) min")
            }
        }
    }

    func testAgendaEndsAtFitsEveryPreset() {
        for earWidth in presetEarWidths {
            XCTAssertTrue(agendaFits(.endsAt(Date()), earWidth: earWidth), "\(earWidth)pt")
        }
    }

    func testAgendaStartsAtFitsEveryPreset() {
        for earWidth in presetEarWidths {
            XCTAssertTrue(agendaFits(.startsAt(Date()), earWidth: earWidth), "\(earWidth)pt")
        }
    }

    func testCompactStepsDownToTheShortAgendaForm() {
        // At 48pt (content 34pt) the full "28 мин" no longer fits; the
        // fallback "28м" must be what is actually shown, not a truncation.
        let clock: (Date) -> String = { _ in "14:30" }
        let compact = EarText.agenda(.minutesLeft(28), clock: clock, earWidth: 48)
        XCTAssertEqual(compact, "28м")
        XCTAssertFalse(EarText.fits("28 мин", earWidth: 48))
        XCTAssertTrue(EarText.fits(compact, earWidth: 48))
    }

    func testCompactDropsThePrefixOnEndsAtWhenNeeded() {
        let clock: (Date) -> String = { _ in "14:30" }
        let compact = EarText.agenda(.endsAt(Date()), clock: clock, earWidth: 48)
        XCTAssertEqual(compact, "14:30")
    }

    func testDurationFitsEveryPresetUpToADay() {
        for earWidth in presetEarWidths {
            for seconds in [0.0, 59, 3599, 3600, 3725, 36000, 86399] {
                let text = EarText.duration(seconds, earWidth: earWidth)
                XCTAssertTrue(EarText.fits(text, earWidth: earWidth), "\(earWidth)pt / \(seconds)s -> \(text)")
            }
        }
    }

    func testDurationStepsDownToWholeMinutesWhenTooNarrowForFullPrecision() {
        // 23:59:59 does not fit a 48pt ear even at the smallest scale.
        XCTAssertFalse(EarText.fits("23:59:59", earWidth: 48))
        let shown = EarText.duration(86399, earWidth: 48)
        // Even "1440м" (4 digits + a letter) is too wide for a 48pt ear;
        // the last, bare-number tier is what actually gets shown.
        XCTAssertEqual(shown, "1440")
        XCTAssertTrue(EarText.fits(shown, earWidth: 48))
    }

    func testDurationNeverPicksTheOverflowingFullFormWhenItDoesNotFit() {
        for earWidth in presetEarWidths {
            let text = EarText.duration(86399, earWidth: earWidth)
            if !EarText.fits("23:59:59", earWidth: earWidth) {
                XCTAssertNotEqual(text, "23:59:59")
            }
        }
    }
}
