import AppKit
import SwiftUI
import Combine

/// Draws the Now Playing card over the macOS lock screen.
///
/// There is no lock-screen widget API on macOS, but the lock screen is just a
/// full-screen shielding window: a borderless window placed at
/// `CGShieldingWindowLevel()` composites above it. The app keeps running while
/// the session is locked, so it only needs to know when to show itself, which
/// `com.apple.screenIsLocked` / `…Unlocked` provide.
/// Must never take key status: the password field has to keep keyboard focus,
/// and a window that grabs it over the lock screen gets suppressed by the
/// system. Clicks still arrive because the hosting view accepts first mouse.
private final class LockScreenWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class LockHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class LockScreenWindowController: NSWindowController {
    private let model: IslandViewModel
    private let settings = IslandSettings.shared
    private var cancellables = Set<AnyCancellable>()
    private let sleepBlocker = DisplaySleepBlocker()

    init(model: IslandViewModel) {
        self.model = model

        let screenFrame = NSScreen.main?.frame ?? .zero
        let window = LockScreenWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        // Never pull the app forward; the lock screen must stay in charge.
        window.hidesOnDeactivate = false
        // Visibility over the lock screen comes from the SkyLight space, not
        // from this level; it only keeps the window above ordinary app windows.
        window.level = NSWindow.Level(rawValue: Int(Int32.max - 2))
        window.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.contentView = LockHostingView(
            rootView: LockScreenView(model: model, settings: settings)
        )

        observeLockState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The distributed notification is the fast path, but it is not guaranteed to
    /// arrive, so the authoritative lock flag is polled as well.
    private var lockPoll: Timer?
    private var wasLocked = false

    private func startLockPolling() {
        lockPoll = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let locked = Self.screenIsLocked()

            if locked != self.wasLocked {
                self.wasLocked = locked
                Self.log("poll detected locked=\(locked)")
                locked ? self.screenLocked() : self.screenUnlocked()
                return
            }

            // loginwindow re-orders itself as it settles, so keep reclaiming the
            // top spot for as long as the screen stays locked.
            if locked, self.settings.lockScreenEnabled, self.model.hasContent,
               let window = self.window {
                window.orderFrontRegardless()
                SkyLightSpace.add(window)
            }
        }
    }

    static func screenIsLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return info["CGSSessionScreenIsLocked"] as? Int == 1
    }

    private func observeLockState() {
        startLockPolling()
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self,
            selector: #selector(screenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    @objc private func screenLocked() {
        Self.log("screenIsLocked enabled=\(settings.lockScreenEnabled) hasContent=\(model.hasContent) title=\(model.title)")
        if settings.preventSleepOnLock {
            sleepBlocker.begin(minutes: settings.preventSleepMinutes)
        }

        guard settings.lockScreenEnabled else { return }
        model.isLockScreenVisible = true
        model.resetLockScreenPresentation()
        resizeToScreen()
        window?.orderFrontRegardless()
        // The window must exist on screen before it can be moved between spaces.
        if let window {
            SkyLightSpace.add(window)
        }
        Self.log("ordered front level=\(window?.level.rawValue ?? -1) visible=\(window?.isVisible ?? false) sky=\(SkyLightSpace.prepare())")
    }

    @objc private func screenUnlocked() {
        Self.log("screenIsUnlocked")
        model.isLockScreenVisible = false
        sleepBlocker.end()
        window?.orderOut(nil)
    }

    static func log(_ message: String) {
        let line = "\(Date()) \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/island-lock.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Shows the overlay without locking, for checking the layout.
    func previewToggle() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            model.resetLockScreenPresentation()
            resizeToScreen()
            window.orderFrontRegardless()
        }
    }

    private func resizeToScreen() {
        guard let window, let screen = NSScreen.main else { return }
        window.setFrame(screen.frame, display: true)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
