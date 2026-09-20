import Foundation

/// Watches Claude Code's own local session logs to show whether it's working
/// right now, and how many tool calls it has made in the current turn.
///
/// There is no public API for this — Claude Code writes its transcript as
/// JSONL under `~/.claude/projects/**/*.jsonl` purely for its own use. This
/// reads only line *shapes* (message role, content block types) to derive two
/// numbers; it never looks at the actual prompt or response text, so nothing
/// from the conversation ends up on screen. Being undocumented, the format can
/// change with any Claude Code update — every parse step fails soft (no crash,
/// just "nothing to show") rather than assuming the shape holds.
final class ClaudeAgentMonitor {
    struct Status: Equatable {
        let isActive: Bool
        let toolCallCount: Int
    }

    private var timer: Timer?
    private var lastSeenPath: String?
    private var lastSeenMTime: Date?
    private var lastStatus: Status?

    /// How recently the log must have been touched to count as "working".
    private static let activeWindow: TimeInterval = 6
    private static let pollInterval: TimeInterval = 2
    /// Enough to cover a long tool-heavy turn without reading a multi-GB
    /// transcript from the start every poll.
    private static let tailBytes = 400_000

    func start(onChange: @escaping (Status?) -> Void) {
        poll(onChange: onChange)
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll(onChange: onChange)
        }
    }

    private func poll(onChange: @escaping (Status?) -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let status = self.computeStatus()
            DispatchQueue.main.async {
                guard status != self.lastStatus else { return }
                self.lastStatus = status
                onChange(status)
            }
        }
    }

    private func computeStatus() -> Status? {
        guard let (path, mtime) = mostRecentlyModifiedSession() else { return nil }

        let isActive = Date().timeIntervalSince(mtime) < Self.activeWindow
        guard isActive else { return Status(isActive: false, toolCallCount: 0) }

        let count = toolCallCountInCurrentTurn(path: path)
        return Status(isActive: true, toolCallCount: count)
    }

    /// Any project's transcript could be the one an open terminal is currently
    /// writing to, so all of them are checked rather than a fixed path.
    private func mostRecentlyModifiedSession() -> (path: String, mtime: Date)? {
        let fm = FileManager.default
        let root = NSString(string: "~/.claude/projects").expandingTildeInPath

        guard let projectDirs = try? fm.contentsOfDirectory(atPath: root) else { return nil }

        var best: (String, Date)?
        for dir in projectDirs {
            let dirPath = "\(root)/\(dir)"
            guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let filePath = "\(dirPath)/\(file)"
                guard
                    let attrs = try? fm.attributesOfItem(atPath: filePath),
                    let mtime = attrs[.modificationDate] as? Date
                else { continue }
                if best == nil || mtime > best!.1 {
                    best = (filePath, mtime)
                }
            }
        }
        return best
    }

    /// Walks backward from the end of the file: each assistant `tool_use`
    /// block adds to the count, and hitting a real user turn (as opposed to an
    /// auto-injected tool result) marks the start of it and stops the scan.
    private func toolCallCountInCurrentTurn(path: String) -> Int {
        guard let handle = FileHandle(forReadingAtPath: path) else { return 0 }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(Self.tailBytes) ? size - UInt64(Self.tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else {
            return 0
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        var count = 0

        for line in lines.reversed() {
            guard
                let lineData = line.data(using: .utf8),
                let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let message = entry["message"] as? [String: Any],
                let blocks = message["content"] as? [[String: Any]]
            else { continue }

            let blockTypes = blocks.compactMap { $0["type"] as? String }

            switch entry["type"] as? String {
            case "assistant":
                count += blockTypes.filter { $0 == "tool_use" }.count
            case "user":
                // A user entry whose only content is a tool result is the
                // harness feeding a result back in, not a new human turn.
                if blockTypes != ["tool_result"] {
                    return count
                }
            default:
                continue
            }
        }
        return count
    }

    deinit {
        timer?.invalidate()
    }
}
