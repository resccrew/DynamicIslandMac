import Foundation

public struct LyricLine: Equatable {
    public let time: Double
    public let text: String

    public init(time: Double, text: String) {
        self.time = time
        self.text = text
    }
}

public enum LyricsParser {
    /// Parses `[mm:ss.cc] text` lines. A stamp may repeat on one line, and lines
    /// with no text mark instrumental gaps, which are kept so the highlight can
    /// rest on them instead of hanging on the previous lyric. Lines without a
    /// valid stamp (metadata tags like `[ar:…]`, junk) are skipped.
    public static func parse(_ lrc: String) -> [LyricLine] {
        var result: [LyricLine] = []

        // `isNewline`, not "\n": Swift reads "\r\n" as one Character, so a
        // CRLF file would otherwise come back as a single line.
        for raw in lrc.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw)
            var stamps: [Double] = []
            var rest = Substring(line)

            while rest.hasPrefix("["),
                  let close = rest.firstIndex(of: "]") {
                let body = rest[rest.index(after: rest.startIndex)..<close]
                let parts = body.split(separator: ":")
                if parts.count == 2,
                   let minutes = Double(parts[0]),
                   let seconds = Double(parts[1]),
                   minutes >= 0, seconds >= 0 {
                    stamps.append(minutes * 60 + seconds)
                }
                rest = rest[rest.index(after: close)...]
            }

            guard !stamps.isEmpty else { continue }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for stamp in stamps {
                result.append(LyricLine(time: stamp, text: text))
            }
        }

        return result.sorted { $0.time < $1.time }
    }

    /// Index of the candidate whose duration is closest to `duration`, or nil
    /// when there are none. Different releases of a song carry different
    /// timings, and a mismatched one drifts out of sync. Missing durations
    /// count as 0, so they only win when nothing better exists.
    public static func closestDurationIndex(_ durations: [Double?], to duration: Double) -> Int? {
        durations.indices.min { abs((durations[$0] ?? 0) - duration) < abs((durations[$1] ?? 0) - duration) }
    }
}
