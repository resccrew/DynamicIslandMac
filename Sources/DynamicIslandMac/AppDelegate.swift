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
    private var liveActivityServer: LiveActivityServer?
    private var cancellables = Set<AnyCancellable>()
    #if DEBUG
    private var debugServer: DebugControlServer?
    #endif

    /// `pkill`, `kill` and Ctrl-C arrive as signals, which would end the app
    /// without running `applicationWillTerminate`. Routing them through
    /// `NSApp.terminate` makes the helpers shut down cleanly first. (A
    /// `SIGKILL` or crash can't be caught; `ChildGuard` covers those.)
    private var signalSources: [DispatchSourceSignal] = []

    private func routeTerminationSignals() {
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        poller.shutdown()
        systemTimers.stopAndWait()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        routeTerminationSignals()
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

        let liveActivityServer = LiveActivityServer(model: model)
        self.liveActivityServer = liveActivityServer
        liveActivityServer.setEnabled(settings.allowExternalAPI)
        settings.$allowExternalAPI
            .removeDuplicates()
            .sink { [weak liveActivityServer] in liveActivityServer?.setEnabled($0) }
            .store(in: &cancellables)

        syncStatusItem()
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.syncStatusItem() }
            .store(in: &cancellables)

        showWelcomeOnFirstLaunch()
    }

    /// A first launch has no icon to look for and no permissions yet: open the
    /// settings once, on the calendar tab, where turning a feature on asks for access.
    private func showWelcomeOnFirstLaunch() {
        guard !settings.hasCompletedOnboarding else { return }
        settings.hasCompletedOnboarding = true
        presentSettings(tab: .calendar)
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
            systemSymbolName: "waveform",
            accessibilityDescription: "Dynamic Island"
        )

        let menu = NSMenu()

        let calendarItem = NSMenuItem(
            title: "Сегодня в календаре",
            action: #selector(showAgenda),
            keyEquivalent: "e"
        )
        calendarItem.target = self
        menu.addItem(calendarItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Настройки…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let previewItem = NSMenuItem(
            title: "Превью экрана блокировки",
            action: #selector(toggleLockPreview),
            keyEquivalent: "l"
        )
        previewItem.target = self
        menu.addItem(previewItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Завершить Dynamic Island", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        return item
    }

    /// Without calendar access the card would be empty, so the menu leads to where it is switched on.
    @objc private func showAgenda() {
        let readsEvents = settings.calendarEnabled && agenda.eventsAccess == .granted
        let readsReminders = settings.remindersEnabled && agenda.remindersAccess == .granted
        guard readsEvents || readsReminders else {
            presentSettings(tab: .calendar)
            return
        }
        model.showAgenda()
    }

    @objc private func openSettings() {
        presentSettings(tab: nil)
    }

    private func presentSettings(tab: SettingsTab?) {
        if settingsController == nil {
            settingsController = SettingsWindowController(agenda: agenda)
        }
        settingsController?.present(tab: tab)
    }

    @objc private func toggleLockPreview() {
        lockScreenController?.previewToggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
