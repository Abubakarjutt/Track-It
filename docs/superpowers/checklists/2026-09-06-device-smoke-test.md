# trackit device smoke test

Run on a physical iPhone (iOS 17+), signed with a HealthKit-capable profile.
Every box is a real interaction, not a screenshot review.

## Build

- [ ] `xcodegen generate` regenerates `Trackit.xcodeproj` with no diff to commit beyond expected.
- [ ] `xcodebuild -scheme Trackit -destination 'generic/platform=iOS' build` — clean build, zero errors.
- [ ] `xcodebuild -scheme Trackit -destination 'platform=iOS Simulator,name=iPhone 15' test` — `TrackitTests` green.

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
