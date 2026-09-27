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
        // «ещё 45 мин» (~70pt at 13pt) fits the ear content at the floor.
        XCTAssertLessThanOrEqual(70 * CollapsedGeometry.minTextScale, CollapsedGeometry.contentWidth)
    }
}
