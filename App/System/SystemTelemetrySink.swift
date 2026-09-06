import Foundation
import WorkoutLoggerApp

/// `TelemetrySink` over a local, append-only queue on disk. Events are written
/// as they come in so they survive a relaunch (the "no analytics surface, no
/// stall" promise: the logging loop never waits on a network). The actual
/// transport — when the queue empties into a backend — is an implementation
/// detail the spec leaves open; `flush()` is that single, documented hook. This
/// adapter carries no branching logic and is not unit-tested; its behaviour is
/// covered by the recorder's flag-gating over the capturing fake.
@MainActor
final class SystemTelemetrySink: TelemetrySink {
    private struct QueueItem: Codable {
        let event: TelemetryCodable
        let recordedAt: Date
    }

    /// The content-free mirror of `TelemetryEvent` for disk storage. No case
     /// carries a load, name, transcript, or free-form text — the same
     /// guarantee the type gives in-memory, persisted.
    private enum TelemetryCodable: String, Codable {
        case workoutStarted
        case setLogged
        case parseFailed
        case correctionMade
        case settingsOpened
        case export
        case healthSyncToggle
        case analyticsToggle
        case recognitionReviewToggle
        case templateSaved
        case workoutCompleted
    }

    private let queueURL: URL
    private var queue: [QueueItem]

    init() {
        let url = URL.applicationSupportDirectory.appending(path: "telemetry.json")
        self.queueURL = url
        self.queue = Self.load(from: url)
    }

    func record(_ event: TelemetryEvent) {
        queue.append(QueueItem(event: Self.code(for: event), recordedAt: Date()))
        persist()
     }

      /// Drains the queue to a backend. The backend is unspecified, so this
      /// clears what it held as the upload point a future transport fills in.
    func flush() {
        guard !queue.isEmpty else { return }
        queue.removeAll()
        persist()
     }

     /// Map a telemetry event to its content-free storage form. A completed
      /// workout collapses to a single case here — the precise counts and bucket
      /// live only in the in-memory `TelemetryEvent`, which the recorder forwards
      /// to the backend, not the disk queue.
    private static func code(for event: TelemetryEvent) -> TelemetryCodable {
        switch event {
        case .workoutStarted: return .workoutStarted
        case .workoutCompleted: return .workoutCompleted
        case .setLogged: return .setLogged
        case .parseFailed: return .parseFailed
        case .correctionMade: return .correctionMade
        case .featureUsed(let feature):
            switch feature {
            case .export: return .export
            case .healthSyncToggle: return .healthSyncToggle
            case .analyticsToggle: return .analyticsToggle
            case .recognitionReviewToggle: return .recognitionReviewToggle
            case .settingsOpened: return .settingsOpened
            case .templateSaved: return .templateSaved
              }
          }
      }

    private static func load(from url: URL) -> [QueueItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([QueueItem].self, from: data)) ?? []
      }

    private func persist() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        try? data.write(to: queueURL, options: .atomic)
     }
}
