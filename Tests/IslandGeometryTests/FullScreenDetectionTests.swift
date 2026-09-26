import XCTest
@testable import IslandGeometry

final class FullScreenDetectionTests: XCTestCase {
    private let own: Int32 = 100
    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    // A built-in display to the left of it, in the same global top-left space.
    private let other = CGRect(x: -1512, y: 0, width: 1512, height: 982)

    private func window(_ bounds: CGRect, pid: Int32 = 200, layer: Int = 0) -> ScreenWindow {
        ScreenWindow(ownerPID: pid, layer: layer, bounds: bounds)
    }

    func testWindowCoveringScreenIsFullScreen() {
        XCTAssertTrue(FullScreenDetection.isFullScreen(windows: [window(display)], displayBounds: display, ownPID: own))
    }

    func testFullScreenOnOtherDisplayIgnored() {
        XCTAssertFalse(FullScreenDetection.isFullScreen(windows: [window(other)], displayBounds: display, ownPID: own))
    }

    func testOwnDesktopMenuBarAndDockIgnored() {
        let windows = [
            window(display, pid: own),                 // our own window
            window(display, pid: 1, layer: -2147483624), // desktop
            window(CGRect(x: 0, y: 0, width: 1920, height: 30), pid: 2, layer: 24), // menu bar
            window(display, pid: 3, layer: 20),         // Dock / overlays
        ]
        XCTAssertFalse(FullScreenDetection.isFullScreen(windows: windows, displayBounds: display, ownPID: own))
    }

    func testZoomedWindowBelowMenuBarIsNotFullScreen() {
        let zoomed = CGRect(x: 0, y: 30, width: 1920, height: 1050)
        XCTAssertFalse(FullScreenDetection.isFullScreen(windows: [window(zoomed)], displayBounds: display, ownPID: own))
    }

    func testRoundingToleranceAccepted() {
        let almost = CGRect(x: 0.5, y: 0, width: 1919.5, height: 1080)
        XCTAssertTrue(FullScreenDetection.isFullScreen(windows: [window(almost)], displayBounds: display, ownPID: own))
    }

    func testEmptyDisplayIsNeverFullScreen() {
        XCTAssertFalse(FullScreenDetection.isFullScreen(windows: [window(display)], displayBounds: .zero, ownPID: own))
    }
}
