# Cluster 7b — Earbud-button push-to-talk

**Prerequisite reading:** `2026-09-11-v1.1-remaining-onboarding.md`.
**Parent:** `2026-09-06-v1.1-deferred-work-design.md` § "Cluster 7" → "Earbud-button push-to-talk".
**Master spec framing:** *"Earbuds already work as the mic; only the on-screen
trigger is v1."* So this item is purely: **let a wired/Bluetooth headset remote
button start and stop an utterance without touching the screen.**

Impl-ready brief; design questions open.

---

## What exists today

The whole logging loop is already driven by two model calls — the screen button
is just one caller:

- `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift`
  - `public func pressed()` — `transcriptSource.beginUtterance(); isListening = true; notLoggedNotice = false`.
  - `public func released() async` — `isListening = false`, timestamps the release,
    `hypotheses = try await transcriptSource.endUtterance()`, applies them,
    emits `.setLoggedLatency` when a set was logged. On `endUtterance()` throw:
    `haptics.play(.notCaught); readbackVoice.perform(.earcon)`.
- `App/Views/HUDView.swift` — `talkButton` calls `model.pressed()` on a
  `DragGesture().onChanged` (when `!model.isListening`) and `model.released()` on
  gesture end. `.accessibilityIdentifier("talkButton")`.
- `App/System/SystemSpeechRecognizer.swift` — `TranscriptSource` over
  `SFSpeechRecognizer` + `AVAudioEngine`; already the mic path the earbuds feed.
- `App/System/SystemReadbackVoice.swift`, `SystemHaptics.swift` — feedback the
  lifter gets without looking.

**Nothing consumes remote-control / media-key events.** There is no
`MPRemoteCommandCenter`, no `MPNowPlayingInfoCenter`, no audio-session category
that would receive them.

---

## The seam

`pressed()` / `released()` are the entire integration surface. A headset-remote
handler is a **second caller** of the same two methods. No model API changes are
needed for the simplest version.

Where the handler lives: a new `@MainActor` type in `App/System/` (e.g.
`RemoteCommandPushToTalk`) that:

1. Configures `MPRemoteCommandCenter` targets (see OPEN QUESTIONS for which
   command).
2. On the "press" signal calls `session.pressed()`; on "release" calls
   `Task { await session.released() }`.
3. Is created and retained in `App/TrackitApp.swift` next to the other `System*`
   wiring, given a reference to the `WorkoutSessionModel`.

If the chosen command semantics need a package-visible affordance (e.g. a
`toggleListening()` on the model because the remote only gives discrete taps, not
press+hold), that is one small TDD slice in `WorkoutLoggerApp` with its own test.

---

## Acceptance tests

Package-level (if a `toggleListening()` or similar is added):

1. A discrete "toggle" call starts an utterance when idle and finishes it when
   listening — same observable effect as `pressed()` then `released()`.
2. A toggle received while `isProcessing` (a prior release still in flight) is
   ignored, not queued into a second overlapping utterance.
3. Feedback on a failed catch is identical whichever caller triggered it.

Device-only (needs real headsets):

4. Wired EarPods centre button starts/stops an utterance with the app
   foregrounded.
5. AirPods stem press (or whatever gesture is chosen) does the same.
6. The handler does **not** hijack the button when no workout is active / the app
   is backgrounded (unless 7c's background-audio work is also in — coordinate).
7. Music playing from another app: pressing the remote does the expected thing
   (either trackit takes it because it's the active audio app, or it's declined
   cleanly — decide in OPEN QUESTIONS).

---

## Hardware dependencies

- A wired headset with an inline remote (Lightning EarPods / USB-C EarPods / a
  3.5 mm set via adapter).
- AirPods or equivalent Bluetooth earbuds.
- A physical iPhone — remote-command events don't arrive in the Simulator.
- Verified as part of the cluster 5a device pass style checklist.

---

## OPEN QUESTIONS (resolve before implementation)

1. **Which remote signal?** `MPRemoteCommandCenter` exposes `playCommand`,
   `pauseCommand`, `togglePlayPauseCommand`, `stopCommand`, plus skip/seek. A
   headset centre button maps to play/pause/toggle. There is **no "press and
   hold" remote command** — the remote gives you discrete events, not a held
   state. So the earbud interaction is almost certainly **toggle** ("tap to
   start listening, tap to stop"), not "hold to talk". Confirm that UX is
   acceptable, or decide a double-press / long-press mapping (`MPRemoteCommandCenter`
   long-press is not standard — would need `AVAudioSession` route-change or
   accessory hacks; probably out of scope).
2. **Does trackit become the Now Playing app?** To reliably receive remote
   commands you generally must set `MPNowPlayingInfoCenter.default().nowPlayingInfo`
   and have an active playback audio session. trackit plays no media. Options:
   (a) publish minimal Now Playing info ("Trackit — workout in progress") only
   while a workout is active; (b) rely on being the foreground audio-recording
   app; (c) accept that it only works when nothing else is playing. This
   interacts heavily with 7c (background audio).
3. **Audio session category.** The recorder currently uses whatever category
   `SystemSpeechRecognizer` sets (likely `.record` or `.playAndRecord`). Receiving
   remote commands and ducking other audio may require `.playAndRecord` with
   `.mixWithOthers` / `.duckOthers`. Define the exact category/mode/options and
   whether it changes the existing recogniser behaviour.
4. **Scope: foreground only, or background too?** If background, this cluster
   depends on 7c. Recommend shipping **foreground-only first** and folding the
   background case into 7c.
5. **Toggle timeout.** With hold-to-talk, releasing ends the utterance. With
   toggle, what ends it if the lifter never taps again — a silence timeout in
   `SystemSpeechRecognizer`? A max duration? This may already exist for the
   screen button; confirm and reuse.
6. **Discoverability.** Is there any UI telling the user the earbud button works?
   A one-time tip? A Settings line? Master spec is silent.

---

## Effort

Small once OPEN QUESTIONS 1–3 are settled — one `App/System/` type, possibly one
package slice, plus device testing. No `writing-plans` pass needed unless the
Now-Playing/audio-session work (Q2/Q3) turns out to entangle the recogniser. Do
**after** 5a is verified so the audio path is known-good on device.

## Status

- [ ] OPEN QUESTIONS resolved and written back
- [ ] package slice (if a toggle affordance is needed) — TDD
- [ ] `App/System/RemoteCommandPushToTalk` + `TrackitApp.swift` wiring
- [ ] device verification with wired + Bluetooth headsets
