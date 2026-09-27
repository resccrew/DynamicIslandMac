import AppKit
import IslandGeometry

/// Measures the display's notch so the island can shrink to exactly its
/// footprint when idle — black on black, indistinguishable from the hardware.
/// On displays without a notch the island draws a virtual one as tall as that
/// display's menu bar (see `DisplayGeometry.notchSize`).
enum ScreenNotch {
    /// Zero on `nil` (no notched display connected) — the island is hidden in
    /// that case, so there is nothing for this size to describe.
    static func size(for screen: NSScreen? = IslandDisplay.screen) -> CGSize {
        guard let screen else { return .zero }
        return DisplayGeometry.notchSize(
            for: IslandDisplay.info(for: screen),
            statusBarThickness: NSStatusBar.system.thickness
        )
    }

    /// Whether the screen has a real camera notch. `IslandDisplay.screen`
    /// only ever returns a notched screen, so this is `true` whenever it is
    /// non-nil — kept as its own check for callers that already have an
    /// `NSScreen` (e.g. re-measuring the current one).
    static func hasNotch(for screen: NSScreen? = IslandDisplay.screen) -> Bool {
        guard let screen else { return false }
        return IslandDisplay.info(for: screen).hasNotch
    }
}

/// Picks the screen the island lives on. `NSScreen.main` follows keyboard
/// focus and `window.screen` is nil before placement, so neither is stable.
enum IslandDisplay {
    /// The built-in notched panel — the only screen the island ever lives on.
    /// `nil` with the lid closed or when only an external, non-notched
    /// monitor is connected; every window controller hides itself in that case
    /// rather than showing the island somewhere that has no real notch to
    /// hide behind (see DESIGN-DECISIONS.md "Только на вырезе").
    static var screen: NSScreen? {
        let screens = NSScreen.screens
        let displays = screens.enumerated().map { info(for: $0.element, isPrimary: $0.offset == 0) }
        guard let index = DisplayGeometry.preferredNotchedDisplay(among: displays) else { return nil }
        return screens[index]
    }

    static func info(for screen: NSScreen, isPrimary: Bool? = nil) -> DisplayInfo {
        DisplayInfo(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
            isBuiltIn: isBuiltIn(screen),
            isPrimary: isPrimary ?? (screen == NSScreen.screens.first)
        )
    }

    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let id = displayID(for: screen) else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    /// Whether another app fills the island's display right now (native
    /// fullscreen, or a borderless player covering it). Main thread.
    static func isShowingFullScreen(_ screen: NSScreen) -> Bool {
        guard let id = displayID(for: screen),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return false }
        let windows = list.compactMap { info -> ScreenWindow? in
            guard
                let pid = info[kCGWindowOwnerPID as String] as? Int32,
                let layer = info[kCGWindowLayer as String] as? Int,
                let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            return ScreenWindow(ownerPID: pid, layer: layer, bounds: bounds)
        }
        return FullScreenDetection.isFullScreen(
            windows: windows,
            displayBounds: CGDisplayBounds(id),
            ownPID: ProcessInfo.processInfo.processIdentifier
        )
    }
}
