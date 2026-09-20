import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки острова"
        window.contentView = NSHostingView(rootView: SettingsView(settings: .shared))
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    /// The app runs as an accessory (no Dock icon), so it has to be activated
    /// explicitly or the settings window opens behind whatever has focus.
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
