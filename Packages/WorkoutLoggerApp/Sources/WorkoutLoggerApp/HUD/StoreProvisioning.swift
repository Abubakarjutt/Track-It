import Foundation
import SwiftData
import WorkoutLoggerCore

/// The persistence store the app came up with at launch.
public enum StoreAvailability {
    /// The on-disk store opened normally.
    case ready(ModelContainer)
    /// The on-disk store could not be opened (corrupt / unreadable); this is an
    /// in-memory fallback so the current workout still logs. History is not
    /// available and the UI should say so.
    case degraded(ModelContainer)

    public var container: ModelContainer {
        switch self {
        case .ready(let container), .degraded(let container): return container
        }
    }

    public var isDegraded: Bool {
        if case .degraded = self { return true }
        return false
    }
}

/// Opens the on-disk `WorkoutRecord` store, or — if that throws — an in-memory
/// container flagged `.degraded`. An in-memory container that itself cannot be
/// created is unrecoverable and traps (there is nowhere left to write).
/// `cloudKitContainerIdentifier` defaults to `nil` (no CloudKit mirroring) so
/// every existing call site, including package tests with no iCloud
/// entitlement, is unaffected; only `TrackitApp.init()` passes a real one.
public func provisionStore(
    onDiskURL: URL, cloudKitContainerIdentifier: String? = nil
) -> StoreAvailability {
    let schema = Schema([WorkoutRecord.self, ExerciseRecord.self, SyncedWorkoutRecord.self])
    let cloudKitDatabase: ModelConfiguration.CloudKitDatabase =
        cloudKitContainerIdentifier.map { .private($0) } ?? .none
    do {
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, url: onDiskURL, cloudKitDatabase: cloudKitDatabase
            )]
        )
        return .ready(container)
    } catch {
        // The degraded fallback is in-memory-only and CloudKit mirroring
        // requires a persistent store — this path already means "no
        // history available", so it stays cloud-free regardless of the
        // caller's identifier.
        let fallback = try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return .degraded(fallback)
    }
}
