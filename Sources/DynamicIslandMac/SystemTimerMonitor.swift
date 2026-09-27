import Foundation
import IslandLogic

/// Kept under its old name for the rest of the app; the parsing and state
/// rules live in `IslandLogic` so they can be unit-tested.
typealias SystemTimer = TimerSnapshot

/// Follows the system Clock's timers without any timer API.
///
/// `mobiletimerd` only serves entitled Apple processes (`MTTimerManager` gets
/// "not entitled" over XPC) and keeps its store in a protected group container.
/// What it does do is describe every change in the unified log — timer id,
/// state, duration, and the exact date the next alert fires — at the default
/// level, readable by any admin user. So this reads the log:
///
/// - at start, `log show` over the last 12 hours rebuilds the timers that are
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
    private var store = TimerLogStore()
    /// Restarts of a `log stream` that keeps dying without output back off
    /// and eventually stop, instead of respawning every 2s forever.
    private var backoff = TimerRestartBackoff()
    private var stream: Process?
    /// See `SystemNowPlaying.lifeline`: closing it, or the app dying, ends `log stream`.
    private var lifeline: Pipe?
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
        queue.async { [weak self] in self?.shutDown() }
    }

    /// Ends `log stream` before returning, for `applicationWillTerminate`.
    func stopAndWait() {
        // Bounded: if the queue is busy (the timer bootstrap reads the log for
        // a second or two) the app exits anyway and the lifeline closes with it.
        let done = DispatchSemaphore(value: 0)
        queue.async { [weak self] in
            self?.shutDown()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
    }

    private func shutDown() {
        stopped = true
        closeLifeline()
        stream?.terminate()
        stream = nil
    }

    private func closeLifeline() {
        try? lifeline?.fileHandleForWriting.close()
        lifeline = nil
    }

    // MARK: - Log reading

    private func bootstrap() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["show", "--last", "12h", "--style", "ndjson", "--predicate", Self.predicate]
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
        store.dropExpired(now: Date())
        publish()
    }

    private func startStream() {
        guard !stopped else { return }
        let process = Process()
        let command = ChildGuard.wrap(
            executable: "/usr/bin/log",
            arguments: ["stream", "--style", "ndjson", "--predicate", Self.predicate]
        )
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        closeLifeline()
        let lifeline = Pipe()
        self.lifeline = lifeline
        process.standardInput = lifeline
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // Touched only on `queue`.
        var sawOutput = false
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.queue.async {
                if !sawOutput {
                    sawOutput = true
                    self?.backoff.succeeded()
                }
                self?.consume(chunk)
            }
        }
        process.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            // `log` can exit on its own (e.g. after sleep); pick it back up.
            self?.queue.async { self?.scheduleRestart(sawOutput: sawOutput) }
        }
        do {
            try process.run()
            stream = process
        } catch {
            stream = nil
            scheduleRestart(sawOutput: false)
        }
    }

    private func scheduleRestart(sawOutput: Bool) {
        guard !stopped else { return }
        stream = nil
        closeLifeline()
        buffer.removeAll()
        if sawOutput { backoff.succeeded() }
        // A stream that ran fine and then exited restarts at the base delay.
        guard let delay = sawOutput ? backoff.base : backoff.failed() else { return }
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.startStream() }
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
              let stamp = (object["timestamp"] as? String).flatMap(TimerLogParser.parseTimestamp)
        else { return }

        let outcome = store.handle(message: message, at: stamp)
        guard live else { return }
        for title in outcome.fired {
            DispatchQueue.main.async { [weak self] in self?.onFire?(title) }
        }
        if outcome.changed { publish() }
    }

    private func publish() {
        let snapshot = Array(store.timers.values)
        DispatchQueue.main.async { [weak self] in self?.onChange?(snapshot) }
    }
}
