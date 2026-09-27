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
        Image(systemName: LiveActivityParts.symbolName(activity))
            .font(.dsEar)
            .foregroundStyle(LiveActivityParts.accent(activity))
    }
}

/// Progress ring, spinner while indeterminate, or the percentage when done.
struct LiveActivityTrailing: View {
    let activity: LiveActivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch activity.state {
        case .running:
            if let progress = activity.progress {
                ZStack {
                    Circle().stroke(Color.white.opacity(.dsTrack), lineWidth: DS.Icon.ringStroke.pt)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(LiveActivityParts.accent(activity), style: StrokeStyle(lineWidth: DS.Icon.ringStroke.pt, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.dsFade(reduceMotion: reduceMotion), value: progress)
                }
                .frame(width: DS.Icon.ring.pt, height: DS.Icon.ring.pt)
            } else {
                DSSpinner(tint: LiveActivityParts.accent(activity), reduceMotion: reduceMotion)
            }
        case .success, .failure:
            Text(activity.title)
                .font(.dsLabel)
                .foregroundStyle(LiveActivityParts.accent(activity))
                .lineLimit(1)
                .frame(maxWidth: 70)
        }
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
