# trackit device smoke test

Run on a physical iPhone (iOS 17+), signed with a HealthKit-capable profile.
Every box is a real interaction, not a screenshot review.

## Build

- [ ] `xcodegen generate` regenerates `Trackit.xcodeproj` with no diff to commit beyond expected.
- [ ] `xcodebuild -scheme Trackit -destination 'generic/platform=iOS' build` — clean build, zero errors.
- [ ] `xcodebuild -scheme Trackit -destination 'platform=iOS Simulator,name=iPhone 15' test` — `TrackitTests` green.
      Simulator note: `HUDGlanceableStateUITests` runs anywhere;
      `TapSelectInteractionUITests` requires mic hardware and only passes
      on a device (the Simulator audio HAL aborts in `AURemoteIO::Initialize`).

## Regression watch — Swift 6 isolation on audio/speech callbacks

Standing up the build loop found three `EXC_BREAKPOINT` crashes: system
callbacks inferred `@MainActor` that the SDK runs off-main. All three are now
fixed — `SystemSpeechAuthorization` / `SystemSpeechRecognizer`
`requestAuthorization` closures are `@Sendable`, and the
`AVAudioEngine.installTap` render block in `SystemSpeechRecognizer.beginUtterance()`
captures the recognition request as `nonisolated(unsafe)` and is `@Sendable`
(the request is fed only from the tap and always `removeTap`'d before
`endUtterance()` touches it again). Verify on device that the record path is
actually crash-free:

- [ ] Press-and-hold the talk button and speak a set → **no crash**; a
      transcript comes back. (A trap in `dispatch_assert_queue` on an audio
      thread means a capture-audio callback is still main-actor-isolated.)

## Voice loop (the product)

- [ ] Fresh install → onboarding priming screen shows, "Continue" grants mic + speech.
- [ ] "start workout" → tone; HUD shows an open workout.
- [ ] "bench press" → full spoken readback ("Bench Press").
- [ ] "225 for 5" → terse readback + a distinct "logged" haptic; rest clock starts.
- [ ] Same phrase again → logs again (repeat-to-retry overwrite is a later cluster; a second row here is fine).
- [ ] "undo" → earcon; last set gone.
- [ ] Airplane mode ON → the whole loop above still works (no network dependency).
- [ ] Rest timer reaches target → haptic + sound fire once.
- [ ] Beat a previous best → PR trophy + its own haptic, exactly once.

## Around the loop

- [ ] History list shows the completed workout; open it, edit a set's load, reopen — change persisted.
- [ ] Per-exercise progress screen renders load / volume / e1RM series.
- [ ] Settings → Export → share sheet appears with a JSON and a CSV option; both files open.
- [ ] Settings → Apple Health toggle → authorization sheet; after granting, the finished workout appears in the Health app as Traditional Strength Training with a duration and an energy figure.
- [ ] Settings → Analytics toggle ON → do a workout → force-quit and relaunch → `telemetry-queue.json` exists under Application Support and holds only `kind`/count/bucket fields (no loads, names, transcripts).
- [ ] Analytics toggle OFF → `telemetry-queue.json` `pending` array is emptied.
- [ ] Failed-utterance review: say gibberish with the review opt-in ON → the transcript appears in the Settings review list; nothing sends without a per-item tap.

## Accessibility / platform

- [ ] Settings → Accessibility → Larger Text at max → HUD number scales within its clamp and stays on screen; every screen readable.
- [ ] Reduce Motion ON → no motion the spec forbids.
- [ ] Rotate the phone → app stays portrait.
- [ ] Screen never auto-locks while a workout is open; locks normally after "end workout".

## Latency (tracked metric — spec § Success gates)

- [ ] Log ~20 sets on device; the emitted `set_logged_latency` buckets have a median ≤ 3000 ms.
- [ ] Note: `set_logged_latency` is emitted only for sets logged straight from an utterance — a set completed via the tap-select shortlist emits none (it would fold in human choice time). Read the median as "press-to-logged for utterances that resolved without disambiguation."
