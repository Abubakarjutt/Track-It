import Foundation
import WorkoutLoggerApp

/// `TelemetryQueueStore` backed by one JSON file in Application Support.
/// Written on every `record` so the queue survives a relaunch; a missing or
/// unreadable file is a fresh state (mints a new install id on next load).
final class FileTelemetryQueueStore: TelemetryQueueStore {
    private let url: URL

    init(url: URL = URL.applicationSupportDirectory.appending(path: "telemetry-queue.json")) {
        self.url = url
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
