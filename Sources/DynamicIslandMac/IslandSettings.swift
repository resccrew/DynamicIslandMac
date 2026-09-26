import SwiftUI
import Combine
import IslandGeometry

/// Live-tunable geometry, shared by the window controller and the view and
/// persisted across launches. Every edit in the settings panel writes here, and
/// both the drawn shape and the panel's frame follow immediately.
final class IslandSettings: ObservableObject {
    static let shared = IslandSettings()

    @Published var collapsedWidth: Double { didSet { persist() } }
    @Published var collapsedHeight: Double { didSet { persist() } }
    @Published var expandedWidth: Double { didSet { persist() } }
    @Published var expandedHeight: Double { didSet { persist() } }

    @Published var fillet: Double { didSet { persist() } }
    @Published var collapsedBottomRadius: Double { didSet { persist() } }
    @Published var expandedBottomRadius: Double { didSet { persist() } }
    /// Much tighter than the collapsed/expanded radii — matches the real
    /// notch's own corner, since idle is meant to sit flush inside it.
    @Published var idleBottomRadius: Double { didSet { persist() } }
    @Published var bottomExponent: Double { didSet { persist() } }
    @Published var topExponent: Double { didSet { persist() } }

    @Published var collapsedArtwork: Double { didSet { persist() } }
    @Published var expandedArtwork: Double { didSet { persist() } }
    @Published var collapsedPadding: Double { didSet { persist() } }
    @Published var expandedPadding: Double { didSet { persist() } }
    @Published var expandedTopPadding: Double { didSet { persist() } }

    @Published var titleFontSize: Double { didSet { persist() } }
    @Published var artistFontSize: Double { didSet { persist() } }

    @Published var peekWidthGrowth: Double { didSet { persist() } }
    @Published var peekHeightGrowth: Double { didSet { persist() } }
    @Published var animationDuration: Double { didSet { persist() } }

    /// Off by default: the window shadow paints a grey halo along the edges that
    /// keeps the island from reading as part of the black screen bezel.
    @Published var showShadow: Bool { didSet { persist() } }

    /// How far the idle island hangs below the notch. A few points give the
    /// pointer something to reach, since the cursor skips over the notch itself.
    @Published var idleHeightExtra: Double { didSet { persist() } }

    @Published var lockScreenEnabled: Bool { didSet { persist() } }
    @Published var lockScreenWidth: Double { didSet { persist() } }
    @Published var lockScreenArtSize: Double { didSet { persist() } }
    /// Positive moves the card down; the password field sits below centre.
    @Published var lockScreenOffsetY: Double { didSet { persist() } }
    /// White card, dark text — an alternative to the default translucent-on-dark look.
    @Published var lockCardLightTheme: Bool { didSet { persist() } }
    /// Fetching lyrics sends the track title and artist to lrclib.net.
    @Published var lyricsEnabled: Bool { didSet { persist() } }

    /// System Calendar events: a heads-up before they start and at the start.
    @Published var calendarEnabled: Bool { didSet { persist() } }
    /// System Reminders: shown when due, with a «Выполнено» button.
    @Published var remindersEnabled: Bool { didSet { persist() } }
    /// How many minutes before an event the heads-up appears.
    @Published var eventLeadMinutes: Double { didSet { persist() } }

    /// Keep the display awake while locked, and for how long.
    @Published var preventSleepOnLock: Bool { didSet { persist() } }
    @Published var preventSleepMinutes: Double { didSet { persist() } }

    /// Hiding the menu bar icon makes the app feel built-in. Re-opening it from
    /// Applications brings the settings back, so it can never be stranded.
    @Published var showStatusIcon: Bool { didSet { persist() } }

    /// Which display hosts the island when several are connected.
    @Published var displayPolicy: IslandDisplayPolicy { didSet { persist() } }

    /// Announce headphones and the charger connecting.

    enum Defaults {
        static let collapsedWidth = 280.0
        static let collapsedHeight = 38.0
        static let expandedWidth = 280.0
        static let expandedHeight = 148.0

        static let fillet = 13.0
        static let collapsedBottomRadius = 26.0
        static let expandedBottomRadius = 36.0
        static let idleBottomRadius = 9.0
        static let bottomExponent = 5.0
        static let topExponent = 2.2

        static let collapsedArtwork = 26.0
        static let expandedArtwork = 54.0
        static let collapsedPadding = 8.0
        static let expandedPadding = 14.0
        static let expandedTopPadding = 12.0

        static let titleFontSize = 15.0
        static let artistFontSize = 12.0

        static let peekWidthGrowth = 18.0
        static let peekHeightGrowth = 5.0
        static let animationDuration = 0.32
        static let showShadow = false
        static let idleHeightExtra = 0.0

        static let lockScreenEnabled = true
        static let lockScreenWidth = 380.0
        static let lockScreenArtSize = 360.0
        /// Below centre, so the card sits just above the avatar and password field.
        static let lockScreenOffsetY = 230.0
        static let lockCardLightTheme = true
        static let lyricsEnabled = true
        static let calendarEnabled = true
        static let remindersEnabled = true
        static let eventLeadMinutes = 5.0
        static let preventSleepOnLock = false
        static let preventSleepMinutes = 10.0
        static let showStatusIcon = true
        static let displayPolicy = IslandDisplayPolicy.primary
    }

    private var isLoading = true

    private init() {
        collapsedWidth = Self.read("collapsedWidth", Defaults.collapsedWidth)
        collapsedHeight = Self.read("collapsedHeight", Defaults.collapsedHeight)
        expandedWidth = Self.read("expandedWidth", Defaults.expandedWidth)
        expandedHeight = Self.read("expandedHeight", Defaults.expandedHeight)

        fillet = Self.read("fillet", Defaults.fillet)
        collapsedBottomRadius = Self.read("collapsedBottomRadius", Defaults.collapsedBottomRadius)
        expandedBottomRadius = Self.read("expandedBottomRadius", Defaults.expandedBottomRadius)
        idleBottomRadius = Self.read("idleBottomRadius", Defaults.idleBottomRadius)
        bottomExponent = Self.read("bottomExponent", Defaults.bottomExponent)
        topExponent = Self.read("topExponent", Defaults.topExponent)

        collapsedArtwork = Self.read("collapsedArtwork", Defaults.collapsedArtwork)
        expandedArtwork = Self.read("expandedArtwork", Defaults.expandedArtwork)
        collapsedPadding = Self.read("collapsedPadding", Defaults.collapsedPadding)
        expandedPadding = Self.read("expandedPadding", Defaults.expandedPadding)
        expandedTopPadding = Self.read("expandedTopPadding", Defaults.expandedTopPadding)

        titleFontSize = Self.read("titleFontSize", Defaults.titleFontSize)
        artistFontSize = Self.read("artistFontSize", Defaults.artistFontSize)

        peekWidthGrowth = Self.read("peekWidthGrowth", Defaults.peekWidthGrowth)
        peekHeightGrowth = Self.read("peekHeightGrowth", Defaults.peekHeightGrowth)
        animationDuration = Self.read("animationDuration", Defaults.animationDuration)
        showShadow = UserDefaults.standard.object(forKey: "showShadow") as? Bool ?? Defaults.showShadow
        idleHeightExtra = Self.read("idleHeightExtra", Defaults.idleHeightExtra)

        lockScreenEnabled = UserDefaults.standard.object(forKey: "lockScreenEnabled") as? Bool
            ?? Defaults.lockScreenEnabled
        lockScreenWidth = Self.read("lockScreenWidth", Defaults.lockScreenWidth)
        lockScreenArtSize = Self.read("lockScreenArtSize", Defaults.lockScreenArtSize)
        lockScreenOffsetY = Self.read("lockScreenOffsetY", Defaults.lockScreenOffsetY)
        lockCardLightTheme = UserDefaults.standard.object(forKey: "lockCardLightTheme") as? Bool
            ?? Defaults.lockCardLightTheme
        lyricsEnabled = UserDefaults.standard.object(forKey: "lyricsEnabled") as? Bool ?? Defaults.lyricsEnabled
        calendarEnabled = UserDefaults.standard.object(forKey: "calendarEnabled") as? Bool
            ?? Defaults.calendarEnabled
        remindersEnabled = UserDefaults.standard.object(forKey: "remindersEnabled") as? Bool
            ?? Defaults.remindersEnabled
        eventLeadMinutes = Self.read("eventLeadMinutes", Defaults.eventLeadMinutes)
        preventSleepOnLock = UserDefaults.standard.object(forKey: "preventSleepOnLock") as? Bool
            ?? Defaults.preventSleepOnLock
        preventSleepMinutes = Self.read("preventSleepMinutes", Defaults.preventSleepMinutes)
        showStatusIcon = UserDefaults.standard.object(forKey: "showStatusIcon") as? Bool ?? Defaults.showStatusIcon
        displayPolicy = IslandDisplayPolicy(stored: UserDefaults.standard.string(forKey: "displayPolicy"))

        isLoading = false
    }

    /// Window sizes include the fillet on each side, because the concave blends
    /// flare outward past the visible body to reach the screen edge.
    var collapsedWindowSize: CGSize {
        CGSize(width: collapsedWidth + fillet * 2, height: collapsedHeight)
    }

    var peekWindowSize: CGSize {
        CGSize(
            width: collapsedWidth + peekWidthGrowth + fillet * 2,
            height: collapsedHeight + peekHeightGrowth
        )
    }

    var expandedWindowSize: CGSize {
        CGSize(width: expandedWidth + fillet * 2, height: expandedHeight)
    }

    /// Idle footprint: exactly the notch's width, hanging a few points below it
    /// so there is something the pointer can actually reach.
    func idleSize(notch: CGSize) -> CGSize {
        CGSize(width: notch.width, height: notch.height + idleHeightExtra)
    }

    /// The panel is kept at this fixed size and never resized while animating —
    /// only the shape inside grows, anchored to the top edge. Animating the
    /// window frame instead makes AppKit scale the captured content, which
    /// briefly leaves a gap above the island.
    /// Tallest card the panel must hold without clipping.
    static let maxExpandedCardHeight: CGFloat = 260

    func containerSize(notch: CGSize, hasNotch: Bool) -> CGSize {
        let candidates: [CGSize] = [
            expandedWindowSize,
            collapsedWindowSize,
            islandSize(state: .peek, hasContent: true, notch: notch, hasNotch: hasNotch),
            islandSize(state: .peek, hasContent: false, notch: notch, hasNotch: hasNotch),
            glanceWindowSize,
            // Timer and call widen the collapsed island; the fixed panel must
            // hold it, or the hosting view stretches the window off-centre.
            DisplayGeometry.collapsedIslandSize(
                CGSize(width: wideEarsWidth(notch: notch, peek: true), height: collapsedHeight + peekHeightGrowth),
                notch: notch,
                hasNotch: hasNotch
            ),
            // Expanded cards hug their content (music ≈ 158pt, agenda up to
            // ≈ 240pt), which can outgrow `expandedHeight`. The panel is
            // click-through outside the shape, so extra height costs nothing.
            CGSize(width: expandedWindowSize.width, height: Self.maxExpandedCardHeight),
        ]
        return CGSize(
            width: candidates.map(\.width).max() ?? expandedWindowSize.width,
            height: candidates.map(\.height).max() ?? expandedWindowSize.height
        )
    }

    /// Tied to the collapsed island rather than fixed, so a glance never towers
    /// over the shape it grows out of.
    /// The glance grows below the notch: its text is wider than the wings
    /// beside the camera, so a single row at notch height would sit behind it.
    var glanceWindowSize: CGSize {
        CGSize(
            width: max(collapsedWidth, 280) + fillet * 2,
            height: collapsedHeight + glanceBodyHeight
        )
    }

    /// Width of each side ear, beside the camera, for timer and call content:
    /// room for a 1:05:09 countdown or a call's icon and duration.
    let wideEar: CGFloat = 64

    /// Island width (fillets included) with `wideEar` on both sides of the notch.
    func wideEarsWidth(notch: CGSize, peek: Bool) -> CGFloat {
        notch.width + wideEar * 2 + fillet * 2 + (peek ? peekWidthGrowth : 0)
    }

    /// Height of the glance's own row, under the notch-tall strip.
    let glanceBodyHeight: CGFloat = 46

    /// Collapsed and peek sizes are capped to the menu bar on displays without
    /// a hardware notch (see `DisplayGeometry.collapsedIslandSize`).
    func islandSize(state: IslandState, hasContent: Bool, notch: CGSize, hasNotch: Bool) -> CGSize {
        let size = islandSize(state: state, hasContent: hasContent, notch: notch)
        switch state {
        case .collapsed, .peek:
            return DisplayGeometry.collapsedIslandSize(size, notch: notch, hasNotch: hasNotch)
        default:
            return size
        }
    }

    private func islandSize(state: IslandState, hasContent: Bool, notch: CGSize) -> CGSize {
        switch state {
        case .glance:
            return glanceWindowSize
        case .hidden:
            return idleSize(notch: notch)
        case .collapsed:
            return collapsedWindowSize
        case .peek:
            // Growing from the idle footprint needs room for the fillets that
            // the idle state suppresses, so the visible body still widens.
            let idle = idleSize(notch: notch)
            let base = hasContent
                ? collapsedWindowSize
                : CGSize(width: idle.width + fillet * 2, height: idle.height)
            return CGSize(
                width: base.width + peekWidthGrowth,
                height: base.height + peekHeightGrowth
            )
        case .expanded:
            return expandedWindowSize
        }
    }

    func resetToDefaults() {
        isLoading = true
        collapsedWidth = Defaults.collapsedWidth
        collapsedHeight = Defaults.collapsedHeight
        expandedWidth = Defaults.expandedWidth
        expandedHeight = Defaults.expandedHeight
        fillet = Defaults.fillet
        collapsedBottomRadius = Defaults.collapsedBottomRadius
        expandedBottomRadius = Defaults.expandedBottomRadius
        idleBottomRadius = Defaults.idleBottomRadius
        bottomExponent = Defaults.bottomExponent
        topExponent = Defaults.topExponent
        collapsedArtwork = Defaults.collapsedArtwork
        expandedArtwork = Defaults.expandedArtwork
        collapsedPadding = Defaults.collapsedPadding
        expandedPadding = Defaults.expandedPadding
        expandedTopPadding = Defaults.expandedTopPadding
        titleFontSize = Defaults.titleFontSize
        artistFontSize = Defaults.artistFontSize
        peekWidthGrowth = Defaults.peekWidthGrowth
        peekHeightGrowth = Defaults.peekHeightGrowth
        animationDuration = Defaults.animationDuration
        showShadow = Defaults.showShadow
        idleHeightExtra = Defaults.idleHeightExtra
        lockScreenEnabled = Defaults.lockScreenEnabled
        lockScreenWidth = Defaults.lockScreenWidth
        lockScreenArtSize = Defaults.lockScreenArtSize
        lockScreenOffsetY = Defaults.lockScreenOffsetY
        lockCardLightTheme = Defaults.lockCardLightTheme
        lyricsEnabled = Defaults.lyricsEnabled
        calendarEnabled = Defaults.calendarEnabled
        remindersEnabled = Defaults.remindersEnabled
        eventLeadMinutes = Defaults.eventLeadMinutes
        preventSleepOnLock = Defaults.preventSleepOnLock
        preventSleepMinutes = Defaults.preventSleepMinutes
        showStatusIcon = Defaults.showStatusIcon
        displayPolicy = Defaults.displayPolicy
        isLoading = false
        persist()
    }

    private static func read(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }

    private func persist() {
        guard !isLoading else { return }
        let d = UserDefaults.standard
        d.set(collapsedWidth, forKey: "collapsedWidth")
        d.set(collapsedHeight, forKey: "collapsedHeight")
        d.set(expandedWidth, forKey: "expandedWidth")
        d.set(expandedHeight, forKey: "expandedHeight")
        d.set(fillet, forKey: "fillet")
        d.set(collapsedBottomRadius, forKey: "collapsedBottomRadius")
        d.set(expandedBottomRadius, forKey: "expandedBottomRadius")
        d.set(idleBottomRadius, forKey: "idleBottomRadius")
        d.set(bottomExponent, forKey: "bottomExponent")
        d.set(topExponent, forKey: "topExponent")
        d.set(collapsedArtwork, forKey: "collapsedArtwork")
        d.set(expandedArtwork, forKey: "expandedArtwork")
        d.set(collapsedPadding, forKey: "collapsedPadding")
        d.set(expandedPadding, forKey: "expandedPadding")
        d.set(expandedTopPadding, forKey: "expandedTopPadding")
        d.set(titleFontSize, forKey: "titleFontSize")
        d.set(artistFontSize, forKey: "artistFontSize")
        d.set(peekWidthGrowth, forKey: "peekWidthGrowth")
        d.set(peekHeightGrowth, forKey: "peekHeightGrowth")
        d.set(animationDuration, forKey: "animationDuration")
        d.set(showShadow, forKey: "showShadow")
        d.set(idleHeightExtra, forKey: "idleHeightExtra")
        d.set(lockScreenEnabled, forKey: "lockScreenEnabled")
        d.set(lockScreenWidth, forKey: "lockScreenWidth")
        d.set(lockScreenArtSize, forKey: "lockScreenArtSize")
        d.set(lockScreenOffsetY, forKey: "lockScreenOffsetY")
        d.set(lockCardLightTheme, forKey: "lockCardLightTheme")
        d.set(lyricsEnabled, forKey: "lyricsEnabled")
        d.set(calendarEnabled, forKey: "calendarEnabled")
        d.set(remindersEnabled, forKey: "remindersEnabled")
        d.set(eventLeadMinutes, forKey: "eventLeadMinutes")
        d.set(preventSleepOnLock, forKey: "preventSleepOnLock")
        d.set(preventSleepMinutes, forKey: "preventSleepMinutes")
        d.set(showStatusIcon, forKey: "showStatusIcon")
        d.set(displayPolicy.rawValue, forKey: "displayPolicy")
    }
}
