# Live-workout HUD (subsystem C)

**Date:** 2026-08-31
**Status:** draft, pending user review
**Scope:** the active-workout screen and everything around a workout while it is
running — the calm high-contrast HUD, the read-only swipe-up set list, the
tap-select fallback UI, keep-awake, and the launch resume-or-discard flow. Also
closes three deferrals carried out of the A+B review. Post-workout + progress
screens (D), onboarding / phrasebook / settings (E), and HealthKit / export /
telemetry (F) remain separate later cycles.

**Builds on:** `docs/superpowers/specs/2026-08-30-app-shell-skeleton-voice-pipeline-design.md`
(subsystems A + B, merged at `8b0c7ca`).

## Problem Statement

A lifter mid-set needs a two-second glance from across the gym to confirm the app
is keeping up. Today `App/Views/RootView.swift` is a bare placeholder: small text,
a plain button, a one-line rest string. There is no prominent rest timer, no way
to see the sets logged so far, and when voice cannot place an exercise the
candidates render as unstyled buttons. The screen locks between sets. On launch,
a workout the user forgot to end is not handled at all — it will silently accept
new sets days later and become a broken multi-day workout. Separately, two rough
edges shipped with A+B: opening the app with a corrupt SwiftData store crashes at
launch (`try! ModelContainer`), and the personal-record haptic fires on the first
working set of every exercise, so it stops signalling anything.

## Solution

A calm, high-contrast active-workout screen showing the current exercise, the
last set in large type, and a prominent count-up rest timer that changes state
when the rest target is reached — plus a large push-to-talk button findable
without looking. Swipe up to see every set logged for the current entry (v1 C is
**read-only**; inline correction is subsystem D). When voice cannot place an
exercise, a clear tap-select list. The screen stays awake for the duration of the
workout. On launch, if a workout was left open: resume it silently if it was
touched recently, or present a resume-or-discard prompt if it is stale. A corrupt
store no longer crashes — the app opens in a degraded mode that still logs the
live workout but shows history as unavailable. The PR haptic fires only for a
genuine new best.

## User Stories

1. As a lifter, I want a calm, high-contrast screen showing the current exercise,
   my last set in large type, and the rest timer, so that a two-second glance
   from across the gym is enough. *(v1 story 39)*
2. As a lifter, I want the current exercise clearly shown at all times, so that a
   glance tells me what my next set will be logged against. *(v1 story 34)*
3. As a lifter, I want my last logged set shown in the largest type on the
   screen, so that I can read it without moving closer.
4. As a lifter, I want a large, obvious push-to-talk button, so that I can find
   and press it without concentration. *(v1 story 40)*
5. As a lifter, I want the button to visibly change while it is listening, so
   that I know the app is capturing me.
6. As a lifter, I want a rest timer that counts up from my last set and is shown
   prominently, so that I know how long I have been resting without opening
   anything.
7. As a lifter, I want the rest timer to visibly change state when my rest target
   is reached, so that a glance tells me it is time to lift. *(v1 story 45, the
   visual half; the haptic + sound half shipped in B)*
8. As a lifter following a template, I want the rest target the timer counts
   toward to reflect that template's target for the current exercise, so that the
   display matches how I am training today. *(v1 story 44)*
9. As a lifter, I want to swipe up to see every set logged for the current entry,
   so that I can verify the app is keeping up. *(v1 story 41)*
10. As a lifter, I want each set in that list shown with its load, reps, and any
    warmup or grouping marker, so that I can scan it quickly.
11. As a lifter whose exercise name was not recognised, I want the app to prompt
    me to pick it from a list, so that I am never stuck. *(v1 story 32)*
12. As a lifter, I want to tap an exercise from that list instead of re-speaking,
    so that I have a reliable option when voice keeps failing. *(v1 story 33)*
13. As a lifter, I want dismissing the tap-select list without choosing to leave
    my workout untouched, so that a stray prompt costs nothing.
14. As a lifter, I want the screen to stay awake for the whole workout, so that it
    does not lock between sets. *(v1 story 42)*
15. As a lifter, I want the screen to resume normal auto-lock once the workout
    ends, so that it does not stay lit in my bag.
16. As a lifter who forgot to end yesterday's workout, I want the app to notice
    the stale open workout on next launch and offer to resume or discard it, so
    that I do not get a broken multi-day workout. *(v1 story 12)*
17. As a lifter who backgrounded the app for two minutes mid-workout, I want it to
    reopen straight into my workout with no prompt, so that a glance away does not
    interrupt me.
18. As a lifter who chooses to resume a stale workout, I want new sets to attach
    to it correctly and my earlier sets preserved, so that resuming is safe.
19. As a lifter who chooses to discard a stale workout, I want it closed as a
    completed workout at its last-activity time, so that my history stays honest
    and nothing is deleted.
20. As a lifter resuming a workout, I want the rest timer to start fresh rather
    than show hours of "rest", so that the display is meaningful.
21. As a lifter, I want a set that merely establishes my first recorded number for
    an exercise to log normally but not trigger the personal-record celebration,
    so that the PR haptic keeps meaning something.
22. As a lifter, I want a genuine new best — beating a number I have on record, or
    beating my own opening set later in the same workout — to still fire the PR
    haptic, so that real progress is still marked.
23. As a user whose local database is damaged, I want the app to still open and
    let me log today's workout, so that one corrupt file does not lock me out.
24. As a user in that state, I want a clear indication that my past workouts are
    temporarily unavailable, so that I am not misled into thinking they are gone.
25. As a lifter, I want all prominent numbers on the HUD rendered consistently
    (whole numbers without a trailing `.0`, a single spot for the brand numeric
    treatment), so that the screen reads cleanly.

## Implementation Decisions

### New and modified modules

**`WorkoutLoggerApp` — new `HUD/` group (all `swift test`-covered):**

- **`HUDProjection`** — a value type built from a `WorkoutSessionModel` snapshot
  that exposes exactly the glanceable fields the view renders, with all
  formatting and fallback logic here rather than in SwiftUI:
  - `exerciseName: String` — current entry's exercise, or a "No exercise yet"
    placeholder.
  - `lastSetLine: String?` — the most recent set formatted unit-aware, whole
    numbers without `.0` (the same rule `ReadbackComposer.number` uses; extract
    it to a shared helper).
  - `restLine: String?` — `mm:ss` count-up, `nil` when no rest is running.
  - `restTargetReached: Bool` — drives the timer's state change (story 7).
  - `isListening: Bool` — button state.
  - `currentEntrySetLines: [String]` — one formatted line per set of the current
    entry, warmup / superset / dropset marked (story 10). Read-only.
  - `tapSelectCandidates: [Exercise]?` — passthrough of the model's field.
  - Two inits: `init(from:)` (`@MainActor`, reads the model) and a memberwise
    init for tests.
- **`LaunchDecision`** — `enum LaunchDecision: Equatable { case fresh,
  resume(Workout), promptStale(Workout) }` and a pure
  `launchDecision(openWorkout: Workout?, now: Date, staleAfter: TimeInterval =
  6 * 60 * 60) -> LaunchDecision`. `nil` → `.fresh`; an open workout with
  `isStale(now:staleAfter:)` true → `.promptStale`; otherwise `.resume`.
- **`closeAbandonedWorkout(_ workout: Workout, in store: SwiftDataWorkoutStore)`**
  — the discard branch of `.promptStale`. Pure of the engine: sets `endedAt =
  workout.lastActivityAt` (not `now()` — the workout ended whenever it was last
  touched, story 19) and calls `store.save`. Nothing is deleted. The app then
  proceeds as `.fresh`.
- **`StoreProvisioning`** — `enum StoreAvailability { case ready(ModelContainer),
  degraded(ModelContainer) }` and `provisionStore(onDiskURL:) -> StoreAvailability`.
  Tries the on-disk `ModelContainer(for: WorkoutRecord.self)`; on any throw, falls
  back to an in-memory container and returns `.degraded`. In-memory creation
  failing is genuinely unrecoverable and keeps a `try!` (see Further Notes).

**`WorkoutLoggerApp` — `WorkoutSessionModel` changes (additive):**

- New observed `private(set) var restTargetSeconds: TimeInterval` and
  `private(set) var isRestTargetReached: Bool`, snapshot-copied from the engine
  in `syncFromEngine()` and refreshed in `tick()`. The HUD needs both and the
  model does not surface them today.
- New observed computed `var keepScreenAwake: Bool` — `true` while `workout != nil
  && workout?.isEnded == false`. The `App/` view maps it to
  `UIApplication.shared.isIdleTimerDisabled`; nothing else touches `UIKit`.
- New init parameter `knownBestExercises: Set<String> = []` — the exercise names
  that had a seeded historical best. Used only for the PR-haptic decision below.
  Defaulted, so existing tests compile unchanged.
- **PR-haptic suppression.** When `engine.personalRecords` grows for an exercise
  `X`, the model fires `.personalRecord` only if the new best is *genuine*:
  `knownBestExercises.contains(X)` **or** the current workout already contained a
  working set for `X` before this utterance (a later set beating your own opener
  in the same session). Otherwise the set still logs and still taps `.logged`,
  but `.personalRecord` is suppressed — it was only establishing the baseline.
- **Resume seeding.** If the model is constructed with a workout already in
  progress (the resume path), its `announcedThisWorkout` is seeded from
  `workout.entries.map(\.exercise.name)`, so the first readback after resuming an
  exercise is terse, matching "already announced this workout".

**`WorkoutLoggerCore` — one additive `WorkoutEngine` seam:**

```swift
/// Adopts an existing, not-yet-ended workout — the launch resume path for a
/// workout the user forgot to end. Precondition: `!workout.isEnded`.
public func resume(_ workout: Workout)
```

- Sets `self.workout = workout`; `activeEntryIndex` to the last entry's index
  (or `nil` if the workout has no entries yet).
- `personalRecords = []` — a resumed session has recorded none *this run*; the
  historical ones live in the workout's set history and in `knownBests`.
- Rebuilds `bestOneRepMax` from `knownBests` folded with the resumed workout's own
  existing working-set estimates, so a set logged after resuming is a PR only if
  it beats both history and what was already done this workout.
- `restStartedAt = nil` — a rest period from before the app was killed is
  meaningless (story 20).
- `retryTarget = nil`, `currentSupersetRunID = nil`, `supersetRunCount` set to the
  max `supersetRunID` already present (so a new run does not collide).
- `templateRestTargets = [:]` — template arming does not survive a relaunch; the
  timer falls back to the engine default until an exercise is re-announced.
- Calls `store.save(workout)` — an idempotent upsert by `startedAt`, harmless if
  the on-disk copy already matches, corrective if it drifted.
- No other engine behaviour changes. `hear`, `undo`, rest state, and PR detection
  all operate on the adopted workout exactly as on a freshly started one.

**`App/` (not `swift test`-covered):**

- **`Views/HUDView.swift`** replaces `RootView`'s placeholder body: a
  `HUDProjection`-driven layout — exercise name, big last-set number, rest timer
  card (state change on `restTargetReached`), the push-to-talk button
  (unchanged gesture wiring), and a swipe-up sheet listing
  `currentEntrySetLines`. A single `bigNumber` view modifier is the one place the
  brand numeric treatment attaches (the actual typeface token is a design task,
  not blocking).
- **`Views/TapSelectSheet.swift`** — renders `tapSelectCandidates` as a proper
  choice list, calls `model.resolveTapSelect(_:)`, dismiss-without-choosing is a
  no-op (story 13).
- **`Views/LaunchGateView.swift`** — on `.promptStale`, a two-button
  resume-or-discard prompt; `.resume` and `.fresh` fall straight through to the
  HUD.
- **`TrackitApp.swift`** — composition root wiring:
  1. `provisionStore(...)` → keep the `degraded` flag for a "history unavailable"
     banner.
  2. Build `SwiftDataWorkoutStore`, seed `knownBests` + `knownBestExercises` from
     `store.history()` (skipped in degraded mode — both empty).
  3. Build `WorkoutEngine`. Compute `launchDecision(openWorkout:
     store.openWorkout(), now:)`. On `.resume(w)` or a resume-accepted
     `.promptStale(w)`, call `engine.resume(w)` before building the model. On a
     discard-accepted `.promptStale(w)`, call `closeAbandonedWorkout(w, in:
     store)` and proceed as `.fresh` (the engine never adopts it).
  4. Build `WorkoutSessionModel` (its `init` `syncFromEngine()` picks up the
     resumed workout).
  5. Map `model.keepScreenAwake` to `isIdleTimerDisabled`, reset on workout end
     and on `scenePhase != .active`.

### What does not change

- No schema change. No new `@Model`. `WorkoutRecord` is untouched.
- `WorkoutStore` (the core protocol) stays save-only. `history()` / `openWorkout()`
  remain concrete `SwiftDataWorkoutStore` methods.
- The A+B voice loop (`pressed` / `released` / `apply` / readback / tap-select
  capture) is unchanged except for the additive fields above.

## Testing Decisions

### What makes a good test here

Assert on the projection's output, the decision enum, or engine state at a seam —
never on the SwiftUI hierarchy, view identity, or collaborator call counts. A
test that breaks when a subview is renamed is testing the wrong thing. Views in
`App/` are deliberately thin renderers so they need no logic tests; the couple of
snapshot / interaction checks the v1 spec allows wait for an environment that can
run `xcodebuild`.

### Modules and seams under test (`swift test`)

- **`HUDProjection`** (`WorkoutLoggerApp`): built from a real `WorkoutSessionModel`
  driven by the existing `Rig` fakes.
  - fresh model → `exerciseName` placeholder, `lastSetLine` / `restLine` nil,
    empty `currentEntrySetLines`.
  - after `"bench 100 for 5"` → `exerciseName` is the resolved exercise,
    `lastSetLine == "100 kg × 5"` (whole number, no `.0`), one entry in
    `currentEntrySetLines`.
  - a lb-unit model → `lastSetLine` renders in pounds.
  - rest running below target → `restLine` counts up `mm:ss`, `restTargetReached
    == false`; clock advanced past target → `restTargetReached == true`.
  - warmup / superset set → its marker appears in `currentEntrySetLines`.
  - `tapSelectCandidates` populated on the model → passed through.
- **`LaunchDecision`** (`WorkoutLoggerApp`): `nil` → `.fresh`; a workout last
  active 10 min ago → `.resume`; last active 8 h ago → `.promptStale`; boundary
  at exactly `staleAfter`.
- **`closeAbandonedWorkout`** (`WorkoutLoggerApp`): a stale workout last active
  8 h ago → after the call, `store.history()` holds it with `endedAt ==
  lastActivityAt` (not the test's `now`), `store.openWorkout()` is nil, and the
  set count is unchanged.
- **`StoreProvisioning`** (`WorkoutLoggerApp`): a bad on-disk URL / unreadable
  store → `.degraded` with a usable in-memory container, no throw.
- **`WorkoutSessionModel`** (`WorkoutLoggerApp`, extends `WorkoutSessionModelTests`):
  - `keepScreenAwake` true while a workout is open, false before the first
    `start workout` and after `end workout`.
  - `restTargetSeconds` / `isRestTargetReached` track the engine after a set and
    after the clock advances.
  - **PR haptic**: first working set of an exercise with no seeded best →
    `played == [.logged]` (suppressed). A heavier working set later in the same
    workout → `played` gains `.personalRecord`. An exercise present in
    `knownBestExercises`, first set beats it → `.personalRecord` fires on the
    first set. *(This replaces the A+B `firstSet` assertion of `[.logged,
    .personalRecord]`.)*
  - resume seeding: a model built with a two-entry workout in progress →
    re-announcing either exercise reads back terse, not full.
- **`WorkoutEngine.resume(_:)`** (`WorkoutLoggerCore`, extends `WorkoutEngineTests`):
  - `resume` a workout with two entries then `hear("bench 100 for 5")` → the set
    appends to the last entry; earlier sets intact; `restStartedAt` becomes
    non-nil from the new set (not the pre-relaunch value).
  - `resume` then `hear("undo")` → drops the last pre-existing set (adoption gives
    a working `activeEntryIndex`).
  - `resume` a workout that already contains a 100 kg × 5 working bench set, then
    `hear("bench 90 for 5")` → no new `PersonalRecord` (does not beat the
    in-workout best); then `hear("bench 110 for 5")` → one new `PersonalRecord`
    (does beat it).
  - `resume` then `endWorkout()` → persisted `endedAt` set to `now()`, workout in
    `history()`, `openWorkout()` nil (the ordinary end path on a resumed workout).
  - `resume` numbers a new superset run above any `supersetRunID` already in the
    adopted workout.

### Prior art

`WorkoutSessionModelTests` (real engine + fakes + injected clock), `ReadbackComposerTests`
(pure-projection assertions — the model for `HUDProjection` tests),
`SwiftDataWorkoutStoreTests` (in-memory container), and the core
`WorkoutEngineTests` (ordered-utterance → engine state — the model for the
`resume` tests).

### UI tests

Minimal and deferred: a HUD glanceable-state snapshot and a tap-select
interaction check, to be added when `xcodebuild` is available. All meaningful
logic sits below the view at the seams above.

## Out of Scope

- **Mid-workout inline set editing** (v1 story 38) — deferred to subsystem D with
  the rest of editing. The swipe-up list in C is read-only.
- Post-workout summary and edit screen, per-exercise progress charts,
  save-as-template (D).
- Onboarding, guided practice, phrasebook, the "speech is on-device / data is
  local" privacy screen, and any settings UI beyond what the model already needs
  (E).
- HealthKit writer, file export, telemetry queue and failed-utterance review (F).
- Lock-screen Live Activity, background-audio operation, earbud-button trigger
  (v1.1).
- Light mode; shipping the actual brand numeric typeface file (the HUD provides
  the single attach point; the token is a design deliverable).
- Streaming / partial transcripts and a "listening…" shimmer — `TranscriptSource`
  contract is unchanged; this is a later additive change.
- Any `WorkoutLoggerCore` change beyond the additive `resume(_:)` seam.

## Further Notes

- **The retained `try!`**: `provisionStore` catches on-disk container failure and
  falls back to an in-memory container with `try!`. If even an in-memory store
  cannot be created the process has no way forward, and an assertion crash there
  is the correct outcome — it is not the launch-crash story 23 is about.
- **Rest timer across a relaunch**: `resume` clears `restStartedAt`, so a resumed
  workout shows no rest until the next set. This is deliberate (story 20).
- **Template rest targets across a relaunch**: also dropped by `resume`. Rare
  (forgot to end a templated workout *and* it went stale) and self-heals as soon
  as an exercise is re-announced. Recording template identity on `Workout` to
  survive this is a possible v1.1 refinement, noted in the A+B spec's own
  deferrals.
- **`knownBestExercises` vs `knownBests`**: the model only needs the *set of
  names* that had a prior best, not the values (the engine already owns the
  numeric comparison). Passing the smaller thing keeps the model's surface
  minimal.
- **Keep-awake reset**: `isIdleTimerDisabled` is reset both when the workout ends
  and when the scene leaves `.active`, so a backgrounded mid-workout app does not
  hold the idle timer.
