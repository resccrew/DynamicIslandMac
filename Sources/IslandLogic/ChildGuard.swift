import Foundation

/// Wraps a helper command so it can never outlive the app.
///
/// The app spawns long-lived helpers (`perl mediaremote-adapter.pl stream`,
/// `log stream`). If the app is killed — `SIGKILL`, a crash, Force Quit — no
/// handler runs and the helper is re-parented to launchd and keeps running.
/// Neither helper reads stdin, so they cannot notice on their own.
///
/// The wrapper is a tiny `/bin/sh` script started with a *lifeline*: a pipe
/// whose write end only the app holds. The script runs the real command and a
/// watcher that blocks reading the lifeline; the kernel closes the write end
/// when the app dies for any reason, the watcher sees EOF and kills the
/// command. `SIGTERM`/`SIGINT`/`SIGHUP` sent to the wrapper (Process.terminate)
/// kill the command too, and the wrapper exits with the command's status.
public enum ChildGuard {
    /// `sh -c` body; `"$@"` is the real command.
    static let script = """
    exec 3<&0
    "$@" </dev/null &
    child=$!
    (cat <&3 >/dev/null; kill $child 2>/dev/null) &
    watcher=$!
    trap 'kill $child $watcher 2>/dev/null; exit 0' TERM INT HUP
    wait $child
    status=$?
    kill $watcher 2>/dev/null
    exit $status
    """

    /// The executable and arguments to launch instead of `executable`/`arguments`.
    /// Attach a `Pipe` as the process's standard input and keep it open for as
    /// long as the helper should live (closing its write end stops the helper).
    public static func wrap(executable: String, arguments: [String]) -> (executable: String, arguments: [String]) {
        ("/bin/sh", ["-c", script, "child-guard", executable] + arguments)
    }
}
