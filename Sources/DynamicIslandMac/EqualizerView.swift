import SwiftUI

/// Five-bar animated equalizer tinted to the album art.
///
/// Driven by `TimelineView` rather than a `Timer` held in a property: a struct's
/// stored properties are rebuilt every time the view is re-created, so on the
/// lock screen — where playback time re-renders this several times a second —
/// the timer was restarted before it ever fired and the bars sat frozen.
/// Deriving the heights from the timeline date keeps it stateless and immune to that.
struct EqualizerView: View {
    let isPlaying: Bool
    var color: Color = .white
    var barWidth: CGFloat = 2.5
    var maxHeight: CGFloat = 14

    private static let barCount = 5
    private static let step = 0.22

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.step)) { context in
            HStack(alignment: .center, spacing: barWidth * 1.15) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: height(index, at: context.date))
                }
            }
            .frame(height: maxHeight)
            .animation(.easeInOut(duration: Self.step), value: context.date)
        }
    }

    private func height(_ index: Int, at date: Date) -> CGFloat {
        guard isPlaying else { return max(barWidth, maxHeight * 0.2) }

        // Each bar gets its own offset and rate so they never move in lockstep.
        let t = date.timeIntervalSinceReferenceDate
        let wave = sin(t * 5.1 + Double(index) * 1.9)
            + sin(t * 2.7 + Double(index) * 3.3) * 0.6
        let level = 0.25 + (wave / 3.2 + 0.5) * 0.75
        return max(barWidth, CGFloat(min(1, max(0.2, level))) * maxHeight)
    }
}
