/// Whether the island shows the current track.
public enum IslandVisibility {
    /// A loaded track keeps the island visible, paused or not, for as long as
    /// its source still reports it (the tab/app is open). A source that goes
    /// away clears the title, which hides the island. With `hideWhenPaused`
    /// on, only a playing track counts (the old behaviour).
    public static func mediaVisible(isPlaying: Bool, hasTrack: Bool, hideWhenPaused: Bool) -> Bool {
        hasTrack && (isPlaying || !hideWhenPaused)
    }

    /// Media fills the island whenever it is visible, and — paused, with
    /// `hideWhenPaused` on — for as long as the island is held open (hovered
    /// or click-opened), so a pause never pulls the card out from under the
    /// pointer.
    public static func showsMedia(isPlaying: Bool, hasTrack: Bool, isOpen: Bool, hideWhenPaused: Bool) -> Bool {
        mediaVisible(isPlaying: isPlaying, hasTrack: hasTrack, hideWhenPaused: hideWhenPaused)
            || (hasTrack && isOpen)
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
