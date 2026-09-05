# Subsystem E — Onboarding & Settings

> Design spec. Voice-first iOS workout logger (trackit). Follows the
> vocabulary in `Packages/WorkoutLoggerCore/CONTEXT.md` and the product
> principles in `PRODUCT.md`. Builds on subsystems A–D (app shell + voice
> pipeline, live-workout HUD, post-workout history/edit/progress) and the
> HUD accessibility/polish pass, all merged to `main`.

## Problem Statement

A lifter opening trackit for the first time is dropped straight onto the
live HUD with no explanation. The first time they press to talk, iOS
throws up a bare "Trackit Would Like to Access the Microphone" /
speech-recognition system prompt with no surrounding context — and if
they tap "Don't Allow" while confused, the core loop is dead and nothing
in the app tells them why or how to fix it.

Beyond that first run, the app has no preferences surface at all:

- **Loads are shown in kilograms, always.** A lifter who trains in pounds
  sees every set line and every progress number in the wrong unit and has
  no way to change it. (Storage is canonically kilograms per ADR-0002;
  this is purely a display-unit gap.)
- **The Exercise library is a fixed list of six barbell movements**
  hard-coded in the app. A lifter cannot add the movements they actually
  train, rename one to match how they say it, or teach it an Alias. Any
  spoken Exercise outside those six falls to the tap-select disambiguation
  path every single time.
- **There is no way to see or recover speech permission** once the first
  prompt has been answered, and no way to wipe workout data (needed for
  pre-launch testing and for a lifter who wants a clean slate).

## Solution

**First run:** one screen, on the same black canvas as the HUD, that
states the on-device / offline promise in the words the product already
commits to, then a single "Continue" button that triggers the system
permission prompts. Whatever the lifter chooses, they land on the HUD.
The screen never appears again.

**A Settings screen**, reached from a gear in the HUD toolbar next to the
History button, with four things:

1. **Units** — a Kilograms / Pounds picker. Changing it re-renders every
   load in the app immediately, mid-workout included, with no data
   migration (storage stays kilograms).
2. **Speech** — a live status row (Granted / Denied / Not determined) and,
   when access is not granted, an "Open iOS Settings" row that deep-links
   to the app's system settings page.
3. **Exercise Library** — a full editor: add a Custom exercise, rename any
   Exercise, edit its Aliases, delete any Exercise. Edits take effect for
   the next spoken utterance immediately. Deleting an Exercise never
   touches the Completed workouts that already reference it.
4. **Data** — a destructive "Delete All Workout Data" action, disabled
   while an Active workout is open, that erases every Workout but keeps
   the Exercise library and preferences.

## User Stories

### First-run onboarding

1. As a first-time user, I want the app to explain why it needs my
   microphone before iOS asks, so that I understand the request and don't
   deny it out of confusion.
2. As a first-time user, I want that explanation to say the processing
   happens on my device and nothing leaves my phone, so that I trust
   granting the permission.
3. As a first-time user, I want a single obvious "Continue" button, so
   that I'm not hunting for how to proceed.
4. As a first-time user, I want tapping "Continue" to bring up the real
   iOS permission prompt, so that I can grant access in one flow.
5. As a first-time user who grants access, I want to land directly on the
   workout screen, so that I can start logging immediately.
6. As a first-time user who denies access, I want to still land on the app
   (not a dead-end wall), so that I can look around and change my mind
   later.
7. As a returning user, I never want to see the onboarding screen again
   once I've been through it, regardless of what I chose.
8. As a user who force-quits during onboarding before tapping "Continue",
   I want to see the onboarding screen again on next launch, so that I
   still get the priming context.
9. As a user with a device or locale where on-device speech recognition is
   unavailable, I want onboarding to still complete and drop me on the
   app, so that the rest of the app (history, progress, settings) is
   usable.
10. As a user resuming an Active workout that was left open when the app
    was killed, I want onboarding (if somehow still pending) to resolve
    before the resume-or-discard prompt, so that the gates don't stack
    confusingly.

### Reaching settings

11. As a user, I want a settings control on the main workout screen, so
    that I can adjust preferences without leaving the app's home.
12. As a user, I want the settings control to sit next to the history
    control, so that the two "leave the workout screen" affordances are
    together.
13. As a user, I want to open Settings whether or not a workout is in
    progress, so that I can fix a wrong unit the moment I notice it.
14. As a user, I want Settings to be a normal scrolling list of labelled
    controls, so that it behaves like every other iOS settings screen I've
    used.

### Units

15. As a lifter who trains in pounds, I want to switch the app to pounds,
    so that every load I see matches the plates I actually load.
16. As a lifter, I want the unit switch to change every already-logged set
    line and every progress figure right away, so that I'm never reading a
    mix of units.
17. As a lifter, I want switching units mid-workout to be safe, so that I
    can correct it without disturbing the Active workout, the rest timer,
    or my session's personal-record tracking.
18. As a lifter, I want my previously logged sets to keep their real
    values after a unit switch (just displayed converted), so that no
    precision is lost and nothing is rewritten.
19. As a lifter who says an explicit unit in a set ("100 kilos"), I want
    that set to keep the unit I spoke regardless of the default, so that
    the default only fills in when I don't say one.
20. As a lifter, I want my unit choice to persist across app launches, so
    that I set it once.
21. As a lifter, I want the default unit to remain kilograms until I
    change it, so that behaviour is unchanged for anyone who never opens
    Settings.

### Speech permission status & recovery

22. As a user, I want to see whether the app currently has speech/mic
    access, so that I can diagnose why press-to-talk isn't working.
23. As a user whose access is denied, I want a one-tap route to the app's
    page in iOS Settings, so that I can re-enable it without digging
    through system menus.
24. As a user, I want the status to refresh when I return to the app after
    changing it in iOS Settings, so that it reflects reality without a
    relaunch.
25. As a user whose access is granted, I don't want to see the recovery
    row, so that the screen stays uncluttered.
26. As a user on a device where speech recognition is unavailable, I want
    the status to communicate that distinctly from "denied", so that I'm
    not sent to iOS Settings to fix something I can't fix.

### Exercise library

27. As a lifter, I want to see every Exercise the app knows, listed
    alphabetically, so that I can scan for the ones I train.
28. As a lifter, I want to add a Custom exercise by name, so that the app
    can log the movements my program actually uses.
29. As a lifter, I want to give an Exercise one or more Aliases, so that
    the app resolves the words I actually say ("RDL", "romanians") to the
    right Exercise.
30. As a lifter, I want to rename an Exercise, so that its canonical name
    matches how I think of it.
31. As a lifter, I want to edit or remove an Alias later, so that I can
    fix a bad one.
32. As a lifter, I want to delete an Exercise I never use, so that the
    library stays relevant and disambiguation has fewer wrong options.
33. As a lifter, I want a newly added or renamed Exercise to be resolvable
    on my very next spoken set, without restarting the app or the workout,
    so that I can fix the library the moment a set fails to resolve.
34. As a lifter, I want deleting an Exercise to leave my past Completed
    workouts exactly as they were, so that my history is never corrupted
    by a library edit.
35. As a lifter, I want the six starter Exercises present on first launch,
    so that common barbell training works out of the box.
36. As a lifter, I want to be able to delete or rename even the six
    starters after first launch, so that the library is fully mine.
37. As a lifter, I want the app to reject an empty Exercise name or one
    that duplicates an existing name (ignoring case), so that the library
    can't be put in a broken state.
38. As a lifter, I want my library edits to persist across launches, so
    that I only teach the app a movement once.
39. As a lifter, I want the Exercise editor to have a clear Save and
    Cancel, so that I can back out of an edit I didn't mean to make —
    matching the Set editor.
40. As a lifter, I want to add an Exercise via an obvious "+" control and
    delete one via swipe, so that it behaves like a standard iOS list.

### Delete all workout data

41. As a user, I want to erase all my logged Workouts, so that I can start
    from a clean slate.
42. As a user, I want a confirmation step before the erase happens, so
    that a stray tap doesn't destroy my history.
43. As a user, I want the erase to keep my Exercise library and my unit
    preference, so that I don't have to re-teach the app after clearing
    history.
44. As a user, I do not want to be able to trigger the erase while an
    Active workout is open, so that I can't destroy a session I'm in the
    middle of.
45. As a user, I want the screen to tell me why the erase is unavailable
    when a workout is open, so that the disabled control isn't a mystery.
46. As a user, I want history, progress, and this-session personal-record
    baselines to reflect the empty state right after the erase, so that
    the app is consistent without a relaunch.

## Implementation Decisions

### Persistence — two independent buckets

- **Preferences** (default unit, `hasCompletedOnboarding`) persist in
  `UserDefaults`, reached through a new **`SettingsStore`** protocol port
  in the app package with a `UserDefaults`-backed implementation in the
  app's system-adapter layer and an in-memory fake for tests. This
  mirrors the existing port/fake pattern (`WorkoutHistoryStore`,
  `TranscriptSource`).
- **The Exercise library** persists in the **existing SwiftData
  container**, as a new `@Model` record type distinct from the workout
  record type. It is reached through a new **`ExerciseLibraryStore`**
  protocol port with a SwiftData implementation and an in-memory fake,
  mirroring the existing workout store pair.
- The two buckets are deliberately separate so that "Delete All Workout
  Data" can wipe Workouts without touching the library or preferences.

### Exercise library model & seeding

- The Exercise record stores a canonical name and an ordered list of
  Aliases. It maps to and from the Core `Exercise` value type.
- On first launch — detected by an empty Exercise record set — the store
  seeds the six starter Exercises currently hard-coded in the app. After
  seeding, the list is entirely user-owned: any Exercise, including a
  seeded one, can be renamed, re-aliased, or deleted.
- The app's composition root stops constructing the Core `ExerciseLibrary`
  from a hard-coded array and instead builds it from the store's records.
  The starter set survives only as a seed constant.
- Name validation: trimmed non-empty, and not equal (case-insensitive) to
  another Exercise's name. Enforced at the model seam; the editor's Save
  is disabled when invalid.
- Deleting an Exercise removes only the library record. Completed workouts
  embed `Exercise` by value in their entries, so history is inherently
  unaffected; no cascade, no history rewrite.

### Live application of unit and library changes (Approach A)

The Core `WorkoutEngine` remains otherwise frozen; this subsystem adds
two setter methods to it and mirrors them one level up:

- `WorkoutEngine` gains `updateLibrary(_:)` and `updateDefaultUnit(_:)`.
  Its two corresponding stored properties change from constant to
  variable; no existing code path changes behaviour. The engine reads
  both fresh on each utterance it applies, so a value swap between
  utterances is inherently consistent — there is no cached parser state
  keyed to the old values.
- `WorkoutSessionModel` gains the same two methods; each assigns its own
  mirrored property and forwards to the engine. Its existing
  display-unit accessor already reads the property, so the HUD projection
  picks up a unit change on its next render.
- A new **`SettingsModel`** (`@Observable`, main-actor) owns the live
  preference values and the derived `ExerciseLibrary`. It holds a
  reference to the `WorkoutSessionModel`. Every mutation follows one
  direction: **persist → update own observable state → call the model's
  setter**. The model never writes back to `SettingsModel`.
- `SettingsModel` is constructed in the composition root after the stores
  and before the engine/model, so it can supply the initial unit and
  library to their initializers (unchanged initializer shapes — the
  values are simply sourced from the stores now).

### Unit-change safety

- Storage is canonical kilograms (ADR-0002); a default-unit change is
  display-and-future-parsing only. Already-logged sets are not touched.
- Each set already records the unit it was captured in; the default only
  fills in when a spoken set carries no explicit unit. Changing the
  default cannot retroactively reinterpret past sets.
- The setter does not touch Active-workout state, the rest timer, or the
  session's personal-record baselines.

### Onboarding

- A new **`OnboardingModel`** exposes whether onboarding should show
  (`hasCompletedOnboarding` is false) and a `completeOnboarding()` that
  requests speech authorization through a new **`SpeechAuthorization`**
  port, then sets the flag — the flag is set regardless of the
  authorization outcome.
- A new gate in the root view precedes the existing stale-workout gate:
  show onboarding when it is pending; otherwise fall through to the
  existing resume-or-discard gate and the HUD, both unchanged.
- The onboarding screen shares the HUD's black canvas and centered-column
  layout (the family the launch-gate screen already belongs to). Body
  copy is drawn from the on-device / offline framing in `PRODUCT.md`'s
  Brand Commitments. One full-width primary button, styled like the talk
  button; no "skip" or "not now" affordance — "Continue" is the proceed
  action, and the lifter still controls the outcome via the system prompt.
- Denial blocks nothing. The existing speech pipeline already fails a
  press fast with a not-caught haptic and earcon when recognition is
  unavailable; the recovery route lives in Settings.

### Speech permission status & recovery

- A new **`SpeechAuthorization`** port exposes a current status (granted /
  denied / not determined / unavailable-on-device) and a `request()`.
  The real implementation wraps the system speech-authorization status
  and the audio-application record-permission; it carries no logic and is
  not unit-tested. A scriptable fake drives the model tests.
- The Speech section shows the status live, re-reading it when the screen
  appears and when the app returns to the foreground. The "Open iOS
  Settings" row is shown only when status is denied (not for
  unavailable-on-device, which iOS Settings can't fix) and opens the
  app's system settings page.

### Settings surface

- The root view's HUD toolbar gains a second trailing item — a gear —
  beside the existing History item. The leading item (the set-list
  button) is unchanged. Settings pushes onto the same navigation stack.
- Settings is a stock grouped form. Sections: Units, Speech, Exercises
  (a row that pushes the library editor), Data.
- The library editor is a stock list; rows show an Exercise's name and
  Alias count. A "+" toolbar item pushes an empty Exercise editor; a row
  tap pushes it seeded; swipe deletes. The Exercise editor is a stock
  form with a name field and an add/remove Alias list, and a
  Cancel/Save toolbar pair matching the Set editor.
- "Delete All Workout Data" is a destructive-role row, disabled with an
  explanatory footer while an Active workout is open. Tapping it raises a
  confirmation dialog; confirming calls a new `deleteAllWorkouts()` on
  the existing workout store port, then refreshes the history model and
  recomputes the session's personal-record baselines to empty. There is
  no type-to-confirm step.

### New units introduced

- App package: `SettingsModel`, `OnboardingModel`, `SettingsStore`
  (protocol) + in-memory fake, `ExerciseLibraryStore` (protocol) +
  SwiftData implementation + in-memory fake, the Exercise `@Model` record,
  `SpeechAuthorization` (protocol) + scriptable fake.
- App (uncompiled) layer: `UserDefaultsSettingsStore`,
  `SystemSpeechAuthorization`, and the views `OnboardingView`,
  `SettingsView`, `ExerciseLibraryView`, `ExerciseEditView`, plus the
  root-view gate and toolbar edits.
- Core: two additive methods on `WorkoutEngine` and the corresponding
  `let` → `var` changes. No other Core change.
- Existing workout store port: one added method, `deleteAllWorkouts()`.

### `DESIGN.md`

Updated in the same change set: an Onboarding screen entry, a Settings
screen entry (stock form, the section list, the gear as a second
documented HUD toolbar control folded into the logging-controls-only
size exception), and an Exercise Library / Exercise Editor entry beside
the existing Set Editor bullet.

## Testing Decisions

### What a good test looks like here

Tests assert observable behaviour at a public seam, never a private
collaborator or a stored-property name. A unit change is verified by what
the display accessor and a subsequent parse produce, not by reading the
mirrored property. Library seeding is verified by the resolvable
Exercises, not by a record count alone. Expected values come from the
spec or a worked conversion, not from re-running the code's own
arithmetic.

### Seams and coverage

- **`WorkoutEngine` (Core), two new methods.** After `updateDefaultUnit`
  to pounds, a spoken set with no unit word canonicalises from pounds
  (assert the stored kilogram value against a hand-worked conversion).
  After `updateLibrary` adds an Exercise, an utterance that previously
  produced a low-confidence result now resolves to it. Neither call
  alters existing stored sets or the personal-record set. Prior art:
  the existing engine test suite.
- **`WorkoutSessionModel`, two mirror methods.** Each forwards to the
  engine (observed via a resolution change) and, for unit, flips the
  display accessor. A call made while an Active workout is open leaves
  the workout, the rest elapsed value, and the known-best baselines
  unchanged. Prior art: the existing session-model test suite and its
  fakes.
- **`SettingsModel` (primary new seam).** Setting the unit persists
  through the `SettingsStore` fake *and* calls the model's unit setter.
  Adding / renaming / re-aliasing / deleting an Exercise persists through
  the `ExerciseLibraryStore` fake and calls the model's library setter
  with a rebuilt library whose contents reflect the edit. A model
  constructed against an empty library store seeds exactly the six
  starters. `hasCompletedOnboarding` round-trips. `deleteAllWorkoutData()`
  calls the store's delete-all when no Active workout is open and is a
  no-op (or reports refusal) when one is. Duplicate (case-insensitive)
  and empty Exercise names are rejected. Prior art: the history model's
  tests.
- **`OnboardingModel`.** `completeOnboarding()` calls
  `SpeechAuthorization.request()` then sets the flag — including when the
  fake returns denied. `shouldShowOnboarding` is false once the flag is
  set and true before, and true when the store was never written.
- **`SwiftDataExerciseLibraryStore`.** Add / rename / alias-edit / delete
  round-trip through an in-memory model container. A delete leaves
  pre-existing workout records intact. Name-collision rejection.
  First-launch seeding inserts the six. Prior art: the SwiftData workout
  store tests.
- **Workout store `deleteAllWorkouts()`.** Removes every workout record
  from the shared SwiftData container while leaving the colocated
  Exercise records and all `SettingsStore` preference values untouched;
  history reads back empty afterwards.

### Not unit-tested

- `SystemSpeechAuthorization` and `UserDefaultsSettingsStore`'s real
  backing — thin wrappers with no branching logic, not compiled in this
  environment. Their behaviour is covered through the fakes at the model
  seams. The status-to-UI decision ("denied ⇒ show recovery row",
  "unavailable ⇒ don't") is logic and *is* tested via the fake.
- The `App/` views — consistency-checked by read-through against the
  package API (every binding, branch, and string maps to a tested model
  member; no logic in a view body), the same bar the HUD views meet.

### Process

Strict TDD, red → green, vertical slices. `swift test` in both
`Packages/WorkoutLoggerCore` and `Packages/WorkoutLoggerApp` each cycle.
No Xcode / `xcodebuild` in this environment.

## Out of Scope

- **Subsystem F**: HealthKit sync, workout export, telemetry. The Speech
  and Data sections are built; no HealthKit or export section is stubbed.
- Any onboarding content beyond the single priming screen — no
  multi-screen tutorial, carousel, page indicators, feature tour, or
  sample workout.
- Editing the Exercise library from the mid-workout tap-select sheet.
  That disambiguation flow is unchanged; "add this as a new Exercise from
  here" is not part of this subsystem.
- Programs, notifications, rest-target configuration, and any
  appearance / theme setting (the app is intentionally forced-dark).
- Import of an Exercise library, bulk Alias editing, per-Exercise default
  rest or default load type, Exercise categories or muscle groups.
- Undo for "Delete All Workout Data" and any export-before-delete offer.
- A per-set unit override in Settings (a spoken explicit unit already
  wins per ADR-0002; nothing changes there).
- Migrating already-stored loads on a unit change (storage is canonical
  kilograms and stays so).
- Localisation of the new copy beyond the existing app's conventions.
- Any accessibility mandate beyond what the stock SwiftUI controls
  provide; `PRODUCT.md` leaves this undecided and this spec does not
  change that.

## Further Notes

- The onboarding flag is a one-way latch keyed only on "the user has been
  shown the priming screen and tapped Continue". It is not re-derived
  from live authorization status, so a later denial in iOS Settings does
  not re-trigger onboarding — recovery is the Settings Speech section by
  design.
- Because `SettingsModel` supplies the initial unit and library to the
  engine and session model at construction, first launch seeds the
  library *before* those are built. The composition root ordering is:
  stores → `SettingsModel` (seeds if needed, reads unit) → engine +
  session model → `OnboardingModel` → root view.
- A unit change mid-workout is safe but will visibly re-render the
  current set line; this is intended (the lifter asked for it) and needs
  no confirmation.
- "Unavailable on device" for speech is a real fourth status, distinct
  from "denied": some locales / devices return no recogniser. The
  Settings row must not send those users to iOS Settings, where there is
  nothing to toggle.
- The gear toolbar item is the second app-authored control on the HUD
  (after PR #2's set-list button). `DESIGN.md`'s "size any new
  mid-workout logging control like the talk button" rule already carries
  a stated exception for non-primary toolbar affordances; the gear falls
  under it.
- If a future subsystem needs a richer first run, it gets its own spec;
  this one deliberately ships the smallest thing that removes the
  cold-open permission prompt.
