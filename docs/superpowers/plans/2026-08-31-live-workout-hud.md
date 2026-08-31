# Live-workout HUD (subsystem C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the calm high-contrast active-workout HUD and the launch resume-or-discard flow for the trackit voice workout logger, and close three edges carried out of the A+B review.

**Architecture:** Everything with logic goes into `Packages/WorkoutLoggerApp` behind `swift test`: three new pure types (`HUDProjection`, `LaunchDecision` + `closeAbandonedWorkout`, `StoreProvisioning`) plus additive `WorkoutSessionModel` state and a stale-recovery seam. `WorkoutLoggerCore` gets exactly one narrow additive method — `WorkoutEngine.resume(_:)` — so a workout the user forgot to end can be adopted on launch. The `App/` Xcode target is rewritten from the placeholder into the real HUD but stays a thin renderer over `HUDProjection`; it is files-only and consistency-checked because this environment has no Xcode/xcodebuild.

**Tech Stack:** Swift 6 (language mode 6, strict concurrency complete), SwiftPM, Swift Testing (`@Test`/`@Suite`/`#expect`/`#require`), SwiftUI, SwiftData, Observation.

**Spec:** `docs/superpowers/specs/2026-08-31-live-workout-hud-design.md` (read it alongside this plan — the plan argues from it). Builds on `docs/superpowers/specs/2026-08-30-app-shell-skeleton-voice-pipeline-design.md`, subsystems A+B, merged at `8b0c7ca`.

## Global Constraints

- **`WorkoutLoggerCore` is frozen except one addition:** `WorkoutEngine.resume(_ workout: Workout)` in Task 3. No other core source edit. No change to any core value type, protocol, or existing method.
- **`swift test` must be green every cycle** in `Packages/WorkoutLoggerCore` (currently 97 tests / 10 suites) and `Packages/WorkoutLoggerApp` (currently 34 tests / 5 suites). Run the changed package's suite at every red and green step.
- **`swift build` must emit no new warnings** in either package, including under `-strict-concurrency=complete`.
- **This environment cannot run Xcode or `xcodebuild`.** `App/` (Task 7) is written and consistency-checked against the real package signatures only; its verification is "the files are complete and internally consistent", not a build.
- **`WorkoutLoggerApp` platforms:** `.iOS(.v17), .macOS(.v14)`. The 3 collaborator protocols (`TranscriptSource`, `ReadbackVoice`, `Haptics`) are `@MainActor`; `WorkoutSessionModel` is `@MainActor @Observable`; the core takes no Observation or SwiftData dependency.
- **Platform facts (from `specs/v1-voice-logging.md`):** native iOS, SwiftUI, iOS 17+, iPhone only, portrait only, dark theme only, on-device persistence via SwiftData, no backend, no accounts.
- **Stale-workout threshold default:** `6 * 60 * 60` seconds (6 hours).
- **TDD:** red before green; one vertical slice per red→green cycle; refactor is a separate committed step, never mixed into a red→green.
- **Commit message trailer** (every commit):
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
  ```

---

## File Structure

**New in `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/`:**

| Path | Responsibility |
|---|---|
| `Formatting/SetFormatting.swift` | `numberString(_:)` (shared whole-number rule, extracted from `ReadbackComposer`) and `formattedSetLine(_:unit:)` (one display line per logged set, unit-aware, warmup/superset/dropset markers). |
| `HUD/HUDProjection.swift` | `HUDProjection` value type — the exact glanceable fields the HUD renders, built from a `WorkoutSessionModel` snapshot. All formatting/fallback logic lives here so the SwiftUI view is a dumb renderer. |
| `HUD/LaunchDecision.swift` | `LaunchDecision` enum, `launchDecision(openWorkout:now:staleAfter:)`, and `closeAbandonedWorkout(_:in:)`. |
| `HUD/StoreProvisioning.swift` | `StoreAvailability` enum and `provisionStore(onDiskURL:)` — on-disk container or in-memory `.degraded` fallback. |

**Modified in `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/`:**

| Path | Change |
|---|---|
| `Session/WorkoutSessionModel.swift` | Additive: `displayUnit`, `restTargetSeconds`, `isRestTargetReached`, `keepScreenAwake`; `knownBestExercises` init param + genuine-PR haptic gate; `announcedThisWorkout` seeding when constructed over a workout in progress; `StaleWorkoutRecovery` seam + `pendingStaleWorkout` + `resumePendingStaleWorkout()` / `discardPendingStaleWorkout()`. |
| `Readback/ReadbackComposer.swift` | `number(_:)` now delegates to the shared `numberString(_:)`. No behaviour change. |

**Modified in `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/`:**

| Path | Change |
|---|---|
| `WorkoutEngine.swift` | Add one method: `public func resume(_ workout: Workout)`. |

**New/modified test files:**

- `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/HUDProjectionTests.swift` (new)
- `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/LaunchDecisionTests.swift` (new)
- `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/StoreProvisioningTests.swift` (new)
- `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift` (extended in Tasks 1 and 4)
- `Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutEngineTests.swift` (extended in Task 3)

**`App/` (Task 7, files-only):** rewrite `TrackitApp.swift`, `Views/RootView.swift`; add `Views/HUDView.swift`, `Views/SetListSheet.swift`, `Views/TapSelectSheet.swift`, `Views/LaunchGateView.swift`.

**Docs (Task 8):** `Packages/WorkoutLoggerCore/specs/v1-voice-logging.md`, `~/.claude/projects/-Users-Apple-projects-trackit/memory/phase-progress.md` (outside the repo, not committed).

---

## Reference: current signatures the plan builds against

From `WorkoutLoggerCore` (all `public`):

```swift
struct Workout: Equatable, Sendable, Codable {
    var entries: [Entry]; var startedAt: Date; var endedAt: Date?; var note: String?
    var isEnded: Bool { endedAt != nil }
    var lastActivityAt: Date            // latest of startedAt / last set loggedAt / endedAt
    func isStale(now: Date, staleAfter threshold: TimeInterval) -> Bool   // now - lastActivityAt > threshold
    init(entries: [Entry] = [], startedAt: Date, endedAt: Date? = nil, note: String? = nil)
}
struct Entry: Equatable, Sendable, Codable { var exercise: Exercise; var sets: [LoggedSet]; init(exercise:sets:[]) }
struct LoggedSet: Equatable, Sendable, Codable {
    var loadType: LoadType; var effort: EffortMeasure; var role: SetRole; var grouping: Grouping
    var loadKilograms: Double?; var reps: Int?; var durationSeconds: Int?; var distanceMeters: Double?
    var supersetRunID: Int?; var loggedAt: Date; var note: String?
    init(loadType:effort:role:grouping:loadKilograms:nil,reps:nil,durationSeconds:nil,distanceMeters:nil,supersetRunID:nil,loggedAt:note:nil)
}
enum MassUnit { case kilograms, pounds }        // + LoadType/EffortMeasure/SetRole/Grouping per CONTEXT.md
struct PersonalRecord: Equatable, Sendable, Codable { let exercise: Exercise; let estimatedOneRepMaxKilograms: Double }
func estimatedOneRepMax(loadKilograms: Double, reps: Int) -> Double     // Epley
final class WorkoutEngine {
    static let defaultRestTargetSeconds: TimeInterval = 120
    private(set) var workout: Workout?
    private(set) var personalRecords: [PersonalRecord]
    private(set) var restStartedAt: Date?
    var restElapsedSeconds: TimeInterval? ; var currentRestTargetSeconds: TimeInterval ; var isRestTargetReached: Bool
    init(store: WorkoutStore, library: ExerciseLibrary, unit: MassUnit = .kilograms,
         knownBests: [String: Double] = [:], restTarget: TimeInterval = defaultRestTargetSeconds,
         now: @escaping () -> Date = Date.init)
    func startWorkout() ; func startWorkout(from: WorkoutTemplate) ; func endWorkout() ; func hear(_ hypotheses: [String])
}
protocol WorkoutStore: AnyObject { func save(_ workout: Workout) }
```

From `WorkoutLoggerApp` (all `public`):

```swift
enum ReadbackPlan: Equatable, Sendable { case speak(String), earcon }
enum HapticCue: Equatable, Sendable { case logged, notCaught, personalRecord, restReached, none }
@MainActor protocol TranscriptSource: AnyObject { func beginUtterance(); func endUtterance() async throws -> [String] }
@MainActor protocol ReadbackVoice: AnyObject { func perform(_ plan: ReadbackPlan) }
@MainActor protocol Haptics: AnyObject { func play(_ cue: HapticCue) }
final class ScriptedTranscriptSource: TranscriptSource { init(_ queue: [[String]]); var throwWhenExhausted: Bool; var beganCount: Int; enum Failure: Error { case exhausted } }
final class SpyReadbackVoice: ReadbackVoice { var performed: [ReadbackPlan]; init() }
final class SpyHaptics: Haptics { var played: [HapticCue]; init() }
final class SwiftDataWorkoutStore: WorkoutStore {
    init(context: ModelContext)
    var lastSaveError: Error? ; var decodeFailureCount: Int
    func save(_ workout: Workout) ; func history() -> [Workout] ; func openWorkout() -> Workout?
}
@MainActor @Observable final class WorkoutSessionModel {
    private(set) var workout: Workout? ; private(set) var personalRecords: [PersonalRecord]
    private(set) var restStartedAt: Date? ; private(set) var restElapsed: TimeInterval
    private(set) var isListening: Bool ; private(set) var tapSelectCandidates: [Exercise]?
    private(set) var lastReadback: ReadbackPlan?
    init(engine:transcriptSource:readbackVoice:haptics:library:unit: MassUnit = .kilograms,
         capReadbackAtEarcon: Bool = false, now: @escaping () -> Date = Date.init)
    func pressed() ; func released() async ; func resolveTapSelect(_ exercise: Exercise) ; func tick()
}
func readbackPlan(for: ParseResult, style: ReadbackStyle, exerciseName: String?) -> ReadbackPlan
```

The existing `WorkoutSessionModelTests` `Rig` helper builds `ModelContainer(for: WorkoutRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))` → `SwiftDataWorkoutStore` → `WorkoutEngine` → `ScriptedTranscriptSource`/`SpyReadbackVoice`/`SpyHaptics` → `WorkoutSessionModel`, with `say(_:)` = `pressed()` then `await released()`.

---

### Task 1: `WorkoutSessionModel` — HUD state fields

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift`
- Modify: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift`

**Interfaces:**
- Consumes: `WorkoutEngine.currentRestTargetSeconds: TimeInterval`, `WorkoutEngine.isRestTargetReached: Bool`, `Workout.isEnded: Bool`, `MassUnit`.
- Produces (new `public` surface on `WorkoutSessionModel`, all `@MainActor`):
  - `var displayUnit: MassUnit` — the unit the HUD formats loads in (surfaces the existing private `unit`).
  - `private(set) var restTargetSeconds: TimeInterval` — snapshot of `engine.currentRestTargetSeconds`.
  - `private(set) var isRestTargetReached: Bool` — snapshot of `engine.isRestTargetReached`, refreshed in `tick()`.
  - `var keepScreenAwake: Bool` — `true` while a workout is open (`workout != nil && workout?.isEnded == false`).

- [ ] **Step 1: Add a `unit` parameter to the test `Rig` builder**

In `WorkoutSessionModelTests.swift`, change `makeRig` to thread a unit through both the engine and the model. Replace the `makeRig` signature and the two construction sites:

```swift
    private func makeRig(
        script: [[String]],
        capAtEarcon: Bool = false,
        knownBests: [String: Double] = [:],
        unit: MassUnit = .kilograms,
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }
    ) throws -> Rig {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(
            store: store, library: Self.library, unit: unit, knownBests: knownBests, now: now
        )
        let source = ScriptedTranscriptSource(script)
        let voice = SpyReadbackVoice()
        let haptics = SpyHaptics()
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: source, readbackVoice: voice,
            haptics: haptics, library: Self.library, unit: unit,
            capReadbackAtEarcon: capAtEarcon, now: now
        )
        return Rig(model: model, source: source, voice: voice, haptics: haptics)
    }
```

- [ ] **Step 2: Write the failing tests**

Append to `WorkoutSessionModelTests.swift`:

```swift
    @Test("displayUnit surfaces the injected unit")
    func displayUnitSurfacesInjectedUnit() throws {
        #expect(try makeRig(script: []).model.displayUnit == .kilograms)
        #expect(try makeRig(script: [], unit: .pounds).model.displayUnit == .pounds)
    }

    @Test("keepScreenAwake is true only while a workout is open")
    func keepScreenAwakeReflectsOpenWorkout() async throws {
        let rig = try makeRig(script: [["start workout"], ["end workout"]])
        #expect(rig.model.keepScreenAwake == false)
        await say(rig)
        #expect(rig.model.keepScreenAwake == true)
        await say(rig)
        #expect(rig.model.keepScreenAwake == false)
    }

    @Test("restTargetSeconds and isRestTargetReached track the engine")
    func restTargetFieldsTrackEngine() async throws {
        var clock = Date(timeIntervalSince1970: 1_000)
        let rig = try makeRig(
            script: [["start workout"], ["bench 100 for 5"]], now: { clock }
        )
        await say(rig); await say(rig)
        #expect(rig.model.restTargetSeconds == 120)
        #expect(rig.model.isRestTargetReached == false)

        clock = Date(timeIntervalSince1970: 1_200) // 200s > 120
        rig.model.tick()
        #expect(rig.model.isRestTargetReached == true)
    }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSessionModelTests`
Expected: FAIL — `value of type 'WorkoutSessionModel' has no member 'displayUnit'` / `'keepScreenAwake'` / `'restTargetSeconds'` / `'isRestTargetReached'`.

- [ ] **Step 4: Add the fields to `WorkoutSessionModel`**

In `WorkoutSessionModel.swift`, add to the observed-state block (after `lastReadback`):

```swift
    /// The rest target the timer counts toward right now — the active exercise's
    /// template value if one is armed, else the engine default. For a "1:23 / 2:00"
    /// style display.
    public private(set) var restTargetSeconds: TimeInterval = WorkoutEngine.defaultRestTargetSeconds
    /// Whether the current rest has reached its target. Snapshot of the engine,
    /// refreshed on every `tick()` because it moves with the clock.
    public private(set) var isRestTargetReached = false
```

Add computed accessors (place them just after the initializer):

```swift
    /// The unit the HUD formats loads in — the injected preference.
    public var displayUnit: MassUnit { unit }

    /// True while a workout is open; the view maps it to `isIdleTimerDisabled`.
    public var keepScreenAwake: Bool {
        guard let workout else { return false }
        return !workout.isEnded
    }
```

In `syncFromEngine()`, add:

```swift
        restTargetSeconds = engine.currentRestTargetSeconds
        isRestTargetReached = engine.isRestTargetReached
```

In `tick()`, refresh the reached flag from the clock. Replace the body with:

```swift
    public func tick() {
        guard let startedAt = restStartedAt else {
            restElapsed = 0
            isRestTargetReached = false
            return
        }
        restElapsed = now().timeIntervalSince(startedAt)
        isRestTargetReached = engine.isRestTargetReached
        if engine.isRestTargetReached, !restReachedFired {
            restReachedFired = true
            haptics.play(.restReached)
        }
    }
```

- [ ] **Step 5: Run the whole app suite to verify green**

Run: `cd Packages/WorkoutLoggerApp && swift test`
Expected: PASS — all suites green (34 existing + 3 new).
Run: `cd Packages/WorkoutLoggerApp && swift build 2>&1 | grep -i warning` → no output.

- [ ] **Step 6: Commit**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerApp
git commit -m "WorkoutLoggerApp: surface rest-target, unit, and keep-awake state on the session model

Additive observed fields the HUD needs: displayUnit, restTargetSeconds,
isRestTargetReached (refreshed in tick()), keepScreenAwake. No behaviour change.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 2: `HUDProjection` + shared set formatting

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Formatting/SetFormatting.swift`
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/HUD/HUDProjection.swift`
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Readback/ReadbackComposer.swift`
- Create: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/HUDProjectionTests.swift`

**Interfaces:**
- Consumes: `WorkoutSessionModel` (`workout`, `restStartedAt`, `restElapsed`, `isRestTargetReached`, `isListening`, `tapSelectCandidates`, `displayUnit` from Task 1); `LoggedSet`, `MassUnit`, `SetRole`, `Grouping`, `EffortMeasure`, `Exercise`.
- Produces:
  - `func numberString(_ value: Double) -> String` — whole numbers as `"100"`, fractional as `"2.5"`.
  - `func formattedSetLine(_ set: LoggedSet, unit: MassUnit) -> String` — one display line.
  - `struct HUDProjection: Equatable, Sendable` with fields `exerciseName: String`, `lastSetLine: String?`, `restLine: String?`, `restTargetReached: Bool`, `isListening: Bool`, `currentEntrySetLines: [String]`, `tapSelectCandidates: [Exercise]?`; a memberwise `init`; and `@MainActor init(from model: WorkoutSessionModel)`.

- [ ] **Step 1: Write the failing tests for `numberString` + `formattedSetLine`**

Create `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/HUDProjectionTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("Set formatting")
struct SetFormattingTests {

    private func set(
        effort: EffortMeasure = .reps, role: SetRole = .working, grouping: Grouping = .straight,
        kg: Double? = nil, reps: Int? = nil, seconds: Int? = nil, metres: Double? = nil
    ) -> LoggedSet {
        LoggedSet(
            loadType: .external, effort: effort, role: role, grouping: grouping,
            loadKilograms: kg, reps: reps, durationSeconds: seconds, distanceMeters: metres,
            loggedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("numberString drops a trailing .0 but keeps real fractions")
    func numberStringRule() {
        #expect(numberString(100) == "100")
        #expect(numberString(2.5) == "2.5")
        #expect(numberString(99.99999999999999) == "100")   // float slop from unit conversion
    }

    @Test("a rep set with load renders load, unit, and reps")
    func repsWithLoad() {
        #expect(formattedSetLine(set(kg: 100, reps: 5), unit: .kilograms) == "100 kg × 5")
    }

    @Test("pounds preference converts the stored kilograms back")
    func poundsConversion() {
        // 100 lb spoken -> engine stores 100 * 0.45359237 kg -> shown back as "100 lb"
        let stored = 100 * 0.45359237
        #expect(formattedSetLine(set(kg: stored, reps: 5), unit: .pounds) == "100 lb × 5")
    }

    @Test("a loadless rep set renders just the reps")
    func bodyweightReps() {
        #expect(formattedSetLine(set(kg: nil, reps: 12), unit: .kilograms) == "12 reps")
    }

    @Test("warmup and grouping markers are appended")
    func markers() {
        #expect(formattedSetLine(set(role: .warmup, kg: 60, reps: 10), unit: .kilograms) == "warm-up 60 kg × 10")
        #expect(formattedSetLine(set(grouping: .superset, kg: 100, reps: 5), unit: .kilograms) == "100 kg × 5 · superset")
        #expect(formattedSetLine(set(grouping: .dropset, kg: 80, reps: 8), unit: .kilograms) == "80 kg × 8 · dropset")
    }

    @Test("duration and distance efforts render their own units")
    func timedAndDistance() {
        #expect(formattedSetLine(set(effort: .duration, seconds: 45), unit: .kilograms) == "45s")
        #expect(formattedSetLine(set(effort: .distance, metres: 400), unit: .kilograms) == "400 m")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter SetFormattingTests`
Expected: FAIL — `cannot find 'numberString' in scope` / `cannot find 'formattedSetLine' in scope`.

- [ ] **Step 3: Create `SetFormatting.swift`**

Create `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Formatting/SetFormatting.swift`:

```swift
import Foundation
import WorkoutLoggerCore

/// Whole numbers without a trailing `.0` (`100`), real fractions kept (`2.5`).
/// The single rule for every prominent number the app shows or speaks.
func numberString(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
}

private let kilogramsPerPound = 0.45359237

/// Rounds to one decimal place, absorbing the float slop a kg↔lb conversion
/// leaves behind before `numberString` decides whole-vs-fraction.
private func gymRound(_ value: Double) -> Double {
    (value * 10).rounded() / 10
}

/// One display line for a logged set: load + unit + reps (or reps alone, or a
/// timed / distance value), a `warm-up ` prefix for warmups, and a
/// ` · superset` / ` · dropset` suffix for grouped sets.
func formattedSetLine(_ set: LoggedSet, unit: MassUnit) -> String {
    var line: String
    switch set.effort {
    case .reps:
        let reps = set.reps ?? 0
        if let kg = set.loadKilograms, kg > 0 {
            let shown = gymRound(unit == .pounds ? kg / kilogramsPerPound : kg)
            let word = unit == .pounds ? "lb" : "kg"
            line = "\(numberString(shown)) \(word) × \(reps)"
        } else {
            line = "\(reps) reps"
        }
    case .duration:
        line = "\(set.durationSeconds ?? 0)s"
    case .distance:
        line = "\(numberString(gymRound(set.distanceMeters ?? 0))) m"
    }
    if set.role == .warmup { line = "warm-up " + line }
    switch set.grouping {
    case .superset: line += " · superset"
    case .dropset:  line += " · dropset"
    case .straight: break
    }
    return line
}
```

- [ ] **Step 4: Run to verify the formatting tests pass**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter SetFormattingTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Point `ReadbackComposer` at the shared helper (refactor, no behaviour change)**

In `Readback/ReadbackComposer.swift`, replace the private `number(_:)` body so it delegates:

```swift
private func number(_ value: Double) -> String {
    numberString(value)
}
```

Run: `cd Packages/WorkoutLoggerApp && swift test --filter "Readback composer"`
Expected: PASS — the composer suite is unchanged.

- [ ] **Step 6: Write the failing `HUDProjection` tests**

Append to `HUDProjectionTests.swift`:

```swift
@Suite("HUDProjection")
@MainActor
struct HUDProjectionTests {

    private static let bench = Exercise(name: "Bench Press", aliases: ["bench"])
    private static let library = ExerciseLibrary([bench])

    private struct Rig { let model: WorkoutSessionModel; let source: ScriptedTranscriptSource }

    private func makeRig(
        script: [[String]], unit: MassUnit = .kilograms,
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }
    ) throws -> Rig {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(store: store, library: Self.library, unit: unit, now: now)
        let source = ScriptedTranscriptSource(script)
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: source, readbackVoice: SpyReadbackVoice(),
            haptics: SpyHaptics(), library: Self.library, unit: unit, now: now
        )
        return Rig(model: model, source: source)
    }

    private func say(_ rig: Rig) async { rig.model.pressed(); await rig.model.released() }

    @Test("a fresh model projects placeholders")
    func freshModel() throws {
        let p = HUDProjection(from: try makeRig(script: []).model)
        #expect(p.exerciseName == "No exercise yet")
        #expect(p.lastSetLine == nil)
        #expect(p.restLine == nil)
        #expect(p.currentEntrySetLines.isEmpty)
        #expect(p.tapSelectCandidates == nil)
    }

    @Test("after a set the projection shows the exercise and the formatted line")
    func afterASet() async throws {
        let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"]])
        await say(rig); await say(rig)
        let p = HUDProjection(from: rig.model)
        #expect(p.exerciseName == "Bench Press")
        #expect(p.lastSetLine == "100 kg × 5")
        #expect(p.currentEntrySetLines == ["100 kg × 5"])
    }

    @Test("a pounds model renders the last set in pounds")
    func poundsModel() async throws {
        let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"]], unit: .pounds)
        await say(rig); await say(rig)
        #expect(HUDProjection(from: rig.model).lastSetLine == "100 lb × 5")
    }

    @Test("restLine counts up mm:ss and restTargetReached flips past the target")
    func restLine() async throws {
        var clock = Date(timeIntervalSince1970: 1_000)
        let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"]], now: { clock })
        await say(rig); await say(rig)

        clock = Date(timeIntervalSince1970: 1_065) // 1:05
        rig.model.tick()
        var p = HUDProjection(from: rig.model)
        #expect(p.restLine == "1:05")
        #expect(p.restTargetReached == false)

        clock = Date(timeIntervalSince1970: 1_130) // past the 120s default
        rig.model.tick()
        p = HUDProjection(from: rig.model)
        #expect(p.restTargetReached == true)
    }

    @Test("the swipe-up list carries warmup and superset markers")
    func setListMarkers() async throws {
        let rig = try makeRig(script: [
            ["start workout"], ["warmup bench 60 for 10"],
            ["superset"], ["bench 100 for 5"], ["end superset"],
        ])
        for _ in 0..<5 { await say(rig) }
        let lines = HUDProjection(from: rig.model).currentEntrySetLines
        #expect(lines.count == 2)
        #expect(lines[0] == "warm-up 60 kg × 10")
        #expect(lines[1] == "100 kg × 5 · superset")
    }

    @Test("low-confidence input surfaces tap-select candidates on the projection")
    func tapSelectPassThrough() async throws {
        let rig = try makeRig(script: [["start workout"], ["flurbo"]])
        await say(rig); await say(rig)
        #expect(HUDProjection(from: rig.model).tapSelectCandidates != nil)
    }
}
```

> If `"warmup bench 60 for 10"` does not produce a warmup `.set` through the real parser, adjust the phrase to whatever the parser accepts for a warmup rep set (check `Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/ParserTests.swift` for the warmup grammar) and keep the assertion on the `"warm-up "` prefix.

- [ ] **Step 7: Run to verify failure**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter HUDProjection`
Expected: FAIL — `cannot find 'HUDProjection' in scope`.

- [ ] **Step 8: Create `HUDProjection.swift`**

Create `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/HUD/HUDProjection.swift`:

```swift
import Foundation
import WorkoutLoggerCore

/// The exact set of glanceable fields the live-workout HUD renders, derived from
/// a `WorkoutSessionModel` snapshot. All fallback and formatting logic lives here
/// so the SwiftUI view is a dumb renderer — and so every rule is `swift test`ed.
public struct HUDProjection: Equatable, Sendable {
    public var exerciseName: String
    public var lastSetLine: String?
    public var restLine: String?
    public var restTargetReached: Bool
    public var isListening: Bool
    public var currentEntrySetLines: [String]
    public var tapSelectCandidates: [Exercise]?

    public init(
        exerciseName: String,
        lastSetLine: String?,
        restLine: String?,
        restTargetReached: Bool,
        isListening: Bool,
        currentEntrySetLines: [String],
        tapSelectCandidates: [Exercise]?
    ) {
        self.exerciseName = exerciseName
        self.lastSetLine = lastSetLine
        self.restLine = restLine
        self.restTargetReached = restTargetReached
        self.isListening = isListening
        self.currentEntrySetLines = currentEntrySetLines
        self.tapSelectCandidates = tapSelectCandidates
    }

    @MainActor
    public init(from model: WorkoutSessionModel) {
        let entry = model.workout?.entries.last
        let unit = model.displayUnit
        exerciseName = entry?.exercise.name ?? "No exercise yet"
        lastSetLine = entry?.sets.last.map { formattedSetLine($0, unit: unit) }
        restLine = model.restStartedAt == nil ? nil : HUDProjection.clock(model.restElapsed)
        restTargetReached = model.isRestTargetReached
        isListening = model.isListening
        currentEntrySetLines = (entry?.sets ?? []).map { formattedSetLine($0, unit: unit) }
        tapSelectCandidates = model.tapSelectCandidates
    }

    /// `m:ss` count-up. Negative / sub-second clamps to `0:00`.
    static func clock(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 9: Run the whole app suite**

Run: `cd Packages/WorkoutLoggerApp && swift test`
Expected: PASS — all suites green.
Run: `cd Packages/WorkoutLoggerApp && swift build 2>&1 | grep -i warning` → no output.

- [ ] **Step 10: Commit**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerApp
git commit -m "WorkoutLoggerApp: HUDProjection + shared set-line formatting

HUDProjection maps a WorkoutSessionModel snapshot to the HUD's glanceable
fields (exercise, last-set line, mm:ss rest, target-reached, set list,
tap-select). numberString() is extracted to Formatting/ and reused by
ReadbackComposer. formattedSetLine() is unit-aware with warmup/grouping markers.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 3: `WorkoutEngine.resume(_:)` — adopt an unfinished workout

**Files:**
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift`
- Modify: `Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutEngineTests.swift`

**Interfaces:**
- Consumes: `Workout`, `Entry`, `LoggedSet`, `estimatedOneRepMax(loadKilograms:reps:)`, the engine's existing private state (`workout`, `activeEntryIndex`, `personalRecords`, `bestOneRepMax`, `knownBests`, `restStartedAt`, `retryTarget`, `currentSupersetRunID`, `supersetRunCount`, `templateRestTargets`, `store`).
- Produces: `public func resume(_ workout: Workout)` on `WorkoutEngine`. After it returns, the engine treats `workout` exactly as a freshly started one: `hear`, `undo`, rest, PR detection all operate on it. `restStartedAt` is `nil` (no rest survives a relaunch). `personalRecords` is `[]`. The PR bar is `knownBests` folded with the resumed workout's own working sets. A no-op if `workout.isEnded`.

- [ ] **Step 1: Write the failing tests**

Append to `WorkoutEngineTests.swift` (before the `InMemoryWorkoutStore` definition at the end):

```swift
    // MARK: - resume(_:)

    private func benchWorkout(
        startedAt: Date = Date(timeIntervalSince1970: 0),
        sets: [LoggedSet]
    ) -> Workout {
        Workout(
            entries: [Entry(exercise: Exercise(name: "Barbell Bench Press", aliases: ["bench"]), sets: sets)],
            startedAt: startedAt
        )
    }

    private func workingSet(
        kg: Double, reps: Int, at t: TimeInterval, run: Int? = nil
    ) -> LoggedSet {
        LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: run == nil ? .straight : .superset,
            loadKilograms: kg, reps: reps, supersetRunID: run, loggedAt: Date(timeIntervalSince1970: t)
        )
    }

    @Test("resume adopts an unfinished workout and new sets attach to its last entry")
    func resumeAttachesNewSets() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        let prior = benchWorkout(sets: [workingSet(kg: 100, reps: 5, at: 10)])

        engine.resume(prior)
        engine.hear(["100 for 3"]) // bare set — attaches to the adopted active entry

        #expect(engine.workout?.entries.count == 1)
        #expect(engine.workout?.entries.first?.sets.count == 2)
        #expect(engine.workout?.entries.first?.sets.last?.reps == 3)
        #expect(store.saved.last?.entries.first?.sets.count == 2)
    }

    @Test("resume then undo drops the last pre-existing set")
    func resumeThenUndo() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.resume(benchWorkout(sets: [
            workingSet(kg: 100, reps: 5, at: 10), workingSet(kg: 100, reps: 5, at: 200),
        ]))

        engine.hear(["undo"])

        #expect(engine.workout?.entries.first?.sets.count == 1)
    }

    @Test("resume does not re-celebrate history; a set below the in-workout best is no PR, above it is")
    func resumePersonalRecordBar() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        // existing set: e1RM(100,5) = 100 * 35 / 30 ≈ 116.67
        engine.resume(benchWorkout(sets: [workingSet(kg: 100, reps: 5, at: 10)]))
        #expect(engine.personalRecords.isEmpty)

        engine.hear(["90 for 5"]) // e1RM ≈ 105 — below
        #expect(engine.personalRecords.isEmpty)

        engine.hear(["120 for 5"]) // e1RM = 140 — above
        #expect(engine.personalRecords.count == 1)
        #expect(engine.personalRecords.first?.exercise == bench)
    }

    @Test("resume clears any pre-relaunch rest; rest restarts from the next set")
    func resumeClearsRest() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        var clock = Date(timeIntervalSince1970: 10_000)
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]), now: { clock })
        engine.resume(benchWorkout(sets: [workingSet(kg: 100, reps: 5, at: 10)]))

        #expect(engine.restStartedAt == nil)

        clock = Date(timeIntervalSince1970: 10_050)
        engine.hear(["100 for 5"])
        #expect(engine.restStartedAt == Date(timeIntervalSince1970: 10_050))
    }

    @Test("resume numbers a new superset run above any already in the adopted workout")
    func resumeSupersetNumbering() {
        let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.resume(benchWorkout(sets: [workingSet(kg: 100, reps: 5, at: 10, run: 2)]))

        engine.hear(["superset"])
        engine.hear(["100 for 5"])

        #expect(engine.workout?.entries.first?.sets.last?.supersetRunID == 3)
    }

    @Test("resume ignores an already-ended workout")
    func resumeIgnoresEndedWorkout() {
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: .empty)
        var ended = benchWorkout(sets: [workingSet(kg: 100, reps: 5, at: 10)])
        ended.endedAt = Date(timeIntervalSince1970: 300)

        engine.resume(ended)

        #expect(engine.workout == nil)
        #expect(store.saved.isEmpty)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/WorkoutLoggerCore && swift test --filter WorkoutEngineTests`
Expected: FAIL — `value of type 'WorkoutEngine' has no member 'resume'`.

- [ ] **Step 3: Implement `resume(_:)`**

In `WorkoutEngine.swift`, add this method immediately after `startWorkout(from:)` and before `endWorkout()`:

```swift
    /// Adopts an existing, not-yet-ended workout — the launch resume path for a
    /// workout the user forgot to end. Precondition (guarded): `!workout.isEnded`.
    ///
    /// New sets attach to the workout's last entry. The rest timer starts fresh
    /// (a rest period from before the app was killed is meaningless). No
    /// `PersonalRecord` is re-announced for work already in the record — but the
    /// PR bar is seeded from `knownBests` folded with that work, so a set logged
    /// after resuming is a record only if it beats both history and this session.
    public func resume(_ workout: Workout) {
        guard !workout.isEnded else { return }

        self.workout = workout
        activeEntryIndex = workout.entries.indices.last
        personalRecords = []
        retryTarget = nil
        currentSupersetRunID = nil
        supersetRunCount = workout.entries
            .flatMap(\.sets)
            .compactMap(\.supersetRunID)
            .max() ?? 0
        templateRestTargets = [:]
        restStartedAt = nil

        var best = knownBests
        for entry in workout.entries {
            for set in entry.sets where set.role == .working {
                guard let load = set.loadKilograms, let reps = set.reps else { continue }
                let e1rm = estimatedOneRepMax(loadKilograms: load, reps: reps)
                best[entry.exercise.name] = max(best[entry.exercise.name] ?? 0, e1rm)
            }
        }
        bestOneRepMax = best

        store.save(workout)
    }
```

- [ ] **Step 4: Run to verify the new tests pass**

Run: `cd Packages/WorkoutLoggerCore && swift test --filter WorkoutEngineTests`
Expected: PASS — all `WorkoutEngineTests` including the 6 new ones.

- [ ] **Step 5: Run the whole core suite**

Run: `cd Packages/WorkoutLoggerCore && swift test`
Expected: PASS — 97 existing + 6 new = 103 tests, all green.
Run: `cd Packages/WorkoutLoggerCore && swift build 2>&1 | grep -i warning` → no output.

- [ ] **Step 6: Commit**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerCore
git commit -m "WorkoutLoggerCore: WorkoutEngine.resume(_:) to adopt an unfinished workout

The launch resume path. Adopts a not-yet-ended Workout: new sets attach to
its last entry, rest restarts fresh, personalRecords is empty, and the PR bar
is knownBests folded with the resumed workout's own working sets so a later
set only records if it beats both. No-op on an ended workout. Additive.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 4: `WorkoutSessionModel` — resume seeding, PR-haptic gate, stale recovery

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift`
- Modify: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift`

**Interfaces:**
- Consumes: `WorkoutEngine.resume(_:)` (Task 3), `WorkoutEngine.personalRecords`, `PersonalRecord.exercise`, `Workout.entries`, `SetRole.working`.
- Produces (new `public` surface on `WorkoutSessionModel`):
  - init param `knownBestExercises: Set<String> = []` — names with a seeded historical best; used only for the genuine-PR gate.
  - `struct StaleWorkoutRecovery` — `{ let workout: Workout; let onResume: () -> Void; let onDiscard: () -> Void; init(...) }`.
  - init param `staleRecovery: StaleWorkoutRecovery? = nil`.
  - `private(set) var staleRecovery: StaleWorkoutRecovery?` (observed) and `var pendingStaleWorkout: Workout? { staleRecovery?.workout }`.
  - `func resumePendingStaleWorkout()` — runs `onResume`, clears the recovery, re-syncs, seeds `announcedThisWorkout` from the resumed workout.
  - `func discardPendingStaleWorkout()` — runs `onDiscard`, clears the recovery, re-syncs.
- Behaviour change: the `.personalRecord` haptic fires only for a *genuine* new best — the exercise had a seeded historical best, or the current workout already held a working set for it before this utterance. A baseline-setting first set logs (`.logged`) but does not celebrate.

- [ ] **Step 1: Rewrite the `firstSet` haptic assertion and add the `makeRig` param**

In `WorkoutSessionModelTests.swift`:

In `makeRig`, add a parameter and thread it (defaulting to the keys of `knownBests`, so the existing PR tests keep firing `.personalRecord`):

```swift
    private func makeRig(
        script: [[String]],
        capAtEarcon: Bool = false,
        knownBests: [String: Double] = [:],
        knownBestExercises: Set<String>? = nil,
        unit: MassUnit = .kilograms,
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }
    ) throws -> Rig {
        // ...engine + source + voice + haptics as before...
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: source, readbackVoice: voice,
            haptics: haptics, library: Self.library, unit: unit,
            capReadbackAtEarcon: capAtEarcon, now: now,
            knownBestExercises: knownBestExercises ?? Set(knownBests.keys)
        )
        return Rig(model: model, source: source, voice: voice, haptics: haptics)
    }
```

Replace the `firstSet` test's haptic expectation and comment:

```swift
        // A baseline-setting first working set logs but does not celebrate: the
        // engine emits a PersonalRecord for it (ADR-0003), but the model's
        // genuine-PR gate suppresses the .personalRecord haptic because the
        // exercise had no seeded best and no earlier working set this workout.
        #expect(rig.haptics.played == [.logged])
```

- [ ] **Step 2: Write the new failing tests**

Append to `WorkoutSessionModelTests.swift`:

```swift
    @Test("a baseline first set is silent on PR, but beating your own opener later celebrates")
    func genuinePRGate() async throws {
        let rig = try makeRig(script: [
            ["start workout"], ["bench 60 for 5"], ["bench 120 for 5"],
        ])
        await say(rig)                    // start
        await say(rig)                    // 60x5 — baseline, no seeded best
        #expect(rig.haptics.played == [.logged])

        await say(rig)                    // 120x5 — beats the in-workout best
        #expect(rig.haptics.played == [.logged, .logged, .personalRecord])
    }

    @Test("a seeded exercise fires the PR haptic on the very first set that beats it")
    func seededExerciseCelebratesFirstSet() async throws {
        let rig = try makeRig(
            script: [["start workout"], ["bench 100 for 5"]],
            knownBests: ["Bench Press": 50]
        )
        await say(rig); await say(rig)
        #expect(rig.haptics.played == [.logged, .personalRecord])
    }

    @Test("resuming a workout seeds announced exercises so their next readback is terse")
    func resumeSeedsAnnouncedExercises() async throws {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let now = { Date(timeIntervalSince1970: 5_000) }
        let engine = WorkoutEngine(store: store, library: Self.library, now: now)
        let prior = Workout(
            entries: [Entry(exercise: Self.bench, sets: [
                LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                          loadKilograms: 100, reps: 5, loggedAt: Date(timeIntervalSince1970: 10)),
            ])],
            startedAt: Date(timeIntervalSince1970: 10)
        )
        engine.resume(prior)

        let source = ScriptedTranscriptSource([["bench 100 for 5"]])
        let voice = SpyReadbackVoice()
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: source, readbackVoice: voice,
            haptics: SpyHaptics(), library: Self.library, now: now
        )

        model.pressed(); await model.released()

        // Bench was already in the resumed workout, so it is not "new this
        // workout" — readback is terse, not the full "Logged. Bench Press, ...".
        #expect(model.lastReadback == .speak("100 for 5"))
    }

    @Test("pendingStaleWorkout resolves via resume")
    func staleRecoveryResume() async throws {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(store: store, library: Self.library)
        let stale = Workout(
            entries: [Entry(exercise: Self.bench, sets: [
                LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                          loadKilograms: 100, reps: 5, loggedAt: Date(timeIntervalSince1970: 10)),
            ])],
            startedAt: Date(timeIntervalSince1970: 10)
        )
        var resumed = false
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: ScriptedTranscriptSource([]),
            readbackVoice: SpyReadbackVoice(), haptics: SpyHaptics(), library: Self.library,
            staleRecovery: .init(
                workout: stale,
                onResume: { resumed = true; engine.resume(stale) },
                onDiscard: { }
            )
        )

        #expect(model.pendingStaleWorkout == stale)
        model.resumePendingStaleWorkout()

        #expect(resumed)
        #expect(model.pendingStaleWorkout == nil)
        #expect(model.workout?.entries.first?.exercise == Self.bench)
    }

    @Test("pendingStaleWorkout resolves via discard without adopting the workout")
    func staleRecoveryDiscard() async throws {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(store: store, library: Self.library)
        let stale = Workout(
            entries: [Entry(exercise: Self.bench, sets: [])],
            startedAt: Date(timeIntervalSince1970: 10)
        )
        var discarded = false
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: ScriptedTranscriptSource([]),
            readbackVoice: SpyReadbackVoice(), haptics: SpyHaptics(), library: Self.library,
            staleRecovery: .init(workout: stale, onResume: { }, onDiscard: { discarded = true })
        )

        model.discardPendingStaleWorkout()

        #expect(discarded)
        #expect(model.pendingStaleWorkout == nil)
        #expect(model.workout == nil)   // engine never adopted it
    }
```

- [ ] **Step 3: Run to verify failure**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSessionModelTests`
Expected: FAIL — `extra argument 'knownBestExercises' in call` / `'staleRecovery'` / no member `pendingStaleWorkout` / `firstSet` fails on `[.logged, .personalRecord] != [.logged]`.

- [ ] **Step 4: Add the `StaleWorkoutRecovery` type**

At the top of `WorkoutSessionModel.swift` (after the imports, before the class):

```swift
/// A stale open workout found at launch, plus the two ways to resolve it. The
/// composition root supplies the closures (`engine.resume` / `closeAbandonedWorkout`);
/// the model just exposes the pending workout and calls one closure when the
/// user picks.
public struct StaleWorkoutRecovery {
    public let workout: Workout
    public let onResume: () -> Void
    public let onDiscard: () -> Void

    public init(workout: Workout, onResume: @escaping () -> Void, onDiscard: @escaping () -> Void) {
        self.workout = workout
        self.onResume = onResume
        self.onDiscard = onDiscard
    }
}
```

- [ ] **Step 5: Wire the new state and init params into `WorkoutSessionModel`**

Add stored properties. `staleRecovery` is observed (not `@ObservationIgnored`) so the view re-renders when it clears:

```swift
    /// A stale open workout awaiting the user's resume-or-discard choice, or nil.
    public private(set) var staleRecovery: StaleWorkoutRecovery?

    /// The workout the launch prompt is asking about, if any.
    public var pendingStaleWorkout: Workout? { staleRecovery?.workout }
```

Add to the `@ObservationIgnored` collaborator block:

```swift
    @ObservationIgnored private let knownBestExercises: Set<String>
```

Extend `init` — add the two parameters (both defaulted) and store them; seed `announcedThisWorkout` when a workout is already in progress:

```swift
    public init(
        engine: WorkoutEngine,
        transcriptSource: TranscriptSource,
        readbackVoice: ReadbackVoice,
        haptics: Haptics,
        library: ExerciseLibrary,
        unit: MassUnit = .kilograms,
        capReadbackAtEarcon: Bool = false,
        now: @escaping () -> Date = Date.init,
        knownBestExercises: Set<String> = [],
        staleRecovery: StaleWorkoutRecovery? = nil
    ) {
        self.engine = engine
        self.transcriptSource = transcriptSource
        self.readbackVoice = readbackVoice
        self.haptics = haptics
        self.library = library
        self.unit = unit
        self.capReadbackAtEarcon = capReadbackAtEarcon
        self.now = now
        self.knownBestExercises = knownBestExercises
        self.staleRecovery = staleRecovery
        syncFromEngine()
        seedAnnouncedFromCurrentWorkout()
    }

    /// When constructed over a workout already in progress (the resume path),
    /// treat its exercises as already announced this workout so the next readback
    /// for one is terse.
    private func seedAnnouncedFromCurrentWorkout() {
        guard let workout, !workout.isEnded else { return }
        announcedThisWorkout = Set(workout.entries.map(\.exercise.name))
    }
```

- [ ] **Step 6: Add the resolve methods**

```swift
    /// The user chose to resume the stale workout.
    public func resumePendingStaleWorkout() {
        staleRecovery?.onResume()
        staleRecovery = nil
        syncFromEngine()
        seedAnnouncedFromCurrentWorkout()
    }

    /// The user chose to discard the stale workout. The engine never adopts it;
    /// the closure closes it in storage at its last-activity time.
    public func discardPendingStaleWorkout() {
        staleRecovery?.onDiscard()
        staleRecovery = nil
        syncFromEngine()
    }
```

- [ ] **Step 7: Gate the PR haptic on a genuine best**

In `apply(_:)`, capture the pre-`hear` workout and compute genuineness. Replace the block from `let setsBefore` through the `fireHaptic(...)` call with:

```swift
        let setsBefore = totalSetCount(workout)
        let prBefore = engine.personalRecords.count
        let workoutBefore = workout

        engine.hear(hypotheses)
        syncFromEngine()

        let setsAfter = totalSetCount(workout)
        let loggedASet = setsAfter > setsBefore

        let genuinePR = engine.personalRecords
            .dropFirst(prBefore)
            .contains { isGenuinePersonalRecord($0.exercise.name, before: workoutBefore) }

        fireHaptic(results: results, loggedASet: loggedASet, firePersonalRecord: genuinePR)
```

Change `fireHaptic`'s signature and body:

```swift
    private func fireHaptic(results: [ParseResult], loggedASet: Bool, firePersonalRecord: Bool) {
        if loggedASet {
            haptics.play(.logged)
            if firePersonalRecord { haptics.play(.personalRecord) }
            return
        }
        if results.contains(where: { isLowConfidence($0) }) {
            haptics.play(.notCaught)
        }
    }

    /// A new best is genuine — worth the celebration haptic — when the exercise
    /// had a seeded historical best, or already had a working set this workout
    /// before this utterance. A set that merely establishes the first recorded
    /// number for an exercise is not.
    private func isGenuinePersonalRecord(_ name: String, before workout: Workout?) -> Bool {
        if knownBestExercises.contains(name) { return true }
        return workout?.entries.contains { entry in
            entry.exercise.name == name && entry.sets.contains { $0.role == .working }
        } ?? false
    }
```

- [ ] **Step 8: Run the filtered suite, then the whole app suite**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSessionModelTests`
Expected: PASS — the rewritten `firstSet`, the 5 new tests, and every prior test (`personalRecord` and `prAddsToLoggedHaptic` still pass because `makeRig` derives `knownBestExercises` from `knownBests.keys`).

Run: `cd Packages/WorkoutLoggerApp && swift test`
Expected: PASS — all suites.
Run: `cd Packages/WorkoutLoggerApp && swift build 2>&1 | grep -i warning` → no output.

- [ ] **Step 9: Commit**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerApp
git commit -m "WorkoutLoggerApp: genuine-PR haptic gate + resume seeding + stale-recovery seam

The .personalRecord haptic now fires only for a real best (seeded exercise, or
one that already had a working set this workout) — a baseline-setting first set
logs silently. announcedThisWorkout is seeded when the model is built over a
resumed workout. New StaleWorkoutRecovery seam: pendingStaleWorkout +
resume/discardPendingStaleWorkout() drive the launch prompt.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 5: `LaunchDecision` + `closeAbandonedWorkout`

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/HUD/LaunchDecision.swift`
- Create: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/LaunchDecisionTests.swift`

**Interfaces:**
- Consumes: `Workout` (`isEnded`, `isStale(now:staleAfter:)`, `lastActivityAt`, `endedAt`), `SwiftDataWorkoutStore.save(_:)` / `.history()` / `.openWorkout()`.
- Produces:
  - `enum LaunchDecision: Equatable, Sendable { case fresh; case resume(Workout); case promptStale(Workout) }`
  - `func launchDecision(openWorkout: Workout?, now: Date, staleAfter: TimeInterval = 6 * 60 * 60) -> LaunchDecision`
  - `func closeAbandonedWorkout(_ workout: Workout, in store: SwiftDataWorkoutStore)` — sets `endedAt = workout.lastActivityAt` and calls `store.save`.

- [ ] **Step 1: Write the failing tests**

Create `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/LaunchDecisionTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("LaunchDecision")
struct LaunchDecisionTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func openWorkout(lastSetAt t: TimeInterval) -> Workout {
        Workout(
            entries: [Entry(exercise: Exercise(name: "Bench Press"), sets: [
                LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                          loadKilograms: 100, reps: 5, loggedAt: Date(timeIntervalSince1970: t)),
            ])],
            startedAt: Date(timeIntervalSince1970: t - 100)
        )
    }

    @Test("no open workout is a fresh launch")
    func noneIsFresh() {
        #expect(launchDecision(openWorkout: nil, now: now) == .fresh)
    }

    @Test("an already-ended workout is a fresh launch")
    func endedIsFresh() {
        var w = openWorkout(lastSetAt: now.timeIntervalSince1970 - 60)
        w.endedAt = Date(timeIntervalSince1970: now.timeIntervalSince1970 - 30)
        #expect(launchDecision(openWorkout: w, now: now) == .fresh)
    }

    @Test("a recently active open workout resumes silently")
    func recentResumes() {
        let w = openWorkout(lastSetAt: now.timeIntervalSince1970 - 10 * 60) // 10 min ago
        #expect(launchDecision(openWorkout: w, now: now) == .resume(w))
    }

    @Test("an open workout stale past the threshold prompts")
    func stalePrompts() {
        let w = openWorkout(lastSetAt: now.timeIntervalSince1970 - 8 * 60 * 60) // 8 h ago
        #expect(launchDecision(openWorkout: w, now: now) == .promptStale(w))
    }

    @Test("exactly at the threshold is not yet stale")
    func boundaryResumes() {
        let w = openWorkout(lastSetAt: now.timeIntervalSince1970 - 6 * 60 * 60) // == staleAfter
        #expect(launchDecision(openWorkout: w, now: now) == .resume(w))
    }

    @Test("closeAbandonedWorkout closes at last-activity time, keeps the record and its sets")
    func closeAtLastActivity() throws {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let lastSet = Date(timeIntervalSince1970: 500)
        let w = openWorkout(lastSetAt: lastSet.timeIntervalSince1970)
        store.save(w) // it is on disk, open

        closeAbandonedWorkout(w, in: store)

        let history = store.history()
        #expect(history.count == 1)
        #expect(history.first?.endedAt == lastSet)          // not `now`
        #expect(history.first?.entries.first?.sets.count == 1)
        #expect(store.openWorkout() == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter LaunchDecision`
Expected: FAIL — `cannot find 'launchDecision' in scope` / `'LaunchDecision'` / `'closeAbandonedWorkout'`.

- [ ] **Step 3: Create `LaunchDecision.swift`**

```swift
import Foundation
import WorkoutLoggerCore

/// What to do with persistence state at launch.
public enum LaunchDecision: Equatable, Sendable {
    /// No open workout — start clean.
    case fresh
    /// An open workout touched recently enough to reopen without asking.
    case resume(Workout)
    /// An open workout stale enough that the user should choose resume-or-discard.
    case promptStale(Workout)
}

/// Classifies the workout (if any) returned by `SwiftDataWorkoutStore.openWorkout()`.
/// `staleAfter` is the idle span past which an open workout is treated as
/// forgotten rather than in-progress.
public func launchDecision(
    openWorkout: Workout?,
    now: Date,
    staleAfter: TimeInterval = 6 * 60 * 60
) -> LaunchDecision {
    guard let workout = openWorkout, !workout.isEnded else { return .fresh }
    return workout.isStale(now: now, staleAfter: staleAfter)
        ? .promptStale(workout)
        : .resume(workout)
}

/// The discard branch of `.promptStale`: close the workout at the moment it was
/// last touched (not `now` — it ended whenever the user stopped logging) and
/// persist it. Nothing is deleted; the app then proceeds as `.fresh`.
public func closeAbandonedWorkout(_ workout: Workout, in store: SwiftDataWorkoutStore) {
    var closed = workout
    closed.endedAt = workout.lastActivityAt
    store.save(closed)
}
```

- [ ] **Step 4: Run to verify pass, then the whole app suite**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter LaunchDecision`
Expected: PASS (6 tests).
Run: `cd Packages/WorkoutLoggerApp && swift test`
Expected: PASS — all suites.

- [ ] **Step 5: Commit**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerApp
git commit -m "WorkoutLoggerApp: LaunchDecision + closeAbandonedWorkout

Pure classification of the open workout found at launch: .fresh / .resume /
.promptStale on a 6h idle threshold. closeAbandonedWorkout closes a discarded
stale workout at its last-activity time and keeps the record.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 6: `StoreProvisioning` — degrade instead of crash

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/HUD/StoreProvisioning.swift`
- Create: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/StoreProvisioningTests.swift`

**Interfaces:**
- Consumes: `WorkoutRecord` (`@Model`), SwiftData `ModelContainer` / `Schema` / `ModelConfiguration`.
- Produces:
  - `enum StoreAvailability { case ready(ModelContainer); case degraded(ModelContainer) }` with `var container: ModelContainer` and `var isDegraded: Bool`.
  - `func provisionStore(onDiskURL: URL) -> StoreAvailability` — on-disk container, or an in-memory `.degraded` fallback when the on-disk init throws.

- [ ] **Step 1: Write the failing tests**

Create `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/StoreProvisioningTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("StoreProvisioning")
struct StoreProvisioningTests {

    @Test("a writable URL yields a ready, working container")
    func writableIsReady() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "trackit-test-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let availability = provisionStore(onDiskURL: url)
        #expect(availability.isDegraded == false)

        // the container is usable
        let context = ModelContext(availability.container)
        context.insert(WorkoutRecord(
            startedAt: Date(timeIntervalSince1970: 0), endedAt: nil, payload: Data("{}".utf8)
        ))
        try context.save()
        let count = try context.fetchCount(FetchDescriptor<WorkoutRecord>())
        #expect(count == 1)
    }

    @Test("an unusable URL degrades to a working in-memory container instead of crashing")
    func unusableDegrades() throws {
        // A path whose parent directory does not exist and cannot be created.
        let url = URL(fileURLWithPath: "/trackit-nonexistent-\(UUID().uuidString)/db.store")

        let availability = provisionStore(onDiskURL: url)
        #expect(availability.isDegraded == true)

        let context = ModelContext(availability.container)
        context.insert(WorkoutRecord(
            startedAt: Date(timeIntervalSince1970: 0), endedAt: nil, payload: Data("{}".utf8)
        ))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<WorkoutRecord>()) == 1)
    }
}
```

> If `provisionStore` does not throw for `/trackit-nonexistent-.../db.store` on this host, make the URL point at a path that is a directory (e.g. `FileManager.default.temporaryDirectory` itself) — opening a directory as a store file throws. The test's intent is "on-disk init failed → `.degraded`, still usable".

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter StoreProvisioning`
Expected: FAIL — `cannot find 'provisionStore' in scope`.

- [ ] **Step 3: Create `StoreProvisioning.swift`**

```swift
import Foundation
import SwiftData
import WorkoutLoggerCore

/// The persistence store the app came up with at launch.
public enum StoreAvailability {
    /// The on-disk store opened normally.
    case ready(ModelContainer)
    /// The on-disk store could not be opened (corrupt / unreadable); this is an
    /// in-memory fallback so the current workout still logs. History is not
    /// available and the UI should say so.
    case degraded(ModelContainer)

    public var container: ModelContainer {
        switch self {
        case .ready(let container), .degraded(let container): return container
        }
    }

    public var isDegraded: Bool {
        if case .degraded = self { return true }
        return false
    }
}

/// Opens the on-disk `WorkoutRecord` store, or — if that throws — an in-memory
/// container flagged `.degraded`. An in-memory container that itself cannot be
/// created is unrecoverable and traps (there is nowhere left to write).
public func provisionStore(onDiskURL: URL) -> StoreAvailability {
    let schema = Schema([WorkoutRecord.self])
    do {
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: onDiskURL)]
        )
        return .ready(container)
    } catch {
        let fallback = try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return .degraded(fallback)
    }
}
```

> Verify the `ModelConfiguration(schema:url:)` initializer against the SwiftData version in this toolchain (`swift build` will tell you). If the label differs, use the available on-disk form — the requirement is "named on-disk configuration at `onDiskURL`".

- [ ] **Step 4: Run to verify pass, then the whole app suite**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter StoreProvisioning`
Expected: PASS (2 tests).
Run: `cd Packages/WorkoutLoggerApp && swift test`
Expected: PASS — all suites.
Run: `cd Packages/WorkoutLoggerApp && swift build 2>&1 | grep -i warning` → no output.

- [ ] **Step 5: Commit**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerApp
git commit -m "WorkoutLoggerApp: StoreProvisioning — degrade to in-memory instead of crashing

provisionStore(onDiskURL:) returns .ready or, when the on-disk container throws,
.degraded with a working in-memory fallback so a corrupt store cannot block
launch. Only an in-memory container that can't be created traps.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 7: `App/` — the HUD view tree and composition root (files-only)

**Files:**
- Modify: `App/TrackitApp.swift`
- Modify: `App/Views/RootView.swift`
- Create: `App/Views/HUDView.swift`
- Create: `App/Views/SetListSheet.swift`
- Create: `App/Views/TapSelectSheet.swift`
- Create: `App/Views/LaunchGateView.swift`

**Interfaces:**
- Consumes from `WorkoutLoggerApp`: `WorkoutSessionModel` (`pressed`, `released`, `resolveTapSelect`, `tick`, `keepScreenAwake`, `pendingStaleWorkout`, `resumePendingStaleWorkout`, `discardPendingStaleWorkout`, `tapSelectCandidates`, `isListening`), `HUDProjection`, `StaleWorkoutRecovery`, `provisionStore`, `StoreAvailability`, `launchDecision`, `LaunchDecision`, `closeAbandonedWorkout`, `SwiftDataWorkoutStore`, `WorkoutRecord`.
- Consumes from `WorkoutLoggerCore`: `WorkoutEngine`, `ExerciseLibrary`, `Exercise`, `Workout`, `estimatedOneRepMax`, `SetRole`.
- Produces: a compiling-by-inspection SwiftUI app. **No `swift test`** — verification is Step 8's consistency check.

**Verification note:** this environment cannot build `App/`. Every symbol used here must be `public` in the packages (confirm against Tasks 1–6) and every signature must match. The task reviewer checks consistency, not a build.

- [ ] **Step 1: Rewrite `TrackitApp.swift` as the composition root**

```swift
import SwiftUI
import SwiftData
import WorkoutLoggerCore
import WorkoutLoggerApp

/// Composition root. `@MainActor` so `init()` may build the `@MainActor`
/// `System*` adapters and the `@MainActor` `WorkoutSessionModel`.
@main
@MainActor
struct TrackitApp: App {
    @State private var model: WorkoutSessionModel
    private let historyUnavailable: Bool

    init() {
        let storeURL = URL.applicationSupportDirectory.appending(path: "Trackit.store")
        let availability = provisionStore(onDiskURL: storeURL)
        historyUnavailable = availability.isDegraded

        let store = SwiftDataWorkoutStore(context: ModelContext(availability.container))
        let library = ExerciseLibrary(TrackitApp.seedExercises)
        let history = availability.isDegraded ? [] : store.history()
        let knownBests = TrackitApp.knownBests(from: history)
        let engine = WorkoutEngine(store: store, library: library, knownBests: knownBests)

        let openWorkout = availability.isDegraded ? nil : store.openWorkout()
        var staleRecovery: StaleWorkoutRecovery?
        switch launchDecision(openWorkout: openWorkout, now: Date()) {
        case .fresh:
            break
        case .resume(let workout):
            engine.resume(workout)
        case .promptStale(let workout):
            staleRecovery = StaleWorkoutRecovery(
                workout: workout,
                onResume: { engine.resume(workout) },
                onDiscard: { closeAbandonedWorkout(workout, in: store) }
            )
        }

        _model = State(initialValue: WorkoutSessionModel(
            engine: engine,
            transcriptSource: SystemSpeechRecognizer(),
            readbackVoice: SystemReadbackVoice(),
            haptics: SystemHaptics(),
            library: library,
            knownBestExercises: Set(knownBests.keys),
            staleRecovery: staleRecovery
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, historyUnavailable: historyUnavailable)
        }
    }

    /// Best estimated 1RM per exercise name across completed history — the PR bar
    /// each exercise must clear this session.
    static func knownBests(from history: [Workout]) -> [String: Double] {
        var best: [String: Double] = [:]
        for workout in history {
            for entry in workout.entries {
                for set in entry.sets where set.role == .working {
                    guard let load = set.loadKilograms, let reps = set.reps else { continue }
                    let e1rm = estimatedOneRepMax(loadKilograms: load, reps: reps)
                    best[entry.exercise.name] = max(best[entry.exercise.name] ?? 0, e1rm)
                }
            }
        }
        return best
    }

    static let seedExercises: [Exercise] = [
        Exercise(name: "Barbell Bench Press", aliases: ["bench", "bench press"]),
        Exercise(name: "Barbell Back Squat", aliases: ["squat", "squats", "back squat"]),
        Exercise(name: "Conventional Deadlift", aliases: ["deadlift", "deads"]),
        Exercise(name: "Overhead Press", aliases: ["ohp", "overhead press", "press"]),
        Exercise(name: "Barbell Row", aliases: ["row", "barbell row", "bent row"]),
        Exercise(name: "Pull-Up", aliases: ["pull up", "pull ups", "pullups"]),
    ]
}
```

- [ ] **Step 2: Rewrite `RootView.swift` as the launch gate + HUD host**

```swift
import SwiftUI
import Combine
import WorkoutLoggerApp

/// Top-level container: shows the resume-or-discard prompt while one is pending,
/// otherwise the HUD. Owns the 1 Hz rest tick and the keep-awake bridge.
///
/// Ownership: `TrackitApp` owns the `@Observable` `WorkoutSessionModel` in its
/// `@State`; this view holds it as a plain `let` (SwiftUI still tracks the
/// `@Observable` reads in `body`). `import Combine` is for `Timer.publish`.
struct RootView: View {
    let model: WorkoutSessionModel
    let historyUnavailable: Bool

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.pendingStaleWorkout != nil {
                LaunchGateView(model: model)
            } else {
                HUDView(model: model, historyUnavailable: historyUnavailable)
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(tick) { _ in model.tick() }
        .onChange(of: model.keepScreenAwake, initial: true) { _, awake in
            UIApplication.shared.isIdleTimerDisabled = awake
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
```

- [ ] **Step 3: Create `LaunchGateView.swift`**

```swift
import SwiftUI
import WorkoutLoggerApp

/// Resume-or-discard prompt for a stale open workout found at launch.
struct LaunchGateView: View {
    let model: WorkoutSessionModel

    var body: some View {
        VStack(spacing: 32) {
            Text("Unfinished workout")
                .font(.title.bold())
                .foregroundStyle(.white)

            if let workout = model.pendingStaleWorkout {
                Text("Started \(workout.startedAt.formatted(date: .abbreviated, time: .shortened)) and never ended.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button("Resume it") { model.resumePendingStaleWorkout() }
                    .buttonStyle(.borderedProminent)
                Button("Discard it") { model.discardPendingStaleWorkout() }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding(40)
    }
}
```

- [ ] **Step 4: Create `HUDView.swift`**

```swift
import SwiftUI
import WorkoutLoggerCore
import WorkoutLoggerApp

/// The calm, high-contrast active-workout screen. A dumb renderer over
/// `HUDProjection` — no formatting or fallback logic lives here.
struct HUDView: View {
    let model: WorkoutSessionModel
    let historyUnavailable: Bool

    @State private var showingSetList = false

    private var hud: HUDProjection { HUDProjection(from: model) }

    var body: some View {
        VStack(spacing: 28) {
            if historyUnavailable {
                Text("History unavailable")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(hud.exerciseName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Text(hud.lastSetLine ?? "—")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            restCard

            Spacer()

            talkButton
        }
        .padding(32)
        .sheet(isPresented: $showingSetList) {
            SetListSheet(lines: hud.currentEntrySetLines)
        }
        .sheet(isPresented: Binding(
            get: { hud.tapSelectCandidates != nil },
            set: { if !$0 { /* dismissed without choosing — no-op */ } }
        )) {
            TapSelectSheet(
                candidates: hud.tapSelectCandidates ?? [],
                onPick: { model.resolveTapSelect($0) }
            )
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in if value.translation.height < -40 { showingSetList = true } }
        )
    }

    @ViewBuilder private var restCard: some View {
        if let restLine = hud.restLine {
            Text(restLine)
                .font(.system(size: 40, weight: .medium, design: .rounded))
                .foregroundStyle(hud.restTargetReached ? Color.green : Color.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(hud.restTargetReached ? Color.green : Color.secondary.opacity(0.4), lineWidth: 2)
                )
        }
    }

    private var talkButton: some View {
        Text(hud.isListening ? "Listening…" : "Hold to talk")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(hud.isListening ? Color.green : Color.white)
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !model.isListening { model.pressed() } }
                    .onEnded { _ in Task { await model.released() } }
            )
    }
}
```

- [ ] **Step 5: Create `SetListSheet.swift`**

```swift
import SwiftUI

/// Swipe-up list of every set logged for the current entry. Read-only in v1 C;
/// inline editing is subsystem D.
struct SetListSheet: View {
    let lines: [String]

    var body: some View {
        NavigationStack {
            List(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.body.monospacedDigit())
            }
            .navigationTitle("This exercise")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Step 6: Create `TapSelectSheet.swift`**

```swift
import SwiftUI
import WorkoutLoggerCore

/// Shown when voice could not place an exercise. Picking one re-issues the
/// utterance against it; dismissing without a choice leaves the workout untouched.
struct TapSelectSheet: View {
    let candidates: [Exercise]
    let onPick: (Exercise) -> Void

    var body: some View {
        NavigationStack {
            List(candidates, id: \.name) { exercise in
                Button(exercise.name) { onPick(exercise) }
            }
            .navigationTitle("Did you mean…")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
```

- [ ] **Step 7: Confirm the seed exercises resolve and `URL.applicationSupportDirectory` is available**

`URL.applicationSupportDirectory` is iOS 16+ — fine at the iOS 17 floor. If the reviewer prefers an explicit `FileManager` lookup, `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appending(path: "Trackit.store")` is equivalent.

- [ ] **Step 8: Consistency check (no build here)**

Re-read all six files and confirm, line by line:
- Every `WorkoutLoggerApp` symbol used is `public`: `WorkoutSessionModel` + its new members (`keepScreenAwake`, `pendingStaleWorkout`, `resumePendingStaleWorkout`, `discardPendingStaleWorkout`, `displayUnit` — Tasks 1, 4), `HUDProjection` + `init(from:)` (Task 2), `StaleWorkoutRecovery` (Task 4), `provisionStore` / `StoreAvailability` (Task 6), `launchDecision` / `LaunchDecision` / `closeAbandonedWorkout` (Task 5), `SwiftDataWorkoutStore` / `WorkoutRecord` (A+B).
- Every `WorkoutLoggerCore` symbol used is `public`: `WorkoutEngine` + `resume(_:)` (Task 3), `ExerciseLibrary`, `Exercise`, `Workout`, `estimatedOneRepMax`, `SetRole.working`.
- `WorkoutSessionModel.init` argument list here matches Task 4's exactly (`knownBestExercises:`, `staleRecovery:` last, both defaulted).
- `System{SpeechRecognizer,ReadbackVoice,Haptics}` are the A+B `@MainActor` adapters — unchanged, still constructed with no arguments.
- `HUDProjection(from:)` is `@MainActor`; every call site here is in a `@MainActor` view body — OK.
- No `App/` file imports `SwiftData` except `TrackitApp.swift` (which needs `ModelContext`).

- [ ] **Step 9: Commit**

```bash
cd /Users/Apple/projects/trackit
git add App
git commit -m "App: live-workout HUD view tree + composition root

RootView is now the launch gate (resume-or-discard prompt) + HUD host with the
1 Hz tick and keep-awake bridge. HUDView renders HUDProjection; SetListSheet
(read-only swipe-up), TapSelectSheet, LaunchGateView. TrackitApp wires
provisionStore -> knownBests -> engine -> launchDecision -> resume/stale-recovery
-> model. Not swift-test covered (no Xcode here); consistency-checked.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 8: Reconcile the spec and memory

**Files:**
- Modify: `Packages/WorkoutLoggerCore/specs/v1-voice-logging.md`
- Modify: `/Users/Apple/.claude/projects/-Users-Apple-projects-trackit/memory/phase-progress.md` (outside the repo — not committed)

**Interfaces:**
- Consumes: the finished state of Tasks 1–7.
- Produces: docs consistent with the code.

- [ ] **Step 1: Note the HUD landing in the v1 spec**

In `Packages/WorkoutLoggerCore/specs/v1-voice-logging.md`, under the module-boundary list (the `- **Workout engine.**` / `- **Readback.**` bullets), append to the **Workout engine** bullet:

```
  The app-shell resume path is `WorkoutEngine.resume(_:)` (subsystem C): it
  adopts a not-yet-ended `Workout` found in storage at launch, attaching new
  sets to its last entry, restarting the rest timer, and seeding the
  personal-record bar from history plus the resumed workout's own sets without
  re-announcing past records.
```

Under `## Testing Decisions`, after the `- **App skeleton + voice pipeline (subsystems A+B).**` bullet, add:

```
- **Live-workout HUD (subsystem C).** `WorkoutLoggerApp` gains three pure,
  `swift test`-covered types — `HUDProjection` (session-model snapshot →
  glanceable HUD fields), `LaunchDecision` + `closeAbandonedWorkout` (classify
  and close the open workout found at launch), and `StoreProvisioning` (on-disk
  container or an in-memory `.degraded` fallback so a corrupt store cannot crash
  launch) — plus a `StaleWorkoutRecovery` seam on `WorkoutSessionModel` and a
  genuine-personal-record gate on its haptic. The HUD view tree in `App/`
  (`HUDView`, `SetListSheet`, `TapSelectSheet`, `LaunchGateView`) is a thin
  renderer over `HUDProjection` and is not `swift test`-covered. Mid-workout
  inline set editing is deferred to subsystem D; the swipe-up set list is
  read-only.
```

- [ ] **Step 2: Run both suites to confirm the spec edit changed nothing**

Run: `cd Packages/WorkoutLoggerCore && swift test` → PASS.
Run: `cd Packages/WorkoutLoggerApp && swift test` → PASS.

- [ ] **Step 3: Commit the spec**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerCore/specs/v1-voice-logging.md
git commit -m "Docs: reconcile the v1 spec with the subsystem C (live-workout HUD) landing

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

- [ ] **Step 4: Update `phase-progress.md`** (outside the repo — not committed)

In `/Users/Apple/.claude/projects/-Users-Apple-projects-trackit/memory/phase-progress.md`, in the "App shell" paragraph, change the deferred-rulings list: remove items (A) PR-haptic-on-every-first-set, (B) `try! ModelContainer`, and (D) `WorkoutEngine` rehydrate seam — each is now closed by subsystem C — and add a new paragraph before the "Subsystems C (HUD)…" sentence:

```
- **Subsystem C — live-workout HUD DONE (package scope).** `HUDProjection`
  (session snapshot → glanceable fields), `LaunchDecision` + `closeAbandonedWorkout`,
  `StoreProvisioning` (in-memory `.degraded` fallback), a `StaleWorkoutRecovery`
  seam + genuine-PR haptic gate on `WorkoutSessionModel`, and one additive core
  seam `WorkoutEngine.resume(_:)`. HUD view tree in `App/` (files-only). Carried
  A+B deferrals A/B/D closed here. Mid-workout inline set edit → D.
```

Leave `MEMORY.md`'s one-line pointer as-is (still accurate).

---

## Self-Review

**1. Spec coverage**

| Spec element | Task |
|---|---|
| `HUDProjection` — exerciseName / lastSetLine / restLine (mm:ss) / restTargetReached / isListening / currentEntrySetLines / tapSelectCandidates, two inits | 2 |
| Formatting: whole numbers without `.0`, one shared helper, unit-aware, warmup/grouping markers | 2 |
| `WorkoutSessionModel`: `restTargetSeconds`, `isRestTargetReached` (refreshed in `tick`) | 1 |
| `WorkoutSessionModel`: `keepScreenAwake` bool | 1 |
| `WorkoutSessionModel`: `knownBestExercises` param + genuine-PR haptic gate (baseline set logs silently; later best or seeded exercise celebrates) | 4 |
| `WorkoutSessionModel`: `announcedThisWorkout` seeding on resume | 4 |
| `WorkoutEngine.resume(_:)` — last entry active, `personalRecords=[]`, PR bar = knownBests ⊕ resumed working sets, `restStartedAt=nil`, superset run numbering, re-save, no-op on ended | 3 |
| `LaunchDecision` — `.fresh` / `.resume` / `.promptStale` on the 6h threshold; `nil` and ended → `.fresh` | 5 |
| `closeAbandonedWorkout` — `endedAt = lastActivityAt`, persisted, nothing deleted | 5 |
| `StoreProvisioning` — `.ready` / `.degraded` in-memory fallback, retained `try!` only for the in-memory case | 6 |
| Keep-awake mapped to `isIdleTimerDisabled`, reset on end / scene inactive | 7 (view) + 1 (bool) |
| Launch flow wiring: provisionStore → seed knownBests (skipped when degraded) → engine → launchDecision → resume / stale-recovery | 7 |
| HUD view tree: `HUDView`, `SetListSheet` (read-only), `TapSelectSheet`, `LaunchGateView` | 7 |
| "History unavailable" indication in degraded mode | 7 |
| Story 13 — dismiss tap-select without choosing is a no-op | 7 (`TapSelectSheet` set-binding no-op) |
| Story 25 — one attach point for prominent numbers | 2 (`numberString`) + 7 (`.rounded` design font) |
| Spec + memory reconciliation | 8 |
| Mid-workout inline edit | Out of scope — deferred to D (stated in spec and Task 8 note) |

No gaps.

**2. Placeholder scan**

No "TBD"/"TODO"/"handle edge cases"/"similar to Task N". Every code step has complete code. The two "if the parser/SwiftData behaves differently, adjust X" notes (Task 2 warmup phrase, Task 6 failing-URL shape) name a concrete fallback and the invariant to preserve — they are not open-ended placeholders.

**3. Type consistency**

- `numberString(_:)` / `formattedSetLine(_:unit:)` — defined Task 2, used only Task 2 + Task 7 (indirectly via `HUDProjection`). ✓
- `HUDProjection` field names — identical in the struct def, the memberwise `init`, the `init(from:)`, the Task 2 tests, and Task 7's `HUDView`. ✓
- `WorkoutSessionModel.init` — Task 1 adds `unit` is *already present*; Task 4 adds `knownBestExercises:` and `staleRecovery:` (both defaulted, last two params). Task 4's `makeRig` and Task 7's `TrackitApp` both call it with that exact list. ✓
- `WorkoutSessionModel.displayUnit` / `keepScreenAwake` / `restTargetSeconds` / `isRestTargetReached` (Task 1) — consumed by `HUDProjection` (Task 2) and `RootView` (Task 7). ✓
- `WorkoutSessionModel.pendingStaleWorkout` / `resumePendingStaleWorkout()` / `discardPendingStaleWorkout()` / `staleRecovery` / `StaleWorkoutRecovery` (Task 4) — consumed by `RootView` + `LaunchGateView` + `TrackitApp` (Task 7). ✓
- `WorkoutEngine.resume(_:)` (Task 3) — consumed by Task 4 tests, Task 7 `TrackitApp`. Signature `func resume(_ workout: Workout)` consistent everywhere. ✓
- `LaunchDecision` / `launchDecision(openWorkout:now:staleAfter:)` / `closeAbandonedWorkout(_:in:)` (Task 5) — used by Task 7 `TrackitApp`. ✓
- `StoreAvailability` (`.container`, `.isDegraded`) / `provisionStore(onDiskURL:)` (Task 6) — used by Task 7 `TrackitApp`. ✓
- `TrackitApp.knownBests(from:)` returns `[String: Double]`; `Set(knownBests.keys)` passed as `knownBestExercises` — matches Task 4's `Set<String>`. ✓
- Haptic-sequence expectations: Task 4 changes `firstSet` to `[.logged]` and adds `genuinePRGate` expecting `[.logged, .logged, .personalRecord]`; the A+B `personalRecord` / `prAddsToLoggedHaptic` tests pass `knownBests: ["Bench Press": 100]`, so `makeRig` derives `knownBestExercises == ["Bench Press"]` → gate returns `true` → `.personalRecord` still fires. ✓

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-08-31-live-workout-hud.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — execute tasks in this session with `executing-plans`, batch execution with checkpoints.

**Which approach?**
