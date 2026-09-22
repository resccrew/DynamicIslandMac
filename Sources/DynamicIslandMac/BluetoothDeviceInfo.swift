import Foundation

/// Looks up the exact hardware model and battery level for a paired Bluetooth
/// device, via `system_profiler SPBluetoothDataType`.
///
/// Apple exposes no public API for either of these for arbitrary Bluetooth
/// audio gear. `system_profiler` is Apple's own supported command-line tool
/// for hardware reporting and is what it uses to fill in the same details in
/// About This Mac, so this is the sanctioned way to get them rather than a
/// private framework or a reverse-engineered file path.
enum BluetoothDeviceInfo {
    struct Info {
        let productID: String?
        /// 0...1, the lower of the two earbuds when both are known.
        let batteryLevel: Double?
    }

    static func lookup(deviceName: String, completion: @escaping (Info?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            completion(run(deviceName: deviceName))
        }
    }

    private static func run(deviceName: String) -> Info? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-xml"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let sections = plist as? [[String: Any]],
            let items = sections.first?["_items"] as? [[String: Any]]
        else { return nil }

        // Connected and previously-paired devices are two separate groups.
        let groups = ["device_connected", "device_not_connected"]
        for section in items {
            for key in groups {
                guard let entries = section[key] as? [[String: Any]] else { continue }
                for entry in entries {
                    for (name, value) in entry {
                        guard matches(name, deviceName), let fields = value as? [String: Any] else {
                            continue
                        }
                        return Info(
                            productID: fields["device_productID"] as? String,
                            batteryLevel: batteryLevel(from: fields)
                        )
                    }
                }
            }
        }
        return nil
    }

    /// CoreAudio and system_profiler both report the user's personalised name
    /// ("AirPods (Nik)"), so this is usually exact — the loose match is only a
    /// safety net for minor formatting differences.
    private static func matches(_ profilerName: String, _ audioName: String) -> Bool {
        let a = profilerName.trimmingCharacters(in: .whitespaces).lowercased()
        let b = audioName.trimmingCharacters(in: .whitespaces).lowercased()
        return a == b || a.contains(b) || b.contains(a)
    }

    private static func batteryLevel(from fields: [String: Any]) -> Double? {
        let keys = ["device_batteryLevelLeft", "device_batteryLevelRight", "device_batteryLevel"]
        let levels = keys.compactMap { fields[$0] as? String }.compactMap(parsePercent)
        return levels.min()
    }

    /// Values look like "96 %".
    private static func parsePercent(_ value: String) -> Double? {
        let digits = value.filter { $0.isNumber }
        guard let percent = Double(digits) else { return nil }
        return percent / 100
    }
}

/// Maps a Bluetooth Product ID to the matching SF Symbol.
///
/// The advertised device name alone cannot tell an AirPods (3rd gen) from a
/// 1st/2nd gen pair — Apple doesn't put the generation in the name — but the
/// Product ID does. These values are a factual hardware identifier table, the
/// same kind of public interoperability data as a USB vendor/product ID list,
/// confirmed here directly against this Mac's own paired-device list.
enum AirPodsModel {
    private static let symbolsByProductID: [String: String] = [
        "0x2002": "airpods",       // AirPods (1st generation)
        "0x200F": "airpods",       // AirPods (2nd generation)
        "0x2013": "airpods.gen3",  // AirPods (3rd generation)
        "0x200E": "airpods.pro",   // AirPods Pro
        "0x2014": "airpods.pro",   // AirPods Pro (2nd generation, Lightning)
        "0x2024": "airpods.pro",   // AirPods Pro (2nd generation, USB-C)
        "0x2027": "airpods.pro",   // AirPods Pro (2nd generation, later revision)
        "0x200A": "airpods.max",   // AirPods Max
        "0x201F": "airpods.max",   // AirPods Max (USB-C)
        "0x2005": "beats.headphones",
    ]

    static func symbol(productID: String?, fallback: String) -> String {
        guard let productID else { return fallback }
        return symbolsByProductID[productID] ?? fallback
    }
}
