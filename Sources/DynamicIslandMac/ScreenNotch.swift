import AppKit
import IslandGeometry

/// Measures the display's notch so the island can shrink to exactly its
/// footprint when idle — black on black, indistinguishable from the hardware.
/// On displays without a notch the island draws a virtual one as tall as that
/// display's menu bar (see `DisplayGeometry.notchSize`).
enum ScreenNotch {
    static func size(for screen: NSScreen? = IslandDisplay.screen) -> CGSize {
        guard let screen else {
            return CGSize(width: DisplayGeometry.virtualNotchWidth, height: NSStatusBar.system.thickness)
        }
        return DisplayGeometry.notchSize(
            for: IslandDisplay.info(for: screen),
            statusBarThickness: NSStatusBar.system.thickness
        )
    }
}

/// Picks the screen the island lives on. `NSScreen.main` follows keyboard
/// focus and `window.screen` is nil before placement, so neither is stable.
enum IslandDisplay {
    static var screen: NSScreen? {
        let screens = NSScreen.screens
        let displays = screens.enumerated().map { info(for: $0.element, isPrimary: $0.offset == 0) }
        let policy = IslandSettings.shared.displayPolicy
        guard let index = DisplayGeometry.preferredDisplay(among: displays, policy: policy) else { return nil }
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
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }
}
