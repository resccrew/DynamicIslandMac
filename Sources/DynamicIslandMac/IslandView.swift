import SwiftUI
import IslandGeometry
import IslandLogic

struct IslandView: View {
    @ObservedObject var model: IslandViewModel
    @ObservedObject var settings: IslandSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .opacity(IslandVisibility.opacity(isHidden: model.state == .hidden))
                .animation(.dsFade(reduceMotion: reduceMotion), value: model.state == .hidden)
                .onHover { hovering in
                    model.hover(hovering)
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(stateAnimation, value: model.state)
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
                    // Keep the text clear of the camera cutout; without one,
                    // just clear the menu bar row the island hangs from.
                    .padding(.top, model.hasNotch ? settings.collapsedHeight : IslandSettings.glanceTopInsetWithoutNotch)
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
            } else if let activity = model.liveActivity {
                if model.isExpanded {
                    LiveActivityExpanded(activity: activity)
                        .expandedCard(settings: settings, notchHeight: model.notchSize.height)
                        .transition(.opacity)
                } else {
                    earsRow { LiveActivityLeading(activity: activity) } trailing: { LiveActivityTrailing(activity: activity) }
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
            } else if IslandVisibility.rendersCollapsedContent(
                isIslandVisible: model.isIslandVisible,
                showsMedia: model.showsMedia
            ) {
                // A paused track under the pointer keeps its row (and play
                // button); gating on `isIslandVisible` alone emptied it.
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

    /// Every state change: the design system's `state` spring, at the speed
    /// chosen in the settings, softened to a fade under Reduce Motion.
    private var stateAnimation: Animation {
        .ds(.spring(response: settings.animationDuration, damping: DS.Motion.stateDamping), reduceMotion: reduceMotion)
    }

    /// Hangs from the top edge of the display and blends into it, the way the
    /// hardware notch does. One squircle exponent for every state.
    private var shape: NotchShape {
        NotchShape(
            // Same concave flare on every visible state, expanded included —
            // the card grows out of the screen edge the way the collapsed
            // pill already does, instead of reading as a separate floating box.
            topFillet: model.state == .hidden ? 0 : settings.fillet,
            bottomRadius: bottomRadius,
            topIsConvex: false
        )
    }

    /// Collapsed and peek round their bottom to exactly half their height;
    /// idle keeps the tight corner of the hardware notch, cards their own.
    private var bottomRadius: CGFloat {
        if model.isExpanded { return DS.Radius.expandedBottom }
        switch model.state {
        case .hidden: return DS.Radius.idle
        case .collapsed, .peek: return CollapsedGeometry.bottomRadius(collapsedLike: islandSize.height)
        case .expanded, .glance: return DS.Radius.expandedBottom
        }
    }

    // MARK: - Collapsed

    private var collapsedContent: some View {
        earsRow {
            artworkView(size: DS.Icon.earSlot)
        } trailing: {
            // Paused: the bars already lie flat as dots; dim them too so the
            // pause reads clearly on an island that now stays visible.
            EqualizerView(isPlaying: model.isPlaying, color: model.accent)
                .opacity(model.isPlaying ? .dsPrimary : .dsDimmed)
        }
    }

    /// The collapsed silhouette's height. Ears are centred in this row in
    /// collapsed *and* peek, so peek growing below it never moves the content.
    private var collapsedRowHeight: CGFloat {
        CGFloat(CollapsedGeometry.contentRowHeight(
            collapsedHeight: settings.islandSize(
                state: .collapsed, hasContent: true, notch: model.notchSize, hasNotch: model.hasNotch
            ).height
        ))
    }

    /// Collapsed content lives only in the two ears beside the camera: the
    /// notch-wide middle stays empty, since whatever is drawn there is hidden
    /// by the hardware (and screenshots don't show it, so it goes unnoticed).
    ///
    /// Every ear is `DS.Ear.width` wide whatever it shows, so the island keeps
    /// one width. In peek the ears widen but the content keeps its place.
    private func earsRow<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let notch = model.notchSize
        let ear = CollapsedGeometry.earWidth(
            islandWidth: islandSize.width, fillet: settings.fillet, notchWidth: notch.width
        )
        let rowHeight = collapsedRowHeight
        // A menu-bar-high island (no hardware notch) can be shorter than the
        // ear slot; shrink the ears' content and inset to fit, centred.
        let scale = DisplayGeometry.collapsedContentScale(
            rowHeight: rowHeight,
            contentHeight: DS.Icon.earSlot,
            inset: DS.Space.xxs
        )
        let inset = CollapsedGeometry.contentInset(earWidth: ear) * scale
        return HStack(spacing: 0) {
            // Measured before padding and framing: the drawn content itself,
            // which can overflow its ear if it doesn't fit.
            leading()
                .fixedSize()
                .scaleEffect(scale, anchor: .leading)
                .reportsContentFrame("leading")
                .padding(.leading, inset)
                .frame(width: ear, alignment: .leading)
            Color.clear.frame(width: notch.width)
            trailing()
                .fixedSize()
                .scaleEffect(scale, anchor: .trailing)
                .reportsContentFrame("trailing")
                .padding(.trailing, inset)
                .frame(width: ear, alignment: .trailing)
        }
        .frame(height: rowHeight)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Call

    private static let callGreen = Color(red: 0.19, green: 0.82, blue: 0.35)

    private func callCollapsedContent(_ call: CallInfo) -> some View {
        earsRow {
            // The app's icon alone; `appIcon` falls back to a phone glyph when
            // the app has none, so a call never shows two phones.
            appIcon(call.bundleID, size: DS.Icon.earSlot)
        } trailing: {
            HStack(spacing: DS.Ear.gap) {
                if call.cameraOn {
                    Image(systemName: "video.fill")
                        .font(.dsEarSecondary)
                        .foregroundStyle(Accent.callGreen)
                }
                callEarDuration(call)
            }
        }
    }

    /// Ticks on its own, like `callDuration`, in the shared ear font.
    private func callEarDuration(_ call: CallInfo) -> some View {
        TimelineView(.periodic(from: call.startedAt, by: 1)) { context in
            Text(formatTime(context.date.timeIntervalSince(call.startedAt)))
                .font(.dsEar)
                .foregroundStyle(Accent.callGreen)
                .fitsEar()
        }
    }

    private func callExpandedContent(_ call: CallInfo) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                appIcon(call.bundleID, size: settings.expandedArtwork)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Звонок · \(call.appName)")
                        .font(.dsCardTitle)
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
                        .font(.dsLabel)
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
            .font(.dsLabel)
            .foregroundStyle(active ? Self.callGreen : .white.opacity(.dsTertiary))
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.white.opacity(0.12)))
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
            EarSymbol(name: model.isTimerPaused ? "pause.fill" : "timer", tint: Accent.timerOrange)
        } trailing: {
            // Paused: the same orange, dimmed.
            Text(formatCountdown(model.timerRemaining ?? 0))
                .font(.dsEar)
                .foregroundStyle(Accent.timerOrange.opacity(model.isTimerPaused ? .dsDimmed : .dsPrimary))
                .fitsEar()
        }
    }

    private var timerExpandedContent: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(model.timerTitle.isEmpty
                     ? (model.isTimerPaused ? "Таймер на паузе" : "Таймер")
                     : model.timerTitle)
                    .font(.dsLabel)
                    .foregroundStyle(.white.opacity(.dsSecondary))
                    .lineLimit(1)
                Text(formatCountdown(model.timerRemaining ?? 0))
                    .font(.dsDisplay)
                    .foregroundColor(model.isTimerPaused ? .white.opacity(DS.Opacity.secondary) : Self.timerOrange)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(.dsTrack))
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
                    .font(.dsLabel)
                    .foregroundStyle(.white.opacity(.dsSecondary))
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
            EarSymbol(name: agendaEarSymbol, tint: agendaEarAccent)
        } trailing: {
            Text(agendaCollapsedTime)
                .font(.dsEar)
                .foregroundStyle(agendaEarAccent)
                .fitsEar()
        }
    }

    private var agendaEarSymbol: String {
        model.agenda.nowEvent != nil ? "calendar" : "checklist"
    }

    /// The ear's value wears the accent of what is on now: Calendar red for
    /// an event, Reminders blue for a reminder.
    private var agendaEarAccent: Color {
        model.agenda.nowEvent != nil ? Accent.calendarRed : Accent.remindersBlue
    }

    private var agendaCollapsedTime: String {
        if let event = model.agenda.nowEvent {
            switch AgendaFormat.collapsedLabel(start: event.start, end: event.end, now: Date()) {
            case .startsAt(let start): return IslandViewModel.clock(start)
            case .minutesLeft(let minutes): return "ещё \(minutes) мин"
            case .endsAt(let end): return "до \(IslandViewModel.clock(end))"
            }
        }
        if let due = model.agenda.nowReminder?.due { return IslandViewModel.clock(due) }
        return IslandViewModel.clock(Date())
    }

    /// What is on now, then the rest of today: up to three events and four
    /// reminders, overdue ones in red.
    private var agendaExpandedContent: some View {
        let agenda = model.agenda
        let laterEvents = agenda.events.filter { $0 != agenda.nowEvent }.prefix(3)
        let reminders = AgendaFormat.listedReminders(
            agenda.reminders, nowReminder: agenda.nowReminder, hasNowEvent: agenda.nowEvent != nil
        ).prefix(4)

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
                    .font(.dsCardTitle)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(laterEvents), id: \.id) { event in
                    HStack(spacing: 8) {
                        Text(IslandViewModel.clock(event.start))
                            .font(.dsLabel)
                            .foregroundColor(.white.opacity(.dsSecondary))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .leading)
                        Text(event.title)
                            .font(.dsBody)
                            .foregroundColor(.white.opacity(DS.Opacity.secondary))
                            .lineLimit(1)
                    }
                }
                ForEach(Array(reminders), id: \.id) { reminder in
                    HStack(spacing: 8) {
                        Button {
                            model.completeReminder(id: reminder.id)
                        } label: {
                            Image(systemName: "circle")
                                .font(.dsEar)
                                .foregroundColor(Self.remindersBlue)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 40, alignment: .leading)
                        Text(reminder.title)
                            .font(.dsBody)
                            .foregroundColor(isOverdue(reminder) ? Self.calendarRed : .white.opacity(DS.Opacity.secondary))
                            .lineLimit(1)
                    }
                }
                if laterEvents.isEmpty && reminders.isEmpty {
                    Text("На сегодня больше ничего")
                        .font(.dsBody)
                        .foregroundColor(.white.opacity(DS.Opacity.secondary))
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
                    .font(.dsCardTitle)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.dsBody)
                    .foregroundColor(.white.opacity(.dsSecondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            // A round icon button, so the title keeps the row's width.
            if let actionSymbol {
                Button(action: action) {
                    Image(systemName: actionSymbol)
                        .font(.dsEar)
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
                            .font(.dsCardTitle)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(model.artist)
                            .font(.dsBody)
                            .foregroundColor(.white.opacity(.dsSecondary))
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
            Text(FormatTime.playback(position: model.position, duration: model.duration).elapsed)
                .font(.dsCaption)
                .foregroundColor(.white.opacity(.dsTertiary))
                .monospacedDigit()

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(.dsTrack))
                    Capsule()
                        .fill(Color.white.opacity(.dsSecondary))
                        .frame(width: proxy.size.width * progressFraction)
                }
            }
            .frame(height: 4)

            if model.duration > 0 {
                Text("-\(FormatTime.playback(position: model.position, duration: model.duration).remaining)")
                    .font(.dsCaption)
                    .foregroundColor(.white.opacity(.dsTertiary))
                    .monospacedDigit()
            } else {
                // Live streams (YouTube/Twitch live) have no length.
                Text("LIVE")
                    .font(.dsCaption)
                    .foregroundColor(Accent.calendarRed.opacity(DS.Opacity.secondary))
            }
        }
    }

    private var progressFraction: CGFloat {
        guard model.duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, model.position / model.duration)))
    }

    private func formatCountdown(_ seconds: Double) -> String { FormatTime.clock(seconds) }

    private func formatTime(_ seconds: Double) -> String { FormatTime.clock(seconds) }

    private var controlsRow: some View {
        HStack(spacing: 14) {
            Button {
                AudioOutputs.showPicker()
            } label: {
                Image(systemName: "speaker.wave.2.circle")
                    .font(.dsEar)
                    .foregroundStyle(.white.opacity(.dsSecondary))
            }
            .buttonStyle(.plain)

            Button {
                model.skipPrevious()
            } label: {
                Image(systemName: "backward.end")
                    .font(.dsEar)
                    .foregroundStyle(.white.opacity(.dsSecondary))
            }
            .buttonStyle(.plain)

            Button {
                model.togglePlayPause()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.dsEar)
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white))
            }
            .buttonStyle(.plain)

            Button {
                model.skipNext()
            } label: {
                Image(systemName: "forward.end")
                    .font(.dsEar)
                    .foregroundStyle(.white.opacity(.dsSecondary))
            }
            .buttonStyle(.plain)

            Button {
                model.openPlayer()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.dsEar)
                    .foregroundStyle(.white.opacity(.dsSecondary))
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
