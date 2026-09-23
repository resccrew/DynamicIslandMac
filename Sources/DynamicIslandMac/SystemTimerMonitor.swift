import Foundation

/// A countdown from the system Clock (Часы) — started in the app, by Siri or
/// by a Shortcut; they all live in the same `mobiletimerd` daemon.
struct SystemTimer: Equatable {
    let id: String
    let title: String
    let duration: TimeInterval
    /// When a running timer goes off; nil while paused.
    let fireDate: Date?
    /// Time left, frozen while paused.
    let pausedRemaining: TimeInterval?

    var isPaused: Bool { fireDate == nil }

    func remaining(at now: Date = Date()) -> TimeInterval {
        if let fireDate { return max(0, fireDate.timeIntervalSince(now)) }
        return pausedRemaining ?? duration
    }
}

/// Follows the system Clock's timers without any timer API.
///
/// `mobiletimerd` only serves entitled Apple processes (`MTTimerManager` gets
/// "not entitled" over XPC) and keeps its store in a protected group container.
/// What it does do is describe every change in the unified log — timer id,
/// state, duration, and the exact date the next alert fires — at the default
/// level, readable by any admin user. So this reads the log:
///
/// - at start, `log show` over the last day rebuilds the timers that are
///   already running or paused;
/// - then `log stream` follows changes as they happen (event-driven, no polling).
///
/// Paused timers log no remaining time, so it is derived from the last known
/// fire date and the moment of the pause. A stop with `firedDate` set is a
/// timer going off; without it, a cancel.
///
/// The log wording is Apple's private detail and may change with an update;
/// the parser fails closed (no timer shown) rather than showing a wrong one.
final class SystemTimerMonitor {
    private let queue = DispatchQueue(label: "SystemTimerMonitor", qos: .utility)
    private var onChange: (([SystemTimer]) -> Void)?
    private var onFire: ((String) -> Void)?

    /// Touched only on `queue`.
    private var timers: [String: SystemTimer] = [:]
    /// Last fire date seen per timer, kept across pauses. Touched only on `queue`.
    private var fireDates: [String: Date] = [:]
    private var stream: Process?
    private var buffer = Data()
    private var stopped = false

    private static let predicate =
        #"process == "mobiletimerd" AND category == "Timers""#

    func start(onChange: @escaping ([SystemTimer]) -> Void, onFire: @escaping (String) -> Void) {
        self.onChange = onChange
        self.onFire = onFire
        queue.async { [weak self] in
            self?.bootstrap()
            self?.startStream()
        }
    }

    /// Sends the current timers again, e.g. after a debug injection ends.
    func republish() {
        queue.async { [weak self] in self?.publish() }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopped = true
            self?.stream?.terminate()
            self?.stream = nil
        }
    }

    // MARK: - Log reading

    private func bootstrap() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["show", "--last", "1d", "--style", "ndjson", "--predicate", Self.predicate]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        for line in data.split(separator: UInt8(ascii: "\n")) {
            handle(line: Data(line), live: false)
        }
        // Anything whose alert time has passed went off while nobody watched.
        let now = Date()
        timers = timers.filter { $0.value.fireDate.map { $0 > now } ?? true }
        publish()
    }

    private func startStream() {
        guard !stopped else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "ndjson", "--predicate", Self.predicate]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            self?.queue.async { self?.consume(chunk) }
        }
        process.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            // `log` can exit on its own (e.g. after sleep); pick it back up.
            self?.queue.asyncAfter(deadline: .now() + 2) { self?.startStream() }
        }
        do {
            try process.run()
            stream = process
        } catch {
            stream = nil
        }
    }

    private func consume(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(line: Data(line), live: true)
        }
    }

    // MARK: - Parsing

    private func handle(line: Data, live: Bool) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let message = object["eventMessage"] as? String,
              let stamp = (object["timestamp"] as? String).flatMap(Self.parseTimestamp)
        else { return }

        if let trigger = Self.parseTrigger(message) {
            fireDates[trigger.id] = trigger.date
            if let timer = timers[trigger.id], !timer.isPaused {
                timers[trigger.id] = SystemTimer(
                    id: timer.id, title: timer.title, duration: timer.duration,
                    fireDate: trigger.date, pausedRemaining: nil
                )
                if live { publish() }
            }
            return
        }

        // Only the store's own change reports: the scheduler and notification
        // lines repeat the same timers with stale states.
        let states: Substring
        if let range = message.range(of: "toTimers:") {
            states = message[range.upperBound...]
        } else if message.contains("didAddTimers") {
            states = message[...]
        } else {
            return
        }

        var changed = false
        for entry in Self.parseEntries(states) {
            changed = apply(entry, at: stamp, live: live) || changed
        }
        if changed && live { publish() }
    }

    private func apply(_ entry: Entry, at stamp: Date, live: Bool) -> Bool {
        let previous = timers[entry.id]
        switch entry.state {
        case "Running":
            // A resume logs its new trigger a moment later; until then,
            // estimate from what was left.
            let known = fireDates[entry.id].flatMap { $0 > stamp ? $0 : nil }
            let estimate = stamp.addingTimeInterval(previous?.pausedRemaining ?? entry.duration)
            let fireDate = previous?.isPaused == true ? estimate : (known ?? estimate)
            timers[entry.id] = SystemTimer(
                id: entry.id, title: entry.title, duration: entry.duration,
                fireDate: fireDate, pausedRemaining: nil
            )
        case "Paused":
            let left = (previous?.fireDate ?? fireDates[entry.id])
                .map { max(0, $0.timeIntervalSince(stamp)) } ?? entry.duration
            timers[entry.id] = SystemTimer(
                id: entry.id, title: entry.title, duration: entry.duration,
                fireDate: nil, pausedRemaining: left
            )
        default:
            // Stopped: gone from the island. Went off only if it has a fire date.
            guard previous != nil else { return false }
            timers[entry.id] = nil
            fireDates[entry.id] = nil
            if live && entry.fired {
                let title = entry.title
                DispatchQueue.main.async { [weak self] in self?.onFire?(title) }
            }
        }
        return timers[entry.id] != previous
    }

    private func publish() {
        let snapshot = Array(timers.values)
        DispatchQueue.main.async { [weak self] in self?.onChange?(snapshot) }
    }

    struct Entry: Equatable {
        let id: String
        let title: String
        let state: String
        let duration: TimeInterval
        let fired: Bool
    }

    private static let entryRegex = try? NSRegularExpression(
        pattern: #"TimerID: ([0-9A-Fa-f-]{36}), Title: (.*?), state:(\w+), duration:([0-9.]+), firedDate: (\(null\)|[^,]+)"#
    )

    private static let triggerRegex = try? NSRegularExpression(
        pattern: #"([0-9A-Fa-f-]{36}) has next trigger .*?date: "([^"]+)""#
    )

    static func parseEntries(_ text: Substring) -> [Entry] {
        guard let regex = entryRegex else { return [] }
        let string = String(text)
        let range = NSRange(string.startIndex..., in: string)
        return regex.matches(in: string, range: range).compactMap { match in
            func group(_ i: Int) -> String? {
                Range(match.range(at: i), in: string).map { String(string[$0]) }
            }
            guard let id = group(1), let state = group(3),
                  let duration = group(4).flatMap(TimeInterval.init)
            else { return nil }
            // UI-started timers have an empty title; Siri's default is internal.
            let raw = group(2) ?? ""
            let title = raw == "CURRENT_TIMER" ? "" : raw
            return Entry(id: id, title: title, state: state, duration: duration,
                         fired: group(5) != "(null)")
        }
    }

    static func parseTrigger(_ message: String) -> (id: String, date: Date)? {
        guard let regex = triggerRegex,
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let idRange = Range(match.range(at: 1), in: message),
              let dateRange = Range(match.range(at: 2), in: message),
              let date = parseTriggerDate(String(message[dateRange]))
        else { return nil }
        return (String(message[idRange]), date)
    }

    /// "Wednesday, September 23, 2026 at 11:05:35 AM Central European Summer Time",
    /// with a narrow no-break space before AM/PM.
    static func parseTriggerDate(_ text: String) -> Date? {
        let cleaned = text
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        triggerFormatter.timeZone = nil
        for format in ["EEEE, MMMM d, yyyy 'at' h:mm:ss a zzzz", "EEEE, MMMM d, yyyy 'at' HH:mm:ss zzzz"] {
            triggerFormatter.dateFormat = format
            if let date = triggerFormatter.date(from: cleaned) { return date }
        }
        // Unknown zone name: the daemon logs in local time, so drop it.
        if let cut = cleaned.range(of: #" (AM|PM) "#, options: .regularExpression) {
            triggerFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm:ss a"
            triggerFormatter.timeZone = .current
            return triggerFormatter.date(from: String(cleaned[..<cut.upperBound]).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private static let triggerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// "2026-09-23 11:05:23.890190+0200"
    static func parseTimestamp(_ text: String) -> Date? {
        timestampFormatter.date(from: text)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        return formatter
    }()
}
