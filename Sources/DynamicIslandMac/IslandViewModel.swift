import AppKit
import SwiftUI
import Combine
import IslandLogic

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
    /// Notch of the display hosting the island. Cached here and refreshed only
    /// by the window controller on placement, so the view, the hit rect and the
    /// panel frame always agree and rendering never walks `NSScreen.screens`.
    @Published var notchSize: CGSize = ScreenNotch.size()
    /// Whether that display has a hardware notch; without one the collapsed
    /// island is capped at the menu bar height. Refreshed together with `notchSize`.
    @Published var hasNotch: Bool = ScreenNotch.hasNotch()
    /// Frames of the collapsed content's leading/trailing ears, in island
    /// coordinates; not published — only the debug server reads them.
    var collapsedContentFrames: [String: CGRect] = [:]

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
        case agenda
        case timer
        case media
        case none
    }

    var content: Content {
        if glanceTitle != nil { return .glance }
        if call != nil { return .call }
        if isAgendaNow || isAgendaPinned { return .agenda }
        if isTimerActive { return .timer }
        if showsMedia { return .media }
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

    /// The system Clock's countdown (Часы, Siri, Shortcuts), shown in the
    /// island in place of Now Playing while it runs — the same footprint,
    /// different content, the way a Live Activity takes over. With several
    /// running, the one that goes off soonest.
    @Published private(set) var systemTimer: SystemTimer?
    @Published private(set) var timerRemaining: TimeInterval?
    @Published private(set) var timerTotal: TimeInterval = 0
    private var timerTick: Timer?

    var isTimerActive: Bool { timerRemaining != nil }
    var isTimerPaused: Bool { systemTimer?.isPaused ?? false }
    var timerTitle: String { systemTimer?.title ?? "" }

    func applySystemTimers(_ timers: [SystemTimer]) {
        let now = Date()
        // Running before paused; among them, least time left.
        let next = timers.min { a, b in
            if a.isPaused != b.isPaused { return !a.isPaused }
            return a.remaining(at: now) < b.remaining(at: now)
        }
        guard next != systemTimer else { return }
        systemTimer = next
        timerTotal = next?.duration ?? 0
        refreshTimerRemaining()
        sync()

        timerTick?.invalidate()
        timerTick = nil
        guard let next, !next.isPaused else { return }
        // Counted from the fire date, never decremented, so it cannot drift
        // from the Clock app.
        timerTick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refreshTimerRemaining()
        }
    }

    /// A system timer went off.
    func systemTimerFired(title: String) {
        presentGlance(title: "Таймер завершён", subtitle: title.isEmpty ? nil : title, symbol: "timer")
    }

    /// The system Clock can't be driven from here (its daemon only serves
    /// entitled Apple processes), so the card hands off to the app.
    func openClock() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Clock.app"))
    }

    private func refreshTimerRemaining() {
        guard let timer = systemTimer else {
            timerRemaining = nil
            return
        }
        // Whole seconds rounded up, like the Clock app: 0:01 until it fires.
        let remaining = timer.remaining().rounded(.up)
        if remaining != timerRemaining { timerRemaining = remaining }
    }

    // MARK: - Agenda

    /// Today's events and reminders from the system Calendar and Reminders
    /// (see `AgendaMonitor`).
    @Published private(set) var agenda = AgendaSnapshot()
    /// The agenda card opened from the menu bar, with nothing happening "now".
    @Published private(set) var isAgendaPinned = false
    private var agendaPinTimer: Timer?

    /// Supplied by `AppDelegate`: ticks a reminder off in the Reminders app.
    var completeReminderHandler: ((String) -> Void)?

    /// An event that just started or a reminder that just fell due.
    var isAgendaNow: Bool { agenda.nowEvent != nil || agenda.nowReminder != nil }

    func applyAgenda(_ snapshot: AgendaSnapshot) {
        guard snapshot != agenda else { return }
        agenda = snapshot
        sync()
    }

    func handleAgendaAlert(_ alert: AgendaAlert) {
        switch alert {
        case let .upcoming(event, minutes):
            presentGlance(
                title: event.title,
                subtitle: "Через \(minutes) мин · \(Self.clock(event.start))",
                symbol: "calendar",
                action: joinAction(for: event)
            )
        case let .started(event):
            presentGlance(
                title: "Сейчас: \(event.title)",
                subtitle: "\(Self.clock(event.start))–\(Self.clock(event.end))",
                symbol: "calendar.badge.clock",
                action: joinAction(for: event)
            )
        case let .due(reminder):
            presentGlance(
                title: reminder.title,
                subtitle: "Напоминание",
                symbol: "checklist",
                action: GlanceAction(label: "Выполнено") { [weak self] in
                    self?.completeReminder(id: reminder.id)
                }
            )
        }
    }

    func completeReminder(id: String) {
        completeReminderHandler?(id)
    }

    func join(_ event: AgendaEvent) {
        guard let url = event.joinURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func joinAction(for event: AgendaEvent) -> GlanceAction? {
        guard event.joinURL != nil else { return nil }
        return GlanceAction(label: "Подключиться") { [weak self] in self?.join(event) }
    }

    /// Menu bar «Сегодня»: the agenda card for a few seconds, or for as long
    /// as the pointer stays on it.
    func showAgenda() {
        isAgendaPinned = true
        sync()
        agendaPinTimer?.invalidate()
        agendaPinTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            guard let self, self.pointerIsInsideIsland?() != true else { return }
            self.isAgendaPinned = false
            self.sync()
        }
    }

    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // MARK: - Calendar glance

    /// A brief, dismiss-itself-on-a-timer peek — the same mechanic the old
    /// device notice used, just repurposed for a manually-triggered calendar
    /// check instead of a hardware event.
    @Published private(set) var glanceTitle: String?
    @Published private(set) var glanceSubtitle: String?
    /// SF Symbol for the glance, so a finished timer does not wear a calendar.
    @Published private(set) var glanceSymbol = "calendar"
    /// Optional button on the glance («Подключиться», «Выполнено»).
    @Published private(set) var glanceAction: GlanceAction?
    private var glanceTimer: Timer?

    func presentGlance(
        title: String,
        subtitle: String?,
        symbol: String = "calendar",
        action: GlanceAction? = nil
    ) {
        glanceTimer?.invalidate()
        glanceTitle = title
        glanceSubtitle = subtitle
        glanceSymbol = symbol
        glanceAction = action
        Haptics.hover()
        sync()

        // A glance with a button stays long enough to reach for it.
        let duration: TimeInterval = action == nil ? 4 : 8
        glanceTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismissGlance()
        }
    }

    func performGlanceAction() {
        let action = glanceAction
        dismissGlance()
        action?.perform()
    }

    private func dismissGlance() {
        glanceTimer?.invalidate()
        glanceTimer = nil
        glanceTitle = nil
        glanceSubtitle = nil
        glanceAction = nil
        sync()
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
    ///
    /// So is an event that just started or a reminder that just fell due, and
    /// the agenda card opened from the menu bar.
    var isIslandVisible: Bool {
        (isPlaying && !title.isEmpty) || isTimerActive || call != nil || isAgendaNow || isAgendaPinned
    }

    /// The track fills the island: while playing, and — paused — while the
    /// island is held open by hover or a click, so a pause never collapses it
    /// under the pointer. `isIslandVisible` stays play-gated, so once the
    /// pointer leaves a paused island hides (the Spotify "stuck" bug above).
    var showsMedia: Bool {
        IslandVisibility.showsMedia(isPlaying: isPlaying, hasTrack: hasContent, isOpen: isHovering || isPinnedOpen)
    }

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
        guard isIslandVisible || isPinnedOpen || showsMedia else { return }
        // The menu-opened agenda card closes on a click like any open card.
        if isAgendaPinned {
            isAgendaPinned = false
            isPinnedOpen = false
            sync()
            return
        }
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
        guard isHovering || isPinnedOpen || isAgendaPinned else { return }
        isHovering = false
        // Leaving also closes a click-opened island, so it never gets stranded
        // open once the pointer is elsewhere.
        isPinnedOpen = false
        isAgendaPinned = false
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
        // Another app taking over counts as a new track even with the same
        // title, so its cover, tint and lyrics never carry over.
        let trackChanged = snapshot.title != title || snapshot.artist != artist
            || snapshot.playerBundleID != playerBundleID

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
        } else if isAgendaPinned {
            next = .expanded
        } else if isPinnedOpen && (isIslandVisible || showsMedia) {
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
        let size = settings.islandSize(state: state, hasContent: isIslandVisible || showsMedia, notch: notch, hasNotch: hasNotch)
        switch state {
        case .expanded:
            guard glanceTitle == nil, let height = expandedContentHeight else { return size }
            return CGSize(width: size.width, height: height)
        case .collapsed, .peek:
            // A countdown or call duration is wider than the ear beside the
            // camera at the media width; widen both ears evenly rather than
            // let it slide under the notch.
            guard content == .timer || content == .call || content == .agenda else { return size }
            let wide = settings.wideEarsWidth(notch: notch, peek: state == .peek)
            return CGSize(width: max(size.width, wide), height: size.height)
        default:
            return size
        }
    }

}

/// A button on a glance, and what it does.
struct GlanceAction: Equatable {
    let label: String
    let perform: () -> Void

    static func == (lhs: GlanceAction, rhs: GlanceAction) -> Bool { lhs.label == rhs.label }
}
