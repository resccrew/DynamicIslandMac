#if DEBUG
import AppKit
import Combine
import Network

/// Debug-only HTTP/JSON control surface on 127.0.0.1, driven by the
/// `island-mcp` server in `mcp/` so Claude can read state, inject tracks and
/// check the island without a real player. Nothing here ships in release.
///
/// The listener runs on the main queue, so every request touches the model
/// on the main thread without extra hops.
final class DebugControlServer {
    static let port: UInt16 = 47800

    private let model: IslandViewModel
    private weak var islandController: IslandWindowController?
    private weak var lockController: LockScreenWindowController?
    private weak var poller: NowPlayingPoller?
    private weak var calls: CallMonitor?
    private var listener: NWListener?
    private var cancellables = Set<AnyCancellable>()

    /// While true the real poller's snapshots are dropped, so an injected
    /// track isn't overwritten a second later.
    private(set) var isInjecting = false
    /// Same for the call monitor while a call is injected.
    private(set) var isInjectingCall = false
    /// Same for the system Clock timers while a timer is injected.
    private(set) var isInjectingTimer = false
    /// Set after launch by the app delegate, to hand real timers back.
    weak var systemTimers: SystemTimerMonitor?
    /// Set after launch; fake agenda is planned through the real monitor.
    weak var agenda: AgendaMonitor?

    private var hoverSimulated = false
    private var realPointerCheck: (() -> Bool)?

    /// In-memory only; never written to disk.
    private var events: [[String: Any]] = []
    private let maxEvents = 300

    init(
        model: IslandViewModel,
        islandController: IslandWindowController?,
        lockController: LockScreenWindowController?,
        poller: NowPlayingPoller?,
        calls: CallMonitor?
    ) {
        self.model = model
        self.islandController = islandController
        self.lockController = lockController
        self.poller = poller
        self.calls = calls
    }

    func start() {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: Self.port)!
        )
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else {
            record("debug server failed to start")
            return
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: .main)
        self.listener = listener
        observeModel()
        record("debug server listening on 127.0.0.1:\(Self.port)")
    }

    // MARK: - Event log

    func record(_ message: String) {
        events.append(["t": Date().timeIntervalSince1970, "event": message])
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    private func observeModel() {
        model.$state
            .removeDuplicates()
            .sink { [weak self] in self?.record("state -> \($0)") }
            .store(in: &cancellables)
        model.$isPlaying
            .removeDuplicates()
            .sink { [weak self] in self?.record("isPlaying -> \($0)") }
            .store(in: &cancellables)
        model.$title
            .removeDuplicates()
            .sink { [weak self] in self?.record("title -> \"\($0)\"") }
            .store(in: &cancellables)
        model.$call
            .map { $0.map { "\($0.appName) camera=\($0.cameraOn)" } ?? "none" }
            .removeDuplicates()
            .sink { [weak self] in self?.record("call -> \($0)") }
            .store(in: &cancellables)
        model.$playerBundleID
            .removeDuplicates()
            .sink { [weak self] in self?.record("player -> \($0 ?? "none")") }
            .store(in: &cancellables)
        model.$lyrics
            .map(\.count)
            .removeDuplicates()
            .sink { [weak self] in self?.record("lyrics lines -> \($0)") }
            .store(in: &cancellables)
    }

    // MARK: - HTTP

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = HTTPRequest(buffer) {
                let (status, body) = self.handle(request)
                self.respond(on: connection, status: status, body: body)
                return
            }
            if isComplete || error != nil || buffer.count > (8 << 20) {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: buffer)
        }
    }

    private func respond(on connection: NWConnection, status: Int, body: [String: Any]) {
        let json = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data("{}".utf8)
        let reason = status == 200 ? "OK" : "Error"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json\r\nContent-Length: \(json.count)\r\nConnection: close\r\n\r\n"
        var payload = Data(head.utf8)
        payload.append(json)
        connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func handle(_ request: HTTPRequest) -> (Int, [String: Any]) {
        let body = request.json
        switch (request.method, request.path) {
        case ("GET", "/state"):
            return (200, state())
        case ("GET", "/logs"):
            return (200, ["events": events])
        case ("POST", "/inject/now-playing"):
            return inject(body)
        case ("POST", "/inject/clear"):
            isInjecting = false
            releasePointer()
            record("injection cleared, real poller resumed")
            return (200, ["ok": true])
        case ("POST", "/inject/call"):
            return injectCall(body)
        case ("POST", "/inject/call/clear"):
            isInjectingCall = false
            model.setCall(nil)
            record("call injection cleared, real call monitor resumed")
            return (200, ["ok": true])
        case ("POST", "/simulate/call-apps"):
            // Treats extra bundle ids as call apps, to exercise the real
            // CoreAudio detection with whatever holds the mic (e.g. Siri).
            let ids = Set(body["bundle_ids"] as? [String] ?? [])
            calls?.setExtraCallApps(ids)
            record("extra call apps \(ids.sorted())")
            return (200, ["ok": true])
        case ("POST", "/simulate/command"):
            // Same path as the island's buttons: routed to the active source.
            switch body["command"] as? String {
            case "play_pause": model.togglePlayPause()
            case "next": model.skipNext()
            case "previous": model.skipPrevious()
            default: return (400, ["error": "command must be play_pause, next or previous"])
            }
            record("simulated command \(body["command"] ?? "")")
            return (200, ["ok": true])
        case ("POST", "/simulate/hover"):
            return simulateHover(inside: body["inside"] as? Bool ?? true)
        case ("POST", "/simulate/tap"):
            // A real click always has the pointer over the island; without
            // this the watchdog closes the card 0.1s later.
            overridePointer()
            model.tap()
            record("simulated tap")
            return (200, ["ok": true, "state": "\(model.state)"])
        case ("POST", "/simulate/glance"):
            let title = body["title"] as? String ?? "Glance"
            model.presentGlance(title: title, subtitle: body["subtitle"] as? String)
            record("simulated glance")
            return (200, ["ok": true])
        case ("POST", "/simulate/timer"):
            // Injects a system-Clock-like timer; the real monitor is muted
            // until cancel, which hands the real timers back.
            if body["cancel"] as? Bool == true {
                isInjectingTimer = false
                model.applySystemTimers([])
                systemTimers?.republish()
            } else if body["fire"] as? Bool == true {
                isInjectingTimer = true
                model.applySystemTimers([])
                model.systemTimerFired(title: body["title"] as? String ?? "")
            } else {
                isInjectingTimer = true
                let seconds = (body["seconds"] as? Double)
                    ?? ((body["minutes"] as? Double) ?? 1) * 60
                let paused = body["paused"] as? Bool == true
                model.applySystemTimers([SystemTimer(
                    id: "debug-timer",
                    title: body["title"] as? String ?? "",
                    duration: (body["duration"] as? Double) ?? seconds,
                    fireDate: paused ? nil : Date().addingTimeInterval(seconds),
                    pausedRemaining: paused ? seconds : nil
                )])
            }
            record("simulated timer \(body)")
            return (200, ["ok": true])
        case ("POST", "/inject/agenda"):
            return injectAgenda(body)
        case ("POST", "/inject/agenda/clear"):
            agenda?.clearInjection()
            record("agenda injection cleared, EventKit resumed")
            return (200, ["ok": true])
        case ("POST", "/simulate/agenda"):
            model.showAgenda()
            record("opened agenda card")
            return (200, ["ok": true, "state": "\(model.state)"])
        case ("POST", "/debug/test-reminder"):
            // Real EventKit round trip in a dedicated list (see AgendaMonitor).
            guard let agenda else { return (500, ["error": "agenda monitor not attached"]) }
            if body["remove"] as? Bool == true {
                return (200, agenda.removeTestData())
            }
            if let id = body["check"] as? String {
                return (200, ["completed": agenda.testReminderCompleted(id: id) as Any? ?? NSNull()])
            }
            guard let id = agenda.createTestReminder(
                title: body["title"] as? String ?? "DynamicIsland test",
                dueIn: body["due_in"] as? Double ?? 60
            ) else { return (500, ["error": "could not create the test reminder"]) }
            return (200, ["id": id])
        case ("POST", "/simulate/glance-action"):
            guard model.glanceAction != nil else { return (400, ["error": "no glance action"]) }
            model.performGlanceAction()
            record("pressed glance action")
            return (200, ["ok": true])
        case ("POST", "/simulate/lock-preview"):
            lockController?.previewToggle()
            record("toggled lock-screen preview")
            return (200, ["ok": true, "visible": lockController?.window?.isVisible ?? false])
        default:
            return (404, ["error": "unknown endpoint \(request.method) \(request.path)"])
        }
    }

    // MARK: - Actions

    private func inject(_ body: [String: Any]) -> (Int, [String: Any]) {
        guard let title = body["title"] as? String else {
            return (400, ["error": "title is required"])
        }
        var artwork: NSImage? = nil
        if let path = body["artwork_path"] as? String {
            artwork = NSImage(contentsOfFile: path)
            guard artwork != nil else { return (400, ["error": "cannot load artwork_path"]) }
        }
        isInjecting = true
        let snapshot = NowPlayingSnapshot(
            title: title,
            artist: body["artist"] as? String ?? "",
            artwork: artwork,
            accent: artwork.map(ArtworkAccent.color(from:)),
            isPlaying: body["playing"] as? Bool ?? true,
            position: body["position"] as? Double ?? 0,
            duration: body["duration"] as? Double ?? 200,
            playerBundleID: body["bundle_id"] as? String
        )
        model.apply(snapshot)
        record("injected now-playing (playing=\(snapshot.isPlaying))")
        return (200, ["ok": true, "state": "\(model.state)"])
    }

    private func injectCall(_ body: [String: Any]) -> (Int, [String: Any]) {
        guard let bundleID = body["bundle_id"] as? String else {
            return (400, ["error": "bundle_id is required"])
        }
        isInjectingCall = true
        let elapsed = body["elapsed"] as? Double ?? 0
        model.setCall(CallInfo(
            appName: body["app"] as? String ?? CallMonitor.appName(bundleID),
            bundleID: bundleID,
            startedAt: Date().addingTimeInterval(-elapsed),
            cameraOn: body["camera"] as? Bool ?? false
        ))
        record("injected call \(bundleID)")
        return (200, ["ok": true, "state": "\(model.state)"])
    }

    /// Hover exits and the pointer watchdog both ask for the real cursor, which
    /// isn't over the island during a simulated hover, so that check is
    /// overridden for as long as the simulation is on.
    private func simulateHover(inside: Bool) -> (Int, [String: Any]) {
        if inside {
            overridePointer()
            model.hover(true)
        } else {
            releasePointer()
            model.hover(false)
        }
        record("simulated hover inside=\(inside)")
        return (200, ["ok": true, "state": "\(model.state)"])
    }

    /// Hands the pointer check back to the real cursor. Called on hover exit
    /// and on /inject/clear so a simulated tap can't pin the island open.
    /// Times are relative to now, in seconds: `start_in`, `duration`,
    /// `due_in` (negative = in the past / overdue).
    private func injectAgenda(_ body: [String: Any]) -> (Int, [String: Any]) {
        guard let agenda else { return (500, ["error": "agenda monitor not attached"]) }
        let now = Date()
        let rawEvents = body["events"] as? [[String: Any]] ?? []
        let rawReminders = body["reminders"] as? [[String: Any]] ?? []
        let events = rawEvents.enumerated().map { index, raw -> AgendaEvent in
            let start = now.addingTimeInterval(raw["start_in"] as? Double ?? 0)
            return AgendaEvent(
                id: "debug-event-\(index)",
                title: raw["title"] as? String ?? "Событие",
                start: start,
                end: start.addingTimeInterval(raw["duration"] as? Double ?? 1800),
                joinURL: (raw["join"] as? String).flatMap(URL.init(string:))
            )
        }
        let reminders = rawReminders.enumerated().map { index, raw -> AgendaReminder in
            AgendaReminder(
                id: "debug-reminder-\(index)",
                title: raw["title"] as? String ?? "Напоминание",
                due: (raw["due_in"] as? Double).map { now.addingTimeInterval($0) }
            )
        }
        agenda.inject(events: events, reminders: reminders)
        record("injected agenda: \(events.count) events, \(reminders.count) reminders")
        return (200, ["ok": true, "content": model.content.rawValue, "state": "\(model.state)"])
    }

    private func releasePointer() {
        guard hoverSimulated else { return }
        model.pointerIsInsideIsland = realPointerCheck
        realPointerCheck = nil
        hoverSimulated = false
    }

    private func overridePointer() {
        guard !hoverSimulated else { return }
        realPointerCheck = model.pointerIsInsideIsland
        model.pointerIsInsideIsland = { true }
        hoverSimulated = true
    }

    // MARK: - State

    private func state() -> [String: Any] {
        let screen = islandController?.window?.screen ?? NSScreen.main
        let screenFrame = screen?.frame ?? .zero
        let notch = ScreenNotch.size(for: screen)
        let notchRect = CGRect(
            x: screenFrame.midX - notch.width / 2,
            y: screenFrame.maxY - notch.height,
            width: notch.width,
            height: notch.height
        )
        let settings = IslandSettings.shared
        var result: [String: Any] = [
            "coordinates": "top-left origin, points, main display",
            "state": "\(model.state)",
            "isIslandVisible": model.isIslandVisible,
            "hasContent": model.hasContent,
            "title": model.title,
            "artist": model.artist,
            "isPlaying": model.isPlaying,
            "position": model.position,
            "duration": model.duration,
            "hasArtwork": model.artwork != nil,
            "lyricsCount": model.lyrics.count,
            "currentLyricIndex": model.currentLyricIndex as Any? ?? NSNull(),
            "lockPresentation": "\(model.lockPresentation)",
            "isLockScreenVisible": model.isLockScreenVisible,
            "timerRemaining": model.timerRemaining as Any? ?? NSNull(),
            "timer": model.systemTimer.map { timer -> [String: Any] in
                [
                    "id": timer.id,
                    "title": timer.title,
                    "duration": timer.duration,
                    "paused": timer.isPaused,
                    "remaining": timer.remaining(),
                ]
            } as Any? ?? NSNull(),
            "injectingTimer": isInjectingTimer,
            "glanceTitle": model.glanceTitle as Any? ?? NSNull(),
            "glanceAction": model.glanceAction?.label as Any? ?? NSNull(),
            "agenda": [
                "events": model.agenda.events.map { ["title": $0.title, "startIn": $0.start.timeIntervalSinceNow,
                                                     "hasJoin": $0.joinURL != nil] },
                "reminders": model.agenda.reminders.map { ["title": $0.title,
                                                          "dueIn": $0.due?.timeIntervalSinceNow as Any? ?? NSNull()] },
                "nowEvent": model.agenda.nowEvent?.title as Any? ?? NSNull(),
                "nowReminder": model.agenda.nowReminder?.title as Any? ?? NSNull(),
                "pinned": model.isAgendaPinned,
                "injecting": agenda?.isInjecting ?? false,
                "eventsAuthorization": agenda?.eventsAuthorization ?? "unknown",
                "remindersAuthorization": agenda?.remindersAuthorization ?? "unknown",
            ] as [String: Any],
            "injecting": isInjecting,
            "injectingCall": isInjectingCall,
            "content": model.content.rawValue,
            "playerBundleID": model.playerBundleID as Any? ?? NSNull(),
            "nowPlayingSource": poller?.source.rawValue ?? "none",
            "showsAppIcon": model.artwork == nil && model.displayArtwork != nil,
            "call": model.call.map { call -> [String: Any] in
                [
                    "app": call.appName,
                    "bundleID": call.bundleID,
                    "cameraOn": call.cameraOn,
                    "elapsed": Date().timeIntervalSince(call.startedAt),
                ]
            } as Any? ?? NSNull(),
            "hoverSimulated": hoverSimulated,
            "screen": [
                "frame": topLeft(screenFrame, in: screenFrame),
                "scale": screen?.backingScaleFactor ?? 1,
                "hasNotch": (screen?.safeAreaInsets.top ?? 0) > 0,
            ],
            "notchRect": topLeft(notchRect, in: screenFrame),
            "settings": [
                "collapsedWidth": settings.collapsedWidth,
                "collapsedHeight": settings.collapsedHeight,
                "expandedWidth": settings.expandedWidth,
                "expandedHeight": settings.expandedHeight,
                "fillet": settings.fillet,
                "animationDuration": settings.animationDuration,
                "lockScreenEnabled": settings.lockScreenEnabled,
                "lyricsEnabled": settings.lyricsEnabled,
                "showShadow": settings.showShadow,
            ],
        ]
        if let panel = islandController?.window {
            result["islandWindow"] = [
                "frame": topLeft(panel.frame, in: screenFrame),
                "visible": panel.isVisible,
                "alpha": panel.alphaValue,
            ]
        }
        if let rect = islandController?.debugIslandScreenRect {
            let shape = topLeft(rect, in: screenFrame)
            result["islandShapeRect"] = shape
            // Collapsed ears' drawn content, in the same top-left screen points.
            if let x = shape["x"], let y = shape["y"] {
                result["contentFrames"] = model.collapsedContentFrames.mapValues { frame -> [String: Double] in
                    [
                        "x": x + frame.minX, "y": y + frame.minY,
                        "width": frame.width, "height": frame.height,
                    ]
                }
            }
        }
        if let window = lockController?.window {
            result["lockWindow"] = [
                "frame": topLeft(window.frame, in: screenFrame),
                "visible": window.isVisible,
            ]
        }
        return result
    }

    /// AppKit's origin is bottom-left; screenshots and the MCP use top-left.
    private func topLeft(_ rect: CGRect, in screen: CGRect) -> [String: Double] {
        [
            "x": rect.minX - screen.minX,
            "y": screen.maxY - rect.maxY,
            "width": rect.width,
            "height": rect.height,
        ]
    }
}

/// Just enough HTTP/1.1 parsing for a local debug client: request line,
/// Content-Length and a JSON body. Returns nil until the request is complete.
private struct HTTPRequest {
    let method: String
    let path: String
    let json: [String: Any]

    init?(_ data: Data) {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator),
              let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8)
        else { return nil }

        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return nil }

        let declared = lines
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) }
            ?? 0
        // A negative length would trap in `prefix(_:)`; treat it as no body.
        let length = max(0, declared)
        let body = data[headerEnd.upperBound...]
        guard body.count >= length else { return nil }

        method = String(parts[0])
        path = String(parts[1].split(separator: "?").first ?? "")
        json = (try? JSONSerialization.jsonObject(with: Data(body.prefix(length)))) as? [String: Any] ?? [:]
    }
}
#endif
