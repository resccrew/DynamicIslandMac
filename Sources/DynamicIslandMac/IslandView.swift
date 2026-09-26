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
        model.islandSize(settings: settings, notch: model.notchSize)
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
                    accent: glanceAccent,
                    actionLabel: model.glanceAction?.label,
                    onAction: { model.performGlanceAction() }
                )
                    // Keep the text clear of the camera cutout.
                    .padding(.top, settings.collapsedHeight)
                    .id(title)
                    .transition(.opacity)
            } else if let call = model.call {
                if model.isExpanded {
                    callExpandedContent(call)
                        .transition(.opacity)
                } else {
                    callCollapsedContent(call)
                        .transition(.opacity)
                }
            } else if model.content == .agenda {
                if model.isExpanded {
                    agendaExpandedContent
                        .transition(.opacity)
                } else {
                    agendaCollapsedContent
                        .transition(.opacity)
                }
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
        .coordinateSpace(name: ContentFrameKey.space)
        .onPreferenceChange(ContentFrameKey.self) { frames in
            model.collapsedContentFrames = frames
        }
        // One observer for all cards: a card inserted fresh doesn't report its
        // initial height to an observer of its own, so it would inherit the
        // previous card's size.
        .onPreferenceChange(ExpandedHeightKey.self) { value in
            guard value > 0 else { return }
            model.expandedContentHeight = value
        }
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
        earsRow {
            artworkView(size: settings.collapsedArtwork)
        } trailing: {
            EqualizerView(
                isPlaying: model.isPlaying,
                color: model.accent,
                barWidth: 2,
                maxHeight: 12
            )
        }
    }

    /// Collapsed content lives only in the two ears beside the camera: the
    /// notch-wide middle stays empty, since whatever is drawn there is hidden
    /// by the hardware (and screenshots don't show it, so it goes unnoticed).
    private func earsRow<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let notch = model.notchSize
        let body = islandSize.width - settings.fillet * 2
        let ear = max(0, (body - notch.width) / 2)
        return HStack(spacing: 0) {
            // Measured before padding and framing: the drawn content itself,
            // which can overflow its ear if it doesn't fit.
            leading()
                .fixedSize()
                .reportsContentFrame("leading")
                .padding(.leading, settings.collapsedPadding)
                .frame(width: ear, alignment: .leading)
            Color.clear.frame(width: notch.width)
            trailing()
                .fixedSize()
                .reportsContentFrame("trailing")
                .padding(.trailing, settings.collapsedPadding)
                .frame(width: ear, alignment: .trailing)
        }
        .frame(height: min(islandSize.height, notch.height))
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Call

    private static let callGreen = Color(red: 0.19, green: 0.82, blue: 0.35)

    private func callCollapsedContent(_ call: CallInfo) -> some View {
        earsRow {
            HStack(spacing: 6) {
                appIcon(call.bundleID, size: settings.collapsedArtwork - 4)
                Image(systemName: "phone.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Self.callGreen)
            }
        } trailing: {
            HStack(spacing: 5) {
                if call.cameraOn {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Self.callGreen)
                }
                callDuration(call, size: 13)
            }
        }
    }

    private func callExpandedContent(_ call: CallInfo) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                appIcon(call.bundleID, size: settings.expandedArtwork)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Звонок · \(call.appName)")
                        .font(.system(size: settings.titleFontSize, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    callDuration(call, size: settings.artistFontSize)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                callIndicator(symbol: "mic.fill", active: true)
                callIndicator(symbol: call.cameraOn ? "video.fill" : "video.slash.fill", active: call.cameraOn)
                Spacer(minLength: 0)
                Button {
                    model.openCallApp()
                } label: {
                    Text("Открыть")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Self.callGreen))
                }
                .buttonStyle(.plain)
            }
        }
        .expandedCard(settings: settings, notchHeight: model.notchSize.height)
    }

    /// Ticks on its own, so the rest of the island isn't re-rendered every second.
    private func callDuration(_ call: CallInfo, size: CGFloat) -> some View {
        TimelineView(.periodic(from: call.startedAt, by: 1)) { context in
            Text(formatTime(context.date.timeIntervalSince(call.startedAt)))
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(Self.callGreen)
                .monospacedDigit()
        }
    }

    private func callIndicator(symbol: String, active: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(active ? Self.callGreen : .white.opacity(0.4))
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.white.opacity(0.1)))
    }

    private func appIcon(_ bundleID: String, size: CGFloat) -> some View {
        Group {
            if let icon = AppIcons.icon(for: bundleID) {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "phone.circle.fill")
                    .resizable()
                    .foregroundStyle(Self.callGreen)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Timer

    private var timerCollapsedContent: some View {
        earsRow {
            Image(systemName: model.isTimerPaused ? "pause.fill" : "timer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Self.timerOrange)
        } trailing: {
            Text(formatCountdown(model.timerRemaining ?? 0))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(model.isTimerPaused ? .white.opacity(0.5) : Self.timerOrange)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var timerExpandedContent: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(model.timerTitle.isEmpty
                     ? (model.isTimerPaused ? "Таймер на паузе" : "Таймер")
                     : model.timerTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Text(formatCountdown(model.timerRemaining ?? 0))
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(model.isTimerPaused ? .white.opacity(0.5) : Self.timerOrange)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule()
                        .fill(Self.timerOrange.opacity(model.isTimerPaused ? 0.45 : 0.9))
                        .frame(width: proxy.size.width * timerFraction)
                }
            }
            .frame(height: 4)

            // Pause and cancel stay in the Clock app: its daemon won't take
            // commands from a third-party process.
            Button {
                model.openClock()
            } label: {
                Text("Открыть Часы")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .expandedCard(settings: settings, notchHeight: model.notchSize.height)
    }

    // MARK: - Agenda

    /// Calendar.app's red and Reminders' blue, so each reads as its own app.
    static let calendarRed = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let remindersBlue = Color(red: 0.04, green: 0.52, blue: 1.0)

    private var glanceAccent: Color {
        switch model.glanceSymbol {
        case "checklist": return Self.remindersBlue
        case "calendar", "calendar.badge.clock": return Self.calendarRed
        default: return model.accent
        }
    }

    private var agendaCollapsedContent: some View {
        earsRow {
            Image(systemName: model.agenda.nowEvent != nil ? "calendar" : "checklist")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.agenda.nowEvent != nil ? Self.calendarRed : Self.remindersBlue)
        } trailing: {
            Text(agendaCollapsedTime)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var agendaCollapsedTime: String {
        if let event = model.agenda.nowEvent { return IslandViewModel.clock(event.start) }
        if let due = model.agenda.nowReminder?.due { return IslandViewModel.clock(due) }
        return IslandViewModel.clock(Date())
    }

    /// What is on now, then the rest of today: up to three events and four
    /// reminders, overdue ones in red.
    private var agendaExpandedContent: some View {
        let agenda = model.agenda
        let laterEvents = agenda.events.filter { $0 != agenda.nowEvent }.prefix(3)
        let reminders = agenda.reminders.filter { $0 != agenda.nowReminder }.prefix(4)

        return VStack(alignment: .leading, spacing: 8) {
            if let event = agenda.nowEvent {
                agendaHeader(
                    symbol: "calendar.badge.clock",
                    color: Self.calendarRed,
                    title: event.title,
                    subtitle: "Сейчас · \(IslandViewModel.clock(event.start))–\(IslandViewModel.clock(event.end))",
                    actionSymbol: event.joinURL == nil ? nil : "video.fill",
                    actionHelp: "Подключиться",
                    action: { model.join(event) }
                )
            } else if let reminder = agenda.nowReminder {
                agendaHeader(
                    symbol: "checklist",
                    color: Self.remindersBlue,
                    title: reminder.title,
                    subtitle: "Напоминание",
                    actionSymbol: "checkmark",
                    actionHelp: "Выполнено",
                    action: { model.completeReminder(id: reminder.id) }
                )
            } else {
                Text("Сегодня")
                    .font(.system(size: settings.titleFontSize, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(laterEvents), id: \.id) { event in
                    HStack(spacing: 8) {
                        Text(IslandViewModel.clock(event.start))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Self.calendarRed)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .leading)
                        Text(event.title)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                ForEach(Array(reminders), id: \.id) { reminder in
                    HStack(spacing: 8) {
                        Button {
                            model.completeReminder(id: reminder.id)
                        } label: {
                            Image(systemName: "circle")
                                .font(.system(size: 13))
                                .foregroundColor(Self.remindersBlue)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 40, alignment: .leading)
                        Text(reminder.title)
                            .font(.system(size: 12))
                            .foregroundColor(isOverdue(reminder) ? Self.calendarRed : .white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                if laterEvents.isEmpty && reminders.isEmpty {
                    Text("На сегодня больше ничего")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Rows run to the left edge; keep the last one off the rounded corner.
        .padding(.bottom, 6)
        .expandedCard(settings: settings, notchHeight: model.notchSize.height)
    }

    private func isOverdue(_ reminder: AgendaReminder) -> Bool {
        guard let due = reminder.due else { return false }
        return due < Date()
    }

    private func agendaHeader(
        symbol: String,
        color: Color,
        title: String,
        subtitle: String,
        actionSymbol: String?,
        actionHelp: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: settings.titleFontSize, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: settings.artistFontSize))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            // A round icon button, so the title keeps the row's width.
            if let actionSymbol {
                Button(action: action) {
                    Image(systemName: actionSymbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(color))
                }
                .buttonStyle(.plain)
                .help(actionHelp)
            }
        }
    }

    /// The system timer's own color (Clock, Control Center).
    static let timerOrange = Color(red: 1.0, green: 0.62, blue: 0.04)

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
        .expandedCard(settings: settings, notchHeight: model.notchSize.height)
    }

    /// Elapsed, bar and remaining on one line, like the iOS player.
    private var progressRow: some View {
        HStack(spacing: 8) {
            Text(formatTime(model.position))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
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

            if model.duration > 0 {
                Text("-\(formatTime(max(0, model.duration - model.position)))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .monospacedDigit()
            } else {
                // Live streams (YouTube/Twitch live) have no length.
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.red.opacity(0.85))
            }
        }
    }

    private var progressFraction: CGFloat {
        guard model.duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, model.position / model.duration)))
    }

    /// Timers run past an hour, unlike most tracks: 1:05:09 rather than 65:09.
    private func formatCountdown(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 3600 else { return formatTime(seconds) }
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
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
        FlipArtwork(image: model.displayArtwork, trackKey: model.trackKey, size: size)
    }
}

private struct ExpandedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    /// Shared frame of the expanded cards: content starts just under the
    /// camera cutout, sits at the top, and reports its natural height.
    func expandedCard(settings: IslandSettings, notchHeight: CGFloat) -> some View {
        self
            .padding(.horizontal, settings.expandedPadding + settings.fillet)
            .padding(.top, notchHeight + settings.expandedTopPadding * 0.5)
            .padding(.bottom, settings.expandedTopPadding)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ExpandedHeightKey.self, value: proxy.size.height)
            })
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Where the collapsed content actually landed, in the island's own
/// coordinates — read by the debug server to check nothing sits under the notch.
struct ContentFrameKey: PreferenceKey {
    static let space = "island"
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func reportsContentFrame(_ name: String) -> some View {
        overlay(GeometryReader { proxy in
            Color.clear.preference(
                key: ContentFrameKey.self,
                value: [name: proxy.frame(in: .named(ContentFrameKey.space))]
            )
        })
    }
}
