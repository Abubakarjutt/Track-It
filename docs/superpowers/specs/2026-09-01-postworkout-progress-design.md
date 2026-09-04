# Subsystem D — Completed-Workout Review, Editing, and Per-Exercise Progress

**Status:** design approved, ready for implementation planning
**Date:** 2026-09-01
**Predecessors:** subsystem A+B (app shell + voice pipeline), subsystem C (live-workout HUD) — both merged to `main`
**Spec authority:** `Packages/WorkoutLoggerCore/specs/v1-voice-logging.md` (stories 37, 38, 47, 48, 49, 50, 51; story 58 named there but deferred — see Out of Scope)
**Glossary:** `Packages/WorkoutLoggerCore/CONTEXT.md`
**Relevant ADRs:** 0001 (Set as four orthogonal axes), 0002 (load canonicalisation in the workout engine), 0003 (Epley formula for estimated 1RM)

---

## Problem Statement

A lifter can start a workout, speak sets into the live HUD, and have them recorded and confirmed. After that, the record is a dead end:

- There is no way to look back at a completed workout. The chronological list of training occasions promised by the v1 spec does not exist.
- A set logged with the wrong load, reps, role, grouping, or against the wrong exercise stays wrong. The pure editing transforms exist in the core but nothing calls them.
- Mid-workout, the swipe-up set list is read-only. A misheard set has to be fixed by voice ("undo", re-speak) or not at all — there is no direct correction.
- Progress is invisible. The lifter cannot see how an exercise's load, volume, or estimated 1RM has moved over weeks, and cannot see how today's work compares with last time.

Three defects carried forward from subsystem C compound this:

- The rest countdown shows elapsed time only; the rest target is never displayed, so the lifter cannot see how much rest remains.
- The spoken readback path picks the exercise to name from the last entry in the workout rather than the genuinely active entry, so after re-announcing an earlier exercise the readback can name the wrong movement.
- The personal-record celebration gate is seeded once at launch from history; a second workout in the same app session, or edits made after resuming, are judged against a stale set of bests.

## Solution

Subsystem D adds the review-and-progress half of the app:

- **A workout history list** — every completed workout, most recent first, each row summarising the date, exercises, working-set volume, and duration. Tapping a row opens that workout.
- **A completed-workout detail screen** — the full contents of one workout, grouped by entry, with every set shown as a formatted line, plus workout totals, the workout note, and a personal-record badge on any working set whose estimated 1RM beat the lifter's prior best for that exercise.
- **Editing on the detail screen** — change any set's load, reps, role, or grouping; add or change a per-set note; move a set to a different exercise; delete a set; add or change the workout note. Every edit is a pure transform applied to the stored workout, re-saved under the same identity.
- **Mid-workout inline editing** — the swipe-up set list in the live HUD becomes editable. A row can be corrected or deleted; the change goes through a new workout-engine seam that keeps the live rest target, retry window, active entry, and personal-record bar consistent.
- **A per-exercise progress screen** — for one exercise, a chart of top-set load, working-set volume, and estimated 1RM across every workout that contained it, the heaviest working-set load of the most recent workout, and a "vs last time" comparison of the two most recent workouts.
- **"Vs last time" on the live HUD** — when an exercise becomes active during a workout, the HUD shows a one-line summary of the last completed workout's heaviest working-set load and best estimated 1RM for that exercise.
- **The three carried fixes** — the rest countdown gains a "elapsed / target" line; the readback path names the genuinely active exercise; the personal-record celebration gate re-derives from history when a workout ends.

Templates — saving a completed workout as a reusable shape, editing templates, starting a workout from a template — are explicitly **not** in this subsystem.

## User Stories

### Workout history list

1. As a lifter, I want a list of every completed workout with the most recent at the top, so that I can find a past training occasion quickly.
2. As a lifter, I want each history row to show the workout's date, so that I can orient myself in time.
3. As a lifter, I want each history row to show which exercises I trained, so that I can recognise the workout without opening it.
4. As a lifter, I want each history row to show the total working-set volume, so that I can gauge how hard the workout was at a glance.
5. As a lifter, I want each history row to show how long the workout took, so that I can compare training density over time.
6. As a lifter, I want the history list to contain only completed workouts, so that a workout still in progress does not appear as a finished record.
7. As a lifter, I want to tap a history row to open the full workout, so that I can review or correct it.
8. As a lifter, I want the history list to reload after I edit a workout, so that the summary figures stay accurate.
9. As a lifter, I want a clear empty state when I have no completed workouts yet, so that I understand the list is empty rather than broken.
10. As a lifter, I want a clear message when storage could not be opened, so that I know my history is temporarily unavailable rather than lost.

### Completed-workout detail screen

11. As a lifter, I want a completed workout shown grouped by entry, so that all the sets for one exercise are together.
12. As a lifter, I want each set shown as a readable line with load, unit, and reps, so that I can check what was recorded.
13. As a lifter, I want warm-up sets marked as warm-up, so that I can tell them apart from working sets.
14. As a lifter, I want superset and dropset sets marked, so that the grouping I performed is visible in the record.
15. As a lifter, I want the workout's total working-set volume shown, so that I have the headline number for that occasion.
16. As a lifter, I want the workout's total working reps shown, so that I can see the volume broken down.
17. As a lifter, I want the workout's duration shown, so that I know how long it took.
18. As a lifter, I want the workout note shown when there is one, so that any context I recorded is visible.
19. As a lifter, I want a personal-record badge on a working set whose estimated 1RM beat my previous best for that exercise, so that I can see when I made progress.
20. As a lifter, I want no personal-record badge on the first working set I ever record for an exercise, so that a badge always means I beat something.
21. As a lifter, I want no personal-record badge on a set that only tied or fell short of my previous best, so that the badge stays meaningful.
22. As a lifter, I want warm-up sets excluded from volume, reps, and personal-record consideration, so that the progress figures reflect real work only.

### Editing a completed workout

23. As a lifter, I want to change a recorded set's load, so that a misheard weight can be corrected.
24. As a lifter, I want to change a recorded set's reps, so that a misheard count can be corrected.
25. As a lifter, I want to change a recorded set's role between working and warm-up, so that a set logged with the wrong role is fixed.
26. As a lifter, I want to clear a recorded set's grouping back to straight or mark it as a dropset, so that the record matches what I actually did. (Joining a set into a specific superset run is out of scope — see Out of Scope.)
27. As a lifter, I want to add or change a note on a single set, so that I can record context for one set.
28. As a lifter, I want to move a set to a different exercise, so that a set logged against the wrong movement lands where it belongs.
29. As a lifter, I want moving a set to remove the entry it came from when that entry has no sets left, so that empty entries do not linger.
30. As a lifter, I want moving a set to a movement I already have an entry for to add the set to that entry, so that I do not end up with two entries for the same exercise.
31. As a lifter, I want moving a set to a movement I have no entry for to create a new entry, so that the set is still recorded.
32. As a lifter, I want to delete a set, so that a set that should never have been recorded is removed.
33. As a lifter, I want deleting the last set of an entry to remove the entry, so that the workout does not keep an empty entry.
34. As a lifter, I want to add or change the workout note, so that I can record context for the whole occasion.
35. As a lifter, I want my edits saved to the same workout record, so that editing does not create a duplicate.
36. As a lifter, I want the workout's totals and personal-record badges to reflect my edits the next time I view it, so that the record stays internally consistent.
37. As a lifter, I want a set editor whose controls only let me enter sensible loads and reps, so that I cannot save a nonsensical set.
38. As a lifter, I want to be told when an edit could not be saved, so that I do not believe a change stuck when it did not.
39. As a lifter, I want a failed save to leave the workout as it was, so that a storage error cannot corrupt the record.

### Mid-workout inline editing

40. As a lifter, I want the swipe-up set list during a workout to be editable, so that I can fix a misheard set without stopping.
41. As a lifter, I want to correct a set's load or reps from the swipe-up list, so that the running record is right.
42. As a lifter, I want to delete a set from the swipe-up list, so that a set logged in error is removed immediately.
43. As a lifter, I want a mid-workout correction to update the personal-record bar, so that a later genuine record is still detected and a corrected-down set does not leave the bar too high.
44. As a lifter, I want a mid-workout correction to clear the retry target, so that my next spoken set does not silently overwrite a set I just edited.
45. As a lifter, I want deleting the active entry's last set mid-workout to leave the workout pointing at a valid entry, so that my next spoken set is logged correctly.
46. As a lifter, I want the rest countdown to keep running through a mid-workout edit, so that correcting a set does not cost me my rest timing.
47. As a lifter, I want mid-workout edits to move only the row I chose, so that editing one set never disturbs another.

### Per-exercise progress screen

48. As a lifter, I want to open a progress screen for a specific exercise, so that I can see how that movement has developed.
49. As a lifter, I want a chart of the load I used for an exercise over time, so that I can see whether I am adding weight.
50. As a lifter, I want a chart of my working-set volume for an exercise over time, so that I can see whether I am doing more work.
51. As a lifter, I want a chart of my estimated 1RM for an exercise over time, so that I can see strength trend independent of the rep scheme I used.
52. As a lifter, I want the heaviest working-set load of my most recent workout for the exercise called out, so that I know my current top set. (Load and estimated 1RM only — the progress value carries no rep count.)
53. As a lifter, I want a "vs last time" comparison of my two most recent workouts for the exercise — top-set load, working-set volume, and estimated 1RM — so that I can see whether today beat the previous occasion.
54. As a lifter, I want workouts that did not contain the exercise left out of its progress screen, so that the trend is not broken by unrelated occasions.
55. As a lifter, I want warm-up sets excluded from every progress figure, so that the charts reflect real work.
56. As a lifter, I want loads shown in my chosen unit on the progress charts, so that the numbers match the rest of the app.
57. As a lifter, I want a clear empty state when I have no history for an exercise, so that I understand there is nothing to chart yet.
58. As a lifter, I want the progress screen to still render with only one workout of history, showing the single point and no comparison, so that it is useful from the second workout onward.
59. As a lifter, I want to reach an exercise's progress screen from a set on the completed-workout detail screen, so that I can jump from a set to its history.

### "Vs last time" on the live HUD

60. As a lifter, I want the HUD to show my last completed workout's top working-set load for the exercise I just announced, so that I have a target in front of me.
61. As a lifter, I want the HUD to show my best estimated 1RM for that exercise from history, so that I know what I am chasing.
62. As a lifter, I want the "vs last time" line to disappear when the active exercise is one I have never trained, so that it never shows a misleading comparison.
63. As a lifter, I want the "vs last time" line to ignore the workout currently in progress, so that it compares against a genuinely previous occasion.
64. As a lifter, I want the "vs last time" line to update when I announce a different exercise, so that it always reflects the movement I am on.

### Carried fixes

65. As a lifter, I want the rest countdown to show elapsed rest against my rest target, so that I know how much rest remains.
66. As a lifter, I want the rest countdown to show elapsed time only when there is no rest target, so that the line is still useful without a template.
67. As a lifter, I want the spoken readback to name the exercise I am actually logging against, so that after I re-announce an earlier movement the readback is not wrong.
68. As a lifter, I want the personal-record celebration to use an up-to-date set of bests after a workout ends, so that a second workout in the same session judges records correctly.

## Implementation Decisions

### Overall shape

- Subsystem D follows the pattern established by subsystem C: **pure projection types** that turn domain values into display models and are covered by `swift test`; **one `@Observable @MainActor` model per screen area** that owns loading and mutation; **dumb SwiftUI views** in the app target that read a projection and call model methods. No new persistence types, no restructuring of existing code.
- Two additive edits to the otherwise-frozen `WorkoutLoggerCore` are approved for this subsystem and no more: one new pure editing transform, and one new workout-engine seam for mid-workout edits. Everything else in the core is used as-is.

### WorkoutLoggerCore — additive edit 1: `movingSet` transform

- A new pure `Workout → Workout` transform is added alongside the existing editing transforms (`replacingSet`, `annotatingSet`, `removingSet`, `annotated`). Shape, from the design discussion:

  ```
  func movingSet(at entryIndex: Int, _ setIndex: Int, toExercise: Exercise) -> Workout
  ```

- Semantics:
  - Out-of-range `entryIndex` or `setIndex` returns the workout unchanged, matching the convention of the sibling transforms.
  - If the source entry's exercise has the same name as `toExercise`, the workout is returned unchanged — there is nothing to move.
  - Otherwise the set is removed from the source entry; if that empties the entry, the entry is dropped, exactly as `removingSet` does.
  - In the resulting entry list, the first entry whose exercise **name** matches `toExercise` receives the set, appended to the end of its set list. If no entry matches by name, a new entry for `toExercise` is appended to the workout with the moved set as its only set.
  - The moved set is carried verbatim: all four axes (load type, effort measure, role, grouping), its note, and its timestamp are unchanged.
- Pinned decisions:
  - The target entry is matched by exercise **name**, never by whole-value exercise equality — exercise equality folds in aliases, so a caller passing an exercise whose aliases differ from the stored entry's would otherwise create a duplicate entry.
  - The moved set is appended at the end of the target entry, not re-sorted by timestamp — this is a post-hoc correction, and a test pins the ordering.
  - `movingSet` does not touch grouping or any superset/dropset run identifier. Moving one set out of a dropset or superset run deliberately splits the run; clearing a grouping marker is a separate `replacingSet` edit.
  - The target entry is resolved from the entry list **after** the source removal, so an index shift caused by dropping an emptied source entry cannot cause a mismatch.

### WorkoutLoggerCore — additive edit 2: mid-workout edit seam on the workout engine

- Two methods are added to the workout engine for correcting the active workout in place. `moveSet` is deliberately **not** added — no mid-workout story moves a set across exercises, and the swipe-up list is per-entry. Shapes, from the design discussion:

  ```
  func editSet(at entryIndex: Int, _ setIndex: Int, with set: LoggedSet)
  func removeSet(at entryIndex: Int, _ setIndex: Int)
  ```

- Both follow the engine's existing handler shape: they mutate session state directly and route the record change through the same internal mutation path that persists via the injected store, so no extra save call is made. The engine is not actor-isolated; these are called on the main actor exactly like the existing voice-handling entry point.
- `editSet`:
  - No-op if there is no active workout or the indices are out of range.
  - Applies the pure `replacingSet` transform to the active workout.
  - Recomputes the best estimated 1RM for the exercise at `entryIndex`. Without this, a working set edited downward leaves the personal-record bar too high and a later genuine record is missed.
  - Clears the retry target unconditionally — the retry target is a `LoggedSet` value snapshot with no positional identity to compare against, and a re-spoken set must never silently overwrite a row the lifter just edited by hand. This matches `removeSet` and the existing undo path.
  - Leaves the active entry index and the rest timer untouched; no entry is added or removed and editing a past set does not restart rest.
- `removeSet`:
  - No-op if there is no active workout or the indices are out of range.
  - Captures the exercise at `entryIndex`, then applies the pure `removingSet` transform, which drops the entry if it empties.
  - Recomputes the best estimated 1RM for the captured exercise.
  - Clears the retry target unconditionally, matching the existing undo path.
  - Repairs the active entry index: before the transform it captures which entry is active; afterwards it points the index back at that same entry's new position, or at the last entry if the active entry was the one removed, or clears it when no entries remain. This is stricter than the undo path (which always jumps to the last entry) because `removeSet` can target an entry that is not the last one, and the swipe-up sheet's active entry can be an earlier one after a re-announcement (story 45).
  - Leaves the rest timer untouched; the lifter may still be resting.

### WorkoutLoggerApp — new pure projections

- **Workout summary projection** — turns one completed workout, plus the history that precedes it, into a display model: entry rows, a formatted line per set, workout totals (working-set volume, working reps, duration), the workout note, and a personal-record badge per working set. It takes prior history as an input because a personal-record badge requires something to beat; the first working set ever recorded for an exercise is not badged. Badge computation is expressed in terms of the existing per-exercise progress function and the existing Epley estimator, not a new hand-rolled fold over history.
- **Exercise progress projection** — turns the existing per-exercise progress value plus the lifter's chosen mass unit into: chart series for top-set load, working-set volume, and estimated 1RM (one point per workout that contained the exercise, oldest first so the charts read left-to-right in time, converted to the display unit); a heaviest-working-set line for the most recent workout; and a "vs last time" delta between the two most recent workouts — top-set load, working-set volume, and best estimated 1RM — which is absent when there are fewer than two. "Best working set" throughout means the working set with the greatest load, consistent with the core progress value's top-set field. The core progress value carries a top-set *load* and a best estimated 1RM but no rep count and no `LoggedSet`, so the heaviest-set call-out and the HUD "vs last time" line show load and estimated 1RM only — never a `load × reps` line.
- Both projections reuse the existing set-line formatting helper rather than re-implementing it. The helper's private rounding and unit-conversion functions are widened to module-internal so the progress projection can convert kilograms to the display unit for chart axes.

### WorkoutLoggerApp — new models

- **Workout history model** (`@Observable @MainActor`) — loads the completed workouts from the store, newest first (filtering out any workout still in progress, which the store's history accessor includes), exposes list rows, opens one workout for the detail screen, and applies an edit. It is constructed with the store-availability flag the launch composition root already computes (degraded when the on-disk store could not be opened) and exposes an "unavailable" state distinct from "no completed workouts yet", so the view can tell story 10 apart from story 9. `applyEdit` takes a `Workout → Workout` transform, applies it to the open workout, saves the result under its unchanged identity, then reads the store's last-save-error flag — the store never throws, it records the failure — immediately after its own save (the flag is only meaningful right after the model's own call, since the store is shared with the engine). If the flag is set it discards the transformed copy, leaves the open workout as it was, skips the reload, and exposes an error string for a non-blocking banner.
- **Exercise progress model** (`@Observable @MainActor`) — given an exercise, pulls the completed workouts from the store, runs the existing per-exercise progress function (passing workouts oldest first), and hands the resulting projection to the view. A degraded or empty store yields an empty projection and an empty state, never a crash.

### WorkoutLoggerApp — changes to existing components

- **Workout session model** gains:
  - An injected history handle — a closure returning the completed workouts — matching the closure-injection style already used for the clock and the stale-workout recovery hooks, and keeping the model off SwiftData directly. The new init parameters are defaulted so existing session-model tests compile unchanged, following subsystem C's convention.
  - A "previous workout" line for the active exercise, recomputed when the active exercise changes (not per set): it runs the per-exercise progress function over history with the in-progress workout filtered out by start time, and takes the most recent point. It is absent for an exercise with no prior history.
  - Thin `editSet` / `removeSet` wrappers taking a row index into the list the swipe-up sheet is showing — that list's rows map one-to-one to the active entry's sets, so the row index is a set index within that entry. The wrapper resolves the active entry as the *last* entry whose exercise name matches the tracked active-exercise name (matching how the HUD projection resolves it, since two entries can share a name), calls the engine seam, then re-syncs from the engine. No engine-private index is exposed to the app target.
  - A re-derivation of the personal-record celebration gate from history when a just-heard utterance ends the workout. The field holding the gate's known exercises changes from a constant to a variable. This fixes the celebration gate only; the engine's in-session personal-record bar remains seeded from launch-time history — see Further Notes.
  - The readback exercise-name lookup switches from "last entry in the workout" to the already-tracked active-exercise name.
- **HUD projection** gains two fields: a rest line formatted `m:ss / m:ss` as elapsed against the rest target (elapsed-only, `m:ss`, when no rest target exists) and a "vs last time" line fed from the session model's previous-workout line.

### App target (files only, consistency-checked, not built here)

- New screens: a history list view, a completed-workout detail view, a set editor, and an exercise progress view using Swift Charts.
- A navigation container is added: a navigation stack reached from a control on the HUD, routing history list → workout detail → exercise progress.
- The swipe-up set list sheet becomes editable (row tap to edit, swipe to delete), wired to the session model's new wrappers. The sheet currently receives only formatted strings; each row must now carry its set index within the active entry so the wrapper knows which set to edit or remove.
- The HUD gains the rest "elapsed / target" row and the "vs last time" row.

### Persistence

- No schema change. Edited workouts are saved through the existing store, which upserts on the workout's start time — an edit overwrites the workout's own record and never creates a duplicate. Start time is never changed by an edit, which is why the history model can re-select the edited workout by it after a reload. This assumes no two completed workouts share an exact start instant, which the save upsert key already relies on.

## Testing Decisions

A good test here asserts on the value a seam produces — a projection's display model, the workout persisted to an in-memory store, an observable change on a model — for a hand-constructed input with a hand-worked expected result (Epley estimates and volumes computed by hand, not by calling the same helper the code uses). Tests do not read private engine state; where a behaviour is internal (the personal-record bar, the active entry index) it is asserted through an observable effect (a later set correctly badged or not, the next logged set landing on the right entry). Tests survive refactoring because they name lifter-visible behaviour.

The seams under test, confirmed during the design discussion:

- **`movingSet` transform** — extends the existing editing-transform test suite in the core. Cases: move to an existing name-matched entry (appended at end); move creating a new entry; source entry dropped when emptied and kept when not; out-of-range indices are a no-op; same-name target is a no-op; target matched by name when aliases differ (no duplicate entry); moved set keeps grouping, run identifier, note, timestamp, and all four axes; target resolved after source removal when the source precedes the target and empties.
- **Mid-workout edit seam** — extends the existing workout-engine test suite. Cases: `editSet` replaces load and reps and persists; `editSet` lowers the personal-record bar so a subsequent lower set that beats the new bar is flagged and one that does not is not; `editSet` clears the retry target so a re-spoken set does not overwrite the edited row; `editSet` out-of-range and no-active-workout no-ops without a save. `removeSet` removes and persists; removing an earlier entry's last set points the active entry back at the lifter's current exercise so the next announced set lands there (story 45); after `removeSet` deletes the set that had set the bar, a later set beating the remaining best is still flagged; clears the retry target; leaves the rest timer untouched; out-of-range and no-active-workout no-ops.
- **Workout summary projection** — new pure test suite. Cases: entry rows and set lines match the formatting helper for a known workout; volume, working reps, and duration totals; workout note surfaced and absent; personal-record badge when the estimate beats prior history; no badge for an exercise absent from prior history; no badge on a tie or a shortfall; warm-ups excluded from totals and badge consideration.
- **Exercise progress projection** — new pure test suite. Cases: one chart point per workout in history order; kilogram-to-pound conversion for a pounds unit; best-working-set line from the most recent workout; "vs last time" delta between the two most recent workouts and absent with fewer than two; empty progress yields empty series and no delta.
- **Workout history model** — new test suite against a real in-memory instance of the store. Cases: loads only completed workouts, newest first; `applyEdit` with each transform (replace, move, remove, annotate) persists the change, reloads the list, and re-selects the workout by start time; a save failure leaves the open workout unchanged, populates the error string, and skips the reload; an edit does not add a second record.
- **Exercise progress model** — new test suite against a real in-memory store. Cases: seeded history yields the right point count for the exercise; workouts lacking the exercise are excluded end-to-end; a degraded or empty store yields an empty projection without crashing.
- **Workout session model** — extends the existing session-model test suite. Cases: the `editSet` / `removeSet` wrappers resolve the active entry from the active-exercise name and drive the engine, with the projection updating; removing the active entry's last set updates the readback target; the previous-workout line reflects the last completed workout for the active exercise and excludes the in-progress workout by start time; the previous-workout line is absent for a new exercise; after a workout that set a new best for an exercise ends, a subsequent same-session workout that beats that new best still fires the personal-record celebration on the first qualifying set (the gate re-derived from history — asserted through the celebration, not by reading the private gate set); the readback name lookup uses the active-exercise name after a re-announcement.
- **HUD projection** — extends the existing HUD-projection test suite. Cases: the rest line renders as `m:ss / m:ss` from elapsed seconds and a rest target and as elapsed-only `m:ss` with no target; the "vs last time" line is fed from the session model's previous-workout line and is absent when that is absent.

Prior art: the subsystem C HUD projection tests (pure projection, table-driven), the existing workout-engine tests (behavioural assertions on the engine through its public surface), the existing session-model tests (`@MainActor` suite driving the model and reading its observable state), and the existing store tests (real in-memory store, no mock).

The app target is not built in this environment; its new views and navigation are checked for consistency against the real model and projection signatures only.

## Out of Scope

- **Templates in every form** — saving a completed workout as a template, a template editor, starting a workout from a template, template persistence. This is a later subsystem, and **v1 story 58 (save a completed workout as a template) is explicitly deferred to it**. The pure `workoutTemplate(from:named:)` transform already in the core is left unused.
- **Joining a set into a superset run on the detail screen.** The grouping control clears a grouping back to straight or marks a set as a dropset. Assigning a set into a specific superset run needs a run identifier the editor has no way to choose, so story 26's superset case is limited to *clearing* an existing superset marker.
- **A third core edit to make the engine's in-session personal-record bar live.** The engine seeds its personal-record bar from launch-time history at the start of each workout. Making a second same-session workout judge records against the first would require a third additive core change, which is outside this subsystem's approved budget. Only the celebration gate is fixed here.
- **A standalone exercise picker for the progress screen.** The progress screen is reached from a set on the completed-workout detail screen. A browse-all-exercises entry point can come later.
- **Editing a set's effort measure** (reps vs duration vs distance) or **load type** on the detail screen. The set editor covers load, reps, role, grouping, and note. Changing the measure or load type of an already-recorded set is not a v1 correction path.
- **Cross-exercise set moves during an active workout.** Moving a set to a different exercise is a completed-workout action only.
- **Undo/redo of edits** on the detail screen. An edit is immediate and is itself corrected by another edit.
- **Chart interactions** — zoom, scrub, date-range selection, per-metric toggles on the progress charts. The charts render fixed series over all available history.
- **Deleting an entire workout** from the history list.
- **Any HealthKit, export, onboarding, phrasebook, or settings work** — those belong to later subsystems.

## Further Notes

- **Personal-record bar residue.** After this subsystem, the personal-record *celebration* — the haptic and visual flourish — uses an up-to-date set of bests re-derived from history when a workout ends. The engine's internal personal-record *bar*, which decides whether a given working set is a record as it is logged, is still seeded from launch-time history at the start of each workout. The only observable gap: a lifter who completes two workouts without relaunching the app, and sets a new estimated-1RM record for some exercise in the first, will have the second workout's sets for that exercise judged against the pre-first-workout best. The stored record is always correct; only a same-session repeat celebration can be over- or under-eager, which is rare and low-stakes. Closing it fully is a one-line core change deferred to whenever the core is next reopened.
- **"Vs last time" excludes the in-progress workout.** The store's history accessor returns the workout currently being logged (the engine re-saves it on every set). Every comparison against "last time" — on the live HUD and implicitly on the post-workout progress screen — filters it out by start time. This is load-bearing and is tested.
- **The two edit paths never share a write route.** A completed-workout edit is a pure transform followed by a save, with the engine entirely uninvolved — the workout is finished and has no live state to maintain. A mid-workout edit must go through the engine because the rest timer, retry window, and personal-record bar are live. The same pure transforms sit underneath both.
- **`recomputeBest` is the load-bearing call in the engine seam.** The engine's retry-correction path already refreshes the per-exercise best estimate after it rewrites a logged set; the undo path does *not* (it only clears the retry target and repairs the active entry index). Both new seam methods must refresh it regardless — a mutation path that changes or drops a working set without recomputing is how a silently wrong personal-record bar enters.
- **Progress and badge lookups use whole-value exercise equality.** The per-exercise progress function filters history with whole-value `Exercise ==`, which folds in the alias list. If a stored historical entry's aliases have drifted from the current library exercise, that workout is silently dropped from the chart (story 54) and from a badge baseline (story 19). Accepted for v1: the library is curated and aliases are stable within a release. `movingSet` uses name-matching specifically to avoid the write-side version of this.
- **Story 66 ("elapsed time only when there is no rest target") is satisfied vacuously, not by a dedicated branch.** `CONTEXT.md`'s "Rest target" is defined as always resolvable — "taken from the active template or **a global default**" — and `WorkoutEngine.currentRestTargetSeconds` implements exactly that (`templateRestTargets[active] ?? restTarget`, with `restTarget` defaulting to `defaultRestTargetSeconds`). So "no rest target" is not a state this app's domain model produces, and `HUDProjection.restLine` correctly never needs an elapsed-only path while a rest is running — it only omits the whole line when no rest has started (`restStartedAt == nil`), which is the *other* "no rest" case the spec already covers. Making "no rest target" a real, reachable state would mean widening `WorkoutEngine.restTarget` to `TimeInterval?` — a third core edit beyond this subsystem's approved two — and revising the glossary's "or a global default" clause to match. Reviewed and declined: the review-time code review flagged story 66 as an implementation gap; on inspection it is a spec-wording mismatch against an already-settled glossary term, not missing code.
- **Git repository, no issue tracker.** This project is a git repository (subsystem C merged at `79e3361`) but tracks specs as files under `docs/superpowers/specs/` (subsystems A+B and C precede this one). There is no configured issue tracker to publish to; the `ready-for-agent` step from the spec-writing skill does not apply here.
- **Next step:** implementation planning via the writing-plans skill, then subagent-driven execution, matching how subsystem C was built.
