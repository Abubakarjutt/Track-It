# Subsystem F — HealthKit Sync, Export & Telemetry

> Design spec. Voice-first iOS workout logger (trackit). Follows the
> vocabulary in `Packages/WorkoutLoggerCore/CONTEXT.md` and the product
> principles in `PRODUCT.md`. Builds on subsystems A–E (app shell + voice
> pipeline, live-workout HUD, post-workout history/edit/progress,
> onboarding & settings), all merged to `main`. Origin: the v1 spec
> `Packages/WorkoutLoggerCore/specs/v1-voice-logging.md`, stories 59–63
> and its "HealthKit writer" / "Telemetry" implementation notes — this
> spec refines those against the architecture that actually shipped.

## Problem Statement

trackit records a clean, editable training history, and after subsystem E
it has a real preferences surface. But the record is a dead end:

- **Nothing reaches Apple Health.** A lifter's strength training never
  shows up in their wider fitness picture — the Health app, the Fitness
  rings, or any other app that reads `HKWorkout`s. Every other logger the
  lifter might have used does this.
- **There is no backup.** History lives only in the app's local SwiftData
  store. There is no CloudKit sync in v1 (deferred to v1.1), so a lost or
  reset phone loses every logged workout with no way to have guarded
  against it. The lifter cannot get their own data out in any form.
- **The app cannot learn what is failing.** When the parser mis-hears a
  set or a lifter abandons logging mid-workout, none of that is visible to
  the developer. There is no signal on which phrases fail, how often
  parses fail, or which features go unused — so recognition and UX
  problems can only be found by the developer training on their own phone.
- **A lifter who wants to help cannot.** When a parse fails, the lifter
  sees the failure but has no way to hand the failing phrase back for
  a fix, even if they would happily do so.

All four gaps are "around the loop" work: the core press-to-talk logging
loop is untouched.

## Solution

Three opt-in, independent capabilities, plus a review affordance, all
reachable from Settings:

- **Apple Health sync.** With the lifter's permission, each completed
  Workout is written to Apple Health once, when it ends, as a single
  traditional strength-training workout with its duration and a rough
  active-energy estimate. One-way: trackit writes, never reads.
- **Export.** A single action serialises the lifter's entire completed
  history to a file — JSON (lossless) or CSV (one row per Set) — and
  hands it to the iOS share sheet, so it can go to Files, AirDrop, or
  anywhere else. A manual backup the lifter owns.
- **Anonymous telemetry.** With the lifter's permission, the app reports a
  small, fixed set of anonymous events — workout started / completed,
  sets logged, parse-failure counts, feature usage — with **no audio and
  no workout content of any kind**. Off by default.
- **Failed-utterance review.** With the lifter's separate permission, the
  transcript text (only the text) of utterances the parser failed on is
  queued locally. The lifter reviews the queue in Settings and chooses,
  per item, whether to submit it. Nothing is sent without that tap.

Every flag defaults to off. The lifter opts in to each one on its own.

## User Stories

### Apple Health sync

1. As a lifter, I want my completed workouts written to Apple Health as
   strength training, so that they count in my wider fitness picture.
2. As a lifter, I want Health writing to be opt-in, so that nothing goes
   to Health without my say-so.
3. As a lifter, I want a single toggle in Settings to turn Health writing
   on and off, so that I control it in one obvious place.
4. As a lifter turning the toggle on, I want the system Health permission
   sheet to appear immediately, so that the choice is made there and then.
5. As a lifter, I want each completed Workout written exactly once, when
   the workout ends, so that Health does not fill with duplicates.
6. As a lifter, I want the written workout to carry its real start time,
   end time, and duration, so that it sits correctly on my Health
   timeline.
7. As a lifter, I want a rough active-energy figure attached, so that the
   workout contributes something sensible to my day's totals, while
   understanding it is an estimate, not a measurement.
8. As a lifter who denies Health permission or later revokes it, I want
   the Settings toggle to reflect that state and point me to iOS
   Settings, so that I am not left wondering why nothing is syncing.
9. As a lifter on a device with no HealthKit (or with it restricted), I
   want the Health section to say so plainly and not offer a toggle that
   cannot work.
10. As a lifter, I want turning the toggle off to stop all future writes
    immediately, without touching workouts already in Health.
11. As a lifter, I want workouts I logged before turning the toggle on to
    stay out of Health (only workouts completed while it is on are
    written), so that enabling it is not a surprise bulk upload.
12. As a lifter who edits a past workout, I accept that the Health entry
    is not rewritten, because the Health figure was always a rough
    write-once snapshot.
13. As a lifter, I want the app to keep working normally if a Health write
    fails, so that a Health problem never blocks logging or ending a
    workout.

### Export

14. As a lifter, I want to export my full training history to a file, so
    that I have a backup even without cloud sync.
15. As a lifter, I want to trigger the export from Settings with one
    action, so that it is easy to find.
16. As a lifter, I want to choose between a JSON file and a CSV file, so
    that I can pick a lossless archive or a spreadsheet-friendly table.
17. As a lifter, I want the JSON export to contain every field of every
    Workout, Entry, and Set, so that it is a true archive I could restore
    from later.
18. As a lifter, I want the CSV export to have one row per Set with the
    Workout, Exercise, and Set details flattened onto it, so that I can
    open it in a spreadsheet and filter or chart it.
19. As a lifter, I want exported loads stated in kilograms with the unit
    named in the file, so that there is no ambiguity about what a number
    means regardless of my display setting.
20. As a lifter, I want the file handed to the standard iOS share sheet,
    so that I can save it to Files, AirDrop it, or send it anywhere.
21. As a lifter, I want the file named with today's date, so that I can
    tell successive backups apart.
22. As a lifter, I want the export to include only completed workouts, so
    that a half-finished session in progress is not in my backup.
23. As a lifter with no completed workouts yet, I want the export action
    disabled with a short explanation, so that I am not handed an empty
    file.
24. As a lifter with a large history, I want the export to complete
    without freezing the app, so that a few hundred workouts is not a
    problem.
25. As a lifter, I want the export to work with no network connection, so
    that a backup never depends on signal.

### Anonymous telemetry

26. As a user, I want anonymous usage analytics with no audio and no
    content of my workouts, so that the app can improve without exposing
    my data.
27. As a user, I want analytics to be off unless I turn it on, so that the
    default is the private one.
28. As a user, I want the Settings toggle to state plainly what is sent
    and what is never sent, so that I can make an informed choice.
29. As a user who opts in, I accept the app reporting: a workout started,
    a workout completed (with counts and a coarse duration bucket), a set
    logged, a parse failure, a correction made, and which features I use.
30. As a user, I want it to be structurally impossible for a load, an
    exercise name, a transcript, or any freeform text to be included in an
    analytics event, so that "no content" is a guarantee, not a promise.
31. As a user who turns analytics off, I want reporting to stop
    immediately, so that the switch is real.
32. As a user, I want analytics to never block or slow the logging loop,
    so that opting in costs me nothing in use.
33. As a user, I want no analytics surface to browse in the app — no
    dashboards, no streaks — because analytics is for improving the app,
    not a feature I interact with.

### Failed-utterance review

34. As a lifter, I want the option to submit only the transcript text of
    utterances the parser failed on, so that I can help fix recognition
    on my own terms.
35. As a lifter, I want failed-utterance collection to be a separate
    opt-in from analytics, so that the two choices are independent.
36. As a lifter who opts in, I want the transcript text of each failed
    parse queued locally, with no audio and nothing about the workout it
    happened in, so that only the phrase itself is kept.
37. As a lifter, I want to see the queued phrases in Settings and pick,
    per phrase, whether to submit or discard it, so that I review before
    anything is sent.
38. As a lifter, I want nothing submitted automatically — a phrase leaves
    my phone only when I tap submit for it, so that I stay in control.
39. As a lifter who opts out, I want the queue to stop growing and want to
    be able to clear what is already in it, so that opting out is
    complete.
40. As a lifter, I want a submitted or discarded phrase removed from the
    queue, so that the list reflects only what still needs my attention.

### Settings surface

41. As a lifter, I want an "Apple Health" section in Settings with the
    sync toggle and its status, so that it sits with the other
    preferences.
42. As a lifter, I want an "Export" row in Settings that starts the
    export, so that backup is a first-class action, not buried.
43. As a lifter, I want a "Privacy" section grouping the analytics toggle,
    the failed-utterance toggle, and — when there are queued phrases — a
    "Review N phrases" row, so that everything about what leaves my phone
    is in one place.
44. As a lifter, I want all of these to look like the rest of Settings —
    plain grouped rows — so that the screen stays calm and scannable.
45. As a lifter, I want each toggle's current state to survive relaunching
    the app, so that I set it once.

### Reliability & privacy

46. As a lifter, I want every one of these features to fail quietly and
    locally — a Health error, an upload failure, a full disk — without
    ever interrupting a workout.
47. As a lifter, I want the core logging loop to keep working fully
    offline and on-device, exactly as before, because none of this
    subsystem changes that.
48. As a lifter, I want the three opt-in flags independent of each other,
    so that enabling one never implies another.

## Implementation Decisions

### Scope: one spec, three slices

The three capabilities are independent and share only the `SettingsStore`
extension and the Settings screen. They are specified together (one
document) but built, tested, and merged as three vertical slices, each
landing its own package tests green before merge, matching the subsystem
cadence used for D and E:

- **F1 — Export.** No new framework, no authorization, no trigger wiring.
  Smallest and lowest-risk; done first.
- **F2 — Apple Health sync.** One new system framework (HealthKit), an
  authorization flow, and a write-on-workout-end trigger.
- **F3 — Telemetry and failed-utterance review.** The anonymous event
  sink and the local review queue.

### F1 — Export

- **Two formats.** JSON is a lossless archive: the Core value types
  (`Workout`, `Entry`, `LoggedSet`, and every axis enum, plus `MassUnit`)
  are already `Codable`, so the JSON document is a thin envelope —
  `{ schemaVersion, exportedAt, workouts: [Workout] }` — encoded with a
  stable key strategy and ISO-8601 dates. CSV is a flat table: **one row
  per Set**, with the owning Workout's and Entry's identifying fields
  repeated on each row (workout start/end, exercise name, then the Set's
  four axes, load in kilograms, reps, duration seconds, distance metres,
  superset run id, note).
- **Loads in kilograms only**, per ADR-0002 (storage is canonical
  kilograms). The CSV carries a `loadUnit` column whose value is always
  `kg`; it does not convert to the lifter's display unit, to keep exported
  numbers unambiguous and rounding-free. JSON carries `loadKilograms` as
  stored.
- **Scope is the entire completed history** — every Workout with an
  `endedAt`. A workout in progress is excluded. This matches
  `WorkoutHistoryModel.rows`, which already filters `isEnded`.
- **The builder is a pure function** in the App package: given
  `[Workout]` and a format, it returns an export document value carrying a
  suggested filename (`trackit-YYYY-MM-DD.<ext>`), a content type, and the
  encoded `Data`. It performs no I/O and touches no system API.
- **Delivery is `App/`-only plumbing.** A SwiftUI view takes the export
  document and presents `UIActivityViewController`. There is no port for
  the share sheet — it is untested plumbing on the far side of the pure
  builder, like the existing `System*` adapters.
- **Empty history** disables the export row with an explanatory footer,
  consistent with how "Delete All Workout Data" behaves while a workout is
  open.
- **Format choice** is a small action presented when the lifter taps
  Export (JSON / CSV), not a persisted preference.

### F2 — Apple Health sync

- **A new port** abstracts HealthKit: it exposes whether HealthKit is
  available on this device at all, the current authorization state
  flattened to the few cases the UI needs, a method to request
  authorization, and a method to write one completed Workout. Writing is
  non-throwing and records the last write error, mirroring
  `WorkoutHistoryStore` / `SwiftDataWorkoutStore`.
- **What is written: exactly one workout per completed Workout** — a
  traditional strength-training workout with `startDate = startedAt`,
  `endDate = endedAt`, and a **rough active-energy estimate**. No per-Set
  samples, no heart rate, no route. The energy figure comes from a **pure
  helper** — `estimatedActiveEnergyKilocalories(for: Workout)` — using a
  deliberately simple heuristic (a resistance-training MET constant over
  the workout's duration), documented as an estimate and verified against
  a hand-worked example.
- **One-way.** Nothing is ever read from HealthKit. No bodyweight import,
  no reading external workouts. (Two-way HealthKit is explicitly out of
  scope, per the v1 spec.)
- **Opt-in.** A new boolean in `SettingsStore`, default `false`. Turning
  it on triggers the authorization request. If authorization is denied or
  HealthKit is unavailable, the Settings section reflects that and offers
  the "Open iOS Settings" affordance already used for speech recovery.
- **Trigger: the workout-end transition.** `WorkoutSessionModel` already
  detects, inside `apply`, the transition from a non-ended to an ended
  workout (it re-derives the personal-record gate there). A new injected
  closure — `onWorkoutEnded: (Workout) -> Void`, defaulting to a no-op —
  is called with the just-completed Workout at that point. The
  composition root wires it to a new `@Observable @MainActor` sync model,
  which no-ops unless the flag is on and authorization is granted. This
  matches how the model already takes injected closures (`history`, and
  the `StaleWorkoutRecovery` callbacks).
- **Write-once, no re-sync.** Editing a past Workout does not rewrite its
  Health entry. The Health figure is a rough write-once snapshot; a later
  divergence is accepted.
- **In-session duplicate guard.** The sync model remembers which Workouts
  (by `startedAt`) it has written this app session and will not write the
  same one twice, covering resume / double-end edge cases. A
  cross-launch persistent dedupe is out of scope — the worst case is a
  rare duplicate Health entry the lifter can delete.
- **The `System` implementation** wrapping `HKHealthStore` lives in `App/`
  and is files-only (not compiled here). An in-memory fake that records
  written workouts drives the model tests.

### F3 — Telemetry

- **A telemetry sink port** with a single method: record an event. The
  event type is a **closed enum** with a fixed set of cases —
  workout started; workout completed (carrying only a total set count, a
  working-set count, and a coarse duration bucket); set logged; parse
  failed; correction made; feature used (carrying a small `Feature`
  enum — export, health toggle, settings opened, template saved, and
  similar). **No case carries a load, an exercise name, a transcript, or
  any free-form string.** The type system is the guarantee behind "no
  content".
- **A recorder facade** the models call. It holds the opt-in flag
  (a new `SettingsStore` boolean, default `false`) and drops every event
  when the flag is off.
- **Emitters.** `WorkoutSessionModel` emits the workout-lifecycle,
  set-logged, parse-failed, and correction events; the Settings model and
  views emit feature-used events. All go through the recorder, so the flag
  is checked in one place.
- **The `System` implementation** is a local persistent queue with
  batched upload when a network is available — untested plumbing in
  `App/`. The choice of analytics backend and transport is an
  implementation detail, not specified here. A capturing fake drives the
  tests.
- **No user-facing analytics surface.** No dashboard, no stats screen, no
  streaks — consistent with DESIGN.md's "no gamification chrome" rule.
  The only UI is the opt-in toggle.

### F3 — Failed-utterance review

- **A separate port** from telemetry: capture a transcript string; expose
  the pending items (each an id, the transcript text, and a capture
  timestamp); submit a set of items; discard a set of items.
- **Only transcript text is stored** — never audio, never the full
  hypotheses list, never anything about the Workout the failure happened
  in.
- **Opt-in.** Its own `SettingsStore` boolean, default `false`,
  independent of the analytics flag. When off, capture is a no-op and the
  lifter can still clear whatever is already queued.
- **Capture point.** `WorkoutSessionModel` captures when a low-confidence
  parse result goes unresolved (the same path that raises the
  "not logged" notice), guarded by the flag.
- **Review UI.** A Settings row — shown only when items are pending —
  opens a list of the queued transcripts. The lifter submits or discards
  per item. Nothing is submitted without an explicit tap. Submitted and
  discarded items leave the queue.
- **The `System` implementation** persists the queue and uploads
  submitted text; a fake captures both.

### `SettingsStore` extension

`SettingsStore` gains three boolean members, all defaulting to `false`:
Health sync enabled, anonymous analytics enabled, failed-utterance
collection enabled. This mirrors how subsystem E added
`hasCompletedOnboarding` to the same port. The `UserDefaults`-backed
implementation and the in-memory fake both grow the three keys.

### Settings surface

New stock grouped `Form` sections, no new visual language:

- **Apple Health** — a toggle "Write workouts to Apple Health"; when
  authorization is denied or HealthKit is unavailable, a status line and
  a conditional "Open iOS Settings" button (the speech-recovery pattern).
- **Export** — a row "Export Training History" that presents the
  JSON / CSV choice then the share sheet; disabled with a footer when
  there are no completed workouts.
- **Privacy** — a "Share anonymous analytics" toggle with a one-line
  description naming what is and is not sent; a "Help improve
  recognition" toggle for failed-utterance collection; and, only when
  items are queued, a "Review N phrases" row into the review list.

### `DESIGN.md`

Add three component entries after the existing Settings-area entries:
**Apple Health section**, **Export**, **Privacy & recognition review** —
each noting it is a stock `Form` section with no customization, and that
telemetry has no browsable surface.

### New units introduced

- Export: a pure history-export builder and an export-document value type
  (App package).
- Apple Health: a HealthKit port, its availability / authorization status
  enum, an `@Observable @MainActor` sync model, and a pure active-energy
  estimate helper (App package); a `System` HealthKit adapter (`App/`).
- Telemetry: a sink port, a closed telemetry-event enum with its `Feature`
  enum, and a recorder facade (App package); a `System` sink adapter
  (`App/`).
- Failed-utterance review: a review port and a pending-utterance value
  type (App package); a `System` adapter (`App/`).
- `SettingsStore` gains three flags; `SettingsModel` gains the toggles and
  the export action; `WorkoutSessionModel` gains an injected
  `onWorkoutEnded` closure and the telemetry / failed-utterance hooks.
- `App/`: new Settings sections, the share-sheet presentation, and the
  three `System` adapters.

## Testing Decisions

### What a good test looks like here

A test drives a public seam with a fake standing in for the system side
and asserts observable behaviour — an event recorded, a workout written,
a document's contents — never a private method or an implementation
detail. The `System` adapters carry no branching logic and are not
compiled in this environment, so they are not unit-tested; their
behaviour is covered through the fakes at the model seams. Prior art: the
subsystem E model tests over the `SettingsStore` / `SpeechAuthorization`
fakes, and the projection tests (`HUDProjection`,
`WorkoutSummaryProjection`, `ExerciseProgressProjection`).

### Seams and coverage

- **Export builder (pure).** JSON decodes back to a `[Workout]` equal to
  the input (lossless round-trip). CSV has exactly one row per Set across
  a multi-workout, multi-entry fixture, with the expected columns and
  kilogram loads. Empty history produces a valid document (empty
  `workouts`), and the Settings row is disabled in that state. The
  suggested filename carries the date and the right extension.
- **Health sync model.** Opted out: a workout-end does nothing. Opted in
  and authorized: exactly one workout is written, with `startDate` /
  `endDate` from the Workout and a positive rough energy value. The same
  end firing twice in a session writes once. Authorization denied or
  HealthKit unavailable: the status the UI reads reflects it and no write
  happens. Turning the flag off stops further writes. The energy helper is
  checked against a hand-worked example. Prior art: `SettingsModel` over
  the speech-auth fake.
- **Telemetry recorder.** Opted out: the sink receives nothing. Opted in:
  each domain trigger maps to the expected event case; enumerating the
  event enum confirms no case exposes a load, a name, or a string beyond
  the fixed `Feature` enum. Turning the flag off stops delivery. Prior
  art: history-model tests with a capturing fake store.
- **Failed-utterance review.** Opted out: capture is a no-op; a
  pre-existing queue can still be cleared. Opted in: an unresolved
  low-confidence utterance enqueues exactly its transcript string;
  `submit` and `discard` remove the named items and nothing else; no item
  leaves the queue without an explicit call.
- **`SettingsModel` integration.** The three flags round-trip through the
  `SettingsStore` fake. Toggling Health on calls the port's
  authorization request. The export action returns a document built from
  the current history.
- **`WorkoutSessionModel`.** The injected `onWorkoutEnded` closure fires
  once, with the completed Workout, on the end transition, and does not
  fire on a mid-workout edit or on resume. The telemetry and
  failed-utterance hooks fire under their trigger conditions and stay
  silent when their flags are off. Prior art: the existing session-model
  suite and its scripted fakes.

### Not unit-tested

- The `System` HealthKit, telemetry, and failed-utterance adapters, the
  share-sheet presentation, and the network upload — thin wrappers with
  no branching, not compiled in this environment.
- The `App/` views — consistency-checked by read-through against the
  package API, as in subsystems D and E.

### Process

`swift test` in both `Packages/WorkoutLoggerCore` and
`Packages/WorkoutLoggerApp` on every slice. Strict TDD, red → green
vertical slices. `App/` is files-only / consistency-checked (no Xcode /
`xcodebuild` in this environment).

## Out of Scope

- **Two-way HealthKit** — reading bodyweight, importing external
  workouts, or reading anything at all from Health (v1 spec, explicitly).
- **CloudKit / cross-device sync.** v1 is local storage plus this manual
  file export (v1 spec — deferred to v1.1).
- **Re-syncing an edited past Workout to Health**, and any cross-launch
  persistent HealthKit deduplication.
- **Per-Set HealthKit samples, heart rate, workout routes**, or any
  Move / Exercise ring contribution beyond the single workout entry and
  its rough energy figure.
- **A user-facing stats, insights, or history-analytics surface** —
  dashboards, streaks, totals screens. Telemetry is upload-only plus its
  toggle.
- **Import** — reading a previously exported file back into the app.
- **Scheduled or automatic export / backup.** Export is a manual share
  action.
- **The analytics backend and transport.** The `System` sink's networking
  is an implementation detail, not specified here.
- **Localisation of exported CSV headers or number formatting** beyond the
  app's existing English multi-locale scope.
- **Set volume / per-muscle-group stimulus metrics** (a separate v1.1
  concern, per the v1 spec).

## Further Notes

- **Build order** F1 (Export) → F2 (Apple Health) → F3 (Telemetry +
  review), each a slice that merges only once its own package tests are
  green, matching the D and E cadence.
- **Privacy stance.** All three opt-in flags default to `false`. The
  closed telemetry-event enum is the structural guarantee against content
  leakage — there is no code path by which a load, name, or transcript can
  enter an analytics event. The failed-utterance queue never auto-sends;
  a phrase leaves the device only on a per-item tap.
- **The core loop is untouched.** Nothing here adds a network dependency
  to logging, changes on-device processing, or alters the press-to-talk
  path. `PRODUCT.md`'s permanent offline / on-device commitment holds.
- **No `docs/agents/issue-tracker.md`** in this repo, so this spec is a
  file (like subsystem E's), not a tracker issue, and the
  `ready-for-agent` triage label cannot be applied. Run
  `/setup-matt-pocock-skills` if tracker integration is wanted later.
- **README roadmap.** Tick "HealthKit sync, export, telemetry" when this
  subsystem lands. The "Onboarding & settings" box is already stale
  (subsystem E merged via PR #3) and should be ticked in the same edit.
- **Possible ADR.** If the "write-once on workout end, no re-sync, rough
  energy estimate" decision for HealthKit proves surprising to a future
  reader, capture it as an ADR under
  `Packages/WorkoutLoggerCore/docs/adr/` at build time. Flagged, not
  required now.
