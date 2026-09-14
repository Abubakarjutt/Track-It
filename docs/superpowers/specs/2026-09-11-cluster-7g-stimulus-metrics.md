# Cluster 7g — Set volume / per-muscle-group stimulus metrics

**Prerequisite reading:** `2026-09-11-v1.1-remaining-onboarding.md`.
**Parent:** `2026-09-06-v1.1-deferred-work-design.md` § "Cluster 7" → "Set volume / per-muscle-group stimulus metrics".
**Master spec:** "Not planned" list — *"**Set volume** / per-muscle-group stimulus
metrics (distinct from Volume; a v1.1 concern)."*
**`CONTEXT.md` already defines the term:**
> **Set volume**: A count of working sets, optionally per muscle group, used to
> gauge training stimulus. Distinct from Volume; not surfaced in v1.
> _Avoid_: hard sets, weekly sets

So the vocabulary is fixed; the metric is defined; only the surfacing and the
muscle-group dimension are unbuilt.

Impl-ready brief; the muscle-group data model is the open question.

---

## What exists today

`Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/ExerciseProgress.swift`:

- `exerciseProgress(for exercise: Exercise, across history: [Workout]) -> ExerciseProgress`
  — pure fold over `[Workout]`.
- `ExerciseSession` already carries `volumeKilograms` (Σ load×reps, working sets
  only), `workingReps` (Σ reps, working sets only), `topSetLoadKilograms`,
  `bestEstimatedOneRepMaxKilograms`. **Warmups never count** — the fold does
  `sets.filter { $0.role == .working }` (line 70).
- **"Set volume" — a working-set count — is not computed anywhere.** It's one
  line: `working.count`.
- **No muscle-group concept exists.** No `MuscleGroup` type, no field on
  `Exercise`, nothing. `Exercise` is `struct Exercise: Equatable, Hashable,
  Sendable, Codable { name: String; aliases: [String] }` (`Model.swift:16`).
- The progress screen (`App/Views/` + the progress model in `WorkoutLoggerApp`)
  draws `ExerciseSession` fields per exercise. There is no whole-workout or
  whole-week rollup view.

---

## The two deliverables

### 7g-1 — Set volume (working-set count), per exercise and per workout

Pure Core, small:

- Add `workingSetCount: Int` to `ExerciseSession` (Σ of working sets that
  session) — same `role == .working` filter the other fields use.
- Add a whole-workout rollup: `workoutSetVolume(_ workout: Workout) -> Int`
  (total working sets) and/or `workoutSetVolumeByExercise(_:) -> [Exercise: Int]`
  (using `Exercise` as a dict key — it's `Hashable`; this is also the
  de-stringly-typing direction cluster 1d took for `knownBests`).
- Surface it on the progress screen and/or a workout-detail view.

This half needs **no design decisions** beyond "where does it show" and can be a
straightforward TDD slice — *if* the Core team agrees to the additive
`ExerciseSession` field (Core is frozen; this is exactly the kind of thing that
needs an explicit budget nod).

### 7g-2 — Per-muscle-group stimulus (the hard part)

To answer "how many working sets did I do for chest this week", every exercise
must map to one or more muscle groups. That data does not exist. Options in the
OPEN QUESTIONS. Once the mapping exists:

- `muscleGroupSetVolume(across history: [Workout], in range: DateInterval) -> [MuscleGroup: Int]`
  — pure fold: for each working set, look up its exercise's muscle groups, add 1
  to each (or a fractional weight — see Q4).
- A new view: a weekly bar/table of set volume per muscle group, the standard
  hypertrophy-tracking surface.

---

## The seam

- **7g-1:** additive fields on `ExerciseSession` + new pure functions in
  `ExerciseProgress.swift` (or a sibling file). The App progress model gains a
  computed passthrough. No protocol changes.
- **7g-2:** a new `MuscleGroup` enum + an `Exercise → [MuscleGroup]` resolver.
  Where the mapping lives (bundled data file, a field on `Exercise`, a separate
  lookup type) is Q1. If it's a field on `Exercise`, that changes a `Codable`
  persisted-shape (`ExerciseRecord` in SwiftData) — migration required. If it's
  a side table keyed by exercise name, no `Exercise` change but the built-in
  exercise seed (`defaultExerciseSeed`) needs muscle data added.

---

## Acceptance tests

Package-level (`swift test`):

1. `workingSetCount` on `ExerciseSession` counts working sets, excludes warmups,
   excludes timed/distance sets per the chosen rule (Q3).
2. `workoutSetVolume` / `...ByExercise` sum correctly over a multi-exercise
   workout fixture.
3. Superset / dropset grouping: does a 3-exercise superset round count as 3 sets
   or 1? (Q3.) Pin whatever is decided.
4. (7g-2) `muscleGroupSetVolume` over a hand-built history + a fixed
   exercise→muscle map produces the expected per-group counts for a date range.
5. (7g-2) An exercise with no muscle mapping is handled deterministically
   (counted under "unclassified", or skipped — Q5).
6. Existing `ExerciseProgress` tests still pass (additive change).

No device work for the computation. The new views get the usual `TrackitTests`
smoke coverage.

---

## OPEN QUESTIONS

> **All 8 resolved 2026-09-12** with the repo owner (owner route: "go ahead with
> the recommendations"). The resolutions below drive the 7g-2 implementation;
> 7g-1 already shipped on its own (see Status). Summary: the mapping lives
> **App-side** in a `MuscleMap` (Core stays frozen); the full **11-group
> hypertrophy** taxonomy; **flat 1.0** attribution; an **unclassified** bucket so
> the total reconciles; a **Monday-start calendar week** window; per-group counts
> **deferred out of the export**.

1. **Where does the exercise→muscle-group mapping live?**
   - (a) A bundled data file (JSON/plist) shipped with the app, keyed by
    exercise name, covering the built-in seed. Custom exercises get a
    muscle-group picker in the exercise editor.
   - (b) A new field on `Exercise` (`primaryMuscles: [MuscleGroup]`,
    `secondaryMuscles: [MuscleGroup]`). Cleanest model, but changes the
    `Codable` shape → SwiftData migration + the export format + every test
   fixture that builds an `Exercise`.
   - (c) A separate `MuscleMap` lookup type in the App layer, Core stays
    untouched, the metric is computed App-side.
  > **Resolved 2026-09-12: (c)** — a `MuscleMap` lookup type in `WorkoutLoggerApp`,
   keyed by exercise **name** (case-insensitive, trimmed). `Exercise` is
   alias-order-sensitive per `Model.swift`, so name-keying is the robust seam.
   `MuscleGroup`, `MuscleGroupSetVolume`, and `MuscleMap.setVolume(across:in:)`
   live in the App package; Core's `workoutSetVolumeByExercise(_:)` stays put and
   the fold reuses it. Core stays frozen — no `Codable`-shape change, no
   migration, no export-format change. (a) is the follow-up once a custom-exercise
   muscle picker exists (then the mapping is user-authored and must persist).
   (b) rejected: the migration + fixture churn isn't warranted for v1.1.
2. **What is the `MuscleGroup` taxonomy?**
  > **Resolved 2026-09-12: the full 11-group hypertrophy set** — enum cases
   `chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves,
   core, forearms`. The raw values *are* these spellings; they become the
   exported keys once the export lands (Q8). `CaseIterable` for a stable display
   order. `CONTEXT.md` gains a "Muscle group" term with an `_Avoid_` list.
3. **Counting rules.**
  > **Resolved 2026-09-12:** warmups **excluded** (inherited — the fold reuses
   `workoutSetVolumeByExercise`, which filters `role == .working`); timed /
   distance working sets **count** (training stimulus even with no reps); a
   superset / dropset round counts **one per working entry**, not one per round
   (inherited from 7g-1); **no** rep/effort threshold — every working set counts.
4. **Fractional attribution?**
  > **Resolved 2026-09-12: flat 1.0 per involved group.** A compound lift's
   working sets add `count` to each group its exercise maps to. No primary /
   secondary weight — that has nothing to hang off (no `Exercise` field, per Q1).
5. **Unclassified exercises.**
  > **Resolved 2026-09-12: show an "unclassified: N sets" row** so the weekly
   total reconciles. `MuscleGroupSetVolume` carries `unclassified: Int` — working
   sets whose exercise the `MuscleMap` doesn't know — alongside `perGroup`, and
   `total == Σ perGroup.values + unclassified` is a testable invariant.
6. **Time window.**
  > **Resolved 2026-09-12: per calendar week, Monday start.** A workout belongs
   to the week its `startedAt` falls in. `calendarWeek(containing:in:)` returns
   that `DateInterval` (`Calendar.startingOfWeek` with `firstWeekday = .monday`,
   + 7 days); the view asks for "this week". A rolling-7-days window is a
   one-line swap if the Monday drop-off proves annoying. No week-boundary setting
   in v1.1.
7. **Does 7g-1 ship without 7g-2?**
  > **Resolved 2026-09-11: yes** — 7g-1 shipped first (Status). 7g-2 lands now
   that Q1/Q2 are resolved.
8. **Export.**
  > **Resolved 2026-09-12: defer per-group counts out of `WorkoutHistoryExport`.**
   7g-1 didn't touch the export, and 7g-2's mapping isn't yet user-stable (no
   custom picker). Revisit when (a) the picker exists and the mapping is durable.
   (7g-1's per-workout set count, if ever added, is separate and stable.)

---

## Effort

7g-1: small, pure Core + a passthrough + a view — half a day, needs the additive
`ExerciseSession` field blessed. 7g-2: medium, gated on the data-model decision
(Q1/Q2) and a taxonomy call; `writing-plans` pass recommended for 7g-2 only.

## Status

- [x] 7g-1: `workingSetCount` + workout rollups + progress-screen surfacing (TDD) — **delivered 2026-09-11**.
  - Core: `ExerciseSession.workingSetCount` (Σ working sets; warmups excluded — timed / distance /
    bodyweight working sets still count), populated by the `exerciseProgress` fold, plus
    `workoutSetVolume(_:)` and `workoutSetVolumeByExercise(_:)` (keyed by the whole `Exercise`
    value; a second entry for one exercise merges; a warmup-only / empty workout → 0 / ∅; the
    two rollups reconcile — the sum of the per-exercise counts equals the whole-workout total).
  - App: `ExerciseProgressProjection.setVolumeSeries` (one point per session, independent of
    tonnage) + `Comparison.setVolumeDelta`; surfaced as a "Set volume" chart and a "Sets: ±N"
    row on the per-exercise progress screen.
  - Tests: Core 169 (5 new `ExerciseProgressTests`); App 245 (the projection suite was extended
    with set-volume assertions — no new suite). Both green.
  - Counting rules pinned by 7g-1 (Q3): warmups excluded; timed / distance / bodyweight working
    sets DO count (Q3, "training stimulus"); a superset / dropset round counts one per working
    set entry, not one per round.
- [x] `CONTEXT.md` — no new term for 7g-1: "Set volume" is already defined there; the
  per-muscle-group term ("Muscle group") now lands with 7g-2.
- [x] OPEN QUESTIONS for 7g-2: Q1 (App-side `MuscleMap`, not Core), Q2 (the 11-group
  taxonomy), Q4 (flat 1.0), Q5 (the `unclassified` bucket), Q6 (Monday-start week) —
  **resolved 2026-09-12**; the recommended `writing-plans` pass followed
  (`2026-09-12-v1.1-cluster-7g-stimulus-metrics.md`).
- [x] 7g-2: `MuscleGroup` + mapping + per-muscle-group fold + weekly view (TDD) — **delivered 2026-09-14**.
  - App-side by decision (Q1 = c): **no `WorkoutLoggerCore` change** — the fold reuses the
    frozen `workoutSetVolume(_:)` / `workoutSetVolumeByExercise(_:)`; Core stays at 169.
  - `MuscleGroup` (the 11-group taxonomy, Q2), `MuscleMap` (exercise-name → groups,
    case/whitespace-insensitive) + `defaultMuscleMap` (the six starters), and
    `MuscleGroupSetVolume` (`perGroup` + the `unclassified` bucket that keeps `total`
    reconciling, Q5).
  - `calendarWeek(containing:in:)` (Monday start, Q6); `MuscleGroupStimulusModel`
    (`@MainActor @Observable`, the current-week fold over `isEnded` history);
    `MuscleGroupStimulusView` + a `chart.bar.fill` toolbar slot in `RootView`.
  - Counting rules inherited from Core (Q3/Q4): warmups excluded; timed / distance /
    bodyweight working sets count; a superset / dropset round counts one per working
    entry; attribution is flat 1.0 (Q4).
  - Tests: App 245 → 261 (+11 `MuscleGroupStimulus`, +5 `MuscleGroupStimulusModel`);
    Core unchanged at 169. Both green.
- [x] update parent roadmap + memory — done 2026-09-14 (deferred-work-design "Cluster 7"
  note + this spec's Status; the INDEX "Status snapshot" is dated, so left as-is).
