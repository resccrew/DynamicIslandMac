import SwiftUI

/// Gives transport buttons physical feedback: the glyph presses in while a
/// circular highlight blooms behind it, then springs back.
struct MediaButtonStyle: ButtonStyle {
    var diameter: CGFloat = 38
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(tint.opacity(configuration.isPressed ? 0.28 : 0))
                    .scaleEffect(configuration.isPressed ? 1 : 0.55)
                    .frame(width: diameter, height: diameter)
            )
            .scaleEffect(configuration.isPressed ? 0.78 : 1)
            .animation(
                // Instant on the way in, loosely sprung on release so it pops back.
                .spring(response: configuration.isPressed ? 0.12 : 0.38, dampingFraction: 0.45),
                value: configuration.isPressed
            )
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
