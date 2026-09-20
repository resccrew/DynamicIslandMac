import AppKit
import CoreAudio
import IOKit.ps

/// What just happened to the hardware, ready to be shown in the island.
struct DeviceNotice: Equatable, Hashable {
    enum Kind: Equatable, Hashable {
        case audioConnected
        case powerConnected
        case powerDisconnected
    }

    let kind: Kind
    let title: String
    /// 0...1 when a battery level is known.
    let level: Double?
    let symbol: String
}

/// Watches for the charger and for audio devices coming and going.
///
/// Both are event-driven — a run-loop source for power, a CoreAudio property
/// listener for output devices — so nothing is polled and the app stays idle
/// until something actually changes.
final class DeviceMonitors {
    private var onNotice: ((DeviceNotice) -> Void)?
    private var powerSource: CFRunLoopSource?
    private var lastPluggedIn: Bool?
    private var lastOutputDeviceID: AudioDeviceID = 0

    func start(onNotice: @escaping (DeviceNotice) -> Void) {
        self.onNotice = onNotice
        lastPluggedIn = Self.isPluggedIn()
        lastOutputDeviceID = Self.defaultOutputDevice()
        startPowerWatch()
        startAudioWatch()
    }

    // MARK: - Power

    private func startPowerWatch() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<DeviceMonitors>.fromOpaque(context).takeUnretainedValue()
            monitor.powerChanged()
        }, context)?.takeRetainedValue() else { return }

        powerSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func powerChanged() {
        let plugged = Self.isPluggedIn()
        // The source also fires on every percentage tick; only the plug matters.
        guard plugged != lastPluggedIn else { return }
        lastPluggedIn = plugged

        let level = Self.batteryLevel()
        onNotice?(DeviceNotice(
            kind: plugged ? .powerConnected : .powerDisconnected,
            title: plugged ? "Зарядка" : "От батареи",
            level: level,
            symbol: plugged ? "bolt.fill" : "battery.50"
        ))
    }

    static func isPluggedIn() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        return IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
            == kIOPMACPowerKey
    }

    static func batteryLevel() -> Double? {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in list {
            guard
                let info = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
                let current = info[kIOPSCurrentCapacityKey] as? Int,
                let max = info[kIOPSMaxCapacityKey] as? Int,
                max > 0
            else { continue }
            return Double(current) / Double(max)
        }
        return nil
    }

    // MARK: - Audio output

    private func startAudioWatch() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.outputDeviceChanged()
        }
    }

    private func outputDeviceChanged() {
        let device = Self.defaultOutputDevice()
        guard device != lastOutputDeviceID, device != 0 else { return }
        lastOutputDeviceID = device

        let name = Self.deviceName(device)
        // Built-in speakers are not an event worth announcing.
        guard !name.isEmpty, !Self.isBuiltIn(device) else { return }

        let fallbackSymbol = Self.symbol(for: name)

        // system_profiler takes a beat, so this stays off the CoreAudio
        // callback's thread; the notice is posted once the lookup returns.
        BluetoothDeviceInfo.lookup(deviceName: name) { [weak self] info in
            guard let self, self.lastOutputDeviceID == device else { return }
            DispatchQueue.main.async {
                self.onNotice?(DeviceNotice(
                    kind: .audioConnected,
                    title: name,
                    level: info?.batteryLevel,
                    symbol: AirPodsModel.symbol(productID: info?.productID, fallback: fallbackSymbol)
                ))
            }
        }
    }

    static func defaultOutputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return device
    }

    private static func deviceName(_ device: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        return status == noErr ? (name as String) : ""
    }

    private static func isBuiltIn(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
        return transport == kAudioDeviceTransportTypeBuiltIn
    }

    /// SF Symbols ship Apple's own AirPods glyphs — official, documented, and
    /// immune to macOS moving its private asset paths around. Renders in the
    /// system's own multicolor style, one line, no private frameworks involved.
    private static func symbol(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpods.max" }
        if lower.contains("airpods pro") { return "airpods.pro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    deinit {
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
        }
    }
}
