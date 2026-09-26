import Foundation
import IslandLogic

/// Fetches time-synced lyrics from LRCLIB.
///
/// Spotify's own lyrics come from Musixmatch and are not exposed through
/// AppleScript or its Web API, so they cannot be read from the running player.
/// LRCLIB is an open, key-less database of LRC files keyed by track metadata,
/// which is what the community players use for the same purpose.
///
/// Note this sends the track title, artist and duration to lrclib.net.
enum LyricsProvider {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config)
    }()

    static func fetch(
        title: String,
        artist: String,
        duration: Double,
        completion: @escaping ([LyricLine]) -> Void
    ) {
        guard !title.isEmpty else {
            completion([])
            return
        }

        // `/api/get` demands the duration match almost exactly and 404s otherwise,
        // which is why plenty of tracks came back with no lyrics at all. Fall back
        // to the fuzzy search and pick the closest release ourselves.
        exactMatch(title: title, artist: artist, duration: duration) { lines in
            if !lines.isEmpty {
                completion(lines)
            } else {
                search(title: title, artist: artist, duration: duration, completion: completion)
            }
        }
    }

    private static func exactMatch(
        title: String,
        artist: String,
        duration: Double,
        completion: @escaping ([LyricLine]) -> Void
    ) {
        let items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]

        request(path: "/api/get", items: items) { data in
            guard
                let data,
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let synced = payload["syncedLyrics"] as? String,
                !synced.isEmpty
            else {
                completion([])
                return
            }
            completion(parse(synced))
        }
    }

    private static func search(
        title: String,
        artist: String,
        duration: Double,
        completion: @escaping ([LyricLine]) -> Void
    ) {
        let items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]

        request(path: "/api/search", items: items) { data in
            guard
                let data,
                let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                completion([])
                return
            }

            // Closest duration wins: different releases of the same song carry
            // different timings, and a mismatched one drifts out of sync.
            let candidates = results.filter { ($0["syncedLyrics"] as? String)?.isEmpty == false }
            let best = LyricsParser.closestDurationIndex(
                candidates.map { $0["duration"] as? Double },
                to: duration
            ).map { candidates[$0] }

            guard let synced = best?["syncedLyrics"] as? String else {
                completion([])
                return
            }
            completion(parse(synced))
        }
    }

    private static func request(
        path: String,
        items: [URLQueryItem],
        completion: @escaping (Data?) -> Void
    ) {
        guard var components = URLComponents(string: "https://lrclib.net\(path)") else {
            completion(nil)
            return
        }
        components.queryItems = items

        guard let url = components.url else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("DynamicIslandMac (lock screen lyrics)", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, _, _ in
            completion(data)
        }.resume()
    }

    static func parse(_ lrc: String) -> [LyricLine] {
        LyricsParser.parse(lrc)
    }
}
