import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// One model and one poller feed both the island and the lock screen.
    private let model = IslandViewModel()
    private let poller = NowPlayingPoller()
    private let calls = CallMonitor()
    private let systemTimers = SystemTimerMonitor()
    private let agenda = AgendaMonitor()
    private let settings = IslandSettings.shared

    private var islandController: IslandWindowController?
    private var lockScreenController: LockScreenWindowController?
    private var settingsController: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    #if DEBUG
    private var debugServer: DebugControlServer?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The controller shows and hides the panel itself, following whether
        // there is anything playing.
        islandController = IslandWindowController(model: model)
        lockScreenController = LockScreenWindowController(model: model)

        #if DEBUG
        debugServer = DebugControlServer(
            model: model,
            islandController: islandController,
            lockController: lockScreenController,
            poller: poller,
            calls: calls
        )
        debugServer?.systemTimers = systemTimers
        debugServer?.agenda = agenda
        debugServer?.start()
        #endif

        model.player = poller
        poller.start { [weak self] snapshot in
            #if DEBUG
            // An injected track must not be overwritten by the real player.
            if self?.debugServer?.isInjecting == true { return }
            #endif
            self?.model.apply(snapshot)
        }

        calls.start { [weak self] call in
            #if DEBUG
            if self?.debugServer?.isInjectingCall == true { return }
            #endif
            self?.model.setCall(call)
        }

        systemTimers.start(
            onChange: { [weak self] timers in
                #if DEBUG
                if self?.debugServer?.isInjectingTimer == true { return }
                #endif
                self?.model.applySystemTimers(timers)
            },
            onFire: { [weak self] title in
                #if DEBUG
                if self?.debugServer?.isInjectingTimer == true { return }
                #endif
                self?.model.systemTimerFired(title: title)
            }
        )

        // Injected agenda goes through the monitor itself (see
        // `AgendaMonitor.inject`), so no debug gate is needed here.
        model.completeReminderHandler = { [weak self] id in
            self?.agenda.complete(reminderID: id)
        }
        agenda.start(
            onSnapshot: { [weak self] snapshot in self?.model.applyAgenda(snapshot) },
            onAlert: { [weak self] alert in self?.model.handleAgendaAlert(alert) }
        )

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

        let calendarItem = NSMenuItem(
            title: "Сегодня",
            action: #selector(showAgenda),
            keyEquivalent: "e"
        )
        calendarItem.target = self
        menu.addItem(calendarItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        return item
    }

    @objc private func showAgenda() {
        model.showAgenda()
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
