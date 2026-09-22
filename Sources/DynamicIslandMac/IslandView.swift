import SwiftUI

struct IslandView: View {
    @ObservedObject var model: IslandViewModel
    @ObservedObject var settings: IslandSettings

    var body: some View {
        VStack(spacing: 0) {
            island
                .frame(width: islandSize.width, height: islandSize.height)
                // A pause (or resume) flips `isIslandVisible` and the frame
                // snaps to its new size on the same spring as every other
                // state change, which reads as an instant cut rather than a
                // disappearance. Fading opacity on a slightly slower, easing
                // curve — independent of that spring — makes it read as the
                // island dissolving instead of the shape just shrinking.
                .opacity(model.state == .hidden ? 0 : 1)
                .animation(.easeOut(duration: 0.35), value: model.state == .hidden)
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
            hasContent: model.isIslandVisible,
            notch: ScreenNotch.size()
        )
    }

    private var island: some View {
        ZStack {
            shape
                .fill(Color.black)
                .contentShape(shape)
                .onTapGesture { model.tap() }

            if let title = model.glanceTitle {
                GlanceView(
                    title: title,
                    subtitle: model.glanceSubtitle,
                    symbol: model.glanceSymbol,
                    accent: model.accent
                )
                    // Keep the text clear of the camera cutout.
                    .padding(.top, settings.collapsedHeight)
                    .id(title)
                    .transition(.opacity)
            } else if model.isTimerActive {
                if model.isExpanded {
                    timerExpandedContent
                        .transition(.opacity)
                } else {
                    timerCollapsedContent
                        .transition(.opacity)
                }
            } else if model.isExpanded {
                expandedContent
                    .transition(.opacity)
            } else if model.isIslandVisible {
                collapsedContent
                    .transition(.opacity)
            }
        }
        .clipShape(shape)
        // Forces a full re-rasterization on every change instead of an
        // incremental CALayer-mask update. Without this, the shape can be
        // pixel-correct in a fresh screen capture while the *live* on-screen
        // compositing still shows a stale mask from an earlier path shape
        // (e.g. square corners left over from a different state) — a repeat
        // of the layer-caching class of bug already hit once in this file
        // (see ClickThroughHostingView's makeLayerTransparent comment).
        .drawingGroup()
    }

    /// Fast and smooth: a short, well-damped spring so it settles without
    /// overshoot ringing. Duration is tunable from the settings panel.
    private var openAnimation: Animation {
        .spring(response: settings.animationDuration, dampingFraction: 0.86)
    }

    /// Hangs from the top edge of the display and blends into it, the way the
    /// hardware notch does.
    private var shape: NotchShape {
        // Idle also needs its own, much tighter corner: the real notch's
        // bottom corners are far less rounded than the collapsed pill's,
        // and reusing collapsedBottomRadius there leaves the actual
        // hardware notch peeking out past our softer curve.
        let bottomRadius: CGFloat = model.isExpanded
            ? settings.expandedBottomRadius
            : model.state == .hidden
                ? settings.idleBottomRadius
                : settings.collapsedBottomRadius

        return NotchShape(
            // Same concave flare on every visible state, expanded included —
            // the card grows out of the screen edge the way the collapsed
            // pill already does, instead of reading as a separate floating
            // box with its own rounded top.
            topFillet: model.state == .hidden ? 0 : settings.fillet,
            bottomRadius: bottomRadius,
            // The squircle exponent tuned for the collapsed pill's large
            // radius reads as an almost-square chamfer at idle's tiny
            // radius. When expanded, we use a perfectly circular exponent (2.2)
            // on ALL corners so it looks like a smooth pill, not a box.
            bottomExponent: model.state == .hidden ? settings.topExponent : (model.isExpanded ? settings.topExponent : settings.bottomExponent),
            topExponent: settings.topExponent,
            // Every visible state keeps the flush notch-continuation look —
            // expanded no longer breaks from it with an ordinary rounded top.
            topIsConvex: false
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

    // MARK: - Timer

    private var timerCollapsedContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            Spacer(minLength: 0)
            Text(formatTime(model.timerRemaining ?? 0))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, settings.collapsedPadding + settings.fillet)
    }

    private var timerExpandedContent: some View {
        VStack(spacing: 14) {
            Text(formatTime(model.timerRemaining ?? 0))
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.white)
                .monospacedDigit()

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: proxy.size.width * timerFraction)
                }
            }
            .frame(height: 4)

            Button {
                model.cancelTimer()
            } label: {
                Text("Отменить")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, settings.expandedPadding + settings.fillet)
        .padding(.top, settings.expandedTopPadding)
        .padding(.bottom, settings.expandedTopPadding)
    }

    private var timerFraction: CGFloat {
        guard model.timerTotal > 0, let remaining = model.timerRemaining else { return 0 }
        return CGFloat(min(1, max(0, 1 - remaining / model.timerTotal)))
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                artworkView(size: settings.expandedArtwork)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.title.isEmpty ? "Nothing playing" : model.title)
                            .font(.system(size: settings.titleFontSize, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(model.artist)
                            .font(.system(size: settings.artistFontSize, weight: .regular))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                    }

                    controlsRow
                }

                Spacer(minLength: 0)
            }

            progressRow
        }
        .padding(.horizontal, settings.expandedPadding + settings.fillet)
        .padding(.top, settings.expandedTopPadding)
        .padding(.bottom, settings.expandedTopPadding)
    }

    private var progressRow: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: proxy.size.width * progressFraction)
                }
            }
            .frame(height: 4)

            HStack {
                Text(formatTime(model.position))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text("-\(formatTime(max(0, model.duration - model.position)))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .monospacedDigit()
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

    private var controlsRow: some View {
        HStack(spacing: 14) {
            Button {
                AudioOutputs.showPicker()
            } label: {
                Image(systemName: "speaker.wave.2.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .buttonStyle(.plain)

            Button {
                model.skipPrevious()
            } label: {
                Image(systemName: "backward.end")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .buttonStyle(.plain)

            Button {
                model.togglePlayPause()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white))
            }
            .buttonStyle(.plain)

            Button {
                model.skipNext()
            } label: {
                Image(systemName: "forward.end")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .buttonStyle(.plain)

            Button {
                model.openPlayer()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .buttonStyle(.plain)
        }
    }

    private func artworkView(size: CGFloat) -> some View {
        FlipArtwork(image: model.artwork, trackKey: model.trackKey, size: size)
    }
}
