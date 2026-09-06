import Testing
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("Telemetry recorder")
@MainActor
struct TelemetryRecorderTests {

    private func makeRecorder(
        sink: CaptureTelemetrySink = CaptureTelemetrySink(),
        enabled: Bool = false
     ) -> (TelemetryRecorder, CaptureTelemetrySink, InMemorySettingsStore) {
        let settings = InMemorySettingsStore(analyticsEnabled: enabled)
        let recorder = TelemetryRecorder(sink: sink, settings: settings)
        return (recorder, sink, settings)
     }

     @Test("nothing is recorded when analytics is off")
    func silentWhenOff() {
        let (recorder, sink, _) = makeRecorder(enabled: false)
        recorder.record(.workoutStarted)
        recorder.record(.setLogged)
        #expect(sink.events.isEmpty)
       }

     @Test("each event is forwarded, in order, when analytics is on")
    func forwardsWhenOn() {
        let (recorder, sink, _) = makeRecorder(enabled: true)
        recorder.record(.workoutStarted)
        recorder.record(.setLogged)
        recorder.record(.parseFailed)
        #expect(sink.events == [.workoutStarted, .setLogged, .parseFailed])
       }

     @Test("turning analytics off stops delivery immediately")
    func turningOffStopsDelivery() {
        let (recorder, sink, _) = makeRecorder(enabled: true)
        recorder.record(.workoutStarted)
        recorder.setEnabled(false)
        recorder.record(.setLogged)
        #expect(sink.events == [.workoutStarted])
       }

     @Test("enabling records the flag and resumes delivery")
    func enablingResumesDelivery() {
        let (recorder, sink, settings) = makeRecorder(enabled: false)
        recorder.setEnabled(true)
        #expect(settings.analyticsEnabled)
        recorder.record(.workoutCompleted(totalSetCount: 10, workingSetCount: 8, duration: .thirtyToFiftyMinutes))
        #expect(sink.events.count == 1)
       }

     @Test("a completed-workout event carries only counts and a coarse bucket")
    func completedEventIsContentFree() async throws {
        let bench = Exercise(name: "Bench Press")
        let ended = Workout(
            entries: [Entry(
                exercise: bench,
                sets: [
                    LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                               loadKilograms: 100, reps: 5, loggedAt: Date(timeIntervalSince1970: 1)),
                    LoggedSet(loadType: .external, effort: .reps, role: .warmup, grouping: .straight,
                               loadKilograms: 40, reps: 10, loggedAt: Date(timeIntervalSince1970: 2)),
                 ]
              )],
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 40 * 60) // 40 min -> thirtyToFiftyMinutes
         )
        let expected = TelemetryEvent.workoutCompleted(
            totalSetCount: 2, workingSetCount: 1, duration: .thirtyToFiftyMinutes
         )
        #expect(WorkoutSessionModel.completedEvent(for: ended) == expected)
       }

     @Test("a workout that never ended buckets as under thirty minutes")
    func unfinishedWorkoutBucketsLow() {
        let open = Workout(
            entries: [],
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: nil
         )
        #expect(TelemetryRecorder.durationBucket(of: open) == .underThirtyMinutes)
       }

     @Test("the three duration buckets split at thirty and fifty minutes")
    func durationBucketBoundaries() {
        func bucket(_ minutes: Double) -> WorkoutDurationBucket {
            TelemetryRecorder.durationBucket(of: Workout(
                entries: [],
                startedAt: Date(timeIntervalSince1970: 0),
                endedAt: Date(timeIntervalSince1970: minutes * 60)
             ))
         }
        #expect(bucket(0) == .underThirtyMinutes)
        #expect(bucket(29.9) == .underThirtyMinutes)
        #expect(bucket(30) == .thirtyToFiftyMinutes)
        #expect(bucket(50) == .thirtyToFiftyMinutes)
        #expect(bucket(50.1) == .overFiftyMinutes)
       }
}
