import SwiftUI
import IslandLogic

// MARK: - Typography

extension Font {
    /// Builds a `Font` from a pure `DS.FontSpec` token.
    static func ds(_ spec: DS.FontSpec) -> Font {
        let weight: Font.Weight
        switch spec.weight {
        case .regular: weight = .regular
        case .medium: weight = .medium
        case .semibold: weight = .semibold
        }
        let design: Font.Design = spec.rounded ? .rounded : .default
        var font = Font.system(size: spec.size, weight: weight, design: design)
        if spec.monospacedDigit {
            font = font.monospacedDigit()
        }
        return font
    }
}

extension Font {
    static var dsEar: Font { .ds(DS.TypeScale.ear) }
    static var dsCardTitle: Font { .ds(DS.TypeScale.cardTitle) }
    static var dsBody: Font { .ds(DS.TypeScale.body) }
    static var dsLabel: Font { .ds(DS.TypeScale.label) }
    static var dsCaption: Font { .ds(DS.TypeScale.caption) }
    static var dsDisplay: Font { .ds(DS.TypeScale.display) }
}

// MARK: - Text opacity levels

extension Double {
    /// Three text levels + dimmed + track — see DESIGN-DECISIONS.md "Прозрачность".
    /// No other opacity value should appear in UI code.
    static var dsPrimary: Double { DS.Opacity.primary }
    static var dsSecondary: Double { DS.Opacity.secondary }
    static var dsTertiary: Double { DS.Opacity.tertiary }
    static var dsDimmed: Double { DS.Opacity.dimmed }
    static var dsTrack: Double { DS.Opacity.track }
}

// MARK: - Accent colors

/// One place for every accent color on the island, the lock screen, and Live
/// Activities. Audit A/B found several near-duplicate RGB triples declared in
/// separate files — merged here:
/// - `callGreen` (IslandView.swift:222) and `successGreen` (LiveActivityView.swift:9)
///   were the exact same RGB (0.19, 0.82, 0.35) — kept as one value, two names.
/// - `calendarRed` (IslandView.swift:372, 1.0/0.27/0.23) and `failureRed`
///   (LiveActivityView.swift:10, 1.0/0.30/0.27) were two slightly different
///   reds for the same meaning ("bad/overdue/failed"). DESIGN-DECISIONS.md
///   says they must be equal; picked `calendarRed`'s value as canonical
///   (it's the older, more-used one) — flagged in the phase-2 report as a
///   value invented/resolved here, not present verbatim in either audit or
///   the decisions doc.
public enum Accent {
    public static let callGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
    public static let successGreen = callGreen

    public static let calendarRed = Color(red: 1.0, green: 0.27, blue: 0.23)
    public static let failureRed = calendarRed

    public static let remindersBlue = Color(red: 0.04, green: 0.52, blue: 1.0)
    public static let timerOrange = Color(red: 1.0, green: 0.62, blue: 0.04)
    public static let activityBlue = Color(red: 0.35, green: 0.62, blue: 1.0)

    /// Default media accent before artwork color extraction finishes.
    public static let mediaDefault = Color(red: 0.80, green: 0.70, blue: 0.58)
}

// MARK: - Motion

extension Animation {
    private static func animation(for kind: DS.MotionCurveKind) -> Animation {
        switch kind {
        case let .spring(response, damping):
            return .spring(response: response, dampingFraction: damping)
        case let .easeOut(duration):
            return .easeOut(duration: duration)
        }
    }

    /// Resolves a design-system motion token to a real `Animation`, honoring
    /// Reduce Motion (springs/scale/flip collapse to a plain fade).
    static func ds(_ kind: DS.MotionCurveKind, reduceMotion: Bool) -> Animation {
        animation(for: DS.Motion.resolve(reduceMotion: reduceMotion, requested: kind))
    }

    static func dsState(reduceMotion: Bool) -> Animation { .ds(DS.Motion.state, reduceMotion: reduceMotion) }
    static func dsFade(reduceMotion: Bool) -> Animation { .ds(DS.Motion.fade, reduceMotion: reduceMotion) }
    static func dsMicro(reduceMotion: Bool) -> Animation { .ds(DS.Motion.micro, reduceMotion: reduceMotion) }
}

// MARK: - CardHeader

/// Shared header for every expanded card (media/call/agenda/activity/glance):
/// a leading element (artwork, app icon, or an SF Symbol in a fixed column),
/// a title, and an optional subtitle — left edges aligned across all cards.
struct CardHeader<Lead: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var titleFont: Font = .dsCardTitle
    var subtitleFont: Font = .dsBody
    @ViewBuilder let lead: () -> Lead
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        titleFont: Font = .dsCardTitle,
        subtitleFont: Font = .dsBody,
        @ViewBuilder lead: @escaping () -> Lead,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleFont = titleFont
        self.subtitleFont = subtitleFont
        self.lead = lead
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: DS.Space.leadGap) {
            lead()
            VStack(alignment: .leading, spacing: DS.Space.titleGap) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(.white.opacity(.dsPrimary))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(subtitleFont)
                        .foregroundStyle(.white.opacity(.dsSecondary))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
    }
}

/// A `CardHeader` whose leading element is an SF Symbol centered in the
/// shared `headerIconColumn` (agenda / activity / glance).
struct SymbolCardHeader<Trailing: View>: View {
    let symbolName: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(
        symbolName: String,
        tint: Color,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.symbolName = symbolName
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        CardHeader(title: title, subtitle: subtitle) {
            Image(systemName: symbolName)
                .font(.system(size: DS.Card.headerIcon, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: DS.Card.headerIconColumn)
        } trailing: {
            trailing()
        }
    }
}

// MARK: - Progress bar

/// 4pt progress bar shared by media/timer/activity. The indeterminate
/// variant is drawn by us (a moving segment), never the system `ProgressView`.
struct DSProgressBar: View {
    enum Mode {
        case determinate(fraction: Double)
        case indeterminate
    }

    var mode: Mode
    var tint: Color
    var paused: Bool = false
    var reduceMotion: Bool = false
    /// The bar's empty track; white by default, black-on-light for the light lock card.
    var trackColor: Color = Color.white.opacity(.dsTrack)

    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                switch mode {
                case let .determinate(fraction):
                    Capsule()
                        .fill(tint.opacity(paused ? .dsDimmed : 1))
                        .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
                case .indeterminate:
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * 0.32)
                        .offset(x: phase * (geo.size.width * 0.68))
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: true)) {
                                phase = 1
                            }
                        }
                }
            }
        }
        .frame(height: DS.Bar.thickness)
    }
}

// MARK: - CapsuleButton

/// The pill-shaped CTA used by call/timer/glance ("Открыть", "Подключиться" …).
struct CapsuleButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = .white
    var fillOpacity: Double = 0.12
    var textOpacity: Double = .dsPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            // A capsule never wraps or shrinks: the text beside it gives way.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .font(.dsLabel)
            .foregroundStyle(tint.opacity(textOpacity))
            .padding(.horizontal, DS.Button.capsuleHorizontal)
            .padding(.vertical, DS.Button.capsuleVertical)
            .frame(minHeight: DS.Button.minHitArea)
            .background(Capsule().fill(tint.opacity(fillOpacity)))
        }
        .buttonStyle(MediaButtonStyle(diameter: 0, tint: tint))
    }
}
