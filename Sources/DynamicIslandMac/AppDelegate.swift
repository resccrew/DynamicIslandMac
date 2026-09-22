import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// One model and one poller feed both the island and the lock screen.
    private let model = IslandViewModel()
    private let poller = NowPlayingPoller()
    private let settings = IslandSettings.shared

    private var islandController: IslandWindowController?
    private var lockScreenController: LockScreenWindowController?
    private var settingsController: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The controller shows and hides the panel itself, following whether
        // there is anything playing.
        islandController = IslandWindowController(model: model)
        lockScreenController = LockScreenWindowController(model: model)


        poller.start { [weak self] snapshot in
            self?.model.apply(snapshot)
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

        let timerItem = NSMenuItem(title: "Таймер", action: nil, keyEquivalent: "")
        timerItem.submenu = makeTimerMenu()
        menu.addItem(timerItem)

        let calendarItem = NSMenuItem(
            title: "Ближайшее событие",
            action: #selector(showCalendarGlance),
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

    private func makeTimerMenu() -> NSMenu {
        let menu = NSMenu()
        for minutes in [1.0, 5.0, 10.0, 15.0, 30.0] {
            let item = NSMenuItem(
                title: "\(Int(minutes)) мин",
                action: #selector(startTimerFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = minutes
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let customItem = NSMenuItem(
            title: "Другое…",
            action: #selector(startCustomTimer),
            keyEquivalent: ""
        )
        customItem.target = self
        menu.addItem(customItem)

        let cancelItem = NSMenuItem(
            title: "Остановить таймер",
            action: #selector(cancelTimer),
            keyEquivalent: ""
        )
        cancelItem.target = self
        menu.addItem(cancelItem)

        return menu
    }

    @objc private func startTimerFromMenu(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Double else { return }
        model.startTimer(minutes: minutes)
    }

    @objc private func startCustomTimer() {
        let alert = NSAlert()
        alert.messageText = "Таймер"
        alert.informativeText = "Сколько минут?"
        alert.addButton(withTitle: "Начать")
        alert.addButton(withTitle: "Отмена")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.stringValue = "10"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn,
              let minutes = Double(field.stringValue), minutes > 0
        else { return }
        model.startTimer(minutes: minutes)
    }

    @objc private func cancelTimer() {
        model.cancelTimer()
    }

    @objc private func showCalendarGlance() {
        CalendarGlanceProvider.fetchNextEvent { [weak self] event in
            guard let self else { return }
            guard let event else {
                self.model.presentGlance(title: "Событий больше нет", subtitle: nil)
                return
            }
            self.model.presentGlance(title: event.title, subtitle: event.timeRange)
        }
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
