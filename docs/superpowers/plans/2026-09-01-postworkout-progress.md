# Post-Workout Review, Editing & Per-Exercise Progress — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the review-and-progress half of trackit — a completed-workout history list, a workout detail screen with full editing, mid-workout inline set editing, a per-exercise progress screen with charts, and a "vs last time" line on the live HUD — plus three carried fixes from subsystem C.

**Architecture:** Mirror subsystem C: pure projection structs (`swift test`-covered, view-agnostic) below one `@Observable @MainActor` model per screen area, with dumb SwiftUI views in the `App/` target. Two additive edits to the otherwise-frozen `WorkoutLoggerCore` — a `Workout.movingSet` pure transform and a `WorkoutEngine.editSet` / `removeSet` mid-workout seam. No schema change; edits re-save through the existing upsert-by-`startedAt` store.

**Tech Stack:** Swift 6 (language mode 6, `-strict-concurrency=complete`), SwiftPM, Swift Testing (`@Test` / `@Suite` / `#expect` / `#require`), SwiftData (`ModelConfiguration(isStoredInMemoryOnly:)` in tests), Swift Charts (in `App/` only — never imported by the package).

**Spec:** `docs/superpowers/specs/2026-09-01-postworkout-progress-design.md` (read it alongside this plan — the plan argues from it).

## Global Constraints

- **Swift 6 language mode**, `-strict-concurrency=complete`. All new model types are `@MainActor @Observable final class`; all new projection types are `public struct … : Equatable, Sendable`.
- **`WorkoutLoggerCore` is frozen** except the two additive edits named in this plan: `Workout.movingSet(at:_:toExercise:)` in `WorkoutEditing.swift`, and `WorkoutEngine.editSet(at:_:with:)` + `removeSet(at:_:)` in `WorkoutEngine.swift`. No other core file changes. No new core files. No new core dependencies.
- **`swift test` runs in this environment; Xcode / `xcodebuild` do not.** The `App/` target is not in the SPM graph — its files are consistency-checked against real package signatures, never compiled here. Tasks 13–14 have no runnable test; their "verify" step is a symbol cross-check plus `swift build` of both packages.
- **Two packages, tested independently:** `cd Packages/WorkoutLoggerCore && swift test` and `cd Packages/WorkoutLoggerApp && swift test`. A Bash `cd` into the package directory is needed before each `swift` invocation (the working directory resets between calls).
- **Loads are stored in kilograms** (ADR-0002). Display conversion to pounds is `kg / 0.45359237`, rounded to one decimal (`gymRound`). Estimated 1RM is Epley: `load * (30 + reps) / 30`, a single rep returned unchanged (ADR-0003, `estimatedOneRepMax(loadKilograms:reps:)`).
- **A Set has four orthogonal axes** (ADR-0001): `loadType`, `effort`, `role`, `grouping`. Warm-up sets (`role == .warmup`) are excluded from volume, working reps, estimated 1RM, and personal-record consideration.
- **Vocabulary** (CONTEXT.md): Workout, Active workout, Completed workout, Entry, Exercise, Set, Working set, Warm-up set, Volume, Estimated 1RM, Personal record, Announcement, Readback, Rest target. Do **not** call a Workout a "session" in names or comments (`ExerciseSession` is a pre-existing core type and stays as-is).
- **Personal-record badge rule:** badge a working set only when the exercise appears in prior history *and* the set's estimated 1RM strictly exceeds the prior best. A first-ever working set for an exercise is never badged.
- **Commit** after every green step that the plan marks "Commit". Commit messages end with the trailer:
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
  ```

---

## File Structure

### `WorkoutLoggerCore` — modify only (the two approved edits)

| File | Responsibility | Change |
|---|---|---|
| `Sources/WorkoutLoggerCore/WorkoutEditing.swift` | Pure `Workout → Workout` editing transforms | **Add** `movingSet(at:_:toExercise:)` beside `replacingSet` / `removingSet` |
| `Sources/WorkoutLoggerCore/WorkoutEngine.swift` | The active-workout engine | **Add** `editSet(at:_:with:)` and `removeSet(at:_:)` — public methods that run a pure transform on the live workout then repair `activeEntryIndex`, the retry target, and the per-exercise best estimate |
| `Tests/WorkoutLoggerCoreTests/WorkoutEditingTests.swift` | — | **Add** `movingSet` cases |
| `Tests/WorkoutLoggerCoreTests/WorkoutEngineTests.swift` | — | **Add** `editSet` / `removeSet` cases |

### `WorkoutLoggerApp` — new files

| File | Responsibility |
|---|---|
| `Sources/WorkoutLoggerApp/Formatting/SetFormatting.swift` *(modify)* | Widen `gymRound` / `kilogramsPerPound` to file-internal; add `loadString(_:unit:)` and `displayLoad(_:unit:)` helpers; refactor `formattedSetLine` to call `loadString` (behaviour unchanged) |
| `Sources/WorkoutLoggerApp/History/WorkoutSummaryProjection.swift` | Pure: a completed `Workout` + prior history + unit → entry rows, formatted set lines, PR badges, totals, note |
| `Sources/WorkoutLoggerApp/History/WorkoutHistoryStore.swift` | `protocol WorkoutHistoryStore` (`history()`, `save(_:)`, `lastSaveError`); `extension SwiftDataWorkoutStore: WorkoutHistoryStore` |
| `Sources/WorkoutLoggerApp/History/WorkoutHistoryModel.swift` | `@Observable @MainActor` — loads completed workouts newest-first, opens one, applies an edit transform → save → reload; exposes an "unavailable" state |
| `Sources/WorkoutLoggerApp/Progress/ExerciseProgressProjection.swift` | Pure: `ExerciseProgress` + unit → chart series (load / volume / e1RM), top-set line, "vs last time" comparison |
| `Sources/WorkoutLoggerApp/Progress/ExerciseProgressModel.swift` | `@Observable @MainActor` — given an `Exercise`, pulls completed history, runs `exerciseProgress`, holds the projection |
| `Tests/WorkoutLoggerAppTests/WorkoutSummaryProjectionTests.swift` | — |
| `Tests/WorkoutLoggerAppTests/WorkoutHistoryModelTests.swift` | — |
| `Tests/WorkoutLoggerAppTests/ExerciseProgressProjectionTests.swift` | — |
| `Tests/WorkoutLoggerAppTests/ExerciseProgressModelTests.swift` | — |

### `WorkoutLoggerApp` — modify

| File | Change |
|---|---|
| `Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift` | Inject `history: () -> [Workout]` (defaulted); add `previousWorkoutLine`; add `editActiveSet` / `removeActiveSet` wrappers; `knownBestExercises` `let` → `var` + re-derive on workout end; fix `exerciseName(for:in:)` to use `activeExerciseName` |
| `Sources/WorkoutLoggerApp/HUD/HUDProjection.swift` | `restLine` renders `m:ss / m:ss`; add `vsLastTimeLine` field fed from `model.previousWorkoutLine` |
| `Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift` | Add cases; update `makeRig` for the new init param |
| `Tests/WorkoutLoggerAppTests/HUDProjectionTests.swift` | Update `restLine` expectation; add `vsLastTimeLine` cases |

### `App/` — files only, consistency-checked (never built here)

| File | Change |
|---|---|
| `App/Views/HistoryListView.swift` *(new)* | Reverse-chronological list of `WorkoutHistoryModel.rows` → tap opens detail |
| `App/Views/WorkoutDetailView.swift` *(new)* | Renders `WorkoutSummaryProjection`; row tap → `SetEditView`; exercise tap → `ExerciseProgressView` |
| `App/Views/ExerciseProgressView.swift` *(new)* | Swift Charts over `ExerciseProgressProjection` series + comparison |
| `App/Views/SetEditView.swift` *(new)* | Form: load / reps / role / grouping (clear-or-dropset) / note / move-to-exercise; builds a `LoggedSet`, calls back |
| `App/Views/RootView.swift` *(modify)* | Wrap the HUD in a `NavigationStack`; add a toolbar button → `HistoryListView` |
| `App/Views/HUDView.swift` *(modify)* | Rest row shows `m:ss / m:ss`; add the "vs last time" row; swipe-up sheet rows become editable |
| `App/Views/SetListSheet.swift` *(modify)* | Rows carry a set index; tap → edit callback, swipe → delete callback |
| `App/TrackitApp.swift` *(modify)* | Build a `SwiftDataWorkoutStore`-backed `WorkoutHistoryModel`; pass `history: { store.history() }` into `WorkoutSessionModel` |

---

## Task 1: `Workout.movingSet` pure transform

**Files:**
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEditing.swift`
- Test: `Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutEditingTests.swift`

**Interfaces:**
- Consumes: `Workout`, `Entry`, `Exercise`, `LoggedSet` (all in `WorkoutEngine.swift` / `Model.swift`); the existing private `hasSet(at:_:)`.
- Produces: `extension Workout { public func movingSet(at entryIndex: Int, _ setIndex: Int, toExercise: Exercise) -> Workout }` — pulls the set at `(entryIndex, setIndex)` out of its entry (dropping the entry if it empties), then appends it to the end of the first entry whose `exercise.name == toExercise.name`, or to a new `Entry(exercise: toExercise)` appended to `entries` if none matches. Out-of-range index → returns `self`. Source entry's `exercise.name == toExercise.name` → returns `self`. The moved set keeps every field (all four axes, `loadKilograms`, `reps`, `durationSeconds`, `distanceMeters`, `supersetRunID`, `loggedAt`, `note`). The target entry is resolved from the entry list **after** the source removal.

- [ ] **Step 1: Write the first failing test** — move to an existing entry

Add to `WorkoutEditingTests.swift` inside `struct WorkoutEditingTests`:

```swift
@Test("moving a set to an exercise that already has an entry appends it there")
func movingToExistingEntry() {
    let original = Workout(
        entries: [
            Entry(exercise: bench, sets: [set(load: 100, reps: 5), set(load: 100, reps: 5)]),
            Entry(exercise: squat, sets: [set(load: 140, reps: 3)]),
        ],
        startedAt: Date(timeIntervalSince1970: 0)
    )

    let edited = original.movingSet(at: 0, 1, toExercise: squat)

    #expect(edited.entries.map(\.exercise) == [bench, squat])
    #expect(edited.entries[0].sets.count == 1)
    #expect(edited.entries[1].sets.map(\.loadKilograms) == [140, 100]) // moved set appended at the end
}
```

- [ ] **Step 2: Run it — expect a compile failure**

Run: `cd Packages/WorkoutLoggerCore && swift test --filter WorkoutEditingTests/movingToExistingEntry`
Expected: FAIL — `value of type 'Workout' has no member 'movingSet'`.

- [ ] **Step 3: Implement `movingSet`**

Add to the `extension Workout` block in `WorkoutEditing.swift`, after `removingSet`:

```swift
/// A copy with the set at `entryIndex` / `setIndex` moved to `toExercise`. It is
/// appended to the end of that exercise's existing entry, or to a new entry if
/// the workout has none. If the move empties the source entry, the entry goes
/// too (same rule as `removingSet`). Every field of the set is carried verbatim,
/// including `grouping` and `supersetRunID` — un-grouping a moved set is a
/// separate `replacingSet` edit. An out-of-range index, or a `toExercise` whose
/// name matches the source entry's, is a no-op.
public func movingSet(at entryIndex: Int, _ setIndex: Int, toExercise: Exercise) -> Workout {
    guard hasSet(at: entryIndex, setIndex) else { return self }
    guard entries[entryIndex].exercise.name != toExercise.name else { return self }

    var copy = self
    let moved = copy.entries[entryIndex].sets.remove(at: setIndex)
    if copy.entries[entryIndex].sets.isEmpty {
        copy.entries.remove(at: entryIndex)
    }

    if let target = copy.entries.firstIndex(where: { $0.exercise.name == toExercise.name }) {
        copy.entries[target].sets.append(moved)
    } else {
        copy.entries.append(Entry(exercise: toExercise, sets: [moved]))
    }
    return copy
}
```

- [ ] **Step 4: Run it — expect PASS**

Run: `cd Packages/WorkoutLoggerCore && swift test --filter WorkoutEditingTests/movingToExistingEntry`
Expected: PASS.

- [ ] **Step 5: Add the remaining `movingSet` cases (one at a time, run after each)**

```swift
@Test("moving a set to an unknown exercise creates a new entry for it")
func movingToNewEntry() {
    let curl = Exercise(name: "Curl", aliases: ["curl"])
    let original = Workout(
        entries: [Entry(exercise: bench, sets: [set(load: 100, reps: 5), set(load: 100, reps: 5)])],
        startedAt: Date(timeIntervalSince1970: 0)
    )

    let edited = original.movingSet(at: 0, 0, toExercise: curl)

    #expect(edited.entries.map(\.exercise.name) == ["Bench", "Curl"])
    #expect(edited.entries[1].sets.count == 1)
}

@Test("moving the last set out of an entry drops the entry")
func movingLastSetDropsSourceEntry() {
    let original = Workout(
        entries: [
            Entry(exercise: bench, sets: [set(load: 100, reps: 5)]),
            Entry(exercise: squat, sets: [set(load: 140, reps: 3)]),
        ],
        startedAt: Date(timeIntervalSince1970: 0)
    )

    let edited = original.movingSet(at: 0, 0, toExercise: squat)

    #expect(edited.entries.map(\.exercise) == [squat])
    #expect(edited.entries[0].sets.count == 2)
}

@Test("moving from an entry that precedes an emptied source still finds the target")
func movingResolvesTargetAfterSourceRemoval() {
    // Source entry (index 0) empties and is removed; the target (squat) shifts
    // from index 1 to index 0. The transform must still land the set on squat.
    let original = Workout(
        entries: [
            Entry(exercise: bench, sets: [set(load: 100, reps: 5)]),
            Entry(exercise: squat, sets: [set(load: 140, reps: 3)]),
        ],
        startedAt: Date(timeIntervalSince1970: 0)
    )

    let edited = original.movingSet(at: 0, 0, toExercise: squat)

    #expect(edited.entries.count == 1)
    #expect(edited.entries[0].exercise == squat)
    #expect(edited.entries[0].sets.map(\.loadKilograms) == [140, 100])
}

@Test("moving a set matches the target entry by name even when aliases differ")
func movingMatchesTargetByName() {
    let squatNoAlias = Exercise(name: "Squat", aliases: [])
    let original = Workout(
        entries: [
            Entry(exercise: bench, sets: [set(load: 100, reps: 5), set(load: 100, reps: 5)]),
            Entry(exercise: squat, sets: [set(load: 140, reps: 3)]), // squat has aliases: ["squat"]
        ],
        startedAt: Date(timeIntervalSince1970: 0)
    )

    let edited = original.movingSet(at: 0, 0, toExercise: squatNoAlias)

    #expect(edited.entries.count == 2) // no duplicate "Squat" entry
    #expect(edited.entries[1].sets.count == 2)
}

@Test("a moved set keeps its axes, note, timestamp, and superset run id")
func movingCarriesEverySetField() {
    let grouped = LoggedSet(
        loadType: .added, effort: .reps, role: .warmup, grouping: .superset,
        loadKilograms: 62.5, reps: 9, supersetRunID: 3,
        loggedAt: Date(timeIntervalSince1970: 111), note: "paused"
    )
    let original = Workout(
        entries: [
            Entry(exercise: bench, sets: [set(load: 100, reps: 5), grouped]),
            Entry(exercise: squat, sets: [set(load: 140, reps: 3)]),
        ],
        startedAt: Date(timeIntervalSince1970: 0)
    )

    let edited = original.movingSet(at: 0, 1, toExercise: squat)

    #expect(edited.entries[1].sets.last == grouped)
}

@Test("moving a set at an out-of-range index changes nothing")
func movingOutOfRangeIsNoOp() {
    let original = workout([set(load: 100, reps: 5)])
    #expect(original.movingSet(at: 0, 9, toExercise: squat) == original)
    #expect(original.movingSet(at: 4, 0, toExercise: squat) == original)
}

@Test("moving a set to the exercise it is already under changes nothing")
func movingToSameExerciseIsNoOp() {
    let original = workout([set(load: 100, reps: 5), set(load: 100, reps: 5)])
    #expect(original.movingSet(at: 0, 0, toExercise: bench) == original)
}
```

Run after each: `cd Packages/WorkoutLoggerCore && swift test --filter WorkoutEditingTests`
Expected: all PASS. If `movingCarriesEverySetField` fails, the implementation is mutating a field — it should not.

- [ ] **Step 6: Full core suite + commit**

Run: `cd Packages/WorkoutLoggerCore && swift test`
Expected: all PASS (no regression in the other suites).

```bash
git add Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEditing.swift \
        Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutEditingTests.swift
git commit -m "$(cat <<'EOF'
WorkoutLoggerCore: add Workout.movingSet(at:_:toExercise:) transform

Moves a logged set to another exercise's entry — appended at the end, target
matched by name, source entry dropped if it empties, every set field carried
verbatim. Additive edit 1 of subsystem D.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
EOF
)"
```

---

## Task 2: `WorkoutEngine.editSet` mid-workout seam

**Files:**
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift`
- Test: `Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutEngineTests.swift`

**Interfaces:**
- Consumes: private `openWorkout`, `mutate(_:)`, `recomputeBest(for:)`, `retryTarget`; `Workout.replacingSet(at:_:with:)` from Task 1's file (pre-existing).
- Produces: `public func editSet(at entryIndex: Int, _ setIndex: Int, with set: LoggedSet)` on `WorkoutEngine` — no-op if there is no open workout or the index is out of range; otherwise replaces the set via `replacingSet`, then `recomputeBest(for:)` the exercise at `entryIndex` and clears `retryTarget` (unconditionally). Does not touch `activeEntryIndex`, `restStartedAt`, or `personalRecords`.

- [ ] **Step 1: Write the failing test** — edit persists and lowers the PR bar

Add inside `struct WorkoutEngineTests`, near the personal-record tests:

```swift
@Test("editSet replaces a set in the live workout, persists it, and re-derives the PR bar")
func editSetLowersPersonalRecordBar() {
    let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
    let store = InMemoryWorkoutStore()
    let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
    engine.startWorkout()
    engine.hear(["bench"])
    engine.hear(["120 for 5"])          // e1RM 140 — a personal record, bar now 140
    #expect(engine.personalRecords.count == 1)

    engine.editSet(at: 0, 0, with: LoggedSet(
        loadType: .external, effort: .reps, role: .working, grouping: .straight,
        loadKilograms: 60, reps: 5, loggedAt: Date(timeIntervalSince1970: 0)
    ))                                   // e1RM now 70 — bar drops

    #expect(engine.workout?.entries[0].sets[0].loadKilograms == 60)
    #expect(store.saved.last?.entries[0].sets[0].loadKilograms == 60)

    engine.hear(["100 for 5"])           // e1RM 116.67 — above 70, below the stale 140
    #expect(engine.personalRecords.count == 2) // caught, because the bar was re-derived
}
```

- [ ] **Step 2: Run it — expect a compile failure**

Run: `cd Packages/WorkoutLoggerCore && swift test --filter WorkoutEngineTests/editSetLowersPersonalRecordBar`
Expected: FAIL — `value of type 'WorkoutEngine' has no member 'editSet'`.

- [ ] **Step 3: Implement `editSet`**

Add to `WorkoutEngine`, immediately after `endWorkout()` (keep the public mid-workout API together):

```swift
/// Corrects the set at `entryIndex` / `setIndex` in the workout in progress —
/// the mid-workout inline edit path (spec story 38). A no-op when no workout is
/// open or the index is out of range. Runs the pure `replacingSet` transform,
/// then re-derives the exercise's running best estimated 1RM (a correction down
/// must not leave the PR bar too high) and clears the retry target, since a
/// re-spoken set must never silently overwrite a row the lifter just hand-edited.
public func editSet(at entryIndex: Int, _ setIndex: Int, with set: LoggedSet) {
    guard let current = openWorkout,
          current.entries.indices.contains(entryIndex),
          current.entries[entryIndex].sets.indices.contains(setIndex)
    else { return }
    let exercise = current.entries[entryIndex].exercise
    mutate { $0 = $0.replacingSet(at: entryIndex, setIndex, with: set) }
    retryTarget = nil
    recomputeBest(for: exercise)
}
```

- [ ] **Step 4: Run it — expect PASS**

Run: `cd Packages/WorkoutLoggerCore && swift test --filter WorkoutEngineTests/editSetLowersPersonalRecordBar`
Expected: PASS.

- [ ] **Step 5: Add the guard and retry-target cases (one at a time)**

```swift
@Test("editSet clears the retry target so a re-spoken set does not overwrite the edited row")
func editSetClearsRetryTarget() {
    let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
    let store = InMemoryWorkoutStore()
    let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
    engine.startWorkout()
    engine.hear(["bench"])
    engine.hear(["100 for 5"])          // this set becomes the retry target

    engine.editSet(at: 0, 0, with: LoggedSet(
        loadType: .external, effort: .reps, role: .working, grouping: .straight,
        loadKilograms: 105, reps: 5, loggedAt: Date(timeIntervalSince1970: 0)
    ))
    engine.hear(["100 for 5"])          // would be a retry-overwrite if the target still stood

    #expect(engine.workout?.entries[0].sets.count == 2) // appended, not overwritten
    #expect(engine.workout?.entries[0].sets.map(\.loadKilograms) == [105, 100])
}

@Test("editSet is a no-op with no open workout or an out-of-range index")
func editSetGuards() {
    let bench = Exercise(name: "Barbell Bench Press", aliases: ["bench"])
    let store = InMemoryWorkoutStore()
    let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
    let dummy = LoggedSet(
        loadType: .external, effort: .reps, role: .working, grouping: .straight,
        loadKilograms: 1, reps: 1, loggedAt: Date(timeIntervalSince1970: 0)
    )

    engine.editSet(at: 0, 0, with: dummy)          // no workout yet
    #expect(store.saved.isEmpty)

    engine.startWorkout()
    engine.hear(["bench"])
    engine.hear(["100 for 5"])
    let savesBefore = store.saved.count
    engine.editSet(at: 0, 9, with: dummy)          // set index out of range
    engine.editSet(at: 5, 0, with: dummy)          // entry index out of range
    #expect(store.saved.count == savesBefore)      // nothing persisted
}
```

Run after each: `cd Packages/WorkoutLoggerCore && swift test --filter WorkoutEngineTests`
Expected: PASS.

- [ ] **Step 6: Full core suite + commit**

Run: `cd Packages/WorkoutLoggerCore && swift test`
Expected: all PASS.

```bash
git add Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift \
        Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutEngineTests.swift
git commit -m "$(cat <<'EOF'
WorkoutLoggerCore: add WorkoutEngine.editSet mid-workout seam

Runs replacingSet on the live workout, then re-derives the exercise's PR bar and
clears the retry target. Additive edit 2 of subsystem D (part 1 of 2).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
EOF
)"
```

---

## Task 3: `WorkoutEngine.removeSet` mid-workout seam

**Files:**
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift`
- Test: `Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutEngineTests.swift`

**Interfaces:**
- Consumes: private `openWorkout`, `mutate(_:)`, `recomputeBest(for:)`, `retryTarget`, `activeEntryIndex`, the private computed `activeExerciseName`; `Workout.removingSet(at:_:)` (pre-existing).
- Produces: `public func removeSet(at entryIndex: Int, _ setIndex: Int)` on `WorkoutEngine` — no-op if no open workout or the index is out of range; otherwise removes the set via `removingSet` (which drops the entry if it empties), then `recomputeBest(for:)` the captured exercise, clears `retryTarget`, and repairs `activeEntryIndex`: it points back at the entry whose name was active before the edit, or at the last entry if that entry was the one removed, or `nil` if no entries remain. `restStartedAt` is left untouched.

- [ ] **Step 1: Write the failing test** — remove drops the emptied entry and repairs the active index

Add inside `struct WorkoutEngineTests`:

```swift
@Test("removeSet drops an emptied earlier entry and keeps the active pointer on the current exercise")
func removeSetRepairsActiveEntryAfterEmptyingEarlierEntry() {
    let bench = Exercise(name: "Bench", aliases: ["bench"])
    let squat = Exercise(name: "Squat", aliases: ["squat"])
    let store = InMemoryWorkoutStore()
    let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench, squat]))
    engine.startWorkout()
    engine.hear(["bench"]); engine.hear(["100 for 5"])   // entry 0, one set
    engine.hear(["squat"]); engine.hear(["140 for 5"])   // entry 1, active
    engine.hear(["bench"])                               // active moves back to entry 0

    engine.removeSet(at: 0, 0)                           // empties + drops entry 0; squat shifts to index 0

    #expect(engine.workout?.entries.map(\.exercise) == [squat])
    engine.hear(["150 for 3"])                           // next set must land on squat
    #expect(engine.workout?.entries[0].sets.map(\.loadKilograms) == [140, 150])
}
```

- [ ] **Step 2: Run it — expect a compile failure**

Run: `cd Packages/WorkoutLoggerCore && swift test --filter WorkoutEngineTests/removeSetRepairsActiveEntryAfterEmptyingEarlierEntry`
Expected: FAIL — `value of type 'WorkoutEngine' has no member 'removeSet'`.

- [ ] **Step 3: Implement `removeSet`**

Add to `WorkoutEngine`, right after `editSet`:

```swift
/// Deletes the set at `entryIndex` / `setIndex` from the workout in progress —
/// the mid-workout inline delete path (spec story 42). A no-op when no workout
/// is open or the index is out of range. Runs the pure `removingSet` transform
/// (which drops the entry if it empties), then re-derives the exercise's best
/// estimated 1RM, clears the retry target, and re-points `activeEntryIndex` at
/// the entry that was active before the edit — or at the last entry if that
/// entry was the one removed, or `nil` if the workout now has no entries. The
/// rest timer is left running; the lifter may still be resting.
public func removeSet(at entryIndex: Int, _ setIndex: Int) {
    guard let current = openWorkout,
          current.entries.indices.contains(entryIndex),
          current.entries[entryIndex].sets.indices.contains(setIndex)
    else { return }
    let exercise = current.entries[entryIndex].exercise
    let activeName = activeExerciseName

    mutate { $0 = $0.removingSet(at: entryIndex, setIndex) }

    retryTarget = nil
    recomputeBest(for: exercise)

    if let activeName,
       let restored = workout?.entries.firstIndex(where: { $0.exercise.name == activeName }) {
        activeEntryIndex = restored
    } else {
        activeEntryIndex = workout?.entries.indices.last
    }
}
```

- [ ] **Step 4: Run it — expect PASS**

Run: `cd Packages/WorkoutLoggerCore && swift test --filter WorkoutEngineTests/removeSetRepairsActiveEntryAfterEmptyingEarlierEntry`
Expected: PASS.

- [ ] **Step 5: Add the remaining `removeSet` cases (one at a time)**

```swift
@Test("removeSet keeps a set it did not touch and persists the smaller workout")
func removeSetDropsOnlyTheChosenSet() {
    let bench = Exercise(name: "Bench", aliases: ["bench"])
    let store = InMemoryWorkoutStore()
    let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
    engine.startWorkout()
    engine.hear(["bench"])
    engine.hear(["100 for 5"]); engine.hear(["110 for 3"]); engine.hear(["105 for 4"])

    engine.removeSet(at: 0, 1)

    #expect(engine.workout?.entries[0].sets.map(\.loadKilograms) == [100, 105])
    #expect(store.saved.last?.entries[0].sets.count == 2)
}

@Test("removeSet re-derives the PR bar so a later set beating the remaining best is caught")
func removeSetReDerivesPersonalRecordBar() {
    let bench = Exercise(name: "Bench", aliases: ["bench"])
    let store = InMemoryWorkoutStore()
    let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
    engine.startWorkout()
    engine.hear(["bench"])
    engine.hear(["100 for 5"])   // e1RM 116.67 — PR, bar 116.67
    engine.hear(["120 for 5"])   // e1RM 140    — PR, bar 140
    #expect(engine.personalRecords.count == 2)

    engine.removeSet(at: 0, 1)   // drop the 120x5; bar re-derives down to 116.67

    engine.hear(["110 for 5"])   // e1RM 128.33 — above 116.67
    #expect(engine.personalRecords.count == 3)
}

@Test("removeSet is a no-op with no open workout or an out-of-range index")
func removeSetGuards() {
    let bench = Exercise(name: "Bench", aliases: ["bench"])
    let store = InMemoryWorkoutStore()
    let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))

    engine.removeSet(at: 0, 0)
    #expect(store.saved.isEmpty)

    engine.startWorkout()
    engine.hear(["bench"]); engine.hear(["100 for 5"])
    let savesBefore = store.saved.count
    engine.removeSet(at: 0, 9)
    engine.removeSet(at: 3, 0)
    #expect(store.saved.count == savesBefore)
}

@Test("removeSet leaves the rest timer running")
func removeSetLeavesRestRunning() {
    let bench = Exercise(name: "Bench", aliases: ["bench"])
    let store = InMemoryWorkoutStore()
    var clock = Date(timeIntervalSince1970: 1_000)
    let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]), now: { clock })
    engine.startWorkout()
    engine.hear(["bench"])
    clock = Date(timeIntervalSince1970: 1_050)
    engine.hear(["100 for 5"]); engine.hear(["110 for 3"])
    let restBefore = engine.restStartedAt

    engine.removeSet(at: 0, 0)

    #expect(engine.restStartedAt == restBefore)
    #expect(engine.restStartedAt != nil)
}
```

Run after each: `cd Packages/WorkoutLoggerCore && swift test --filter WorkoutEngineTests`
Expected: PASS.

- [ ] **Step 6: Full core suite + commit — this is the last core change**

Run: `cd Packages/WorkoutLoggerCore && swift test`
Expected: all PASS.

```bash
git add Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift \
        Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutEngineTests.swift
git commit -m "$(cat <<'EOF'
WorkoutLoggerCore: add WorkoutEngine.removeSet mid-workout seam

Runs removingSet on the live workout, then re-derives the PR bar, clears the
retry target, and re-points the active entry at the current exercise (or the
last entry if it was removed). Additive edit 2 of subsystem D (part 2 of 2).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
EOF
)"
```

---

## Task 4: Shared load-formatting helpers

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Formatting/SetFormatting.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/HUDProjectionTests.swift` (the `SetFormattingTests` suite lives there)

**Interfaces:**
- Consumes: `numberString(_:)`, `MassUnit`, `LoggedSet` (pre-existing).
- Produces (all file-internal, no `public`):
  - `let kilogramsPerPound = 0.45359237` (was `private`)
  - `func gymRound(_ value: Double) -> Double` (was `private`)
  - `func loadString(_ kilograms: Double, unit: MassUnit) -> String` — `"100 kg"` / `"137.5 lb"`, converted and `gymRound`ed.
  - `func displayLoad(_ kilograms: Double, unit: MassUnit) -> Double` — the same converted, rounded number without a unit word, for chart axes.
  - `formattedSetLine` unchanged in behaviour; its reps-with-load branch now calls `loadString`.

- [ ] **Step 1: Write the failing test**

Add to the `SetFormattingTests` suite in `HUDProjectionTests.swift`:

```swift
@Test("loadString renders a kilogram value in the chosen unit")
func loadStringRule() {
    #expect(loadString(100, unit: .kilograms) == "100 kg")
    #expect(loadString(100 * 0.45359237, unit: .pounds) == "100 lb")
}

@Test("displayLoad is the converted, rounded number with no unit word")
func displayLoadRule() {
    #expect(displayLoad(100, unit: .kilograms) == 100)
    #expect(displayLoad(100 * 0.45359237, unit: .pounds) == 100)
}
```

- [ ] **Step 2: Run it — expect a compile failure**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter SetFormattingTests`
Expected: FAIL — `cannot find 'loadString' in scope`.

- [ ] **Step 3: Implement the helpers and refactor `formattedSetLine`**

In `SetFormatting.swift`, change the two `private` declarations to file-internal:

```swift
let kilogramsPerPound = 0.45359237

/// Rounds to one decimal place, absorbing the float slop a kg↔lb conversion
/// leaves behind before `numberString` decides whole-vs-fraction.
func gymRound(_ value: Double) -> Double {
    (value * 10).rounded() / 10
}
```

Add, directly below `gymRound`:

```swift
/// A load converted to the display unit and rounded, without a unit word — the
/// value a chart axis plots.
func displayLoad(_ kilograms: Double, unit: MassUnit) -> Double {
    gymRound(unit == .pounds ? kilograms / kilogramsPerPound : kilograms)
}

/// A load in the display unit, rounded and unit-labelled: "100 kg" / "137.5 lb".
func loadString(_ kilograms: Double, unit: MassUnit) -> String {
    "\(numberString(displayLoad(kilograms, unit: unit))) \(unit == .pounds ? "lb" : "kg")"
}
```

Then, inside `formattedSetLine`, replace exactly this fragment of the `.reps` case:

```swift
        if let kg = set.loadKilograms, kg > 0 {
            let shown = gymRound(unit == .pounds ? kg / kilogramsPerPound : kg)
            let word = unit == .pounds ? "lb" : "kg"
            line = "\(numberString(shown)) \(word) × \(reps)"
        } else {
```

with:

```swift
        if let kg = set.loadKilograms, kg > 0 {
            line = "\(loadString(kg, unit: unit)) × \(reps)"
        } else {
```

Leave the `warm-up ` prefix and the ` · superset` / ` · dropset` suffix logic untouched.

- [ ] **Step 4: Run it — expect PASS, no regression**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter SetFormattingTests`
Expected: PASS — including the pre-existing `repsWithLoad` / `poundsConversion` cases (behaviour is unchanged).

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Formatting/SetFormatting.swift \
        Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/HUDProjectionTests.swift
git commit -m "$(cat <<'EOF'
WorkoutLoggerApp: extract loadString/displayLoad from formattedSetLine

Widens gymRound and kilogramsPerPound to file-internal and adds two shared
load-formatting helpers the summary and progress projections will reuse.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
EOF
)"
```

---

## Task 5: `WorkoutSummaryProjection`

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/WorkoutSummaryProjection.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSummaryProjectionTests.swift`

**Interfaces:**
- Consumes: `Workout`, `Entry`, `LoggedSet`, `Exercise`, `MassUnit`, `exerciseProgress(for:across:)`, `estimatedOneRepMax(loadKilograms:reps:)` (core); `formattedSetLine(_:unit:)`, `loadString(_:unit:)` (Task 4).
- Produces:
  ```swift
  public struct WorkoutSummaryProjection: Equatable, Sendable {
      public struct SetRow: Equatable, Sendable {
          public var line: String
          public var isPersonalRecord: Bool
      }
      public struct EntryRow: Equatable, Sendable {
          public var exerciseName: String
          public var sets: [SetRow]
      }
      public var entries: [EntryRow]
      public var totalVolumeText: String     // e.g. "1,720 kg" — loadString of Σ(load×reps) over working sets
      public var totalWorkingReps: Int
      public var durationText: String        // "48 min" from startedAt ..< (endedAt ?? lastActivityAt)
      public var note: String?

      public init(entries: [EntryRow], totalVolumeText: String, totalWorkingReps: Int,
                  durationText: String, note: String?)               // memberwise
      public init(workout: Workout, priorHistory: [Workout], unit: MassUnit)
  }
  ```
  PR badge: within each entry, the working set with the greatest Epley e1RM is badged **iff** `exerciseProgress(for: entry.exercise, across: priorHistory).bestEstimatedOneRepMaxKilograms` is non-nil and that max e1RM strictly exceeds it. At most one badge per entry. Warm-up sets never badged, never in the volume/reps totals.

- [ ] **Step 1: Write the first failing test** — set lines and totals

```swift
import Foundation
import Testing
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("WorkoutSummaryProjection")
struct WorkoutSummaryProjectionTests {

    private let bench = Exercise(name: "Bench", aliases: ["bench"])
    private let squat = Exercise(name: "Squat", aliases: ["squat"])

    private func working(_ load: Double, _ reps: Int) -> LoggedSet {
        LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                  loadKilograms: load, reps: reps, loggedAt: Date(timeIntervalSince1970: 0))
    }
    private func warmup(_ load: Double, _ reps: Int) -> LoggedSet {
        LoggedSet(loadType: .external, effort: .reps, role: .warmup, grouping: .straight,
                  loadKilograms: load, reps: reps, loggedAt: Date(timeIntervalSince1970: 0))
    }

    @Test("entry rows carry formatted set lines; totals cover working sets only")
    func rowsAndTotals() {
        let workout = Workout(
            entries: [Entry(exercise: bench, sets: [warmup(60, 10), working(100, 5), working(100, 5)])],
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 48 * 60)
        )

        let p = WorkoutSummaryProjection(workout: workout, priorHistory: [], unit: .kilograms)

        #expect(p.entries.count == 1)
        #expect(p.entries[0].exerciseName == "Bench")
        #expect(p.entries[0].sets.map(\.line) == ["warm-up 60 kg × 10", "100 kg × 5", "100 kg × 5"])
        #expect(p.totalWorkingReps == 10)          // 5 + 5; the warm-up's 10 do not count
        #expect(p.totalVolumeText == "1000 kg")    // 100*5 + 100*5
        #expect(p.durationText == "48 min")
    }
}
```

- [ ] **Step 2: Run it — expect a compile failure**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSummaryProjectionTests`
Expected: FAIL — `cannot find 'WorkoutSummaryProjection' in scope`.

- [ ] **Step 3: Implement the projection**

Create `History/WorkoutSummaryProjection.swift`:

```swift
import Foundation
import WorkoutLoggerCore

/// Everything the completed-workout detail screen renders, derived from one
/// `Workout` plus the history that precedes it. Pure and `swift test`-covered so
/// the SwiftUI view stays a dumb renderer. Warm-up sets are shown but excluded
/// from every total and from personal-record consideration (CONTEXT.md "Role").
public struct WorkoutSummaryProjection: Equatable, Sendable {
    public struct SetRow: Equatable, Sendable {
        public var line: String
        public var isPersonalRecord: Bool
        public init(line: String, isPersonalRecord: Bool) {
            self.line = line
            self.isPersonalRecord = isPersonalRecord
        }
    }

    public struct EntryRow: Equatable, Sendable {
        public var exerciseName: String
        public var sets: [SetRow]
        public init(exerciseName: String, sets: [SetRow]) {
            self.exerciseName = exerciseName
            self.sets = sets
        }
    }

    public var entries: [EntryRow]
    public var totalVolumeText: String
    public var totalWorkingReps: Int
    public var durationText: String
    public var note: String?

    public init(entries: [EntryRow], totalVolumeText: String, totalWorkingReps: Int,
                durationText: String, note: String?) {
        self.entries = entries
        self.totalVolumeText = totalVolumeText
        self.totalWorkingReps = totalWorkingReps
        self.durationText = durationText
        self.note = note
    }

    public init(workout: Workout, priorHistory: [Workout], unit: MassUnit) {
        entries = workout.entries.map { entry in
            let priorBest = exerciseProgress(for: entry.exercise, across: priorHistory)
                .bestEstimatedOneRepMaxKilograms
            let recordSetIndex = Self.personalRecordSetIndex(in: entry.sets, beating: priorBest)
            let rows = entry.sets.enumerated().map { index, set in
                SetRow(line: formattedSetLine(set, unit: unit), isPersonalRecord: index == recordSetIndex)
            }
            return EntryRow(exerciseName: entry.exercise.name, sets: rows)
        }

        let working = workout.entries.flatMap(\.sets).filter { $0.role == .working }
        let volume = working.reduce(0.0) { running, set in
            guard let load = set.loadKilograms, let reps = set.reps else { return running }
            return running + load * Double(reps)
        }
        totalVolumeText = loadString(volume, unit: unit)
        totalWorkingReps = working.reduce(0) { $0 + ($1.reps ?? 0) }

        let end = workout.endedAt ?? workout.lastActivityAt
        let minutes = Int(end.timeIntervalSince(workout.startedAt) / 60)
        durationText = "\(minutes) min"

        note = workout.note
    }

    /// The index of the working set with the greatest Epley estimate, but only
    /// when `priorBest` exists and that estimate strictly clears it. `nil`
    /// otherwise — no prior history for the exercise means nothing to beat.
    private static func personalRecordSetIndex(in sets: [LoggedSet], beating priorBest: Double?) -> Int? {
        guard let priorBest else { return nil }
        var bestIndex: Int?
        var bestEstimate = priorBest
        for (index, set) in sets.enumerated() {
            guard set.role == .working, let load = set.loadKilograms, let reps = set.reps else { continue }
            let estimate = estimatedOneRepMax(loadKilograms: load, reps: reps)
            if estimate > bestEstimate {
                bestEstimate = estimate
                bestIndex = index
            }
        }
        return bestIndex
    }
}
```

- [ ] **Step 4: Run it — expect PASS**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSummaryProjectionTests`
Expected: PASS.

- [ ] **Step 5: Add the PR-badge and note cases (one at a time)**

```swift
@Test("a working set that beats prior history's best estimated 1RM is badged")
func personalRecordBadged() {
    let prior = [Workout(
        entries: [Entry(exercise: bench, sets: [working(100, 5)])],   // e1RM 116.67
        startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60)
    )]
    let today = Workout(
        entries: [Entry(exercise: bench, sets: [working(100, 5), working(120, 5)])], // 116.67, 140
        startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_060)
    )

    let p = WorkoutSummaryProjection(workout: today, priorHistory: prior, unit: .kilograms)

    #expect(p.entries[0].sets.map(\.isPersonalRecord) == [false, true])
}

@Test("the first working set ever recorded for an exercise is not badged")
func firstEverSetNotBadged() {
    let today = Workout(
        entries: [Entry(exercise: bench, sets: [working(140, 5)])],
        startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60)
    )

    let p = WorkoutSummaryProjection(workout: today, priorHistory: [], unit: .kilograms)

    #expect(p.entries[0].sets.map(\.isPersonalRecord) == [false])
}

@Test("a set that only ties the prior best is not badged")
func tieNotBadged() {
    let prior = [Workout(
        entries: [Entry(exercise: bench, sets: [working(100, 5)])],
        startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60)
    )]
    let today = Workout(
        entries: [Entry(exercise: bench, sets: [working(100, 5)])],  // identical e1RM
        startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_060)
    )

    let p = WorkoutSummaryProjection(workout: today, priorHistory: prior, unit: .kilograms)

    #expect(p.entries[0].sets.allSatisfy { !$0.isPersonalRecord })
}

@Test("a warmup that would out-estimate prior history is never badged")
func warmupNeverBadged() {
    let prior = [Workout(
        entries: [Entry(exercise: bench, sets: [working(100, 5)])],
        startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60)
    )]
    let today = Workout(
        entries: [Entry(exercise: bench, sets: [warmup(200, 5), working(100, 5)])],
        startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_060)
    )

    let p = WorkoutSummaryProjection(workout: today, priorHistory: prior, unit: .kilograms)

    #expect(p.entries[0].sets.map(\.isPersonalRecord) == [false, false])
}

@Test("the workout note is surfaced, and nil when absent")
func noteSurfaced() {
    let base = Workout(entries: [Entry(exercise: bench, sets: [working(100, 5)])],
                       startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60))
    #expect(WorkoutSummaryProjection(workout: base, priorHistory: [], unit: .kilograms).note == nil)

    let annotated = base.annotated(with: "felt easy")
    #expect(WorkoutSummaryProjection(workout: annotated, priorHistory: [], unit: .kilograms).note == "felt easy")
}

@Test("a pounds projection formats the volume total in pounds")
func poundsVolume() {
    let today = Workout(
        entries: [Entry(exercise: bench, sets: [working(100 * 0.45359237, 5)])],
        startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60)
    )
    let p = WorkoutSummaryProjection(workout: today, priorHistory: [], unit: .pounds)
    #expect(p.totalVolumeText == "500 lb")   // 100 lb × 5
}
```

Run after each: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSummaryProjectionTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/WorkoutSummaryProjection.swift \
        Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSummaryProjectionTests.swift
git commit -m "$(cat <<'EOF'
WorkoutLoggerApp: add WorkoutSummaryProjection

Pure projection for the completed-workout detail screen: entry rows with
formatted set lines, per-entry PR badge vs prior history, working-set volume and
rep totals, duration, and the workout note.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
EOF
)"
```

---

## Task 6: `ExerciseProgressProjection`

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Progress/ExerciseProgressProjection.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/ExerciseProgressProjectionTests.swift`

**Interfaces:**
- Consumes: `ExerciseProgress`, `ExerciseSession` (core); `displayLoad(_:unit:)`, `loadString(_:unit:)` (Task 4); `MassUnit`.
- Produces:
  ```swift
  public struct ExerciseProgressProjection: Equatable, Sendable {
      public struct Point: Equatable, Sendable {
          public var date: Date
          public var value: Double            // already in the display unit
      }
      public struct Comparison: Equatable, Sendable {
          public var topSetLoadDelta: Double?      // display unit; nil if either session had no top set
          public var volumeDelta: Double           // display unit
          public var estimatedOneRepMaxDelta: Double?
      }
      public var loadSeries: [Point]                // one per session that had a top set load
      public var volumeSeries: [Point]              // one per session
      public var estimatedOneRepMaxSeries: [Point]  // one per session that had an estimate
      public var topSetText: String?               // most recent session: "<load> · e1RM <load>" (e1RM clause dropped if nil), nil if no top set
      public var comparison: Comparison?           // last vs previous session; nil with < 2 sessions

      public init(loadSeries: [Point], volumeSeries: [Point], estimatedOneRepMaxSeries: [Point],
                  topSetText: String?, comparison: Comparison?)          // memberwise
      public init(progress: ExerciseProgress, unit: MassUnit)
  }
  ```
  `progress.sessions` is oldest-first (the core guarantees history order; Task 8 feeds it oldest-first). All load-like values pass through `displayLoad`; `volumeDelta` and `volumeSeries` convert the kilogram tonnage the same way.

- [ ] **Step 1: Write the first failing test** — series and top-set line

```swift
import Foundation
import Testing
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("ExerciseProgressProjection")
struct ExerciseProgressProjectionTests {

    private func session(_ t: TimeInterval, volume: Double, reps: Int, top: Double?, e1rm: Double?) -> ExerciseSession {
        ExerciseSession(date: Date(timeIntervalSince1970: t), volumeKilograms: volume,
                        workingReps: reps, topSetLoadKilograms: top, bestEstimatedOneRepMaxKilograms: e1rm)
    }

    @Test("each session becomes one point per series, oldest first, and the top-set line is the latest session")
    func seriesAndTopSet() {
        let progress = ExerciseProgress(sessions: [
            session(1_000, volume: 1_000, reps: 10, top: 100, e1rm: 116.67),
            session(2_000, volume: 1_200, reps: 12, top: 110, e1rm: 128.33),
        ])

        let p = ExerciseProgressProjection(progress: progress, unit: .kilograms)

        #expect(p.loadSeries.map(\.value) == [100, 110])
        #expect(p.loadSeries.map(\.date) == [Date(timeIntervalSince1970: 1_000), Date(timeIntervalSince1970: 2_000)])
        #expect(p.volumeSeries.map(\.value) == [1_000, 1_200])
        // every plotted value passes through displayLoad -> gymRound (1 decimal)
        #expect(p.estimatedOneRepMaxSeries.map(\.value) == [116.7, 128.3])
        // topSetLoad 110 -> "110 kg"; e1RM 128.33 -> "128.3 kg"
        #expect(p.topSetText == "110 kg · e1RM 128.3 kg")
    }
}
```

- [ ] **Step 2: Run it — expect a compile failure**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter ExerciseProgressProjectionTests`
Expected: FAIL — `cannot find 'ExerciseProgressProjection' in scope`.

- [ ] **Step 3: Implement the projection**

Create `Progress/ExerciseProgressProjection.swift`:

```swift
import Foundation
import WorkoutLoggerCore

/// Everything the per-exercise progress screen draws, derived from the core's
/// `ExerciseProgress`. Pure and `swift test`-covered. `ExerciseProgress.sessions`
/// carries no rep count or full set, so the top-set call-out and comparison are
/// load and estimated-1RM only — never a "load × reps" line.
public struct ExerciseProgressProjection: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var date: Date
        public var value: Double
        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    public struct Comparison: Equatable, Sendable {
        public var topSetLoadDelta: Double?
        public var volumeDelta: Double
        public var estimatedOneRepMaxDelta: Double?
        public init(topSetLoadDelta: Double?, volumeDelta: Double, estimatedOneRepMaxDelta: Double?) {
            self.topSetLoadDelta = topSetLoadDelta
            self.volumeDelta = volumeDelta
            self.estimatedOneRepMaxDelta = estimatedOneRepMaxDelta
        }
    }

    public var loadSeries: [Point]
    public var volumeSeries: [Point]
    public var estimatedOneRepMaxSeries: [Point]
    public var topSetText: String?
    public var comparison: Comparison?

    public init(loadSeries: [Point], volumeSeries: [Point], estimatedOneRepMaxSeries: [Point],
                topSetText: String?, comparison: Comparison?) {
        self.loadSeries = loadSeries
        self.volumeSeries = volumeSeries
        self.estimatedOneRepMaxSeries = estimatedOneRepMaxSeries
        self.topSetText = topSetText
        self.comparison = comparison
    }

    public init(progress: ExerciseProgress, unit: MassUnit) {
        let sessions = progress.sessions
        loadSeries = sessions.compactMap { s in
            s.topSetLoadKilograms.map { Point(date: s.date, value: displayLoad($0, unit: unit)) }
        }
        volumeSeries = sessions.map { Point(date: $0.date, value: displayLoad($0.volumeKilograms, unit: unit)) }
        estimatedOneRepMaxSeries = sessions.compactMap { s in
            s.bestEstimatedOneRepMaxKilograms.map { Point(date: s.date, value: displayLoad($0, unit: unit)) }
        }
        if let last = sessions.last, let top = last.topSetLoadKilograms {
            if let e1rm = last.bestEstimatedOneRepMaxKilograms {
                topSetText = "\(loadString(top, unit: unit)) · e1RM \(loadString(e1rm, unit: unit))"
            } else {
                topSetText = loadString(top, unit: unit)
            }
        } else {
            topSetText = nil
        }

        if sessions.count >= 2 {
            let last = sessions[sessions.count - 1]
            let prev = sessions[sessions.count - 2]
            comparison = Comparison(
                topSetLoadDelta: delta(last.topSetLoadKilograms, prev.topSetLoadKilograms, unit: unit),
                volumeDelta: displayLoad(last.volumeKilograms, unit: unit)
                    - displayLoad(prev.volumeKilograms, unit: unit),
                estimatedOneRepMaxDelta: delta(last.bestEstimatedOneRepMaxKilograms,
                                               prev.bestEstimatedOneRepMaxKilograms, unit: unit)
            )
        } else {
            comparison = nil
        }
    }

    private func delta(_ a: Double?, _ b: Double?, unit: MassUnit) -> Double? {
        guard let a, let b else { return nil }
        return displayLoad(a, unit: unit) - displayLoad(b, unit: unit)
    }
}
```

- [ ] **Step 4: Run it — expect PASS**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter ExerciseProgressProjectionTests`
Expected: PASS.

- [ ] **Step 5: Add the comparison, pounds, and empty cases (one at a time)**

```swift
@Test("the comparison is the last two sessions' deltas")
func comparisonDeltas() {
    let progress = ExerciseProgress(sessions: [
        session(1_000, volume: 1_000, reps: 10, top: 100, e1rm: 110),
        session(2_000, volume: 1_150, reps: 11, top: 105, e1rm: 118),
    ])

    let c = ExerciseProgressProjection(progress: progress, unit: .kilograms).comparison

    #expect(c?.topSetLoadDelta == 5)
    #expect(c?.volumeDelta == 150)
    #expect(c?.estimatedOneRepMaxDelta == 8)
}

@Test("fewer than two sessions means no comparison")
func noComparisonWithOneSession() {
    let progress = ExerciseProgress(sessions: [session(1_000, volume: 1_000, reps: 10, top: 100, e1rm: 110)])
    let p = ExerciseProgressProjection(progress: progress, unit: .kilograms)
    #expect(p.comparison == nil)
    #expect(p.loadSeries.count == 1)
}

@Test("an empty progress yields empty series and no comparison")
func empty() {
    let p = ExerciseProgressProjection(progress: ExerciseProgress(sessions: []), unit: .kilograms)
    #expect(p.loadSeries.isEmpty)
    #expect(p.volumeSeries.isEmpty)
    #expect(p.estimatedOneRepMaxSeries.isEmpty)
    #expect(p.topSetText == nil)
    #expect(p.comparison == nil)
}

@Test("a bodyweight session contributes a volume point but no load or estimate point")
func bodyweightSessionSparseSeries() {
    let progress = ExerciseProgress(sessions: [
        session(1_000, volume: 0, reps: 30, top: nil, e1rm: nil),
        session(2_000, volume: 0, reps: 33, top: nil, e1rm: nil),
    ])
    let p = ExerciseProgressProjection(progress: progress, unit: .kilograms)
    #expect(p.loadSeries.isEmpty)
    #expect(p.estimatedOneRepMaxSeries.isEmpty)
    #expect(p.volumeSeries.map(\.value) == [0, 0])
    #expect(p.topSetText == nil)                  // last session has no top set
    #expect(p.comparison?.topSetLoadDelta == nil)
    #expect(p.comparison?.volumeDelta == 0)
}

@Test("a pounds projection converts every plotted value")
func poundsSeries() {
    let progress = ExerciseProgress(sessions: [
        session(1_000, volume: 100 * 0.45359237, reps: 1, top: 100 * 0.45359237, e1rm: 100 * 0.45359237),
    ])
    let p = ExerciseProgressProjection(progress: progress, unit: .pounds)
    #expect(p.loadSeries.map(\.value) == [100])
    #expect(p.volumeSeries.map(\.value) == [100])
    #expect(p.topSetText == "100 lb · e1RM 100 lb")
}
```

Run after each: `cd Packages/WorkoutLoggerApp && swift test --filter ExerciseProgressProjectionTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Progress/ExerciseProgressProjection.swift \
        Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/ExerciseProgressProjectionTests.swift
git commit -m "$(cat <<'EOF'
WorkoutLoggerApp: add ExerciseProgressProjection

Turns the core ExerciseProgress into unit-converted chart series (load, volume,
estimated 1RM), a heaviest-set line, and a two-session "vs last time" comparison.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
EOF
)"
```

---

## Task 7: `WorkoutHistoryStore` protocol + `WorkoutHistoryModel`

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/WorkoutHistoryStore.swift`
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/WorkoutHistoryModel.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutHistoryModelTests.swift`

**Interfaces:**
- Consumes: `Workout` (core); `SwiftDataWorkoutStore` (`history()`, `save(_:)`, `lastSaveError` — all pre-existing).
- Produces:
  ```swift
  public protocol WorkoutHistoryStore: AnyObject {
      func history() -> [Workout]
      func save(_ workout: Workout)
      var lastSaveError: Error? { get }
  }
  extension SwiftDataWorkoutStore: WorkoutHistoryStore {}

  @MainActor @Observable
  public final class WorkoutHistoryModel {
      public private(set) var rows: [Workout]        // completed only, newest first
      public private(set) var selected: Workout?
      public private(set) var saveError: String?
      public let isUnavailable: Bool

      public init(store: WorkoutHistoryStore, historyUnavailable: Bool = false)
      public func reload()
      public func open(_ workout: Workout)                       // re-selects rows.first { $0.startedAt == workout.startedAt }
      public func applyEdit(_ transform: (Workout) -> Workout)   // transform selected → save → (on lastSaveError) set saveError & bail, else reload + re-select
  }
  ```

- [ ] **Step 1: Write the first failing test** — loads completed workouts newest-first

```swift
import Foundation
import Testing
import SwiftData
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("WorkoutHistoryModel")
@MainActor
struct WorkoutHistoryModelTests {

    private let bench = Exercise(name: "Bench", aliases: ["bench"])

    private func inMemoryStore() throws -> SwiftDataWorkoutStore {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return SwiftDataWorkoutStore(context: ModelContext(container))
    }

    private func working(_ load: Double, _ reps: Int) -> LoggedSet {
        LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                  loadKilograms: load, reps: reps, loggedAt: Date(timeIntervalSince1970: 0))
    }

    private func workout(started: TimeInterval, ended: TimeInterval?, sets: [LoggedSet]) -> Workout {
        Workout(entries: [Entry(exercise: bench, sets: sets)],
                startedAt: Date(timeIntervalSince1970: started),
                endedAt: ended.map { Date(timeIntervalSince1970: $0) })
    }

    @Test("rows are the completed workouts, newest first; an open workout is excluded")
    func loadsCompletedNewestFirst() throws {
        let store = try inMemoryStore()
        store.save(workout(started: 1_000, ended: 1_500, sets: [working(100, 5)]))
        store.save(workout(started: 3_000, ended: 3_500, sets: [working(110, 5)]))
        store.save(workout(started: 5_000, ended: nil, sets: [working(120, 5)])) // open

        let model = WorkoutHistoryModel(store: store)

        #expect(model.rows.map(\.startedAt) == [
            Date(timeIntervalSince1970: 3_000), Date(timeIntervalSince1970: 1_000),
        ])
        #expect(model.isUnavailable == false)
    }
}
```

- [ ] **Step 2: Run it — expect a compile failure**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutHistoryModelTests`
Expected: FAIL — `cannot find 'WorkoutHistoryModel' in scope`.

- [ ] **Step 3: Implement the protocol and the model**

Create `History/WorkoutHistoryStore.swift`:

```swift
import Foundation
import WorkoutLoggerCore

/// The slice of persistence the history and progress models need: read all
/// stored workouts, write one back, and see whether the last write failed.
/// `SwiftDataWorkoutStore` already has every member.
public protocol WorkoutHistoryStore: AnyObject {
    func history() -> [Workout]
    func save(_ workout: Workout)
    var lastSaveError: Error? { get }
}

extension SwiftDataWorkoutStore: WorkoutHistoryStore {}
```

Create `History/WorkoutHistoryModel.swift`:

```swift
import Foundation
import Observation
import WorkoutLoggerCore

/// Owns the completed-workout list and the edit-then-resave loop for the detail
/// screen. Editing runs a pure `WorkoutLoggerCore` transform on the open workout
/// and saves the result under its unchanged `startedAt`, so an edit overwrites
/// the workout's own record — never a duplicate (spec story 35).
@MainActor
@Observable
public final class WorkoutHistoryModel {
    /// Completed workouts, most recent first.
    public private(set) var rows: [Workout] = []
    /// The workout open on the detail screen, or `nil`.
    public private(set) var selected: Workout?
    /// A human-readable description of the last failed save, or `nil`.
    public private(set) var saveError: String?
    /// Storage could not be opened at launch — the list shows "unavailable",
    /// distinct from an empty history (spec story 10 vs 9).
    public let isUnavailable: Bool

    @ObservationIgnored private let store: WorkoutHistoryStore

    public init(store: WorkoutHistoryStore, historyUnavailable: Bool = false) {
        self.store = store
        self.isUnavailable = historyUnavailable
        reload()
    }

    public func reload() {
        rows = isUnavailable ? [] : Array(store.history().filter(\.isEnded).reversed())
    }

    public func open(_ workout: Workout) {
        selected = rows.first { $0.startedAt == workout.startedAt }
    }

    /// Applies `transform` to the open workout, saves it, and reloads the list.
    /// The store never throws — it records a failure in `lastSaveError` — so on a
    /// failure this discards the edited copy, leaves `selected` as it was, and
    /// skips the reload, keeping the on-screen state honest about what persisted.
    public func applyEdit(_ transform: (Workout) -> Workout) {
        guard let current = selected else { return }
        let edited = transform(current)
        store.save(edited)
        if let error = store.lastSaveError {
            saveError = String(describing: error)
            return
        }
        saveError = nil
        reload()
        selected = rows.first { $0.startedAt == edited.startedAt }
    }
}
```

Note: `reversed()` on an `Array` returns a `ReversedCollection`, so the `Array(...)` wrapper is required to assign to the `[Workout]` property.

- [ ] **Step 4: Run it — expect PASS**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutHistoryModelTests`
Expected: PASS.

- [ ] **Step 5: Add edit, save-failure, and unavailable cases (one at a time)**

Add a failing-store fake at the bottom of the test file:

```swift
private final class FailingHistoryStore: WorkoutHistoryStore {
    private var stored: [Workout]
    var lastSaveError: Error?
    struct Boom: Error {}

    init(_ stored: [Workout]) { self.stored = stored }
    func history() -> [Workout] { stored }
    func save(_ workout: Workout) { lastSaveError = Boom() } // never actually stores
}
```

```swift
@Test("applyEdit with replacingSet persists the change and re-selects the workout")
func editPersistsAndReSelects() throws {
    let store = try inMemoryStore()
    store.save(workout(started: 1_000, ended: 1_500, sets: [working(100, 5), working(100, 5)]))
    let model = WorkoutHistoryModel(store: store)
    model.open(model.rows[0])

    model.applyEdit { $0.replacingSet(at: 0, 1, with: working(90, 8)) }

    #expect(model.saveError == nil)
    #expect(model.rows.count == 1)                                  // no duplicate
    #expect(model.selected?.startedAt == Date(timeIntervalSince1970: 1_000))
    #expect(model.selected?.entries[0].sets.map(\.reps) == [5, 8])
    #expect(store.history().first?.entries[0].sets.map(\.reps) == [5, 8]) // actually stored
}

@Test("applyEdit with movingSet relocates the set in the stored workout")
func editMovesSet() throws {
    let squat = Exercise(name: "Squat", aliases: ["squat"])
    let store = try inMemoryStore()
    let w = Workout(
        entries: [
            Entry(exercise: bench, sets: [working(100, 5), working(100, 5)]),
            Entry(exercise: squat, sets: [working(140, 5)]),
        ],
        startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_500)
    )
    store.save(w)
    let model = WorkoutHistoryModel(store: store)
    model.open(model.rows[0])

    model.applyEdit { $0.movingSet(at: 0, 0, toExercise: squat) }

    #expect(model.selected?.entries.map { $0.exercise.name } == ["Bench", "Squat"])
    #expect(model.selected?.entries[1].sets.count == 2)
}

@Test("applyEdit with removingSet drops the set, and the entry if it empties")
func editRemovesSet() throws {
    let store = try inMemoryStore()
    store.save(workout(started: 1_000, ended: 1_500, sets: [working(100, 5)]))
    let model = WorkoutHistoryModel(store: store)
    model.open(model.rows[0])

    model.applyEdit { $0.removingSet(at: 0, 0) }

    #expect(model.selected?.entries.isEmpty == true)
}

@Test("applyEdit with annotated persists the workout note")
func editAnnotates() throws {
    let store = try inMemoryStore()
    store.save(workout(started: 1_000, ended: 1_500, sets: [working(100, 5)]))
    let model = WorkoutHistoryModel(store: store)
    model.open(model.rows[0])

    model.applyEdit { $0.annotated(with: "tough session") }

    #expect(model.selected?.note == "tough session")
    #expect(store.history().first?.note == "tough session")
}

@Test("a failed save leaves the open workout untouched, records the error, and does not reload")
func saveFailureIsSurfaced() {
    let w = Workout(entries: [Entry(exercise: bench, sets: [working(100, 5)])],
                    startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_500))
    let store = FailingHistoryStore([w])
    let model = WorkoutHistoryModel(store: store)
    model.open(model.rows[0])
    let before = model.selected

    model.applyEdit { $0.annotated(with: "should not stick") }

    #expect(model.saveError != nil)
    #expect(model.selected == before)          // unchanged
}

@Test("an unavailable store yields no rows and the unavailable flag")
func unavailable() throws {
    let store = try inMemoryStore()
    store.save(workout(started: 1_000, ended: 1_500, sets: [working(100, 5)]))

    let model = WorkoutHistoryModel(store: store, historyUnavailable: true)

    #expect(model.rows.isEmpty)
    #expect(model.isUnavailable)
}
```

Run after each: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutHistoryModelTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/WorkoutHistoryStore.swift \
        Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/WorkoutHistoryModel.swift \
        Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutHistoryModelTests.swift
git commit -m "$(cat <<'EOF'
WorkoutLoggerApp: add WorkoutHistoryModel + WorkoutHistoryStore

Loads completed workouts newest-first, opens one for the detail screen, and runs
an edit transform through save-then-reload with a non-blocking error path when
the store reports lastSaveError.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
EOF
)"
```

---

## Task 8: `ExerciseProgressModel`

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Progress/ExerciseProgressModel.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/ExerciseProgressModelTests.swift`

**Interfaces:**
- Consumes: `Exercise`, `MassUnit`, `exerciseProgress(for:across:)` (core); `WorkoutHistoryStore` (Task 7); `ExerciseProgressProjection` (Task 6).
- Produces:
  ```swift
  @MainActor @Observable
  public final class ExerciseProgressModel {
      public private(set) var projection: ExerciseProgressProjection
      public init(exercise: Exercise, store: WorkoutHistoryStore, unit: MassUnit, historyUnavailable: Bool = false)
  }
  ```
  Pulls `store.history().filter(\.isEnded)` (already oldest-first — `SwiftDataWorkoutStore.history()` sorts `.startedAt` forward), runs `exerciseProgress(for:across:)`, wraps it in `ExerciseProgressProjection(progress:unit:)`. Unavailable → empty history → empty projection.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
import SwiftData
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("ExerciseProgressModel")
@MainActor
struct ExerciseProgressModelTests {

    private let bench = Exercise(name: "Bench", aliases: ["bench"])
    private let squat = Exercise(name: "Squat", aliases: ["squat"])

    private func inMemoryStore() throws -> SwiftDataWorkoutStore {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return SwiftDataWorkoutStore(context: ModelContext(container))
    }

    private func working(_ load: Double, _ reps: Int) -> LoggedSet {
        LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                  loadKilograms: load, reps: reps, loggedAt: Date(timeIntervalSince1970: 0))
    }

    private func workout(_ started: TimeInterval, _ exercise: Exercise, _ sets: [LoggedSet]) -> Workout {
        Workout(entries: [Entry(exercise: exercise, sets: sets)],
                startedAt: Date(timeIntervalSince1970: started),
                endedAt: Date(timeIntervalSince1970: started + 60))
    }

    @Test("the model folds only the completed workouts that used the exercise, oldest first")
    func foldsMatchingCompletedWorkouts() throws {
        let store = try inMemoryStore()
        store.save(workout(1_000, bench, [working(100, 5)]))
        store.save(workout(2_000, squat, [working(140, 5)]))   // different exercise
        store.save(workout(3_000, bench, [working(105, 5)]))

        let model = ExerciseProgressModel(exercise: bench, store: store, unit: .kilograms)

        #expect(model.projection.volumeSeries.map(\.value) == [500, 525])
        #expect(model.projection.comparison?.volumeDelta == 25)
    }

    @Test("an unavailable store yields an empty projection, not a crash")
    func unavailableIsEmpty() throws {
        let store = try inMemoryStore()
        store.save(workout(1_000, bench, [working(100, 5)]))

        let model = ExerciseProgressModel(exercise: bench, store: store, unit: .kilograms,
                                          historyUnavailable: true)

        #expect(model.projection.volumeSeries.isEmpty)
        #expect(model.projection.comparison == nil)
    }
}
```

- [ ] **Step 2: Run it — expect a compile failure**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter ExerciseProgressModelTests`
Expected: FAIL — `cannot find 'ExerciseProgressModel' in scope`.

- [ ] **Step 3: Implement the model**

Create `Progress/ExerciseProgressModel.swift`:

```swift
import Foundation
import Observation
import WorkoutLoggerCore

/// Backs the per-exercise progress screen. Reads completed history once at
/// construction, folds it with the core `exerciseProgress` function, and holds
/// the drawable projection. Rebuilt (not mutated) when the screen is reopened.
@MainActor
@Observable
public final class ExerciseProgressModel {
    public private(set) var projection: ExerciseProgressProjection

    public init(exercise: Exercise, store: WorkoutHistoryStore, unit: MassUnit,
                historyUnavailable: Bool = false) {
        let history = historyUnavailable ? [] : store.history().filter(\.isEnded)
        let progress = exerciseProgress(for: exercise, across: history)
        projection = ExerciseProgressProjection(progress: progress, unit: unit)
    }
}
```

- [ ] **Step 4: Run it — expect PASS**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter ExerciseProgressModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Progress/ExerciseProgressModel.swift \
        Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/ExerciseProgressModelTests.swift
git commit -m "$(cat <<'EOF'
WorkoutLoggerApp: add ExerciseProgressModel

Reads completed history, folds it with exerciseProgress, and holds an
ExerciseProgressProjection for the progress screen.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
EOF
)"
```

---

## Task 9: `WorkoutSessionModel` — history injection + "previous workout" line

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift`

**Interfaces:**
- Consumes: `exerciseProgress(for:across:)`, `ExerciseSession`, `Exercise` (core); `loadString(_:unit:)` (Task 4); the existing `library`, `unit`, `updateActiveExercise(from:)`, `activeExerciseName`.
- Produces:
  - New init parameter `history: @escaping () -> [Workout] = { [] }`, stored as `@ObservationIgnored private let history`.
  - `public private(set) var previousWorkoutLine: String?` — set whenever `activeExerciseName` is recomputed. Format: `"Last time: top <load> · best e1RM <load>"` (either clause dropped if its value is `nil`; the whole line `nil` if the exercise is new, not in the library, or has no prior loaded session). Loads via `loadString`.
  - `static func previousWorkoutLine(for exercise: Exercise, unit: MassUnit, history: [Workout], excluding openStartedAt: Date?) -> String?` — filters `history` to `isEnded && startedAt != openStartedAt`, runs `exerciseProgress`, formats `.sessions.last`.

- [ ] **Step 1: Update `makeRig` in `WorkoutSessionModelTests.swift`**

The suite's shared `Self.library` has only `Exercise(name: "Bench Press", aliases: ["bench"])`. Leave it. Add a `history` parameter to `makeRig` (defaulted, so every existing call is untouched) and forward it to the model:

```swift
    private func makeRig(
        script: [[String]],
        capAtEarcon: Bool = false,
        knownBests: [String: Double] = [:],
        knownBestExercises: Set<String>? = nil,
        unit: MassUnit = .kilograms,
        history: @escaping () -> [Workout] = { [] },
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
            capReadbackAtEarcon: capAtEarcon, now: now,
            knownBestExercises: knownBestExercises ?? Set(knownBests.keys),
            history: history
        )
        return Rig(model: model, source: source, voice: voice, haptics: haptics)
    }
```

- [ ] **Step 2: Write the failing test**

```swift
@Test("previousWorkoutLine shows the last completed workout's top set and best estimate for the active exercise")
func previousWorkoutLineForActiveExercise() async throws {
    let priorBench = Workout(
        entries: [Entry(exercise: Self.bench, sets: [
            LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                      loadKilograms: 100, reps: 5, loggedAt: Date(timeIntervalSince1970: 10)),
        ])],
        startedAt: Date(timeIntervalSince1970: 10), endedAt: Date(timeIntervalSince1970: 70)
    )
    let rig = try makeRig(
        script: [["start workout"], ["bench 90 for 5"]],
        history: { [priorBench] }
    )
    await say(rig)   // start
    await say(rig)   // bench 90 for 5 — active exercise becomes Bench

    // e1RM(100,5) = 100 * 35 / 30 = 116.666… -> gymRound 116.7
    #expect(rig.model.previousWorkoutLine == "Last time: top 100 kg · best e1RM 116.7 kg")
}

@Test("previousWorkoutLine is nil for an exercise with no prior history")
func previousWorkoutLineNilForNewExercise() async throws {
    let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"]], history: { [] })
    await say(rig); await say(rig)
    #expect(rig.model.previousWorkoutLine == nil)
}

@Test("previousWorkoutLine ignores the workout currently in progress")
func previousWorkoutLineExcludesOpenWorkout() async throws {
    // history() returns the open workout too — the engine re-saves it on every
    // set — so the filter must drop the workout whose startedAt matches the open
    // one. This test builds its own store so history() reads real saved state.
    let container = try ModelContainer(
        for: WorkoutRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let store = SwiftDataWorkoutStore(context: ModelContext(container))
    let engine = WorkoutEngine(store: store, library: Self.library)
    let model = WorkoutSessionModel(
        engine: engine,
        transcriptSource: ScriptedTranscriptSource([
            ["start workout"], ["bench 100 for 5"], ["bench 105 for 5"],
        ]),
        readbackVoice: SpyReadbackVoice(), haptics: SpyHaptics(), library: Self.library,
        history: { store.history() }
    )
    for _ in 0..<3 { model.pressed(); await model.released() }

    #expect(model.previousWorkoutLine == nil)  // the only stored workout is the open one
}
```

- [ ] **Step 3: Run it — expect a failure**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSessionModelTests/previousWorkoutLineForActiveExercise`
Expected: FAIL — `value of type 'WorkoutSessionModel' has no member 'previousWorkoutLine'` (and an init-arg error until Step 1's `makeRig` change compiles against the new param).

- [ ] **Step 4: Implement**

In `WorkoutSessionModel.swift`:

Add the stored observable property near `activeExerciseName`:

```swift
    /// A one-line summary of the last completed workout for the active exercise —
    /// its heaviest working-set load and best estimated 1RM — or `nil` when the
    /// exercise has no prior history. Feeds the HUD "vs last time" row. Load and
    /// estimate only: `ExerciseSession` carries no rep count.
    public private(set) var previousWorkoutLine: String?
```

Add the injected handle to the `@ObservationIgnored private let` block:

```swift
    @ObservationIgnored private let history: () -> [Workout]
```

Add the parameter to `init` immediately after `staleRecovery` (the current last parameter), defaulted, and assign it in the body before the `syncFromEngine()` call:

```swift
        staleRecovery: StaleWorkoutRecovery? = nil,
        history: @escaping () -> [Workout] = { [] }
    ) {
        // ...existing assignments...
        self.staleRecovery = staleRecovery
        self.history = history
        syncFromEngine()
        seedAnnouncedFromCurrentWorkout()
    }
```

At the end of `updateActiveExercise(from:)` and at the end of `seedAnnouncedFromCurrentWorkout()`, add a call to `refreshPreviousWorkoutLine()` (both are the points where `activeExerciseName` settles). Add these two methods:

```swift
    /// Recompute `previousWorkoutLine` for the current active exercise.
    private func refreshPreviousWorkoutLine() {
        guard let name = activeExerciseName,
              let exercise = library.exercises.first(where: { $0.name == name }) else {
            previousWorkoutLine = nil
            return
        }
        previousWorkoutLine = Self.previousWorkoutLine(
            for: exercise, unit: unit, history: history(), excluding: workout?.startedAt
        )
    }

    /// The formatted "last time" summary for `exercise`, or `nil` when there is
    /// no prior completed workout with a loaded working set for it. The workout
    /// in progress (matched by `openStartedAt`) is filtered out — `history()`
    /// includes it because the engine re-saves it on every set.
    static func previousWorkoutLine(
        for exercise: Exercise, unit: MassUnit, history: [Workout], excluding openStartedAt: Date?
    ) -> String? {
        let prior = history.filter { $0.isEnded && $0.startedAt != openStartedAt }
        guard let last = exerciseProgress(for: exercise, across: prior).sessions.last else { return nil }
        var clauses: [String] = []
        if let top = last.topSetLoadKilograms { clauses.append("top \(loadString(top, unit: unit))") }
        if let e1rm = last.bestEstimatedOneRepMaxKilograms {
            clauses.append("best e1RM \(loadString(e1rm, unit: unit))")
        }
        guard !clauses.isEmpty else { return nil }
        return "Last time: " + clauses.joined(separator: " · ")
    }
```

- [ ] **Step 5: Run it — expect PASS**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSessionModelTests`
Expected: PASS (all cases, including the pre-existing suite).

- [ ] **Step 6: Commit**

```bash
git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift \
        Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift
git commit -m "$(cat <<'EOF'
WorkoutLoggerApp: inject history into WorkoutSessionModel; add previousWorkoutLine

The model now takes a history closure (defaulted) and derives a "last time"
summary for the active exercise, excluding the workout in progress.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
EOF
)"
```

---

## Task 10: `WorkoutSessionModel` — mid-workout edit wrappers

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift`

**Interfaces:**
- Consumes: `engine.editSet(at:_:with:)`, `engine.removeSet(at:_:)` (Tasks 2–3); `LoggedSet` (core); the existing `syncFromEngine()`, `updateActiveExercise(from:)`, `activeExerciseName`, `refreshPreviousWorkoutLine()` (Task 9).
- Produces:
  - `public func editActiveSet(_ setIndex: Int, to set: LoggedSet)` — resolves the active entry as `workout.entries.lastIndex { $0.exercise.name == activeExerciseName }`, calls `engine.editSet(at:setIndex:with:)`, then re-syncs.
  - `public func removeActiveSet(_ setIndex: Int)` — same resolution, calls `engine.removeSet(at:setIndex:)`, then re-syncs.
  - Both no-op when there is no active entry. The row index is a position in the active entry's set list (what the swipe-up sheet shows).

- [ ] **Step 1: Add a multi-exercise model helper to the suite**

The shared `makeRig` library has one exercise; the remove-path test needs two. Add this private helper to `struct WorkoutSessionModelTests` (Task 11 reuses it):

```swift
    private func makeMultiExerciseModel(
        script: [[String]],
        exercises: [Exercise],
        knownBestExercises: Set<String> = [],
        history: (() -> [Workout])? = nil
    ) throws -> (model: WorkoutSessionModel, store: SwiftDataWorkoutStore, haptics: SpyHaptics) {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let library = ExerciseLibrary(exercises)
        let engine = WorkoutEngine(store: store, library: library)
        let haptics = SpyHaptics()
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: ScriptedTranscriptSource(script),
            readbackVoice: SpyReadbackVoice(), haptics: haptics, library: library,
            knownBestExercises: knownBestExercises,
            // Default: history reads this helper's own store, so a scripted
            // "end workout" is visible to the celebration-gate re-derive.
            history: history ?? { store.history() }
        )
        return (model, store, haptics)
    }
```

- [ ] **Step 2: Write the failing tests**

```swift
@Test("editActiveSet routes a corrected set through the engine and updates the projection")
func editActiveSetUpdatesLiveWorkout() async throws {
    let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"]])
    await say(rig); await say(rig)

    rig.model.editActiveSet(0, to: LoggedSet(
        loadType: .external, effort: .reps, role: .working, grouping: .straight,
        loadKilograms: 105, reps: 5, loggedAt: Date(timeIntervalSince1970: 0)
    ))

    #expect(rig.model.workout?.entries[0].sets[0].loadKilograms == 105)
}

@Test("removeActiveSet deletes the row and, when it empties the entry, moves the active exercise")
func removeActiveSetEmptiesEntry() async throws {
    let bench = Exercise(name: "Bench Press", aliases: ["bench"])
    let squat = Exercise(name: "Back Squat", aliases: ["squat"])
    let (model, _, _) = try makeMultiExerciseModel(
        script: [["start workout"], ["bench 100 for 5"], ["squat 140 for 5"], ["bench"]],
        exercises: [bench, squat]
    )
    for _ in 0..<4 { model.pressed(); await model.released() }
    // Active exercise is Bench again, its entry has exactly one set.

    model.removeActiveSet(0)

    #expect(model.workout?.entries.map { $0.exercise.name } == ["Back Squat"])
    #expect(model.activeExerciseName == "Back Squat")
}

@Test("the edit wrappers are a no-op when no workout is open")
func editWrappersNoOpWithoutWorkout() throws {
    let rig = try makeRig(script: [])
    rig.model.editActiveSet(0, to: LoggedSet(
        loadType: .external, effort: .reps, role: .working, grouping: .straight,
        loadKilograms: 1, reps: 1, loggedAt: Date(timeIntervalSince1970: 0)
    ))
    rig.model.removeActiveSet(0)
    #expect(rig.model.workout == nil)
}
```

- [ ] **Step 3: Run it — expect a compile failure**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSessionModelTests/editActiveSetUpdatesLiveWorkout`
Expected: FAIL — `value of type 'WorkoutSessionModel' has no member 'editActiveSet'`.

- [ ] **Step 4: Implement**

In `WorkoutSessionModel.swift`, add a `MARK: - Mid-workout editing` section:

```swift
    // MARK: - Mid-workout editing

    /// Correct the set at `setIndex` of the active entry — the swipe-up list's
    /// row index. Routed through the engine so the live rest target, retry
    /// window, and personal-record bar stay consistent (spec story 38). A no-op
    /// when no entry is active.
    public func editActiveSet(_ setIndex: Int, to set: LoggedSet) {
        guard let entryIndex = activeEntryIndex() else { return }
        engine.editSet(at: entryIndex, setIndex, with: set)
        afterEngineEdit()
    }

    /// Delete the set at `setIndex` of the active entry (spec story 42). A no-op
    /// when no entry is active.
    public func removeActiveSet(_ setIndex: Int) {
        guard let entryIndex = activeEntryIndex() else { return }
        engine.removeSet(at: entryIndex, setIndex)
        afterEngineEdit()
    }

    /// The index of the active entry in `workout.entries` — the last entry whose
    /// exercise name matches `activeExerciseName` (two entries can share a name;
    /// this matches how `HUDProjection` resolves the active entry).
    private func activeEntryIndex() -> Int? {
        guard let name = activeExerciseName else { return nil }
        return workout?.entries.lastIndex { $0.exercise.name == name }
    }

    private func afterEngineEdit() {
        syncFromEngine()
        updateActiveExercise(from: [])   // re-validate activeExerciseName against the smaller workout
        refreshPreviousWorkoutLine()
    }
```

- [ ] **Step 5: Run it — expect PASS**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSessionModelTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift \
        Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift
git commit -m "$(cat <<'EOF'
WorkoutLoggerApp: add editActiveSet/removeActiveSet wrappers on WorkoutSessionModel

Resolve the active entry from activeExerciseName and drive the engine's
mid-workout edit seam, then re-sync. The swipe-up list passes a row index only.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
EOF
)"
```

---

## Task 11: `WorkoutSessionModel` — readback fix + personal-record gate re-derivation

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift`

**Interfaces:**
- Consumes: the existing `activeExerciseName`, `history()` (Task 9), `apply(_:)`, `isGenuinePersonalRecord(_:before:)`.
- Produces:
  - `exerciseName(for:in:)` returns `activeExerciseName` instead of `workout?.entries.last?.exercise.name` when no announcement is in the results.
  - `knownBestExercises` changes from `let` to `var`.
  - `apply(_:)` re-derives `knownBestExercises` from `history()` when the just-heard utterance ends the workout (`workoutBefore?.isEnded == false && workout?.isEnded == true`).
  - `static func exercisesWithLoadedWorkingSet(in history: [Workout]) -> Set<String>` — names of exercises that have at least one working set carrying both a load and a rep count.

> **On the `exerciseName(for:in:)` fix.** `exerciseName` is consumed only by
> `readbackPlan`'s `.full` branch (`"Logged. <name>, ..."`) and by
> `consumeIsNewExercise`. A bare-set utterance is always read back `.terse` (the
> exercise is already announced), and the `.terse` and `.announcement` paths never
> speak `<name>` — so on today's code the `entries.last` vs `activeExerciseName`
> difference is not observable in `lastReadback`. The change is a spec-alignment
> correctness fix (spec story 67): the model has `activeExerciseName` *because*
> `entries.last` is the wrong exercise after the lifter returns to an earlier one,
> and any future readback style that speaks the name on a bare set would inherit
> the bug. It is verified by the type change plus the characterization test below
> (which pins that the bare-set readback stays stable) and the green suite.

- [ ] **Step 1: Write the failing tests** (uses `makeMultiExerciseModel` from Task 10)

```swift
@Test("a bare set after returning to an earlier exercise still reads back terse")
func bareSetReadbackAfterReturnIsStable() async throws {
    let bench = Exercise(name: "Bench Press", aliases: ["bench"])
    let squat = Exercise(name: "Back Squat", aliases: ["squat"])
    let (model, _, _) = try makeMultiExerciseModel(
        script: [
            ["start workout"], ["bench 100 for 5"], ["squat 140 for 3"], ["bench"], ["100 for 5"],
        ],
        exercises: [bench, squat]
    )
    for _ in 0..<5 { model.pressed(); await model.released() }

    // Characterization: the last utterance is a bare set on the re-announced Bench
    // entry. It must land on Bench (activeExerciseName), and the readback is terse.
    #expect(model.activeExerciseName == "Bench Press")
    #expect(model.workout?.entries.map { $0.exercise.name } == ["Bench Press", "Back Squat"])
    #expect(model.workout?.entries[0].sets.count == 2)   // the bare set went to Bench, not Squat
    #expect(model.lastReadback == .speak("100 for 5"))
}

@Test("a second same-session workout celebrates a set that beats the ended workout's best")
func secondWorkoutCelebratesAgainstEndedWorkout() async throws {
    let bench = Exercise(name: "Bench Press", aliases: ["bench"])
    let (model, _, haptics) = try makeMultiExerciseModel(
        script: [
            ["start workout"], ["bench 100 for 5"], ["end workout"],
            ["start workout"], ["bench 120 for 5"],
        ],
        exercises: [bench],
        knownBestExercises: []                 // nothing seeded at launch
    )

    for _ in 0..<5 { model.pressed(); await model.released() }

    // First workout's 100×5 is e1RM 116.7 — logged, not celebrated (first ever).
    // "end workout" re-derives the gate from history (wired to the helper's store
    // by default), so "Bench Press" now counts as an exercise with a beatable
    // record. The second workout's 120×5 (e1RM 140) beats it, so the
    // personal-record haptic fires.
    #expect(haptics.played.contains(.personalRecord))
}
```

- [ ] **Step 2: Run them**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter "WorkoutSessionModelTests/secondWorkoutCelebratesAgainstEndedWorkout|WorkoutSessionModelTests/bareSetReadbackAfterReturnIsStable"`
Expected: `secondWorkoutCelebratesAgainstEndedWorkout` FAILS — the PR haptic is not fired (the gate never learned "Bench Press"). `bareSetReadbackAfterReturnIsStable` PASSES already — it is a characterization test pinning behavior the `exerciseName` change must not disturb.

- [ ] **Step 3: Implement**

In `WorkoutSessionModel.swift`:

Change the declaration:

```swift
    @ObservationIgnored private var knownBestExercises: Set<String>
```

In `exerciseName(for:in:)`, replace the final line:

```swift
    private func exerciseName(for salient: ParseResult, in results: [ParseResult]) -> String? {
        for case .announcement(let exercise) in results { return exercise.name }
        if isAnnouncement(salient), case .announcement(let exercise) = salient { return exercise.name }
        return activeExerciseName
    }
```

In `apply(_:)`, after `syncFromEngine()` / `updateActiveExercise(from: results)` and before the haptic block, add:

```swift
        if workoutBefore?.isEnded == false, workout?.isEnded == true {
            knownBestExercises = Self.exercisesWithLoadedWorkingSet(in: history())
        }
```

Add the helper near `isGenuinePersonalRecord`:

```swift
    /// Exercise names that have at least one completed working set with both a
    /// load and a rep count anywhere in `history` — the exercises for which a
    /// personal record can be beaten. Used to refresh the celebration gate when a
    /// workout ends, so a second workout in the same app session judges records
    /// against up-to-date history (spec story 68).
    static func exercisesWithLoadedWorkingSet(in history: [Workout]) -> Set<String> {
        var names: Set<String> = []
        for workout in history {
            for entry in workout.entries {
                for set in entry.sets where set.role == .working {
                    if set.loadKilograms != nil, set.reps != nil { names.insert(entry.exercise.name) }
                }
            }
        }
        return names
    }
```

- [ ] **Step 4: Run it — expect PASS**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSessionModelTests`
Expected: PASS — both new tests and the full pre-existing suite (the `exerciseName` change must not move any existing readback expectation).

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift \
        Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift
git commit -m "$(cat <<'EOF'
WorkoutLoggerApp: fix readback exercise name; re-derive PR gate on workout end

Readback now names the active exercise (not the last entry). knownBestExercises
becomes a var and re-derives from history when a workout ends, so a second
same-session workout celebrates records correctly.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
EOF
)"
```

---

## Task 12: `HUDProjection` — rest target row + "vs last time" row

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/HUD/HUDProjection.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/HUDProjectionTests.swift`

**Interfaces:**
- Consumes: `model.restTargetSeconds` (pre-existing), `model.previousWorkoutLine` (Task 9), the existing `HUDProjection.clock(_:)`.
- Produces:
  - `restLine` while resting is now `"\(clock(elapsed)) / \(clock(model.restTargetSeconds))"` (e.g. `"1:05 / 2:00"`); still `nil` when no rest is running.
  - New stored `public var vsLastTimeLine: String?`, added to the memberwise `init` (last parameter, default `nil`) and set in `init(from:)` to `model.previousWorkoutLine`.

- [ ] **Step 1: Update the existing `restLine` test and add the new cases**

In `HUDProjectionTests.swift`, in `func restLine()` replace the one line

```swift
        #expect(p.restLine == "1:05")
```

with

```swift
        #expect(p.restLine == "1:05 / 2:00")       // elapsed / default 120s target
```

(`freshModel`'s `#expect(p.restLine == nil)` still holds — no rest running.)

Add:

```swift
@Test("vsLastTimeLine passes through the model's previous-workout summary")
func vsLastTimeLinePassThrough() async throws {
    let priorBench = Workout(
        entries: [Entry(exercise: Self.bench, sets: [
            LoggedSet(loadType: .external, effort: .reps, role: .working, grouping: .straight,
                      loadKilograms: 100, reps: 5, loggedAt: Date(timeIntervalSince1970: 10)),
        ])],
        startedAt: Date(timeIntervalSince1970: 10), endedAt: Date(timeIntervalSince1970: 70)
    )
    let container = try ModelContainer(
        for: WorkoutRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let store = SwiftDataWorkoutStore(context: ModelContext(container))
    let engine = WorkoutEngine(store: store, library: Self.library)
    let model = WorkoutSessionModel(
        engine: engine, transcriptSource: ScriptedTranscriptSource([["start workout"], ["bench 90 for 5"]]),
        readbackVoice: SpyReadbackVoice(), haptics: SpyHaptics(), library: Self.library,
        history: { [priorBench] }
    )
    model.pressed(); await model.released()
    model.pressed(); await model.released()

    #expect(HUDProjection(from: model).vsLastTimeLine == "Last time: top 100 kg · best e1RM 116.7 kg")
}

@Test("a fresh model has no vsLastTimeLine")
func freshModelNoVsLastTime() throws {
    #expect(HUDProjection(from: try makeRig(script: []).model).vsLastTimeLine == nil)
}
```

`HUDProjectionTests.makeRig` does not need to change — it constructs `WorkoutSessionModel` without a `history:` argument, and after Task 9 that parameter is defaulted. `vsLastTimeLinePassThrough` builds its own model with a `history:` closure; `freshModelNoVsLastTime` needs no history.

- [ ] **Step 2: Run it — expect a failure**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter HUDProjectionTests`
Expected: FAIL — `restLine` mismatch (`"1:05"` vs `"1:05 / 2:00"`) and `value of type 'HUDProjection' has no member 'vsLastTimeLine'`.

- [ ] **Step 3: Implement**

In `HUDProjection.swift`:

Add the field and extend the memberwise init:

```swift
    public var currentEntrySetLines: [String]
    public var tapSelectCandidates: [Exercise]?
    public var vsLastTimeLine: String?

    public init(
        exerciseName: String,
        lastSetLine: String?,
        restLine: String?,
        restTargetReached: Bool,
        isListening: Bool,
        currentEntrySetLines: [String],
        tapSelectCandidates: [Exercise]?,
        vsLastTimeLine: String? = nil
    ) {
        // ... existing assignments ...
        self.vsLastTimeLine = vsLastTimeLine
    }
```

In `init(from:)`, change `restLine` and set `vsLastTimeLine`:

```swift
        restLine = model.restStartedAt == nil
            ? nil
            : "\(HUDProjection.clock(model.restElapsed)) / \(HUDProjection.clock(model.restTargetSeconds))"
        // ...
        vsLastTimeLine = model.previousWorkoutLine
```

- [ ] **Step 4: Run it — expect PASS**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter HUDProjectionTests`
Expected: PASS.

- [ ] **Step 5: Full app suite + commit**

Run: `cd Packages/WorkoutLoggerApp && swift test`
Expected: all PASS.

```bash
git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/HUD/HUDProjection.swift \
        Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/HUDProjectionTests.swift
git commit -m "$(cat <<'EOF'
WorkoutLoggerApp: HUD rest row shows elapsed/target; add vsLastTimeLine

restLine now renders "m:ss / m:ss" against the rest target, and the projection
carries the session model's previous-workout summary for the "vs last time" row.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
EOF
)"
```

---

## Task 13: `App/` — read-only history, detail, and progress screens

**Files:**
- Create: `App/Views/HistoryListView.swift`
- Create: `App/Views/WorkoutDetailView.swift`
- Create: `App/Views/ExerciseProgressView.swift`

**Interfaces:**
- Consumes (from `WorkoutLoggerApp`, all verified in earlier tasks): `WorkoutHistoryModel` (`rows: [Workout]`, `selected: Workout?`, `saveError: String?`, `isUnavailable: Bool`, `open(_:)`, `applyEdit(_:)`), `WorkoutSummaryProjection(workout:priorHistory:unit:)`, `ExerciseProgressModel(exercise:store:unit:historyUnavailable:)`, `ExerciseProgressProjection`, `WorkoutHistoryStore`.
- Consumes (from `WorkoutLoggerCore`): `Workout`, `Exercise`.
- Produces: three `View` structs. `SetEditView` (referenced by `WorkoutDetailView`) and all navigation wiring land in Task 14. **No package changes.** This task cannot be built here — verification is a signature cross-check (Step 2).

> **Tasks 13 and 14 together deliver the `App/` layer.** Neither is compiled in
> this environment, and they reference each other (Task 13's `WorkoutDetailView`
> uses Task 14's `SetEditView`; Task 14's `HUDView`/`RootView` edits assume Task
> 13's `NavigationStack`). Both are structurally verified at the end of Task 14.
> Commit each task's files at its own end.
>
> **`exerciseProgress(for:across:)` matches by whole-value `Exercise` equality**
> (name *and* aliases). Always hand it the real `Exercise` value pulled from a
> stored `Workout` — never `Exercise(name: someString)`, which has empty aliases
> and will silently match nothing. (`Workout.movingSet` is the exception: it
> matches its target entry by name, so a name-only `Exercise` is fine there.)

- [ ] **Step 1: Write the three views**

`App/Views/HistoryListView.swift`:

```swift
import SwiftUI
import WorkoutLoggerCore
import WorkoutLoggerApp

/// Reverse-chronological list of completed workouts. A dumb renderer over
/// `WorkoutHistoryModel`.
struct HistoryListView: View {
    let historyModel: WorkoutHistoryModel
    let unit: MassUnit
    let store: WorkoutHistoryStore
    let historyUnavailable: Bool

    var body: some View {
        Group {
            if historyModel.isUnavailable {
                ContentUnavailableView("History unavailable",
                                       systemImage: "externaldrive.badge.xmark",
                                       description: Text("Storage could not be opened."))
            } else if historyModel.rows.isEmpty {
                ContentUnavailableView("No workouts yet", systemImage: "list.bullet.rectangle")
            } else {
                List(historyModel.rows, id: \.startedAt) { workout in
                    NavigationLink {
                        WorkoutDetailView(
                            historyModel: historyModel, workout: workout,
                            unit: unit, store: store, historyUnavailable: historyUnavailable
                        )
                        .onAppear { historyModel.open(workout) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                            Text(workout.entries.map(\.exercise.name).joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}
```

`App/Views/WorkoutDetailView.swift`:

```swift
import SwiftUI
import WorkoutLoggerCore
import WorkoutLoggerApp

/// One completed workout: entries, formatted set lines with PR badges, totals,
/// and the note. Row tap opens the set editor; exercise-name tap opens progress.
struct WorkoutDetailView: View {
    let historyModel: WorkoutHistoryModel
    let workout: Workout
    let unit: MassUnit
    let store: WorkoutHistoryStore
    let historyUnavailable: Bool

    private var summary: WorkoutSummaryProjection {
        let prior = historyModel.rows.filter { $0.startedAt < workout.startedAt }
        return WorkoutSummaryProjection(workout: workout, priorHistory: prior, unit: unit)
    }

    /// The live workout value edits run against (falls back to the passed-in one
    /// before the first `open`).
    private var current: Workout { historyModel.selected ?? workout }

    var body: some View {
        List {
            if let error = historyModel.saveError {
                Text("Couldn’t save: \(error)").foregroundStyle(.red)
            }
            ForEach(Array(summary.entries.enumerated()), id: \.offset) { entryIndex, entry in
                Section {
                    ForEach(Array(entry.sets.enumerated()), id: \.offset) { setIndex, row in
                        NavigationLink {
                            SetEditView(
                                set: current.entries[entryIndex].sets[setIndex],
                                exerciseNames: current.entries.map(\.exercise.name),
                                unit: unit
                            ) { edited in
                                // One atomic transform → one save.
                                historyModel.applyEdit { w in
                                    var next = w.replacingSet(at: entryIndex, setIndex, with: edited.set)
                                    if let target = edited.moveToExerciseName, target != entry.exerciseName {
                                        next = next.movingSet(at: entryIndex, setIndex,
                                                              toExercise: Exercise(name: target))
                                    }
                                    return next
                                }
                            } onDelete: {
                                historyModel.applyEdit { $0.removingSet(at: entryIndex, setIndex) }
                            }
                        } label: {
                            HStack {
                                Text(row.line).font(.body.monospacedDigit())
                                if row.isPersonalRecord {
                                    Spacer(); Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                                }
                            }
                        }
                    }
                } header: {
                    NavigationLink(entry.exerciseName) {
                        ExerciseProgressView(
                            exercise: current.entries[entryIndex].exercise,   // real value, aliases intact
                            unit: unit, store: store, historyUnavailable: historyUnavailable
                        )
                    }
                }
            }
            Section("Totals") {
                Text("Volume: \(summary.totalVolumeText)")
                Text("Working reps: \(summary.totalWorkingReps)")
                Text("Duration: \(summary.durationText)")
                if let note = summary.note { Text(note).italic() }
            }
        }
        .navigationTitle(workout.startedAt.formatted(date: .abbreviated, time: .omitted))
    }
}
```

`App/Views/ExerciseProgressView.swift`:

```swift
import SwiftUI
import Charts
import WorkoutLoggerCore
import WorkoutLoggerApp

/// Load, volume, and estimated-1RM trend for one exercise, plus a "vs last time"
/// row. Charts render fixed series over all available history.
struct ExerciseProgressView: View {
    let exercise: Exercise
    let unit: MassUnit
    let store: WorkoutHistoryStore
    let historyUnavailable: Bool

    private var projection: ExerciseProgressProjection {
        ExerciseProgressModel(exercise: exercise, store: store, unit: unit,
                              historyUnavailable: historyUnavailable).projection
    }

    var body: some View {
        let p = projection
        return Group {
            if p.volumeSeries.isEmpty {
                ContentUnavailableView("No history yet",
                                       systemImage: "chart.xyaxis.line",
                                       description: Text("Log \(exercise.name) to see progress."))
            } else {
                List {
                    if let top = p.topSetText { Text("Top set last time: \(top)") }
                    if let c = p.comparison {
                        Section("Vs last time") {
                            if let d = c.topSetLoadDelta { Text("Top set: \(signed(d))") }
                            Text("Volume: \(signed(c.volumeDelta))")
                            if let d = c.estimatedOneRepMaxDelta { Text("Est. 1RM: \(signed(d))") }
                        }
                    }
                    chartSection("Load", p.loadSeries)
                    chartSection("Volume", p.volumeSeries)
                    chartSection("Estimated 1RM", p.estimatedOneRepMaxSeries)
                }
            }
        }
        .navigationTitle(exercise.name)
    }

    private func chartSection(_ title: String, _ points: [ExerciseProgressProjection.Point]) -> some View {
        Section(title) {
            Chart(points, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value(title, point.value))
                PointMark(x: .value("Date", point.date), y: .value(title, point.value))
            }
            .frame(height: 160)
        }
    }

    private func signed(_ value: Double) -> String {
        (value >= 0 ? "+" : "") + numberFormatted(value)
    }
    private func numberFormatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
```

- [ ] **Step 2: Verify — signature cross-check (no build here)**

Run: `cd Packages/WorkoutLoggerApp && swift build` and `cd Packages/WorkoutLoggerCore && swift build`
Expected: both succeed (the package APIs the views call are what Tasks 1–12 produced).

Then confirm each symbol the new views reference exists, with:

```bash
grep -R "struct WorkoutSummaryProjection\|struct ExerciseProgressProjection\|final class WorkoutHistoryModel\|final class ExerciseProgressModel\|protocol WorkoutHistoryStore" Packages/WorkoutLoggerApp/Sources
grep -n "public init(workout: Workout, priorHistory:" Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/History/WorkoutSummaryProjection.swift
grep -n "public init(exercise: Exercise, store: WorkoutHistoryStore" Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Progress/ExerciseProgressModel.swift
```

Expected: every grep matches. Note in the task report that `App/` is not compiled in this environment; the check is structural. `SetEditView` is undefined until Task 14 — that is expected and does not fail this step.

- [ ] **Step 3: Commit**

```bash
git add App/Views/HistoryListView.swift App/Views/WorkoutDetailView.swift \
        App/Views/ExerciseProgressView.swift
git commit -m "$(cat <<'EOF'
App: add history list, workout detail, and exercise progress screens

Read-only screens over WorkoutHistoryModel / WorkoutSummaryProjection /
ExerciseProgressModel. Navigation wiring and SetEditView follow in the next
commit. Files-only; the App target is not built in this environment.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
EOF
)"
```

---

## Task 14: `App/` — set editor, editable swipe-up list, HUD rows, composition root

**Files:**
- Create: `App/Views/SetEditView.swift`
- Modify: `App/Views/SetListSheet.swift`
- Modify: `App/Views/HUDView.swift`
- Modify: `App/Views/RootView.swift`
- Modify: `App/TrackitApp.swift`

**Interfaces:**
- Consumes: `WorkoutSessionModel` (`editActiveSet(_:to:)`, `removeActiveSet(_:)`, `displayUnit`), `HUDProjection` (`restLine`, `vsLastTimeLine`, `currentEntrySetLines`), `WorkoutHistoryModel`, `WorkoutHistoryStore`, `SwiftDataWorkoutStore`, `LoggedSet`, `LoadType`, `EffortMeasure`, `SetRole`, `Grouping`, `Exercise`.
- Produces: a `SetEditView` returning an edited `LoggedSet` plus an optional move-target name; an editable `SetListSheet`; two new HUD rows; a `TrackitApp` that builds a `WorkoutHistoryModel` and passes `history: { store.history() }` into `WorkoutSessionModel`. **Files-only; not built here.**

- [ ] **Step 1: Write `SetEditView`**

`App/Views/SetEditView.swift`:

```swift
import SwiftUI
import WorkoutLoggerCore

/// Edit one recorded set: load, reps, role, grouping (clear-to-straight or mark
/// dropset only — see spec Out of Scope), note, and an optional move to another
/// exercise. Builds a `LoggedSet` and hands it back; deletion is a separate
/// callback.
struct SetEditView: View {
    struct Result { var set: LoggedSet; var moveToExerciseName: String? }

    let set: LoggedSet
    let exerciseNames: [String]
    let unit: MassUnit
    let onSave: (Result) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loadText: String
    @State private var reps: Int
    @State private var role: SetRole
    @State private var isDropset: Bool
    @State private var note: String
    @State private var moveTarget: String

    init(set: LoggedSet, exerciseNames: [String], unit: MassUnit,
         onSave: @escaping (Result) -> Void, onDelete: @escaping () -> Void) {
        self.set = set
        self.exerciseNames = exerciseNames
        self.unit = unit
        self.onSave = onSave
        self.onDelete = onDelete
        let shownLoad = set.loadKilograms.map { unit == .pounds ? $0 / 0.45359237 : $0 }
        _loadText = State(initialValue: shownLoad.map { String(($0 * 10).rounded() / 10) } ?? "")
        _reps = State(initialValue: set.reps ?? 0)
        _role = State(initialValue: set.role)
        _isDropset = State(initialValue: set.grouping == .dropset)
        _note = State(initialValue: set.note ?? "")
        _moveTarget = State(initialValue: "")
    }

    var body: some View {
        Form {
            Section("Load (\(unit == .pounds ? "lb" : "kg"))") {
                TextField("Load", text: $loadText).keyboardType(.decimalPad)
            }
            Section("Reps") {
                Stepper("\(reps)", value: $reps, in: 0...99)
            }
            Section("Role") {
                Picker("Role", selection: $role) {
                    Text("Working").tag(SetRole.working)
                    Text("Warm-up").tag(SetRole.warmup)
                }.pickerStyle(.segmented)
            }
            Section("Grouping") {
                Toggle("Dropset", isOn: $isDropset)
                if set.grouping == .superset {
                    Text("Part of a superset — saving clears that.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Note") {
                TextField("Note", text: $note, axis: .vertical)
            }
            Section("Move to exercise") {
                Picker("Exercise", selection: $moveTarget) {
                    Text("Keep here").tag("")
                    ForEach(exerciseNames, id: \.self) { Text($0).tag($0) }
                }
            }
            Section {
                Button("Delete set", role: .destructive) { onDelete(); dismiss() }
            }
        }
        .navigationTitle("Edit set")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save(); dismiss() }
            }
        }
    }

    private func save() {
        let enteredKg: Double? = Double(loadText).map { unit == .pounds ? $0 * 0.45359237 : $0 }
        var edited = set
        edited.loadKilograms = enteredKg
        edited.reps = edited.effort == .reps ? reps : edited.reps
        edited.role = role
        edited.grouping = isDropset ? .dropset : .straight
        edited.supersetRunID = isDropset ? edited.supersetRunID : nil
        edited.note = note.isEmpty ? nil : note
        onSave(Result(set: edited, moveToExerciseName: moveTarget.isEmpty ? nil : moveTarget))
    }
}
```

- [ ] **Step 2: Make `SetListSheet` editable**

`App/Views/SetListSheet.swift`:

```swift
import SwiftUI

/// Swipe-up list of every set for the current entry. Tap a row to edit it,
/// swipe to delete. Row order matches the active entry's set order 1:1.
struct SetListSheet: View {
    let lines: [String]
    let onEdit: (Int) -> Void
    let onDelete: (Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Button { onEdit(index) } label: {
                        Text(line).font(.body.monospacedDigit())
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { onDelete(index) }
                    }
                }
            }
            .navigationTitle("This exercise")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Step 3: Wire the HUD rows and the editable sheet**

`App/Views/HUDView.swift` — the file already resolves the active entry only as strings via `HUDProjection`. Add a `LoggedSet`-level resolver and the edit state.

Add stored/computed members to `struct HUDView`:

```swift
    @State private var editingRow: EditRow?

    /// Identifiable wrapper so `.sheet(item:)` can carry the tapped row index.
    private struct EditRow: Identifiable { let id: Int }

    /// The active entry as a value (mirrors `HUDProjection.init(from:)`'s
    /// resolution), so the editor can be seeded with the real `LoggedSet`.
    private var activeEntry: Entry? {
        let entries = model.workout?.entries
        return model.activeExerciseName
            .flatMap { name in entries?.last { $0.exercise.name == name } }
            ?? entries?.last
    }
```

In `body`, after `restCard`, add the "vs last time" row:

```swift
            if let vs = hud.vsLastTimeLine {
                Text(vs)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
```

Replace the `.setList` case of the `.sheet(item: activeSheet)` switch:

```swift
            case .setList:
                SetListSheet(
                    lines: hud.currentEntrySetLines,
                    onEdit: { index in editingRow = EditRow(id: index) },
                    onDelete: { index in model.removeActiveSet(index) }
                )
```

And add a second sheet modifier next to the existing `.sheet(item: activeSheet)`:

```swift
        .sheet(item: $editingRow) { row in
            if let set = activeEntry?.sets[safe: row.id] {
                NavigationStack {
                    SetEditView(
                        set: set,
                        exerciseNames: [],                 // no cross-exercise move mid-workout (out of scope)
                        unit: model.displayUnit,
                        onSave: { model.editActiveSet(row.id, to: $0.set) },
                        onDelete: { model.removeActiveSet(row.id) }
                    )
                }
            }
        }
```

Add a bounds-safe subscript helper at file scope in `HUDView.swift` (or a shared `App/` extensions file if one exists):

```swift
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

`restCard` is unchanged — `hud.restLine` now already carries `"m:ss / m:ss"`.

- [ ] **Step 4: Wrap the HUD in a `NavigationStack` with a history entry point**

`App/Views/RootView.swift` — add two stored properties and wrap the `HUDView` branch:

```swift
struct RootView: View {
    let model: WorkoutSessionModel
    let historyModel: WorkoutHistoryModel
    let store: any WorkoutHistoryStore
    let historyUnavailable: Bool
    // ...unchanged: scenePhase, tick...
```

In `body`, replace the `else { HUDView(...) }` branch:

```swift
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
                        }
                }
            }
```

Add `import WorkoutLoggerCore` to `RootView.swift` if not already present (it needs `WorkoutHistoryStore`'s module — `WorkoutLoggerApp` re-exports it, so `import WorkoutLoggerApp` alone suffices; add `WorkoutLoggerCore` only if the build complains).

- [ ] **Step 5: Build the history model in the composition root**

`App/TrackitApp.swift`:

Add stored properties:

```swift
    @State private var model: WorkoutSessionModel
    private let historyModel: WorkoutHistoryModel
    private let store: SwiftDataWorkoutStore
    private let historyUnavailable: Bool
```

In `init()`, `store` is already a local (`let store = SwiftDataWorkoutStore(...)`). After the `switch launchDecision(...)` block, before `_model = State(...)`:

```swift
        self.store = store
        self.historyModel = WorkoutHistoryModel(
            store: store, historyUnavailable: availability.isDegraded
        )
```

Add `history:` as the last argument of the `WorkoutSessionModel(...)` initializer:

```swift
        _model = State(initialValue: WorkoutSessionModel(
            engine: engine,
            transcriptSource: SystemSpeechRecognizer(),
            readbackVoice: SystemReadbackVoice(),
            haptics: SystemHaptics(),
            library: library,
            knownBestExercises: Set(knownBests.keys),
            staleRecovery: staleRecovery,
            history: { store.history() }
        ))
```

Update `body`:

```swift
    var body: some Scene {
        WindowGroup {
            RootView(model: model, historyModel: historyModel, store: store,
                     historyUnavailable: historyUnavailable)
        }
    }
```

- [ ] **Step 6: Verify — signature cross-check (no build here)**

Run: `cd Packages/WorkoutLoggerApp && swift test` and `cd Packages/WorkoutLoggerCore && swift test`
Expected: both suites fully green (no package file changed in Tasks 13–14, so this is a regression guard).

Cross-check the `App/` call sites:

```bash
grep -n "editActiveSet\|removeActiveSet" Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift
grep -n "vsLastTimeLine" Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/HUD/HUDProjection.swift
grep -n "history:" Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift
```

Expected: all match. Record in the report that `App/` is consistency-checked only.

- [ ] **Step 7: Commit**

```bash
git add App/Views/SetEditView.swift App/Views/SetListSheet.swift App/Views/HUDView.swift \
        App/Views/RootView.swift App/TrackitApp.swift
git commit -m "$(cat <<'EOF'
App: add set editor, make swipe-up list editable, wire history into the model

SetEditView builds an edited LoggedSet (load/reps/role/grouping/note/move);
SetListSheet gains tap-to-edit and swipe-to-delete; HUD shows the vs-last-time
row; TrackitApp builds WorkoutHistoryModel and passes history into the session
model. Files-only; the App target is not built in this environment.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo
EOF
)"
```

---

## Final verification

- [ ] `cd Packages/WorkoutLoggerCore && swift test` — all suites green.
- [ ] `cd Packages/WorkoutLoggerApp && swift test` — all suites green.
- [ ] `cd Packages/WorkoutLoggerCore && swift build 2>&1 | grep -i warning` — no output.
- [ ] `cd Packages/WorkoutLoggerApp && swift build 2>&1 | grep -i warning` — no output.
- [ ] `git log --oneline` shows one commit per task (14) on the feature branch, the spec commit as the first.
- [ ] Spec self-check: every one of the spec's 68 user stories maps to a task below (see coverage note).

### Story coverage

| Spec stories | Task(s) |
|---|---|
| 1–10 (history list) | 7 (model), 13 (view) |
| 11–22 (detail screen) | 5 (projection: rows, lines, badges, totals, note), 13 (view) |
| 23–36 (editing a completed workout) | 1 (`movingSet`), 5 (badge/total recompute on re-view), 7 (`applyEdit`), 14 (`SetEditView`) |
| 37 (sane input controls) | 14 (`SetEditView` steppers/pickers) |
| 38–39 (save feedback / failure safety) | 7 (`saveError`, discard-on-failure), 13 (banner) |
| 40–47 (mid-workout inline editing) | 2 (`editSet`), 3 (`removeSet`), 10 (wrappers), 14 (editable sheet) |
| 48–59 (progress screen) | 6 (projection), 8 (model), 13 (charts view) |
| 60–64 ("vs last time" HUD) | 9 (`previousWorkoutLine`), 12 (`vsLastTimeLine`), 14 (HUD row) |
| 65–66 (rest target row) | 12 (`restLine` format), 14 (HUD row) |
| 67 (readback names active exercise) | 11 |
| 68 (PR gate re-derives on end) | 11 |

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-09-01-postworkout-progress.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration. **REQUIRED SUB-SKILL:** `superpowers:subagent-driven-development`. The SDD setup creates the feature worktree/branch and commits this spec + plan as the first commit.

**2. Inline Execution** — execute tasks in this session with `superpowers:executing-plans`, batching with checkpoints.

**Which approach?**
