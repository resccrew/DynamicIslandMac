import Foundation

/// The text shown in a collapsed ear. It must never be cut with an ellipsis,
/// so every label is short by construction and `estimatedWidth` lets tests
/// prove it fits `CollapsedGeometry.contentWidth` at the ear font (SF Pro
/// 13 semibold, tabular digits).
public enum EarText {
    /// Agenda: «28 мин» while an event runs (under an hour left),
    /// «до 14:30» when it runs longer, the plain start time before it starts.
    /// `clock` formats a date as `HH:mm`.
    public static func agenda(_ label: AgendaFormat.CollapsedLabel, clock: (Date) -> String) -> String {
        switch label {
        case .startsAt(let start): return clock(start)
        case .minutesLeft(let minutes): return "\(minutes) мин"
        case .endsAt(let end): return "до \(clock(end))"
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

    /// Whether `text` fits an ear at the smallest allowed scale.
    public static func fits(_ text: String) -> Bool {
        estimatedWidth(text) * CollapsedGeometry.minTextScale <= CollapsedGeometry.contentWidth
    }
}
