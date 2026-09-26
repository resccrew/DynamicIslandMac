import XCTest
@testable import IslandGeometry

final class DisplayGeometryTests: XCTestCase {
    // Built-in notched panel in points at the "More Space" scaled mode
    // (1512x982), notch 32pt tall and 190pt wide.
    private let builtIn = DisplayInfo(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        safeAreaTop: 32,
        auxiliaryLeftWidth: 661,
        auxiliaryRightWidth: 661,
        isBuiltIn: true
    )

    private func external(x: CGFloat = 0, y: CGFloat = 0, menuBar: CGFloat = 24, primary: Bool = true) -> DisplayInfo {
        DisplayInfo(
            frame: CGRect(x: x, y: y, width: 1920, height: 1080),
            visibleFrame: CGRect(x: x, y: y, width: 1920, height: 1080 - menuBar),
            isPrimary: primary
        )
    }

    func testNotchedBuiltInUsesHardwareNotch() {
        let size = DisplayGeometry.notchSize(for: builtIn, statusBarThickness: 24)
        XCTAssertEqual(size, CGSize(width: 190, height: 32))
    }

    func testExternalVirtualNotchMatchesMenuBarHeight() {
        let size = DisplayGeometry.notchSize(for: external(), statusBarThickness: 37)
        XCTAssertEqual(size.height, 24)
        XCTAssertEqual(size.width, 190)
    }

    func testAutoHiddenMenuBarFallsBackToStatusBarThickness() {
        let size = DisplayGeometry.notchSize(for: external(menuBar: 0), statusBarThickness: 22)
        XCTAssertEqual(size.height, 22)
    }

    func testVirtualNotchWidthClampedOnTinyScreen() {
        let tiny = DisplayInfo(
            frame: CGRect(x: 0, y: 0, width: 300, height: 200),
            visibleFrame: CGRect(x: 0, y: 0, width: 300, height: 176)
        )
        let size = DisplayGeometry.notchSize(for: tiny, statusBarThickness: 24)
        XCTAssertEqual(size.width, 150)
        XCTAssertLessThanOrEqual(size.width, tiny.frame.width)
    }

    func testOnlyBuiltIn() {
        var only = builtIn
        only.isPrimary = true
        for policy in IslandDisplayPolicy.allCases {
            XCTAssertEqual(DisplayGeometry.preferredDisplay(among: [only], policy: policy), 0)
        }
    }

    func testBuiltInPlusPrimaryExternal() {
        let displays = [external(), builtIn]
        XCTAssertEqual(DisplayGeometry.preferredDisplay(among: displays, policy: .primary), 0)
        XCTAssertEqual(DisplayGeometry.preferredDisplay(among: displays, policy: .builtIn), 1)
    }

    func testLidClosedOnlyExternal() {
        let displays = [external()]
        for policy in IslandDisplayPolicy.allCases {
            XCTAssertEqual(DisplayGeometry.preferredDisplay(among: displays, policy: policy), 0)
        }
    }

    func testBuiltInPolicyWithoutBuiltInFallsBackToPrimary() {
        let displays = [external(x: 1920, primary: false), external(primary: true)]
        XCTAssertEqual(DisplayGeometry.preferredDisplay(among: displays, policy: .builtIn), 1)
    }

    func testEmptyListIsNil() {
        XCTAssertNil(DisplayGeometry.preferredDisplay(among: [], policy: .primary))
        XCTAssertNil(DisplayGeometry.preferredDisplay(among: [], policy: .builtIn))
    }

    func testPanelOriginTopCentreWithNegativeOrigin() {
        let left = external(x: -1920, y: 100, primary: false)
        let origin = DisplayGeometry.panelOrigin(containerSize: CGSize(width: 400, height: 200), on: left)
        XCTAssertEqual(origin, CGPoint(x: -960 - 200, y: 1180 - 200))
    }

    func testStoredPolicyDecoding() {
        XCTAssertEqual(IslandDisplayPolicy(stored: "automatic"), .primary)
        XCTAssertEqual(IslandDisplayPolicy(stored: "garbage"), .primary)
        XCTAssertEqual(IslandDisplayPolicy(stored: nil), .primary)
        XCTAssertEqual(IslandDisplayPolicy(stored: "builtIn"), .builtIn)
        XCTAssertEqual(IslandDisplayPolicy(stored: "primary"), .primary)
    }

    func testDockOnLeftOrBottomDoesNotChangeMenuBarHeight() {
        let dockLeft = DisplayInfo(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 70, y: 0, width: 1850, height: 1056)
        )
        let dockBottom = DisplayInfo(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 70, width: 1920, height: 986)
        )
        XCTAssertEqual(DisplayGeometry.menuBarHeight(for: dockLeft, statusBarThickness: 37), 24)
        XCTAssertEqual(DisplayGeometry.menuBarHeight(for: dockBottom, statusBarThickness: 37), 24)
    }

    func testPanelOriginOnDisplayAbovePrimary() {
        let above = external(x: 200, y: 1080, primary: false)
        let origin = DisplayGeometry.panelOrigin(containerSize: CGSize(width: 400, height: 200), on: above)
        XCTAssertEqual(origin, CGPoint(x: 1160 - 200, y: 2160 - 200))
    }

    func testBuiltInPolicyPicksNonPrimaryNotchedBuiltIn() {
        let displays = [external(primary: true), builtIn]
        guard let index = DisplayGeometry.preferredDisplay(among: displays, policy: .builtIn) else {
            return XCTFail("expected a display")
        }
        XCTAssertEqual(index, 1)
        XCTAssertEqual(
            DisplayGeometry.notchSize(for: displays[index], statusBarThickness: 24),
            CGSize(width: 190, height: 32)
        )
    }

    func testPartialAuxiliaryDataGivesVirtualNotch() {
        var partial = builtIn
        partial.auxiliaryRightWidth = nil
        XCTAssertFalse(partial.hasNotch)
        let size = DisplayGeometry.notchSize(for: partial, statusBarThickness: 24)
        XCTAssertEqual(size, CGSize(width: 190, height: 32))
        // Height comes from the menu bar gap (982 - 950), not safeAreaTop.
        partial.visibleFrame.size.height = 958
        XCTAssertEqual(DisplayGeometry.notchSize(for: partial, statusBarThickness: 24).height, 24)
    }

    func testNegativeGapFallsBackToStatusBarThickness() {
        let odd = DisplayInfo(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1100)
        )
        XCTAssertEqual(DisplayGeometry.menuBarHeight(for: odd, statusBarThickness: 22), 22)
    }

    // MARK: - Collapsed island fits the menu bar

    func testNoNotchCollapsedCappedAtThirtyPointMenuBar() {
        let notch = CGSize(width: 190, height: 30)
        let collapsed = DisplayGeometry.collapsedIslandSize(CGSize(width: 306, height: 38), notch: notch, hasNotch: false)
        XCTAssertEqual(collapsed, CGSize(width: 306, height: 30))
        let peek = DisplayGeometry.collapsedIslandSize(CGSize(width: 324, height: 43), notch: notch, hasNotch: false)
        XCTAssertLessThanOrEqual(peek.height, 30)
        XCTAssertEqual(peek.width, 324)
    }

    func testNoNotchCollapsedCappedAtTwentyFourPointMenuBar() {
        let size = DisplayGeometry.collapsedIslandSize(
            CGSize(width: 306, height: 38), notch: CGSize(width: 190, height: 24), hasNotch: false
        )
        XCTAssertEqual(size, CGSize(width: 306, height: 24))
    }

    func testNotchedDisplayCollapsedUnchanged() {
        let size = DisplayGeometry.collapsedIslandSize(
            CGSize(width: 306, height: 38), notch: CGSize(width: 190, height: 32), hasNotch: true
        )
        XCTAssertEqual(size, CGSize(width: 306, height: 38))
    }

    func testShorterRequestIsNotEnlarged() {
        let size = DisplayGeometry.collapsedIslandSize(
            CGSize(width: 200, height: 20), notch: CGSize(width: 190, height: 30), hasNotch: false
        )
        XCTAssertEqual(size, CGSize(width: 200, height: 20))
    }

    func testContentScaleFitsRow() {
        // 26pt artwork in a 24pt row with 2pt insets → 20/26.
        XCTAssertEqual(DisplayGeometry.collapsedContentScale(rowHeight: 24, contentHeight: 26), 20.0 / 26.0, accuracy: 1e-9)
        XCTAssertEqual(DisplayGeometry.collapsedContentScale(rowHeight: 32, contentHeight: 26), 1)
        XCTAssertEqual(DisplayGeometry.collapsedContentScale(rowHeight: 24, contentHeight: 0), 1)
    }
}
