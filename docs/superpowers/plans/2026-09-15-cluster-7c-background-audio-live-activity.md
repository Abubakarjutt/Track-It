# Cluster 7c — Background audio + Live Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **This run:** executed inline in-session by the authoring agent (full
> context already held; a fresh-subagent-per-task pipeline would duplicate
> the two-axis review this cluster gets at the end anyway).

**Goal:** A locked/backgrounded phone still lets one explicit earbud-button
press log a set (spoken back through a kept-alive audio session), still signals
rest completion (a new local notification, since none existed), and shows a
lock-screen + Dynamic Island Live Activity for the active workout.

**Architecture:** Two independent-but-coordinated deliverables. Deliverable 1
(background operation) is almost entirely an App-layer audio-session +
`Info.plist` change plus one new small App-layer type
(`SystemRestNotificationScheduler`) behind a new `WorkoutLoggerApp` protocol —
`RestTimer`/`WorkoutEngine` already store rest as a timestamp, so no Core
change and no live ticking dependency. Deliverable 2 adds a new WidgetKit
extension target (`TrackitWidgets`) and one new App-layer controller
(`LiveActivityController`) that reads a small `WorkoutLoggerApp` projection
type (`WorkoutActivityState`, primitives only — no `ActivityKit` import in the
package, since it doesn't build for macOS) and republishes it into
`ActivityKit`.

**Tech Stack:** Swift 6.0, SwiftUI, `AVFoundation`/`Speech` (existing),
`UserNotifications` (new), `ActivityKit` + `WidgetKit` (new, App/extension
only), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-11-cluster-7c-background-audio-live-activity.md`
(the resolved OPEN QUESTIONS section is authoritative scope — read it first).

## Global Constraints

- Explicit-press-only background trigger — **no continuous background
  listening** (spec OPEN QUESTION 2's resolution).
- No live background audio session for the rest timer itself — rest state is
  computed from `restStartedAt` + target, pure arithmetic against wall-clock
  `now()` (OPEN QUESTION 1).
- Live Activity updates are **local-only** (`Activity.update(...)` from the
  running app) — no push/APNs (OPEN QUESTION 3).
- Dynamic Island: minimal = a dot; compact = a mic glyph (idle/listening) or
  rest-seconds-remaining (resting), mutually exclusive; expanded = exercise
  name + last set + rest countdown (OPEN QUESTION 4).
- The Live Activity is **read-only** — no buttons, no App Intent target (OPEN
  QUESTION 7).
- `WorkoutLoggerCore` gets **no changes** in this plan. `WorkoutLoggerApp`
  gets primitives-only additions — nothing in that package may `import
  ActivityKit`/`UserNotifications`/`WidgetKit` (the package targets
  `.macOS(.v14)` too, per `Packages/WorkoutLoggerApp/Package.swift`, and none
  of those frameworks exist there).
- App-layer files are **not** compiled by `swift test` — verify them via
  `xcodegen generate && xcodebuild -project Trackit.xcodeproj -scheme Trackit
  -destination 'generic/platform=iOS Simulator' build` (must build BOTH the
  `Trackit` app target and the new `TrackitWidgets` extension target it
  embeds).
- Package suites: Core via `swift test`, App via `swift test --no-parallel`
  (the default parallel runner deadlocks the App suite on this machine).

---

### Task 1: `WorkoutSessionModel.activeEntry()` — extract the shared active-entry resolution

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift`
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/HUD/HUDProjection.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift`

**Interfaces:**
- Produces: `public func activeEntry() -> WorkoutEntry?` on `WorkoutSessionModel`
  — the entry `activeExerciseName` names (searching from the end, since a name
  can repeat across entries — a superset run), falling back to
  `workout?.entries.last`. Later tasks (`WorkoutActivityState`) call this
  instead of re-deriving the same resolution `HUDProjection.init(from:)`
  already has, so it isn't duplicated a second time.

`HUDProjection.init(from:)` currently has this inline (lines ~52-56):
```swift
let entries = model.workout?.entries
let entry = model.activeExerciseName
    .flatMap { name in entries?.last { $0.exercise.name == name } }
    ?? entries?.last
```

- [ ] **Step 1: Write the failing test** — add to `WorkoutSessionModelTests.swift`
  (near the other `activeExerciseName` tests):

```swift
@Test("activeEntry() resolves the entry activeExerciseName names, not always the last one added")
func activeEntryTracksActiveExerciseName() throws {
    let rig = try makeRig(script: [
        ["start workout"],
        ["bench 100 for 5"],
        ["squat 60 for 5"],
        ["bench"], // re-announce an earlier exercise — active moves back
    ])
    await say(rig); await say(rig); await say(rig); await say(rig)
    #expect(rig.model.activeEntry()?.exercise.name == "Bench Press")
}

@Test("activeEntry() is nil with no open workout")
func activeEntryNilWithNoWorkout() throws {
    let rig = try makeRig(script: [])
    #expect(rig.model.activeEntry() == nil)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test --no-parallel --filter WorkoutSessionModelTests`
Expected: FAIL — `value of type 'WorkoutSessionModel' has no member 'activeEntry'`

- [ ] **Step 3: Add `activeEntry()` and refactor `HUDProjection` to use it**

In `WorkoutSessionModel.swift`, add near `activeEntryIndex()` (the existing
private helper `editActiveSet`/`removeActiveSet` use, which does the same
name-based search but returns an index — `activeEntry()` is the public,
whole-entry sibling other App-layer code can call without reaching past the
model's private state):

```swift
/// The entry the next set will be logged against — the one
/// `activeExerciseName` names (searching from the end: a name can repeat
/// across entries, a superset run), falling back to the workout's last
/// entry. `nil` with no open workout. Shared by `HUDProjection` and the
/// Live Activity projection (cluster 7c) so the "not always the last entry"
/// rule lives in exactly one place.
public func activeEntry() -> WorkoutEntry? {
    let entries = workout?.entries
    return activeExerciseName
        .flatMap { name in entries?.last { $0.exercise.name == name } }
        ?? entries?.last
}
```

In `HUDProjection.swift`, replace the inline derivation:
```swift
@MainActor
public init(from model: WorkoutSessionModel) {
    let entry = model.activeEntry()
    let unit = model.displayUnit
    exerciseName = entry?.exercise.name ?? "No exercise yet"
    ...
```
(delete the now-unused `let entries = model.workout?.entries` line and the
inline `flatMap`/`??` — `entry` now comes straight from `model.activeEntry()`).

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --no-parallel --filter WorkoutSessionModelTests`
Expected: PASS. Also run the full App suite once to confirm the `HUDProjection`
refactor didn't change its behavior: `swift test --no-parallel` — expect the
same pass count as before this task, plus the 2 new tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift \
        Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/HUD/HUDProjection.swift \
        Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift
git commit -m "refactor(7c): extract WorkoutSessionModel.activeEntry(), reuse in HUDProjection"
```

---

### Task 2: `WorkoutSessionModel.restDeadline`

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift`

**Interfaces:**
- Consumes: existing `restStartedAt: Date?`, `restTargetSeconds: TimeInterval`.
- Produces: `public var restDeadline: Date? { get }` — later tasks (the
  notification scheduler wiring, `WorkoutActivityState`) read this instead of
  each re-deriving `startedAt + target`.

- [ ] **Step 1: Write the failing test**

```swift
@Test("restDeadline is restStartedAt + restTargetSeconds, computed with no ticking")
func restDeadlineIsPureArithmetic() throws {
    let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"]])
    await say(rig); await say(rig)
    let expected = rig.model.restStartedAt!.addingTimeInterval(rig.model.restTargetSeconds)
    #expect(rig.model.restDeadline == expected)
}

@Test("restDeadline is nil when no rest is running")
func restDeadlineNilWhenIdle() throws {
    let rig = try makeRig(script: [])
    #expect(rig.model.restDeadline == nil)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --no-parallel --filter WorkoutSessionModelTests`
Expected: FAIL — no member `restDeadline`.

- [ ] **Step 3: Implement**

Add next to `restTargetSeconds`'s declaration:

```swift
/// `restStartedAt + restTargetSeconds` — the wall-clock moment rest ends, or
/// `nil` when no rest is running. Pure derivation, no dependency on `tick()`
/// having run recently; used by anything that needs "when does rest end"
/// without polling (cluster 7c: the rest-completion local notification and
/// the Live Activity's self-rendering countdown).
public var restDeadline: Date? {
    restStartedAt.map { $0.addingTimeInterval(restTargetSeconds) }
}
```

- [ ] **Step 4: Run to verify it passes** — same filter as Step 2, expect PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift \
        Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift
git commit -m "feat(7c): add WorkoutSessionModel.restDeadline"
```

---

### Task 3: `RestNotificationScheduler` protocol + fake, wired into rest transitions

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/RestNotificationScheduler.swift`
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift`
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/Fakes.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift`

**Interfaces:**
- Produces:
  ```swift
  @MainActor
  public protocol RestNotificationScheduler {
      /// Replace any pending schedule with one firing at `deadline`.
      func schedule(deadline: Date)
      /// Clear a pending schedule, if any. Idempotent.
      func cancel()
  }
  ```
  and a no-op default conformer (`NoOpRestNotificationScheduler`), and
  `SpyRestNotificationScheduler` (test fake, records `scheduled: [Date]` and
  `cancelCount: Int`) in `Fakes.swift`.
- Consumes (later, Task 9): `App/System/SystemRestNotificationScheduler`
  will be the real conformer the composition root passes in.

Why a default parameter, not a required one like `haptics`/`readbackVoice`:
this dependency is policy on top of state the model already owns correctly
without it (unlike `TranscriptSource`, which the model cannot function
without at all) — same shape as `onWorkoutEnded`/`history`, which also
default to inert no-ops. A default avoids touching every existing
`WorkoutSessionModel(...)` call site across the test suite and
`TrackitApp.swift` for a dependency most of them don't care about.

- [ ] **Step 1: Write the failing tests**

```swift
@Test("starting rest schedules a notification at the rest deadline")
func startingRestSchedulesNotification() throws {
    let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"]])
    await say(rig); await say(rig)
    #expect(rig.restNotifications.scheduled == [rig.model.restDeadline!])
    #expect(rig.restNotifications.cancelCount == 0)
}

@Test("skipping rest cancels the scheduled notification")
func skippingRestCancelsNotification() throws {
    let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"], ["skip rest"]])
    await say(rig); await say(rig); await say(rig)
    #expect(rig.model.restStartedAt == nil)
    #expect(rig.restNotifications.cancelCount == 1)
}

@Test("a second rest period reschedules rather than stacking")
func secondRestReschedules() throws {
    let rig = try makeRig(script: [
        ["start workout"], ["bench 100 for 5"], ["bench 100 for 5"],
    ])
    await say(rig); await say(rig); await say(rig)
    #expect(rig.restNotifications.scheduled.count == 2)
    #expect(rig.restNotifications.scheduled.last == rig.model.restDeadline!)
}
```

Add `let restNotifications: SpyRestNotificationScheduler` to the private
`Rig` struct and to `makeRig`'s construction (passed as
`restNotifications: restNotifications` into `WorkoutSessionModel(...)`),
mirroring how `haptics`/`voice` are already threaded through.

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --no-parallel --filter WorkoutSessionModelTests`
Expected: FAIL — no such parameter/member.

- [ ] **Step 3: Implement**

`RestNotificationScheduler.swift`:
```swift
import Foundation

/// Schedules the "rest is over" signal for when the app can't rely on a live
/// `tick()` loop to notice — backgrounded or the screen locked (cluster 7c).
/// One outstanding schedule at a time: `schedule(deadline:)` implicitly
/// replaces whatever was pending; `cancel()` clears it without replacement.
@MainActor
public protocol RestNotificationScheduler {
    func schedule(deadline: Date)
    func cancel()
}

/// The default when no real scheduler is supplied — tests and any composition
/// root that doesn't care about the backgrounded case get inert no-ops rather
/// than a crash or an optional to unwrap everywhere.
public struct NoOpRestNotificationScheduler: RestNotificationScheduler {
    public init() {}
    public func schedule(deadline: Date) {}
    public func cancel() {}
}
```

In `Fakes.swift`, alongside `SpyHaptics`/`SpyReadbackVoice`:
```swift
public final class SpyRestNotificationScheduler: RestNotificationScheduler {
    public private(set) var scheduled: [Date] = []
    public private(set) var cancelCount = 0
    public init() {}
    public func schedule(deadline: Date) { scheduled.append(deadline) }
    public func cancel() { cancelCount += 1 }
}
```

In `WorkoutSessionModel.swift`:
1. Add the stored dependency next to `haptics`:
   ```swift
   @ObservationIgnored private let restNotifications: RestNotificationScheduler
   ```
2. Add the init parameter with a default, after `haptics`:
   ```swift
   restNotifications: RestNotificationScheduler = NoOpRestNotificationScheduler(),
   ```
   and `self.restNotifications = restNotifications` in the body.
3. In `syncFromEngine()`, diff the old value before overwriting it:
   ```swift
   private func syncFromEngine() {
       let previousRestStartedAt = restStartedAt
       workout = engine.workout
       personalRecords = engine.personalRecords
       restStartedAt = engine.restStartedAt
       restTargetSeconds = engine.currentRestTargetSeconds
       isRestTargetReached = engine.isRestTargetReached

       if restStartedAt != previousRestStartedAt {
           if let deadline = restDeadline {
               restNotifications.schedule(deadline: deadline)
           } else {
               restNotifications.cancel()
           }
       }
   }
   ```
   This single choke point already covers every rest transition in the
   codebase — `apply()` (voice commands `start rest`/`skip rest`, and a
   logged set restarting rest), `editActiveSet`/`removeActiveSet` (via
   `afterEngineEdit()`), `init()` and `resumePendingStaleWorkout()` (so a
   cold relaunch that resumes a workout with rest already running correctly
   reschedules — `previousRestStartedAt` is `nil` before the first
   `syncFromEngine()` call, so a non-nil resumed value is a real transition).
   Ending the workout already clears `restStartedAt` to `nil` via the
   engine's own `rest.skip()`, so no special-case is needed there — the
   `nil` branch fires for free.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --no-parallel --filter WorkoutSessionModelTests`, then the
full suite: `swift test --no-parallel`.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/RestNotificationScheduler.swift \
        Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift \
        Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/Fakes.swift \
        Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift
git commit -m "feat(7c): RestNotificationScheduler seam, wired to every rest transition"
```

---

### Task 4: `WorkoutActivityState` projection

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Activity/WorkoutActivityState.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutActivityStateTests.swift` (new file)

**Interfaces:**
- Consumes: `WorkoutSessionModel.hasActiveWorkout`, `.activeEntry()` (Task 1),
  `.restDeadline` (Task 2), `.isListening`.
- Produces:
  ```swift
  public struct WorkoutActivityState: Equatable, Sendable {
      public var exerciseName: String
      public var workingSetCount: Int
      public var isResting: Bool
      public var restDeadline: Date?
      public var isListening: Bool
  }
  ```
  with a failable `@MainActor init?(from model: WorkoutSessionModel)` —
  `nil` when `!model.hasActiveWorkout` (the controller in Task 8 reads that
  `nil` as "end the Activity"). `App/Widgets/Shared/WorkoutActivityAttributes.swift`
  (Task 7) maps this 1:1 into its `ContentState` — this type stays free of
  `ActivityKit` so `WorkoutLoggerApp` keeps building for macOS.

- [ ] **Step 1: Write the failing tests** (new file
  `WorkoutActivityStateTests.swift`, same `@Suite`/rig style as
  `WorkoutSessionModelTests.swift` — reuse its private `makeRig`/`say` by
  duplicating the small helper locally, since Swift test types don't share
  private helpers across files; keep it to the minimum this suite needs):

```swift
import Testing
import SwiftData
import Foundation
@testable import WorkoutLoggerApp
import WorkoutLoggerCore

@Suite("WorkoutActivityState")
@MainActor
struct WorkoutActivityStateTests {
    private static let bench = Exercise(name: "Bench Press", aliases: ["bench"])
    private static let library = ExerciseLibrary([bench])

    private func makeModel(script: [[String]]) throws -> (WorkoutSessionModel, ScriptedTranscriptSource) {
        let container = try ModelContainer(
            for: WorkoutRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(store: store, library: Self.library)
        let source = ScriptedTranscriptSource(script)
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: source, readbackVoice: SpyReadbackVoice(),
            haptics: SpyHaptics(), library: Self.library
        )
        return (model, source)
    }

    private func say(_ model: WorkoutSessionModel) async {
        model.pressed()
        await model.released()
    }

    @Test("reflects current exercise, working-set count, and rest deadline")
    func reflectsCurrentState() async throws {
        let (model, _) = try makeModel(script: [["start workout"], ["bench 100 for 5"]])
        await say(model); await say(model)
        let state = WorkoutActivityState(from: model)
        #expect(state?.exerciseName == "Bench Press")
        #expect(state?.workingSetCount == 1)
        #expect(state?.isResting == true)
        #expect(state?.restDeadline == model.restDeadline)
    }

    @Test("is nil with no active workout")
    func nilWithNoWorkout() throws {
        let (model, _) = try makeModel(script: [])
        #expect(WorkoutActivityState(from: model) == nil)
    }

    @Test("goes nil when the workout ends")
    func nilAfterWorkoutEnds() async throws {
        let (model, _) = try makeModel(script: [["start workout"], ["end workout"]])
        await say(model); await say(model)
        #expect(WorkoutActivityState(from: model) == nil)
    }
}
```

(Confirm the exact "end workout" transcript phrase against
`Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/Parser.swift` before
using it verbatim — grep for `endWorkout` in the parser's command-word table
and substitute the real phrase if `"end workout"` isn't it.)

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --no-parallel --filter WorkoutActivityStateTests`
Expected: FAIL — type doesn't exist.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// The compact, `ActivityKit`-free snapshot of live-workout state the Live
/// Activity needs (cluster 7c). Lives in `WorkoutLoggerApp`, not `App/`, so
/// the "what does the Activity show" derivation is one `swift test`ed place
/// rather than logic embedded in the widget-extension controller reaching
/// into `WorkoutSessionModel`'s many properties (Feature Envy) — this
/// mirrors `HUDProjection`'s role for the on-screen HUD.
public struct WorkoutActivityState: Equatable, Sendable {
    public var exerciseName: String
    public var workingSetCount: Int
    public var isResting: Bool
    public var restDeadline: Date?
    public var isListening: Bool

    public init(
        exerciseName: String, workingSetCount: Int, isResting: Bool,
        restDeadline: Date?, isListening: Bool
    ) {
        self.exerciseName = exerciseName
        self.workingSetCount = workingSetCount
        self.isResting = isResting
        self.restDeadline = restDeadline
        self.isListening = isListening
    }

    /// `nil` when no workout is active — the controller reads that as "end
    /// the Activity".
    @MainActor
    public init?(from model: WorkoutSessionModel) {
        guard model.hasActiveWorkout else { return nil }
        let entry = model.activeEntry()
        exerciseName = entry?.exercise.name ?? "Workout in progress"
        workingSetCount = entry?.sets.filter { $0.role == .working }.count ?? 0
        isResting = model.restStartedAt != nil
        restDeadline = model.restDeadline
        isListening = model.isListening
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --no-parallel --filter WorkoutActivityStateTests`, then the
full App suite.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Activity/WorkoutActivityState.swift \
        Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutActivityStateTests.swift
git commit -m "feat(7c): WorkoutActivityState — the ActivityKit-free live-activity projection"
```

---

### Task 5: Background modes + audio-session escalation (Deliverable 1, App layer)

**Files:**
- Modify: `App/Info.plist`
- Modify: `App/System/SystemSpeechRecognizer.swift`

**Interfaces:**
- No Swift API changes — this task is capability/`Info.plist` + the audio
  session category.

- [ ] **Step 1: `Info.plist`** — add background audio capability:

```xml
    <key>UIBackgroundModes</key>
    <array>
        <string>audio</string>
    </array>
```
(insert after the `NSHealthUpdateUsageDescription` entry, before `</dict>`).

- [ ] **Step 2: Escalate the audio session category**

In `SystemSpeechRecognizer.swift`, `beginUtterance()` currently sets:
```swift
try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
```
`.record` **disallows audio output entirely** — `SystemReadbackVoice`'s
`AVSpeechSynthesizer` needs a playback-capable category to speak results back
while backgrounded (the explicit-press scope this cluster adds, OPEN
QUESTION 2), and `UIBackgroundModes: audio` itself requires an active
playback-capable session to keep the process alive. Change to:
```swift
try? session.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
```
Document the change inline:
```swift
// `.playAndRecord`, not `.record` (cluster 7c): `.record` disallows audio
// output entirely, which would silently swallow every spoken readback once
// this session is active — and UIBackgroundModes: audio needs a
// playback-capable category to keep the process alive backgrounded at all.
// `.duckOthers` unchanged — still no reason to let other audio keep playing
// under an utterance or its readback.
```

- [ ] **Step 3: Interruption + route-change recovery (best-effort; device-verified only — see spec acceptance test 6)**

Add to `SystemSpeechRecognizer`, registered once (e.g. in `init` — add an
explicit `init()` if none exists, or at the top of the class body via a
lazy-registered `NotificationCenter` observer token stored as a property so
it can be removed in `deinit`):

```swift
private var interruptionObserver: NSObjectProtocol?

// call from init:
private func observeInterruptions() {
    interruptionObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
    ) { [weak self] note in
        guard
            let self,
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        Task { @MainActor in
            switch type {
            case .began:
                // A call or another app took the session — this utterance
                // can't continue. `endUtterance()`'s own hang-path guards
                // (final result already gone) resolve any parked
                // continuation empty rather than hang; nothing further to
                // do here beyond letting that happen naturally.
                break
            case .ended:
                let shouldResume = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
                if shouldResume {
                    try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                }
            @unknown default:
                break
            }
        }
    }
}
```
Call `observeInterruptions()` once — this class has no `init` today
(implicit memberwise-free default init from its stored properties, all of
which have defaults), so add:
```swift
init() { observeInterruptions() }
```
and remove the observer in `deinit`:
```swift
deinit {
    if let interruptionObserver {
        NotificationCenter.default.removeObserver(interruptionObserver)
    }
}
```
This is intentionally minimal — a full route-change handler (headphones
unplugged mid-utterance, etc.) is real scope but not package-testable and
not one of this cluster's resolved OPEN QUESTIONS; leave a `// TODO(7c
follow-up)` comment on the interruption handler noting route-change
(`AVAudioSession.routeChangeNotification`) is a candidate for the device-
verification pass (spec acceptance test 6) to reveal whether it's actually
needed, rather than building untested speculative handling now.

- [ ] **Step 4: Verify** — App-layer, no `swift test` coverage. Verified in
  Task 11's full `xcodebuild`.

- [ ] **Step 5: Commit**

```bash
git add App/Info.plist App/System/SystemSpeechRecognizer.swift
git commit -m "feat(7c): background audio mode + .playAndRecord session + interruption recovery"
```

---

### Task 6: `SystemRestNotificationScheduler` (real `UNUserNotificationCenter` conformer)

**Files:**
- Create: `App/System/SystemRestNotificationScheduler.swift`
- Modify: `App/TrackitApp.swift`

**Interfaces:**
- Consumes: `RestNotificationScheduler` protocol (Task 3).
- Produces: wires a real scheduler into `WorkoutSessionModel`'s init call in
  `TrackitApp.swift`.

- [ ] **Step 1: Implement**

```swift
import Foundation
import UserNotifications
import WorkoutLoggerApp

/// `RestNotificationScheduler` over `UNUserNotificationCenter` (cluster 7c).
/// One fixed identifier ("rest-complete") — `add(_:)` with a repeated
/// identifier replaces the pending request, so `schedule(deadline:)` never
/// needs to explicitly cancel before scheduling a new one.
@MainActor
final class SystemRestNotificationScheduler: RestNotificationScheduler {
    private static let identifier = "rest-complete"
    private let center = UNUserNotificationCenter.current()

    func schedule(deadline: Date) {
        // Fire-and-forget, like SystemSpeechRecognizer's
        // SFSpeechRecognizer.requestAuthorization — the real gate is the
        // system permission prompt itself; a denial just means this
        // specific notification never shows, which is the same silent
        // no-op UNUserNotificationCenter gives a denied `add` outright.
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Back to it — your next set is up."
        content.sound = .default

        // A deadline already in the past (e.g. reconciling a very late
        // foreground open) still fires promptly rather than being silently
        // dropped — UNTimeIntervalNotificationTrigger requires a positive
        // interval.
        let interval = max(0.1, deadline.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.identifier, content: content, trigger: trigger
        )
        center.add(request)
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }
}
```

- [ ] **Step 2: Wire into `TrackitApp.swift`**

In `init()`, construct it before `session` and pass it in:
```swift
let restNotifications = SystemRestNotificationScheduler()
```
and add `restNotifications: restNotifications,` to the `WorkoutSessionModel(...)`
call (after `haptics: SystemHaptics(),`).

- [ ] **Step 3: Verify** — App-layer; verified in Task 11's `xcodebuild`.

- [ ] **Step 4: Commit**

```bash
git add App/System/SystemRestNotificationScheduler.swift App/TrackitApp.swift
git commit -m "feat(7c): SystemRestNotificationScheduler, wired into TrackitApp"
```

---

### Task 7: Widget extension target + shared `ActivityAttributes` type

**Files:**
- Modify: `project.yml`
- Modify: `App/Info.plist`
- Create: `App/Widgets/Shared/WorkoutActivityAttributes.swift`
- Create: `App/Widgets/Info.plist`
- Create: `App/Widgets/TrackitWidgetsBundle.swift`
- Create: `App/Widgets/WorkoutLiveActivity.swift`

**Interfaces:**
- Produces: `WorkoutActivityAttributes: ActivityAttributes` with
  `ContentState: Codable, Hashable` — visible to both `Trackit` and
  `TrackitWidgets` targets (same source file listed in both targets'
  `sources:` in `project.yml`). No dependency on `WorkoutLoggerCore` or
  `WorkoutLoggerApp` (both are `App/`-only primitives, matching the spec's
  "its own small file, no dependency on `WorkoutLoggerCore`").

- [ ] **Step 1: `App/Widgets/Shared/WorkoutActivityAttributes.swift`**

```swift
import Foundation
import ActivityKit

/// The Live Activity's content contract (cluster 7c) — primitives only, no
/// `WorkoutLoggerCore`/`WorkoutLoggerApp` dependency, since this file
/// compiles into BOTH the app target and the `TrackitWidgets` extension
/// target. `App/System/LiveActivityController` maps
/// `WorkoutLoggerApp.WorkoutActivityState` into `ContentState` 1:1.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exerciseName: String
        var workingSetCount: Int
        var isResting: Bool
        var restDeadline: Date?
        var isListening: Bool
    }
}
```

- [ ] **Step 2: `App/Widgets/Info.plist`** (extension target's plist):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>TrackitWidgets</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
```

- [ ] **Step 3: `App/Info.plist`** — add `NSSupportsLiveActivities`:

```xml
    <key>NSSupportsLiveActivities</key>
    <true/>
```

- [ ] **Step 4: `project.yml`** — add the `TrackitWidgets` target and embed it:

```yaml
targets:
  Trackit:
    # ...unchanged...
    dependencies:
      - package: WorkoutLoggerCore
        product: WorkoutLoggerCore
      - package: WorkoutLoggerApp
        product: WorkoutLoggerApp
      - target: TrackitWidgets
        embed: true
  TrackitWidgets:
    type: app-extension
    platform: iOS
    sources:
      - path: App/Widgets
    settings:
      base:
        TARGETED_DEVICE_FAMILY: "1"
        SWIFT_VERSION: "6.0"
        INFOPLIST_FILE: App/Widgets/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.abubakarsahi.trackit.widgets
        SKIP_INSTALL: "NO"
  TrackitTests:
    # ...unchanged...
```
(`sources: [path: App/Widgets]` pulls in `Shared/WorkoutActivityAttributes.swift`
too since it's a subdirectory — no separate listing needed. Confirm XcodeGen's
exact app-extension `type:` string against its README/schema at
implementation time — `com.apple.product-type.app-extension` is the
underlying Xcode value; XcodeGen's shorthand is typically `app-extension` but
verify rather than guess, since a wrong string fails `xcodegen generate`
loudly and cheaply.)

- [ ] **Step 5: `App/Widgets/TrackitWidgetsBundle.swift`**

```swift
import WidgetKit
import SwiftUI

@main
struct TrackitWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
    }
}
```

- [ ] **Step 6: `App/Widgets/WorkoutLiveActivity.swift`** — the
  `ActivityConfiguration` + lock-screen view + Dynamic Island presentations
  per OPEN QUESTION 4's resolution:

```swift
import ActivityKit
import WidgetKit
import SwiftUI

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    ExpandedView(state: context.state)
                }
            } compactLeading: {
                CompactView(state: context.state)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Circle().fill(.tint).frame(width: 6, height: 6)
            }
        }
    }
}

private struct LockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.exerciseName).font(.headline)
            Text("\(state.workingSetCount) working set\(state.workingSetCount == 1 ? "" : "s")")
                .font(.subheadline)
            if state.isResting, let deadline = state.restDeadline {
                Text(timerInterval: Date()...deadline, countsDown: true)
                    .font(.title3.monospacedDigit())
            }
        }
        .padding()
    }
}

private struct ExpandedView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.exerciseName).font(.headline)
            Text("\(state.workingSetCount) working set\(state.workingSetCount == 1 ? "" : "s")")
                .font(.caption)
            if state.isResting, let deadline = state.restDeadline {
                Text(timerInterval: Date()...deadline, countsDown: true)
                    .font(.body.monospacedDigit())
            }
        }
    }
}

private struct CompactView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if state.isResting, let deadline = state.restDeadline {
            Text(timerInterval: Date()...deadline, countsDown: true)
                .font(.caption.monospacedDigit())
        } else {
            Image(systemName: state.isListening ? "mic.fill" : "mic")
        }
    }
}
```
(`Text(timerInterval:countsDown:)` self-renders from the `Date` bound with no
process needed to keep ticking — the mechanism OPEN QUESTION 3's resolution
relies on for "the countdown itself stays accurate" even while suspended.)

- [ ] **Step 7: Verify build** — `xcodegen generate` must succeed and produce
  the new target; full build verification happens in Task 11 once the
  controller (Task 8) exists to actually start an Activity (an unstarted
  widget extension still needs to compile standalone, so this step's
  `xcodegen generate && xcodebuild build` run is real signal on its own, not
  deferred busywork).

Run: `xcodegen generate && xcodebuild -project Trackit.xcodeproj -scheme Trackit -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED, including a `TrackitWidgets.appex` product.

- [ ] **Step 8: Commit**

```bash
git add project.yml App/Info.plist App/Widgets
git commit -m "feat(7c): TrackitWidgets extension target + WorkoutActivityAttributes + Live Activity views"
```

---

### Task 8: `LiveActivityController`

**Files:**
- Create: `App/System/LiveActivityController.swift`
- Modify: `App/TrackitApp.swift`

**Interfaces:**
- Consumes: `WorkoutLoggerApp.WorkoutActivityState` (Task 4),
  `WorkoutActivityAttributes` (Task 7), `WorkoutSessionModel`.
- Produces: `@MainActor final class LiveActivityController`, retained in
  `TrackitApp.swift` next to `RemoteCommandPushToTalk`/
  `SystemRestNotificationScheduler`.

- [ ] **Step 1: Implement**

```swift
import Foundation
import ActivityKit
import Observation
import WorkoutLoggerApp

/// Starts, updates, and ends the workout Live Activity (cluster 7c) — a
/// second observer of `WorkoutSessionModel`, alongside `HUDView` and
/// `RemoteCommandPushToTalk` (7b). Local-only updates (OPEN QUESTION 3): no
/// push, no server — `Activity.update(...)` runs whenever this process is
/// alive to observe a state change.
///
/// `@MainActor` because `WorkoutSessionModel` and `ActivityKit`'s
/// `Activity` type are both main-actor-bound in practice.
@MainActor
final class LiveActivityController {
    private let session: WorkoutSessionModel
    private var activity: Activity<WorkoutActivityAttributes>?

    init(session: WorkoutSessionModel) {
        self.session = session
        observe()
    }

    /// Re-arms itself after every fire, same self-re-arming
    /// `withObservationTracking` pattern as `RemoteCommandPushToTalk` (7b).
    private func observe() {
        withObservationTracking {
            _ = session.hasActiveWorkout
            _ = session.workout
            _ = session.restStartedAt
            _ = session.isListening
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.observe()
            }
        }
        sync()
    }

    private func sync() {
        guard let state = WorkoutActivityState(from: session) else {
            Task { await activity?.end(nil, dismissalPolicy: .immediate) }
            activity = nil
            return
        }
        let content = WorkoutActivityAttributes.ContentState(
            exerciseName: state.exerciseName,
            workingSetCount: state.workingSetCount,
            isResting: state.isResting,
            restDeadline: state.restDeadline,
            isListening: state.isListening
        )
        if let activity {
            Task { await activity.update(ActivityContent(state: content, staleDate: nil)) }
        } else {
            activity = try? Activity.request(
                attributes: WorkoutActivityAttributes(),
                content: ActivityContent(state: content, staleDate: nil)
            )
        }
    }
}
```

- [ ] **Step 2: Wire into `TrackitApp.swift`**

Add a stored property next to `remotePushToTalk`:
```swift
private let liveActivity: LiveActivityController
```
and construct it right after `remotePushToTalk`:
```swift
self.liveActivity = LiveActivityController(session: session)
```

- [ ] **Step 3: Verify** — full `xcodebuild` in Task 11.

- [ ] **Step 4: Commit**

```bash
git add App/System/LiveActivityController.swift App/TrackitApp.swift
git commit -m "feat(7c): LiveActivityController, wired into TrackitApp"
```

---

### Task 9: Full verification + spec/status updates

**Files:**
- Modify: `docs/superpowers/specs/2026-09-11-cluster-7c-background-audio-live-activity.md`

- [ ] **Step 1: Full test + build pass**

```bash
cd Packages/WorkoutLoggerCore && swift test
cd ../WorkoutLoggerApp && swift test --no-parallel
cd ../.. && xcodegen generate && \
  xcodebuild -project Trackit.xcodeproj -scheme Trackit -destination 'generic/platform=iOS Simulator' build
```
All three must be green before proceeding.

- [ ] **Step 2: Two-axis code review** (`mattpocock-skills:code-review`),
  fixed point = the commit this branch forked from (`f54d835`), spec = this
  cluster's spec file. Fold findings, re-verify.

- [ ] **Step 3: Tick the spec's Status checklist** (package slice, App
  wiring, widget target — leave "device verification + battery measurement"
  unticked, same device-only gate style as every prior cluster).

- [ ] **Step 4: PR + rebase-merge + main sync + memory update**, following
  the same `finishing-a-development-branch` rhythm as clusters 7b/7e.

---

## Self-Review Notes (from the plan author, not a re-review pass)

- **Spec coverage:** Deliverable 1 (Tasks 2,3,5,6) and Deliverable 2
  (Tasks 4,7,8) both covered; package-level acceptance tests 1-2 (Deliverable
  1) and 1 (Deliverable 2) map to Tasks 2/3 and Task 4's tests respectively.
  Device-only acceptance tests (both deliverables) are explicitly out of
  scope for this plan — Task 9 leaves that Status box unticked, matching
  every prior cluster's device-verification gate.
- **Open risk carried forward, not resolved by this plan:** XcodeGen's exact
  extension `type:` string (Task 7, Step 4) and the "end workout" parser
  phrase (Task 4, Step 1) are flagged inline rather than guessed — confirm
  both against the real source/tool output during execution, not from this
  plan's memory of them.
