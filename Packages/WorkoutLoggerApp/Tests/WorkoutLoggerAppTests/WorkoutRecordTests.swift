import Testing
import SwiftData
import Foundation
@testable import WorkoutLoggerApp

@Suite("WorkoutRecord persistence")
@MainActor
struct WorkoutRecordTests {

    @Test("a record inserts into an in-memory store and reads back")
    func insertAndFetch() throws {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let started = Date(timeIntervalSince1970: 1_000)

        context.insert(WorkoutRecord(startedAt: started, endedAt: nil, payload: Data([1, 2, 3])))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<WorkoutRecord>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.startedAt == started)
        #expect(fetched.first?.endedAt == nil)
        #expect(fetched.first?.payload == Data([1, 2, 3]))
    }
}
