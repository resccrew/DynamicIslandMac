import AppKit
import IslandLogic
import Network
import Security

/// The public, release-build HTTP API that lets scripts, CI and agents show a
/// Live Activity in the island (see `tools/island` and the README).
///
/// Unlike `DebugControlServer` this ships to users, so it is locked down:
/// loopback only, a bearer token from a 0600 file, no browser `Origin`, a
/// loopback `Host`, capped bodies, connections and activity count. The rules
/// themselves live in `IslandLogic` (`LiveActivityHTTP`, `LiveActivityStore`).
///
/// Runs on the main queue, so the model is only ever touched on main.
final class LiveActivityServer {
    static let port: UInt16 = 47810
    private static let maxConnections = 16
    private static let readTimeout: TimeInterval = 5

    private let model: IslandViewModel
    private var store = LiveActivityStore()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var expiryTimer: Timer?
    private var token = ""

    init(model: IslandViewModel) {
        self.model = model
    }

    var isRunning: Bool { listener != nil }

    /// Starts or stops with the «Разрешить внешний API» setting.
    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    private func start() {
        guard listener == nil else { return }
        switch LiveActivityToken.loadOrCreate() {
        case let .failure(error):
            NSLog("Live Activity API disabled: token unavailable (\(error))")
            return
        case let .success(token):
            self.token = token
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else {
            NSLog("Live Activity API: can't listen on 127.0.0.1:\(Self.port)")
            return
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.stop() }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        store.removeAll()
        publish()
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        guard connections.count < Self.maxConnections else {
            connection.cancel()
            return
        }
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed: self?.connections.removeValue(forKey: key)
            default: break
            }
        }
        connection.start(queue: .main)
        // A client that never finishes its request doesn't hold a slot forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.readTimeout) { [weak connection] in
            connection?.cancel()
        }
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch LiveActivityHTTP.parse(buffer, maxBody: self.store.rules.maxBodyBytes) {
            case let .success(request):
                let (status, body) = self.handle(request)
                self.respond(on: connection, status: status, body: body)
            case .failure(.incomplete) where !isComplete && error == nil:
                self.receive(on: connection, buffer: buffer)
            case .failure(.incomplete):
                connection.cancel()
            case let .failure(failure):
                self.respond(on: connection, status: failure.status, body: ["error": "\(failure)"])
            }
        }
    }

    private func respond(on connection: NWConnection, status: Int, body: [String: Any]) {
        let json = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data("{}".utf8)
        var head = "HTTP/1.1 \(status) \(status < 300 ? "OK" : "Error")\r\n"
        head += "Content-Type: application/json\r\nContent-Length: \(json.count)\r\nConnection: close\r\n\r\n"
        var payload = Data(head.utf8)
        payload.append(json)
        connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - Routes

    private func handle(_ request: LiveActivityRequest) -> (Int, [String: Any]) {
        if case let .failure(failure) = LiveActivityHTTP.authorize(request, token: token, port: Self.port) {
            return (failure.status, ["error": "\(failure)"])
        }
        let now = Date()
        switch (request.method, request.path) {
        case ("POST", "/v1/activity"):
            switch LiveActivityPayload.parsePush(request.body, rules: store.rules) {
            case let .failure(error):
                return (400, ["error": error.message])
            case let .success(update):
                switch store.apply(update, now: now) {
                case let .failure(error):
                    return (error == .missingTitle ? 400 : 429, ["error": error.message])
                case let .success(activity):
                    publish()
                    return (200, ["ok": true, "activity": Self.json(activity)])
                }
            }
        case ("POST", "/v1/clear"):
            switch LiveActivityPayload.parseClear(request.body, rules: store.rules) {
            case let .failure(error):
                return (400, ["error": error.message])
            case .success(nil):
                store.removeAll()
                publish()
                return (200, ["ok": true])
            case let .success(id?):
                if case let .failure(error) = store.remove(id: id) { return (404, ["error": error.message]) }
                publish()
                return (200, ["ok": true])
            }
        case ("GET", "/v1/activities"):
            store.expire(now: now)
            return (200, ["activities": store.sorted.map(Self.json), "shown": store.current?.id as Any? ?? NSNull()])
        default:
            return (404, ["error": "unknown route \(request.method) \(request.path)"])
        }
    }

    private static func json(_ activity: LiveActivity) -> [String: Any] {
        [
            "id": activity.id,
            "title": activity.title,
            "subtitle": activity.subtitle as Any? ?? NSNull(),
            "symbol": activity.symbol as Any? ?? NSNull(),
            "progress": activity.progress as Any? ?? NSNull(),
            "color": activity.accentHex as Any? ?? NSNull(),
            "state": activity.state.rawValue,
        ]
    }

    // MARK: - Island

    /// Hands the winning activity to the island and re-arms the dismiss timer.
    private func publish() {
        store.expire(now: Date())
        model.setLiveActivity(store.current)
        expiryTimer?.invalidate()
        expiryTimer = nil
        guard let next = store.nextExpiry() else { return }
        expiryTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, next.timeIntervalSinceNow), repeats: false) {
            [weak self] _ in self?.publish()
        }
    }
}

/// The API token, kept in Application Support with owner-only permissions.
enum LiveActivityToken {
    enum Failure: Error {
        case directory
        case random
        case write
    }

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DynamicIslandMac", isDirectory: true)
            .appendingPathComponent("api-token")
    }

    static func loadOrCreate() -> Result<String, Failure> {
        let fm = FileManager.default
        let url = fileURL
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        } catch {
            return .failure(.directory)
        }
        if let existing = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), existing.count >= 32 {
            // Tighten a file someone loosened by hand.
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return .success(existing)
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return .failure(.random)
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        // Created 0600 from the start: never world-readable, even briefly.
        let created = fm.createFile(atPath: url.path, contents: Data((token + "\n").utf8),
                                    attributes: [.posixPermissions: 0o600])
        if !created {
            guard (try? Data((token + "\n").utf8).write(to: url)) != nil else { return .failure(.write) }
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return .success(token)
    }
}
