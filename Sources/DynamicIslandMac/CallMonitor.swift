import AppKit
import CoreAudio
import CoreMediaIO

/// An ongoing call: some known calling app has held the microphone open.
struct CallInfo: Equatable {
    let appName: String
    /// The app to bring forward (a helper's parent, e.g. Chrome for Meet).
    let bundleID: String
    let startedAt: Date
    var cameraOn: Bool
}

/// Detects calls without any call-app API: CoreAudio reports, per process,
/// whether it is capturing from an input device (macOS 14.2+), and CoreMediaIO
/// whether any camera is running.
///
/// Only a known calling app counts, and only after it has held the mic for
/// `startDelay` — Siri, dictation and voice memos also open the mic, and a
/// call app briefly probing it (settings, a mic test) is not a call. The call
/// ends after the mic has been released for `endDelay`, so a hiccup doesn't
/// flicker the island.
///
/// Polled once a second on a background queue: it is a handful of property
/// reads, and process-list listeners would still need per-process listeners
/// re-registered on every change.
final class CallMonitor {
    private let queue = DispatchQueue(label: "CallMonitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var onChange: ((CallInfo?) -> Void)?

    private static let startDelay: TimeInterval = 2
    private static let endDelay: TimeInterval = 2

    /// Touched only on `queue`.
    private var candidate: (bundleID: String, since: Date)?
    private var current: CallInfo?
    private var lastSeen = Date.distantPast

    /// Extra bundle ids treated as call apps; debug-only hook for live tests.
    /// Touched only on `queue`.
    private var extraCallApps: Set<String> = []

    func setExtraCallApps(_ bundleIDs: Set<String>) {
        queue.async { [weak self] in self?.extraCallApps = bundleIDs }
    }

    /// Bundle-id prefixes of apps whose microphone use means a call, mapped to
    /// the app that owns them. Prefixes also catch helpers
    /// (`com.google.Chrome.helper`, `com.hnc.Discord.helper.Renderer`).
    private static let callApps: [(prefix: String, owner: String)] = [
        ("ru.keepcoder.Telegram", "ru.keepcoder.Telegram"),
        ("org.telegram.desktop", "org.telegram.desktop"),
        ("com.apple.FaceTime", "com.apple.FaceTime"),
        // FaceTime and iPhone-relay calls capture in this daemon, not the app.
        ("com.apple.avconferenced", "com.apple.FaceTime"),
        ("us.zoom.xos", "us.zoom.xos"),
        ("com.hnc.Discord", "com.hnc.Discord"),
        ("net.whatsapp.WhatsApp", "net.whatsapp.WhatsApp"),
        ("desktop.WhatsApp", "desktop.WhatsApp"),
        ("com.tinyspeck.slackmacgap", "com.tinyspeck.slackmacgap"),
        ("com.microsoft.teams2", "com.microsoft.teams2"),
        ("com.microsoft.teams", "com.microsoft.teams"),
        ("com.skype.skype", "com.skype.skype"),
        ("com.viber.osx", "com.viber.osx"),
        ("org.whispersystems.signal-desktop", "org.whispersystems.signal-desktop"),
        ("com.cisco.webexmeetingsapp", "com.cisco.webexmeetingsapp"),
        // Browsers: a tab holding the mic is Meet, Discord web, Telegram web …
        ("com.google.Chrome", "com.google.Chrome"),
        ("company.thebrowser.Browser", "company.thebrowser.Browser"),
        ("com.brave.Browser", "com.brave.Browser"),
        ("com.microsoft.edgemac", "com.microsoft.edgemac"),
        ("ru.yandex.desktop.yandex-browser", "ru.yandex.desktop.yandex-browser"),
        ("com.operasoftware.Opera", "com.operasoftware.Opera"),
        ("org.mozilla.firefox", "org.mozilla.firefox"),
        ("com.apple.Safari", "com.apple.Safari"),
        // Safari captures in WebKit's GPU process.
        ("com.apple.WebKit.GPU", "com.apple.Safari"),
    ]

    /// `onChange` runs on main whenever a call starts, ends or the camera flips.
    func start(onChange: @escaping (CallInfo?) -> Void) {
        self.onChange = onChange
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    private func poll() {
        let now = Date()
        let micOwner = Self.inputProcessBundleIDs().lazy.compactMap(owner(of:)).first
        var next = current

        if let micOwner {
            lastSeen = now
            if current?.bundleID == micOwner {
                // Ongoing; only the camera can change.
            } else if let candidate, candidate.bundleID == micOwner {
                if now.timeIntervalSince(candidate.since) >= Self.startDelay {
                    next = CallInfo(
                        appName: Self.appName(micOwner),
                        bundleID: micOwner,
                        startedAt: candidate.since,
                        cameraOn: false
                    )
                }
            } else {
                candidate = (micOwner, now)
            }
        } else {
            candidate = nil
            if current != nil, now.timeIntervalSince(lastSeen) >= Self.endDelay {
                next = nil
            }
        }

        if next != nil {
            next?.cameraOn = Self.isAnyCameraRunning()
        }
        guard next != current else { return }
        current = next
        DispatchQueue.main.async { [weak self] in self?.onChange?(next) }
    }

    private func owner(of bundleID: String) -> String? {
        if extraCallApps.contains(bundleID) { return bundleID }
        return Self.callApps.first { bundleID.hasPrefix($0.prefix) }?.owner
    }

    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - CoreAudio

    /// Bundle ids of every process currently capturing audio input.
    private static func inputProcessBundleIDs() -> [String] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else {
            return []
        }

        return processes.compactMap { process in
            guard uint32(process, kAudioProcessPropertyIsRunningInput) == 1 else { return nil }
            return bundleID(of: process)
        }
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    private static func bundleID(of process: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() as String?,
              !string.isEmpty
        else { return nil }
        return string
    }

    // MARK: - CoreMediaIO

    private static func isAnyCameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else {
            return false
        }

        return devices.contains { device in
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
            )
            var value: UInt32 = 0
            var valueUsed: UInt32 = 0
            let status = CMIOObjectGetPropertyData(
                device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &valueUsed, &value
            )
            return status == noErr && value != 0
        }
    }
}
