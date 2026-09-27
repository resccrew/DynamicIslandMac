import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    private let navigation = SettingsNavigation()

    init(agenda: AgendaMonitor) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsMetrics.windowWidth, height: SettingsMetrics.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки острова"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(
            rootView: SettingsView(settings: .shared, agenda: agenda, navigation: navigation)
        )
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The app runs as an accessory (no Dock icon), so it has to be activated
    /// explicitly or the settings window opens behind whatever has focus.
    func present(tab: SettingsTab? = nil) {
        if let tab { navigation.tab = tab }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
