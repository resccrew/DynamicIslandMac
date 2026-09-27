import CoreGraphics

/// Numbers that belong to the lock screen only. Everything that the island
/// also has (fonts, opacities, radii, spacing, control sizes) comes from `DS`;
/// what is left here has no `DS` token yet.
enum LockMetrics {
    /// Cover in the compact card: the island's `DS.Card.lead` scaled up for the bigger screen.
    static let compactArtwork: CGFloat = 84
    /// The expanded card is as wide as the cover, so both share one left and right edge.
    static let playerWidthToArtwork: CGFloat = 1
    /// Gap between the player and the lyrics column.
    static let playerToLyrics: CGFloat = 56

    /// Placeholder glyph in a cover-less tile, relative to the tile size.
    static let placeholderGlyphRatio: CGFloat = 0.36

    enum Lyrics {
        static let fontSize: CGFloat = 21
        static let lineHeight: CGFloat = 62
        static let visibleLines: CGFloat = 5
        /// Column width relative to the cover, so the two stay in proportion at any cover size.
        static let widthToArtwork: CGFloat = 1.1
        static let fadeEdge: Double = 0.18
        static let inactiveOpacity: Double = 0.3
        static let glowOpacity: Double = 0.35
        static let glowRadius: CGFloat = 10
        /// How long an empty list reads as «Ищем текст…» before it turns into «Текст не найден».
        static let searchSeconds: Double = 4
    }

    enum Shadow {
        static let artworkOpacity: Double = 0.35
        static let artworkRadius: CGFloat = 18
        static let artworkY: CGFloat = 8
        static let cardLightOpacity: Double = 0.25
        static let cardDarkOpacity: Double = 0.4
        static let cardRadius: CGFloat = 20
        static let cardY: CGFloat = 8
    }

    enum Backdrop {
        static let blur: CGFloat = 120
        static let scale: CGFloat = 1.25
        static let saturation: Double = 1.8
        static let scrimTop: Double = 0.18
        static let scrimBottom: Double = 0.38
    }

    /// Dark card background, close to the island's black but readable against the wash.
    static let darkCardWhite: Double = 0.1

    enum Transition {
        static let expandedScale: CGFloat = 0.9
        static let compactScale: CGFloat = 1.05
    }

    /// Idle fill of the «Текст» chip (the active one uses `DS.Opacity.track`).
    static let chipIdleFill: Double = 0.12
}
