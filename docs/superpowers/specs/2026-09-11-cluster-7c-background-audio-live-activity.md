# Cluster 7c — Background-audio operation + lock-screen Live Activity

**Prerequisite reading:** `2026-09-11-v1.1-remaining-onboarding.md`.
**Parent:** `2026-09-06-v1.1-deferred-work-design.md` § "Cluster 7" → "Background-audio operation + lock-screen Live Activity".
**Master spec framing:** *"v1 keeps the screen awake and assumes the app stays
foregrounded. The rest-timer completion signal is haptic + sound + local
notification in v1; the Live Activity treatment arrives with this."* Further Notes
also: *"Live Activity arrives with background-audio."*

Two coupled deliverables: (1) the app keeps working (listening + speaking + rest
timer) with the screen locked or the app backgrounded; (2) a lock-screen /
Dynamic Island Live Activity shows the current workout + rest countdown.

Impl-ready brief; design questions open.

---

## What exists today

- **Screen stays awake, app assumed foreground.** v1 sets keep-awake during a
  workout (story 42) and does no background-mode work.
- **Rest timer** lives in Core (`WorkoutEngine` rest sub-behaviour;
  `rest.arm(...)`, `rest.reset()`, per-exercise targets via
  `WorkoutTemplate.restTargetsByExercise` — see cluster 2). The App layer ticks
  it: `WorkoutSessionModel.tick()` is called on a timer and drives rest state
  into the HUD projection.
- **Rest-completion signal** in v1: **correction (2026-09-15) — checked, and
  it's haptic only.** `WorkoutSessionModel.tick()` fires
  `haptics.play(.restReached)` once when `engine.isRestTargetReached` flips
  true (`Session/WorkoutSessionModel.swift:286-288`); `SystemHaptics` maps
  that to `UINotificationFeedbackGenerator.notificationOccurred(.warning)`
  (`App/System/SystemHaptics.swift:20`), which plays iOS's built-in system
  sound as a side effect of the generator — there is no separate sound
  asset. **No `UNUserNotificationCenter` call exists anywhere in the repo**
  (grepped `App/`, both packages) — the original text above ("a local
  notification... if present") was speculative and wrong. This matters:
  `tick()` only runs while the app is foreground and polling, so today's
  entire rest-completion signal is silent the moment the app backgrounds —
  Deliverable 1 must add a real local notification, not just relocate an
  existing one (see OPEN QUESTION 5's resolution).
- **No `ActivityKit`**, no widget extension target, no `UIBackgroundModes` in
  `App/Info.plist` (confirm — it currently has the usage-description keys and
  nothing background-related).
- `project.yml` defines exactly two targets: `Trackit` (app) and `TrackitTests`
  (UI tests). No extension target.

---

## Deliverable 1 — background operation

### Seam

The recogniser and readback are already isolated behind `TranscriptSource` /
`ReadbackVoice` protocols with `System*` implementations. Making them work
backgrounded is almost entirely an **`App/`-side audio-session + capabilities**
concern, not a package concern:

- Add `audio` to `UIBackgroundModes` in `App/Info.plist`.
- `App/System/SystemSpeechRecognizer.swift` — audio session must be
  `.playAndRecord` (or `.record`) with `.mixWithOthers`/`.duckOthers` as decided,
  and must stay active across backgrounding. Handle `AVAudioSession`
  interruption + route-change notifications (call, other app, unplugged
  headset).
- The rest timer must keep counting while backgrounded. Options: keep a
  background audio session alive (fragile, battery cost, App Review scrutiny), or
  compute rest remaining from wall-clock timestamps (`restStartedAt` + target)
  so no live ticking is needed — the Live Activity and a scheduled local
  notification carry the UX, and `tick()` just reconciles on foreground. **The
  timestamp approach is strongly preferred** and may need a tiny package
  affordance (expose `restStartedAt` / `restDeadline` if not already public).

### Acceptance tests

Package-level:

1. Rest-remaining is a pure function of `restStartedAt`, the target, and "now" —
   assert it against an injected clock with no ticking.
2. Foregrounding after a gap reconciles rest state correctly (already partly
   covered by cluster 2's resume tests — extend).

Device-only:

3. Lock the screen mid-workout; press the earbud button (needs 7b) or keep the
   app running with screen off; an utterance still logs.
4. Readback still speaks with the screen locked.
5. Rest completion still fires its signal with the app backgrounded.
6. A phone call interrupts and, on return, the recogniser recovers.
7. Battery cost over a 60-minute backgrounded session is acceptable
   (measure with Instruments / Xcode Energy log).

---

## Deliverable 2 — Live Activity

### New target

`ActivityKit` Live Activities require a **Widget Extension target**. This is new
scaffolding:

- Add a `TrackitWidgets` app-extension target to `project.yml` (`com.apple...widget`
  product type, `NSExtensionPointIdentifier com.apple.widgetkit-extension`).
- `App/Widgets/` (new dir): the `Widget` + `ActivityConfiguration`, the
  lock-screen view, the Dynamic Island `expanded` / `compact` / `minimal`
  presentations.
- `NSSupportsLiveActivities = YES` in `App/Info.plist`.
- A shared `ActivityAttributes` type visible to both the app and the extension
  (its own small file, no dependency on `WorkoutLoggerCore` — pass primitives:
  exercise name string, set count, rest-deadline `Date`, an "is resting" flag).

### Seam

The app starts/updates/ends the Activity from the session layer. Cleanest: a
new `App/System/` type (`LiveActivityController`) with
`start(workout:) / update(state:) / end()`, driven by the same
`WorkoutSessionModel` observations the HUD uses (current exercise, last set,
rest deadline). It translates the model's state into `ActivityAttributes`
content. No `WorkoutLoggerCore` change; possibly a small `WorkoutLoggerApp`
change only if the model needs to expose a compact "activity state" projection
(preferable to the controller reaching into many properties — Feature Envy).

### Acceptance tests

Package-level (if an activity-state projection is added):

1. The projection reflects current exercise, working-set count, and rest
   deadline; updates when the model does; goes nil when the workout ends.

Device-only:

2. Starting a workout shows the Live Activity on the lock screen + Dynamic
   Island.
3. Logging a set updates it within a second.
4. The rest countdown ticks down on the lock screen (ActivityKit renders the
   `Text(timerInterval:)` itself — no push needed for the countdown).
5. Ending the workout dismisses it.
6. Force-quitting the app leaves the Activity in a sane state (stale, then
   auto-expires).

---

## Hardware / account dependencies

- A physical iPhone with Dynamic Island (or at least lock-screen Live Activity
  support — iOS 16.1+, but the app targets iOS 17+ so fine).
- Live Activities do **not** run in the Simulator's lock screen realistically;
  device required.
- No new entitlement for local Live Activities; **push-updated** Live Activities
  need APNs + the `com.apple.developer.usernotifications.time-sensitive` /
  push-token flow — see OPEN QUESTIONS (probably not needed).

---

## OPEN QUESTIONS (resolve before implementation)

> **All 7 resolved 2026-09-15** (owner route: Q2/Q4/Q5/Q7 via
> `AskUserQuestion`, accepted every recommendation; Q1/Q3/Q6 are
> implementation-technical calls, resolved directly and noted below).
> Summary: **explicit-press-only** background trigger (no continuous
> listening — completes the promise 7b's own spec deferred here), a
> **scheduled local notification** for rest completion (none existed
> before — see the "What exists today" correction above), the spec's own
> proposed **Dynamic Island content**, **read-only** Live Activity (no
> "Skip Rest" button), no live background audio session for the timer
> (timestamp-based), **local-only** Live Activity updates, and the
> standard `project.yml` widget-extension recipe (confirmed at
> implementation time via `xcodegen` + `xcodebuild`).

1. **Does the rest timer need a live background audio session at all?**
      > **Resolved 2026-09-15: no — timestamp-based, as the spec already
      > strongly recommended.** Technical call, resolved directly. Core's
      > `RestTimer` (`Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/RestTimer.swift`)
      > already stores `startedAt: Date?` and computes `elapsed(now:)` as
      > pure arithmetic against an injected clock — no live ticking is
      > baked into the domain model today; `WorkoutSessionModel.tick()` is
      > an App-layer polling convenience, not something the rest state
      > itself depends on. `restStartedAt` and `restTargetSeconds` are
      > already public on `WorkoutSessionModel`
      > (`Session/WorkoutSessionModel.swift:29,37`) — Deliverable 1 needs
      > no new package-level affordance beyond what already exists;
      > "rest deadline" is just `restStartedAt + restTargetSeconds`,
      > computed wherever it's needed (the local notification's fire
      > date, the Live Activity's `Text(timerInterval:)` end bound).
2. **Is background *listening* actually in scope, or only background *timer +
   readback + Live Activity*?**
      > **Resolved 2026-09-15 (owner, recommended option): explicit-press
      > only.** No continuous background mic access. A locked/backgrounded
      > phone still responds to a single earbud-button press (cluster 7b):
      > that press starts one utterance, held alive by a background audio
      > session only for the duration of that utterance + its spoken
      > readback, then the session can drop again. This is exactly the
      > scope cluster 7b's own spec deferred here ("background folded into
      > cluster 7c" — see `2026-09-11-cluster-7b-earbud-push-to-talk.md`
      > OPEN QUESTION 4's resolution). `RemoteCommandPushToTalk`
      > (7b) itself needs no change — it already just calls
      > `session.toggleListening()`; what changes is the audio-session
      > lifecycle and `UIBackgroundModes` that let that call still work
      > with the app backgrounded.
3. **Live Activity updates: local only or push?**
      > **Resolved 2026-09-15: local-only, as the spec recommended.**
      > Technical call, resolved directly — no APNs/server infrastructure
      > exists in this repo and adding one for a single push-updated field
      > would be large new scope for a marginal freshness gain.
      > **Staleness behaviour, now concrete given Q2's answer:** the
      > Activity's content is updated locally (`Activity.update(...)`)
      > whenever the app process is alive and a rest/set state change
      > happens — every foreground moment, and every explicit-press
      > utterance's brief background audio session (Q2). Between those
      > moments the process may be suspended; the *countdown itself*
      > stays accurate regardless (ActivityKit's `Text(timerInterval:)`
      > renders from the `Date` bound already pushed into the content, it
      > does not need a live process to keep ticking), but a *state*
      > change that happens with no process alive to observe it (e.g. the
      > rest timer reaching its target while suspended) will only be
      > reflected in the Activity's non-countdown fields (e.g. "resting"
      > → done) the next time the process wakes — which the local
      > notification (Q5) exists precisely to cover in the meantime.
4. **Dynamic Island content.**
      > **Resolved 2026-09-15 (owner, recommended option): the spec's own
      > proposal.** minimal = a dot; compact = a mic glyph (idle/listening)
      > or rest-seconds-remaining (resting) — mutually exclusive per
      > moment, never both; expanded = exercise name + last set + rest
      > countdown.
5. **Interaction with the existing local notification.**
      > **Resolved 2026-09-15 (owner, recommended option) — reframed by
      > the "What exists today" correction above: there is no existing
      > local notification to interact with.** Add one: a
      > `UNUserNotificationCenter` local notification scheduled at
      > rest-start for `restTargetSeconds` later, cancelled if rest is
      > skipped/reset before firing. This is the "phone in your pocket,
      > not looking" signal; the Live Activity is the "glance at the lock
      > screen" one — the pairing the spec originally intended, now built
      > rather than assumed to already exist. The foreground haptic
      > (`SystemHaptics.play(.restReached)`) is unaffected — it still
      > fires from `tick()` while foreground; the notification is
      > additive for the backgrounded case, not a replacement.
6. **Widget extension + XcodeGen.**
      > **Resolved 2026-09-15: standard recipe, confirmed by building it
      > in this pass.** Technical call, resolved directly — `project.yml`
      > gets a `TrackitWidgets` target (`type: app_extension`,
      > `com.apple.widgetkit-extension` `NSExtensionPointIdentifier`),
      > sources under `App/Widgets/`, and the main `Trackit` target
      > embeds it. `xcodegen generate && xcodebuild build` must go green
      > before this cluster is considered landed — same verification bar
      > as every prior cluster's App-layer work.
7. **Does the Live Activity offer actions** (e.g. a "skip rest" button)?
      > **Resolved 2026-09-15 (owner, recommended option): read-only.**
      > No buttons, no App Intent target, this pass — mirrors the planned
      > Watch complication's (cluster 7f) read-only stance. Keeps the
      > widget extension's surface to rendering only, no path back into
      > running app state to design, build, and test. A "Skip Rest"
      > button is a clean, additive follow-up if wanted later.

---

## Effort

Medium-large. Deliverable 1 is small if the timestamp approach wins (it does,
per OPEN QUESTION 1's resolution — `RestTimer` is already timestamp-based, no
package change needed there); the added scope is the background audio-session
lifecycle + a new local notification. Deliverable 2 is a new target + WidgetKit
views + a controller. **`writing-plans` pass taken** given the risk profile
(new Xcode target, ActivityKit, `UIBackgroundModes`) — plan file at
`docs/superpowers/plans/2026-09-15-cluster-7c-background-audio-live-activity.md`,
executed inline in-session rather than via subagent-driven-development (this
session already holds full context; a fresh-subagent-per-task pipeline would
duplicate review work already covered by this cluster's own two-axis review
at the end). Depends on 5a (audio path verified on device) and coordinates
with 7b (earbud button in background, done) and 7e (visual design, done).

## Status

- [x] OPEN QUESTIONS resolved and written back. Done 2026-09-15.
- [ ] `writing-plans` → plan file
- [ ] Deliverable 1: background modes + audio session + timestamp-based rest
- [ ] Deliverable 2: widget extension target + Live Activity views + controller
- [ ] device verification (both deliverables) + battery measurement
