# Cluster 5 remainder — device verification, real telemetry transport, latency confirmation

**Prerequisite reading:** `2026-09-11-v1.1-remaining-onboarding.md`.
**Parent roadmap:** `2026-09-06-v1.1-deferred-work-design.md` § "Cluster 5".
**Execution plan (still valid for the package parts already done):**
`docs/superpowers/plans/2026-09-06-v1.1-cluster-5-telemetry-latency.md`.

Cluster 5 is the only work between the current tree and a shippable build. The
package-level code for 5b and 5c is **already merged**. What is left is:

1. **5a** — a full smoke pass on a physical iPhone, plus two device-only UI tests.
2. **5b** — confirm `TelemetryHTTPTransport` compiles and works in the real
   `xcodebuild`, and point it at a real ingest host (GitHub issue #6).
3. **5c** — confirm the press-to-logged median is ≤ 3 s on real hardware, then
   promote the metric from "tracked" to a hard pre-release check.

Everything here is split into **[IN-REPO]** (doable now, no hardware) and
**[DEVICE]** (needs a Mac with Xcode 26 + a physical iPhone, and an Apple
Developer account for signing).

---

## What already exists

### Package layer (merged, `swift test`-green)

- `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Telemetry/`
  - `TelemetryEvent.swift` — closed enum; `case setLoggedLatency(millisBucket: Int)` is the latency carrier.
  - `TelemetryPayload.swift` — `TelemetryPayload`, `TelemetryPayloadCodec`; a test asserts the encoded JSON carries only enum-derived keys (the content-free invariant).
  - `TelemetryTransport.swift` — `public protocol TelemetryTransport: Sendable { func send(_ body: Data) async throws }` + `enum TelemetryTransportError { case permanent(statusCode: Int) }`.
  - `TelemetryQueueStore.swift` — `QueuedEvent`, `TelemetryQueueState`, protocol + `InMemoryTelemetryQueueStore`.
  - `TelemetryUploader.swift` — `@MainActor ... : TelemetrySink`; batching, exponential back-off, queue cap, `discardPending()` on opt-out.
  - `Latency.swift` — `LatencyMetric.bucketMillis(_:)` (100 ms buckets, clamps ≤0 to 0) and `LatencyMetric.medianBucketMillis(of:)` (lower-middle median; **not called at runtime yet** — see issue #8).
  - `TelemetryFakes.swift` — `SpyTelemetryTransport`, fake queue store.
- `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift`
  — `released() async` wall-clocks `now().timeIntervalSince(releasedAt)` across
  `endUtterance()` + `apply(hypotheses)` and, when a set was logged, emits
  `onTelemetry(.setLoggedLatency(millisBucket: LatencyMetric.bucketMillis(...)))`.
  The latency event is **only** emitted for a set logged straight from an
  utterance — not one completed via tap-select disambiguation.

### App layer (files-only — written, compiles under `xcodebuild` per PR #11, not run)

- `App/System/TelemetryHTTPTransport.swift` — `struct TelemetryHTTPTransport: TelemetryTransport`.
  - `static let defaultEndpoint = URL(string: "https://telemetry.trackit.abubakarsahi.com/v1/events")!` — **placeholder host, does not resolve.**
  - `send(_:)` POSTs `application/json`; 2xx = delivered; `{400, 404, 413, 422}` → `.permanent` (drop batch); everything else (408/429/5xx/network) throws plain → uploader retries with back-off. 401/403 deliberately stay transient. No response body read.
- `App/System/FileTelemetryQueueStore.swift` — JSON-file `TelemetryQueueStore`.
- `App/TrackitApp.swift` — builds a `TelemetryUploader` from those two adapters; flushes on `scenePhase == .active`.
- `App/System/SystemSpeechRecognizer.swift`, `SystemReadbackVoice.swift`,
  `SystemHaptics.swift`, `SystemHealthKitWorkoutStore.swift` — real adapters,
  compile, three Swift 6 `@MainActor`-callback crashes already fixed.
- `App/Info.plist` — has `NSSpeechRecognitionUsageDescription`,
  `NSMicrophoneUsageDescription`, `NSHealthUpdateUsageDescription`.
- `App/Trackit.entitlements` — has `com.apple.developer.healthkit`.
- `App/Tests/` (`TrackitTests`, XCUITest bundle):
  - `HUDGlanceableStateUITests` — talk button present + portrait lock. **Green on the iPhone 17 simulator.**
  - `TapSelectInteractionUITests` — **needs mic hardware**; the Simulator audio HAL times out in `AURemoteIO::Initialize`. Device-only.

---

## 5a — Device smoke pass

### [IN-REPO] prep before the device pass

1. **Re-read every `System*` adapter against its package protocol.** For each of
   `SystemSpeechRecognizer` (`TranscriptSource`), `SystemReadbackVoice`
   (`ReadbackVoice`), `SystemHaptics` (`Haptics`),
   `SystemHealthKitWorkoutStore` (`HealthKitWorkoutStore`),
   `SystemSettingsStore`, and the telemetry adapters: open the adapter and the
   protocol side by side and confirm every method signature, parameter label,
   and `async`/`throws` marker matches. This is the only correctness check
   available without a compiler; do it deliberately, not by skim. Record the
   result in the PR body.
2. **Audit `App/TrackitApp.swift` wiring.** Every model constructor argument
   should be a value built earlier in the same function. Confirm:
   - `healthSync` gets `SystemHealthKitWorkoutStore()` + `settingsStore` +
     `SwiftDataSyncedWorkoutStore(context:)`.
   - `historyModel.onWorkoutEdited` is set to
     `{ workout in Task { @MainActor in await healthSync.workoutEdited(workout) } }`.
   - the `TelemetryUploader` is passed as the `TelemetrySink` into
     `TelemetryRecorder`, and `.flush()` is called on `scenePhase == .active`.
3. **Fill in the smoke checklist's expected values.** Open
   `docs/superpowers/checklists/2026-09-06-device-smoke-test.md` and, for any
   step whose expected observation is vague, tighten it against the current
   projections so the device pass is unambiguous. (This checklist is the
   contract for the [DEVICE] step below — don't change what it tests, only
   sharpen how you'll know it passed.)
4. **Write down the three regression-watch crashes** from that checklist
   (`SFSpeechRecognizer.requestAuthorization`,
   `AVAudioApplication.requestRecordPermission`, `AVAudioEngine.installTap`
   render block — all fixed via `@Sendable` + `nonisolated(unsafe)`), so if any
   `EXC_BREAKPOINT` shows up on device you recognise it immediately.

### [DEVICE] the pass itself

Environment: a Mac with Xcode 26 / iOS 26 SDK, `xcodegen` installed, a physical
iPhone (iOS 17+) on your Apple Developer team.

```bash
xcodegen generate
xcodebuild -scheme Trackit -destination 'generic/platform=iOS' build
xcodebuild -scheme Trackit -destination 'id=<your-device-udid>' test   # runs TrackitTests
```

Then run every section of
`docs/superpowers/checklists/2026-09-06-device-smoke-test.md` on the device:

- **Build** — clean `xcodegen generate` + `xcodebuild build` + `test`.
- **Regression watch** — no `EXC_BREAKPOINT` on the audio/speech callbacks.
- **Voice loop** — press-talk-release, real `SFSpeechRecognizer` with
  `requiresOnDeviceRecognition = true`, in real gym noise; n-best shape sane;
  `.dictation` hint applied; readback + earcon timing feels right; the four
  `CHHapticEngine` patterns (logged / notCaught / personalRecord / restReached)
  feel distinct.
- **Around the loop** — History, Progress, Export share sheet; **Apple Health
  toggle → authorization sheet → finish a workout → it appears in the Health app
  as Traditional Strength Training**; edit a synced workout → the Health copy
  updates (cluster 4's `resync`); Analytics toggle → a `telemetry-queue.json`
  appears in the app container.
- **Accessibility / platform** — Larger Text on the big HUD number, Reduce
  Motion, portrait lock, no auto-lock during a workout (stories 42, 66, 67).
- **Latency** — see 5c below.
- **`TapSelectInteractionUITests`** — now runs (real mic); should pass.

### [DEVICE] acceptance

- `xcodebuild test` green on the device (both UI tests).
- Every checklist section ticked, with notes on anything that felt wrong.
- A signed build installs and a full workout logs end to end by voice.
- A workout written to Apple Health is visible in the Health app and updates
  after an edit.

### Hardware-only, cannot be prepped in-repo

The actual feel of haptics/readback timing, real-recogniser accuracy in noise,
the HealthKit authorization sheet, and mic-dependent UI tests. Everything else
above is checklist tightening you can do now.

---

## 5b — Real telemetry transport + endpoint (GitHub issue #6)

### [DEVICE] confirm the transport compiles and runs

`TelemetryHTTPTransport` and `FileTelemetryQueueStore` are consistency-checked
only. Under the real `xcodebuild`:

- Confirm they compile (they're in the `Trackit` target sources).
- With Analytics enabled, finish a workout, background the app, and confirm a
  batch POST leaves the device (Charles / a local echo server / your ingest
  host's logs). Confirm the body is a JSON array of enum-shaped events + a
  content-free install id, nothing else.
- Kill connectivity, finish a workout, confirm nothing blocks and the queue
  file grows; restore connectivity, foreground, confirm it flushes.
- Toggle Analytics off, confirm the queue file is emptied (`discardPending()`).

### OPEN QUESTIONS (resolve before shipping analytics enabled)

1. **Ingest host.** `defaultEndpoint` is
   `https://telemetry.trackit.abubakarsahi.com/v1/events` — a placeholder that
   does not resolve. **Decide:** stand up a first-party endpoint at a real host,
   or adopt a hosted analytics service (and wrap its SDK behind
   `TelemetryTransport` so the package contract is unchanged). The payload is
   tiny and fixed; a minimal first-party collector is a few lines. This is the
   blocking item on issue #6.
2. **Status-code taxonomy.** The `{400, 404, 413, 422}` → `.permanent` split and
   the "401/403 stay transient" choice are a best guess made without a real
   endpoint contract (documented as provisional in
   `TelemetryTransport.swift` and issue #6). Once the endpoint exists, reconcile
   its actual error responses with this set. If the uploader ever starts
   splitting oversized batches, **413 must move out of `.permanent`** (noted in
   the transport source).
3. **Install-id shape.** Confirm what content-free identifier the payload
   carries and that it is stable per install and not derivable to a person.
   (`abubakarsahi534@gmail.com` and any account identifier must never reach the
   payload — see the onboarding doc.)
4. **Auth.** Does the endpoint need an API key / bearer token in the request?
   If so, where is it stored (Info.plist build setting vs. entitlement vs.
   keychain) and does a rotation story exist?

### [IN-REPO] prep

- Nothing in the package should need to change. If a resolved OPEN QUESTION
  forces a package change (e.g. the transport needs a header the protocol can't
  express), that is a new TDD slice in `WorkoutLoggerApp` with its own test —
  keep `App/` logic-free.

---

## 5c — Latency: confirm ≤ 3 s median on device, then gate it

The master spec's launch gate: **≤ 3 s median press-to-confirmed-set**. The span
is button-release → the "logged" haptic/readback fires; it covers
`endUtterance()`, `postProcess`, `parse`, `engine.hear`, and feedback dispatch.
`LatencyMetric.bucketMillis` buckets it to 100 ms; `medianBucketMillis` is the
exact gate definition (lower-middle median).

### [DEVICE] measure

- With Analytics enabled, log ~30 sets by voice across a realistic session.
- Read the `.setLoggedLatency` buckets out of the queue file (or your ingest
  host).
- Compute the median with `LatencyMetric.medianBucketMillis(of:)` semantics
  (lower-middle element of the sorted buckets).
- Record it. The gate wants this **stably < 3000 ms on real hardware**.

### OPEN QUESTIONS

1. **Where does the gate live once promoted?** Options: a device-run assertion
   in `TrackitTests` seeded from a scripted-utterance batch (fast, but the
   scripted clock isn't wall-clock); a manual pre-release checklist line backed
   by a real session's numbers; or a CI job that replays recorded audio through
   the real recogniser (overlaps cluster 6's harness — consider sharing it).
2. **`medianBucketMillis` has no runtime caller** (issue #8, item kept
   deliberately). Decide whether the promoted gate is the caller, or whether it
   stays a shared definition used only by an offline analysis script.
3. **Scripted-clock vs wall-clock.** The package tests drive an injected clock,
   so they can assert the computed span for a scripted utterance but not real
   recogniser latency. Confirm the gate distinguishes "our code's overhead"
   (testable in-package) from "recogniser + device" (device-only).

### [IN-REPO] prep

- Add a package test (if not already present) that asserts
  `medianBucketMillis` over a scripted batch matches a hand-worked expected
  value — pins the definition so the eventual gate can't drift.
- If OPEN QUESTION 1 picks the CI-replay option, coordinate the harness shape
  with `2026-09-11-cluster-6-accuracy-gate.md` so audio fixtures load once.

---

## Effort

5a device pass: ~half a day on hardware once the [IN-REPO] prep is done.
5b: small once the endpoint decision is made; the collector itself may be a
separate infra task. 5c: an hour of device measurement + whatever the gate
placement decision implies. A `writing-plans` pass is **not** needed — this spec
plus the existing checklist is the plan.

## Status

- [ ] 5a [IN-REPO] adapter + wiring re-audit, checklist tightening
- [ ] 5a [DEVICE] full smoke pass, both UI tests green on device
- [ ] 5b endpoint decision (issue #6) + [DEVICE] transport confirmation
- [ ] 5c [DEVICE] median measurement + gate-placement decision
- [ ] update `2026-09-06-v1.1-deferred-work-design.md` Cluster 5 status + memory
