/// Whether the island shows the current track.
public enum IslandVisibility {
    /// Media fills the island while it plays, and — paused — for as long as
    /// the island is held open (hovered or click-opened), so a pause never
    /// pulls the card out from under the pointer. Once it closes, a paused
    /// track hides again (see `IslandViewModel.isIslandVisible`).
    public static func showsMedia(isPlaying: Bool, hasTrack: Bool, isOpen: Bool) -> Bool {
        hasTrack && (isPlaying || isOpen)
    }

    /// The collapsed/peek row is drawn for anything visible, and for a paused
    /// track while the island is held open.
    public static func rendersCollapsedContent(isIslandVisible: Bool, showsMedia: Bool) -> Bool {
        isIslandVisible || showsMedia
    }

    /// The whole island fades only when it goes to `.hidden`; a paused but
    /// open island stays fully opaque.
    public static func opacity(isHidden: Bool) -> Double {
        isHidden ? 0 : 1
    }
}
