import XCTest
@testable import IslandLogic

final class AppDisplayNameTests: XCTestCase {
    func testInstalledNameWins() {
        XCTAssertEqual(AppDisplayName.resolve(bundleID: "us.zoom.xos", localized: "zoom.us"), "zoom.us")
    }

    func testKnownTableWhenNotInstalled() {
        let expected = [
            "us.zoom.xos": "Zoom", "com.microsoft.teams2": "Teams", "com.hnc.Discord": "Discord",
            "ru.keepcoder.Telegram": "Telegram", "com.apple.FaceTime": "FaceTime",
            "net.whatsapp.WhatsApp": "WhatsApp",
        ]
        for (id, name) in expected {
            XCTAssertEqual(AppDisplayName.resolve(bundleID: id, localized: nil), name, id)
        }
    }

    func testBlankInstalledNameFallsThrough() {
        XCTAssertEqual(AppDisplayName.resolve(bundleID: "us.zoom.xos", localized: "  "), "Zoom")
    }

    func testUnknownUsesLastMeaningfulComponentCapitalised() {
        XCTAssertEqual(AppDisplayName.resolve(bundleID: "com.example.superchat", localized: nil), "Superchat")
        XCTAssertEqual(AppDisplayName.resolve(bundleID: "org.foo.bar.helper", localized: nil), "Bar")
        XCTAssertEqual(AppDisplayName.resolve(bundleID: "us.acme.xos", localized: nil), "Acme")
    }

    func testNeverEmptyOrRawSuffixForKnownApps() {
        for id in AppDisplayName.known.keys {
            let name = AppDisplayName.resolve(bundleID: id, localized: nil)
            XCTAssertFalse(name.isEmpty)
            XCTAssertNotEqual(name.lowercased(), "xos")
        }
        XCTAssertEqual(AppDisplayName.resolve(bundleID: "x", localized: nil), "X")
    }
}

final class ChildGuardTests: XCTestCase {
    func testWrapKeepsTheCommandIntact() {
        let wrapped = ChildGuard.wrap(executable: "/usr/bin/perl", arguments: ["a b", "--x=1"])
        XCTAssertEqual(wrapped.executable, "/bin/sh")
        XCTAssertEqual(wrapped.arguments.prefix(2).first, "-c")
        XCTAssertEqual(Array(wrapped.arguments.suffix(3)), ["/usr/bin/perl", "a b", "--x=1"])
    }

    /// Starts `sleep` through the guard and returns the wrapper, its lifeline and the sleeper's pid.
    private func startGuardedSleeper() throws -> (process: Process, lifeline: Pipe, pid: pid_t) {
        let command = ChildGuard.wrap(
            executable: "/bin/sh",
            arguments: ["-c", "echo $$; exec sleep 60"]
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        let lifeline = Pipe()
        let output = Pipe()
        process.standardInput = lifeline
        process.standardOutput = output
        try process.run()
        // The child prints its own pid first; `exec` keeps that pid for `sleep`.
        var line = Data()
        while !line.contains(UInt8(ascii: "\n")) {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            line.append(chunk)
        }
        let text = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try XCTUnwrap(pid_t(text))
        return (process, lifeline, pid)
    }

    private func waitUntilGone(_ pid: pid_t, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    func testChildDiesWhenTheLifelineCloses() throws {
        let started = try startGuardedSleeper()
        XCTAssertEqual(kill(started.pid, 0), 0, "child should be running")
        // What the kernel does when the app is killed: the write end closes.
        try started.lifeline.fileHandleForWriting.close()
        XCTAssertTrue(waitUntilGone(started.pid), "child outlived its lifeline")
        started.process.waitUntilExit()
    }

    func testChildDiesWhenTheWrapperIsTerminated() throws {
        let started = try startGuardedSleeper()
        started.process.terminate()
        XCTAssertTrue(waitUntilGone(started.pid), "child outlived a terminated wrapper")
        started.process.waitUntilExit()
        try? started.lifeline.fileHandleForWriting.close()
    }
}
