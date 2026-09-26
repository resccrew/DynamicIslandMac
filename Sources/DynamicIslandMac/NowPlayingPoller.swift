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

    // MARK: - Commands

    func togglePlayPause() {
        guard source == .system, let system else { return AppleScriptNowPlaying.playPause() }
        system.send(.togglePlayPause)
    }

    func next() {
        guard source == .system, let system else { return AppleScriptNowPlaying.next() }
        system.send(.nextTrack)
    }

    func previous() {
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
        guard let info = systemInfo else {
            deliver(NowPlayingSnapshot(
                title: "", artist: "", artwork: nil, accent: nil,
                isPlaying: false, position: 0, duration: 0, playerBundleID: nil
            ))
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

        // An app that is still registered but no longer has anything loaded
        // (its tab was closed) can report a bare, paused, untitled entry.
        // That is a source that went away, not a paused track; since a paused
        // track now keeps the island up, it must clear instead.
        if !info.isPlaying && info.title.isEmpty && info.artist.isEmpty && info.album.isEmpty {
            deliver(NowPlayingSnapshot(
                title: "", artist: "", artwork: nil, accent: nil,
                isPlaying: false, position: 0, duration: 0, playerBundleID: nil
            ))
            return
        }

        let duration = info.duration ?? 0
        var position = info.elapsed
        if info.isPlaying {
            position += Date().timeIntervalSince(info.timestamp)
        }

        // A bare <video>/<audio> page has no artist: name the browser (or the
        // app) instead, and if it has no title either, use that as the title.
        let owner = info.bundleID.map(AppIdentity.owner(of:))
        let appName = Self.appName(owner)
        let subtitle = [info.artist, info.album, appName].first { !$0.isEmpty } ?? ""
        let title = info.title.isEmpty ? appName : info.title
        deliver(NowPlayingSnapshot(
            title: title,
            artist: subtitle == title ? "" : subtitle,
            artwork: artwork,
            accent: accent,
            isPlaying: info.isPlaying,
            position: position,
            duration: duration,
            playerBundleID: owner
        ))
    }

    private static func appName(_ bundleID: String?) -> String {
        guard
            let bundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return "" }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private func handle(_ info: AppleScriptNowPlaying.Info?) {
        var artwork: NSImage? = nil
        var accent: NSColor? = nil
        if let urlString = info?.artworkURL {
            if urlString == cachedArtworkKey {
                artwork = cachedArtwork
                accent = cachedAccent
            } else if let url = URL(string: urlString), let data = try? Data(contentsOf: url) {
                artwork = NSImage(data: data)
                accent = artwork.map(ArtworkAccent.color(from:))
                cachedArtworkKey = urlString
                cachedArtwork = artwork
                cachedAccent = accent
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

    private func deliver(_ snapshot: NowPlayingSnapshot) {
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(snapshot)
        }
    }

    deinit {
        timer?.invalidate()
        system?.stop()
    }
}
