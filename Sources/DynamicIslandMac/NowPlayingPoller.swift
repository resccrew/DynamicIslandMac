import AppKit
import IslandLogic

struct NowPlayingSnapshot {
    let title: String
    let artist: String
    let artwork: NSImage?
    let accent: NSColor?
    let isPlaying: Bool
    let position: Double
    let duration: Double
    /// Which app is playing, so the island can offer to open it.
    let playerBundleID: String?
}

/// A transport command from the island's buttons.
enum NowPlayingCommand: String {
    case togglePlayPause, next, previous
}

extension NowPlayingSnapshot {
    /// Nothing loaded anywhere.
    static let empty = NowPlayingSnapshot(
        title: "", artist: "", artwork: nil, accent: nil,
        isPlaying: false, position: 0, duration: 0, playerBundleID: nil
    )
}

/// Where Now Playing currently comes from, surfaced for debugging.
enum NowPlayingSourceKind: String {
    /// System-wide Now Playing: any app, any browser tab.
    case system
    /// Spotify/Music over AppleScript, when the system source is unavailable.
    case appleScript
}

/// Feeds the model Now Playing snapshots on main, once a second and on every
/// change, and routes transport commands to whichever source is active.
///
/// The system source (see `SystemNowPlaying`) is preferred: it covers browsers
/// and every media app, and pushes changes instead of being polled. If it is
/// missing (not a bundled .app) or keeps dying, AppleScript against
/// Spotify/Music takes over.
final class NowPlayingPoller {
    private var timer: Timer?
    private let queue = DispatchQueue(label: "NowPlayingPoller", qos: .utility)
    private var onUpdate: ((NowPlayingSnapshot) -> Void)?

    private var system: SystemNowPlaying?
    private(set) var source: NowPlayingSourceKind = .appleScript

    /// Latest system state; the 1s tick re-emits it so playback time keeps
    /// moving between events. Touched only on `queue`.
    private var systemInfo: SystemNowPlaying.Info?
    /// Latest report per source app, and which one owns the island. The
    /// stream carries whatever macOS calls "now playing"; the arbiter stops a
    /// paused app that reports in from stealing the island from one that is
    /// still playing (see `NowPlayingArbiter`). Touched only on `queue`.
    private var systemInfos: [String: SystemNowPlaying.Info] = [:]
    private var arbiter = NowPlayingArbiter()

    private var cachedArtworkKey: String?
    private var cachedArtwork: NSImage?
    private var cachedAccent: NSColor?
    /// AppleScript artwork URL being downloaded. Touched only on `queue`.
    private var artworkDownload: String?

    /// App display names by bundle id: a LaunchServices lookup per tick
    /// adds up. Touched only on `queue`.
    private var appNames: [String: String] = [:]

    /// What was last handed to main, to skip re-sending an unchanged idle
    /// state every second. Touched only on `queue`.
    private var lastDelivered: DeliveredKey?

    private static let artworkSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    /// Debug hook: when set and it returns true, a transport command was
    /// handled (e.g. by an injected fake track) and must not reach a player.
    var commandInterceptor: ((NowPlayingCommand) -> Bool)?

    func start(onUpdate: @escaping (NowPlayingSnapshot) -> Void) {
        self.onUpdate = onUpdate

        if let system = SystemNowPlaying() {
            self.system = system
            source = .system
            system.onFailure = { [weak self] in self?.fallBackToAppleScript() }
            system.start { [weak self] info in
                self?.queue.async {
                    self?.receiveSystem(info)
                    self?.emitSystem()
                }
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    /// Forces the next state out even if unchanged, e.g. after a debug
    /// injection overwrote what the model shows.
    func resync() {
        queue.async { [weak self] in self?.lastDelivered = nil }
    }

    // MARK: - Commands

    func togglePlayPause() {
        if commandInterceptor?(.togglePlayPause) == true { return }
        guard source == .system, let system else { return AppleScriptNowPlaying.playPause() }
        system.send(.togglePlayPause)
    }

    func next() {
        if commandInterceptor?(.next) == true { return }
        guard source == .system, let system else { return AppleScriptNowPlaying.next() }
        system.send(.nextTrack)
    }

    func previous() {
        if commandInterceptor?(.previous) == true { return }
        guard source == .system, let system else { return AppleScriptNowPlaying.previous() }
        system.send(.previousTrack)
    }

    // MARK: - Updates

    private func tick() {
        switch source {
        case .system:
            queue.async { [weak self] in
                // A playing source that went quiet loses its grace period here.
                self?.pickSystemWinner()
                self?.emitSystem()
            }
        case .appleScript:
            // The AppleScript itself runs on its own serial queue; the artwork
            // download and colour extraction continue here off the main thread.
            // Skipped while the previous fetch still waits on a player.
            AppleScriptNowPlaying.fetch { [weak self] info in
                self?.queue.async {
                    self?.handle(info)
                }
            }
        }
    }

    private func fallBackToAppleScript() {
        system = nil
        source = .appleScript
    }

    private func receiveSystem(_ info: SystemNowPlaying.Info?) {
        guard let info else {
            systemInfos.removeAll()
            arbiter.reset()
            systemInfo = nil
            return
        }
        let id = info.bundleID.map(AppIdentity.owner(of:)) ?? ""
        systemInfos[id] = info
        arbiter.report(id: id, isPlaying: info.isPlaying, at: Date())
        pickSystemWinner()
    }

    private func pickSystemWinner() {
        guard let id = arbiter.winner(at: Date()) else { return }
        systemInfo = systemInfos[id]
    }

    private func emitSystem() {
        // An app that is still registered but no longer has anything loaded
        // (its tab was closed) reports a bare, paused, untitled entry. That is
        // a source that went away, not a paused track; since a paused track
        // keeps the island up, it must clear instead.
        guard let info = systemInfo, !info.isSourceGone else {
            deliver(.empty)
            return
        }

        var artwork: NSImage? = nil
        var accent: NSColor? = nil
        if let data = info.artworkData {
            // Every line repeats the full cover; decode and tint only on change.
            let key = "\(data.count)|\(data.prefix(64).base64EncodedString())|\(data.suffix(64).base64EncodedString())"
            if key != cachedArtworkKey {
                cachedArtworkKey = key
                cachedArtwork = NSImage(data: data)
                cachedAccent = cachedArtwork.map(ArtworkAccent.color(from:))
            }
            artwork = cachedArtwork
            accent = cachedAccent
        }

        let duration = info.duration ?? 0
        var position = info.elapsed
        if info.isPlaying {
            position += Date().timeIntervalSince(info.timestamp)
        }

        let owner = info.bundleID.map(AppIdentity.owner(of:))
        let labels = NowPlayingPayload.labels(for: info, appName: appName(owner))
        deliver(NowPlayingSnapshot(
            title: labels.title,
            artist: labels.artist,
            artwork: artwork,
            accent: accent,
            isPlaying: info.isPlaying,
            position: position,
            duration: duration,
            playerBundleID: owner
        ))
    }

    private func appName(_ bundleID: String?) -> String {
        guard let bundleID else { return "" }
        if let cached = appNames[bundleID] { return cached }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? ""
        appNames[bundleID] = name
        return name
    }

    private func handle(_ info: AppleScriptNowPlaying.Info?) {
        var artwork: NSImage? = nil
        var accent: NSColor? = nil
        if let urlString = info?.artworkURL {
            if urlString == cachedArtworkKey {
                artwork = cachedArtwork
                accent = cachedAccent
            } else {
                // Downloaded off this queue; the next tick picks it up.
                downloadArtwork(urlString)
            }
        }

        deliver(NowPlayingSnapshot(
            title: info?.title ?? "",
            artist: info?.artist ?? "",
            artwork: artwork,
            accent: accent,
            isPlaying: info?.isPlaying ?? false,
            position: info?.positionSeconds ?? 0,
            duration: info?.durationSeconds ?? 0,
            playerBundleID: info?.source.bundleIdentifier
        ))
    }

    /// Fetches an AppleScript cover without blocking `queue`; one at a time.
    private func downloadArtwork(_ urlString: String) {
        guard artworkDownload != urlString, let url = URL(string: urlString),
              url.scheme == "https" || url.scheme == "http"
        else { return }
        artworkDownload = urlString
        Self.artworkSession.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap(NSImage.init(data:))
            let accent = image.map(ArtworkAccent.color(from:))
            self?.queue.async {
                guard let self, self.artworkDownload == urlString else { return }
                self.artworkDownload = nil
                guard let image else { return }
                self.cachedArtworkKey = urlString
                self.cachedArtwork = image
                self.cachedAccent = accent
            }
        }.resume()
    }

    /// Everything the model shows except the moving position. A paused or
    /// empty state that matches the last one sent is not sent again, so an
    /// idle Mac isn't woken every second for nothing.
    private struct DeliveredKey: Equatable {
        let title: String
        let artist: String
        let artwork: ObjectIdentifier?
        let isPlaying: Bool
        let position: Double
        let duration: Double
        let playerBundleID: String?

        init(_ snapshot: NowPlayingSnapshot) {
            title = snapshot.title
            artist = snapshot.artist
            artwork = snapshot.artwork.map(ObjectIdentifier.init)
            isPlaying = snapshot.isPlaying
            // A paused position that jumps (a seek) is still news.
            position = snapshot.isPlaying ? 0 : snapshot.position.rounded()
            duration = snapshot.duration
            playerBundleID = snapshot.playerBundleID
        }
    }

    private func deliver(_ snapshot: NowPlayingSnapshot) {
        let key = DeliveredKey(snapshot)
        if !snapshot.isPlaying, key == lastDelivered { return }
        lastDelivered = key
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(snapshot)
        }
    }

    /// Stops the adapter before the app exits.
    func shutdown() {
        timer?.invalidate()
        system?.stopAndWait()
    }

    deinit {
        timer?.invalidate()
        system?.stop()
    }
}
