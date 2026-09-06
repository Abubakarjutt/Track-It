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
}
