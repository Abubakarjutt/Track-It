import Foundation
import Observation

/// Owns the failed-utterance review queue and its opt-in. Capture is a no-op
/// when collection is off, and a phrase leaves the device only on an explicit
/// per-item submit. The core logging loop only ever calls `capture(_:)`, which
/// is gated here, so a failure can never enqueue without the flag.
@MainActor
@Observable
public final class FailedUtteranceModel {
    @ObservationIgnored private let store: FailedUtteranceStore
    @ObservationIgnored private let settings: SettingsStore

    /// Mirrors `settings.recognitionReviewEnabled` so a view re-renders on toggle.
    public private(set) var isEnabled: Bool
    /// The phrases awaiting a decision, mirrored from the store so the
     /// "Review N phrases" row re-renders when the queue changes.
    public private(set) var pending: [PendingUtterance]

    public init(store: FailedUtteranceStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        self.isEnabled = settings.recognitionReviewEnabled
        self.pending = store.pending
     }

     /// Queue a failed utterance's transcript when collection is on. A no-op
     /// when off, so opting out stops the queue growing.
    public func capture(_ transcript: String) {
        guard isEnabled else { return }
        store.capture(transcript)
        refreshPending()
     }

     /// The number of phrases waiting — the count the "Review N phrases" row shows.
    public var pendingCount: Int { pending.count }

     /// Submit chosen phrases for upload; they leave the queue. The count and
     /// list update for the caller's convenience.
    public func submit(_ utterances: [PendingUtterance]) {
        store.submit(utterances)
        refreshPending()
     }

     /// Discard chosen phrases without uploading; they leave the queue.
    public func discard(_ utterances: [PendingUtterance]) {
        store.discard(utterances)
        refreshPending()
     }

     /// Flip the opt-in. Disabling stops capture; the queue can still be
     /// cleared or worked through, matching "opting out is complete".
    public func setEnabled(_ enabled: Bool) {
        settings.recognitionReviewEnabled = enabled
        isEnabled = enabled
     }

     /// Clear everything queued — used when the lifter opts out.
    public func clearAll() {
        store.clearAll()
        refreshPending()
     }

      /// Re-read the queue — call on Settings `.onAppear` so the
       /// "Review N phrases" row reflects phrases captured since the model was
       /// built.
    public func refreshPending() {
        pending = store.pending
      }
}
