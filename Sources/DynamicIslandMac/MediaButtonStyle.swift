import SwiftUI
import IslandLogic

/// Gives transport buttons physical feedback: the glyph presses in while a
/// circular highlight blooms behind it, then springs back.
struct MediaButtonStyle: ButtonStyle {
    var diameter: CGFloat = 38
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration, diameter: diameter, tint: tint)
    }

    /// Reads Reduce Motion, which a `ButtonStyle` cannot do directly.
    private struct PressBody: View {
        let configuration: Configuration
        let diameter: CGFloat
        let tint: Color
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private static let pressedScale: CGFloat = 0.9

        var body: some View {
            configuration.label
                .background(
                    Circle()
                        .fill(tint.opacity(configuration.isPressed ? .dsTrack : 0))
                        .frame(width: diameter, height: diameter)
                )
                .scaleEffect(configuration.isPressed && !reduceMotion ? Self.pressedScale : 1)
                .animation(.dsMicro(reduceMotion: reduceMotion), value: configuration.isPressed)
        }
    }
}

/// A transport button.
///
/// The press effect alone is barely visible, because a click holds the button
/// down for only a few milliseconds and the animation dies with it. Counting
/// taps drives a bounce that plays out after the finger is gone, so the
/// feedback is seen no matter how briefly the button was held.
struct MediaButton: View {
    let systemName: String
    let size: CGFloat
    var opacity: Double = 1
    var width: CGFloat = 34
    var height: CGFloat = 28
    var highlightDiameter: CGFloat = 38
    var tint: Color = .white
    let action: () -> Void

    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint.opacity(opacity))
                // Play and pause morph into one another instead of cutting.
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .speed(1.7), value: taps)
                .frame(width: width, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(MediaButtonStyle(diameter: highlightDiameter, tint: tint))
    }
}
