import Foundation

/// Records every `send` call for the watch-transport tests (cluster 7f).
public final class SpyWatchSummaryTransport: WatchSummaryTransport {
    public private(set) var sent: [Date?] = []
    public init() {}
    public func send(lastWorkoutEndedAt: Date?) { sent.append(lastWorkoutEndedAt) }
}
