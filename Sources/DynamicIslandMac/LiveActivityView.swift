import IslandLogic
import SwiftUI

/// Pieces of a Live Activity pushed through `LiveActivityServer`. The island
/// places them itself: the collapsed ones go into its ears beside the camera,
/// the expanded one into its shared card frame.
enum LiveActivityParts {
    static let defaultAccent = Color(red: 0.35, green: 0.62, blue: 1.0)
    static let successGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let failureRed = Color(red: 1.0, green: 0.30, blue: 0.27)

    static func accent(_ activity: LiveActivity) -> Color {
        switch activity.state {
        case .success: return successGreen
        case .failure: return failureRed
        case .running: return activity.accentHex.flatMap(color(hex:)) ?? defaultAccent
        }
    }

    static func color(hex: String) -> Color? {
        guard let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// The pushed symbol if it exists, otherwise one that says the state.
    static func symbolName(_ activity: LiveActivity) -> String {
        switch activity.state {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        case .running:
            if let symbol = activity.symbol, NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil {
                return symbol
            }
            return "bolt.fill"
        }
    }
}

struct LiveActivityLeading: View {
    let activity: LiveActivity

    var body: some View {
        EarSymbol(name: symbol, tint: LiveActivityParts.accent(activity))
    }

    /// The pushed symbol in every state, so a finished activity still says
    /// what it was; the outcome is shown on the right.
    private var symbol: String {
        if let pushed = activity.symbol, NSImage(systemSymbolName: pushed, accessibilityDescription: nil) != nil {
            return pushed
        }
        return "bolt.fill"
    }
}

/// Progress ring, spinner while indeterminate, or the outcome glyph when done. The
/// ring, the equalizer and the ear symbols all share one height (`DS.Icon`).
struct LiveActivityTrailing: View {
    let activity: LiveActivity

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch activity.state {
        case .running:
            if let progress = activity.progress {
                ring(trim: progress)
                    .animation(.dsFade(reduceMotion: reduceMotion), value: progress)
            } else {
                spinner
            }
        case .success, .failure:
            EarSymbol(name: LiveActivityParts.symbolName(activity), tint: LiveActivityParts.accent(activity))
        }
    }

    private func ring(trim: Double) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(.dsTrack), lineWidth: DS.Icon.ringStroke)
            Circle()
                .trim(from: 0, to: trim)
                .stroke(LiveActivityParts.accent(activity), style: StrokeStyle(lineWidth: DS.Icon.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: DS.Icon.ring, height: DS.Icon.ring)
    }

    /// Indeterminate: a quarter arc turning once a second, drawn like the
    /// ring rather than the system spinner. Still under Reduce Motion.
    private var spinner: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            ZStack {
                Circle().stroke(Color.white.opacity(.dsTrack), lineWidth: DS.Icon.ringStroke)
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(LiveActivityParts.accent(activity), style: StrokeStyle(lineWidth: DS.Icon.ringStroke, lineCap: .round))
                    .rotationEffect(.degrees(reduceMotion ? -90 : turn * 360 - 90))
            }
            .frame(width: DS.Icon.ring, height: DS.Icon.ring)
        }
    }
}

struct LiveActivityExpanded: View {
    let activity: LiveActivity

    var body: some View {
        let accent = LiveActivityParts.accent(activity)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: LiveActivityParts.symbolName(activity))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(.dsCardTitle)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let subtitle = activity.subtitle {
                        Text(subtitle)
                            .font(.dsBody)
                            .foregroundStyle(.white.opacity(.dsSecondary))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if activity.state == .running, let progress = activity.progress {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.dsEar)
                        .foregroundStyle(accent)
                        .monospacedDigit()
                }
            }
            if activity.state == .running {
                if let progress = activity.progress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(.dsTrack))
                            Capsule().fill(accent).frame(width: proxy.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                    .animation(.easeOut(duration: 0.3), value: progress)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(accent)
                }
            }
        }
    }
}
