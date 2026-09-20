import Foundation
import IOKit.pwr_mgt

/// Holds a power assertion so the display stays on while the screen is locked.
///
/// This is the same mechanism `caffeinate` uses, and it keeps working after the
/// session locks. The assertion is always released on unlock and after the
/// configured window, so a forgotten lock screen cannot drain the battery all
/// night.
final class DisplaySleepBlocker {
    private var assertionID: IOPMAssertionID = 0
    private var isHeld = false
    private var expiry: Timer?

    /// Keeps the display awake for `minutes`, restarting the countdown if already held.
    func begin(minutes: Double) {
        expiry?.invalidate()

        if !isHeld {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "DynamicIslandMac lock screen" as CFString,
                &id
            )
            guard result == kIOReturnSuccess else { return }
            assertionID = id
            isHeld = true
        }

        expiry = Timer.scheduledTimer(withTimeInterval: minutes * 60, repeats: false) { [weak self] _ in
            self?.end()
        }
    }

    func end() {
        expiry?.invalidate()
        expiry = nil

        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isHeld = false
    }

    deinit {
        end()
    }
}
