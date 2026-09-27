import Foundation

/// Pure geometry of the collapsed island and its peek (hover) state, built on
/// the `DS` tokens. Kept free of AppKit/SwiftUI so the rules that make the
/// island look "one grid" — the same width for every kind of content, content
/// that stands still while peek grows the silhouette — can be unit-tested.
///
/// Zone A of the unified design (see DESIGN-DECISIONS.md).
public enum CollapsedGeometry {
    /// One squircle (Lamé) exponent for every corner in every state, so the
    /// shape never "clicks" between collapsed, peek, hidden and expanded.
    public static let shapeExponent: Double = 2.2

    /// Smallest scale an ear label may shrink to. Ear text is never cut with
    /// an ellipsis: labels are written short enough (see `EarText`) to fit at
    /// full size, and this only absorbs font-metric error. Local to zone A;
    /// promote to `DS` if other zones need it.
    public static let minTextScale: Double = 0.85

    /// Height of the collapsed pill: the notch plus a `Space.s` lip below it.
    public static func height(notchHeight: Double) -> Double {
        notchHeight + DS.Space.s
    }

    /// Visible body width, fillets excluded: notch + one ear on each side.
    public static func bodyWidth(notchWidth: Double) -> Double {
        DS.collapsedWidth(notchWidth: notchWidth)
    }

    /// Window width: the concave fillets flare outward past the body.
    public static func windowWidth(notchWidth: Double, fillet: Double) -> Double {
        bodyWidth(notchWidth: notchWidth) + 2 * fillet
    }

    /// Width of one ear column for an island of `islandWidth` (fillets
    /// included). Collapsed this is exactly `DS.Ear.width`; peek adds half of
    /// the growth on each side.
    public static func earWidth(islandWidth: Double, fillet: Double, notchWidth: Double) -> Double {
        max(0, (islandWidth - 2 * fillet - notchWidth) / 2)
    }

    /// Distance from the outer edge of an ear to its content. It is
    /// `DS.Ear.inset` measured from the *collapsed* ear, so in peek — where the
    /// ear is wider — the extra width is added and the content stays exactly
    /// where it was: peek grows the silhouette, not the layout.
    public static func contentInset(earWidth: Double) -> Double {
        DS.Ear.inset + max(0, earWidth - DS.Ear.width)
    }

    /// Width available to an ear's content once the inset is taken off the
    /// collapsed ear.
    public static var contentWidth: Double {
        DS.Ear.width - DS.Ear.inset
    }

    /// Height of the row the ears' content is centred in: the *collapsed*
    /// silhouette, never the peek one (peek adds height below, content stays).
    public static func contentRowHeight(collapsedHeight: Double) -> Double {
        collapsedHeight
    }

    /// Bottom radius by state: half the height for the collapsed pill and
    /// peek, the idle and card radii otherwise. `nil` height means the state
    /// has its own fixed radius.
    public static func bottomRadius(collapsedLike height: Double) -> Double {
        DS.Radius.collapsedBottom(height: height)
    }

    /// Peek growth, on the spacing scale: `2·Space.m` wider (each side gets
    /// one `Space.m`), `Space.xs` taller.
    public static var defaultPeekWidthGrowth: Double { 2 * DS.Space.m }
    public static var defaultPeekHeightGrowth: Double { DS.Space.xs }
}
