import AppKit

/// Fallback Now Playing source using AppleScript against Spotify/Music.app.
/// MediaRemote's private API returns an empty dictionary for non-entitled,
/// ad-hoc-signed apps on modern macOS (confirmed via debug logging), so this
/// is the reliable path for an app built outside Apple's provisioning system.
enum AppleScriptNowPlaying {
    enum Source {
        case spotify
        case music

        var bundleIdentifier: String {
            switch self {
            case .spotify: return "com.spotify.client"
            case .music: return "com.apple.Music"
            }
        }
    }

    struct Info {
        let title: String
        let artist: String
        let artworkURL: String?
        let isPlaying: Bool
        let positionSeconds: Double
        let durationSeconds: Double
        let source: Source
    }

    /// Both players are asked; a playing one beats a paused one, so a paused
    /// Spotify no longer hides Music that is actually playing.
    static func fetch() -> Info? {
        let candidates = [fetchSpotify(), fetchMusic()].compactMap { $0 }
        let shown = candidates.first(where: \.isPlaying) ?? candidates.first
        activeSource = shown?.source
        return shown
    }

    /// The player last shown, so commands go to it rather than to whichever
    /// app happens to be running. Confined to `queue`, like every call here.
    private static var activeSource: Source?

    /// Every AppleScript call — polling and commands alike — runs here. It keeps
    /// the work off the main thread (Apple Events to Spotify take long enough to
    /// stall a tap) and gives the compiled-script cache a single owner.
    private static let queue = DispatchQueue(label: "AppleScriptNowPlaying")

    /// Async entry point for the poller, so callers never touch the queue directly.
    static func fetch(completion: @escaping (Info?) -> Void) {
        queue.async { completion(fetch()) }
    }

    static func playPause() { run(spotify: "playpause", music: "playpause") }
    static func next() { run(spotify: "next track", music: "next track") }
    static func previous() { run(spotify: "previous track", music: "previous track") }

    private static func run(spotify spotifyCmd: String, music musicCmd: String) {
        queue.async {
            let script: String
            switch activeSource {
            case .spotify:
                script = "tell application \"Spotify\" to \(spotifyCmd)"
            case .music:
                script = "tell application \"Music\" to \(musicCmd)"
            case nil:
                script = """
                if application "Spotify" is running then
                    tell application "Spotify" to \(spotifyCmd)
                else if application "Music" is running then
                    tell application "Music" to \(musicCmd)
                end if
                """
            }
            _ = runAppleScript(script)
        }
    }

    private static func fetchSpotify() -> Info? {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify"
                set playerState to player state as string
                if playerState is "playing" or playerState is "paused" then
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set artworkURL to artwork url of current track
                    set posSec to player position
                    set durMs to duration of current track
                    return trackName & "||" & trackArtist & "||" & playerState & "||" & artworkURL & "||" & posSec & "||" & durMs
                end if
            end tell
        end if
        return ""
        """
        guard let result = runAppleScript(script), !result.isEmpty else { return nil }
        let parts = result.components(separatedBy: "||")
        guard parts.count >= 6 else { return nil }

        return Info(
            title: parts[0],
            artist: parts[1],
            artworkURL: parts[3],
            isPlaying: parts[2] == "playing",
            positionSeconds: Double(parts[4]) ?? 0,
            durationSeconds: (Double(parts[5]) ?? 0) / 1000,
            source: .spotify
        )
    }

    private static func fetchMusic() -> Info? {
        let script = """
        if application "Music" is running then
            tell application "Music"
                if player state is playing or player state is paused then
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set stateStr to player state as string
                    set posSec to player position
                    set durSec to duration of current track
                    return trackName & "||" & trackArtist & "||" & stateStr & "||" & posSec & "||" & durSec
                end if
            end tell
        end if
        return ""
        """
        guard let result = runAppleScript(script), !result.isEmpty else { return nil }
        let parts = result.components(separatedBy: "||")
        guard parts.count >= 5 else { return nil }
        return Info(
            title: parts[0],
            artist: parts[1],
            artworkURL: nil,
            isPlaying: parts[2] == "playing",
            positionSeconds: Double(parts[3]) ?? 0,
            durationSeconds: Double(parts[4]) ?? 0,
            source: .music
        )
    }

    /// Compiled scripts are cached and reused.
    ///
    /// `NSAppleScript(source:)` compiles on creation, and building a fresh one
    /// for every poll — once a second, forever — was the single biggest drain in
    /// the app. Compiling once and re-executing costs a fraction of that.
    ///
    /// `NSAppleScript` is not thread-safe, so the cache and every execution are
    /// confined to one serial queue.
    private static var compiledScripts: [String: NSAppleScript] = [:]

    @discardableResult
    private static func runAppleScript(_ source: String) -> String? {
        let script: NSAppleScript
        if let cached = compiledScripts[source] {
            script = cached
        } else {
            guard let created = NSAppleScript(source: source) else { return nil }
            compiledScripts[source] = created
            script = created
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil {
            return nil
        }
        return result.stringValue
    }
}
