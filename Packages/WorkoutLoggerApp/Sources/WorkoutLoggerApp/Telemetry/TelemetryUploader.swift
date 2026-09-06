import Foundation

/// The whole analytics send policy in one tested, pure-logic object: a
/// persisted local queue, batched delivery, exponential back-off on failure,
/// a hard cap, and opt-out discard. It is a `TelemetrySink`, so the recorder
/// forwards straight to it. `record(_:)` only touches local state — the
/// logging loop never waits on the network (`PRODUCT.md`).
@MainActor
public final class TelemetryUploader: @MainActor TelemetrySink {

    public struct Config: Sendable {
        public var batchSize: Int
        public var maxQueuedEvents: Int
        public var baseRetryDelay: TimeInterval
        public var maxRetryDelay: TimeInterval

        public init(
            batchSize: Int = 20,
            maxQueuedEvents: Int = 500,
            baseRetryDelay: TimeInterval = 60,
            maxRetryDelay: TimeInterval = 3600
        ) {
            self.batchSize = batchSize
            self.maxQueuedEvents = maxQueuedEvents
            self.baseRetryDelay = baseRetryDelay
            self.maxRetryDelay = maxRetryDelay
        }
    }

    private let transport: TelemetryTransport
    private let queueStore: TelemetryQueueStore
    private let config: Config
    private let now: () -> Date

    private var state: TelemetryQueueState
    private var failureCount = 0
    private var nextAttemptAt: Date = .distantPast

    public init(
        transport: TelemetryTransport,
        queueStore: TelemetryQueueStore,
        config: Config = Config(),
        now: @escaping () -> Date = Date.init
    ) {
        self.transport = transport
        self.queueStore = queueStore
        self.config = config
        self.now = now

        var loaded = queueStore.load()
        if loaded.installID.isEmpty {
            loaded.installID = UUID().uuidString
            queueStore.save(loaded)
        }
        self.state = loaded
    }

    public var pendingCount: Int { state.pending.count }
    public var installID: String { state.installID }

    // MARK: TelemetrySink

    public func record(_ event: TelemetryEvent) {
        state.pending.append(QueuedEvent(
            event: TelemetryPayloadCodec.payload(for: event),
            recordedAt: now()
        ))
        if state.pending.count > config.maxQueuedEvents {
            state.pending.removeFirst(state.pending.count - config.maxQueuedEvents)
        }
        queueStore.save(state)
    }

    /// Deliver at most one batch. Safe to call on app-foreground, on a timer,
    /// or after `record`; it no-ops when the queue is empty or a back-off
    /// window is open (Task 6).
    public func flush() async {
        guard !state.pending.isEmpty, now() >= nextAttemptAt else { return }

        let batch = Array(state.pending.prefix(config.batchSize))
        let payload = TelemetryPayload(
            installID: state.installID,
            events: batch.map(\.event)
        )
        let body: Data
        do {
            body = try JSONEncoder().encode(payload)
        } catch {
            return // an un-encodable content-free payload is not a real case; drop the attempt
        }

        do {
            try await transport.send(body)
            state.pending.removeFirst(batch.count)
            failureCount = 0
            nextAttemptAt = .distantPast
            queueStore.save(state)
        } catch {
            registerFailure()
        }
    }

    private func registerFailure() {
        failureCount += 1
        // filled in by Task 6
    }
}
