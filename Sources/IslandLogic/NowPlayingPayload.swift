import Foundation

/// One state from mediaremote-adapter's JSON stream.
public struct NowPlayingInfo: Equatable {
    public let title: String
    public let artist: String
    public let album: String
    public let isPlaying: Bool
    /// Elapsed time as of `timestamp`; extrapolate with the wall clock.
    public let elapsed: Double
    public let timestamp: Date
    /// Nil for live streams (the adapter drops an infinite duration).
    public let duration: Double?
    public let bundleID: String?
    public let artworkData: Data?

    public init(title: String, artist: String, album: String, isPlaying: Bool, elapsed: Double,
                timestamp: Date, duration: Double?, bundleID: String?, artworkData: Data?) {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.duration = duration
        self.bundleID = bundleID
        self.artworkData = artworkData
    }

    /// A registered app with nothing loaded (its tab was closed) reports a
    /// bare, paused, untitled entry: the source went away, not a paused track.
    public var isSourceGone: Bool {
        !isPlaying && title.isEmpty && artist.isEmpty && album.isEmpty
    }
}

public enum NowPlayingPayload {
    /// Wraps the value so "nothing playing" (a valid, empty payload) is
    /// distinguishable from a line that couldn't be read (nil).
    public struct Parsed: Equatable {
        public let value: NowPlayingInfo?
    }

    public static func parse(_ line: Data, now: Date = Date()) -> Parsed? {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            object["type"] as? String == "data"
        else { return nil }
        guard let payload = object["payload"] as? [String: Any], !payload.isEmpty else {
            return Parsed(value: nil)
        }

        let timestamp = (payload["timestamp"] as? String).flatMap(ISO8601DateFormatter().date(from:)) ?? now
        let duration = (payload["duration"] as? Double).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return Parsed(value: NowPlayingInfo(
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

    /// Title and subtitle for the island. The app's name is never used as the
    /// artist (a browser tab would read "Google Chrome"); it only stands in
    /// for a missing title.
    public static func labels(for info: NowPlayingInfo, appName: String) -> (title: String, artist: String) {
        let title = info.title.isEmpty ? appName : info.title
        let subtitle = [info.artist, info.album].first { !$0.isEmpty } ?? ""
        return (title, subtitle == title ? "" : subtitle)
    }
}
