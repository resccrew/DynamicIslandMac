import SwiftUI

struct IslandView: View {
    @ObservedObject var model: IslandViewModel
    @ObservedObject var settings: IslandSettings

    var body: some View {
        VStack(spacing: 0) {
            island
                .frame(width: islandSize.width, height: islandSize.height)
                .onHover { hovering in
                    model.hover(hovering)
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(openAnimation, value: model.state)
    }

    /// Anchored to the top of a fixed-size panel, so growing downward never
    /// opens a gap against the screen edge.
    private var islandSize: CGSize {
        settings.islandSize(
            state: model.state,
            hasContent: model.hasContent,
            notch: ScreenNotch.size()
        )
    }

    private var island: some View {
        ZStack {
            shape
                .fill(Color.black)
                .contentShape(shape)
                .onTapGesture { model.tap() }

            if let notice = model.notice {
                NoticeView(notice: notice, accent: model.accent)
                    .id(notice)
                    .transition(.opacity)
            } else if model.isExpanded {
                expandedContent
                    .transition(.opacity)
            } else if model.hasContent {
                collapsedContent
                    .transition(.opacity)
            }
        }
        .clipShape(shape)
    }

    /// Fast and smooth: a short, well-damped spring so it settles without
    /// overshoot ringing. Duration is tunable from the settings panel.
    private var openAnimation: Animation {
        .spring(response: settings.animationDuration, dampingFraction: 0.86)
    }

    /// Hangs from the top edge of the display and blends into it, the way the
    /// hardware notch does.
    private var shape: NotchShape {
        NotchShape(
            // Idle sits exactly inside the notch, so the outward flares are
            // suppressed — otherwise they'd stick out as black wings beside it.
            topFillet: model.state == .hidden ? 0 : settings.fillet,
            bottomRadius: model.isExpanded
                ? settings.expandedBottomRadius
                : settings.collapsedBottomRadius,
            bottomExponent: settings.bottomExponent,
            topExponent: settings.topExponent
        )
    }

    // MARK: - Collapsed

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            artworkView(size: settings.collapsedArtwork)
            Spacer(minLength: 0)
            EqualizerView(
                isPlaying: model.isPlaying,
                color: model.accent,
                barWidth: 2,
                maxHeight: 12
            )
        }
        .padding(.horizontal, settings.collapsedPadding + settings.fillet)
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 13) {
                artworkView(size: settings.expandedArtwork)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.title.isEmpty ? "Nothing playing" : model.title)
                        .font(.system(size: settings.titleFontSize, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(model.artist)
                        .font(.system(size: settings.artistFontSize, weight: .regular))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }
                .padding(.top, 3)

                Spacer(minLength: 6)

                EqualizerView(
                    isPlaying: model.isPlaying,
                    color: model.accent,
                    barWidth: 2,
                    maxHeight: 12
                )
                .padding(.top, 6)
            }

            progressRow
                .padding(.top, 16)

            controlsRow
                .padding(.top, 12)
        }
        .padding(.horizontal, settings.expandedPadding + settings.fillet)
        .padding(.top, settings.expandedTopPadding)
    }

    private var progressRow: some View {
        HStack(spacing: 11) {
            Text(formatTime(model.position))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .monospacedDigit()

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: proxy.size.width * progressFraction)
                }
            }
            .frame(height: 4)

            Text("-\(formatTime(max(0, model.duration - model.position)))")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .monospacedDigit()
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 0) {
            controlButton("arrow.up.forward.app", size: 17, opacity: 0.95) { model.openPlayer() }
            Spacer(minLength: 0)
            controlButton("backward.fill", size: 17, opacity: 0.95) { model.skipPrevious() }
            Spacer(minLength: 0)
            controlButton(model.isPlaying ? "pause.fill" : "play.fill", size: 20, opacity: 1) {
                model.togglePlayPause()
            }
            Spacer(minLength: 0)
            controlButton("forward.fill", size: 17, opacity: 0.95) { model.skipNext() }
            Spacer(minLength: 0)
            controlButton("airplayaudio", size: 16, opacity: 0.95) { AudioOutputs.showPicker() }
        }
    }

    private func controlButton(
        _ systemName: String,
        size: CGFloat,
        opacity: Double,
        action: @escaping () -> Void
    ) -> some View {
        MediaButton(
            systemName: systemName,
            size: size,
            opacity: opacity,
            width: 38,
            height: 30,
            highlightDiameter: 34,
            action: action
        )
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

    private func artworkView(size: CGFloat) -> some View {
        FlipArtwork(image: model.artwork, trackKey: model.trackKey, size: size)
    }
}
