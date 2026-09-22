import AppKit

/// System-wide Now Playing: whatever macOS itself shows in Control Center —
/// Spotify and Music, but also any browser tab playing a `<video>`/`<audio>`
/// (YouTube, SoundCloud, Twitch, VK, Яндекс Музыка …) or any other media app.
///
/// MediaRemote answers only entitled processes since macOS 15.4, so it is
/// read through the vendored mediaremote-adapter: `/usr/bin/perl` (Apple-signed,
/// still entitled) loads a small framework and streams JSON, one full state
/// per line. The stream is event-driven; nothing is polled here.
final class SystemNowPlaying {
    struct Info {
        let title: String
        let artist: String
        let album: String
        let isPlaying: Bool
        /// Elapsed time as of `timestamp`; extrapolate with the wall clock.
        let elapsed: Double
        let timestamp: Date
        /// Nil for live streams (the adapter drops an infinite duration).
        let duration: Double?
        let bundleID: String?
        let artworkData: Data?
    }

    /// MRCommand ids understood by `send`.
    enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private static let perl = "/usr/bin/perl"

    private let scriptPath: String
    private let frameworkPath: String
    private let queue = DispatchQueue(label: "SystemNowPlaying", qos: .utility)
    private var process: Process?
    private var buffer = Data()
    private var onUpdate: ((Info?) -> Void)?
    private var stopped = false
    /// Consecutive stream deaths without a single line of output; past a few,
    /// the adapter is treated as broken and the caller falls back.
    private var failedStarts = 0
    var onFailure: (() -> Void)?

    /// Nil outside a bundled .app (e.g. `swift run`), where the adapter isn't
    /// packaged; the caller then stays on AppleScript.
    init?() {
        guard
            let script = Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl"),
            let frameworks = Bundle.main.privateFrameworksPath
        else { return nil }
        let framework = (frameworks as NSString).appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: framework) else { return nil }
        scriptPath = script
        frameworkPath = framework
    }

    /// `onUpdate` runs on a background queue; nil means nothing is playing anywhere.
    func start(onUpdate: @escaping (Info?) -> Void) {
        self.onUpdate = onUpdate
        queue.async { [weak self] in self?.launch() }
    }

    func send(_ command: Command) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.perl)
        process.arguments = [scriptPath, frameworkPath, "send", String(command.rawValue)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopped = true
            self?.process?.terminate()
        }
    }

    // MARK: - Stream

    private func launch() {
        guard !stopped else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.perl)
        process.arguments = [scriptPath, frameworkPath, "stream", "--no-diff", "--debounce=100", "--allow-missing-title"]
        let pipe = Pipe()
        process.standardOutput = pipe
        // Live streams make the adapter warn on every update; nothing to read.
        process.standardError = FileHandle.nullDevice

        var sawOutput = false
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.queue.async {
                if !sawOutput {
                    sawOutput = true
                    self?.failedStarts = 0
                }
                self?.consume(chunk)
            }
        }
        process.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            self?.queue.async { self?.restart(sawOutput: sawOutput) }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            restart(sawOutput: false)
        }
    }

    private func restart(sawOutput: Bool) {
        guard !stopped else { return }
        process = nil
        buffer.removeAll()
        if !sawOutput { failedStarts += 1 }
        guard failedStarts < 3 else {
            stopped = true
            DispatchQueue.main.async { [weak self] in self?.onFailure?() }
            return
        }
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.launch() }
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        let newline = UInt8(ascii: "\n")
        while let end = buffer.firstIndex(of: newline) {
            let line = buffer[buffer.startIndex..<end]
            buffer.removeSubrange(buffer.startIndex...end)
            guard let info = Self.parse(line) else { continue }
            onUpdate?(info.value)
        }
    }

    /// Wraps the parsed value so "nothing playing" (a valid, empty payload) is
    /// distinguishable from a line that couldn't be read.
    private struct Parsed { let value: Info? }

    private static let dateFormatter: ISO8601DateFormatter = ISO8601DateFormatter()

    private static func parse(_ line: Data) -> Parsed? {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            object["type"] as? String == "data"
        else { return nil }
        guard let payload = object["payload"] as? [String: Any], !payload.isEmpty else {
            return Parsed(value: nil)
        }

        let timestamp = (payload["timestamp"] as? String).flatMap(dateFormatter.date(from:)) ?? Date()
        let duration = (payload["duration"] as? Double).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return Parsed(value: Info(
            title: payload["title"] as? String ?? "",
            artist: payload["artist"] as? String ?? "",
            album: payload["album"] as? String ?? "",
            isPlaying: payload["playing"] as? Bool ?? false,
            elapsed: payload["elapsedTime"] as? Double ?? 0,
            timestamp: timestamp,
            duration: duration,
            bundleID: payload["bundleIdentifier"] as? String,
            artworkData: (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
        ))
    }
}
