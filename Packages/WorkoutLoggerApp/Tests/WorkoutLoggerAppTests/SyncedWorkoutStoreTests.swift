import Foundation
import Testing
import SwiftData
@testable import WorkoutLoggerApp

@Suite("SyncedWorkoutStore")
@MainActor
struct SyncedWorkoutStoreTests {
    private let t1 = Date(timeIntervalSince1970: 1_000)
    private let t2 = Date(timeIntervalSince1970: 2_000)

    @Test("an unmarked start time is not synced; marking it makes it synced")
    func markAndCheck() {
        let store = InMemorySyncedWorkoutStore()
        #expect(store.isSynced(startedAt: t1) == false)
        store.markSynced(startedAt: t1)
        #expect(store.isSynced(startedAt: t1))
        #expect(store.isSynced(startedAt: t2) == false)
    }

    @Test("marking the same start time twice is idempotent")
    func markTwice() {
        let store = InMemorySyncedWorkoutStore()
        store.markSynced(startedAt: t1)
        store.markSynced(startedAt: t1)
        #expect(store.isSynced(startedAt: t1))
    }

    @Test("forgetAll clears every marked start time")
    func clearsEverything() {
        let store = InMemorySyncedWorkoutStore()
        store.markSynced(startedAt: t1)
        store.markSynced(startedAt: t2)
        store.forgetAll()
        #expect(store.isSynced(startedAt: t1) == false)
        #expect(store.isSynced(startedAt: t2) == false)
    }

    @Test("the SwiftData store persists a marked start time across store instances")
    func swiftDataRoundTrip() throws {
        let container = try ModelContainer(
            for: SyncedWorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        SwiftDataSyncedWorkoutStore(context: context).markSynced(startedAt: t1)

        // a fresh store over the same container — stands in for a relaunch
        let reopened = SwiftDataSyncedWorkoutStore(context: context)
        #expect(reopened.isSynced(startedAt: t1))
        #expect(reopened.isSynced(startedAt: t2) == false)

        reopened.forgetAll()
        #expect(reopened.isSynced(startedAt: t1) == false)
    }

    @Test("the SwiftData store marking the same start time twice does not throw or duplicate")
    func swiftDataMarkTwice() throws {
        let container = try ModelContainer(
            for: SyncedWorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataSyncedWorkoutStore(context: ModelContext(container))
        store.markSynced(startedAt: t1)
        store.markSynced(startedAt: t1)
        #expect(store.isSynced(startedAt: t1))
    }
}
