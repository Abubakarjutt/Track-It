import Foundation
import WorkoutLoggerApp

/// `FailedUtteranceStore` over a local, on-disk queue. A phrase leaves the
/// device only through `submit`, which is the documented upload point a backend
/// fills in — by default it records the submission locally so the lifter has a
/// receipt, and never auto-sends. Capture stores transcript text only (the
/// `PendingUtterance` struct carries nothing else). This adapter is persistence
/// and wiring with no branching logic; it is not unit-tested, its behaviour
/// covered by the model over the capturing fake.
@MainActor
final class SystemFailedUtteranceStore: FailedUtteranceStore {
    private struct Stored: Codable {
        let id: String
        let transcript: String
        let capturedAt: Date
     }

    private let queueURL: URL
    private let submissionsURL: URL
    private var queue: [Stored]
     /// Phrases the lifter has chosen to submit — a local receipt of what left
        /// the device, kept so a future transport has something to retry.
    private var submissions: [Stored]

    init() {
        let base = URL.applicationSupportDirectory
        self.queueURL = base.appending(path: "recognition-review.json")
        self.submissionsURL = base.appending(path: "recognition-submissions.json")
        self.queue = Self.load(from: queueURL)
        self.submissions = Self.load(from: submissionsURL)
       }

    var pending: [PendingUtterance] {
        queue.map { PendingUtterance(id: $0.id, transcript: $0.transcript, capturedAt: $0.capturedAt) }
     }

    func capture(_ transcript: String) {
        queue.append(Stored(id: UUID().uuidString, transcript: transcript, capturedAt: Date()))
        persistQueue()
     }

    func submit(_ utterances: [PendingUtterance]) {
        let ids = Set(utterances.map(\.id))
        submissions.append(contentsOf: utterances.map {
            Stored(id: $0.id, transcript: $0.transcript, capturedAt: $0.capturedAt)
          })
        queue.removeAll { ids.contains($0.id) }
        persistQueue()
        persistSubmissions()
     }

    func discard(_ utterances: [PendingUtterance]) {
        let ids = Set(utterances.map(\.id))
        queue.removeAll { ids.contains($0.id) }
        persistQueue()
     }

    func clearAll() {
        queue.removeAll()
        persistQueue()
       }

    private static func load(from url: URL) -> [Stored] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Stored].self, from: data)) ?? []
       }

    private func persistQueue() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        try? data.write(to: queueURL, options: .atomic)
       }

    private func persistSubmissions() {
        guard let data = try? JSONEncoder().encode(submissions) else { return }
        try? data.write(to: submissionsURL, options: .atomic)
       }
 }
