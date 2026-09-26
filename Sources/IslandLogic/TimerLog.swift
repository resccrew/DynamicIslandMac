import Foundation

/// A countdown from the system Clock (Часы) — started in the app, by Siri or
/// by a Shortcut; they all live in the same `mobiletimerd` daemon.
public struct TimerSnapshot: Equatable {
    public let id: String
    public let title: String
    public let duration: TimeInterval
    /// When a running timer goes off; nil while paused.
    public let fireDate: Date?
    /// Time left, frozen while paused.
    public let pausedRemaining: TimeInterval?

    public init(id: String, title: String, duration: TimeInterval, fireDate: Date?, pausedRemaining: TimeInterval?) {
        self.id = id
        self.title = title
        self.duration = duration
        self.fireDate = fireDate
        self.pausedRemaining = pausedRemaining
    }

    public var isPaused: Bool { fireDate == nil }

    public func remaining(at now: Date = Date()) -> TimeInterval {
        if let fireDate { return max(0, fireDate.timeIntervalSince(now)) }
        return pausedRemaining ?? duration
    }
}

/// Parses `mobiletimerd`'s unified-log lines. The wording is Apple's private
/// detail; every parser fails closed (nil / empty) on anything unexpected.
public enum TimerLogParser {
    public struct Entry: Equatable {
        public let id: String
        public let title: String
        public let state: String
        public let duration: TimeInterval
        public let fired: Bool

        public init(id: String, title: String, state: String, duration: TimeInterval, fired: Bool) {
            self.id = id
            self.title = title
            self.state = state
            self.duration = duration
            self.fired = fired
        }
    }

    private static let entryRegex = try? NSRegularExpression(
        pattern: #"TimerID: ([0-9A-Fa-f-]{36}), Title: (.*?), state:(\w+), duration:([0-9.]+), firedDate: (\(null\)|[^,]+)"#
    )

    private static let triggerRegex = try? NSRegularExpression(
        pattern: #"([0-9A-Fa-f-]{36}) has next trigger .*?date: "([^"]+)""#
    )

    public static func parseEntries(_ text: Substring) -> [Entry] {
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

    public static func parseTrigger(_ message: String) -> (id: String, date: Date)? {
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
    public static func parseTriggerDate(_ text: String) -> Date? {
        let cleaned = text
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        // A fresh formatter per call: callers may be on any queue.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEEE, MMMM d, yyyy 'at' h:mm:ss a zzzz", "EEEE, MMMM d, yyyy 'at' HH:mm:ss zzzz"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) { return date }
        }
        // Unknown zone name: the daemon logs in local time, so drop it.
        guard let cut = cleaned.range(of: #" (AM|PM) "#, options: .regularExpression) else { return nil }
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm:ss a"
        formatter.timeZone = .current
        return formatter.date(from: String(cleaned[..<cut.upperBound]).trimmingCharacters(in: .whitespaces))
    }

    /// "2026-09-23 11:05:23.890190+0200"
    public static func parseTimestamp(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        return formatter.date(from: text)
    }
}

/// The timers the log describes, rebuilt line by line. Not thread-safe; the
/// owner confines it to one queue.
public struct TimerLogStore {
    public struct Outcome: Equatable {
        /// The visible set of timers changed.
        public var changed = false
        /// Titles of timers that went off (not cancelled).
        public var fired: [String] = []
    }

    public private(set) var timers: [String: TimerSnapshot] = [:]
    /// Last fire date seen per timer, kept across pauses.
    private var fireDates: [String: Date] = [:]

    public init() {}

    /// Feeds one log message stamped `stamp`.
    public mutating func handle(message: String, at stamp: Date) -> Outcome {
        var outcome = Outcome()
        if let trigger = TimerLogParser.parseTrigger(message) {
            fireDates[trigger.id] = trigger.date
            if let timer = timers[trigger.id], !timer.isPaused {
                timers[trigger.id] = TimerSnapshot(
                    id: timer.id, title: timer.title, duration: timer.duration,
                    fireDate: trigger.date, pausedRemaining: nil
                )
                outcome.changed = true
            }
            return outcome
        }

        // Only the store's own change reports: the scheduler and notification
        // lines repeat the same timers with stale states.
        let states: Substring
        if let range = message.range(of: "toTimers:") {
            states = message[range.upperBound...]
        } else if message.contains("didAddTimers") {
            states = message[...]
        } else {
            return outcome
        }

        for entry in TimerLogParser.parseEntries(states) {
            let previous = timers[entry.id]
            apply(entry, at: stamp, outcome: &outcome)
            if timers[entry.id] != previous { outcome.changed = true }
        }
        return outcome
    }

    /// Drops timers whose alert time has passed (went off while unobserved).
    public mutating func dropExpired(now: Date) {
        timers = timers.filter { $0.value.fireDate.map { $0 > now } ?? true }
    }

    private mutating func apply(_ entry: TimerLogParser.Entry, at stamp: Date, outcome: inout Outcome) {
        let previous = timers[entry.id]
        switch entry.state {
        case "Running":
            // A resume logs its new trigger a moment later; until then,
            // estimate from what was left.
            let known = fireDates[entry.id].flatMap { $0 > stamp ? $0 : nil }
            let estimate = stamp.addingTimeInterval(previous?.pausedRemaining ?? entry.duration)
            let fireDate = previous?.isPaused == true ? estimate : (known ?? estimate)
            timers[entry.id] = TimerSnapshot(
                id: entry.id, title: entry.title, duration: entry.duration,
                fireDate: fireDate, pausedRemaining: nil
            )
        case "Paused":
            let left = (previous?.fireDate ?? fireDates[entry.id])
                .map { max(0, $0.timeIntervalSince(stamp)) } ?? entry.duration
            timers[entry.id] = TimerSnapshot(
                id: entry.id, title: entry.title, duration: entry.duration,
                fireDate: nil, pausedRemaining: left
            )
        default:
            // Stopped: gone from the island. Went off only if it has a fire date.
            guard previous != nil else { return }
            timers[entry.id] = nil
            fireDates[entry.id] = nil
            if entry.fired { outcome.fired.append(entry.title) }
        }
    }
}

/// Exponential backoff for restarting a helper process that keeps dying.
public struct TimerRestartBackoff {
    public let base: TimeInterval
    public let maxDelay: TimeInterval
    public let maxFailures: Int
    public private(set) var failures = 0

    public init(base: TimeInterval = 2, maxDelay: TimeInterval = 300, maxFailures: Int = 8) {
        self.base = base
        self.maxDelay = maxDelay
        self.maxFailures = maxFailures
    }

    /// A run that produced output: the helper works, start over.
    public mutating func succeeded() { failures = 0 }

    /// Records a death without output; nil means give up.
    public mutating func failed() -> TimeInterval? {
        failures += 1
        guard failures < maxFailures else { return nil }
        return min(maxDelay, base * pow(2, Double(failures - 1)))
    }
}
