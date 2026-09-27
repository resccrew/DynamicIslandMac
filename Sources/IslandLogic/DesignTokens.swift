import Foundation

/// Single source of truth for every design constant used across the island,
/// the lock screen, and settings — collapsed pill, expanded card, and lock
/// screen alike. Values here mirror `DesignSystem.swift` in
/// `DynamicIslandMac-design/DESIGN-DECISIONS.md` exactly; nothing in this file
/// depends on AppKit or SwiftUI, so it can be unit-tested and reused by any
/// layer (geometry, view models, previews).
///
/// This file is written once (phase 2) and after that changes only through
/// the orchestrator — see "Зоны файлов для фазы 3" in DESIGN-DECISIONS.md.
public enum DS {

    // MARK: - Spacing

    /// The one spacing scale used everywhere: `[2, 4, 6, 8, 12, 16, 27]`.
    public enum Space {
        public static let xxs: Double = 2
        public static let xs: Double = 4
        public static let s: Double = 6
        public static let m: Double = 8
        public static let l: Double = 12
        public static let xl: Double = 16
        /// Card side margin (12 + fillet 13, kept as its own named token since
        /// it is derived, not picked from the raw scale).
        public static let cardSide: Double = 27

        /// title ↔ subtitle gap in `CardHeader`.
        public static let titleGap: Double = xxs
        /// lead element (artwork / app icon / SF symbol slot) ↔ text column.
        public static let leadGap: Double = l
        /// header ↔ progress / controls / list section gap.
        public static let sectionGap: Double = l
        /// gap between rows inside a list (agenda entries).
        public static let rowGap: Double = s
        /// time label ↔ progress bar, icon ↔ text within a single row.
        public static let inlineGap: Double = m
        /// card content starts this far below the notch.
        public static let cardTopBelowNotch: Double = s
        /// card bottom padding.
        public static let cardBottom: Double = l

        /// The full raw scale, for validating that nothing invents new values.
        public static let scale: [Double] = [xxs, xs, s, m, l, xl, cardSide]
    }

    // MARK: - Ear (collapsed / peek)

    public enum Ear {
        /// One ear width for every content kind (media/timer/call/agenda/activity)
        /// so the island never changes width when the content kind changes.
        public static let width: Double = 64
        /// Distance from the outer edge of the ear to its content — identical
        /// in collapsed and peek (peek grows the silhouette, not the inset).
        public static let inset: Double = Space.m
        /// Gap between elements inside one ear.
        public static let gap: Double = Space.s
    }

    // MARK: - Icons

    public enum Icon {
        /// Visual slot for the leading element in an ear (artwork / app icon).
        public static let earSlot: Double = 22
        /// SF Symbol size inside an ear.
        public static let earSymbol: Double = 14
        /// Secondary SF Symbol size inside an ear (e.g. video glyph next to phone).
        public static let earSecondary: Double = 11
        /// Collapsed progress ring diameter + stroke.
        public static let ring: Double = 14
        public static let ringStroke: Double = 2
        /// Equalizer bar height (= earSymbol) and width.
        public static let eqBarHeight: Double = 14
        public static let eqBarWidth: Double = 2
    }

    // MARK: - Card (expanded card header, `CardHeader`)

    public enum Card {
        /// Leading slot shared by media/call/timer/agenda/activity `CardHeader`.
        public static let lead: Double = 54
        /// SF Symbol size in the header when there is no artwork/app icon.
        public static let headerIcon: Double = 20
        /// Column width the header icon is centered in.
        public static let headerIconColumn: Double = 30
        /// Minimum panel height so tall cards (agenda) aren't clipped.
        public static let maxExpandedHeight: Double = 260
    }

    // MARK: - Buttons

    public enum Button {
        /// Primary circular button (play/pause, agenda action).
        public static let primary: Double = 32
        /// Invisible hit-frame around secondary icon buttons (transport,
        /// call indicators). The icon glyph itself is 13–14pt.
        public static let secondaryHitFrame: Double = 28
        public static let secondaryIconMin: Double = 13
        public static let secondaryIconMax: Double = 14
        /// Capsule button padding.
        public static let capsuleHorizontal: Double = Space.l
        public static let capsuleVertical: Double = Space.s
        /// Minimum hit-area for any interactive control.
        public static let minHitArea: Double = 28
    }

    // MARK: - Progress bar

    public enum Bar {
        public static let thickness: Double = 4
        public static let trackOpacity: Double = Opacity.track
    }

    // MARK: - Radii

    public enum Radius {
        /// Concave fillet at the top, shared by every non-hidden state.
        public static let fillet: Double = 13
        /// Bottom radius of the expanded card.
        public static let expandedBottom: Double = 36
        /// Bottom radius while hidden (idle).
        public static let idle: Double = 9
        /// Lock screen card corner radius.
        public static let lockCard: Double = 22
        /// Artwork/app-icon corner ratio (radius = size * ratio), unified
        /// across island card, ear slot, and lock screen artwork.
        public static let artworkRatio: Double = 0.21

        /// Bottom radius of the collapsed pill: exactly half its height, no
        /// clamp artifact (audit A found the old settings value 26 being
        /// clamped down to 25 at render time — this formula removes that gap).
        public static func collapsedBottom(height: Double) -> Double {
            height / 2
        }
    }

    // MARK: - Opacity (three text levels + dimmed + track — nothing else)

    public enum Opacity {
        public static let primary: Double = 1.0
        public static let secondary: Double = 0.6
        public static let tertiary: Double = 0.4
        /// Paused / inactive state (equalizer dots, off indicators).
        public static let dimmed: Double = 0.4
        /// Progress bar track.
        public static let track: Double = 0.22

        /// All distinct opacity levels the design system defines, ordered.
        /// `dimmed == tertiary` by decision (both 0.4) — kept as separate
        /// names because they describe different things, not different values.
        public static let orderedLevels: [Double] = [track, tertiary, secondary, primary]
    }

    // MARK: - Motion

    /// Curve "kind" a token resolves to once Reduce Motion is taken into
    /// account. AppKit/SwiftUI-free so it can be unit tested; the SwiftUI
    /// layer (`DesignSystem.swift`) turns this into a real `Animation`.
    public enum MotionCurveKind: Equatable {
        case spring(response: Double, damping: Double)
        case easeOut(duration: Double)
    }

    public enum Motion {
        /// All state transitions (size/shape changes), glance included.
        public static let stateResponse: Double = 0.32
        public static let stateDamping: Double = 0.86
        /// Fades — content appearing/disappearing, progress, the ring.
        public static let fadeDuration: Double = 0.32
        /// Flips (artwork), the equalizer, and press feedback.
        public static let microDuration: Double = 0.22

        public static let state = MotionCurveKind.spring(response: stateResponse, damping: stateDamping)
        public static let fade = MotionCurveKind.easeOut(duration: fadeDuration)
        public static let micro = MotionCurveKind.easeOut(duration: microDuration)

        /// The three motion tokens, for exhaustiveness tests.
        public static let all: [MotionCurveKind] = [state, fade, micro]

        /// With Reduce Motion on, only a fade is ever used — no springs, no
        /// scale, no flip (`accessibilityDisplayShouldReduceMotion`).
        public static func resolve(reduceMotion: Bool, requested: MotionCurveKind) -> MotionCurveKind {
            guard reduceMotion else { return requested }
            switch requested {
            case .spring:
                return .easeOut(duration: fadeDuration)
            case .easeOut:
                return requested
            }
        }
    }

    // MARK: - Typography

    public enum FontWeight {
        case regular
        case medium
        case semibold
    }

    public struct FontSpec: Equatable {
        public let size: Double
        public let weight: FontWeight
        public let monospacedDigit: Bool
        public let rounded: Bool

        public init(size: Double, weight: FontWeight, monospacedDigit: Bool = false, rounded: Bool = false) {
            self.size = size
            self.weight = weight
            self.monospacedDigit = monospacedDigit
            self.rounded = rounded
        }
    }

    public enum TypeScale {
        /// Ear label (call duration, timer countdown, agenda time).
        public static let ear = FontSpec(size: 13, weight: .semibold, monospacedDigit: true)
        /// Title shared by every card header, and the lock screen (one weight
        /// everywhere — no more 16 medium/semibold on the lock screen).
        public static let cardTitle = FontSpec(size: 15, weight: .semibold)
        /// Subtitle / list row text.
        public static let body = FontSpec(size: 12, weight: .regular)
        /// CTA text, list row time/value.
        public static let label = FontSpec(size: 12, weight: .semibold)
        /// Progress-row time, "LIVE" badge base size.
        public static let caption = FontSpec(size: 11, weight: .medium, monospacedDigit: true)
        /// Timer's big number.
        public static let display = FontSpec(size: 34, weight: .semibold, monospacedDigit: true, rounded: true)
    }

    // MARK: - Pure geometry helpers

    /// `collapsedWidth = notchWidth + 2 · earWidth`. Width no longer depends
    /// on content kind (media used to be 306pt, timer/call/agenda/activity
    /// 339pt — audit A, finding #1).
    public static func collapsedWidth(notchWidth: Double) -> Double {
        notchWidth + 2 * Ear.width
    }

    /// Height of the ear's content column: the silhouette height minus the
    /// vertical room taken by `Ear.inset` on both top and bottom, so content
    /// centers in the visible silhouette instead of the notch-clamped row.
    public static func earContentHeight(silhouetteHeight: Double) -> Double {
        max(0, silhouetteHeight - 2 * Ear.inset)
    }

    /// `Ear.inset` is a constant, not derived from silhouette size — this
    /// helper exists so call sites never hardcode `8` again.
    public static func earContentInset() -> Double {
        Ear.inset
    }
}
