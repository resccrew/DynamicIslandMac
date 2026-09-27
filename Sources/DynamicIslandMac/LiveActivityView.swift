import IslandLogic
import SwiftUI

/// Pieces of a Live Activity pushed through `LiveActivityServer`. The island
/// places them itself: the collapsed ones go into its ears beside the camera,
/// the expanded one into its shared card frame.
enum LiveActivityParts {

    static func accent(_ activity: LiveActivity) -> Color {
        switch activity.state {
        case .success: return Accent.successGreen
        case .failure: return Accent.failureRed
        case .running: return activity.accentHex.flatMap(color(hex:)) ?? Accent.activityBlue
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
                DSSpinner(tint: LiveActivityParts.accent(activity), reduceMotion: reduceMotion)
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
}

struct LiveActivityExpanded: View {
    let activity: LiveActivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let accent = LiveActivityParts.accent(activity)
        let progress = activity.state == .running ? activity.progress : nil

        VStack(alignment: .leading, spacing: DS.Space.sectionGap.pt) {
            SymbolCardHeader(
                symbolName: LiveActivityParts.symbolName(activity),
                tint: accent,
                title: activity.title,
                subtitle: activity.subtitle
            ) {
                if let progress {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.dsLabel.monospacedDigit())
                        .foregroundStyle(accent)
                }
            }
            if activity.state == .running {
                DSProgressBar(
                    mode: progress.map { .determinate(fraction: $0) } ?? .indeterminate,
                    tint: accent,
                    reduceMotion: reduceMotion
                )
                .animation(.dsFade(reduceMotion: reduceMotion), value: progress)
            }
        }
    }
}
