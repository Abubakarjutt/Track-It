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
- **Rest-completion signal** in v1: haptic + sound + a local notification
  (`UNUserNotificationCenter`). Look for the local-notification scheduling in the
  App layer's session/HUD area and in `App/System/` (a `SystemNotifications`-style
  wrapper, if present).
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

## OPEN QUESTIONS

1. **Does the rest timer need a live background audio session at all?** Strong
   recommendation: no — derive remaining time from timestamps + a scheduled
   local notification + the Live Activity's self-rendering countdown. Confirm,
   because "yes" means a much heavier, battery-hungry, App-Review-sensitive
   implementation.
2. **Is background *listening* actually in scope, or only background *timer +
   readback + Live Activity*?** Continuous background mic access is a strong App
   Review flag and a privacy concern. Likely scope: the app may be backgrounded
   / screen-locked and still *respond to an explicit earbud-button press* (7b),
   but it is not always-listening in the background. Nail this down — it changes
   the audio-session design.
3. **Live Activity updates: local only or push?** Local updates
   (`Activity.update(...)` from the running app) are enough if the app process
   stays alive in the background audio session. If the app can be suspended,
   keeping the Activity fresh needs push (APNs, a server, tokens). Prefer
   local-only; document the staleness behaviour when suspended.
4. **Dynamic Island content.** What's in compact / minimal / expanded? Proposal:
   minimal = a dot; compact = rest seconds remaining or a mic glyph; expanded =
   exercise name + last set + rest countdown. Needs a design pass (interacts
   with 7e light mode and the "HUD is the brand" stance).
5. **Interaction with the existing local notification.** Keep both the
   notification and the Live Activity, or does the Live Activity replace the
   notification? (Recommend: keep the notification as the "you're not looking at
   the phone at all" signal; Live Activity is the "glance at lock screen" one.)
6. **Widget extension + XcodeGen.** Confirm the `project.yml` extension-target
   recipe and that `xcodegen` + `xcodebuild` build it cleanly. New target = new
   signing config.
7. **Does the Live Activity offer actions** (e.g. a "skip rest" button —
   ActivityKit supports `Button`/`Toggle` with App Intents on iOS 17+)? Or is it
   read-only like the Watch complication (7f)?

---

## Effort

Medium-large. Deliverable 1 is small if the timestamp approach wins; Deliverable
2 is a new target + WidgetKit views + a controller. **`writing-plans` pass
recommended.** Depends on 5a (audio path verified on device) and coordinates with
7b (earbud button in background) and 7e (visual design).

## Status

- [ ] OPEN QUESTIONS resolved and written back
- [ ] `writing-plans` → plan file
- [ ] Deliverable 1: background modes + audio session + timestamp-based rest
- [ ] Deliverable 2: widget extension target + Live Activity views + controller
- [ ] device verification (both deliverables) + battery measurement
