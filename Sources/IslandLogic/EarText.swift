import Foundation

/// The text shown in a collapsed ear. It must never be cut with an ellipsis,
/// so every label is short by construction and `estimatedWidth` lets tests
/// prove it fits `CollapsedGeometry.contentWidth(earWidth:)` at the ear font
/// (SF Pro 13 semibold, tabular digits) for whatever ear width is in effect.
public enum EarText {
    /// Agenda: «28 мин» while an event runs (under an hour left),
    /// «до 14:30» when it runs longer, the plain start time before it starts.
    /// `clock` formats a date as `HH:mm`.
    /// Steps down the same way `duration` does when the normal phrasing does
    /// not fit a narrow ear: "N мин" -> "Nм", "до HH:mm" -> the bare time.
    public static func agenda(
        _ label: AgendaFormat.CollapsedLabel, clock: (Date) -> String, earWidth: Double = DS.Ear.width
    ) -> String {
        switch label {
        case .startsAt(let start):
            return clock(start)
        case .minutesLeft(let minutes):
            let full = "\(minutes) мин"
            if fits(full, earWidth: earWidth) { return full }
            return "\(minutes)м"
        case .endsAt(let end):
            let full = "до \(clock(end))"
            if fits(full, earWidth: earWidth) { return full }
            return clock(end)
        }
    }

    // Advance widths in points at 13pt semibold (rounded up a little).
    private static let digit = 8.0
    private static let colon = 3.6
    private static let space = 3.6
    private static let letter = 9.0

    /// Conservative width of `text`: digits and colons by their own advance,
    /// spaces, and every other character as a wide (Cyrillic) letter.
    public static func estimatedWidth(_ text: String) -> Double {
        text.reduce(0) { total, character in
            if character.isNumber { return total + digit }
            if character == ":" { return total + colon }
            if character == " " { return total + space }
            return total + letter
        }
    }

    /// Whether `text` fits an ear of `earWidth` at the smallest allowed scale.
    public static func fits(_ text: String, earWidth: Double = DS.Ear.width) -> Bool {
        estimatedWidth(text) * CollapsedGeometry.minTextScale <= CollapsedGeometry.contentWidth(earWidth: earWidth)
    }

    /// A running duration (call, timer) for the ear. `FormatTime.clock`'s full
    /// precision («1:02:05») is what the expanded card always shows, but a
    /// narrow ear — the «Компактный» size preset especially — can be too
    /// narrow for it even at the smallest allowed scale. Rather than let it
    /// clip, this steps down to whole minutes and, narrower still, to a bare
    /// number: always something exact and never cut with an ellipsis.
    public static func duration(_ seconds: Double, earWidth: Double = DS.Ear.width) -> String {
        let full = FormatTime.clock(seconds)
        if fits(full, earWidth: earWidth) { return full }

        let totalMinutes = Int((max(0, seconds) / 60).rounded())
        let minutes = "\(totalMinutes)м"
        if fits(minutes, earWidth: earWidth) { return minutes }

        return "\(totalMinutes)"
    }
}
