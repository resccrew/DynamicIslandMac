import AppKit

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

/// Polls Now Playing state on a background queue (AppleScript calls block,
/// and artwork is fetched over the network) and reports snapshots on main.
/// Position/duration are forwarded every tick for a live progress bar;
/// artwork is only re-downloaded when its URL actually changes.
final class NowPlayingPoller {
    private var timer: Timer?
    private let queue = DispatchQueue(label: "NowPlayingPoller", qos: .utility)
    private var cachedArtworkURL: String?
    private var cachedArtwork: NSImage?
    private var cachedAccent: NSColor?

    func start(onUpdate: @escaping (NowPlayingSnapshot) -> Void) {
        poll(onUpdate: onUpdate)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll(onUpdate: onUpdate)
        }
    }

    private func poll(onUpdate: @escaping (NowPlayingSnapshot) -> Void) {
        // The AppleScript itself runs on its own serial queue; the artwork
        // download and colour extraction continue here off the main thread.
        AppleScriptNowPlaying.fetch { [weak self] info in
            self?.queue.async {
                self?.handle(info, onUpdate: onUpdate)
            }
        }
    }

    private func handle(
        _ info: AppleScriptNowPlaying.Info?,
        onUpdate: @escaping (NowPlayingSnapshot) -> Void
    ) {
        var artwork: NSImage? = nil
        var accent: NSColor? = nil
        if let urlString = info?.artworkURL {
            if urlString == cachedArtworkURL {
                artwork = cachedArtwork
                accent = cachedAccent
            } else if let url = URL(string: urlString), let data = try? Data(contentsOf: url) {
                artwork = NSImage(data: data)
                accent = artwork.map(ArtworkAccent.color(from:))
                cachedArtworkURL = urlString
                cachedArtwork = artwork
                cachedAccent = accent
            }
        }

        let snapshot = NowPlayingSnapshot(
            title: info?.title ?? "",
            artist: info?.artist ?? "",
            artwork: artwork,
            accent: accent,
            isPlaying: info?.isPlaying ?? false,
            position: info?.positionSeconds ?? 0,
            duration: info?.durationSeconds ?? 0,
            playerBundleID: info?.source.bundleIdentifier
        )

        DispatchQueue.main.async {
            onUpdate(snapshot)
        }
    }

    deinit {
        timer?.invalidate()
    }
}
