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
                        .expandedCard(notchHeight: model.notchSize.height)
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
        // Paused: the whole row is dimmed (cover and the flat-dot bars alike),
        // so the pause reads clearly on an island that now stays visible.
        earsRow(dimmed: !model.isPlaying) {
            artworkView(size: DS.Icon.earSlot)
        } trailing: {
            EqualizerView(isPlaying: model.isPlaying, color: model.accent)
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
        dimmed: Bool = false,
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
                .opacity(dimmed ? .dsDimmed : .dsPrimary)
                .fixedSize()
                .scaleEffect(scale, anchor: .leading)
                .reportsContentFrame("leading")
                .padding(.leading, inset)
                .frame(width: ear, alignment: .leading)
            Color.clear.frame(width: notch.width)
            trailing()
                .opacity(dimmed ? .dsDimmed : .dsPrimary)
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

    private static let callGreen = Accent.callGreen

    private func callCollapsedContent(_ call: CallInfo) -> some View {
        earsRow {
            // The app's icon (`appIcon` falls back to a phone glyph when it has
            // none, so a call never shows two phones), then the camera glyph.
            // The right ear stays the duration alone so a long call keeps clear
            // of the notch.
            HStack(spacing: DS.Ear.gap) {
                appIcon(call.bundleID, size: DS.Icon.earSlot)
                if call.cameraOn {
                    EarSymbol(name: "video.fill", tint: Accent.callGreen)
                }
            }
        } trailing: {
            callEarDuration(call)
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
        VStack(alignment: .leading, spacing: DS.Space.sectionGap.pt) {
            // Ticks on its own, so the rest of the island isn't re-rendered every second.
            TimelineView(.periodic(from: call.startedAt, by: 1)) { context in
                CardHeader(
                    title: "Звонок · \(call.appName)",
                    subtitle: FormatTime.clock(context.date.timeIntervalSince(call.startedAt))
                ) {
                    appIcon(call.bundleID, size: DS.Card.lead.pt)
                }
            }

            HStack(spacing: DS.Space.m.pt) {
                CardIndicator(symbol: "mic.fill", tint: Self.callGreen)
                CardIndicator(
                    symbol: call.cameraOn ? "video.fill" : "video.slash.fill",
                    tint: call.cameraOn ? Self.callGreen : .white.opacity(.dsTertiary)
                )
                Spacer(minLength: 0)
                CapsuleButton(title: "Открыть", tint: Self.callGreen) {
                    model.openCallApp()
                }
            }
        }
        .expandedCard(notchHeight: model.notchSize.height)
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

    private func appIcon(_ bundleID: String, size: CGFloat) -> some View {
        Group {
            if let icon = AppIcons.icon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    // Transparent margins make app icons read smaller than art.
                    .scaleEffect(CollapsedGeometry.appIconScale)
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
        // Paused: the whole row (glyph and digits) is the same orange, dimmed.
        earsRow(dimmed: model.isTimerPaused) {
            EarSymbol(name: model.isTimerPaused ? "pause.fill" : "timer", tint: Accent.timerOrange)
        } trailing: {
            Text(formatCountdown(model.timerRemaining ?? 0))
                .font(.dsEar)
                .foregroundStyle(Accent.timerOrange)
                .fitsEar()
        }
    }

    private var timerExpandedContent: some View {
        let title = model.timerTitle.isEmpty
            ? (model.isTimerPaused ? "Таймер на паузе" : "Таймер")
            : model.timerTitle

        return VStack(alignment: .leading, spacing: DS.Space.sectionGap.pt) {
            SymbolCardHeader(
                symbolName: model.isTimerPaused ? "pause.fill" : "timer",
                tint: Self.timerOrange.opacity(model.isTimerPaused ? .dsDimmed : .dsPrimary),
                title: title
            ) {
                Text(formatCountdown(model.timerRemaining ?? 0))
                    .font(.dsDisplay)
                    .foregroundColor(model.isTimerPaused ? .white.opacity(.dsDimmed) : Self.timerOrange)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            DSProgressBar(
                mode: .determinate(fraction: Double(timerFraction)),
                tint: Self.timerOrange,
                paused: model.isTimerPaused,
                reduceMotion: reduceMotion
            )

            // Pause and cancel stay in the Clock app: its daemon won't take
            // commands from a third-party process.
            CapsuleButton(title: "Открыть Часы", tint: Self.timerOrange) {
                model.openClock()
            }
        }
        .expandedCard(notchHeight: model.notchSize.height)
    }

    // MARK: - Agenda

    /// Calendar.app's red and Reminders' blue, so each reads as its own app.
    static let calendarRed = Accent.calendarRed
    static let remindersBlue = Accent.remindersBlue

    private var glanceAccent: Color {
        switch model.glanceSymbol {
        case "checklist": return Self.remindersBlue
        case "calendar", "calendar.badge.clock": return Self.calendarRed
        case "timer": return Self.timerOrange
        default: return .white.opacity(.dsPrimary)
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
    /// An overdue reminder is red, like everywhere else.
    private var agendaEarAccent: Color {
        if model.agenda.nowEvent != nil { return Accent.calendarRed }
        if let reminder = model.agenda.nowReminder, isOverdue(reminder) { return Accent.calendarRed }
        return Accent.remindersBlue
    }

    private var agendaCollapsedTime: String {
        if let event = model.agenda.nowEvent {
            return EarText.agenda(
                AgendaFormat.collapsedLabel(start: event.start, end: event.end, now: Date()),
                clock: IslandViewModel.clock
            )
        }
        if let due = model.agenda.nowReminder?.due { return IslandViewModel.clock(due) }
        return IslandViewModel.clock(Date())
    }

    /// What is on now, then the rest of today, overdue reminders in red.
    /// Every row's text starts where the header's text does.
    private var agendaExpandedContent: some View {
        let agenda = model.agenda
        let laterEvents = agenda.events.filter { $0 != agenda.nowEvent }.prefix(AgendaLimits.events)
        let reminders = AgendaFormat.listedReminders(
            agenda.reminders, nowReminder: agenda.nowReminder, hasNowEvent: agenda.nowEvent != nil
        ).prefix(AgendaLimits.reminders)

        return VStack(alignment: .leading, spacing: DS.Space.sectionGap.pt) {
            if let event = agenda.nowEvent {
                SymbolCardHeader(
                    symbolName: "calendar.badge.clock",
                    tint: Self.calendarRed,
                    title: event.title,
                    subtitle: "Сейчас · \(IslandViewModel.clock(event.start))–\(IslandViewModel.clock(event.end))"
                ) {
                    if event.joinURL != nil {
                        CardPrimaryButton(symbol: "video.fill", fill: Self.calendarRed, help: "Подключиться") {
                            model.join(event)
                        }
                    }
                }
            } else if let reminder = agenda.nowReminder {
                let reminderTint = isOverdue(reminder) ? Self.calendarRed : Self.remindersBlue
                SymbolCardHeader(
                    symbolName: "checklist",
                    tint: reminderTint,
                    title: reminder.title,
                    subtitle: "Напоминание"
                ) {
                    CardPrimaryButton(symbol: "checkmark", fill: reminderTint, help: "Выполнено") {
                        model.completeReminder(id: reminder.id)
                    }
                }
            } else {
                SymbolCardHeader(symbolName: "calendar", tint: Self.calendarRed, title: "Сегодня")
            }

            VStack(alignment: .leading, spacing: DS.Space.rowGap.pt) {
                ForEach(Array(laterEvents), id: \.id) { event in
                    agendaRow(
                        lead: Image(systemName: "calendar")
                            .font(.dsBody)
                            .foregroundStyle(Self.calendarRed),
                        title: event.title,
                        titleColor: .white.opacity(.dsPrimary),
                        time: IslandViewModel.clock(event.start)
                    )
                }
                ForEach(Array(reminders), id: \.id) { reminder in
                    agendaRow(
                        lead: CardIconButton(symbol: "circle", opacity: .dsPrimary, tint: Self.remindersBlue, help: "Выполнено") {
                            model.completeReminder(id: reminder.id)
                        },
                        title: reminder.title,
                        titleColor: isOverdue(reminder) ? Self.calendarRed : .white.opacity(.dsPrimary),
                        time: reminder.due.map { IslandViewModel.clock($0) }
                    )
                }
                if laterEvents.isEmpty && reminders.isEmpty {
                    Text("На сегодня больше ничего")
                        .font(.dsBody)
                        .foregroundColor(.white.opacity(.dsTertiary))
                        .padding(.leading, agendaTextInset)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .expandedCard(notchHeight: model.notchSize.height)
    }

    private enum AgendaLimits {
        static let events = 3
        static let reminders = 3
    }

    /// Where a `SymbolCardHeader`'s text starts: past its icon column.
    private var agendaTextInset: CGFloat { (DS.Card.headerIconColumn + DS.Space.leadGap).pt }

    /// Icon in the header's column, the title where the header's title starts,
    /// the time trailing.
    private func agendaRow<Lead: View>(
        lead: Lead,
        title: String,
        titleColor: Color,
        time: String?
    ) -> some View {
        HStack(spacing: DS.Space.leadGap.pt) {
            lead.frame(width: DS.Card.headerIconColumn.pt)
            Text(title)
                .font(.dsBody)
                .foregroundColor(titleColor)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let time {
                Text(time)
                    .font(.dsCaption)
                    .foregroundColor(.white.opacity(.dsSecondary))
            }
        }
    }

    private func isOverdue(_ reminder: AgendaReminder) -> Bool {
        guard let due = reminder.due else { return false }
        return due < Date()
    }

    /// The system timer's own color (Clock, Control Center).
    static let timerOrange = Accent.timerOrange

    private var timerFraction: CGFloat {
        guard model.timerTotal > 0, let remaining = model.timerRemaining else { return 0 }
        return CGFloat(min(1, max(0, 1 - remaining / model.timerTotal)))
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.sectionGap.pt) {
            // The header's own arrangement, with the transport row under the
            // text: `CardHeader` has no slot for it.
            HStack(spacing: DS.Space.leadGap.pt) {
                artworkView(size: DS.Card.lead.pt)

                VStack(alignment: .leading, spacing: DS.Space.m.pt) {
                    VStack(alignment: .leading, spacing: DS.Space.titleGap.pt) {
                        Text(model.title.isEmpty ? "Ничего не играет" : model.title)
                            .font(.dsCardTitle)
                            .foregroundColor(.white.opacity(.dsPrimary))
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
        .expandedCard(notchHeight: model.notchSize.height)
    }

    /// Elapsed, bar and remaining on one line, like the iOS player.
    private var progressRow: some View {
        let times = FormatTime.playback(position: model.position, duration: model.duration)
        return HStack(spacing: DS.Space.inlineGap.pt) {
            Text(times.elapsed)
                .font(.dsCaption)
                .foregroundColor(.white.opacity(.dsTertiary))

            DSProgressBar(
                mode: .determinate(fraction: Double(progressFraction)),
                tint: model.accent,
                reduceMotion: reduceMotion
            )

            if model.duration > 0 {
                Text("-\(times.remaining)")
                    .font(.dsCaption)
                    .foregroundColor(.white.opacity(.dsTertiary))
            } else {
                // Live streams (YouTube/Twitch live) have no length.
                Text("LIVE")
                    .font(.dsCaption)
                    .foregroundColor(Accent.failureRed)
            }
        }
    }

    private var progressFraction: CGFloat {
        guard model.duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, model.position / model.duration)))
    }

    private func formatCountdown(_ seconds: Double) -> String { FormatTime.clock(seconds) }

    private func formatTime(_ seconds: Double) -> String { FormatTime.clock(seconds) }

    /// Transport row: 28pt hit-frames edge to edge, the first glyph pulled
    /// back so it lines up with the text above it.
    private var controlsRow: some View {
        HStack(spacing: 0) {
            CardIconButton(symbol: "speaker.wave.2") { AudioOutputs.showPicker() }
            CardIconButton(symbol: "backward.end") { model.skipPrevious() }
            CardPrimaryButton(symbol: model.isPlaying ? "pause.fill" : "play.fill", glyph: .black, fill: .white) {
                model.togglePlayPause()
            }
            CardIconButton(symbol: "forward.end") { model.skipNext() }
            CardIconButton(symbol: "arrow.up.forward.app") { model.openPlayer() }
        }
        .padding(.leading, -((DS.Button.secondaryHitFrame - DS.Button.secondaryIconMin) / 2).pt)
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
    func expandedCard(notchHeight: CGFloat) -> some View {
        self
            .cardFrame(notchHeight: notchHeight)
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
