import Foundation
import WorkoutLoggerApp

/// `TelemetryQueueStore` backed by one JSON file in Application Support.
/// Written on every `record` so the queue survives a relaunch; a missing or
/// unreadable file is a fresh state (mints a new install id on next load).
final class FileTelemetryQueueStore: TelemetryQueueStore {
    private let url: URL

    init(url: URL = URL.applicationSupportDirectory.appending(path: "telemetry-queue.json")) {
        self.url = url

        let directory = url.deletingLastPathComponent()

        // Application Support is not guaranteed to exist on a first launch, and
        // `Data.write` will not create it — make it now, so `save` can't
        // silently drop the queue on the floor.
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        // Legacy cleanup: the pre-uploader sink wrote `telemetry.json` beside
        // this file. It is dead since the switch to the queue store — remove the
        // orphan so it doesn't linger on devices upgraded across the rename.
        // Cheap enough to re-check every launch; the `fileExists` guard means it
        // does real work only once, on the first launch after the upgrade.
        let legacySinkFile = directory.appending(path: "telemetry.json")
        if FileManager.default.fileExists(atPath: legacySinkFile.path) {
            try? FileManager.default.removeItem(at: legacySinkFile)
        }
    }

    func load() -> TelemetryQueueState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(TelemetryQueueState.self, from: data)
        else { return TelemetryQueueState() }
        return state
    }

    func save(_ state: TelemetryQueueState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
