import SwiftUI
import IslandLogic

/// Layout and control pieces shared by the expanded cards (media, call, timer,
/// agenda, live activity, glance). Everything is built from `DS` tokens.

extension Double {
    /// A design-token value as a layout length.
    var pt: CGFloat { CGFloat(self) }
}

extension Font {
    /// Glyph of a card button (transport, call indicators, primary circles).
    static var dsButtonIcon: Font {
        .ds(DS.FontSpec(size: DS.Button.secondaryIconMin, weight: .semibold))
    }
}

/// Rounded-square clip of an artwork or app icon in a card's leading slot.
struct CardLeadClip: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: DS.Card.lead.pt, height: DS.Card.lead.pt)
            .clipShape(RoundedRectangle(cornerRadius: (DS.Card.lead * DS.Radius.artworkRatio).pt, style: .continuous))
    }
}

/// A round, filled button (play/pause, join, done).
struct CardPrimaryButton: View {
    let symbol: String
    var glyph: Color = .white
    var fill: Color
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.dsButtonIcon)
                .foregroundStyle(glyph)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: DS.Button.primary.pt, height: DS.Button.primary.pt)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(MediaButtonStyle(diameter: DS.Button.primary.pt, tint: fill))
        .help(help ?? "")
        .accessibilityLabel(help ?? "")
    }
}

/// A bare icon button with the shared 28pt hit-frame.
struct CardIconButton: View {
    let symbol: String
    var opacity: Double = .dsSecondary
    var tint: Color = .white
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.dsButtonIcon)
                .foregroundStyle(tint.opacity(opacity))
                .frame(width: DS.Button.secondaryHitFrame.pt, height: DS.Button.secondaryHitFrame.pt)
                .contentShape(Rectangle())
        }
        .buttonStyle(MediaButtonStyle(diameter: DS.Button.secondaryHitFrame.pt, tint: tint))
        .help(help ?? "")
    }
}

/// A non-interactive status glyph in a soft circle (call mic/camera state).
struct CardIndicator: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.dsButtonIcon)
            .foregroundStyle(tint)
            .frame(width: DS.Button.secondaryHitFrame.pt, height: DS.Button.secondaryHitFrame.pt)
            .background(Circle().fill(Color.white.opacity(.dsTrack)))
    }
}

/// The shared frame of every expanded card: side margin, a small gap under
/// the camera cutout, a bottom margin; reports its natural height.
extension View {
    func cardFrame(notchHeight: CGFloat) -> some View {
        self
            .padding(.horizontal, DS.Space.cardSide.pt)
            .padding(.top, notchHeight + DS.Space.cardTopBelowNotch.pt)
            .padding(.bottom, DS.Space.cardBottom.pt)
    }
}

/// Indeterminate activity ring: a quarter arc turning in the ring's track.
/// Drawn by us — the system `ProgressView` renders as a yellow "unavailable"
/// placeholder inside the island's `drawingGroup`.
struct DSSpinner: View {
    var tint: Color
    var reduceMotion: Bool = false

    @State private var turning = false

    private enum Spin {
        static let arc = 0.28
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(.dsTrack), lineWidth: DS.Icon.ringStroke.pt)
            Circle()
                .trim(from: 0, to: Spin.arc)
                .stroke(tint, style: StrokeStyle(lineWidth: DS.Icon.ringStroke.pt, lineCap: .round))
                .rotationEffect(.degrees(turning ? 360 : 0))
        }
        .frame(width: DS.Icon.ring.pt, height: DS.Icon.ring.pt)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: DS.Motion.indeterminatePeriod).repeatForever(autoreverses: false)) {
                turning = true
            }
        }
    }
}
