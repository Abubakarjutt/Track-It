import Foundation

/// The whole analytics send policy in one tested, pure-logic object: a
/// persisted local queue, batched delivery, exponential back-off on failure,
/// a hard cap, and opt-out discard. It is a `TelemetrySink`, so the recorder
/// forwards straight to it. `record(_:)` only touches local state — the
/// logging loop never waits on the network (`PRODUCT.md`).
///
/// `TelemetrySink` is a non-isolated protocol (its other conformers — the
/// no-op sink and the test fake — hold no actor state). The `@MainActor
/// TelemetrySink` spelling below is a deliberate *isolated conformance*: the
/// type keeps its `@MainActor` isolation and the compiler confines the
/// conformance to the main actor, which is where the recorder already calls
/// it. Drop the isolated spelling and the conformance would have to be
/// `nonisolated`, forcing `record(_:)` to hop off the actor and reopening the
/// data race the isolation is here to prevent.
@MainActor
public final class TelemetryUploader: @MainActor TelemetrySink {

    public struct Config: Sendable {
        public var batchSize: Int
        public var maxQueuedEvents: Int
        public var baseRetryDelay: TimeInterval
        public var maxRetryDelay: TimeInterval
        /// After this many consecutive unclassified send failures the head
        /// batch is dropped, so a poison batch the taxonomy doesn't catch
        /// can't wedge the queue behind it forever.
        public var maxConsecutiveFailures: Int

        public init(
            batchSize: Int = 20,
            maxQueuedEvents: Int = 500,
            baseRetryDelay: TimeInterval = 60,
            maxRetryDelay: TimeInterval = 3600,
            maxConsecutiveFailures: Int = 10
        ) {
            self.batchSize = batchSize
            self.maxQueuedEvents = maxQueuedEvents
            self.baseRetryDelay = baseRetryDelay
            self.maxRetryDelay = maxRetryDelay
            self.maxConsecutiveFailures = maxConsecutiveFailures
        }
    }

    private let transport: TelemetryTransport
    private let queueStore: TelemetryQueueStore
    private let config: Config
    private let now: () -> Date

    private var state: TelemetryQueueState
    private var failureCount = 0
    private var nextAttemptAt: Date = .distantPast
    private var isFlushing = false
    /// Bumped whenever the head of `pending` moves or clears out from under an
    /// in-flight send — `discardPending()` and the `record(_:)` cap-trim. A
    /// flush captures it before `await`ing the transport and refuses to
    /// `removeFirst` if it changed (see `dropFromHead`).
    private var queueGeneration = 0

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
            queueGeneration &+= 1   // the head just moved; invalidate any in-flight drop
        }
        queueStore.save(state)

        // Size trigger (spec 5b): once a whole batch has accumulated, try to
        // send it now rather than waiting for the next foreground. The detached
        // flush is re-entrancy-guarded and back-off-gated; the extra conditions
        // here just keep it from spawning a Task that would immediately no-op
        // (queue saturated at cap, or a back-off window still open).
        if state.pending.count >= config.batchSize,
           state.pending.count % config.batchSize == 0,
           !isFlushing,
           now() >= nextAttemptAt {
            Task { await self.flush() }
        }
    }

    /// Drain the queue: send batches back to back until it is empty or a send
    /// fails (which opens a back-off window). Re-entrancy-guarded — a second
    /// call while one is in flight is a no-op, so wiring this to both
    /// `scenePhase` and a timer cannot double-send or drop unsent events.
    public func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        while !state.pending.isEmpty, now() >= nextAttemptAt {
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

            let generation = queueGeneration   // capture before the await
            do {
                try await transport.send(body)
                dropFromHead(batch, generation: generation)   // delivered
                failureCount = 0
                nextAttemptAt = .distantPast
            } catch TelemetryTransportError.permanent(_) {
                // A permanent rejection: the endpoint will never accept this
                // batch. Dropping it is progress just like a successful send —
                // clear the transient-failure state too, so a later batch is
                // not given up on early on a `failureCount` that belonged to
                // this one, then keep draining the rest of the queue.
                dropFromHead(batch, generation: generation)
                failureCount = 0
                nextAttemptAt = .distantPast
            } catch {
                registerFailure()
                if failureCount >= config.maxConsecutiveFailures {
                    // Unclassified, but failing over and over — drop the head
                    // so events behind it can still get out, clear the back-off
                    // so the loop keeps draining the rest of the queue.
                    dropFromHead(batch, generation: generation)
                    failureCount = 0
                    nextAttemptAt = .distantPast
                    continue
                }
                return // transient: stop draining; the back-off window gates the next flush
            }
        }
    }

    /// Remove `batch` from the head of the queue — but only if the queue was
    /// not structurally changed while the send was in flight. `discardPending()`
    /// (opt-out) and the `record(_:)` cap-trim both move or clear the head and
    /// bump `queueGeneration`; a blind `removeFirst` then trims unsent events,
    /// or traps on an emptied queue.
    private func dropFromHead(_ batch: [QueuedEvent], generation: Int) {
        guard generation == queueGeneration else { return }
        state.pending.removeFirst(batch.count)
        queueStore.save(state)
    }

    /// Opt-out: forget every queued event and close any back-off window. The
    /// install id survives so a later opt-in is still one anonymous identity.
    public func discardPending() {
        state.pending.removeAll()
        failureCount = 0
        nextAttemptAt = .distantPast
        queueGeneration &+= 1   // any in-flight send must not drop a re-recorded batch
        queueStore.save(state)
    }

    private func registerFailure() {
        failureCount += 1
        let exponent = Double(failureCount - 1)
        let delay = min(config.baseRetryDelay * pow(2, exponent), config.maxRetryDelay)
        nextAttemptAt = now().addingTimeInterval(delay)
    }
}
