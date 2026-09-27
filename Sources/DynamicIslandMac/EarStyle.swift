import SwiftUI
import IslandLogic

/// Fonts and pieces shared by everything drawn in the collapsed ears
/// (media, call, timer, agenda, live activity), built only from `DS` tokens.
extension Font {
    /// The SF Symbol beside an ear's label (timer, calendar, phone, activity).
    static var dsEarSymbol: Font { .system(size: DS.Icon.earSymbol, weight: .semibold) }
    /// A secondary symbol next to it (the camera glyph beside a call's time).
    static var dsEarSecondary: Font { .system(size: DS.Icon.earSecondary, weight: .semibold) }
}

/// An SF Symbol in an ear: always the same `DS.Icon.earSlot` square, centred,
/// so timer, calendar, activity and status glyphs share one size and one
/// baseline whatever their natural proportions.
struct EarSymbol: View {
    let name: String
    let tint: Color

    var body: some View {
        Image(systemName: name)
            .font(.dsEarSymbol)
            .foregroundStyle(tint)
            .frame(width: DS.Icon.earSlot, height: DS.Icon.earSlot)
    }
}

extension View {
    /// Keeps an ear's text inside the ear: it shrinks (never below
    /// `CollapsedGeometry.minTextScale`) rather than sliding under the camera.
    /// `earWidth` is the live setting (`IslandSettings.earWidth`) — the
    /// compact preset leaves noticeably less room than the default.
    func fitsEar(earWidth: Double) -> some View {
        self
            .lineLimit(1)
            .minimumScaleFactor(CollapsedGeometry.minTextScale)
            .frame(maxWidth: CollapsedGeometry.contentWidth(earWidth: earWidth))
    }
}
