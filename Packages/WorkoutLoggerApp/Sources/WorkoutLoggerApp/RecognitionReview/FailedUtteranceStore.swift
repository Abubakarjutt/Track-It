import Foundation

/// The local queue of failed-utterance transcripts a lifter may submit to help
/// fix recognition. Capture only ever stores transcript text (never audio or
/// workout content). A phrase leaves the device only on an explicit `submit`,
/// which the real `System` implementation (in `App/`) uploads; here it is a
/// seam a capturing fake can assert on. Submitting or discarding removes the
/// item from the queue either way.
public protocol FailedUtteranceStore: AnyObject {
    /// Transcript text currently waiting for a decision, oldest first.
    var pending: [PendingUtterance] { get }
    /// Add a failed utterance's transcript to the queue. A no-op when the
    /// caller's opt-in is off, so the model gates this.
    func capture(_ transcript: String)
    /// Hand these transcripts to the upload and drop them from the queue.
    func submit(_ utterances: [PendingUtterance])
    /// Drop these transcripts from the queue without uploading.
    func discard(_ utterances: [PendingUtterance])
    /// Empty the queue — used when the lifter opts out.
    func clearAll()
}

/// The default store: a queue that is never fed. Used when recognition review is
/// not wired, so the logging loop has no dependency on the queue.
final class NoopFailedUtteranceStore: FailedUtteranceStore {
    public init() {}
    public var pending: [PendingUtterance] { [] }
    public func capture(_ transcript: String) {}
    public func submit(_ utterances: [PendingUtterance]) {}
    public func discard(_ utterances: [PendingUtterance]) {}
    public func clearAll() {}
}
