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
   Recommend (a) or (c) to keep Core frozen; (b) is "correct" but expensive.
2. **What is the `MuscleGroup` taxonomy?** Chest / back / shoulders / biceps /
   triceps / quads / hamstrings / glutes / calves / core / forearms? Push/pull/
   legs only? The granularity choice is a product decision and hard to change
   later (it's in exported data). `CONTEXT.md` will need the new term(s) added
   with an `_Avoid_` list.
3. **Counting rules.**
   - Warmups excluded (consistent with every other `ExerciseSession` field) —
     confirm.
   - Timed / distance working sets: do they count toward set volume? (They have
     no reps but they are training stimulus.)
   - Supersets/dropsets: one grouped round = N sets (one per exercise) or 1?
   - Does a "working" set below some rep/effort threshold count? (Probably yes;
     don't overthink.)
4. **Fractional attribution?** Serious hypertrophy trackers count a compound lift
   as e.g. 1.0 to the primary muscle and 0.5 to secondaries. Or is it a flat
   1.0 per involved group? Flat is simpler and defensible for v1.1.
5. **Unclassified exercises.** A custom exercise the user didn't tag: bucket it
   as "unclassified" in the per-group view, or omit it? (Recommend: show an
   "unclassified: N sets" row so the total reconciles.)
6. **Time window.** Per workout, per calendar week, per rolling 7 days, "this
   mesocycle"? Weekly is the convention. Is there a week-boundary setting
   (Mon vs Sun)?
7. **Does 7g-1 ship without 7g-2?** Set-volume-per-exercise is genuinely useful
   alone and needs no new data. Recommend shipping 7g-1 first as its own small
   PR, then 7g-2 once Q1/Q2 are resolved.
8. **Export.** Should set volume / muscle-group volume appear in the
   `WorkoutHistoryExport` output? (Probably yes for 7g-1's per-workout count;
   7g-2 only if the mapping is stable.)

---

## Effort

7g-1: small, pure Core + a passthrough + a view — half a day, needs the additive
`ExerciseSession` field blessed. 7g-2: medium, gated on the data-model decision
(Q1/Q2) and a taxonomy call; `writing-plans` pass recommended for 7g-2 only.

## Status

- [ ] OPEN QUESTIONS resolved (esp. Q1 mapping location, Q2 taxonomy, Q3 counting rules)
- [ ] 7g-1: `workingSetCount` + workout rollups + progress-screen surfacing (TDD)
- [ ] 7g-2: `MuscleGroup` + mapping + `muscleGroupSetVolume` + weekly view (TDD)
- [ ] `CONTEXT.md` updated with any new terms
- [ ] update parent roadmap + memory
