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
}
