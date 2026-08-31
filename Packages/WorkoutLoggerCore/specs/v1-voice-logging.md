# Spec: Voice-First Workout Logging (v1)

_Derived from the `/grill-me` design session. Vocabulary follows `/CONTEXT.md`;
the Set data-model rationale is recorded in
`docs/adr/0001-set-modelled-as-orthogonal-axes.md`. Greenfield iOS app — no
existing code or seams._

---

## Problem Statement

Serious lifters log every working set — load, reps, and often warmups, bodyweight
assistance, timed holds, supersets and dropsets. In a tap-based app this means
30–40 manual entries per workout: unlock the phone, find the exercise in a list,
tap through load and reps, repeat between every set — frequently with chalky or
sweaty hands, while trying to actually rest.

The result: logging pulls focus out of the workout, feels like a chore, and many
lifters either reconstruct the workout from memory afterwards (losing accuracy on
the exact sets they hit) or stop logging altogether — which defeats the point of
running a structured strength or hypertrophy program.

## Solution

An iPhone app where the user speaks each set as they finish it. Press a
push-to-talk button, say the exercise once ("bench press"), then say each set
("225 for 5"). The set is logged immediately, confirmed by a short spoken
readback plus a distinct haptic, with no need to look at the screen.

It works fully offline in a loud gym, understands the vocabulary of structured
barbell/dumbbell training including warmups, bodyweight and assisted work, timed
and distance efforts, supersets and dropsets, and lets the user correct mistakes
by simply repeating the set or saying "undo". After the workout the user reviews
a clean, editable record and sees per-exercise progress over time, with a
celebratory moment when they hit a personal record.

The voice loop is the entire product, not a feature bolted onto a tap-based
logger.

---

## User Stories

### Onboarding and permissions

1. As a new user, I want the app to explain why it needs microphone and speech
   recognition access before it asks, so that I trust granting it.
2. As a new user, I want a guided ~60-second practice workout on first launch, so
   that I complete the full press → speak → confirm loop once before it matters.
3. As a new user, I want the practice workout to tell me exactly what phrases to
   say, so that I learn the supported grammar by doing rather than reading.
4. As a new user, I want to see the readback and the logged set appear during the
   practice, so that I understand what "it worked" looks like.
5. As a user, I want a persistent phrasebook of everything I can say, reachable
   any time, so that I can check phrasing when I forget.
6. As a user, I want to open the phrasebook by saying "help", so that I do not
   have to stop and tap during a set.
7. As a user, I want the app to tell me it works offline, so that I do not worry
   about gym signal.
8. As a privacy-conscious user, I want an in-app screen that states speech is
   processed on-device and data is stored locally, so that I understand what does
   and does not leave my phone.

### Starting and structuring a workout

9. As a lifter, I want to start a workout by saying "start workout" or tapping a
   button, so that sets have somewhere to attach.
10. As a lifter following a template, I want to start a saved template, so that
    the workout begins with my planned entries already loaded.
11. As a lifter, I want every set written to storage the moment I say it, so that
    a phone call, app switch, or crash never loses logged work.
12. As a lifter who forgot to end yesterday's workout, I want the app to detect
    the stale active workout on next launch and offer to resume or close it, so
    that I do not get a broken multi-day workout.
13. As a lifter, I want to end a workout by saying "end workout" or tapping a
    button, so that the workout closes cleanly and totals are finalised.
14. As a lifter who trains twice in a day, I want each workout recorded
    separately, so that my history is accurate.

### Logging sets by voice — core

15. As a lifter, I want to announce an exercise once ("incline dumbbell press")
    and then log multiple sets without repeating its name, so that logging is
    fast.
16. As a lifter, I want to say "225 for 5" and have it logged against the current
    exercise, so that the common case takes one short phrase.
17. As a lifter, I want to also say the exercise inline ("bench 225 for 5") when I
    prefer, so that the grammar matches how I naturally talk.
18. As a lifter, I want the app to interpret numbers in the load and reps slots as
    numbers even when speech is ambiguous, so that "one eighty five" and "185"
    both work.
19. As a lifter, I want a short spoken readback after each set, so that I know
    what was logged without looking.
20. As a lifter, I want the readback to be terse when the app is confident and
    fuller when it is unsure or the exercise is new, so that confirmation is fast
    when things are going well and careful when they might be wrong.
21. As a lifter, I want a distinct "logged" haptic on every successful set, so
    that I get confirmation even with readback volume down.
22. As a lifter, I want to turn readback down to an earcon in settings, so that I
    am not hearing full sentences 30 times a workout.

### Logging sets by voice — the four axes

23. As a lifter, I want to mark a set as a warmup ("warmup 135 for 10"), so that
    it does not count toward my volume, personal records, or estimated 1RM.
24. As a lifter doing bodyweight work, I want to log reps with no load
    ("pull-ups 12"), so that calisthenics sets are recorded properly.
25. As a lifter doing weighted calisthenics, I want to log added load ("plus 25
    for 8"), so that my progression on those movements is tracked.
26. As a lifter using an assisted machine, I want to log the assistance amount
    ("assisted 8, minus 40"), so that the set reflects reduced resistance.
27. As a lifter doing planks or carries, I want to log a duration effort ("plank
    for 60 seconds"), so that holds are captured with a time rather than reps.
28. As a lifter doing a loaded carry, I want to log a distance effort ("farmer
    carry, 40 metres"), so that distance work is recorded.
29. As a lifter doing a superset, I want consecutive sets of two or more exercises
    grouped as a superset, so that my record shows how I actually trained.
30. As a lifter doing a dropset, I want consecutive descending-load sets of one
    exercise grouped as a dropset, so that the intensity technique is visible in
    history.

### Switching exercises and the tap fallback

31. As a lifter, I want to announce a new exercise to move on ("now squats"), so
    that subsequent sets attach to it.
32. As a lifter whose exercise name was not recognised, I want the app to prompt
    me to pick it from a list, so that I am never stuck.
33. As a lifter, I want to tap an exercise from today's template or the library
    instead of saying it, so that I have a reliable option when voice fails.
34. As a lifter, I want the current exercise clearly shown on screen, so that a
    glance tells me what my next set will be logged against.

### Correcting mistakes

35. As a lifter, I want to fix a misheard set by just pressing and saying it
    again, so that correction costs one action.
36. As a lifter, I want to say "undo" to remove the last thing I logged, so that a
    set that should not exist is easy to drop.
37. As a lifter, I want to fix any set on the post-workout summary — its load,
    reps, exercise, warmup role, or grouping — so that anything voice got wrong is
    cleaned up later.
38. As a lifter, I want the swipe-up set list during the workout to be editable
    inline, so that I can correct a set mid-workout without ending it.

### The active-workout screen

39. As a lifter, I want a calm, high-contrast screen showing the current exercise,
    my last set in large type, and the rest timer, so that a two-second glance
    from across the gym is enough.
40. As a lifter, I want a large, obvious push-to-talk button, so that I can find
    and press it without concentration.
41. As a lifter, I want to swipe up to see every set logged for the current
    entry, so that I can verify the app is keeping up.
42. As a lifter, I want the screen to stay awake during a workout, so that it does
    not lock between sets.

### Rest timer

43. As a lifter, I want a rest timer to start automatically when I log a set, so
    that I do not have to remember to start it.
44. As a lifter, I want a default rest target that a template can override, so
    that the timer matches how I train that day.
45. As a lifter, I want a haptic and sound when my rest target is reached, so that
    I know it is time to lift without watching the clock.
46. As a lifter, I want to say "start rest" or "skip rest", so that I can control
    the timer hands-free.

### History and progress

47. As a lifter, I want a chronological list of completed workouts, so that I can
    see what I have done.
48. As a lifter, I want to open any completed workout and edit it, so that I can
    fix or annotate old workouts.
49. As a lifter, I want a per-exercise progress screen with load and volume over
    time, so that I can see whether I am progressing.
50. As a lifter, I want my best set and an estimated 1RM trend per exercise, so
    that I can gauge strength changes.
51. As a lifter, I want a "vs last time" comparison when I train an exercise, so
    that I know what to beat.
52. As a lifter, I want the app to detect a personal record and mark it with a
    distinct haptic and a brief celebratory moment, so that progress feels
    rewarding.

### Units, library, templates

53. As a lifter, I want to choose kg or lb, so that entries match my gym.
54. As a lifter, I want to optionally say explicit units ("100 kilos"), so that I
    can override the default when needed.
55. As a lifter, I want a built-in library covering the common barbell and
    dumbbell exercises with sensible aliases ("OHP", "RDL"), so that name
    recognition works out of the box.
56. As a lifter with an unusual movement, I want to create a custom exercise and
    record a spoken alias for it, so that I can voice-log it like any other.
57. As a lifter, I want to build a template in a tap-based editor at home, so that
    setup work happens off the gym floor.
58. As a lifter, I want to save a completed workout as a template, so that a
    workout I liked becomes reusable in one tap.

### Ecosystem, backup, privacy

59. As a lifter, I want completed workouts written to Apple Health as strength
    training, so that they count in my wider fitness picture.
60. As a lifter, I want HealthKit writing to be opt-in, so that nothing goes to
    Health without my say-so.
61. As a lifter, I want to export my full training history to a file, so that I
    have a backup even without cloud sync.
62. As a user, I want anonymous usage analytics with no audio and no content of my
    workouts, so that the app can improve without exposing my data.
63. As a user, I want the option to review and submit only the transcript text of
    utterances the parser failed on, so that I can help fix recognition on my own
    terms.

### Reliability and accessibility

64. As a lifter in a basement gym, I want logging to work with no internet, so
    that dead signal never blocks me.
65. As a lifter, I want speech recognition and parsing to feel near-instant, so
    that logging does not interrupt my rest.
66. As a user who relies on larger text, I want the app to respect Dynamic Type
    everywhere, with the big HUD number scaling within a sensible range, so that
    it stays readable.
67. As a user, I want the app to respect Reduce Motion and provide labels on
    controls, so that it degrades gracefully with assistive technology.

---

## Implementation Decisions

### Platform and stack

- Native iOS, SwiftUI, iOS 17+, iPhone only, portrait only.
- On-device persistence via SwiftData (iOS 17 baseline makes this available).
- No backend service in v1. No accounts.

### Module boundaries (conceptual)

- **Parser.** Pure, synchronous. Input: a transcript plus the current workout
  context (active exercise, previous set for that exercise, unit setting).
  Output: an ordered list of results, each one of: a structured set, an
  announcement, a command, or a low-confidence result carrying the reason and the
  resolver's ranked candidate exercises (may be empty) for the tap-select
  fallback. The command vocabulary is `undo`, `start rest`, `skip rest`, `help`,
  `start workout`, `end workout`, and the grouping markers `superset` /
  `end superset`. Grouping is otherwise driven by keyword: a `dropset <load> for
  <reps>` utterance stamps that one set's grouping axis; the `superset` /
  `end superset` markers bracket a run whose membership the workout engine
  tracks (the parser holds no cross-utterance state). A set's load is emitted
  **as spoken**, tagged with its unit — the default, or an explicit spoken one
  (`kg`, `kilos`, `lb`, `pounds`, …) accepted on any load-bearing form — and the
  parser does no unit conversion. A bare exercise name may carry a leading
  `now` / `next` filler (`now squats`), which the parser strips before resolving.
  A set whose load or rep count exceeds a plausibility ceiling (reps > 100, or a
  spoken load > 1000 in either unit) is treated as a magnitude mis-hear: the
  parser returns a low-confidence result rather than a set nobody performed.
  No I/O, no dependence on the speech framework.
- **STT post-processor.** Input: raw recognition hypotheses from the speech
  framework plus the exercise library and alias table. Output: a single corrected
  transcript, with exercise-name biasing and numeric-slot coercion applied.
  Separable from the live speech capture.
- **Speech capture.** Wraps the on-device speech recogniser and the iOS audio
  session; owns push-to-talk start/stop; emits transcripts. Behind an interface
  so the rest of the app can be driven by a fake transcript source in tests.
  The app-shell realisation of this interface is `TranscriptSource`
  (`beginUtterance` / `endUtterance() async -> [String]`); `SystemSpeechRecognizer`
  wraps `SFSpeechRecognizer` + `AVAudioEngine`, and a `ScriptedTranscriptSource`
  fake drives the session model in `swift test`.
- **Exercise library + resolver.** Curated core list seeded from the Free
  Exercise DB, plus an alias table and user-defined custom exercises (each with
  an optional spoken alias). The resolver maps a spoken name to an Exercise with
  a confidence score; below threshold it returns "unresolved" and the UI prompts
  a tap-select.
- **Workout engine.** Owns workout lifecycle, applies parser results to build the
  workout record, canonicalises each set's load to kilograms as it comes in,
  persists every set on receipt (no in-memory buffer held until "end"), detects a
  stale active workout on launch, runs personal-record detection, drives
  rest-timer state.
  The app-shell resume path is `WorkoutEngine.resume(_:)` (subsystem C): it
  adopts a not-yet-ended `Workout` found in storage at launch, attaching new
  sets to its last entry, restarting the rest timer, and seeding the
  personal-record bar from history plus the resumed workout's own sets without
  re-announcing past records.
- **Readback.** Given a parser result, chooses terse TTS, full TTS, or an earcon.
  A new exercise this workout, or a low-confidence parse result, forces full TTS;
  a command gets an earcon; a user setting can cap everything at earcon only.
  Confidence gating on *confident* results (a shaky `.set` / `.announcement` still
  getting full TTS) is deferred until the parser reports a confidence score on
  those results — today it only reports one on `.lowConfidence`.
- **Haptics.** A fixed vocabulary of distinct patterns: logged, not-caught /
  parse-failure, personal record, rest-target reached.
- **Rest timer.** Count-up from the last logged set. Rest target resolved from
  the active workout's template, else a global default. Completion signalled by
  haptic + sound + local notification (see Further Notes on Live Activity).
- **HealthKit writer.** On workout end, if opted in, writes one traditional
  strength training workout with duration and a rough active-energy estimate.
  One-way only.
- **Telemetry.** Local event queue, batched upload: workout started/completed,
  sets logged, parse-failure counts, feature taps — no audio, no workout content.
  Separately, an opt-in failed-utterance queue stores transcript text only, shown
  to the user for review before any send.
- **Onboarding.** Drives the guided practice workout and hosts the phrasebook.

### Data model

- A **Set** is described by four independent axes (see ADR-0001), not a single
  type enum:
  - **load type** — `external`, `bodyweight`, `added`, `assisted`
  - **effort measure** — `reps`, `duration`, `distance`
  - **role** — `working`, `warmup`
  - **grouping** — `straight`, `superset`, `dropset`
  Its value fields are: load + its unit, reps, duration (seconds), distance
  (metres) — populated according to the effort measure. A set may also carry an
  optional freeform note the lifter adds after the fact (story 48).
- **Superset** and **dropset** are values of the grouping axis over an ordered
  run of sets; a superset spans two or more exercises, a dropset stays on one.
  They are not separate set types. A superset set also carries a run id assigned
  by the workout engine, so two superset runs performed back-to-back (no straight
  set between them) stay distinct in history rather than merging into one block.
- The parser carries a set's load as spoken (value + unit); the workout engine
  canonicalises it to kilograms on the way in. Stored loads are always
  kilograms; display converts back to the user's unit setting. An explicit spoken
  unit ("100 kilos") overrides the default for that set. See ADR-0002.
- Sets with the `warmup` role are excluded from volume, personal-record, and
  estimated-1RM computations.
- **Volume** is Σ (load × reps) across working sets.
- Per-exercise progress also reports Σ working reps per session — the progression
  signal for bodyweight movements (story 25), where Volume is zero.
- A **personal record** is a new best estimated 1RM for an exercise, from any
  working set — one value per exercise.
- An **Entry** is one exercise's ordered list of sets within a workout or
  template.
- A completed **Workout** may carry an optional freeform session note (story 48).
  Post-workout editing (correcting a set, deleting a set, annotating, saving the
  workout as a template) is a set of pure `Workout` transforms; the caller
  persists the result.
- A **Template** is an ordered list of entries, each referencing an Exercise,
  with target set counts and an optional rest target; it holds no loads. Starting
  a template creates a new workout.

### Key contracts and interactions

- Push-to-talk: press starts capture, release (or second press) ends it; the
  captured audio yields one transcript, which flows post-processor → parser →
  workout engine.
- The active exercise persists across utterances until an announcement or a
  tap-select changes it.
- Repeat-to-retry: when a new set for the active exercise closely matches the
  immediately previous utterance's target (same exercise, values within a small
  tolerance) and arrives before any intervening set, it overwrites rather than
  appends. `undo` removes the last appended item outright.
- Confidence gating uses parser-reported confidence plus a "new exercise this
  workout" signal to select readback verbosity.
- A set is only auto-logged against a fuzzily-matched exercise name when the
  resolver's confidence clears a fixed bar; a weaker match yields a low-confidence
  result and nothing is logged, so the user re-speaks or tap-selects rather than
  having a wrong set silently recorded. A bare "`<exercise> <n>`" with an
  implausibly large `<n>` (a dropped "for") is treated the same way.
- Every set is persisted synchronously on receipt; the workout engine never
  relies on an "end workout" event to flush.
- Stale-workout detection: on launch, any workout with no end timestamp and a
  last-set timestamp older than a threshold triggers a resume/close prompt.

### Visual / brand decisions

- Dark theme only in v1. Single accent hue on near-black. A distinctive numeric
  typeface is a design token used for all prominent numbers.
- Haptic patterns are a designed set of 3–4, defined once and reused.
- App ships under a placeholder name.

---

## Testing Decisions

### What makes a good test here

Tests assert on **external behaviour at a seam**, never on internal call order,
private state, or view hierarchy:

- Given a transcript and a workout context, the parser emits the correct list of
  structured sets / announcements / commands.
- Given an ordered sequence of utterances, the workout engine produces the
  correct workout record, personal-record flags, and rest-timer state
  transitions.
- Given raw recognition hypotheses and a library, the post-processor produces the
  expected corrected transcript.

A test that breaks when an internal function is renamed, or that checks how many
times a collaborator was called, is testing the wrong thing.

### Seams (fewest possible, highest possible)

1. **Parser (primary seam).** Pure function `(transcript, context) → [result]`.
   A large table-driven case suite is the backbone of the whole project: all four
   set axes and their combinations, warmup role, added and assist load, duration
   and distance efforts, superset and dropset grouping, announcements, the inline
   exercise form, explicit and implicit units, every command word, and
   deliberately messy / low-confidence inputs with their expected fallbacks.
   Written in Phase 1, before any UI exists.
2. **STT post-processor.** `(rawHypotheses, library) → correctedTranscript`.
   Canned hypothesis lists in, expected corrected transcript out. Covers
   exercise biasing, alias resolution, and numeric-slot coercion.
3. **Workout engine, driven by a fake transcript source.** Feed an ordered list
   of utterances through the real post-processor and parser into the engine
   backed by an in-memory SwiftData store; assert the resulting workout record,
   repeat-to-retry overwrite behaviour, `undo`, personal-record detection,
   rest-timer transitions, and stale-workout recovery. The speech framework is
   mocked only at the "transcript emitted" boundary — nothing lower.

- **App skeleton + voice pipeline (subsystems A+B).** A second SwiftPM package
  `WorkoutLoggerApp` holds the `@Observable WorkoutSessionModel`, a SwiftData
  `WorkoutStore` (one `@Model` per session, `Workout` JSON blob keyed on
  `startedAt`), the pure `readbackPlan` composer, and protocol + fake
  collaborators. All covered by `swift test`. The Xcode app target (`App/`,
  generated from `project.yml`) holds `@main`, the SwiftUI view tree, and the
  `System*` framework wrappers, and is not `swift test`-covered.

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

### Slower / metric tests

- **Audio corpus run.** Recorded clips (self and volunteers, real gym noise)
  covering every axis combination and command, run through the real on-device
  recogniser + real parser in CI. Reported as no-correction rate and
  press-to-confirm latency, tracked against the launch gate (≥ 85%
  no-correction, ≤ 3 s median). Treated as a tracked metric first; promoted to a
  hard CI gate once stable. Built lazily, after the grammar settles.
  - The package-level slice exists now: `score([CorpusEntry], library:)` drives
    canned recogniser n-best hypotheses through the real `postProcess → parse`
    chain and reports the no-correction rate, with the ≥ 85% floor asserted as a
    tracked metric. The recogniser front-end (audio → hypotheses) and the latency
    half wait for the app shell; when they land, the corpus swaps its hand-authored
    hypothesis lists for recogniser output and the same scorer runs.

### UI tests

Minimal. A couple of interaction/snapshot checks for the HUD's glanceable state
and the post-workout edit flow. All meaningful logic lives below the view layer
at the seams above, so UI tests stay thin.

### Prior art

None — greenfield. These three seams and the parser case-suite format are
established here as the patterns for the codebase.

---

## Out of Scope

### Not in v1 (planned for v1.1)

- CloudKit sync across devices (v1 has local storage + manual file export only).
- Earbud-button push-to-talk (earbuds work as the mic; the on-screen button is
  the trigger).
- Background-audio operation and a lock-screen Live Activity (v1 keeps the screen
  awake and assumes the app stays foregrounded).
- Grammar long-tail: "add a plate", "same as last time", "back-off set", and
  similar relative or contextual phrasings.
- Light mode.
- Read-only Apple Watch complication.

### Not planned

- Nutrition / calorie tracking.
- Cardio-first tracking (GPS running/cycling/rowing). Duration and distance
  efforts *inside* a lifting workout are in scope; standalone cardio is not.
- Coaching: auto-regulation, "you should deload" advice, AI form feedback. A
  multi-week **program** with automatic progression is a stated v2, not v1.
- Social features: feed, followers, share cards, leaderboards.
- Android, iPad, web app.
- A general-purpose voice assistant. The app understands set-logging grammar and
  a small fixed command set only.
- Wake-word activation, cloud speech-to-text, and an LLM-based parser (grammar
  only in v1; an LLM fallback is a later consideration).
- Multi-language support beyond English (English multi-locale only: US, UK, AU,
  CA, IN).
- Two-way HealthKit (reading body weight or external workouts).
- **Set volume** / per-muscle-group stimulus metrics (distinct from Volume; a
  v1.1 concern).

---

## Further Notes

- **Builder context.** Solo developer, first real iOS app, nights and weekends,
  no hard deadline. CloudKit sync and the earbud button are the two areas most
  likely to stall a first-time iOS developer for weeks, which is why both are
  deferred to v1.1. The agreed build order is the guardrail against "no deadline"
  becoming "no ship": (1) parser core with its case suite, (2) skeleton loop
  end-to-end, (3) the loop made pleasant (HUD, readback, haptics, corrections,
  workout lifecycle, rest timer), (4) around the loop (templates, progress,
  post-workout edit, onboarding, settings, HealthKit, privacy, telemetry),
  (5) harden and beta. Phase 3 should not begin until Phase 2 has survived a week
  of the developer's own training.
- **"Won't cut anything" tension.** During the design session the developer
  initially resisted cutting scope. The agreed resolution treats CloudKit sync,
  earbud-button PTT, and the grammar long-tail as *sequenced to v1.1*, not
  removed. All four set axes and their combinations, templates, and per-exercise
  progress remain in v1 as requested. Worth reconfirming before build starts.
- **Rest-timer completion signal.** v1 rest-timer completion is haptic + sound +
  local notification. The Live Activity treatment arrives with background-audio
  operation in v1.1.
- **Success gates.** Pre-launch voice-loop gate (must clear before public
  release): ≥ 85% of sets logged with no correction, ≤ 3 s median
  press-to-confirmed-set. Retention: ≥ 40% of onboarded users complete 3 workouts
  in 2 weeks, ≥ 20% still active in week 6. PMF: ≥ 40% of active users would be
  "very disappointed" to lose the app.
- **Business model.** Free, no monetisation in v1; optimise for retention.
  Revisit a one-time purchase or subscription only if v2 adds a program or
  coaching that justifies it.
- **Name.** Deferred. Direction: coined or mechanical, one word, under six
  letters. Codebase ships under a placeholder.
