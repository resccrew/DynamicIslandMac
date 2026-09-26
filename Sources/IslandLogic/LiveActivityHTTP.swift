import Foundation

/// A parsed HTTP/1.1 request, just enough for the local Live Activity API.
public struct LiveActivityRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    /// Lowercased names.
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public enum LiveActivityHTTPError: Error, Equatable, Sendable {
    /// Keep reading: the head or the body isn't complete yet.
    case incomplete
    case malformed
    case tooLarge
    case forbiddenOrigin
    case badHost
    case unauthorized

    public var status: Int {
        switch self {
        case .incomplete, .malformed: return 400
        case .tooLarge: return 413
        case .forbiddenOrigin, .badHost: return 403
        case .unauthorized: return 401
        }
    }
}

public enum LiveActivityHTTP {
    static let maxHeadBytes = 8192

    /// Parses a request out of the bytes read so far.
    public static func parse(_ data: Data, maxBody: Int) -> Result<LiveActivityRequest, LiveActivityHTTPError> {
        guard let range = data.range(of: Data("\r\n\r\n".utf8)) else {
            return .failure(data.count > maxHeadBytes ? .tooLarge : .incomplete)
        }
        guard range.lowerBound <= maxHeadBytes,
              let head = String(data: data[data.startIndex..<range.lowerBound], encoding: .utf8)
        else { return .failure(.malformed) }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return .failure(.malformed) }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .failure(.malformed) }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .failure(.malformed) }
            // A repeated Host/Authorization is a smuggling trick, not a client.
            guard headers[name] == nil else { return .failure(.malformed) }
            headers[name] = value
        }
        if headers["transfer-encoding"] != nil { return .failure(.malformed) }

        let length: Int
        if let raw = headers["content-length"] {
            guard let parsed = Int(raw), parsed >= 0 else { return .failure(.malformed) }
            length = parsed
        } else {
            length = 0
        }
        guard length <= maxBody else { return .failure(.tooLarge) }
        let bodyStart = range.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return .failure(.incomplete) }
        let body = data[bodyStart..<(bodyStart + length)]
        return .success(LiveActivityRequest(
            method: String(parts[0]),
            path: String(parts[1]),
            headers: headers,
            body: Data(body)
        ))
    }

    /// Only local, non-browser clients holding the token get through.
    ///
    /// - A browser always sends `Origin` on cross-site POSTs and fetches, so
    ///   any request carrying one is refused: web pages can't drive the island.
    /// - `Host` must name loopback, which defeats DNS rebinding.
    /// - The bearer token is compared in constant time.
    public static func authorize(_ request: LiveActivityRequest, token: String, port: UInt16) -> Result<Void, LiveActivityHTTPError> {
        if request.headers["origin"] != nil { return .failure(.forbiddenOrigin) }
        guard let host = request.headers["host"], isLoopbackHost(host, port: port) else { return .failure(.badHost) }
        guard let auth = request.headers["authorization"], auth.hasPrefix("Bearer ") else {
            return .failure(.unauthorized)
        }
        let presented = String(auth.dropFirst("Bearer ".count))
        guard !token.isEmpty, constantTimeEquals(presented, token) else { return .failure(.unauthorized) }
        return .success(())
    }

    static func isLoopbackHost(_ host: String, port: UInt16) -> Bool {
        let allowed = ["127.0.0.1", "localhost", "[::1]"]
        return allowed.contains(host.lowercased()) || allowed.contains { host.lowercased() == "\($0):\(port)" }
    }

    static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = UInt8(x.count == y.count ? 0 : 1)
        for i in 0..<max(x.count, y.count) {
            diff |= (i < x.count ? x[i] : 0) ^ (i < y.count ? y[i] : 0)
        }
        return diff == 0
    }
}
