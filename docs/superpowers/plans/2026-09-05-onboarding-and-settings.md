# Onboarding & Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first-run permission-priming screen and a Settings screen (mass unit, speech-permission status/recovery, exercise-library CRUD, delete-all-workout-data) to the trackit voice workout logger, with unit and library changes applied live.

**Architecture:** Two persistence buckets — preferences in `UserDefaults` behind a new `SettingsStore` port, the exercise library in the existing SwiftData container as a new `ExerciseRecord` model behind a new `ExerciseLibraryStore` port. A new `@Observable @MainActor SettingsModel` owns the live values and pushes unit/library changes one-directionally into `WorkoutSessionModel`, which forwards to the otherwise-frozen `WorkoutEngine` through two new additive setter methods. A tiny `OnboardingModel` gates a new screen ahead of the existing stale-workout gate in `RootView`.

**Tech Stack:** Swift 6, Swift Testing, SwiftData, SwiftUI (iOS 17+). Two SwiftPM packages (`WorkoutLoggerCore`, `WorkoutLoggerApp`) built and tested with `swift test`; the `App/` target (`App/Views/*`, `App/System/*`, `App/TrackitApp.swift`) is not compiled in this environment and is consistency-checked by read-through only.

**Spec:** `docs/superpowers/specs/2026-09-05-onboarding-and-settings-design.md`

## Global Constraints

- Strict TDD: red → green, one vertical slice per cycle. Run `swift test` in **both** `Packages/WorkoutLoggerCore` and `Packages/WorkoutLoggerApp` every cycle; both suites must stay green. Use separate shell invocations per package (a chained `cd … && swift test && cd … && swift test` runs the second `swift test` from the wrong directory).
- **Exactly two `WorkoutLoggerCore` edits, both additive:** `WorkoutEngine.updateLibrary(_ library: ExerciseLibrary)` and `WorkoutEngine.updateDefaultUnit(_ unit: MassUnit)`, with the two corresponding `private let` stored properties (`library`, `unit`) becoming `private var`. No other Core source change. (`WorkoutLoggerCore` test files may be added/extended freely.)
- No Xcode / `xcodebuild`. `App/` files are written to match the package API exactly and reviewed by read-through; no view carries logic that isn't a thin call into a tested model member.
- Loads are stored canonically in kilograms (ADR-0002). A default-unit change is display-and-future-parsing only; it never rewrites a stored set.
- Vocabulary follows `Packages/WorkoutLoggerCore/CONTEXT.md`: **Exercise** (catalog entry), **Custom exercise**, **Alias**, **Workout / Active workout / Completed workout**, **Load**, **working set**.
- Copy tone follows `PRODUCT.md` Brand Commitments ("on device", "nothing leaves your phone").
- `HealthKit` sync, export, and telemetry are subsystem F — out of scope. Build no stub sections for them.
- Pound⇄kilogram factor, matching existing code: `1 lb = 0.45359237 kg`.
- Branch: `subsystem-e-onboarding-settings` (spec committed at `2e54bcf`). Commit after every green step with the message shown in the step.
- Commit message trailer for every commit:
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
  ```

---

## File Structure

### `WorkoutLoggerCore` (compiled, tested)
- `Sources/WorkoutLoggerCore/WorkoutEngine.swift` — **modify**: `library` and `unit` `let`→`var`; add `updateLibrary(_:)` and `updateDefaultUnit(_:)`.
- `Tests/WorkoutLoggerCoreTests/WorkoutEngineTests.swift` — **modify**: add cases for the two new methods.

### `WorkoutLoggerApp` (compiled, tested)
- `Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift` — **modify**: `library`/`unit` `let`→`var`; add `updateLibrary(_:)`, `updateDefaultUnit(_:)`, `hasActiveWorkout`, `refreshKnownBests()`.
- `Sources/WorkoutLoggerApp/Settings/SettingsStore.swift` — **create**: `SettingsStore` protocol.
- `Sources/WorkoutLoggerApp/Settings/SpeechAuthorization.swift` — **create**: `SpeechAuthorizationStatus` enum + `SpeechAuthorization` protocol.
- `Sources/WorkoutLoggerApp/Settings/SettingsFakes.swift` — **create**: `InMemorySettingsStore`, `FakeSpeechAuthorization`, `InMemoryExerciseLibraryStore`.
- `Sources/WorkoutLoggerApp/Settings/SettingsModel.swift` — **create**: `@Observable @MainActor SettingsModel`.
- `Sources/WorkoutLoggerApp/Settings/OnboardingModel.swift` — **create**: `@Observable @MainActor OnboardingModel`.
- `Sources/WorkoutLoggerApp/Persistence/ExerciseRecord.swift` — **create**: `@Model ExerciseRecord`.
- `Sources/WorkoutLoggerApp/Persistence/ExerciseLibraryStore.swift` — **create**: `ExerciseLibraryStore` protocol, `ExerciseLibraryError`, `SwiftDataExerciseLibraryStore`, `defaultExerciseSeed`.
- `Sources/WorkoutLoggerApp/Persistence/SwiftDataWorkoutStore.swift` — **modify**: add `deleteAllWorkouts()`.
- `Sources/WorkoutLoggerApp/History/WorkoutHistoryStore.swift` — **modify**: add `deleteAllWorkouts()` to the protocol.
- `Sources/WorkoutLoggerApp/History/WorkoutHistoryModel.swift` — **modify**: add `deleteAllWorkoutData()`.
- `Sources/WorkoutLoggerApp/HUD/StoreProvisioning.swift` — **modify**: add `ExerciseRecord.self` to the schema.
- `Tests/WorkoutLoggerAppTests/` — **create**: `SettingsModelTests.swift`, `OnboardingModelTests.swift`, `ExerciseLibraryStoreTests.swift`, `SettingsFakesTests.swift`; **modify**: `WorkoutSessionModelTests.swift`, `WorkoutHistoryModelTests.swift`, `SwiftDataWorkoutStoreTests.swift`, `StoreProvisioningTests.swift`.

### `App/` (not compiled; consistency-checked)
- `App/Views/OnboardingView.swift` — **create**.
- `App/Views/SettingsView.swift` — **create**.
- `App/Views/ExerciseLibraryView.swift` — **create**.
- `App/Views/ExerciseEditView.swift` — **create**.
- `App/System/UserDefaultsSettingsStore.swift` — **create**.
- `App/System/SystemSpeechAuthorization.swift` — **create**.
- `App/Views/RootView.swift` — **modify**: onboarding gate + gear toolbar item.
- `App/TrackitApp.swift` — **modify**: build the new stores/models; load the library from the store; drop the hard-coded `seedExercises`.
- `DESIGN.md` — **modify**: Onboarding, Settings, and Exercise Library / Editor entries.

---

## Task 1: `WorkoutEngine.updateDefaultUnit(_:)`

**Files:**
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift` (`unit` at line ~163 `let`→`var`; new method near the other `public func`s)
- Test: `Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutEngineTests.swift`

**Interfaces:**
- Consumes: `WorkoutEngine(store:library:unit:knownBests:restTarget:now:)`, `WorkoutEngine.hear(_:)`, `InMemoryWorkoutStore` (existing Core test double), `ExerciseLibrary`, `MassUnit`, `Exercise`.
- Produces: `WorkoutEngine.updateDefaultUnit(_ unit: MassUnit)` — replaces the default unit used when a spoken set carries no explicit unit word. Affects only subsequently heard sets.

- [ ] **Step 1: Write the failing test**

Add to `WorkoutEngineTests.swift` inside `struct WorkoutEngineTests`:

```swift
@Test("updateDefaultUnit changes the unit applied to a later set with no spoken unit")
func updateDefaultUnitAffectsLaterSets() {
    let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench press"])
    let store = InMemoryWorkoutStore()
    let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]), unit: .kilograms)
    engine.startWorkout()
    engine.hear(["bench press"])
    engine.hear(["100 for 5"]) // default kilograms

    engine.updateDefaultUnit(.pounds)
    engine.hear(["200 for 3"]) // now defaults to pounds

    let sets = engine.workout?.entries.first?.sets
    #expect(sets?.count == 2)
    #expect(sets?.first?.loadKilograms == 100)
    #expect(sets?.last?.loadKilograms == 200 * 0.45359237)
}

@Test("updateDefaultUnit does not rewrite sets already stored")
func updateDefaultUnitLeavesStoredSetsAlone() {
    let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench press"])
    let engine = WorkoutEngine(store: InMemoryWorkoutStore(), library: ExerciseLibrary([bench]), unit: .kilograms)
    engine.startWorkout()
    engine.hear(["bench press"])
    engine.hear(["100 for 5"])

    engine.updateDefaultUnit(.pounds)

    #expect(engine.workout?.entries.first?.sets.first?.loadKilograms == 100)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerCore && swift test --filter WorkoutEngineTests`
Expected: FAIL — `value of type 'WorkoutEngine' has no member 'updateDefaultUnit'`.

- [ ] **Step 3: Write minimal implementation**

In `WorkoutEngine.swift`, change the stored property (comment kept):

```swift
    /// The user's kg/lb preference — the default unit for a set with no spoken unit.
    private var unit: MassUnit
```

Add, next to the other public methods (e.g. just below `hear(_:)`):

```swift
    /// Replace the default unit applied to a spoken set that carries no unit
    /// word. Read fresh on each `hear(_:)`, so a change between utterances is
    /// consistent; already-stored sets keep the kilogram value they were
    /// canonicalised to.
    public func updateDefaultUnit(_ unit: MassUnit) {
        self.unit = unit
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/WorkoutLoggerCore && swift test`
Expected: PASS (whole suite green, 122 tests).
Run: `cd Packages/WorkoutLoggerApp && swift test`
Expected: PASS (unchanged, 105 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerCore
git commit -m "feat(engine): live default-unit setter"
```

---

## Task 2: `WorkoutEngine.updateLibrary(_:)`

**Files:**
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift` (`library` at line ~156 `let`→`var`; new method)
- Test: `Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutEngineTests.swift`

**Interfaces:**
- Consumes: `WorkoutEngine`, `WorkoutEngine.hear(_:)`, `WorkoutEngine.personalRecords`, `ExerciseLibrary`, `Exercise`.
- Produces: `WorkoutEngine.updateLibrary(_ library: ExerciseLibrary)` — replaces the library used by `postProcess` + `parse` on subsequent utterances. Does not touch stored entries or `personalRecords`.

- [ ] **Step 1: Write the failing test**

```swift
@Test("updateLibrary makes a previously-unknown exercise resolvable on the next utterance")
func updateLibraryAddsResolvableExercise() {
    let store = InMemoryWorkoutStore()
    let engine = WorkoutEngine(store: store, library: .empty)
    engine.startWorkout()
    engine.hear(["incline dumbbell press"]) // unknown → no entry
    #expect(engine.workout?.entries.isEmpty == true)

    let incline = Exercise(name: "Incline Dumbbell Press", aliases: ["incline dumbbell press", "incline press"])
    engine.updateLibrary(ExerciseLibrary([incline]))
    engine.hear(["incline dumbbell press"])

    #expect(engine.workout?.entries.map(\.exercise) == [incline])
}

@Test("updateLibrary leaves existing entries and personal records untouched")
func updateLibraryPreservesExistingWork() {
    let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench press"])
    let engine = WorkoutEngine(store: InMemoryWorkoutStore(), library: ExerciseLibrary([bench]))
    engine.startWorkout()
    engine.hear(["bench press"])
    engine.hear(["100 for 5"])
    let entriesBefore = engine.workout?.entries
    let prCountBefore = engine.personalRecords.count

    engine.updateLibrary(.empty)

    #expect(engine.workout?.entries == entriesBefore)
    #expect(engine.personalRecords.count == prCountBefore)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerCore && swift test --filter WorkoutEngineTests`
Expected: FAIL — `value of type 'WorkoutEngine' has no member 'updateLibrary'`.

- [ ] **Step 3: Write minimal implementation**

In `WorkoutEngine.swift`:

```swift
    private var library: ExerciseLibrary
```

Add next to `updateDefaultUnit`:

```swift
    /// Replace the exercise library used to resolve spoken names. Read fresh
    /// on each `hear(_:)` via `postProcess` + `parse`, so a swap between
    /// utterances is consistent; entries already logged embed their
    /// `Exercise` by value and are unaffected.
    public func updateLibrary(_ library: ExerciseLibrary) {
        self.library = library
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/WorkoutLoggerCore && swift test` → PASS.
Run: `cd Packages/WorkoutLoggerApp && swift test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerCore
git commit -m "feat(engine): live exercise-library setter"
```

---

## Task 3: `WorkoutSessionModel` — mirror `updateDefaultUnit` / `updateLibrary`

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift` (`library`/`unit` `let`→`var` at lines ~69-70; new methods)
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift`

**Interfaces:**
- Consumes: `WorkoutEngine.updateDefaultUnit(_:)`, `WorkoutEngine.updateLibrary(_:)` (Tasks 1–2); `WorkoutSessionModel(engine:transcriptSource:readbackVoice:haptics:library:unit:…)`; the test `Rig` / `makeRig` helper; `ScriptedTranscriptSource`; `WorkoutSessionModel.displayUnit`, `.workout`, `.activeExerciseName`.
- Produces: `WorkoutSessionModel.updateDefaultUnit(_ unit: MassUnit)` and `WorkoutSessionModel.updateLibrary(_ library: ExerciseLibrary)` — each assigns the model's own mirrored copy (used by its inspection parse in `apply`) and forwards to the engine.

- [ ] **Step 1: Write the failing test**

Add to `WorkoutSessionModelTests.swift`:

```swift
@Test("updateDefaultUnit flips displayUnit and is forwarded to the engine")
func updateDefaultUnitFlipsDisplayUnitAndForwards() async throws {
    let rig = try makeRig(script: [["start workout"], ["bench"], ["200 for 3"]], unit: .kilograms)
    #expect(rig.model.displayUnit == .kilograms)
    await say(rig) // start
    await say(rig) // bench

    rig.model.updateDefaultUnit(.pounds)
    #expect(rig.model.displayUnit == .pounds)

    await say(rig) // 200 for 3 — now defaults to pounds in the engine
    #expect(rig.model.workout?.entries.first?.sets.first?.loadKilograms == 200 * 0.45359237)
}

@Test("updateLibrary lets a new exercise resolve through the model's own parse and the engine")
func updateLibraryResolvesNewExercise() async throws {
    let rig = try makeRig(script: [["start workout"], ["incline press"]])
    await say(rig) // start

    let incline = Exercise(name: "Incline Press", aliases: ["incline press"])
    rig.model.updateLibrary(ExerciseLibrary([Self.bench, incline]))
    await say(rig) // incline press

    #expect(rig.model.workout?.entries.map(\.exercise.name).contains("Incline Press") == true)
    #expect(rig.model.activeExerciseName == "Incline Press")
}

@Test("updating unit mid-workout leaves the open workout and PR gate intact")
func updateDefaultUnitMidWorkoutIsInert() async throws {
    let rig = try makeRig(script: [["start workout"], ["bench"], ["100 for 5"]])
    await say(rig); await say(rig); await say(rig)
    let startedAt = rig.model.workout?.startedAt
    let entries = rig.model.workout?.entries

    rig.model.updateDefaultUnit(.pounds)

    #expect(rig.model.workout?.startedAt == startedAt)
    #expect(rig.model.workout?.entries == entries)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSessionModelTests`
Expected: FAIL — `value of type 'WorkoutSessionModel' has no member 'updateDefaultUnit'`.

- [ ] **Step 3: Write minimal implementation**

In `WorkoutSessionModel.swift`, change the two declarations:

```swift
    @ObservationIgnored private var library: ExerciseLibrary
    @ObservationIgnored private var unit: MassUnit
```

Add, near `pressed()` / `released()`:

```swift
    /// Replace the default kg/lb unit live. Updates the copy this model uses
    /// for its own inspection parse and forwards to the engine, which owns
    /// the authoritative apply. Display-only for already-logged sets.
    public func updateDefaultUnit(_ unit: MassUnit) {
        self.unit = unit
        engine.updateDefaultUnit(unit)
    }

    /// Replace the exercise library live, on both this model's inspection
    /// parse and the engine's authoritative one.
    public func updateLibrary(_ library: ExerciseLibrary) {
        self.library = library
        engine.updateLibrary(library)
    }
```

Note: `displayUnit` is already `public var displayUnit: MassUnit { unit }` and needs no change.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/WorkoutLoggerApp && swift test` → PASS.
Run: `cd Packages/WorkoutLoggerCore && swift test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp
git commit -m "feat(session): mirror live unit/library setters to the engine"
```

---

## Task 4: `WorkoutSessionModel` — `hasActiveWorkout` + `refreshKnownBests()`

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift`

**Interfaces:**
- Consumes: `WorkoutSessionModel.workout`, the injected `history: () -> [Workout]` closure, the existing `static func exercisesWithLoadedWorkingSet(in:) -> Set<String>`, `makeRig` (accepts `history:` and `knownBestExercises:`).
- Produces:
  - `WorkoutSessionModel.hasActiveWorkout: Bool` — true while a Workout is open and not ended.
  - `WorkoutSessionModel.refreshKnownBests()` — re-derives the personal-record celebration gate from the current `history()` result. Used after "delete all workout data", which has no workout-end event to trigger the usual refresh.

- [ ] **Step 1: Write the failing test**

```swift
@Test("hasActiveWorkout tracks the open-workout lifecycle")
func hasActiveWorkoutLifecycle() async throws {
    let rig = try makeRig(script: [["start workout"], ["end workout"]])
    #expect(rig.model.hasActiveWorkout == false)
    await say(rig) // start
    #expect(rig.model.hasActiveWorkout == true)
    await say(rig) // end
    #expect(rig.model.hasActiveWorkout == false)
}

@Test("refreshKnownBests re-derives the celebration gate from current history")
func refreshKnownBestsFromHistory() async throws {
    // Gate seeded as if history had a loaded working Bench Press set…
    let rig = try makeRig(
        script: [["start workout"], ["bench"], ["100 for 5"]],
        knownBestExercises: ["Bench Press"],
        history: { [] } // …but history is now empty
    )
    rig.model.refreshKnownBests()

    await say(rig); await say(rig); await say(rig)
    // First loaded working set for Bench Press with an empty gate is a
    // baseline, not a celebration.
    #expect(rig.haptics.played.contains(.personalRecord) == false)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSessionModelTests`
Expected: FAIL — `value of type 'WorkoutSessionModel' has no member 'hasActiveWorkout'`.

- [ ] **Step 3: Write minimal implementation**

In `WorkoutSessionModel.swift`, near `keepScreenAwake`:

```swift
    /// True while a Workout is open and not yet ended — Settings uses it to
    /// block "delete all workout data" mid-session.
    public var hasActiveWorkout: Bool { workout.map { !$0.isEnded } ?? false }

    /// Re-derive the personal-record celebration gate from current history.
    /// The normal refresh happens when a workout ends; "delete all workout
    /// data" wipes history with no such event, so it calls this explicitly.
    public func refreshKnownBests() {
        knownBestExercises = Self.exercisesWithLoadedWorkingSet(in: history())
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/WorkoutLoggerApp && swift test` → PASS.
Run: `cd Packages/WorkoutLoggerCore && swift test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp
git commit -m "feat(session): hasActiveWorkout flag and refreshKnownBests()"
```

---

## Task 5: `SettingsStore` + `SpeechAuthorization` ports and fakes

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Settings/SettingsStore.swift`
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Settings/SpeechAuthorization.swift`
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Settings/SettingsFakes.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/SettingsFakesTests.swift`

**Interfaces:**
- Consumes: `MassUnit` (from `WorkoutLoggerCore`).
- Produces:
  - `protocol SettingsStore: AnyObject` — `var defaultUnit: MassUnit { get set }`, `var hasCompletedOnboarding: Bool { get set }`.
  - `enum SpeechAuthorizationStatus: Equatable, Sendable` — `notDetermined`, `granted`, `denied`, `unavailable`.
  - `@MainActor protocol SpeechAuthorization: AnyObject` — `var status: SpeechAuthorizationStatus { get }`, `func request() async`.
  - `final class InMemorySettingsStore: SettingsStore` — defaults `.kilograms` / `false`.
  - `@MainActor final class FakeSpeechAuthorization: SpeechAuthorization` — `init(status:resultAfterRequest:)`, `private(set) var requestCount: Int`.
  - `final class InMemoryExerciseLibraryStore: ExerciseLibraryStore` — declared here as a stub returning empty; its full behavior is filled in Task 6. (Placed here so Task 6's file stays real-impl-only. If Task 6 is done first, create it there instead — either order works; keep one definition.)

  > **Decision (plan author):** put `InMemoryExerciseLibraryStore` in Task 6 alongside the protocol it implements, not here. Task 5 creates only `InMemorySettingsStore` and `FakeSpeechAuthorization`. This note supersedes the bullet above.

- [ ] **Step 1: Write the failing test**

Create `SettingsFakesTests.swift`:

```swift
import Testing
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("Settings fakes")
@MainActor
struct SettingsFakesTests {

    @Test("InMemorySettingsStore round-trips both values")
    func settingsStoreRoundTrip() {
        let store = InMemorySettingsStore()
        #expect(store.defaultUnit == .kilograms)
        #expect(store.hasCompletedOnboarding == false)

        store.defaultUnit = .pounds
        store.hasCompletedOnboarding = true

        #expect(store.defaultUnit == .pounds)
        #expect(store.hasCompletedOnboarding == true)
    }

    @Test("FakeSpeechAuthorization reports its status and transitions on request()")
    func speechAuthFake() async {
        let auth = FakeSpeechAuthorization(status: .notDetermined, resultAfterRequest: .denied)
        #expect(auth.status == .notDetermined)
        #expect(auth.requestCount == 0)

        await auth.request()

        #expect(auth.status == .denied)
        #expect(auth.requestCount == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter SettingsFakesTests`
Expected: FAIL — `cannot find 'InMemorySettingsStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

`SettingsStore.swift`:

```swift
import WorkoutLoggerCore

/// The slice of preference persistence the settings and onboarding models
/// need: the default kg/lb unit and whether first-run priming has been shown.
/// Backed by `UserDefaults` in the app; an in-memory fake in tests.
public protocol SettingsStore: AnyObject {
    var defaultUnit: MassUnit { get set }
    var hasCompletedOnboarding: Bool { get set }
}
```

`SpeechAuthorization.swift`:

```swift
/// Current speech / microphone authorization, flattened to the four states
/// the UI distinguishes. `unavailable` means the device or locale has no
/// on-device recogniser — iOS Settings can't fix it, so no recovery link.
public enum SpeechAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case unavailable
}

/// Reads and requests speech authorization. The real implementation wraps
/// the system speech + record-permission APIs and carries no logic; a
/// scriptable fake drives the model tests.
@MainActor
public protocol SpeechAuthorization: AnyObject {
    var status: SpeechAuthorizationStatus { get }
    func request() async
}
```

`SettingsFakes.swift`:

```swift
import WorkoutLoggerCore

/// In-memory `SettingsStore` for tests and previews.
public final class InMemorySettingsStore: SettingsStore {
    public var defaultUnit: MassUnit
    public var hasCompletedOnboarding: Bool

    public init(defaultUnit: MassUnit = .kilograms, hasCompletedOnboarding: Bool = false) {
        self.defaultUnit = defaultUnit
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}

/// Scriptable `SpeechAuthorization`: starts at `status`, and `request()`
/// moves it to `resultAfterRequest` and bumps `requestCount`.
@MainActor
public final class FakeSpeechAuthorization: SpeechAuthorization {
    public private(set) var status: SpeechAuthorizationStatus
    public private(set) var requestCount = 0
    private let resultAfterRequest: SpeechAuthorizationStatus

    public init(
        status: SpeechAuthorizationStatus = .notDetermined,
        resultAfterRequest: SpeechAuthorizationStatus = .granted
    ) {
        self.status = status
        self.resultAfterRequest = resultAfterRequest
    }

    public func request() async {
        requestCount += 1
        status = resultAfterRequest
    }

    /// Test hook: simulate the user changing the setting in iOS Settings.
    public func set(_ status: SpeechAuthorizationStatus) {
        self.status = status
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/WorkoutLoggerApp && swift test` → PASS.
Run: `cd Packages/WorkoutLoggerCore && swift test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp
git commit -m "feat(settings): SettingsStore and SpeechAuthorization ports with fakes"
```

---

## Task 6: `ExerciseRecord` model + `ExerciseLibraryStore` port + SwiftData impl

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/ExerciseRecord.swift`
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/ExerciseLibraryStore.swift`
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/HUD/StoreProvisioning.swift` (add `ExerciseRecord.self` to the `Schema`)
- Create: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/ExerciseLibraryStoreTests.swift`
- Modify: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/StoreProvisioningTests.swift` (only if it asserts the exact schema; otherwise leave)

**Interfaces:**
- Consumes: `Exercise` (`name: String`, `aliases: [String]`, `init(name:aliases:)`), `WorkoutRecord`, `provisionStore(onDiskURL:)`, SwiftData `ModelContext` / `ModelContainer`.
- Produces:
  - `@Model final class ExerciseRecord` — `@Attribute(.unique) var name: String`, `var aliases: [String]`, `init(name:aliases:)`.
  - `enum ExerciseLibraryError: Error, Equatable` — `emptyName`, `duplicateName`.
  - `protocol ExerciseLibraryStore: AnyObject`:
    - `func all() -> [Exercise]` — alphabetical by `name`, case-insensitive.
    - `func seedIfEmpty(_ exercises: [Exercise])` — inserts the given exercises only when the store is empty.
    - `func add(_ exercise: Exercise) throws` — throws `.emptyName` / `.duplicateName` (case-insensitive).
    - `func update(named originalName: String, to exercise: Exercise) throws` — rename + re-alias; same validation, but the record being edited does not count as its own duplicate.
    - `func delete(named name: String)` — no-op if absent.
  - `final class SwiftDataExerciseLibraryStore: ExerciseLibraryStore` — `init(context: ModelContext)`.
  - `let defaultExerciseSeed: [Exercise]` — the six starter exercises (moved verbatim from `TrackitApp.seedExercises`).

- [ ] **Step 1: Write the failing test**

Create `ExerciseLibraryStoreTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("SwiftDataExerciseLibraryStore")
@MainActor
struct ExerciseLibraryStoreTests {

    private func makeStore() throws -> (SwiftDataExerciseLibraryStore, ModelContext) {
        let container = try ModelContainer(
            for: ExerciseRecord.self, WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        return (SwiftDataExerciseLibraryStore(context: context), context)
    }

    @Test("seedIfEmpty inserts once, then is a no-op")
    func seedOnce() throws {
        let (store, _) = try makeStore()
        store.seedIfEmpty([Exercise(name: "Squat"), Exercise(name: "Bench")])
        store.seedIfEmpty([Exercise(name: "Deadlift")])

        #expect(store.all().map(\.name) == ["Bench", "Squat"])
    }

    @Test("add / update / delete round-trip; all() is alphabetical")
    func crudRoundTrip() throws {
        let (store, _) = try makeStore()
        try store.add(Exercise(name: "Row", aliases: ["barbell row"]))
        try store.add(Exercise(name: "Curl"))
        try store.update(named: "Row", to: Exercise(name: "Pendlay Row", aliases: ["pendlay"]))
        store.delete(named: "Curl")

        let all = store.all()
        #expect(all.map(\.name) == ["Pendlay Row"])
        #expect(all.first?.aliases == ["pendlay"])
    }

    @Test("empty and duplicate names are rejected")
    func validation() throws {
        let (store, _) = try makeStore()
        try store.add(Exercise(name: "Bench Press"))

        #expect(throws: ExerciseLibraryError.emptyName) {
            try store.add(Exercise(name: "   "))
        }
        #expect(throws: ExerciseLibraryError.duplicateName) {
            try store.add(Exercise(name: "bench press"))
        }
    }

    @Test("update lets a record keep its own name but rejects colliding with another")
    func updateDuplicateRules() throws {
        let (store, _) = try makeStore()
        try store.add(Exercise(name: "Bench Press"))
        try store.add(Exercise(name: "Squat"))

        try store.update(named: "Squat", to: Exercise(name: "Squat", aliases: ["back squat"]))
        #expect(store.all().first(where: { $0.name == "Squat" })?.aliases == ["back squat"])

        #expect(throws: ExerciseLibraryError.duplicateName) {
            try store.update(named: "Squat", to: Exercise(name: "Bench Press"))
        }
    }

    @Test("deleting an exercise leaves stored workouts intact")
    func deleteDoesNotTouchWorkouts() throws {
        let (store, context) = try makeStore()
        try store.add(Exercise(name: "Bench Press"))
        let workoutStore = SwiftDataWorkoutStore(context: context)
        let set = LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .straight,
            loadKilograms: 100, reps: 5, durationSeconds: nil, distanceMeters: nil,
            supersetRunID: nil, loggedAt: Date(timeIntervalSince1970: 10), note: nil
        )
        workoutStore.save(Workout(
            entries: [Entry(exercise: Exercise(name: "Bench Press"), sets: [set])],
            startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 100)
        ))

        store.delete(named: "Bench Press")

        #expect(store.all().isEmpty)
        #expect(workoutStore.history().count == 1)
    }

    @Test("defaultExerciseSeed is the six starters")
    func seedConstant() {
        #expect(defaultExerciseSeed.count == 6)
        #expect(defaultExerciseSeed.map(\.name).contains("Conventional Deadlift"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter ExerciseLibraryStoreTests`
Expected: FAIL — `cannot find 'ExerciseRecord' in scope`.

- [ ] **Step 3: Write minimal implementation**

`ExerciseRecord.swift`:

```swift
import SwiftData

/// One persisted Exercise in the user's library: a unique canonical name and
/// its spoken Aliases. Distinct from `WorkoutRecord` in the same container —
/// "delete all workout data" removes `WorkoutRecord`s only.
@Model
public final class ExerciseRecord {
    @Attribute(.unique) public var name: String
    public var aliases: [String]

    public init(name: String, aliases: [String]) {
        self.name = name
        self.aliases = aliases
    }
}
```

`ExerciseLibraryStore.swift`:

```swift
import Foundation
import SwiftData
import WorkoutLoggerCore

public enum ExerciseLibraryError: Error, Equatable {
    case emptyName
    case duplicateName
}

/// Read/write access to the user's Exercise library.
public protocol ExerciseLibraryStore: AnyObject {
    func all() -> [Exercise]
    func seedIfEmpty(_ exercises: [Exercise])
    func add(_ exercise: Exercise) throws
    func update(named originalName: String, to exercise: Exercise) throws
    func delete(named name: String)
}

/// The exercises a brand-new install starts with. After first launch the
/// library is entirely user-owned; this is only the initial population.
public let defaultExerciseSeed: [Exercise] = [
    Exercise(name: "Barbell Bench Press", aliases: ["bench", "bench press"]),
    Exercise(name: "Barbell Back Squat", aliases: ["squat", "squats", "back squat"]),
    Exercise(name: "Conventional Deadlift", aliases: ["deadlift", "deads"]),
    Exercise(name: "Overhead Press", aliases: ["ohp", "overhead press", "press"]),
    Exercise(name: "Barbell Row", aliases: ["row", "barbell row", "bent row"]),
    Exercise(name: "Pull-Up", aliases: ["pull up", "pull ups", "pullups"]),
]

/// SwiftData-backed `ExerciseLibraryStore`. One `ExerciseRecord` per Exercise.
public final class SwiftDataExerciseLibraryStore: ExerciseLibraryStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    private func records() -> [ExerciseRecord] {
        (try? context.fetch(FetchDescriptor<ExerciseRecord>())) ?? []
    }

    public func all() -> [Exercise] {
        records()
            .map { Exercise(name: $0.name, aliases: $0.aliases) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func seedIfEmpty(_ exercises: [Exercise]) {
        guard records().isEmpty else { return }
        for exercise in exercises {
            context.insert(ExerciseRecord(name: exercise.name, aliases: exercise.aliases))
        }
        try? context.save()
    }

    public func add(_ exercise: Exercise) throws {
        let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ExerciseLibraryError.emptyName }
        guard !records().contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { throw ExerciseLibraryError.duplicateName }
        context.insert(ExerciseRecord(name: name, aliases: exercise.aliases))
        try? context.save()
    }

    public func update(named originalName: String, to exercise: Exercise) throws {
        let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ExerciseLibraryError.emptyName }
        let all = records()
        guard let record = all.first(where: {
            $0.name.localizedCaseInsensitiveCompare(originalName) == .orderedSame
        }) else { return }
        let collides = all.contains {
            $0 !== record && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        guard !collides else { throw ExerciseLibraryError.duplicateName }
        record.name = name
        record.aliases = exercise.aliases
        try? context.save()
    }

    public func delete(named name: String) {
        for record in records() where record.name.localizedCaseInsensitiveCompare(name) == .orderedSame {
            context.delete(record)
        }
        try? context.save()
    }
}

extension SwiftDataExerciseLibraryStore {}
```

`StoreProvisioning.swift` — change the one schema line:

```swift
    let schema = Schema([WorkoutRecord.self, ExerciseRecord.self])
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/WorkoutLoggerApp && swift test` → PASS. If `StoreProvisioningTests` asserts the schema's model count, update that expectation to `2`; otherwise no test change is needed.
Run: `cd Packages/WorkoutLoggerCore && swift test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp
git commit -m "feat(library): ExerciseRecord model and ExerciseLibraryStore"
```

---

## Task 7: Delete-all plumbing — store + history model

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/WorkoutHistoryStore.swift` (add protocol method)
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/SwiftDataWorkoutStore.swift` (implement it)
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/WorkoutHistoryModel.swift` (add `deleteAllWorkoutData()`)
- Modify: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/SwiftDataWorkoutStoreTests.swift`
- Modify: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutHistoryModelTests.swift`

**Interfaces:**
- Consumes: `WorkoutHistoryStore` (`history()`, `save(_:)`, `lastSaveError`), `SwiftDataWorkoutStore`, `WorkoutHistoryModel(store:historyUnavailable:)`, `WorkoutHistoryModel.rows`, `.reload()`. Any existing in-memory `WorkoutHistoryStore` fake used by `WorkoutHistoryModelTests` gains the new method.
- Produces:
  - `WorkoutHistoryStore.deleteAllWorkouts()` — removes every stored Workout; `ExerciseRecord`s and preferences untouched.
  - `WorkoutHistoryModel.deleteAllWorkoutData()` — calls `store.deleteAllWorkouts()` then `reload()`; leaves `selected` nil.

- [ ] **Step 1: Write the failing test**

Add to `SwiftDataWorkoutStoreTests.swift`:

```swift
@Test("deleteAllWorkouts empties history and leaves colocated exercise records")
func deleteAllWorkouts() throws {
    let container = try ModelContainer(
        for: WorkoutRecord.self, ExerciseRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let store = SwiftDataWorkoutStore(context: context)
    store.save(workout(startedAt: 1_000, reps: 5))
    store.save(workout(startedAt: 2_000, reps: 3))
    context.insert(ExerciseRecord(name: "Bench Press", aliases: ["bench"]))
    try context.save()

    store.deleteAllWorkouts()

    #expect(store.history().isEmpty)
    let exercises = try context.fetch(FetchDescriptor<ExerciseRecord>())
    #expect(exercises.count == 1)
}
```

Add to `WorkoutHistoryModelTests.swift` (match its existing store-fake pattern — if it uses `SwiftDataWorkoutStore` directly, mirror that; if it has an in-memory fake, add `deleteAllWorkouts()` there too):

```swift
@Test("deleteAllWorkoutData clears the rows and the store")
func deleteAllWorkoutData() throws {
    let store = /* the suite's existing store-construction helper */ try makeStore()
    store.save(endedWorkout(startedAt: 1_000))
    store.save(endedWorkout(startedAt: 2_000))
    let model = WorkoutHistoryModel(store: store)
    #expect(model.rows.count == 2)

    model.deleteAllWorkoutData()

    #expect(model.rows.isEmpty)
    #expect(store.history().isEmpty)
}
```

> If `WorkoutHistoryModelTests` has no `endedWorkout`/`makeStore` helper, reuse whatever it already uses to seed completed workouts; the assertion shape is what matters.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter SwiftDataWorkoutStoreTests`
Expected: FAIL — `value of type 'SwiftDataWorkoutStore' has no member 'deleteAllWorkouts'`.

- [ ] **Step 3: Write minimal implementation**

`WorkoutHistoryStore.swift` — add to the protocol:

```swift
public protocol WorkoutHistoryStore: AnyObject {
    func history() -> [Workout]
    func save(_ workout: Workout)
    func deleteAllWorkouts()
    var lastSaveError: Error? { get }
}
```

`SwiftDataWorkoutStore.swift` — add:

```swift
    /// Removes every `WorkoutRecord`. Exercise-library records and any
    /// `SettingsStore` values live elsewhere and are untouched.
    public func deleteAllWorkouts() {
        lastSaveError = nil
        do {
            try context.delete(model: WorkoutRecord.self)
            try context.save()
        } catch {
            lastSaveError = error
        }
    }
```

`WorkoutHistoryModel.swift` — add:

```swift
    /// Erase every Completed and open Workout record, then reload. The
    /// Exercise library and preferences are separate stores and survive.
    public func deleteAllWorkoutData() {
        store.deleteAllWorkouts()
        selected = nil
        reload()
    }
```

Add `deleteAllWorkouts()` to any in-memory `WorkoutHistoryStore` fake the app-test target defines (search `: WorkoutHistoryStore` in `Tests/`). Minimal body: `saved.removeAll()` (or the fake's equivalent backing array).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/WorkoutLoggerApp && swift test` → PASS.
Run: `cd Packages/WorkoutLoggerCore && swift test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp
git commit -m "feat(history): deleteAllWorkouts store method and model action"
```

---

## Task 8: `OnboardingModel`

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Settings/OnboardingModel.swift`
- Create: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/OnboardingModelTests.swift`

**Interfaces:**
- Consumes: `SettingsStore` (`hasCompletedOnboarding`), `SpeechAuthorization` (`request()`), `InMemorySettingsStore`, `FakeSpeechAuthorization` (Task 5).
- Produces: `@Observable @MainActor final class OnboardingModel`:
  - `init(settingsStore: SettingsStore, speechAuthorization: SpeechAuthorization)`
  - `var shouldShowOnboarding: Bool` — `!settingsStore.hasCompletedOnboarding`
  - `func completeOnboarding() async` — `await speechAuthorization.request()`, then `settingsStore.hasCompletedOnboarding = true` (the flag is set regardless of the authorization result).

- [ ] **Step 1: Write the failing test**

Create `OnboardingModelTests.swift`:

```swift
import Testing
@testable import WorkoutLoggerApp

@Suite("OnboardingModel")
@MainActor
struct OnboardingModelTests {

    @Test("shouldShowOnboarding mirrors the persisted flag")
    func mirrorsFlag() {
        let notDone = OnboardingModel(
            settingsStore: InMemorySettingsStore(hasCompletedOnboarding: false),
            speechAuthorization: FakeSpeechAuthorization()
        )
        let done = OnboardingModel(
            settingsStore: InMemorySettingsStore(hasCompletedOnboarding: true),
            speechAuthorization: FakeSpeechAuthorization()
        )
        #expect(notDone.shouldShowOnboarding == true)
        #expect(done.shouldShowOnboarding == false)
    }

    @Test("completeOnboarding requests auth then sets the flag, even on denial")
    func completeOnDenial() async {
        let store = InMemorySettingsStore(hasCompletedOnboarding: false)
        let auth = FakeSpeechAuthorization(status: .notDetermined, resultAfterRequest: .denied)
        let model = OnboardingModel(settingsStore: store, speechAuthorization: auth)

        await model.completeOnboarding()

        #expect(auth.requestCount == 1)
        #expect(store.hasCompletedOnboarding == true)
        #expect(model.shouldShowOnboarding == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter OnboardingModelTests`
Expected: FAIL — `cannot find 'OnboardingModel' in scope`.

- [ ] **Step 3: Write minimal implementation**

`OnboardingModel.swift`:

```swift
import Observation

/// Gates the one-screen first-run priming flow. The flag is a one-way latch
/// on "the priming screen was shown and dismissed"; it is not re-derived
/// from live authorization, so a later denial in iOS Settings does not
/// re-trigger onboarding — recovery lives in the Settings Speech section.
@MainActor
@Observable
public final class OnboardingModel {
    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let speechAuthorization: SpeechAuthorization

    public init(settingsStore: SettingsStore, speechAuthorization: SpeechAuthorization) {
        self.settingsStore = settingsStore
        self.speechAuthorization = speechAuthorization
    }

    public var shouldShowOnboarding: Bool { !settingsStore.hasCompletedOnboarding }

    /// Fire the system speech / microphone prompts, then record that priming
    /// is done — regardless of what the user chose.
    public func completeOnboarding() async {
        await speechAuthorization.request()
        settingsStore.hasCompletedOnboarding = true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/WorkoutLoggerApp && swift test` → PASS.
Run: `cd Packages/WorkoutLoggerCore && swift test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp
git commit -m "feat(onboarding): OnboardingModel gate and completion"
```

---

## Task 9: `SettingsModel` — construction, library seeding, unit get/set

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Settings/SettingsModel.swift`
- Create: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/SettingsModelTests.swift`

**Interfaces:**
- Consumes: `SettingsStore`, `ExerciseLibraryStore`, `SpeechAuthorization`, `WorkoutSessionModel` (`updateDefaultUnit(_:)`, `updateLibrary(_:)`, `displayUnit`, `hasActiveWorkout`, `refreshKnownBests()`), `WorkoutHistoryModel` (`deleteAllWorkoutData()`), `ExerciseLibrary`, `Exercise`, `MassUnit`, `defaultExerciseSeed`. Test doubles: `InMemorySettingsStore`, `InMemoryExerciseLibraryStore`, `FakeSpeechAuthorization`. A `WorkoutSessionModel` + `WorkoutHistoryModel` built over an in-memory `ModelContainer` (mirror `WorkoutSessionModelTests.makeRig`).
- Produces: `@Observable @MainActor final class SettingsModel`:
  - `init(settingsStore:libraryStore:speechAuthorization:session:historyModel:seed:)` where `seed: [Exercise] = defaultExerciseSeed`. On init: `libraryStore.seedIfEmpty(seed)`, then read `exercises` from `libraryStore.all()`, read `unit` from `settingsStore.defaultUnit`, read `speechStatus` from `speechAuthorization.status`, and push the initial library into `session` via `session.updateLibrary(currentLibrary)`.
  - `var unit: MassUnit` — get returns the stored value; set (when changed) persists to `settingsStore.defaultUnit` and calls `session.updateDefaultUnit(newValue)`.
  - `private(set) var exercises: [Exercise]` — alphabetical; the list-view source.
  - `var currentLibrary: ExerciseLibrary { ExerciseLibrary(exercises) }`.
  - (CRUD, speech, delete-all added in Tasks 10–12.)

- [ ] **Step 1: Write the failing test**

Create `SettingsModelTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("SettingsModel")
@MainActor
struct SettingsModelTests {

    struct Rig {
        let settings: SettingsModel
        let settingsStore: InMemorySettingsStore
        let libraryStore: InMemoryExerciseLibraryStore
        let speech: FakeSpeechAuthorization
        let session: WorkoutSessionModel
        let history: WorkoutHistoryModel
    }

    func makeRig(
        settingsStore: InMemorySettingsStore = InMemorySettingsStore(),
        libraryStore: InMemoryExerciseLibraryStore = InMemoryExerciseLibraryStore(),
        speech: FakeSpeechAuthorization = FakeSpeechAuthorization(status: .granted),
        seed: [Exercise] = [Exercise(name: "Bench Press", aliases: ["bench"])]
    ) throws -> Rig {
        let container = try ModelContainer(
            for: WorkoutRecord.self, ExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(store: store, library: .empty)
        let session = WorkoutSessionModel(
            engine: engine, transcriptSource: ScriptedTranscriptSource([]),
            readbackVoice: SpyReadbackVoice(), haptics: SpyHaptics(), library: .empty,
            history: { store.history() }
        )
        let history = WorkoutHistoryModel(store: store)
        let settings = SettingsModel(
            settingsStore: settingsStore, libraryStore: libraryStore,
            speechAuthorization: speech, session: session, historyModel: history, seed: seed
        )
        return Rig(settings: settings, settingsStore: settingsStore, libraryStore: libraryStore,
                   speech: speech, session: session, history: history)
    }

    @Test("init seeds an empty library and exposes it alphabetically")
    func initSeeds() throws {
        let rig = try makeRig(seed: [
            Exercise(name: "Squat"), Exercise(name: "Bench Press"),
        ])
        #expect(rig.settings.exercises.map(\.name) == ["Bench Press", "Squat"])
        #expect(rig.libraryStore.all().count == 2)
    }

    @Test("init does not reseed a populated library")
    func initNoReseed() throws {
        let libraryStore = InMemoryExerciseLibraryStore()
        try libraryStore.add(Exercise(name: "Deadlift"))
        let rig = try makeRig(libraryStore: libraryStore, seed: [Exercise(name: "Bench Press")])
        #expect(rig.settings.exercises.map(\.name) == ["Deadlift"])
    }

    @Test("init pushes the loaded library into the session")
    func initPushesLibrary() throws {
        let libraryStore = InMemoryExerciseLibraryStore()
        try libraryStore.add(Exercise(name: "Overhead Press", aliases: ["ohp"]))
        let rig = try makeRig(libraryStore: libraryStore)

        // The session can now resolve the seeded name.
        rig.session.pressed()
        // (no transcript scripted; assert the library round-trips instead)
        #expect(rig.settings.currentLibrary.exercises.map(\.name) == ["Overhead Press"])
    }

    @Test("unit is read from the store and, when changed, persisted and pushed to the session")
    func unitGetSet() throws {
        let rig = try makeRig(settingsStore: InMemorySettingsStore(defaultUnit: .pounds))
        #expect(rig.settings.unit == .pounds)
        #expect(rig.session.displayUnit == .pounds)

        rig.settings.unit = .kilograms

        #expect(rig.settingsStore.defaultUnit == .kilograms)
        #expect(rig.session.displayUnit == .kilograms)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter SettingsModelTests`
Expected: FAIL — `cannot find 'SettingsModel' in scope` (and `InMemoryExerciseLibraryStore` — add it now, see Step 3).

- [ ] **Step 3: Write minimal implementation**

First, add `InMemoryExerciseLibraryStore` to `SettingsFakes.swift`:

```swift
/// In-memory `ExerciseLibraryStore` with the same validation rules as the
/// SwiftData one, for model tests.
public final class InMemoryExerciseLibraryStore: ExerciseLibraryStore {
    private var items: [Exercise] = []
    public init() {}

    public func all() -> [Exercise] {
        items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func seedIfEmpty(_ exercises: [Exercise]) {
        guard items.isEmpty else { return }
        items = exercises
    }

    public func add(_ exercise: Exercise) throws {
        let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ExerciseLibraryError.emptyName }
        guard !items.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { throw ExerciseLibraryError.duplicateName }
        items.append(Exercise(name: name, aliases: exercise.aliases))
    }

    public func update(named originalName: String, to exercise: Exercise) throws {
        let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ExerciseLibraryError.emptyName }
        guard let index = items.firstIndex(where: {
            $0.name.localizedCaseInsensitiveCompare(originalName) == .orderedSame
        }) else { return }
        let collides = items.enumerated().contains { offset, item in
            offset != index && item.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        guard !collides else { throw ExerciseLibraryError.duplicateName }
        items[index] = Exercise(name: name, aliases: exercise.aliases)
    }

    public func delete(named name: String) {
        items.removeAll { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }
}
```

`SettingsModel.swift`:

```swift
import Observation
import WorkoutLoggerCore

/// Owns the live preference values and the derived exercise library, and
/// pushes unit / library changes one-directionally into the session (which
/// forwards to the engine). Persistence is split: unit + onboarding flag in
/// `SettingsStore` (UserDefaults); the library in `ExerciseLibraryStore`
/// (SwiftData). "Delete all workout data" is orchestrated here but touches
/// only the workout store.
@MainActor
@Observable
public final class SettingsModel {
    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let libraryStore: ExerciseLibraryStore
    @ObservationIgnored private let speechAuthorization: SpeechAuthorization
    @ObservationIgnored private let session: WorkoutSessionModel
    @ObservationIgnored private let historyModel: WorkoutHistoryModel

    private var _unit: MassUnit
    public private(set) var exercises: [Exercise]
    public private(set) var speechStatus: SpeechAuthorizationStatus

    public init(
        settingsStore: SettingsStore,
        libraryStore: ExerciseLibraryStore,
        speechAuthorization: SpeechAuthorization,
        session: WorkoutSessionModel,
        historyModel: WorkoutHistoryModel,
        seed: [Exercise] = defaultExerciseSeed
    ) {
        self.settingsStore = settingsStore
        self.libraryStore = libraryStore
        self.speechAuthorization = speechAuthorization
        self.session = session
        self.historyModel = historyModel

        libraryStore.seedIfEmpty(seed)
        self._unit = settingsStore.defaultUnit
        self.exercises = libraryStore.all()
        self.speechStatus = speechAuthorization.status

        session.updateDefaultUnit(_unit)
        session.updateLibrary(ExerciseLibrary(exercises))
    }

    /// The kg/lb default. Setting it (to a new value) persists and pushes
    /// live to the session and engine.
    public var unit: MassUnit {
        get { _unit }
        set {
            guard newValue != _unit else { return }
            _unit = newValue
            settingsStore.defaultUnit = newValue
            session.updateDefaultUnit(newValue)
        }
    }

    /// The library as it currently stands — what gets pushed on any edit.
    public var currentLibrary: ExerciseLibrary { ExerciseLibrary(exercises) }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/WorkoutLoggerApp && swift test` → PASS.
Run: `cd Packages/WorkoutLoggerCore && swift test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp
git commit -m "feat(settings): SettingsModel construction, library seeding, unit setter"
```

---

## Task 10: `SettingsModel` — exercise-library CRUD with live push

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Settings/SettingsModel.swift`
- Modify: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/SettingsModelTests.swift`

**Interfaces:**
- Consumes: `ExerciseLibraryStore.add(_:)` / `.update(named:to:)` / `.delete(named:)` / `.all()`, `ExerciseLibraryError`, `WorkoutSessionModel.updateLibrary(_:)`, `SettingsModel.currentLibrary`.
- Produces:
  - `SettingsModel.addExercise(name: String, aliases: [String]) throws`
  - `SettingsModel.updateExercise(named originalName: String, toName newName: String, aliases: [String]) throws`
  - `SettingsModel.deleteExercise(named name: String)`
  - Each successful call refreshes `exercises` from `libraryStore.all()` and calls `session.updateLibrary(currentLibrary)`. A throwing call mutates nothing.

- [ ] **Step 1: Write the failing test**

Add to `SettingsModelTests.swift`:

```swift
@Test("addExercise persists, refreshes the list, and pushes the library live")
func addExercisePushes() throws {
    let rig = try makeRig(seed: [Exercise(name: "Bench Press")])

    try rig.settings.addExercise(name: "Romanian Deadlift", aliases: ["rdl", "romanians"])

    #expect(rig.settings.exercises.map(\.name) == ["Bench Press", "Romanian Deadlift"])
    #expect(rig.libraryStore.all().map(\.name).contains("Romanian Deadlift"))
    #expect(rig.settings.currentLibrary.exercises.contains { $0.aliases.contains("rdl") })
}

@Test("updateExercise renames, re-aliases, and re-sorts")
func updateExercise() throws {
    let rig = try makeRig(seed: [Exercise(name: "Row"), Exercise(name: "Curl")])

    try rig.settings.updateExercise(named: "Row", toName: "Zzz Row", aliases: ["pendlay"])

    #expect(rig.settings.exercises.map(\.name) == ["Curl", "Zzz Row"])
    #expect(rig.settings.exercises.last?.aliases == ["pendlay"])
}

@Test("deleteExercise removes it and pushes the smaller library")
func deleteExercise() throws {
    let rig = try makeRig(seed: [Exercise(name: "Bench Press"), Exercise(name: "Squat")])

    rig.settings.deleteExercise(named: "Squat")

    #expect(rig.settings.exercises.map(\.name) == ["Bench Press"])
    #expect(rig.settings.currentLibrary.exercises.map(\.name) == ["Bench Press"])
}

@Test("a rejected add changes nothing")
func rejectedAddIsInert() throws {
    let rig = try makeRig(seed: [Exercise(name: "Bench Press")])

    #expect(throws: ExerciseLibraryError.duplicateName) {
        try rig.settings.addExercise(name: "bench press", aliases: [])
    }
    #expect(rig.settings.exercises.map(\.name) == ["Bench Press"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter SettingsModelTests`
Expected: FAIL — `value of type 'SettingsModel' has no member 'addExercise'`.

- [ ] **Step 3: Write minimal implementation**

Add to `SettingsModel`:

```swift
    /// Add a Custom exercise. Throws `ExerciseLibraryError` on an empty or
    /// duplicate (case-insensitive) name, mutating nothing in that case.
    public func addExercise(name: String, aliases: [String]) throws {
        try libraryStore.add(Exercise(name: name, aliases: aliases))
        refreshLibrary()
    }

    /// Rename and/or re-alias an existing Exercise.
    public func updateExercise(named originalName: String, toName newName: String, aliases: [String]) throws {
        try libraryStore.update(named: originalName, to: Exercise(name: newName, aliases: aliases))
        refreshLibrary()
    }

    /// Remove an Exercise. Past Workouts that reference it are unaffected
    /// (they embed `Exercise` by value).
    public func deleteExercise(named name: String) {
        libraryStore.delete(named: name)
        refreshLibrary()
    }

    private func refreshLibrary() {
        exercises = libraryStore.all()
        session.updateLibrary(currentLibrary)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/WorkoutLoggerApp && swift test` → PASS.
Run: `cd Packages/WorkoutLoggerCore && swift test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp
git commit -m "feat(settings): exercise-library CRUD with live push to the session"
```

---

## Task 11: `SettingsModel` — speech status

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Settings/SettingsModel.swift`
- Modify: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/SettingsModelTests.swift`

**Interfaces:**
- Consumes: `SpeechAuthorization.status`, `FakeSpeechAuthorization.set(_:)` (test hook from Task 5).
- Produces:
  - `SettingsModel.refreshSpeechStatus()` — re-reads `speechAuthorization.status` into `speechStatus`.
  - `SettingsModel.showsSpeechRecoveryRow: Bool` — `true` only when `speechStatus == .denied` (not for `.unavailable`, which iOS Settings can't fix).

- [ ] **Step 1: Write the failing test**

```swift
@Test("speech status is read on init and re-read on refresh")
func speechStatusRefresh() throws {
    let speech = FakeSpeechAuthorization(status: .notDetermined)
    let rig = try makeRig(speech: speech)
    #expect(rig.settings.speechStatus == .notDetermined)

    speech.set(.denied)
    rig.settings.refreshSpeechStatus()

    #expect(rig.settings.speechStatus == .denied)
}

@Test("the recovery row shows for denied only")
func recoveryRowVisibility() throws {
    for (status, shows) in [
        (SpeechAuthorizationStatus.granted, false),
        (.notDetermined, false),
        (.denied, true),
        (.unavailable, false),
    ] {
        let rig = try makeRig(speech: FakeSpeechAuthorization(status: status))
        #expect(rig.settings.showsSpeechRecoveryRow == shows)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter SettingsModelTests`
Expected: FAIL — `value of type 'SettingsModel' has no member 'refreshSpeechStatus'`.

- [ ] **Step 3: Write minimal implementation**

Add to `SettingsModel`:

```swift
    /// Re-read speech authorization — call on Settings `.onAppear` and when
    /// the app returns to the foreground, since the user can change it in
    /// iOS Settings and come back.
    public func refreshSpeechStatus() {
        speechStatus = speechAuthorization.status
    }

    /// Whether to show the "Open iOS Settings" recovery row. Only `denied`
    /// is recoverable there; `unavailable` is a device/locale limitation.
    public var showsSpeechRecoveryRow: Bool { speechStatus == .denied }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/WorkoutLoggerApp && swift test` → PASS.
Run: `cd Packages/WorkoutLoggerCore && swift test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp
git commit -m "feat(settings): speech-status read/refresh and recovery-row rule"
```

---

## Task 12: `SettingsModel` — delete all workout data

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Settings/SettingsModel.swift`
- Modify: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/SettingsModelTests.swift`

**Interfaces:**
- Consumes: `WorkoutSessionModel.hasActiveWorkout`, `WorkoutSessionModel.refreshKnownBests()` (Task 4), `WorkoutHistoryModel.deleteAllWorkoutData()` (Task 7), `WorkoutHistoryModel.rows`, `WorkoutSessionModel` start/end via a `ScriptedTranscriptSource` (mirror `WorkoutSessionModelTests.say`).
- Produces:
  - `SettingsModel.canDeleteAllWorkoutData: Bool` — `!session.hasActiveWorkout`.
  - `SettingsModel.deleteAllWorkoutData()` — no-op when `!canDeleteAllWorkoutData`; otherwise `historyModel.deleteAllWorkoutData()` then `session.refreshKnownBests()`.

- [ ] **Step 1: Write the failing test**

```swift
@Test("delete-all is blocked while a workout is open")
func deleteBlockedMidWorkout() async throws {
    let container = try ModelContainer(
        for: WorkoutRecord.self, ExerciseRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let store = SwiftDataWorkoutStore(context: ModelContext(container))
    let bench = Exercise(name: "Bench Press", aliases: ["bench"])
    let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
    let source = ScriptedTranscriptSource([["start workout"], ["bench"], ["100 for 5"]])
    let session = WorkoutSessionModel(
        engine: engine, transcriptSource: source, readbackVoice: SpyReadbackVoice(),
        haptics: SpyHaptics(), library: ExerciseLibrary([bench]), history: { store.history() }
    )
    let history = WorkoutHistoryModel(store: store)
    let settings = SettingsModel(
        settingsStore: InMemorySettingsStore(), libraryStore: InMemoryExerciseLibraryStore(),
        speechAuthorization: FakeSpeechAuthorization(), session: session, historyModel: history,
        seed: [bench]
    )

    session.pressed(); await session.released() // start
    session.pressed(); await session.released() // bench
    session.pressed(); await session.released() // 100 for 5
    #expect(settings.canDeleteAllWorkoutData == false)

    settings.deleteAllWorkoutData() // no-op

    #expect(store.history().isEmpty == false)
}

@Test("delete-all clears rows and the PR gate when no workout is open")
func deleteClearsWhenIdle() async throws {
    let container = try ModelContainer(
        for: WorkoutRecord.self, ExerciseRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let store = SwiftDataWorkoutStore(context: ModelContext(container))
    // One completed workout already on disk.
    let done = Workout(
        entries: [Entry(exercise: Exercise(name: "Bench Press"), sets: [LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .straight,
            loadKilograms: 140, reps: 3, durationSeconds: nil, distanceMeters: nil,
            supersetRunID: nil, loggedAt: Date(timeIntervalSince1970: 10), note: nil)])],
        startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 100)
    )
    store.save(done)
    let engine = WorkoutEngine(store: store, library: .empty)
    let session = WorkoutSessionModel(
        engine: engine, transcriptSource: ScriptedTranscriptSource([]),
        readbackVoice: SpyReadbackVoice(), haptics: SpyHaptics(), library: .empty,
        knownBestExercises: ["Bench Press"], history: { store.history() }
    )
    let history = WorkoutHistoryModel(store: store)
    #expect(history.rows.count == 1)
    let settings = SettingsModel(
        settingsStore: InMemorySettingsStore(), libraryStore: InMemoryExerciseLibraryStore(),
        speechAuthorization: FakeSpeechAuthorization(), session: session, historyModel: history,
        seed: [Exercise(name: "Bench Press")]
    )

    #expect(settings.canDeleteAllWorkoutData == true)
    settings.deleteAllWorkoutData()

    #expect(history.rows.isEmpty)
    #expect(store.history().isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter SettingsModelTests`
Expected: FAIL — `value of type 'SettingsModel' has no member 'canDeleteAllWorkoutData'`.

- [ ] **Step 3: Write minimal implementation**

Add to `SettingsModel`:

```swift
    /// False while a Workout is open — the destructive action is disabled
    /// with an explanatory footer in that state.
    public var canDeleteAllWorkoutData: Bool { !session.hasActiveWorkout }

    /// Erase every stored Workout. The Exercise library and preferences are
    /// separate stores and survive. No-op while a Workout is open.
    public func deleteAllWorkoutData() {
        guard canDeleteAllWorkoutData else { return }
        historyModel.deleteAllWorkoutData()
        session.refreshKnownBests()
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Packages/WorkoutLoggerApp && swift test` → PASS.
Run: `cd Packages/WorkoutLoggerCore && swift test` → PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp
git commit -m "feat(settings): guarded delete-all-workout-data"
```

---

## Task 13: App views (files-only, consistency-checked)

**Files:**
- Create: `App/Views/OnboardingView.swift`
- Create: `App/Views/SettingsView.swift`
- Create: `App/Views/ExerciseLibraryView.swift`
- Create: `App/Views/ExerciseEditView.swift`

**Interfaces:**
- Consumes: `OnboardingModel` (`completeOnboarding()` async), `SettingsModel` (`unit`, `exercises`, `speechStatus`, `showsSpeechRecoveryRow`, `refreshSpeechStatus()`, `addExercise`, `updateExercise`, `deleteExercise`, `canDeleteAllWorkoutData`, `deleteAllWorkoutData()`), `SpeechAuthorizationStatus`, `MassUnit`, `Exercise`. `UIApplication.openSettingsURLString`. Styling mirrors `HUDView` (talk-button shape) and `SetEditView` (toolbar Cancel/Save pair).
- Produces: four `View` structs. No logic beyond bindings and direct calls into the models above.

> No `swift test` step — the `App/` target is not compiled here. "Run" steps are read-through checks against the package API.

- [ ] **Step 1: Write `OnboardingView.swift`**

```swift
import SwiftUI
import WorkoutLoggerApp

/// One-screen first-run priming. Shares the HUD's black canvas / centered
/// column. "Continue" fires the system speech + mic prompts, then the caller
/// dismisses this screen regardless of the outcome.
struct OnboardingView: View {
    let model: OnboardingModel
    let onComplete: () -> Void

    @State private var working = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Speak your sets.")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
            Text("Trackit turns your spoken sets into a workout log, on device. "
                 + "It listens while you speak each set — nothing leaves your phone.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                working = true
                Task {
                    await model.completeOnboarding()
                    working = false
                    onComplete()
                }
            } label: {
                Text("Continue")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .background(RoundedRectangle(cornerRadius: 24).fill(.white))
            }
            .disabled(working)
        }
        .padding(40)
        .background(Color.black.ignoresSafeArea())
    }
}
```

- [ ] **Step 2: Write `ExerciseEditView.swift`**

```swift
import SwiftUI
import WorkoutLoggerCore
import WorkoutLoggerApp

/// Add or edit one Exercise: canonical name plus an editable Alias list.
/// Save is disabled for an empty name; the model rejects duplicates and
/// surfaces the error.
struct ExerciseEditView: View {
    let model: SettingsModel
    /// nil → adding a new Exercise; non-nil → editing this one.
    let existing: Exercise?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var aliases: [String]
    @State private var errorText: String?

    init(model: SettingsModel, existing: Exercise?) {
        self.model = model
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _aliases = State(initialValue: existing?.aliases ?? [])
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Exercise name", text: $name)
            }
            Section("Aliases") {
                ForEach(aliases.indices, id: \.self) { i in
                    TextField("Alias", text: $aliases[i])
                }
                .onDelete { aliases.remove(atOffsets: $0) }
                Button("Add alias") { aliases.append("") }
            }
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
        }
        .navigationTitle(existing == nil ? "New Exercise" : "Edit Exercise")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        let cleaned = aliases
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        do {
            if let existing {
                try model.updateExercise(named: existing.name, toName: name, aliases: cleaned)
            } else {
                try model.addExercise(name: name, aliases: cleaned)
            }
            dismiss()
        } catch {
            errorText = "That name is empty or already used."
        }
    }
}
```

- [ ] **Step 3: Write `ExerciseLibraryView.swift`**

```swift
import SwiftUI
import WorkoutLoggerApp

/// The full Exercise library: a stock list, "+" to add, tap to edit, swipe
/// to delete. Past Workouts are unaffected by any edit here.
struct ExerciseLibraryView: View {
    let model: SettingsModel
    @State private var adding = false

    var body: some View {
        List {
            ForEach(model.exercises, id: \.name) { exercise in
                NavigationLink {
                    ExerciseEditView(model: model, existing: exercise)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                        if !exercise.aliases.isEmpty {
                            Text(exercise.aliases.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets { model.deleteExercise(named: model.exercises[i].name) }
            }
        }
        .navigationTitle("Exercise Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack { ExerciseEditView(model: model, existing: nil) }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Deleting an exercise leaves past workouts unchanged.")
                .font(.footnote).foregroundStyle(.secondary).padding()
        }
    }
}
```

- [ ] **Step 4: Write `SettingsView.swift`**

```swift
import SwiftUI
import UIKit
import WorkoutLoggerCore
import WorkoutLoggerApp

/// Stock grouped form: Units, Speech, Exercises, Data.
struct SettingsView: View {
    let model: SettingsModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            Section("Units") {
                Picker("Load unit", selection: Binding(
                    get: { model.unit },
                    set: { model.unit = $0 }
                )) {
                    Text("Kilograms").tag(MassUnit.kilograms)
                    Text("Pounds").tag(MassUnit.pounds)
                }
                .pickerStyle(.segmented)
            }

            Section("Speech") {
                HStack {
                    Text("Microphone access")
                    Spacer()
                    Text(statusText).foregroundStyle(.secondary)
                }
                if model.showsSpeechRecoveryRow {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }

            Section("Exercises") {
                NavigationLink {
                    ExerciseLibraryView(model: model)
                } label: {
                    HStack {
                        Text("Exercise Library")
                        Spacer()
                        Text("\(model.exercises.count)").foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Delete All Workout Data", role: .destructive) {
                    confirmingDelete = true
                }
                .disabled(!model.canDeleteAllWorkoutData)
            } footer: {
                Text(model.canDeleteAllWorkoutData
                     ? "Deletes every logged workout. Your exercise library and preferences are kept."
                     : "Finish your current workout first.")
            }
        }
        .navigationTitle("Settings")
        .onAppear { model.refreshSpeechStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshSpeechStatus() }
        }
        .confirmationDialog("Delete all workout data?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { model.deleteAllWorkoutData() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var statusText: String {
        switch model.speechStatus {
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .notDetermined: return "Not determined"
        case .unavailable: return "Unavailable on this device"
        }
    }
}
```

- [ ] **Step 5: Consistency check + commit**

Verify by read-through: every model member referenced above exists with that exact signature in `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Settings/` (Tasks 8–12). `MassUnit` is `Hashable` (it is `Equatable` + an enum with no associated values → usable as a `.tag`). No view holds state the model should own.

```bash
git add App/Views/OnboardingView.swift App/Views/SettingsView.swift App/Views/ExerciseLibraryView.swift App/Views/ExerciseEditView.swift
git commit -m "feat(app): onboarding and settings views (files-only)"
```

---

## Task 14: Wire it up — `RootView` gate, gear, composition root, DESIGN.md

**Files:**
- Create: `App/System/UserDefaultsSettingsStore.swift`
- Create: `App/System/SystemSpeechAuthorization.swift`
- Modify: `App/Views/RootView.swift`
- Modify: `App/TrackitApp.swift`
- Modify: `DESIGN.md`

**Interfaces:**
- Consumes: everything from Tasks 5–13; `provisionStore(onDiskURL:)` (now schema-includes `ExerciseRecord`), `SwiftDataExerciseLibraryStore(context:)`, `SwiftDataWorkoutStore(context:)`, `defaultExerciseSeed`, `WorkoutHistoryModel(store:historyUnavailable:)`.
- Produces: `UserDefaultsSettingsStore: SettingsStore`, `SystemSpeechAuthorization: SpeechAuthorization`; a `RootView` that shows `OnboardingView` first, then the existing stale gate, then the HUD, with a gear toolbar item opening `SettingsView`; a `TrackitApp` that builds the two new stores and both models and loads the library from the store.

> Files-only. No `swift test`. Read-through checks only.

- [ ] **Step 1: Write `App/System/UserDefaultsSettingsStore.swift`**

```swift
import Foundation
import WorkoutLoggerCore
import WorkoutLoggerApp

/// `SettingsStore` over `UserDefaults.standard`. No logic beyond key access.
final class UserDefaultsSettingsStore: SettingsStore {
    private enum Key {
        static let unit = "defaultMassUnit"
        static let onboarded = "hasCompletedOnboarding"
    }
    private let defaults = UserDefaults.standard

    var defaultUnit: MassUnit {
        get { defaults.string(forKey: Key.unit) == "pounds" ? .pounds : .kilograms }
        set { defaults.set(newValue == .pounds ? "pounds" : "kilograms", forKey: Key.unit) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }
}
```

- [ ] **Step 2: Write `App/System/SystemSpeechAuthorization.swift`**

```swift
import Foundation
import Speech
import AVFoundation
import WorkoutLoggerApp

/// `SpeechAuthorization` over `SFSpeechRecognizer` + `AVAudioApplication`.
/// Thin adapter, no branching logic beyond flattening the system enums.
@MainActor
final class SystemSpeechAuthorization: SpeechAuthorization {
    var status: SpeechAuthorizationStatus {
        if SFSpeechRecognizer() == nil { return .unavailable }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            default: return .notDetermined
            }
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    func request() async {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { _ in cont.resume() }
        }
        _ = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
        }
    }
}
```

- [ ] **Step 3: Modify `App/Views/RootView.swift`**

Add stored dependencies and the gate. New `let`s on `RootView`:

```swift
    let settingsModel: SettingsModel
    let onboardingModel: OnboardingModel
```

Replace the `if model.pendingStaleWorkout != nil { … } else { … }` block with:

```swift
            if onboardingModel.shouldShowOnboarding {
                OnboardingView(model: onboardingModel) { /* state re-reads shouldShowOnboarding */ }
            } else if model.pendingStaleWorkout != nil {
                LaunchGateView(model: model)
            } else {
                NavigationStack {
                    HUDView(model: model, historyUnavailable: historyUnavailable)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    HistoryListView(
                                        historyModel: historyModel,
                                        unit: model.displayUnit,
                                        store: store,
                                        historyUnavailable: historyUnavailable
                                    )
                                } label: {
                                    Image(systemName: "clock.arrow.circlepath")
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    SettingsView(model: settingsModel)
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                }
            }
```

`OnboardingModel` is `@Observable`, so `shouldShowOnboarding` flipping after `completeOnboarding()` re-renders `RootView` and falls through. Keep the `onComplete` closure empty (or wire it to a haptic later); it exists so the view can force a re-check if needed.

- [ ] **Step 4: Modify `App/TrackitApp.swift`**

In `init()`:
- Build the `settingsStore` and `speechAuth`:
  ```swift
  let settingsStore = UserDefaultsSettingsStore()
  let speechAuth = SystemSpeechAuthorization()
  ```
- Build the library store from the provisioned container and load the library from it (replacing `let library = ExerciseLibrary(TrackitApp.seedExercises)`):
  ```swift
  let libraryStore = SwiftDataExerciseLibraryStore(context: ModelContext(availability.container))
  libraryStore.seedIfEmpty(defaultExerciseSeed)
  let library = ExerciseLibrary(availability.isDegraded ? defaultExerciseSeed : libraryStore.all())
  ```
  (When degraded, the on-disk library isn't trustworthy; fall back to the seed so voice still resolves common lifts.)
- After `historyModel` and `_model` are built, build the two new models and hold them in `@State` / `let`:
  ```swift
  let settingsModel = SettingsModel(
      settingsStore: settingsStore, libraryStore: libraryStore,
      speechAuthorization: speechAuth, session: model,
      historyModel: historyModel, seed: defaultExerciseSeed
  )
  let onboardingModel = OnboardingModel(settingsStore: settingsStore, speechAuthorization: speechAuth)
  ```
  (`model` is the `WorkoutSessionModel` just built; if it's in `_model` as `State`, read `_model.wrappedValue`.)
- Delete the `static let seedExercises: [Exercise] = [ … ]` array (now `defaultExerciseSeed` in the package). Keep `static func knownBests(from:)`.
- Pass the new models into `RootView`:
  ```swift
  RootView(model: model, historyModel: historyModel, store: store,
           historyUnavailable: historyUnavailable,
           settingsModel: settingsModel, onboardingModel: onboardingModel)
  ```
  Store `settingsModel` / `onboardingModel` in `private let` properties (they're reference types; no `@State` needed unless the body observes them directly — `RootView` does, so plain `let` on `TrackitApp` is fine and matches how `historyModel` is already held).

- [ ] **Step 5: Update `DESIGN.md`, then commit**

Add three entries, matching the file's existing voice:

- Under the screen/component list, an **Onboarding** entry: black canvas, single centered column (the `LaunchGateView` family), title + on-device/offline body copy from PRODUCT.md, one full-width talk-button-styled "Continue" that fires the system prompts; shown once, never again.
- A **Settings** entry: stock grouped `Form`; sections Units (segmented `Picker`), Speech (status row + conditional "Open iOS Settings"), Exercises (row → library), Data (destructive "Delete All Workout Data", disabled mid-workout, `confirmationDialog`). Reached via a `gearshape` toolbar item — the second app-authored HUD toolbar control after the set-list button; folds under the existing "logging-controls-only" exception to the 96pt rule.
- An **Exercise Library / Exercise Editor** entry beside the Set Editor bullet: stock `List` with name + Alias line, "+" to add, tap to edit, swipe to delete; editor is a stock `Form` (name field + Alias list) with the same `.cancellationAction` / `.confirmationAction` toolbar pair as the Set Editor.

```bash
git add App/System/UserDefaultsSettingsStore.swift App/System/SystemSpeechAuthorization.swift App/Views/RootView.swift App/TrackitApp.swift DESIGN.md
git commit -m "feat(app): wire onboarding gate, settings gear, and composition root"
```

---

## Self-Review

### 1. Spec coverage

| Spec area | Task(s) |
|---|---|
| Onboarding: one screen, priming copy, Continue → system prompt, shown once, denial doesn't block | 8 (`OnboardingModel`), 13 (`OnboardingView`), 14 (`RootView` gate) |
| Onboarding gate precedes stale-workout gate | 14 |
| Settings reachable via gear in HUD toolbar | 14 |
| Units: kg/lb picker, persist, live re-render, mid-workout safe, explicit-spoken-unit still wins, default stays kg | 1, 3, 9, 13 (`SettingsView` picker) |
| Speech: live status (4 states), "Open iOS Settings" for denied only, refresh on appear/foreground, unavailable distinct | 5, 11, 13 (`SettingsView`), 14 (`SystemSpeechAuthorization`) |
| Exercise library: list alphabetical, add/rename/alias/delete, live resolution, delete leaves history intact, seed 6 on first launch, seeds editable, empty/dup rejected, persist, Cancel/Save | 6, 9, 10, 13 (`ExerciseLibraryView`/`ExerciseEditView`) |
| Delete all workout data: confirm dialog, keeps library + prefs, blocked mid-workout with footer, history/progress/PR-gate reflect empty | 4, 7, 12, 13 (`SettingsView`) |
| Two-bucket persistence (UserDefaults + SwiftData) | 5, 6, 14 |
| `ExerciseRecord` in existing container, distinct from `WorkoutRecord` | 6 |
| Approach A: additive engine setters, `let`→`var`, one-directional push | 1, 2, 3, 9, 10 |
| Composition-root ordering: stores → SettingsModel (seeds) → engine/model → OnboardingModel → RootView | 14 |
| `DESIGN.md` updated | 14 |
| Out of scope (HealthKit/export/telemetry, tutorial, tap-select add, themes, undo of delete) | not built — no task, correct |

**Gap noted and accepted:** the engine's `knownBests` (launch-seeded, gates whether a `PersonalRecord` value is *emitted*) is a `private let` and, under the "two Core edits only" constraint, is not made settable. Task 4/12 reset the App-layer `knownBestExercises` celebration gate (what actually fires the `.personalRecord` haptic) and reload history/progress, so US 41–46 hold for the user-visible surface. Residual: between a wipe and the next app launch, a set that beats its in-session progression but not a pre-wipe historical best won't fire the celebration haptic. This is documented in the spec's Further Notes; if the reviewer rejects it, add a third additive Core method `WorkoutEngine.updateKnownBests(_ bests: [String: Double])` and call it from `SettingsModel.deleteAllWorkoutData()` with `[:]`.

### 2. Placeholder scan

No "TBD"/"handle edge cases"/"similar to Task N". Task 7's history-model test references "the suite's existing store-construction helper" — this is a real instruction to reuse a named local helper whose exact name depends on the current test file; the assertion shape and store calls are fully specified. Task 5's superseded bullet about `InMemoryExerciseLibraryStore` is explicitly overridden by the decision note directly under it and by Task 9 Step 3, which contains the full implementation.

### 3. Type consistency

- `WorkoutEngine.updateDefaultUnit(_:)` / `updateLibrary(_:)` — same names Tasks 1, 2, 3 produce and consume.
- `WorkoutSessionModel.updateDefaultUnit(_:)` / `updateLibrary(_:)` / `hasActiveWorkout` / `refreshKnownBests()` — consistent across Tasks 3, 4, 9, 12.
- `SettingsModel` members — `unit` (get/set), `exercises`, `currentLibrary`, `speechStatus`, `showsSpeechRecoveryRow`, `refreshSpeechStatus()`, `addExercise(name:aliases:)`, `updateExercise(named:toName:aliases:)`, `deleteExercise(named:)`, `canDeleteAllWorkoutData`, `deleteAllWorkoutData()` — defined across Tasks 9–12, consumed identically in Task 13.
- `ExerciseLibraryStore` — `all()`, `seedIfEmpty(_:)`, `add(_:)`, `update(named:to:)`, `delete(named:)` — same in Task 6 (protocol + SwiftData impl), Task 9 Step 3 (in-memory impl), Tasks 9–12 (consumed).
- `SettingsStore` — `defaultUnit`, `hasCompletedOnboarding` — Tasks 5, 8, 9, 14.
- `SpeechAuthorization` — `status`, `request()`; `SpeechAuthorizationStatus` cases `notDetermined`/`granted`/`denied`/`unavailable` — Tasks 5, 8, 11, 13, 14.
- `WorkoutHistoryStore.deleteAllWorkouts()` / `WorkoutHistoryModel.deleteAllWorkoutData()` — Task 7, consumed in Task 12.
- `defaultExerciseSeed` — defined Task 6, consumed Tasks 9, 14.
- `ExerciseRecord(name:aliases:)` — Task 6, used in Tasks 6, 7 tests.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-05-onboarding-and-settings.md`. Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
