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
    private var listener: NWListener?
    private var cancellables = Set<AnyCancellable>()

    /// While true the real poller's snapshots are dropped, so an injected
    /// track isn't overwritten a second later.
    private(set) var isInjecting = false

    private var hoverSimulated = false
    private var realPointerCheck: (() -> Bool)?

    /// In-memory only; never written to disk.
    private var events: [[String: Any]] = []
    private let maxEvents = 300

    init(
        model: IslandViewModel,
        islandController: IslandWindowController?,
        lockController: LockScreenWindowController?
    ) {
        self.model = model
        self.islandController = islandController
        self.lockController = lockController
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
            if body["cancel"] as? Bool == true {
                model.cancelTimer()
            } else {
                model.startTimer(minutes: (body["minutes"] as? Double) ?? 1)
            }
            record("simulated timer \(body)")
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
            "glanceTitle": model.glanceTitle as Any? ?? NSNull(),
            "injecting": isInjecting,
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
            result["islandShapeRect"] = topLeft(rect, in: screenFrame)
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
