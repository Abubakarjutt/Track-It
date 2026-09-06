import Foundation

/// One pending event, stored already in its content-free wire form so the
/// on-disk queue can never hold anything the wire could not.
public struct QueuedEvent: Codable, Equatable, Sendable {
    public let event: TelemetryEventPayload
    public let recordedAt: Date

    public init(event: TelemetryEventPayload, recordedAt: Date) {
        self.event = event
        self.recordedAt = recordedAt
    }
}

/// Everything the uploader persists between launches: the stable install id
/// and the not-yet-sent events. Back-off state is deliberately in-memory
/// only — a relaunch just means the next retry happens one interval sooner.
public struct TelemetryQueueState: Codable, Equatable, Sendable {
    public var installID: String
    public var pending: [QueuedEvent]

    public init(installID: String = UUID().uuidString, pending: [QueuedEvent] = []) {
        self.installID = installID
        self.pending = pending
    }
}

/// Persists `TelemetryQueueState`. The app writes a JSON file; tests keep it
/// in memory.
public protocol TelemetryQueueStore: AnyObject {
    func load() -> TelemetryQueueState
    func save(_ state: TelemetryQueueState)
}

/// In-memory `TelemetryQueueStore` for tests and previews.
public final class InMemoryTelemetryQueueStore: TelemetryQueueStore {
    private var state: TelemetryQueueState
    public init(_ initial: TelemetryQueueState = TelemetryQueueState()) {
        self.state = initial
    }
    public func load() -> TelemetryQueueState { state }
    public func save(_ state: TelemetryQueueState) { self.state = state }
}
