import SwiftUI

/// Album art that flips when the track changes.
///
/// The turn is split in two halves around the edge-on moment: the old cover
/// rotates to 90°, the image is swapped while it is invisible, and the new one
/// comes back from -90°. Swapping at that exact point is what sells it as one
/// card turning over rather than two pictures cross-fading.
///
/// The flip is started by the *arrival of the new cover*, not by the track name
/// changing. Artwork is downloaded a beat later, so turning on the name alone
/// spins the card and lands on the very same picture.
struct FlipArtwork: View {
    let image: NSImage?
    /// Identifies the track, so a re-delivered cover for the same song does not
    /// trigger another spin.
    let trackKey: String
    let size: CGFloat
    var cornerRatio: CGFloat = 0.21

    @State private var shown: NSImage?
    @State private var flippedKey = ""
    @State private var angle: Double = 0

    private static let half = 0.22

    var body: some View {
        artwork
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.55
            )
            .onAppear {
                shown = image
                flippedKey = trackKey
            }
            .onChange(of: image) { new in
                guard trackKey != flippedKey else {
                    // Same song: a late or refreshed cover just takes its place.
                    shown = new
                    return
                }
                flippedKey = trackKey
                flip(to: new)
            }
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: size * cornerRatio, style: .continuous)
            .fill(Color.white.opacity(0.1))
            .overlay {
                if let shown {
                    Image(nsImage: shown)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(
                            RoundedRectangle(cornerRadius: size * cornerRatio, style: .continuous)
                        )
                }
            }
            .frame(width: size, height: size)
    }

    private func flip(to new: NSImage?) {
        withAnimation(.easeIn(duration: Self.half)) {
            angle = 90
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.half) {
            shown = new
            angle = -90
            withAnimation(.easeOut(duration: Self.half)) {
                angle = 0
            }
        }
    }
}
