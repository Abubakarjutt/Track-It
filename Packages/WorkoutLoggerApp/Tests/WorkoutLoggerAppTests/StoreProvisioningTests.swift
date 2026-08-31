import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("StoreProvisioning")
struct StoreProvisioningTests {

    @Test("a writable URL yields a ready, working container")
    func writableIsReady() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "trackit-test-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let availability = provisionStore(onDiskURL: url)
        #expect(availability.isDegraded == false)

        // the container is usable
        let context = ModelContext(availability.container)
        context.insert(WorkoutRecord(
            startedAt: Date(timeIntervalSince1970: 0), endedAt: nil, payload: Data("{}".utf8)
        ))
        try context.save()
        let count = try context.fetchCount(FetchDescriptor<WorkoutRecord>())
        #expect(count == 1)
    }

    @Test("a corrupt store file degrades to a working in-memory container instead of crashing")
    func corruptStoreDegrades() throws {
        // A file that exists but is not a SQLite database — the realistic
        // "unreadable store" the degraded path exists for.
        //
        // NOTE: SwiftData/CoreData logs its own store-load-failure diagnostics to
        // stderr here ("...couldn't be opened because it isn't in the correct
        // format"). That is expected Apple-framework output for the failure this
        // test deliberately provokes — there is no public API to silence it — and
        // it does not indicate a problem: `provisionStore` catches the Swift
        // error and returns `.degraded`, which is exactly what we assert.
        let url = FileManager.default.temporaryDirectory
            .appending(path: "trackit-corrupt-\(UUID().uuidString).store")
        try Data("this is not a database".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let availability = provisionStore(onDiskURL: url)
        #expect(availability.isDegraded == true)

        let context = ModelContext(availability.container)
        context.insert(WorkoutRecord(
            startedAt: Date(timeIntervalSince1970: 0), endedAt: nil, payload: Data("{}".utf8)
        ))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<WorkoutRecord>()) == 1)
    }
}
