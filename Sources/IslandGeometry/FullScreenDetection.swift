import CoreGraphics

/// One on-screen window as `CGWindowListCopyWindowInfo` reports it, in
/// global top-left coordinates.
public struct ScreenWindow: Equatable, Sendable {
    public var ownerPID: Int32
    /// `kCGWindowLayer`: 0 for ordinary app windows; the desktop, Dock,
    /// menu bar and our own status-level panel all sit on other layers.
    public var layer: Int
    public var bounds: CGRect

    public init(ownerPID: Int32, layer: Int, bounds: CGRect) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.bounds = bounds
    }
}

public enum FullScreenDetection {
    /// Slack for rounding in window bounds, in points.
    static let tolerance: CGFloat = 1

    /// Whether another app's ordinary window covers the whole display —
    /// native fullscreen, or a borderless player filling the screen. A
    /// zoomed window stops below the menu bar and does not count.
    /// `displayBounds` is in the same top-left space (`CGDisplayBounds`).
    public static func isFullScreen(windows: [ScreenWindow], displayBounds: CGRect, ownPID: Int32) -> Bool {
        guard !displayBounds.isEmpty else { return false }
        let target = displayBounds.insetBy(dx: tolerance, dy: tolerance)
        return windows.contains { window in
            window.layer == 0 && window.ownerPID != ownPID && window.bounds.contains(target)
        }
    }
}
