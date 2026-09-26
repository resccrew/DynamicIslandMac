import Foundation

/// Clock-style durations for track progress, call length and timers.
public enum FormatTime {
    /// `m:ss` under an hour, `h:mm:ss` from an hour on (1:02:05, not 62:05).
    /// Truncates to whole seconds; negative or non-finite input reads 0:00.
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        return clock(wholeSeconds: Int(seconds))
    }

    /// Elapsed and remaining for a progress bar, rounded together so they
    /// always add up to the track's length: 200 s at 0 reads 0:00 / 3:20.
    public static func playback(position: Double, duration: Double) -> (elapsed: String, remaining: String) {
        guard duration.isFinite, duration > 0 else { return (clock(position), "0:00") }
        let total = Int(duration.rounded())
        let elapsed = position.isFinite ? min(total, max(0, Int(position))) : 0
        return (clock(wholeSeconds: elapsed), clock(wholeSeconds: total - elapsed))
    }

    private static func clock(wholeSeconds total: Int) -> String {
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
