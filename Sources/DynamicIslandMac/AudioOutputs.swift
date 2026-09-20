import AppKit
import CoreAudio

/// Lists and switches the system audio output.
///
/// The real AirPlay picker is Control Center's and is not scriptable, but the
/// default output device itself is settable through CoreAudio — which is what
/// that picker ultimately does.
enum AudioOutputs {
    struct Device {
        let id: AudioDeviceID
        let name: String
    }

    static func available() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasOutput(id), let name = name(of: id), !name.isEmpty else { return nil }
            return Device(id: id, name: name)
        }
    }

    static func current() -> AudioDeviceID {
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

    @discardableResult
    static func setDefault(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = device
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &value
        ) == noErr
    }

    /// Only devices that can actually play audio belong in the list; inputs and
    /// aggregate oddities would just be noise.
    private static func hasOutput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size > 0 else { return false }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }

        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else {
            return false
        }

        let list = UnsafeMutableAudioBufferListPointer(
            buffer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func name(of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else {
            return nil
        }
        return name as String
    }

    /// Pops the device list under the button. Built as an `NSMenu` on purpose:
    /// the island's panel never becomes key, so a SwiftUI popover would have no
    /// window to attach to.
    static func showPicker() {
        let devices = available()
        guard !devices.isEmpty else { return }

        let active = current()
        let menu = NSMenu()

        for device in devices {
            let item = NSMenuItem(
                title: device.name,
                action: #selector(MenuTarget.pick(_:)),
                keyEquivalent: ""
            )
            item.target = MenuTarget.shared
            item.representedObject = device.id
            item.state = device.id == active ? .on : .off
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private final class MenuTarget: NSObject {
        static let shared = MenuTarget()

        @objc func pick(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? AudioDeviceID else { return }
            AudioOutputs.setDefault(id)
        }
    }
}
