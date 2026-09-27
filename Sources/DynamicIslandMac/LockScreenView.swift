import SwiftUI
import IslandLogic

/// The lock-screen card. Same visual language as the island's expanded card:
/// `DS` fonts, opacities, spacing and control sizes, and the same progress row.
struct LockScreenView: View {
    @ObservedObject var model: IslandViewModel
    @ObservedObject var settings: IslandSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var lyricsSearchExpired = false

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
                            .transition(swapTransition(scale: LockMetrics.Transition.expandedScale))
                    } else {
                        compactCard
                            .transition(swapTransition(scale: LockMetrics.Transition.compactScale))
                    }
                }
            }
            // Expanded is centred on screen; collapsed keeps the tuned offset
            // that puts it just above the avatar and password field.
            .offset(y: model.lockArtExpanded ? 0 : settings.lockScreenOffsetY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.dsState(reduceMotion: reduceMotion), value: model.lockPresentation)
    }

    /// Reduce Motion: a plain fade, no scale.
    private func swapTransition(scale: CGFloat) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: scale).combined(with: .opacity)
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
                        .blur(radius: LockMetrics.Backdrop.blur, opaque: true)
                        .scaleEffect(LockMetrics.Backdrop.scale)
                        // Blurring averages the cover down to a muddy grey, so
                        // push the colour back up to read as ambient light.
                        .saturation(LockMetrics.Backdrop.saturation)
                } else {
                    model.accent
                }

                // Just enough to keep the card and the system's own text legible.
                LinearGradient(
                    colors: [.black.opacity(LockMetrics.Backdrop.scrimTop), .black.opacity(LockMetrics.Backdrop.scrimBottom)],
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
        VStack(spacing: DS.Space.sectionGap) {
            HStack(spacing: DS.Space.leadGap) {
                artwork(size: LockMetrics.compactArtwork)
                    .onTapGesture { model.toggleLockArt() }

                VStack(alignment: .leading, spacing: DS.Space.m) {
                    titleBlock(alignment: .leading)
                    controlsRow
                }
            }

            progressRow
        }
        .padding(.horizontal, DS.Space.cardSide)
        .padding(.vertical, DS.Space.xl)
        .frame(width: settings.lockScreenWidth)
        .background(cardBackground)
    }

    private func titleBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: DS.Space.titleGap) {
            Text(model.title)
                .font(.dsCardTitle)
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            Text(model.artist)
                .font(.dsBody)
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
        }
    }

    /// Spread across the full card width (same right edge as the progress
    /// bar below), like the transport row on the island.
    private var controlsRow: some View {
        HStack(spacing: 0) {
            MediaButton(
                systemName: "backward.end",
                size: DS.Button.secondaryIconMin,
                opacity: DS.Opacity.secondary,
                width: DS.Button.secondaryHitFrame,
                height: DS.Button.secondaryHitFrame,
                highlightDiameter: DS.Button.primary,
                tint: palette.tint
            ) { model.skipPrevious() }
            .accessibilityLabel("Предыдущий трек")

            Spacer(minLength: 0)

            Button {
                model.togglePlayPause()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.dsEar)
                    .foregroundStyle(palette.background)
                    .frame(width: DS.Button.primary, height: DS.Button.primary)
                    .background(Circle().fill(palette.tint))
                    .contentShape(Circle())
            }
            .buttonStyle(MediaButtonStyle(diameter: DS.Button.primary, tint: palette.tint))
            .accessibilityLabel(model.isPlaying ? "Пауза" : "Воспроизвести")

            Spacer(minLength: 0)

            MediaButton(
                systemName: "forward.end",
                size: DS.Button.secondaryIconMin,
                opacity: DS.Opacity.secondary,
                width: DS.Button.secondaryHitFrame,
                height: DS.Button.secondaryHitFrame,
                highlightDiameter: DS.Button.primary,
                tint: palette.tint
            ) { model.skipNext() }
            .accessibilityLabel("Следующий трек")
        }
        .frame(maxWidth: .infinity)
    }

    /// Elapsed, bar and remaining on one line — the island's progress row.
    private var progressRow: some View {
        HStack(spacing: DS.Space.inlineGap) {
            Text(FormatTime.playback(position: model.position, duration: model.duration).elapsed)
                .font(.dsCaption)
                .foregroundStyle(palette.tertiary)

            progressBar

            if model.duration > 0 {
                Text("-\(FormatTime.playback(position: model.position, duration: model.duration).remaining)")
                    .font(.dsCaption)
                    .foregroundStyle(palette.tertiary)
            } else {
                // Live streams have no length.
                Text("LIVE")
                    .font(.dsCaption)
                    .foregroundStyle(Accent.calendarRed.opacity(DS.Opacity.secondary))
            }
        }
    }

    private var progressBar: some View {
        DSProgressBar(
            mode: .determinate(fraction: progressFraction),
            tint: palette.tint,
            reduceMotion: reduceMotion,
            trackColor: palette.tint.opacity(DS.Opacity.track)
        )
    }

    // MARK: - Expanded artwork

    /// Driven purely by which step the user is on.
    ///
    /// Deliberately not "…and lyrics are loaded": a track change empties the
    /// lines for the second it takes to fetch the next ones, and tying the
    /// layout to that made the whole player slide to the middle and back every
    /// time the song changed.
    private var showsLyrics: Bool {
        settings.lyricsEnabled && model.lockPresentation == .lyrics
    }

    private var lyricsToggle: some View {
        CapsuleButton(
            title: "Текст",
            systemImage: "quote.bubble.fill",
            tint: .white,
            fillOpacity: showsLyrics ? DS.Opacity.track : LockMetrics.chipIdleFill,
            textOpacity: showsLyrics ? DS.Opacity.primary : DS.Opacity.secondary
        ) { model.toggleLockLyrics() }
    }

    /// Karaoke column: the whole song laid out and slid vertically so the line
    /// being sung sits in the middle. Scrolling the strip rather than swapping a
    /// few labels is what makes it glide instead of snapping line to line.
    private var lyricsColumn: some View {
        let index = model.currentLyricIndex ?? 0
        let lineHeight = LockMetrics.Lyrics.lineHeight
        let viewportHeight = lineHeight * LockMetrics.Lyrics.visibleLines

        return Group {
            if model.lyrics.isEmpty {
                lyricsPlaceholder
            } else {
                lyricsLines(index: index, lineHeight: lineHeight, viewportHeight: viewportHeight)
            }
        }
        .frame(width: settings.lockScreenArtSize * LockMetrics.Lyrics.widthToArtwork, height: viewportHeight, alignment: .top)
    }

    private func lyricsLines(index: Int, lineHeight: CGFloat, viewportHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.lyrics.enumerated()), id: \.offset) { position, line in
                let isCurrent = position == index
                Text(line.text.isEmpty ? "♪" : line.text)
                    .font(.system(size: LockMetrics.Lyrics.fontSize, weight: isCurrent ? .bold : .semibold))
                    .foregroundStyle(.white.opacity(isCurrent ? DS.Opacity.primary : LockMetrics.Lyrics.inactiveOpacity))
                    .shadow(color: .white.opacity(isCurrent ? LockMetrics.Lyrics.glowOpacity : 0), radius: LockMetrics.Lyrics.glowRadius)
                    .lineLimit(2)
                    .frame(height: lineHeight, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .offset(y: viewportHeight / 2 - lineHeight / 2 - CGFloat(index) * lineHeight)
        .frame(maxHeight: viewportHeight, alignment: .top)
        .clipped()
        // Fades the lines running off the top and bottom instead of cutting them.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: LockMetrics.Lyrics.fadeEdge),
                    .init(color: .black, location: 1 - LockMetrics.Lyrics.fadeEdge),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .animation(.dsFade(reduceMotion: reduceMotion), value: index)
    }

    /// No lines yet: first «Ищем текст…», and once the search has had its time, «Текст не найден».
    private var lyricsPlaceholder: some View {
        Text(lyricsSearchExpired ? "Текст не найден" : "Ищем текст…")
            .font(.dsCardTitle)
            .foregroundStyle(.white.opacity(DS.Opacity.secondary))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: model.trackKey) {
                lyricsSearchExpired = false
                try? await Task.sleep(nanoseconds: UInt64(LockMetrics.Lyrics.searchSeconds * 1_000_000_000))
                lyricsSearchExpired = true
            }
    }

    private var playerColumn: some View {
        let width = settings.lockScreenArtSize * LockMetrics.playerWidthToArtwork
        return VStack(spacing: DS.Space.xl) {
            artwork(size: settings.lockScreenArtSize)
                .onTapGesture { model.toggleLockArt() }

            VStack(spacing: DS.Space.sectionGap) {
                titleBlock(alignment: .center)
                progressRow
                controlsRow
            }
            .padding(.horizontal, DS.Space.cardSide)
            .padding(.vertical, DS.Space.xl)
            .frame(width: width)
            .background(cardBackground)

            if settings.lyricsEnabled {
                lyricsToggle
            }
        }
    }

    /// With lyrics the player moves aside to make room for them; without lyrics
    /// there is nothing to pair it with, so it stays centred on its own.
    private var expandedArt: some View {
        HStack(spacing: LockMetrics.playerToLyrics) {
            playerColumn
            if showsLyrics {
                lyricsColumn
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Shared pieces

    /// The real cover only — never the source app's icon blown up to cover size;
    /// without a cover the tile shows a neutral note.
    private func artwork(size: CGFloat) -> some View {
        ZStack {
            FlipArtwork(image: model.artwork, trackKey: model.trackKey, size: size)
            if model.artwork == nil {
                Image(systemName: "music.note")
                    .font(.system(size: size * LockMetrics.placeholderGlyphRatio, weight: .semibold))
                    .foregroundStyle(.white.opacity(DS.Opacity.tertiary))
            }
        }
        .shadow(
            color: .black.opacity(LockMetrics.Shadow.artworkOpacity),
            radius: LockMetrics.Shadow.artworkRadius,
            y: LockMetrics.Shadow.artworkY
        )
    }

    /// Colours for the card content: the three text levels of the design system,
    /// in black on the light card and white on the dark one.
    private var palette: (primary: Color, secondary: Color, tertiary: Color, tint: Color, background: Color) {
        let ink: Color = settings.lockCardLightTheme ? .black : .white
        let paper: Color = settings.lockCardLightTheme ? .white : .black
        return (
            ink.opacity(DS.Opacity.primary),
            ink.opacity(DS.Opacity.secondary),
            ink.opacity(DS.Opacity.tertiary),
            ink,
            paper
        )
    }

    /// Dark by default, like the island — and no outline, like the island. The
    /// light card stays as an option.
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.lockCard, style: .continuous)
        return Group {
            if settings.lockCardLightTheme {
                shape.fill(Color.white)
                    .shadow(color: .black.opacity(LockMetrics.Shadow.cardLightOpacity),
                            radius: LockMetrics.Shadow.cardRadius, y: LockMetrics.Shadow.cardY)
            } else {
                shape.fill(Color(white: LockMetrics.darkCardWhite))
                    .shadow(color: .black.opacity(LockMetrics.Shadow.cardDarkOpacity),
                            radius: LockMetrics.Shadow.cardRadius, y: LockMetrics.Shadow.cardY)
            }
        }
    }

    private var progressFraction: Double {
        guard model.duration > 0 else { return 0 }
        return min(1, max(0, model.position / model.duration))
    }
}
