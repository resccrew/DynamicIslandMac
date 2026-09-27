import XCTest
@testable import IslandLogic

final class DesignTokensTests: XCTestCase {

    // MARK: - Ear width / collapsed width

    func testEarWidthIsSharedByAllContentKinds() {
        // There is exactly one ear width constant — by construction there is
        // nothing per-content-kind to diverge, but pin the value so a future
        // edit can't silently reintroduce a second one.
        XCTAssertEqual(DS.Ear.width, 64)
    }

    func testCollapsedWidthFormula() {
        XCTAssertEqual(DS.collapsedWidth(notchWidth: 185), 185 + 2 * 64)
        XCTAssertEqual(DS.collapsedWidth(notchWidth: 190), 190 + 2 * DS.Ear.width)
        XCTAssertEqual(DS.collapsedWidth(notchWidth: 0), 2 * DS.Ear.width)
    }

    // MARK: - Opacity scale

    func testOpacityHasExactlyThreeTextLevelsPlusDimmedAndTrack() {
        // primary, secondary, tertiary + dimmed + track = 5 named tokens.
        let distinctValues = Set([
            DS.Opacity.primary,
            DS.Opacity.secondary,
            DS.Opacity.tertiary,
            DS.Opacity.dimmed,
            DS.Opacity.track,
        ])
        // dimmed == tertiary by decision, so only 4 distinct numeric values.
        XCTAssertEqual(distinctValues.count, 4)
        XCTAssertEqual(DS.Opacity.dimmed, DS.Opacity.tertiary)
    }

    func testOpacityLevelsAreStrictlyOrdered() {
        let levels = DS.Opacity.orderedLevels
        XCTAssertEqual(levels.count, 4)
        for (a, b) in zip(levels, levels.dropFirst()) {
            XCTAssertLessThan(a, b)
        }
    }

    // MARK: - Spacing scale

    func testAllSpacingValuesBelongToTheScale() {
        let allowed: Set<Double> = [2, 4, 6, 8, 12, 16, 27]
        let usedTokens: [Double] = [
            DS.Space.xxs, DS.Space.xs, DS.Space.s, DS.Space.m, DS.Space.l, DS.Space.xl, DS.Space.cardSide,
            DS.Space.titleGap, DS.Space.leadGap, DS.Space.sectionGap, DS.Space.rowGap,
            DS.Space.inlineGap, DS.Space.cardTopBelowNotch, DS.Space.cardBottom,
        ]
        for value in usedTokens {
            XCTAssertTrue(allowed.contains(value), "\(value) is not in the approved spacing scale")
        }
        XCTAssertEqual(Set(DS.Space.scale), allowed)
    }

    // MARK: - Motion

    func testMotionHasExactlyThreeTokens() {
        XCTAssertEqual(DS.Motion.all.count, 3)
        XCTAssertEqual(DS.Motion.state, .spring(response: 0.32, damping: 0.86))
        XCTAssertEqual(DS.Motion.fade, .easeOut(duration: 0.32))
        XCTAssertEqual(DS.Motion.micro, .easeOut(duration: 0.22))
    }

    func testReduceMotionNeverResolvesToASpring() {
        for token in DS.Motion.all {
            let resolved = DS.Motion.resolve(reduceMotion: true, requested: token)
            switch resolved {
            case .spring:
                XCTFail("Reduce Motion must never resolve to a spring (implies scale/bounce)")
            case .easeOut:
                break
            }
        }
    }

    func testReduceMotionOffKeepsTheRequestedCurve() {
        for token in DS.Motion.all {
            XCTAssertEqual(DS.Motion.resolve(reduceMotion: false, requested: token), token)
        }
    }

    // MARK: - Radii

    func testCollapsedBottomRadiusIsExactlyHalfHeight() {
        XCTAssertEqual(DS.Radius.collapsedBottom(height: 38), 19)
        XCTAssertEqual(DS.Radius.collapsedBottom(height: 43), 21.5)
        XCTAssertEqual(DS.Radius.collapsedBottom(height: 0), 0)
    }

    // MARK: - Icons

    func testIconSizesBelongToTheAllowedSet() {
        let allowed: Set<Double> = [11, 14, 20, 22, 30, 54]  // DESIGN-DECISIONS «Иконки»
        let used: [Double] = [
            DS.Icon.earSlot, DS.Icon.earSymbol, DS.Icon.earSecondary,
            DS.Icon.ring, DS.Icon.eqBarHeight,
            DS.Card.headerIcon, DS.Card.headerIconColumn, DS.Card.lead,
        ]
        for value in used {
            XCTAssertTrue(allowed.contains(value), "\(value) is not an approved icon size")
        }
    }

    func testEarSlotAndEarSymbolAreDistinctButBothPositive() {
        XCTAssertGreaterThan(DS.Icon.earSlot, DS.Icon.earSymbol)
        XCTAssertGreaterThan(DS.Icon.earSymbol, DS.Icon.earSecondary)
    }

    // MARK: - Ear content helpers

    func testEarContentInsetIsConstantAcrossSilhouetteSizes() {
        XCTAssertEqual(DS.earContentInset(), DS.Ear.inset)
        XCTAssertEqual(DS.earContentInset(), 8)
    }

    func testEarContentHeightNeverNegative() {
        XCTAssertEqual(DS.earContentHeight(silhouetteHeight: 0), 0)
        XCTAssertGreaterThanOrEqual(DS.earContentHeight(silhouetteHeight: 38), 0)
    }
}
