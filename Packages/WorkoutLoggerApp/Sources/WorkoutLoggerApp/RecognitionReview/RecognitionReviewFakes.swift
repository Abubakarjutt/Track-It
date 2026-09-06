import Foundation

/// A `FailedUtteranceStore` for tests: an in-memory queue that records what it
/// was submitted, so a test can assert per-item submit/discard and that
/// capture respects the flag. HealthKit-free — the model seam is what the
/// tests cover, not the system store.
public final class FakeFailedUtteranceStore: FailedUtteranceStore {
    public private(set) var queue: [PendingUtterance] = []
    public private(set) var submitted: [PendingUtterance] = []
    public private(set) var discardCount = 0
    public private(set) var clearedCount = 0

    public init() {}

     /// Seed a pre-existing queue the model should be able to clear.
    public func seed(_ utterances: [PendingUtterance]) {
        queue.append(contentsOf: utterances)
     }

    public var pending: [PendingUtterance] { queue }

    public func capture(_ transcript: String) {
        queue.append(PendingUtterance(transcript: transcript))
     }

    public func submit(_ utterances: [PendingUtterance]) {
        submitted.append(contentsOf: utterances)
        let ids = Set(utterances.map(\.id))
        queue.removeAll { ids.contains($0.id) }
     }

    public func discard(_ utterances: [PendingUtterance]) {
        discardCount += 1
        let ids = Set(utterances.map(\.id))
        queue.removeAll { ids.contains($0.id) }
     }

    public func clearAll() {
        clearedCount += 1
        queue.removeAll()
     }
}
