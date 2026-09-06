import Testing
import Foundation
@testable import WorkoutLoggerApp

@Suite("Telemetry uploader")
@MainActor
struct TelemetryUploaderTests {

    @Test("queue state round-trips through Codable")
    func queueStateRoundTrips() throws {
        let state = TelemetryQueueState(
            installID: "abc",
            pending: [QueuedEvent(
                event: TelemetryPayloadCodec.payload(for: .setLogged),
                recordedAt: Date(timeIntervalSince1970: 10)
            )]
        )
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(TelemetryQueueState.self, from: data) == state)
    }

    @Test("the in-memory queue store returns what was last saved")
    func inMemoryStoreRoundTrips() {
        let store = InMemoryTelemetryQueueStore()
        var state = store.load()
        state.pending.append(QueuedEvent(
            event: TelemetryPayloadCodec.payload(for: .workoutStarted),
            recordedAt: Date(timeIntervalSince1970: 1)
        ))
        store.save(state)
        #expect(store.load() == state)
    }

    @Test("the spy transport records bodies and can be told to fail")
    func spyTransport() async throws {
        let spy = SpyTelemetryTransport()
        try await spy.send(Data([1, 2, 3]))
        #expect(spy.sentBodies == [Data([1, 2, 3])])

        struct Boom: Error {}
        spy.failWith = Boom()
        await #expect(throws: Boom.self) { try await spy.send(Data()) }
        #expect(spy.sendCount == 2)
    }

    private func makeUploader(
        transport: SpyTelemetryTransport = SpyTelemetryTransport(),
        store: InMemoryTelemetryQueueStore = InMemoryTelemetryQueueStore(),
        config: TelemetryUploader.Config = .init(),
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }
    ) -> (TelemetryUploader, SpyTelemetryTransport, InMemoryTelemetryQueueStore) {
        (TelemetryUploader(transport: transport, queueStore: store, config: config, now: now),
         transport, store)
    }

    @Test("record enqueues and persists, and never sends")
    func recordEnqueuesWithoutSending() {
        let (uploader, transport, store) = makeUploader()
        uploader.record(.setLogged)
        uploader.record(.parseFailed)
        #expect(uploader.pendingCount == 2)
        #expect(store.load().pending.count == 2)
        #expect(transport.sendCount == 0)
    }

    @Test("a fresh uploader mints one stable install id and persists it")
    func mintsInstallID() {
        let (uploader, _, store) = makeUploader()
        let id = uploader.installID
        #expect(!id.isEmpty)
        #expect(store.load().installID == id)
    }

    @Test("an uploader resumes the persisted queue and install id")
    func resumesPersistedState() {
        let seeded = TelemetryQueueState(
            installID: "kept-id",
            pending: [QueuedEvent(event: TelemetryPayloadCodec.payload(for: .setLogged),
                                  recordedAt: Date(timeIntervalSince1970: 5))]
        )
        let (uploader, _, _) = makeUploader(store: InMemoryTelemetryQueueStore(seeded))
        #expect(uploader.installID == "kept-id")
        #expect(uploader.pendingCount == 1)
    }

    @Test("the queue is capped at maxQueuedEvents, dropping the oldest")
    func queueCap() {
        let (uploader, _, store) = makeUploader(config: .init(batchSize: 100, maxQueuedEvents: 3))
        for _ in 0..<5 { uploader.record(.setLogged) }
        for _ in 0..<2 { uploader.record(.parseFailed) }
        #expect(uploader.pendingCount == 3)
        // the three survivors are the newest: parseFailed, parseFailed, setLogged
        let kinds = store.load().pending.map(\.event.kind)
        #expect(kinds == ["set_logged", "parse_failed", "parse_failed"])
    }

    @Test("flush sends one batch as a TelemetryPayload and clears the sent events")
    func flushSendsBatch() async throws {
        let (uploader, transport, store) = makeUploader(config: .init(batchSize: 2))
        uploader.record(.workoutStarted)
        uploader.record(.setLogged)
        uploader.record(.parseFailed)

        await uploader.flush()

        #expect(transport.sentBodies.count == 1)
        let payload = try JSONDecoder().decode(TelemetryPayload.self, from: transport.sentBodies[0])
        #expect(payload.installID == uploader.installID)
        #expect(payload.events.map(\.kind) == ["workout_started", "set_logged"])
        #expect(uploader.pendingCount == 1)             // parseFailed still queued
        #expect(store.load().pending.map(\.event.kind) == ["parse_failed"])
    }

    @Test("flush with an empty queue is a no-op")
    func flushEmptyIsNoop() async {
        let (uploader, transport, _) = makeUploader()
        await uploader.flush()
        #expect(transport.sendCount == 0)
    }

    @Test("a second flush sends the next batch")
    func flushDrainsAcrossCalls() async {
        let (uploader, transport, _) = makeUploader(config: .init(batchSize: 1))
        uploader.record(.setLogged)
        uploader.record(.parseFailed)
        await uploader.flush()
        await uploader.flush()
        #expect(transport.sentBodies.count == 2)
        #expect(uploader.pendingCount == 0)
    }

    @Test("a failed send keeps the batch and opens a back-off window")
    func failureBacksOff() async {
        var clock = Date(timeIntervalSince1970: 0)
        let transport = SpyTelemetryTransport()
        struct Down: Error {}
        transport.failWith = Down()
        let (uploader, _, store) = makeUploader(
            transport: transport,
            config: .init(batchSize: 10, baseRetryDelay: 60, maxRetryDelay: 3600),
            now: { clock }
        )
        uploader.record(.setLogged)

        await uploader.flush()                       // fails, failureCount = 1
        #expect(uploader.pendingCount == 1)
        #expect(store.load().pending.count == 1)

        clock = Date(timeIntervalSince1970: 59)       // still inside the 60 s window
        transport.failWith = nil
        await uploader.flush()
        #expect(transport.sentBodies.isEmpty)         // no attempt yet

        clock = Date(timeIntervalSince1970: 61)       // window elapsed
        await uploader.flush()
        #expect(transport.sentBodies.count == 1)
        #expect(uploader.pendingCount == 0)
    }

    @Test("back-off doubles each consecutive failure up to the ceiling")
    func backoffDoublesToCeiling() async {
        var clock = Date(timeIntervalSince1970: 0)
        let transport = SpyTelemetryTransport()
        struct Down: Error {}
        transport.failWith = Down()
        let (uploader, _, _) = makeUploader(
            transport: transport,
            config: .init(batchSize: 10, baseRetryDelay: 10, maxRetryDelay: 25),
            now: { clock }
        )
        uploader.record(.setLogged)

        await uploader.flush()                         // fail 1 -> next window 10 s
        clock = Date(timeIntervalSince1970: 11)
        await uploader.flush()                         // fail 2 -> next window 20 s (from t=11 -> 31)
        clock = Date(timeIntervalSince1970: 25)
        await uploader.flush()
        #expect(transport.sendCount == 2)             // 25 < 31, no third attempt
        clock = Date(timeIntervalSince1970: 32)
        await uploader.flush()                         // fail 3 -> ceiling 25 s
        #expect(transport.sendCount == 3)
    }
}
