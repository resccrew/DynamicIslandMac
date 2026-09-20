import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// One model and one poller feed both the island and the lock screen.
    private let model = IslandViewModel()
    private let poller = NowPlayingPoller()
    private let devices = DeviceMonitors()
    private let settings = IslandSettings.shared

    private var islandController: IslandWindowController?
    private var lockScreenController: LockScreenWindowController?
    private var agentStatusController: AgentStatusWindowController?
    private var settingsController: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The controller shows and hides the panel itself, following whether
        // there is anything playing.
        islandController = IslandWindowController(model: model)
        lockScreenController = LockScreenWindowController(model: model)
        agentStatusController = AgentStatusWindowController()

        poller.start { [weak self] snapshot in
            self?.model.apply(snapshot)
        }

        devices.start { [weak self] notice in
            guard IslandSettings.shared.deviceNoticesEnabled else { return }
            self?.model.present(notice)
        }

        syncStatusItem()
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.syncStatusItem() }
            .store(in: &cancellables)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening the app again from Applications or the Dock reveals the settings.
    /// This is the way back in when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openSettings()
        return true
    }

    private func syncStatusItem() {
        if settings.showStatusIcon {
            guard statusItem == nil else { return }
            statusItem = makeStatusItem()
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "smallcircle.filled.circle",
            accessibilityDescription: "Dynamic Island"
        )

        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Настройки…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let previewItem = NSMenuItem(
            title: "Показать карточку локскрина",
            action: #selector(toggleLockPreview),
            keyEquivalent: "l"
        )
        previewItem.target = self
        menu.addItem(previewItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        return item
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController()
        }
        settingsController?.present()
    }

    @objc private func toggleLockPreview() {
        lockScreenController?.previewToggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
