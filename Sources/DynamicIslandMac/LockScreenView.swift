import SwiftUI

struct LockScreenView: View {
    @ObservedObject var model: IslandViewModel
    @ObservedObject var settings: IslandSettings

    var body: some View {
        ZStack {
            if model.lockPresentation != .card {
                backdrop
                    .transition(.opacity)
            }

            // A ZStack keeps both layouts centred on the same point, so the swap
            // reads as a grow in place. Matching the artwork across the two
            // layouts instead makes it fly in from the card's left edge.
            ZStack {
                if model.hasContent {
                    if model.lockArtExpanded {
                        expandedArt
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else {
                        compactCard
                            .transition(.scale(scale: 1.05).combined(with: .opacity))
                    }
                }
            }
            // Expanded is centred on screen; collapsed keeps the tuned offset
            // that puts it just above the avatar and password field.
            .offset(y: model.lockArtExpanded ? 0 : settings.lockScreenOffsetY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: model.lockPresentation)
    }

    /// The whole lock screen washed in the cover's colours: the artwork blown up
    /// and heavily blurred, which reads as ambient light rather than a picture.
    private var backdrop: some View {
        GeometryReader { proxy in
            ZStack {
                if let artwork = model.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 120, opaque: true)
                        .scaleEffect(1.25)
                        // Blurring averages the cover down to a muddy grey, so
                        // push the colour back up to read as ambient light.
                        .saturation(1.8)
                } else {
                    model.accent
                }

                // Just enough to keep the card and the system's own text legible.
                LinearGradient(
                    colors: [.black.opacity(0.18), .black.opacity(0.38)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { model.toggleLockArt() }
    }

    // MARK: - Compact card

    private var compactCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                artwork(size: 84)
                    .onTapGesture { model.toggleLockArt() }

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(palette.primary)
                            .lineLimit(1)
                        Text(model.artist)
                            .font(.system(size: 14))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }

                    compactControlsRow
                }

                Spacer(minLength: 0)
            }

            compactProgressSection
        }
        .padding(24)
        .frame(width: settings.lockScreenWidth)
        .background(cardBackground)
    }

    private var compactControlsRow: some View {
        HStack(spacing: 24) {
            Button {
                model.skipPrevious()
            } label: {
                Image(systemName: "backward.end")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.secondary)
            }
            .buttonStyle(.plain)

            Button {
                model.togglePlayPause()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.background)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(palette.primary))
            }
            .buttonStyle(.plain)

            Button {
                model.skipNext()
            } label: {
                Image(systemName: "forward.end")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var compactProgressSection: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.trackBackground)
                    Capsule()
                        .fill(palette.trackFill)
                        .frame(width: proxy.size.width * progressFraction)
                }
            }
            .frame(height: 4)

            HStack {
                Text(formatTime(model.position))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text(model.duration > 0 ? "-\(formatTime(max(0, model.duration - model.position)))" : "LIVE")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Expanded artwork

    /// Whether the lyrics step is offered at all.
    private var lyricsAvailable: Bool {
        settings.lyricsEnabled
    }

    /// Driven purely by which step the user is on.
    ///
    /// Deliberately not "…and lyrics are loaded": a track change empties the
    /// lines for the second it takes to fetch the next ones, and tying the
    /// layout to that made the whole player slide to the middle and back every
    /// time the song changed.
    private var showsLyrics: Bool {
        lyricsAvailable && model.lockPresentation == .lyrics
    }

    private var lyricsToggle: some View {
        Button {
            model.toggleLockLyrics()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Текст")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(showsLyrics ? 1 : 0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(.white.opacity(showsLyrics ? 0.22 : 0.10))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(MediaButtonStyle(diameter: 0))
    }

    /// Karaoke column: the whole song laid out and slid vertically so the line
    /// being sung sits in the middle. Scrolling the strip rather than swapping a
    /// few labels is what makes it glide instead of snapping line to line.
    private var lyricsColumn: some View {
        let index = model.currentLyricIndex ?? 0
        let lineHeight: CGFloat = 62
        let visibleLines: CGFloat = 5
        let viewportHeight = lineHeight * visibleLines

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.lyrics.enumerated()), id: \.offset) { position, line in
                let isCurrent = position == index
                Text(line.text.isEmpty ? "♪" : line.text)
                    .font(.system(size: 21, weight: isCurrent ? .bold : .semibold))
                    .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.3))
                    .shadow(color: .white.opacity(isCurrent ? 0.35 : 0), radius: 10)
                    .lineLimit(2)
                    .frame(height: lineHeight, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .offset(y: viewportHeight / 2 - lineHeight / 2 - CGFloat(index) * lineHeight)
        .frame(width: 400, height: viewportHeight, alignment: .top)
        .clipped()
        // Fades the lines running off the top and bottom instead of cutting them.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .animation(.easeInOut(duration: 0.45), value: index)
    }

    private var playerColumn: some View {
        VStack(spacing: 18) {
            artwork(size: settings.lockScreenArtSize)
                .onTapGesture { model.toggleLockArt() }

            VStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text(model.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                    Text(model.artist)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }

                compactProgressSection
                compactControlsRow
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(width: settings.lockScreenArtSize * 0.78)
            .background(cardBackground)

            if lyricsAvailable {
                lyricsToggle
            }
        }
    }

    /// With lyrics the player moves aside to make room for them; without lyrics
    /// there is nothing to pair it with, so it stays centred on its own.
    private var expandedArt: some View {
        HStack(spacing: 56) {
            playerColumn
            if showsLyrics {
                lyricsColumn
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Shared pieces

    private func artwork(size: CGFloat) -> some View {
        FlipArtwork(image: model.displayArtwork, trackKey: model.trackKey, size: size, cornerRatio: 0.16)
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    /// Colours for the card content — swaps with `lockCardLightTheme` so the
    /// same layout reads correctly against either background.
    private var palette: (primary: Color, secondary: Color, trackBackground: Color, trackFill: Color, background: Color) {
        if settings.lockCardLightTheme {
            (.black.opacity(0.85), .black.opacity(0.45), .black.opacity(0.1), .black.opacity(0.75), .white)
        } else {
            (.white, .white.opacity(0.65), .white.opacity(0.25), .white.opacity(0.9), .black)
        }
    }

    /// A solid white card for the light theme, matching a native widget;
    /// translucent glass over the ambient wash for the default dark theme.
    private var cardBackground: some View {
        Group {
            if settings.lockCardLightTheme {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(white: 0.1))
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    )
            }
        }
    }

    private var progressFraction: CGFloat {
        guard model.duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, model.position / model.duration)))
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
