import SwiftUI

/// Album art that flips when the track changes.
///
/// The turn is split in two halves around the edge-on moment: the old cover
/// rotates to 90°, the image is swapped while it is invisible, and the new one
/// comes back from -90°. Swapping at that exact point is what sells it as one
/// card turning over rather than two pictures cross-fading.
///
/// Every track change flips exactly once. Artwork is downloaded a beat after
/// the name changes, so the turn waits for the new cover (up to `coverWait`)
/// and lands on it; if none arrives in time it lands on the placeholder, and a
/// cover that shows up later just takes its place without a second spin.
struct FlipArtwork: View {
    let image: NSImage?
    /// Identifies the track, so a re-delivered cover for the same song does not
    /// trigger another spin.
    let trackKey: String
    let size: CGFloat
    var cornerRatio: CGFloat = 0.21

    @State private var shown: NSImage?
    @State private var angle: Double = 0
    /// The track whose flip has already started; a different `trackKey` means
    /// a flip is owed.
    @State private var flippedKey = ""
    /// The cover the running flip will land on; kept current if a refreshed
    /// cover for the same song arrives mid-turn.
    @State private var target: NSImage?
    @State private var isFlipping = false
    /// The track waiting for its cover. Read inside delayed callbacks, where
    /// `trackKey` and `image` are a stale copy of the view.
    @State private var pendingKey: String?
    /// Bumped on every flip so callbacks of an interrupted one are ignored.
    @State private var generation = 0

    private static let half = 0.22
    private static let coverWait = 1.2

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
            // Name and cover travel together and come in through the
            // parameter: handling them in two separate `onChange`s depends on
            // which one SwiftUI happens to run first.
            .onChange(of: Content(key: trackKey, image: image)) { _, new in
                reconcile(trackKey: new.key, image: new.image)
            }
    }

    private struct Content: Equatable {
        let key: String
        let image: NSImage?
    }

    private func reconcile(trackKey: String, image: NSImage?) {
        guard trackKey != flippedKey else {
            // Same song: a late or refreshed cover just takes its place.
            target = image
            if !isFlipping { shown = image }
            return
        }
        guard image == nil else {
            flip(to: image, key: trackKey)
            return
        }
        // No cover yet: wait for it, but never skip the turn.
        let key = trackKey
        pendingKey = key
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coverWait) {
            guard pendingKey == key else { return }
            flip(to: nil, key: key)
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
                        // Pin to the square before clipping, or a non-square
                        // cover (podcasts, local files) spills out of the card.
                        .frame(width: size, height: size)
                        .clipShape(
                            RoundedRectangle(cornerRadius: size * cornerRatio, style: .continuous)
                        )
                }
            }
            .frame(width: size, height: size)
    }

    private func flip(to new: NSImage?, key: String) {
        flippedKey = key
        pendingKey = nil
        target = new
        isFlipping = true
        generation += 1
        let current = generation
        withAnimation(.easeIn(duration: Self.half)) {
            angle = 90
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.half) {
            // A newer flip took over mid-turn; let it finish on its own cover.
            guard current == generation else { return }
            shown = target
            angle = -90
            withAnimation(.easeOut(duration: Self.half)) {
                angle = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.half) {
                guard current == generation else { return }
                isFlipping = false
                shown = target
            }
        }
    }
}
