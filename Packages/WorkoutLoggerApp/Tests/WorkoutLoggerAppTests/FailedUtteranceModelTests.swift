import Testing
import Foundation
@testable import WorkoutLoggerApp

@Suite("FailedUtteranceModel")
@MainActor
struct FailedUtteranceModelTests {

    private func makeModel(
        store: FakeFailedUtteranceStore = FakeFailedUtteranceStore(),
        enabled: Bool = false
    ) -> (FailedUtteranceModel, FakeFailedUtteranceStore, InMemorySettingsStore) {
        let settings = InMemorySettingsStore(recognitionReviewEnabled: enabled)
        let model = FailedUtteranceModel(store: store, settings: settings)
        return (model, store, settings)
    }

     @Test("capture is a no-op when collection is off")
    func captureNoOpWhenOff() {
        let (model, store, _) = makeModel(enabled: false)
        model.capture("flurbo")
        #expect(store.queue.isEmpty)
        #expect(model.pendingCount == 0)
        }

     @Test("an unresolved utterance enqueues only its transcript when collection is on")
    func captureEnqueuesTranscriptWhenOn() {
        let (model, store, _) = makeModel(enabled: true)
        model.capture("flurbo 225 for 5")
        #expect(store.queue.count == 1)
        #expect(store.queue.first?.transcript == "flurbo 225 for 5")
        #expect(model.pendingCount == 1)
        }

      @Test("submit removes the named items and records them for upload")
    func submitRemovesAndRecords() {
        let (model, store, _) = makeModel(enabled: true)
        model.capture("alpha")
        model.capture("beta")
        let both = model.pending
         #expect(model.pendingCount == 2)

        model.submit(both)

         #expect(store.submitted.count == 2)
          #expect(model.pendingCount == 0)
        }

      @Test("discard removes the named items without submitting")
    func discardRemovesWithoutSubmitting() {
        let (model, store, _) = makeModel(enabled: true)
        model.capture("alpha")
        model.capture("beta")
        let beta = model.pending.filter { $0.transcript == "beta" }

        model.discard(beta)

         #expect(store.submitted.isEmpty)
         #expect(store.discardCount == 1)
          #expect(model.pending.map(\.transcript) == ["alpha"])
         }

     @Test("a pre-existing queue can be cleared even when collection is off")
    func preExistingQueueCanBeClearedWhenOff() {
        let store = FakeFailedUtteranceStore()
        store.seed([
            PendingUtterance(transcript: "old one"),
            PendingUtterance(transcript: "another"),
         ])
        let (model, _, _) = makeModel(store: store, enabled: false)
         #expect(model.pendingCount == 2)

        model.clearAll()

        #expect(store.clearedCount == 1)
        #expect(model.pendingCount == 0)
        }

     @Test("turning collection off stops capture but leaves the queue intact")
    func turningOffStopsCaptureKeepsQueue() {
        let (model, store, settings) = makeModel(enabled: true)
        model.capture("first")
        model.setEnabled(false)
         #expect(settings.recognitionReviewEnabled == false)
        model.capture("second")
         #expect(store.queue.map(\.transcript) == ["first"])
        }

       @Test("a captured utterance carries its transcript and a capture time, nothing else")
    func utteranceCarriesOnlyTranscriptAndTime() {
        let now = Date(timeIntervalSince1970: 42_000)
        let (model, _, _) = makeModel(enabled: true)
        let item = PendingUtterance(transcript: "squats 100 for 5", capturedAt: now)
         #expect(item.transcript == "squats 100 for 5")
         #expect(item.capturedAt == now)
         #expect(item.id.count > 0)
          // The model enqueues a freshly captured phrase the same way.
        model.capture("flurbo")
         #expect(model.pending.last?.transcript == "flurbo")
          }
}
