import AppKit
import SwiftUI
import Combine

/// Resting sizes: fully out of sight when there is nothing to show, idle, a
/// slight grow under the pointer, and fully open.
enum IslandState {
    case hidden
    case collapsed
    case peek
    case expanded
    /// A calendar glance taking over the island for a few seconds.
    case glance
}

final class IslandViewModel: ObservableObject {
    /// Starts hidden so launching with nothing playing doesn't flash an empty island.
    @Published private(set) var state: IslandState = .hidden
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var artwork: NSImage? = nil
    /// Natural height of the expanded card on screen, measured by the view; the
    /// island hugs it rather than a fixed height with dead space at the bottom.
    @Published var expandedContentHeight: CGFloat?

    static let defaultAccent = Color(red: 0.80, green: 0.70, blue: 0.58)
    @Published var accent: Color = IslandViewModel.defaultAccent
    @Published var isPlaying: Bool = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    /// Bundle id of whatever is playing, so the island can bring it to the front.
    @Published var playerBundleID: String?

    /// Transport commands go to whichever source is playing (system-wide Now
    /// Playing, or AppleScript as a fallback). Set by `AppDelegate`.
    weak var player: NowPlayingPoller?

    /// What the island body shows, in priority order. Glance and call are
    /// transient takeovers; a timer outranks media the way a Live Activity does.
    enum Content: String {
        case glance
        case call
        case timer
        case media
        case none
    }

    var content: Content {
        if glanceTitle != nil { return .glance }
        if call != nil { return .call }
        if isTimerActive { return .timer }
        if isPlaying && !title.isEmpty || isPinnedOpen && hasContent { return .media }
        return .none
    }

    // MARK: - Call

    /// A call in progress in some calling app (see `CallMonitor`).
    @Published private(set) var call: CallInfo?

    func setCall(_ call: CallInfo?) {
        guard call != self.call else { return }
        let started = self.call == nil && call != nil
        self.call = call
        if started { Haptics.hover() }
        sync()
    }

    /// Brings the calling app forward.
    func openCallApp() {
        guard
            let bundleID = call?.bundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Lock screen has three steps: the compact card, a large cover on its own,
    /// and only then the karaoke view.
    enum LockPresentation {
        case card
        case artwork
        case lyrics
    }

    @Published private(set) var lockPresentation: LockPresentation = .card

    var lockArtExpanded: Bool { lockPresentation != .card }

    @Published private(set) var lyrics: [LyricLine] = []

    // MARK: - Timer

    /// A user-started countdown, shown in the island in place of Now Playing
    /// while it runs — the same footprint, different content, the way a
    /// Live Activity takes over.
    @Published private(set) var timerRemaining: TimeInterval?
    @Published private(set) var timerTotal: TimeInterval = 0
    private var timerTick: Timer?

    var isTimerActive: Bool { timerRemaining != nil }

    func startTimer(minutes: Double) {
        let seconds = minutes * 60
        timerTotal = seconds
        timerRemaining = seconds
        Haptics.hover()
        sync()

        timerTick?.invalidate()
        timerTick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, var remaining = self.timerRemaining else { return }
            remaining -= 1
            if remaining <= 0 {
                self.cancelTimer()
                self.presentGlance(title: "Таймер завершён", subtitle: nil, symbol: "timer")
            } else {
                self.timerRemaining = remaining
            }
        }
    }

    func cancelTimer() {
        timerTick?.invalidate()
        timerTick = nil
        timerRemaining = nil
        timerTotal = 0
        sync()
    }

    // MARK: - Calendar glance

    /// A brief, dismiss-itself-on-a-timer peek — the same mechanic the old
    /// device notice used, just repurposed for a manually-triggered calendar
    /// check instead of a hardware event.
    @Published private(set) var glanceTitle: String?
    @Published private(set) var glanceSubtitle: String?
    /// SF Symbol for the glance, so a finished timer does not wear a calendar.
    @Published private(set) var glanceSymbol = "calendar"
    private var glanceTimer: Timer?

    func presentGlance(title: String, subtitle: String?, symbol: String = "calendar") {
        glanceTimer?.invalidate()
        glanceTitle = title
        glanceSubtitle = subtitle
        glanceSymbol = symbol
        Haptics.hover()
        sync()

        glanceTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.glanceTitle = nil
            self?.glanceSubtitle = nil
            self?.sync()
        }
    }

    /// Index of the line that should be highlighted, or nil before the first one.
    var currentLyricIndex: Int? {
        guard !lyrics.isEmpty else { return nil }
        guard let index = lyrics.lastIndex(where: { $0.time <= position }) else { return nil }
        return index
    }

    var isExpanded: Bool { state == .expanded }

    /// Hover, a click, and the track-change flash are independent reasons to be
    /// open. Keeping them separate stops the `onHover(false)` that SwiftUI emits
    /// while the panel resizes from cancelling a flash that just started.
    private var isHovering = false
    private var isPinnedOpen = false

    private var pointerWatchdog: Timer?
    private var lastHoverHaptic: Date = .distantPast

    private var lyricsTrackKey = ""
    /// The player is polled once a second, which is far too coarse to land a
    /// lyric on the beat, so playback time is advanced locally between polls.
    private var positionTicker: Timer?

    /// A track is loaded, regardless of play state — used by the lock screen,
    /// which (like iOS) keeps showing a paused track rather than hiding it.
    var hasContent: Bool { !title.isEmpty }

    /// Whether the island itself should be showing.
    ///
    /// Deliberately *not* the same as `hasContent`: Spotify's AppleScript has
    /// no real "stopped" state — its `stop` command just pauses, and a paused
    /// track keeps reporting its title indefinitely. Gating on title alone
    /// meant the island stayed visible, poking out past the real notch, for as
    /// long as anything had ever played that session. Requiring `isPlaying`
    /// too means it actually goes flush the moment playback stops.
    ///
    /// A running timer is just as valid a reason to be visible as playback —
    /// it takes over the same footprint (see `isTimerActive` in content
    /// selection), so it has to be counted here too or the island never
    /// leaves `.hidden` for a timer started with nothing playing.
    ///
    /// A call is shown for as long as it lasts, whatever else is going on.
    var isIslandVisible: Bool { (isPlaying && !title.isEmpty) || isTimerActive || call != nil }

    /// Changes exactly once per track, driving the artwork flip.
    var trackKey: String { "\(title)|\(artist)" }

    /// Supplied by the window controller: whether the pointer is actually over
    /// the panel right now, in screen coordinates.
    var pointerIsInsideIsland: (() -> Bool)?

    func hover(_ hovering: Bool) {
        if hovering {
            guard !isHovering else { return }
            isHovering = true
            fireHoverHaptic()
            sync()
        } else {
            // SwiftUI also emits an exit while the panel is resizing under the
            // pointer. Trusting the real cursor position instead of a settle
            // timer keeps the close instant without that false positive.
            guard pointerIsInsideIsland?() != true else { return }
            closeFromPointerExit()
        }
    }

    /// Click toggles the full card; hovering alone only peeks. With nothing
    /// playing there is no card to show, so the click is ignored. No haptic
    /// here — the only tap belongs to entering the island.
    func tap() {
        // An open card stays tappable after a pause, so it can still be closed.
        guard isIslandVisible || isPinnedOpen else { return }
        isPinnedOpen.toggle()
        sync()
    }

    /// One tap per entry. The island resizes under the pointer, which can make
    /// SwiftUI re-deliver an enter; without this guard those repeats stack up
    /// and read as a stuttering buzz.
    private func fireHoverHaptic() {
        let now = Date()
        guard now.timeIntervalSince(lastHoverHaptic) > 0.5 else { return }
        lastHoverHaptic = now
        Haptics.hover()
    }

    private func closeFromPointerExit() {
        guard isHovering || isPinnedOpen else { return }
        isHovering = false
        // Leaving also closes a click-opened island, so it never gets stranded
        // open once the pointer is elsewhere.
        isPinnedOpen = false
        sync()
    }

    /// A moving pointer can leave without SwiftUI delivering a final exit (the
    /// panel may have resized out from under it), so verify periodically while open.
    private func startPointerWatchdog() {
        guard pointerWatchdog == nil else { return }
        pointerWatchdog = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.isHovering || self.isPinnedOpen else { return }
            if self.pointerIsInsideIsland?() != true {
                self.closeFromPointerExit()
            }
        }
    }

    private func stopPointerWatchdog() {
        pointerWatchdog?.invalidate()
        pointerWatchdog = nil
    }

    func apply(_ snapshot: NowPlayingSnapshot) {
        let trackChanged = snapshot.title != title || snapshot.artist != artist

        title = snapshot.title
        artist = snapshot.artist
        isPlaying = snapshot.isPlaying
        // Players can report a stale position past the end (track boundary,
        // ads); never show more than the track's length.
        position = snapshot.duration > 0
            ? min(max(snapshot.position, 0), snapshot.duration)
            : max(snapshot.position, 0)
        duration = snapshot.duration
        playerBundleID = snapshot.playerBundleID

        if trackChanged {
            loadLyrics(title: snapshot.title, artist: snapshot.artist, duration: snapshot.duration)
        }
        updatePositionTicker()
        // A new track must never keep the previous song's cover or tint; within
        // one track a missing cover just means it has not been fetched yet.
        if let artwork = snapshot.artwork {
            self.artwork = artwork
        } else if trackChanged || snapshot.title.isEmpty {
            self.artwork = nil
        }
        if let accent = snapshot.accent {
            self.accent = Color(nsColor: accent)
        } else if trackChanged {
            self.accent = Self.defaultAccent
        }

        // A track change only swaps the artwork and tint in place; the island
        // never opens itself.
        sync()
    }

    /// Tapping the cover steps into the large artwork, and from anywhere deeper
    /// it collapses all the way back to the card.
    func toggleLockArt() {
        lockPresentation = lockPresentation == .card ? .artwork : .card
    }

    /// Lyrics are a deliberate second step, not something the cover tap skips to.
    func toggleLockLyrics() {
        lockPresentation = lockPresentation == .lyrics ? .artwork : .lyrics
    }

    private func loadLyrics(title: String, artist: String, duration: Double) {
        let key = "\(title)|\(artist)"
        guard key != lyricsTrackKey else { return }
        lyricsTrackKey = key
        lyrics = []

        guard IslandSettings.shared.lyricsEnabled, !title.isEmpty else { return }

        LyricsProvider.fetch(title: title, artist: artist, duration: duration) { [weak self] lines in
            DispatchQueue.main.async {
                // A slow reply for a track that already changed must not land.
                guard let self, self.lyricsTrackKey == key else { return }
                self.lyrics = lines
            }
        }
    }

    /// Whether anything on screen actually shows playback time right now.
    /// Ticking five times a second re-renders the island for nothing when only
    /// the artwork and equalizer are visible.
    private var needsFinePosition: Bool {
        isLockScreenVisible || state == .expanded
    }

    var isLockScreenVisible = false {
        didSet { updatePositionTicker() }
    }

    private func updatePositionTicker() {
        guard isPlaying, needsFinePosition else {
            positionTicker?.invalidate()
            positionTicker = nil
            return
        }

        guard positionTicker == nil else { return }
        positionTicker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            // The ticker only interpolates between polls; it must not run the
            // clock past the end while waiting for the next track.
            self.position = self.duration > 0
                ? min(self.position + 0.2, self.duration)
                : self.position + 0.2
        }
    }

    /// Each lock starts from the compact card rather than however it was left.
    func resetLockScreenPresentation() {
        lockPresentation = .card
    }

    /// Brings the playing app to the front.
    func openPlayer() {
        guard
            let bundleID = playerBundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }


    func togglePlayPause() { player?.togglePlayPause() }
    func skipNext() { player?.next() }
    func skipPrevious() { player?.previous() }

    /// The cover, or — for a page or app that publishes none — the icon of the
    /// app that is playing, so the island never shows an empty square for a
    /// YouTube tab or a podcast app.
    var displayArtwork: NSImage? {
        artwork ?? playerBundleID.flatMap(AppIcons.icon(for:))
    }

    private func sync() {
        let next: IslandState
        if glanceTitle != nil {
            // A calendar glance takes precedence over playback, so the
            // island can show it even with nothing playing.
            next = .glance
        } else if isPinnedOpen && (isIslandVisible || hasContent) {
            // Pausing from the card's own button must not pull the card, and
            // the play button with it, out from under the pointer. It closes
            // on pointer exit like any click-opened island.
            next = .expanded
        } else if isHovering {
            // Hover still responds with nothing playing, so the island shows it
            // is alive — just with an empty body.
            next = .peek
        } else if !isIslandVisible {
            next = .hidden
        } else {
            next = .collapsed
        }

        if state != next {
            state = next
            updatePositionTicker()
        }

        if isHovering || isPinnedOpen {
            startPointerWatchdog()
        } else {
            stopPointerWatchdog()
        }
    }
}

extension IslandViewModel {
    /// The island's on-screen size. Shared by the view and by the window
    /// controller's pointer hit-test, so both agree on the hugging height.
    func islandSize(settings: IslandSettings, notch: CGSize) -> CGSize {
        let size = settings.islandSize(state: state, hasContent: isIslandVisible, notch: notch)
        guard state == .expanded, glanceTitle == nil,
              let height = expandedContentHeight else { return size }
        return CGSize(width: size.width, height: height)
    }
}
