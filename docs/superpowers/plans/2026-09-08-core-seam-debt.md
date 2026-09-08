# Cluster 1 — Core Seam Debt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reopen `WorkoutLoggerCore` once, land the six carried seam-debt changes (1a–1f) named across three v1 code reviews, and re-freeze it.

**Architecture:** Additive changes to the pure domain package plus one thread-through of an existing signal. Three items (1a re-seed, 1b `previousSet`, 1d `Exercise: Hashable`) already exist as uncommitted WIP carried onto this branch — Task 1 lands and reviews that as-is. The rest are new: value-key the three per-exercise maps (1d), thread resolver confidence into `ParseResult` and back into `readbackStyle` (1c), record template identity on `Workout` (1f), split the rest-timer and PR-tracker sub-machines out of `WorkoutEngine` behind unchanged public surface (1e), and sweep the small findings (1f). One App-target edit wires the re-seed provider (1a).

**Tech Stack:** Swift 6 / Swift 6.2 Approachable Concurrency, Swift Testing (`import Testing`, `@Suite`/`@Test`/`#expect`), SwiftPM. `swift test` in `Packages/WorkoutLoggerCore` and `Packages/WorkoutLoggerApp`. The `App/` Xcode target does not build in this environment — its one edit (Task 2) is files-only and consistency-checked, as in subsystems C–F.

**Spec:** `docs/superpowers/specs/2026-09-06-v1.1-deferred-work-design.md` — Cluster 1 section. This plan argues from that spec; executors read both.

**Branch:** `v1.1-core-seam-debt`, cut from `origin/main` (`da52901`). Carries pre-applied WIP in three core files (see Task 1). Base branch for the finish menu: `main`. Baseline before Task 1: core suite green at **127 tests / 10 suites**.

## Global Constraints

Every task's requirements implicitly include this section. Values copied verbatim from the spec and `Packages/WorkoutLoggerCore/CONTEXT.md` / the ADRs.

- **One core-reopen.** Land 1a–1f together on this branch; do not split them across later cycles. `WorkoutLoggerCore` is frozen again when this branch merges.
- **No behaviour change to** load canonicalisation, the four orthogonal axes (ADR-0001), kilogram canonicalisation (ADR-0002), or the Epley formula `load * (30 + reps) / 30` (ADR-0003).
- **No new dependencies.** Foundation and Swift Testing only.
- **Swift 6 data-race clean.** `swift build` and `swift test` pass with the package's existing strictness. New stored closures stay `@Sendable` (see `knownBestsProvider`).
- **Vocabulary follows CONTEXT.md.** The stored-set type is `LoggedSet`, never `Set`. Do not introduce `session` as an identifier name (subsystem E review finding).
- **Test at the seam.** Assert externally observable behaviour (public properties, returned values, persisted `Workout`); never internal call order or private state.
- **Existing `WorkoutEngineTests` stay green unchanged after the 1e extraction (Task 7).** New behaviour gets new tests; the extraction proves itself by not disturbing the old ones.
- App name stays the placeholder "Trackit".

---

## File Structure

### `WorkoutLoggerCore` — Sources

| File | Responsibility | Tasks touching it |
|---|---|---|
| `Model.swift` | Domain value types. `Exercise: Hashable` (WIP, Task 1). `ParseResult` cases gain `confidence` (Task 5). | 1, 5 |
| `WorkoutEngine.swift` | Workout lifecycle + parser-result application. Also holds `public struct Workout`. WIP re-seed / `previousSet` wiring (Task 1). `Workout.templateName` added + stamped (Task 4). `hear` pattern update (Task 5). Maps re-keyed to `[Exercise: …]` (Task 6). Rest-timer + PR-tracker extracted (Task 7). | 1, 4, 5, 6, 7 |
| `RestTimer.swift` | **New (Task 7).** The count-up rest timer sub-machine lifted out of `WorkoutEngine`: `startedAt`, target resolution, `elapsed` / `targetReached`. Value type, engine-owned. | 7 |
| `PRTracker.swift` | **New (Task 7).** The personal-record sub-machine lifted out of `WorkoutEngine`: pre-workout seed, running best per exercise, `personalRecords` list, record / recompute / fold-in. | 7 |
| `Parser.swift` | Seam A. Threads the resolver's confidence into `.set` / `.announcement` results (Task 5). | 5 |
| `Resolver.swift` | Seam B. Unchanged — already returns `confidence: Double` on `.resolved`. | — |
| `Readback.swift` | `readbackStyle` — re-add the confidence gate for a shaky parse of a known exercise (Task 5). | 5 |
| `ExerciseProgress.swift` | Per-exercise progress fold. Stored fields `var` → `let`; private `estimatedOneRepMax(of:)` renamed (Task 3). | 3 |
| `WorkoutEditing.swift` | Pure `Workout` edit transforms. `movingSet` name-string comparisons → whole-value `Exercise` equality (Task 6). | 6 |
| `WorkoutTemplate.swift` | `WorkoutTemplate` / `TemplateItem`. Unchanged. | — |

### `WorkoutLoggerCore` — Tests

`WorkoutEngineTests.swift` (1a/1b WIP tests already present; +1d re-key/collision, +1f `templateName`, updated map literals), `ExerciseProgressTests.swift` (rename fallout), `ParserTests.swift` (+confidence score cases, `.set`/`.announcement` pattern updates), `ReadbackTests.swift` (+shaky-known-exercise case, signature updates), `WorkoutCodableTests.swift` (+`templateName` round-trip), `WorkoutTemplateTests.swift` (map literal + identity updates).

### `WorkoutLoggerApp` + `App/`

| File | Change | Task |
|---|---|---|
| `App/TrackitApp.swift` | `WorkoutEngine(…)` call gains `knownBestsProvider:`; `knownBests(from:)` helper re-keyed to `[Exercise: Double]`. Files-only. | 2, 6 |
| `Packages/WorkoutLoggerApp/…/Readback/ReadbackComposer.swift` | `case .set` / `case .announcement` pattern updates for the new `confidence` payload. | 5 |
| `Packages/WorkoutLoggerApp/…/Session/WorkoutSessionModel.swift` | Same pattern updates (`updateActiveExercise`, `exerciseName`). | 5 |
| `Packages/WorkoutLoggerApp` tests | `ReadbackComposerTests`, `WorkoutSessionModelTests`, any rig building `.set(…)` — pattern / literal updates. | 5, 6 |

---

## Task 1: Land the carried WIP — 1a engine re-seed, 1b `previousSet`, `Exercise: Hashable`

**Source:** spec 1a, 1b, 1d (conformance half). Three files arrived on this branch as uncommitted edits from a prior session; this task turns them into one reviewed commit and removes the noise.

**Files:**
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/Model.swift` (already edited — `Exercise: Hashable` + doc comment)
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift` (already edited — `knownBestsProvider`, `seededBests()`, `lastParsingContext`, `activeExercise` / `activePreviousParsedSet` / `displayUnitLoad`, `hear` builds a populated `WorkoutContext`)
- Modify: `Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutEngineTests.swift` (already edited — `secondWorkoutReSeedsThePRBar`, `hearFeedsParsingContext`, `previousSetTracksTheLastSet`)

**Interfaces:**
- Produces: `WorkoutEngine.init(…knownBestsProvider: (@Sendable () -> [String: Double])? = nil…)` — re-keyed to `[Exercise: Double]` in Task 6. `WorkoutEngine.lastParsingContext: WorkoutContext` (public read-only) — the context the last `hear(_:)` parsed against.
- Produces: `Exercise: Hashable` (whole-value, name + aliases).
- Consumes: nothing new.

- [ ] **Step 1: Read the carried diff**

Run: `git diff da52901 -- Packages/WorkoutLoggerCore`
Expected: exactly the three files above. Confirm the *functional* delta is only: `Exercise` gains `Hashable`; `WorkoutEngine` gains `knownBestsProvider` (stored `let`), `seededBests()` (`knownBestsProvider?() ?? knownBests`), `lastParsingContext` (stored, `= WorkoutContext()`), private `activeExercise` / `activePreviousParsedSet` / `displayUnitLoad`; `startWorkout()` and `resume(_:)` seed from `seededBests()` instead of `knownBests`; `hear(_:)` builds `WorkoutContext(activeExercise:previousSet:unit:)` and assigns `lastParsingContext`.

- [ ] **Step 2: Strip the doc-comment whitespace churn**

The WIP re-indented many `///` lines in `WorkoutEngine.swift` with a stray leading space. Restore every doc-comment line this branch touched to the single 4-space indent matching the surrounding declarations. Only lines whose sole change is leading whitespace — do not touch the functional edits. After this, `git diff da52901 -- WorkoutEngine.swift` should be roughly 40 lines, not ~126.

- [ ] **Step 3: Run the core suite**

Run: `cd Packages/WorkoutLoggerCore && swift test`
Expected: PASS, `Test run with 127 tests in 10 suites`.

- [ ] **Step 4: Verify the three carried tests assert the right seam**

Read `secondWorkoutReSeedsThePRBar`, `hearFeedsParsingContext`, `previousSetTracksTheLastSet`. Confirm each asserts a public observable (`engine.personalRecords`, `engine.lastParsingContext`) and not private state. The `final class Best: @unchecked Sendable` box in `secondWorkoutReSeedsThePRBar` is a test-local mutable holder for the provider closure — acceptable; leave it.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/Model.swift \
        Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift \
        Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutEngineTests.swift
git commit -m "feat(core): in-session PR-bar re-seed (1a), previousSet from hear (1b), Exercise: Hashable (1d)

Carried WIP from an earlier session, cleaned of doc-comment whitespace
churn and committed with its tests.

- WorkoutEngine gains an optional @Sendable knownBestsProvider; startWorkout
  and resume seed the PR bar from it when supplied, so a second workout in
  the same app run is judged against the first's records, not a
  launch-captured value.
- hear() builds a populated WorkoutContext (active exercise + its last set
  as a ParsedSet) and exposes it as lastParsingContext.
- Exercise conforms to Hashable over the whole value (name + aliases).

Claude-Session: https://claude.ai/code/session_01NPXLzSUXbBwoLLFVo2hg6z"
```

---

## Task 2: Wire the re-seed provider in the composition root (1a — App)

**Source:** spec 1a — "re-derive `knownBests` from the injected history closure (already available to the model as of subsystem D)". Task 1 added the engine hook; this connects it.

**Files:**
- Modify: `App/TrackitApp.swift` — the single `WorkoutEngine(…)` construction (around line 47) and the `static func knownBests(from history:)` helper (around line 133).

**Interfaces:**
- Consumes: `WorkoutEngine.init(…knownBestsProvider:…)` from Task 1; `TrackitApp`'s existing `history` closure.
- Produces: nothing new.

**Note:** `App/` does not compile in this environment. Make the edit minimal and idiomatic, and consistency-check it by eye against the engine signature. No test here — the behaviour is covered by `secondWorkoutReSeedsThePRBar` at the package seam.

- [ ] **Step 1: Pass the provider**

At the `WorkoutEngine(…)` call, add the provider argument alongside the existing launch-time `knownBests:` seed:

```swift
let engine = WorkoutEngine(
    store: store,
    library: library,
    unit: unit,
    knownBests: Self.knownBests(from: history()),        // launch-time seed, unchanged
    knownBestsProvider: { Self.knownBests(from: history()) }, // live re-seed each startWorkout
    now: now
)
```

Match the surrounding names (`history`, `store`, `library`, `unit`, `now`). The closure must be `@Sendable`; `Self.knownBests(from:)` is a static pure function over a `[Workout]` snapshot, so a `{ Self.knownBests(from: history()) }` literal is `@Sendable` as long as `history` is. If the compiler (when this target is eventually built) rejects capture of `history`, capture the store or model weakly and read history through it.

- [ ] **Step 2: Consistency-check**

Confirm `knownBests(from:)` still returns `[String: Double]` at this point (Task 6 re-keys it). Confirm no other `WorkoutEngine(` call exists in `App/` (there is only one; the test rigs are in the packages).

- [ ] **Step 3: Commit**

```bash
git add App/TrackitApp.swift
git commit -m "feat(app): feed WorkoutEngine a live knownBests provider (1a)

The engine now re-seeds the PR bar from history on every startWorkout, so
two workouts in one app run judge records correctly. Files-only; the App
target is not built in this environment.

Claude-Session: https://claude.ai/code/session_01NPXLzSUXbBwoLLFVo2hg6z"
```

---

## Task 3: 1f mechanical — immutable progress fields, unambiguous Epley overload

**Source:** spec 1f (subsystem D review, "Findings NOT taken").

**Files:**
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/ExerciseProgress.swift`
- Modify: `Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/ExerciseProgressTests.swift` (only if a test mutates a field in place)

**Interfaces:**
- Produces: `ExerciseSession` and `ExerciseProgress` stored properties become `public let`. Private free function `estimatedOneRepMax(of:)` renamed to `epleyEstimate(of:)`.
- Consumes: nothing new.

- [ ] **Step 1: Record the green baseline**

Run: `cd Packages/WorkoutLoggerCore && swift test --filter ExerciseProgress`
Expected: PASS.

- [ ] **Step 2: `var` → `let` on the stored fields**

In `ExerciseProgress`: `public var sessions` → `public let sessions`. (`bestEstimatedOneRepMaxKilograms` is computed — leave it.)
In `ExerciseSession`: `date`, `volumeKilograms`, `workingReps`, `topSetLoadKilograms`, `bestEstimatedOneRepMaxKilograms` all `public var` → `public let`.
Both memberwise inits already assign every field, so nothing else changes.

- [ ] **Step 3: Rename the private overload**

`private func estimatedOneRepMax(of set: LoggedSet) -> Double?` → `private func epleyEstimate(of set: LoggedSet) -> Double?`. Update its one call site (`working.compactMap(estimatedOneRepMax(of:))` → `working.compactMap(epleyEstimate(of:))`). The public `estimatedOneRepMax(loadKilograms:reps:)` in `WorkoutEngine.swift` is untouched; the ambiguity is gone.

- [ ] **Step 4: Run tests**

Run: `cd Packages/WorkoutLoggerCore && swift test`
Expected: PASS, 127 tests. If a progress test constructed a session and mutated a field afterwards, rewrite it to pass the value through the init.

- [ ] **Step 5: Commit**

```bash
git add Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/ExerciseProgress.swift \
        Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/ExerciseProgressTests.swift
git commit -m "refactor(core): immutable ExerciseProgress fields, rename private Epley overload (1f)

Claude-Session: https://claude.ai/code/session_01NPXLzSUXbBwoLLFVo2hg6z"
```

---

## Task 4: 1f — template identity on `Workout`

**Source:** spec 1f — "No template identity on `Workout` — required by cluster 2, so land it here." Cluster 2 re-loads the originating template on `resume`; it needs a stable handle. `WorkoutTemplate` has only `name`, so identity is the name.

**Files:**
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift` — `public struct Workout` gains `templateName: String?`; `startWorkout(from:)` stamps it.
- Modify: `Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutCodableTests.swift` — round-trip + missing-key decode.
- Modify: `Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutTemplateTests.swift` — identity assertion.

**Interfaces:**
- Produces: `Workout.templateName: String?` (stored, `= nil` default, `Codable` via synthesised `decodeIfPresent`). `Workout.init` gains a trailing `templateName: String? = nil` parameter. `startWorkout(from template:)` sets `templateName = template.name`; `startWorkout()` leaves it `nil`.
- Consumes: `WorkoutTemplate.name`.

- [ ] **Step 1: Write the failing tests**

In `WorkoutTemplateTests.swift`:

```swift
@Test("a workout started from a template records the template's name")
func templateIdentityRecorded() {
    let store = InMemoryWorkoutStore()
    let bench = Exercise(name: "Bench", aliases: ["bench"])
    let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
    engine.startWorkout(from: WorkoutTemplate(name: "Push Day", items: [TemplateItem(exercise: bench)]))
    #expect(engine.workout?.templateName == "Push Day")
}

@Test("a plain workout has no template name")
func plainStartHasNoTemplateName() {
    let store = InMemoryWorkoutStore()
    let engine = WorkoutEngine(store: store, library: .empty)
    engine.startWorkout()
    #expect(engine.workout?.templateName == nil)
}
```

In `WorkoutCodableTests.swift`:

```swift
@Test("templateName round-trips, and JSON without the key decodes as nil")
func templateNameRoundTrip() throws {
    let workout = Workout(entries: [], startedAt: Date(timeIntervalSince1970: 1), templateName: "Leg Day")
    let data = try JSONEncoder().encode(workout)
    #expect(try JSONDecoder().decode(Workout.self, from: data).templateName == "Leg Day")

    let legacy = #"{"entries":[],"startedAt":1}"#.data(using: .utf8)!
    #expect(try JSONDecoder().decode(Workout.self, from: legacy).templateName == nil)
}
```

Confirm the `legacy` JSON matches how `Workout` actually encodes `startedAt` (a bare `Double` seconds under the default strategy); adjust the literal in Step 4 if the encoder round-trip in the first half of the test shows a different shape.

- [ ] **Step 2: Run to verify they fail**

Run: `cd Packages/WorkoutLoggerCore && swift test --filter "templateIdentityRecorded|plainStartHasNoTemplateName|templateNameRoundTrip"`
Expected: FAIL — `templateName` is not a member of `Workout`.

- [ ] **Step 3: Add the field**

In `public struct Workout`:

```swift
    /// The name of the `WorkoutTemplate` this workout was started from, or `nil`
    /// for a plain `startWorkout()`. Recorded so a resumed templated workout can
    /// re-load its template and re-arm per-exercise rest targets (cluster 2).
    public var templateName: String?
```

Add `templateName: String? = nil` as the last parameter of `init` and `self.templateName = templateName` in the body. `Codable` stays synthesised — an optional property decodes a missing key as `nil` automatically.

- [ ] **Step 4: Stamp it in `startWorkout(from:)`**

`startWorkout(from:)` calls `startWorkout()` then arms the template rest targets. After the arming, add a mutation of the open workout:

```swift
        mutate { $0.templateName = template.name }
```

Use whatever the file's existing open-workout mutation helper is called (`mutate`, `updateWorkout`, `withWorkout` — match the surrounding code); the persisted revision must carry the name.

- [ ] **Step 5: Run the tests**

Run: `cd Packages/WorkoutLoggerCore && swift test`
Expected: PASS, 129 tests.

- [ ] **Step 6: Commit**

```bash
git add Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift \
        Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutCodableTests.swift \
        Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutTemplateTests.swift
git commit -m "feat(core): record originating template name on Workout (1f)

Cluster 2 needs a stable handle to re-load a resumed templated workout's
template. Optional + synthesised Codable, so existing records decode as nil.

Claude-Session: https://claude.ai/code/session_01NPXLzSUXbBwoLLFVo2hg6z"
```

---

## Task 5: 1c — parser confidence on confident results, re-added `readbackStyle` gate

**Source:** spec 1c; master spec readback story 20 ("terse when confident, fuller when unsure"). Today it is only half-live: a *new* exercise forces full TTS, a *shaky parse of a known* one does not, because `ParseResult.set` / `.announcement` carry no confidence. `Readback.swift` already carries a comment marking where the gate belongs.

**Files:**
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/Model.swift` — `ParseResult` cases.
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/Parser.swift` — produce the score.
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/Readback.swift` — consume it.
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift` — `hear` pattern update.
- Modify: `Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/ParserTests.swift`, `ReadbackTests.swift`.
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Readback/ReadbackComposer.swift`, `Session/WorkoutSessionModel.swift`.
- Modify: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/ReadbackComposerTests.swift`, `WorkoutSessionModelTests.swift` (any `.set(…)` / `.announcement(…)` literal or pattern).

**Interfaces:**
- Produces: `ParseResult.set(ParsedSet, confidence: Double)` and `ParseResult.announcement(Exercise, confidence: Double)`. Confidence is `1.0` for a form that matched by regex with no fuzzy name resolution (the straight and keyword load-set forms); for the inline, duration, distance, bodyweight and bare-name forms it is the resolver's score for the matched name (`0.60 ... 1.0`). An exact resolver match already returns `1.0`.
- Produces: `readbackConfidenceFloor` in `Readback.swift` = `confidentMatchThreshold` (0.85). A `.set` / `.announcement` whose `confidence < readbackConfidenceFloor` reads back `.full` even for a familiar exercise.
- Consumes: `resolve(_:in:)` → `.resolved(Exercise, confidence: Double)` (unchanged), `confidentMatchThreshold` (unchanged).

- [ ] **Step 1: Write the failing parser tests**

In `ParserTests.swift`:

```swift
@Test("a clean regex set match reports full confidence")
func straightSetIsFullyConfident() {
    let results = parse("100 for 5", context: WorkoutContext(unit: .kilograms), library: .empty)
    guard case .set(_, let confidence) = results.first else { Issue.record("expected a set"); return }
    #expect(confidence == 1.0)
}

@Test("an inline set against a fuzzily-matched name carries the resolver's confidence")
func inlineSetCarriesResolverConfidence() {
    let bench = Exercise(name: "Bench Press", aliases: ["bench"])
    let results = parse("bemch press 100 for 5", context: WorkoutContext(unit: .kilograms), library: ExerciseLibrary([bench]))
    guard case .announcement(_, let annConfidence) = results.first,
          case .set(_, let setConfidence) = results.dropFirst().first
    else { Issue.record("expected announcement + set"); return }
    #expect(annConfidence < 1.0 && annConfidence >= 0.60)
    #expect(setConfidence == annConfidence)
}

@Test("a bare exact announcement reports full confidence")
func bareExactAnnouncementIsFullyConfident() {
    let bench = Exercise(name: "Bench Press", aliases: ["bench"])
    let results = parse("bench", context: WorkoutContext(unit: .kilograms), library: ExerciseLibrary([bench]))
    guard case .announcement(_, let confidence) = results.first else { Issue.record("expected an announcement"); return }
    #expect(confidence == 1.0)
}
```

If `"bemch press"` scores outside `0.60 ..< 1.0` when you run Step 3, substitute another single-character corruption of a multi-token name — any such corruption lands in the fuzzy band with the current `editSimilarity` / `tokenSetSimilarity` scoring.

- [ ] **Step 2: Write the failing readback test**

In `ReadbackTests.swift` — update the `set()` helper to take an optional confidence and add the shaky case:

```swift
private func set(confidence: Double = 1.0) -> ParseResult {
    .set(ParsedSet(
        loadType: .external, effort: .reps, role: .working, grouping: .straight,
        load: 100, loadUnit: .kilograms, reps: 5
    ), confidence: confidence)
}

@Test("a shaky parse of a familiar exercise still gets a full readback")
func fullForLowConfidenceKnownExercise() {
    #expect(
        readbackStyle(for: set(confidence: 0.7), isNewExercise: false, capAtEarcon: false)
            == .full
    )
}
```

Match the real `ParsedSet` initialiser argument list in the `set()` helper — copy it from the existing helper rather than the shape above if they differ.

Also update the existing `.announcement(bench)` literal in `fullWhenExerciseIsNew` to `.announcement(bench, confidence: 1.0)`.

- [ ] **Step 3: Run to verify failure**

Run: `cd Packages/WorkoutLoggerCore && swift test`
Expected: compile failure — `.set` / `.announcement` arity mismatch across the suite. That is the intended source break; Steps 4–7 resolve it.

- [ ] **Step 4: Change `ParseResult`**

In `Model.swift`:

```swift
public enum ParseResult: Equatable, Sendable {
    case set(ParsedSet, confidence: Double)
    case announcement(Exercise, confidence: Double)
    case command(Command)
    case lowConfidence(reason: LowConfidenceReason, bestGuesses: [Exercise])
}
```

- [ ] **Step 5: Produce the score in `Parser.swift`**

- The keyword / straight load-set forms: `return [.set(set, confidence: 1.0)]`.
- `matchInlineExercise` already switches on `resolve`. Change its `.announce(Exercise)` result to `.announce(Exercise, confidence: Double)` and carry the score from the `.resolved` branch (`confidence >= confidentMatchThreshold`). The weak `.resolved` and `.unresolved` branches keep returning `.tooUnsure`.
- `announce(...)`: `return [.announcement(exercise, confidence: c), .set(set, confidence: c)]` where `c` is the carried score. The `isPlausible` guard still returns `.lowConfidence`.
- Bodyweight form: same — emit `.announcement(exercise, confidence: c)` and `.set(ParsedSet(…), confidence: c)`.
- Bare-name form: `case .resolved(let exercise, let confidence): return [.announcement(exercise, confidence: confidence)]`.
- Exact matches from `resolve` already return `1.0`, so an exact bare name or exact inline name gets `1.0` for free.

- [ ] **Step 6: Consume it in `Readback.swift`**

```swift
/// A parse whose confidence is below this reads back in full even for a
/// familiar exercise — story 20's "fuller when unsure". Shares the resolver's
/// confident-match bar; split it out if the two ever need to diverge.
let readbackConfidenceFloor = confidentMatchThreshold

public func readbackStyle(
    for result: ParseResult,
    isNewExercise: Bool,
    capAtEarcon: Bool
) -> ReadbackStyle {
    if capAtEarcon { return .earcon }

    switch result {
    case .lowConfidence:
        return .full
    case let .set(_, confidence), let .announcement(_, confidence):
        if confidence < readbackConfidenceFloor { return .full }
        return isNewExercise ? .full : .terse
    case .command:
        return .earcon
    }
}
```

Delete the stale "not wired here yet" comment block above the function.

- [ ] **Step 7: Update the consumers**

- `WorkoutEngine.hear`: `case .set(let parsedSet, _):` and `case .announcement(let exercise, _):` — the engine ignores confidence (it applies every non-low-confidence result).
- `ReadbackComposer.readbackPlan` (App): `case .set(let set, _):`, `case .announcement(let exercise, _):`.
- `WorkoutSessionModel.updateActiveExercise` / `exerciseName` (App): `for case .announcement(let exercise, _) in results`.
- Every remaining test literal: `.set(x)` → `.set(x, confidence: 1.0)`, `.announcement(y)` → `.announcement(y, confidence: 1.0)`, and `case .set(let s)` → `case .set(let s, _)` unless the test is about confidence.

- [ ] **Step 8: Run both suites**

Run: `cd Packages/WorkoutLoggerCore && swift test` — Expected: PASS (~135 tests).
Run: `cd Packages/WorkoutLoggerApp && swift test` — Expected: PASS, 224 tests, count unchanged.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat(core): parser reports confidence on confident results; readback gates on it (1c)

ParseResult.set / .announcement now carry a confidence Double — 1.0 for a
clean regex match, the resolver's score for a fuzzily-matched name.
readbackStyle forces a full readback below the confident-match bar, so a
shaky parse of a familiar exercise is spoken in full (story 20).

Claude-Session: https://claude.ai/code/session_01NPXLzSUXbBwoLLFVo2hg6z"
```

---

## Task 6: 1d — value-key the three per-exercise maps

**Source:** spec 1d — `knownBests`, `bestOneRepMax`, `templateRestTargets` are `[String: …]` keyed on `exercise.name`; two library exercises normalising to the same display name, or alias drift, collide or miss silently. `Exercise: Hashable` landed in Task 1; this keys the maps on the value.

**Files:**
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift`
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEditing.swift` — `movingSet` name comparisons.
- Modify: `App/TrackitApp.swift` — `knownBests(from:)` helper return type + key. Files-only.
- Modify: `Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutEngineTests.swift`, `WorkoutTemplateTests.swift` — map literals.
- Modify: `Packages/WorkoutLoggerApp` tests / rigs that pass a `knownBests:` literal.

**Interfaces:**
- Produces: `WorkoutEngine.init(…knownBests: [Exercise: Double] = [:]…knownBestsProvider: (@Sendable () -> [Exercise: Double])? = nil…)`. Internal `bestOneRepMax: [Exercise: Double]`, `templateRestTargets: [Exercise: TimeInterval]`. `activeExercise` (added Task 1) is the map key.
- Consumes: `Exercise: Hashable` (Task 1).

- [ ] **Step 1: Write the failing collision test**

In `WorkoutEngineTests.swift`:

```swift
@Test("same-name exercises with different aliases do not share a personal-record bar")
func personalRecordBarIsValueKeyed() {
    let rowA = Exercise(name: "Row", aliases: ["barbell row"])
    let rowB = Exercise(name: "Row", aliases: ["cable row"])
    let store = InMemoryWorkoutStore()
    let engine = WorkoutEngine(
        store: store,
        library: ExerciseLibrary([rowA, rowB]),
        knownBests: [rowA: 500]   // rowA carries an unbeatable historical bar
    )
    engine.startWorkout()
    engine.hear(["cable row 100 for 5"])   // e1RM ~116.7 — a PR for rowB, which has no bar
    #expect(engine.personalRecords.map(\.exercise) == [rowB])
}
```

If the resolver cannot pick `rowB` from `"cable row"` unambiguously (both `Row` entries score similarly), assert at the map boundary instead: seed `knownBests: [rowA: 500]`, drive `rowB` in through its unique alias, and confirm `rowB`'s set is flagged because its bar is `0`, not `rowA`'s `500`. Tune the aliases so exactly one entry resolves from the spoken phrase.

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/WorkoutLoggerCore && swift test`
Expected: compile failure on `knownBests: [rowA: 500]` (`[String: Double]` expected).

- [ ] **Step 3: Re-key the maps in `WorkoutEngine.swift`**

- `private let knownBests: [Exercise: Double]`
- `private let knownBestsProvider: (@Sendable () -> [Exercise: Double])?`
- `private var bestOneRepMax: [Exercise: Double] = [:]`
- `private var templateRestTargets: [Exercise: TimeInterval] = [:]`
- `init(…, knownBests: [Exercise: Double] = [:], …, knownBestsProvider: (@Sendable () -> [Exercise: Double])? = nil, …)`
- `seededBests() -> [Exercise: Double]`
- `recordPersonalBest` / `recomputeBest`: `bestOneRepMax[exercise.name]` → `bestOneRepMax[exercise]`; `knownBests[exercise.name]` → `knownBests[exercise]`. Any `.filter { $0.exercise == exercise }` is already whole-value.
- `resume(_:)`: `best[entry.exercise.name]` → `best[entry.exercise]`.
- `startWorkout(from:)`: the `Dictionary(template.items.compactMap { … ($0.exercise.name, $0.restTargetSeconds) })` build → key by `$0.exercise`.
- `currentRestTargetSeconds`: read `templateRestTargets[activeExercise]` (the `Exercise?` added in Task 1), not the name.
- `activeExerciseName`: if `currentRestTargetSeconds` was its only caller, delete it; otherwise leave it.

- [ ] **Step 4: Whole-value equality in `WorkoutEditing.swift`**

`movingSet`: `entries[entryIndex].exercise.name != toExercise.name` → `entries[entryIndex].exercise != toExercise`; `firstIndex(where: { $0.exercise.name == toExercise.name })` → `firstIndex(where: { $0.exercise == toExercise })`. Confirm the existing "move to same exercise is a no-op" test still passes — the guard now compares whole values, stricter but correct.

- [ ] **Step 5: Update `App/TrackitApp.swift`**

`static func knownBests(from history: [Workout]) -> [Exercise: Double]` — change the return type and `best[entry.exercise.name]` → `best[entry.exercise]`. The Task 2 call sites now type-check against the re-keyed engine init. Files-only.

- [ ] **Step 6: Update test literals**

Every `knownBests: ["Bench": …]` in `WorkoutEngineTests.swift` / `WorkoutTemplateTests.swift` / the `WorkoutLoggerApp` rigs → `knownBests: [bench: …]` using the `Exercise` value in scope. `secondWorkoutReSeedsThePRBar` (Task 1) uses `["Bench": best.value]` — change to `[seededBench: best.value]`. Any `templateRestTargets` seed literal in `WorkoutTemplateTests` re-keyed the same way.

- [ ] **Step 7: Run both suites**

Run: `cd Packages/WorkoutLoggerCore && swift test` — Expected: PASS.
Run: `cd Packages/WorkoutLoggerApp && swift test` — Expected: PASS, 224.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(core): value-key knownBests / bestOneRepMax / templateRestTargets on Exercise (1d)

Exercise: Hashable (Task 1) lets the three per-exercise maps key on the
whole value instead of exercise.name, so same-name library entries and
alias drift can no longer collide or miss silently. movingSet compares
whole Exercise values too.

Claude-Session: https://claude.ai/code/session_01NPXLzSUXbBwoLLFVo2hg6z"
```

---

## Task 7: 1e — split `RestTimer` and `PRTracker` out of `WorkoutEngine`

**Source:** spec 1e — `WorkoutEngine` owns lifecycle, parser-result application, load canonicalisation, PR detection *and* rest-timer state. The rest-timer and PR sub-machines move behind their own types without changing the engine's public surface. Spec: "mechanical extraction, behaviour-preserving, existing engine tests stay green unchanged. Do this *after* 1a and 1d so the extracted types are born clean."

**Files:**
- Create: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/RestTimer.swift`
- Create: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/PRTracker.swift`
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift` — own an instance of each, delegate.
- No test file changes expected. If any `WorkoutEngineTests` case breaks, the extraction changed behaviour — fix the forwarding, not the test.

**Interfaces:**
- `RestTimer` (value type, engine-owned): `mutating func start(at: Date)`, `mutating func skip()`, `mutating func arm(_ targets: [Exercise: TimeInterval])`, `mutating func reset()`, `var startedAt: Date?`, `func elapsed(now: Date) -> TimeInterval?`, `func currentTarget(activeExercise: Exercise?) -> TimeInterval`, `func targetReached(now: Date, activeExercise: Exercise?) -> Bool`. Holds `startedAt`, an injected `defaultTarget`, and `armed: [Exercise: TimeInterval]`.
- `PRTracker` (value type, engine-owned): `init(seed: [Exercise: Double], provider: (@Sendable () -> [Exercise: Double])?)`, `mutating func reseed()`, `mutating func record(_ set: LoggedSet, for exercise: Exercise) -> PersonalRecord?`, `mutating func recompute(for exercise: Exercise, from sets: [LoggedSet])`, `mutating func foldIn(_ workout: Workout)`, `var personalRecords: [PersonalRecord]`. Holds `seed`, `provider`, `running: [Exercise: Double]`, `personalRecords`.
- `WorkoutEngine` public surface is **unchanged**: `personalRecords`, `restStartedAt`, `restElapsedSeconds`, `currentRestTargetSeconds`, `isRestTargetReached` all forward to the two sub-objects.

- [ ] **Step 1: Record the green baseline**

Run: `cd Packages/WorkoutLoggerCore && swift test --filter "Workout engine|Workout Template"`
Expected: PASS. Note the exact count.

- [ ] **Step 2: Extract `RestTimer`**

Create `RestTimer.swift` with the struct above. Move the logic verbatim from `WorkoutEngine`:
- `elapsed(now:)` = `startedAt.map { now.timeIntervalSince($0) }`
- `currentTarget(activeExercise:)` = `activeExercise.flatMap { armed[$0] } ?? defaultTarget`
- `targetReached(now:activeExercise:)` = `elapsed(now:).map { $0 >= currentTarget(activeExercise:) } ?? false`

In `WorkoutEngine`: replace the stored `restStartedAt`, `restTarget`, `templateRestTargets` with `private var rest: RestTimer`, initialised `RestTimer(defaultTarget: restTarget)`. Rewrite each accessor as a forward:
- `restStartedAt` → `{ rest.startedAt }`
- `restElapsedSeconds` → `rest.elapsed(now: now())`
- `currentRestTargetSeconds` → `rest.currentTarget(activeExercise: activeExercise)`
- `isRestTargetReached` → `rest.targetReached(now: now(), activeExercise: activeExercise)`
- `startRest()` → `rest.start(at: now())`; `skipRest()` → `rest.skip()`
- `appendSet`'s `restStartedAt = set.loggedAt` → `rest.start(at: set.loggedAt)`
- `startWorkout()` / `resume(_:)` rest resets → `rest.reset()`
- `startWorkout(from:)`'s target dictionary → `rest.arm(<the [Exercise: TimeInterval] dictionary>)`
- `endWorkout()`'s `restStartedAt = nil` → `rest.skip()`

- [ ] **Step 3: Run engine + template tests**

Run: `cd Packages/WorkoutLoggerCore && swift test --filter "Workout engine|Workout Template"`
Expected: PASS, same count as Step 1. If not, fix the forwarding — do not touch the tests.

- [ ] **Step 4: Extract `PRTracker`**

Create `PRTracker.swift`. Move `knownBests` (→ `seed`), `knownBestsProvider` (→ `provider`), `bestOneRepMax` (→ `running`), `personalRecords`, `seededBests()`, `recordPersonalBest`, `recomputeBest`, and the `resume` fold loop into it:
- keep `personalRecords` inside `PRTracker`, exposed read-only; `reseed()` clears it and reloads `running` from `provider?() ?? seed`.
- `record(_:for:)` folds the set into `running`, appends to `personalRecords` if it beats the bar, and returns the appended `PersonalRecord?` for callers that want it.
- `recompute(for:from:)` takes the working sets the engine gathers (`workout.entries.filter { $0.exercise == exercise }.flatMap(\.sets)`).
- `foldIn(_:)` is the `resume` seeding loop.

In `WorkoutEngine`: `private var pr: PRTracker`, initialised `PRTracker(seed: knownBests, provider: knownBestsProvider)`.
- `personalRecords` → `{ pr.personalRecords }`
- `startWorkout()`'s PR reset → `pr.reseed()`
- `appendSet`'s `recordPersonalBest(set, for: exercise)` → `pr.record(set, for: exercise)`; the retry branch's `recomputeBest(for:)` → `pr.recompute(for: exercise, from: <sets>)`
- `editSet` / `removeSet`'s `recomputeBest(for:)` → `pr.recompute(for:from:)`
- `resume(_:)`'s seed + fold → `pr.reseed(); pr.foldIn(workout)`

- [ ] **Step 5: Run the full core suite**

Run: `cd Packages/WorkoutLoggerCore && swift test`
Expected: PASS, unchanged count from before Task 7. Every pre-existing `WorkoutEngineTests` case green **with no edit**.

- [ ] **Step 6: Run the App suite**

Run: `cd Packages/WorkoutLoggerApp && swift test`
Expected: PASS, 224. `WorkoutEngine`'s public surface is unchanged.

- [ ] **Step 7: Commit**

```bash
git add Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/RestTimer.swift \
        Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/PRTracker.swift \
        Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift
git commit -m "refactor(core): extract RestTimer and PRTracker from WorkoutEngine (1e)

Two cohesive sub-machines move behind their own value types. WorkoutEngine's
public surface is unchanged and every existing engine test passes unchanged.
Born value-keyed (1d) and re-seeding (1a).

Claude-Session: https://claude.ai/code/session_01NPXLzSUXbBwoLLFVo2hg6z"
```

---

## Task 8: Reconcile the spec, run both suites, whole-branch review

**Files:**
- Modify: `docs/superpowers/specs/2026-09-06-v1.1-deferred-work-design.md` — mark Cluster 1 landed.
- Modify: `Packages/WorkoutLoggerCore/CONTEXT.md` if it names the string-keyed maps or the monolithic engine.

- [ ] **Step 1: Full green run, both packages**

```bash
cd Packages/WorkoutLoggerCore && swift test
cd ../WorkoutLoggerApp && swift test
```
Expected: both PASS. Core up from 127 (post-Task-1) to roughly 135; App unchanged at 224.

- [ ] **Step 2: Reconcile the spec**

In the Cluster 1 section, add a landed note under each of 1a–1f pointing at this branch, mirroring how earlier subsystem specs were reconciled on merge. Note explicitly:
- 1b has no consumer yet (the grammar that leans on `previousSet` is cluster 7) — it is wired and asserted via `lastParsingContext`, nothing more.
- The `workoutTemplate(from:named:)` rest-target round-trip named in 1f is **not** in this cluster — it depends on cluster 2 recording template identity on use; `templateName` (Task 4) is the identity half it needs.

- [ ] **Step 3: Commit the reconciliation**

```bash
git add docs/ Packages/WorkoutLoggerCore/CONTEXT.md
git commit -m "docs: reconcile the v1.1 spec + CONTEXT with the cluster 1 landing

Claude-Session: https://claude.ai/code/session_01NPXLzSUXbBwoLLFVo2hg6z"
```

- [ ] **Step 4: Whole-branch review**

Dispatch `ecc:swift-reviewer` (and, for the `@Sendable` closure and the value-type extraction, `ecc:swift-concurrency-6-2`) against `git diff main...v1.1-core-seam-debt`. Fold findings in one wave, re-run both suites, then hand off via `superpowers:finishing-a-development-branch` with base branch `main`.

---

## Self-Review

**Spec coverage** — every Cluster 1 sub-item maps to a task:

| Spec item | Task(s) |
|---|---|
| 1a re-seed the PR bar | 1 (engine, carried WIP) + 2 (App wiring) |
| 1b feed `previousSet` from `hear` | 1 (carried WIP) |
| 1c parser confidence on confident results | 5 |
| 1d `Exercise: Hashable` + kill stringly-typed maps | 1 (conformance, carried WIP) + 6 (re-key) |
| 1e split `WorkoutEngine` into composed types | 7 |
| 1f `var`→`let` on progress types | 3 |
| 1f `estimatedOneRepMax(of:)` overload rename | 3 |
| 1f template identity on `Workout` | 4 |
| 1f `workoutTemplate` rest-target round-trip | **deferred to cluster 2** (documented in Task 8 Step 2 — depends on cluster 2's on-use template reload; Task 4 lands the identity half) |
| Cluster 1 out of scope: canonicalisation / axes / Epley / LLM fallback | untouched — Global Constraints |

**Ordering rationale:** Task 1 first — it turns the pre-applied WIP into a clean reviewed base and unblocks the rest. Tasks 2–4 are small and low-risk (App wiring, mechanical `let`/rename, one optional field). Task 5 (`ParseResult` source break) and Task 6 (map re-key) are the two structural changes; 5 before 6 so the `ParseResult` churn and the map churn are separate review surfaces. Task 7 (extraction) is last per the spec's explicit "after 1a and 1d" — the sub-types are then born re-seeding and value-keyed. Task 8 reconciles and reviews.

**Type consistency:** `knownBests` / `knownBestsProvider` are `[String: Double]` after Task 1 and become `[Exercise: Double]` in Task 6 — every call site (`App/TrackitApp.swift`, test rigs) is updated in Task 6 Steps 5–6. `ParseResult.set` / `.announcement` gain `confidence: Double` in Task 5 and are never changed again. `Workout.templateName` is added once (Task 4) and only read by cluster 2. `activeExercise` (private, added Task 1) is the rest-target map key from Task 6 on; `activeExerciseName` is deleted in Task 6 Step 3 only if `currentRestTargetSeconds` was its last caller. `RestTimer` / `PRTracker` (Task 7) consume the already-re-keyed `[Exercise: …]` maps — never the string form.

**Placeholder scan:** every code step carries the actual edit. Two deliberately empirical points, each with the rule for resolving it: the exact fuzzy string in Task 5 Step 1 (`inlineSetCarriesResolverConfidence`), and whether Task 6's collision test asserts through the resolver or at the map boundary (Task 6 Step 1). Both are decided by running the step, not guessed in advance.
