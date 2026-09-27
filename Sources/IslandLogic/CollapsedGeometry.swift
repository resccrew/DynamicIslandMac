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

    /// Height of the collapsed pill: exactly the notch, so it never reaches
    /// below the menu bar into the working area.
    public static func height(notchHeight: Double) -> Double {
        notchHeight
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

    /// Clear space kept between an ear's content and the camera cutout.
    public static var notchGap: Double { DS.Space.s }

    /// Width available to an ear's content: the collapsed ear minus the outer
    /// inset and the gap to the notch, so nothing ever touches the camera.
    public static var contentWidth: Double {
        DS.Ear.width - DS.Ear.inset - notchGap
    }

    /// Icons of apps (Telegram, Chrome…) carry transparent margins and read
    /// smaller than cover art of the same frame; they are drawn this much
    /// larger. Covers are not scaled.
    public static let appIconScale: Double = 1.15

    /// Width of the call ear's leading group: app icon, and the camera glyph
    /// beside it when the camera is on. The camera lives on the left so the
    /// right ear only ever holds the duration, however long the call.
    public static func callLeadingWidth(cameraOn: Bool) -> Double {
        cameraOn ? DS.Icon.earSlot + DS.Ear.gap + DS.Icon.earSlot : DS.Icon.earSlot
    }

    /// Expanded card width (fillets excluded) equal to the peek width, so a
    /// card does not narrow when it opens: `peek − 2·fillet` = body + growth.
    public static func expandedWidth(notchWidth: Double, peekGrowth: Double) -> Double {
        bodyWidth(notchWidth: notchWidth) + peekGrowth
    }

    /// Height of the row the ears' content is centred in: the notch itself —
    /// not the collapsed silhouette (which is `Space.s` taller: a small lip
    /// below the notch, unchanged in peek) and not the peek silhouette. On a
    /// real notch the row therefore sits exactly under the camera cutout.
    public static func contentRowHeight(notchHeight: Double) -> Double {
        notchHeight
    }

    /// Visual size of the leading slot (cover art / app icon) in an ear,
    /// scaled to the notch: comfortably inside it with `Space.s` of breathing
    /// room top and bottom, so a taller notch reads a proportionally bigger
    /// slot instead of the same fixed size everywhere.
    public static func earIconSlot(notchHeight: Double) -> Double {
        max(0, notchHeight - 2 * DS.Space.s)
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
