import Foundation

/// Decides which media source owns the island when several report.
///
/// Rules: a playing source beats a paused one; among playing sources the one
/// that most recently *started* playing wins; with nothing playing, the
/// latest report wins. A playing source counts as playing only while its
/// report is fresh (`staleAfter`), or while it is the latest reporter — so a
/// source that stopped reporting can't hold the island forever, and a paused
/// old source reporting in can't steal it from one that is still playing.
public struct NowPlayingArbiter {
    public struct Source: Equatable {
        public let id: String
        public var isPlaying: Bool
        public var lastStartedAt: Date?
        public var reportedAt: Date
    }

    public let staleAfter: TimeInterval
    public private(set) var sources: [String: Source] = [:]
    private var latestID: String?

    public init(staleAfter: TimeInterval = 3) {
        self.staleAfter = staleAfter
    }

    /// Records a report and returns the current winner's id.
    @discardableResult
    public mutating func report(id: String, isPlaying: Bool, at now: Date) -> String? {
        var source = sources[id] ?? Source(id: id, isPlaying: false, lastStartedAt: nil, reportedAt: now)
        if isPlaying && (!source.isPlaying || source.lastStartedAt == nil) {
            source.lastStartedAt = now
        }
        source.isPlaying = isPlaying
        source.reportedAt = now
        sources[id] = source
        latestID = id
        return winner(at: now)
    }

    /// Nothing is playing anywhere: forget every source.
    public mutating func reset() {
        sources.removeAll()
        latestID = nil
    }

    public func winner(at now: Date) -> String? {
        let playing = sources.values.filter { source in
            source.isPlaying && (source.id == latestID || now.timeIntervalSince(source.reportedAt) <= staleAfter)
        }
        if let best = playing.max(by: { ($0.lastStartedAt ?? .distantPast) < ($1.lastStartedAt ?? .distantPast) }) {
            return best.id
        }
        return latestID
    }
}
