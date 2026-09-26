import Foundation

/// Where an external job is: still going, or finished one way or the other.
public enum LiveActivityState: String, Codable, Sendable {
    case running
    case success
    case failure

    public var isFinished: Bool { self != .running }
}

/// One activity pushed by a script, CI job or agent through the local API.
public struct LiveActivity: Equatable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String?
    /// SF Symbol name; the view falls back to a generic one if it doesn't exist.
    public var symbol: String?
    /// 0...1, or nil for an indeterminate (spinning) activity.
    public var progress: Double?
    /// `#RRGGBB`.
    public var accentHex: String?
    public var state: LiveActivityState
    /// Seconds a finished activity stays before it goes away on its own.
    public var dismissAfter: TimeInterval?
    public var createdAt: Date
    public var updatedAt: Date
    /// When `state` first became success/failure.
    public var finishedAt: Date?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        symbol: String? = nil,
        progress: Double? = nil,
        accentHex: String? = nil,
        state: LiveActivityState = .running,
        dismissAfter: TimeInterval? = nil,
        createdAt: Date,
        updatedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.progress = progress
        self.accentHex = accentHex
        self.state = state
        self.dismissAfter = dismissAfter
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.finishedAt = finishedAt
    }

    /// When this activity leaves the island by itself, if ever.
    public func expiry(rules: LiveActivityRules = .init()) -> Date {
        if let finishedAt {
            return finishedAt.addingTimeInterval(dismissAfter ?? rules.defaultDismissAfter)
        }
        // A script that died mid-run never sends its final state.
        return updatedAt.addingTimeInterval(rules.staleRunningAfter)
    }
}

/// Limits and timings of the API, in one place so tests can pin them.
public struct LiveActivityRules: Equatable, Sendable {
    public var maxActivities = 5
    public var maxBodyBytes = 4096
    public var maxIDLength = 64
    public var maxTitleLength = 80
    public var maxSubtitleLength = 120
    public var maxSymbolLength = 64
    public var maxDismissAfter: TimeInterval = 3600
    /// A finished activity without an explicit `dismiss` goes after this.
    public var defaultDismissAfter: TimeInterval = 8
    /// A running activity nobody updated for this long is dropped.
    public var staleRunningAfter: TimeInterval = 15 * 60

    public init() {}
}

public enum LiveActivityError: Error, Equatable, Sendable {
    case malformedJSON
    case invalidField(String, String)
    case missingTitle
    case tooManyActivities(Int)
    case notFound(String)

    public var message: String {
        switch self {
        case .malformedJSON: return "body must be a JSON object"
        case let .invalidField(field, why): return "\(field): \(why)"
        case .missingTitle: return "title is required for a new activity"
        case let .tooManyActivities(max): return "at most \(max) activities at once"
        case let .notFound(id): return "no activity with id \(id)"
        }
    }
}

/// A validated push: only the fields the client sent, so an update can change
/// the state alone (`island push --id build --state success`).
public struct LiveActivityUpdate: Equatable, Sendable {
    public var id: String
    public var title: String?
    public var subtitle: String?
    public var symbol: String?
    public var progress: Double?
    public var accentHex: String?
    public var state: LiveActivityState?
    public var dismissAfter: TimeInterval?

    public init(
        id: String,
        title: String? = nil,
        subtitle: String? = nil,
        symbol: String? = nil,
        progress: Double? = nil,
        accentHex: String? = nil,
        state: LiveActivityState? = nil,
        dismissAfter: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.progress = progress
        self.accentHex = accentHex
        self.state = state
        self.dismissAfter = dismissAfter
    }
}

public enum LiveActivityPayload {
    private struct Raw: Decodable {
        var id: String?
        var title: String?
        var subtitle: String?
        var symbol: String?
        var progress: Double?
        var color: String?
        var state: String?
        var dismiss: Double?
    }

    private struct ClearRaw: Decodable {
        var id: String?
    }

    /// Parses and checks a push body.
    public static func parsePush(_ body: Data, rules: LiveActivityRules = .init()) -> Result<LiveActivityUpdate, LiveActivityError> {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: body) else { return .failure(.malformedJSON) }
        switch validID(raw.id, rules: rules) {
        case let .failure(error): return .failure(error)
        case let .success(id):
            var update = LiveActivityUpdate(id: id)
            if let title = raw.title {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return .failure(.invalidField("title", "must not be empty")) }
                guard trimmed.count <= rules.maxTitleLength else {
                    return .failure(.invalidField("title", "longer than \(rules.maxTitleLength)"))
                }
                update.title = trimmed
            }
            if let subtitle = raw.subtitle {
                let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count <= rules.maxSubtitleLength else {
                    return .failure(.invalidField("subtitle", "longer than \(rules.maxSubtitleLength)"))
                }
                update.subtitle = trimmed
            }
            if let symbol = raw.symbol {
                guard !symbol.isEmpty, symbol.count <= rules.maxSymbolLength,
                      symbol.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == ".") })
                else { return .failure(.invalidField("symbol", "SF Symbol name like hammer.fill")) }
                update.symbol = symbol
            }
            if let progress = raw.progress {
                guard progress.isFinite, (0...1).contains(progress) else {
                    return .failure(.invalidField("progress", "must be within 0...1"))
                }
                update.progress = progress
            }
            if let color = raw.color {
                guard isHexColor(color) else { return .failure(.invalidField("color", "must be #RRGGBB")) }
                update.accentHex = color.uppercased()
            }
            if let state = raw.state {
                guard let parsed = LiveActivityState(rawValue: state) else {
                    return .failure(.invalidField("state", "running, success or failure"))
                }
                update.state = parsed
            }
            if let dismiss = raw.dismiss {
                guard dismiss.isFinite, (0...rules.maxDismissAfter).contains(dismiss) else {
                    return .failure(.invalidField("dismiss", "seconds within 0...\(Int(rules.maxDismissAfter))"))
                }
                update.dismissAfter = dismiss
            }
            return .success(update)
        }
    }

    /// Parses a clear body: `{"id": "build"}`, or `{}` to clear everything (nil).
    public static func parseClear(_ body: Data, rules: LiveActivityRules = .init()) -> Result<String?, LiveActivityError> {
        if body.isEmpty { return .success(nil) }
        guard let raw = try? JSONDecoder().decode(ClearRaw.self, from: body) else { return .failure(.malformedJSON) }
        guard raw.id != nil else { return .success(nil) }
        return validID(raw.id, rules: rules).map { Optional($0) }
    }

    static func validID(_ id: String?, rules: LiveActivityRules) -> Result<String, LiveActivityError> {
        guard let id, !id.isEmpty else { return .failure(.invalidField("id", "is required")) }
        guard id.count <= rules.maxIDLength,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) })
        else { return .failure(.invalidField("id", "1-\(rules.maxIDLength) of A-Z a-z 0-9 - _ .")) }
        return .success(id)
    }

    static func isHexColor(_ s: String) -> Bool {
        s.count == 7 && s.first == "#" && s.dropFirst().allSatisfy { $0.isHexDigit }
    }
}

/// All pushed activities, which one the island shows, and when they expire.
/// A value type with no clock of its own: every call takes `now`.
public struct LiveActivityStore: Equatable, Sendable {
    public private(set) var activities: [String: LiveActivity] = [:]
    public let rules: LiveActivityRules

    public init(rules: LiveActivityRules = .init()) {
        self.rules = rules
    }

    /// Creates or merges an activity; fields the update omits keep their value.
    @discardableResult
    public mutating func apply(_ update: LiveActivityUpdate, now: Date) -> Result<LiveActivity, LiveActivityError> {
        expire(now: now)
        var activity: LiveActivity
        if let existing = activities[update.id] {
            activity = existing
        } else {
            guard activities.count < rules.maxActivities else { return .failure(.tooManyActivities(rules.maxActivities)) }
            guard let title = update.title else { return .failure(.missingTitle) }
            activity = LiveActivity(id: update.id, title: title, createdAt: now)
        }
        if let title = update.title { activity.title = title }
        if let subtitle = update.subtitle { activity.subtitle = subtitle.isEmpty ? nil : subtitle }
        if let symbol = update.symbol { activity.symbol = symbol }
        if let progress = update.progress { activity.progress = progress }
        if let accent = update.accentHex { activity.accentHex = accent }
        if let dismiss = update.dismissAfter { activity.dismissAfter = dismiss }
        if let state = update.state {
            if state.isFinished, !activity.state.isFinished || activity.state != state { activity.finishedAt = now }
            if !state.isFinished { activity.finishedAt = nil }
            activity.state = state
        }
        activity.updatedAt = now
        activities[update.id] = activity
        return .success(activity)
    }

    public mutating func remove(id: String) -> Result<Void, LiveActivityError> {
        guard activities.removeValue(forKey: id) != nil else { return .failure(.notFound(id)) }
        return .success(())
    }

    public mutating func removeAll() {
        activities.removeAll()
    }

    /// Drops finished activities past their dismiss time and stale running ones.
    public mutating func expire(now: Date) {
        activities = activities.filter { $0.value.expiry(rules: rules) > now }
    }

    /// The earliest moment `expire` would drop something.
    public func nextExpiry() -> Date? {
        activities.values.map { $0.expiry(rules: rules) }.min()
    }

    /// The one the island shows. A freshly finished activity is the news, so
    /// it wins (latest finish first) until it's dismissed; otherwise the
    /// running one that started last — by start, not by update, so progress
    /// ticks of two parallel jobs don't make the island flicker between them.
    public var current: LiveActivity? {
        let all = Array(activities.values)
        let finished = all.filter { $0.finishedAt != nil }
        if let latest = finished.max(by: { ($0.finishedAt!, $1.id) < ($1.finishedAt!, $0.id) }) {
            return latest
        }
        return all.max { ($0.createdAt, $1.id) < ($1.createdAt, $0.id) }
    }

    /// Newest first, for the list endpoint.
    public var sorted: [LiveActivity] {
        activities.values.sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }
}
