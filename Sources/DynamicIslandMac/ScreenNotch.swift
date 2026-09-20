import AppKit

/// Measures the display's notch so the island can shrink to exactly its
/// footprint when idle — black on black, indistinguishable from the hardware.
enum ScreenNotch {
    /// Fallback pill for displays without a notch, where there is nothing to
    /// hide behind and the island has to be its own small shape.
    private static let fallback = CGSize(width: 190, height: 32)

    static func size(for screen: NSScreen? = NSScreen.main) -> CGSize {
        guard let screen,
              screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else {
            return fallback
        }

        return CGSize(
            width: screen.frame.width - left.width - right.width,
            height: screen.safeAreaInsets.top
        )
    }
}
