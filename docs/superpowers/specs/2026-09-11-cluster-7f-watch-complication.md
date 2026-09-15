# Cluster 7f — Read-only Apple Watch complication

**Prerequisite reading:** `2026-09-11-v1.1-remaining-onboarding.md`.
**Parent:** `2026-09-06-v1.1-deferred-work-design.md` § "Cluster 7" → "Read-only Apple Watch complication".
**Master spec framing:** one line — *"Read-only Apple Watch complication."* No
further detail anywhere. This is the least-specified Cluster 7 item; the OPEN
QUESTIONS are load-bearing.

Impl-ready brief; design is wide open.

---

## What exists today

- **No watchOS target.** `project.yml` has `Trackit` (app) and `TrackitTests`
  (UI tests) only.
- No WatchConnectivity, no WidgetKit, no shared app group.
- All state lives on the phone: SwiftData (`WorkoutRecord`, `ExerciseRecord`,
  `SyncedWorkoutRecord`) + UserDefaults (`SettingsStore`).
- `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/ExerciseProgress.swift`
  and the history/progress projections already compute everything a glanceable
  watch face would show: last workout date, per-exercise bests, volume. These
  are pure functions over `[Workout]`.
- `WorkoutHistoryModel` / the progress model in `WorkoutLoggerApp` expose those
  projections to the phone UI.

---

## The work (assuming the smallest useful version)

"Read-only complication" most likely means: **a watch-face complication showing a
single glanceable fact** (e.g. "3 days since last workout" or "12 workouts this
month" or today's volume), updated from the phone. It is *not* a watch app for
logging (that would be a separate, much larger effort — and contradicts
"read-only").

1. **New watchOS App target + Widget Extension** in `project.yml`
   (`watchapp2`/`watchkit2-extension` product types, or the modern
   single-target watchOS app + `WidgetKit` complication). Even a "complication
   only" deliverable needs a watch app to host the widget extension.
2. **Shared data transport phone → watch.** Options:
   - `WatchConnectivity` (`WCSession`) — phone pushes a small "summary" payload
     (a `Codable` struct of the 1–3 numbers) on workout end / app foreground;
     watch caches it and the complication reads the cache.
   - App Group + shared file / shared `UserDefaults` — simpler, but the phone
     and watch don't share a container automatically; still needs
     `WCSession.transferUserInfo` or `updateApplicationContext` to move bytes.
   - CloudKit (only if 7a lands first and the watch reads the same store).
   Recommend `WCSession.updateApplicationContext` with a tiny summary struct —
   it's the "latest value wins, delivered opportunistically" primitive that
   exactly fits a read-only complication.
3. **A `WatchSummary` `Codable` struct** shared by phone + watch (its own small
   file; primitives only, no `WorkoutLoggerCore` dependency on the watch side —
   or add `WorkoutLoggerCore` as a watch dependency if the projections are
   wanted directly; it's pure Swift so it should build for watchOS).
4. **Phone side:** a small `App/System/WatchSummaryPublisher` that observes the
   history/progress models and calls `WCSession.default.updateApplicationContext`
   with a fresh `WatchSummary` whenever the underlying data changes.
5. **Watch side:** a `TimelineProvider` that reads the cached `WatchSummary` and
   renders the complication families in scope (see OPEN QUESTIONS).

No `WorkoutLoggerCore` change required — the numbers already exist as
projections. Possibly a small `WorkoutLoggerApp` addition: a single
`watchSummary` computed property that bundles the 1–3 facts, so the publisher
isn't reaching into three models (Feature Envy).

---

## Acceptance tests

Package-level:

1. `WatchSummary` round-trips through `Codable`.
2. The `watchSummary` projection (if added) computes the chosen facts from a
   given `[Workout]` — assert against hand-worked history fixtures (reuse
   `ExerciseProgress` test fixtures).
3. The publisher emits a new summary when history changes and not otherwise
   (spy on a fake `WCSession`-shaped protocol).

Device-only (needs a paired Apple Watch):

4. Adding the complication to a watch face shows the current value.
5. Finishing a workout on the phone updates the complication within the OS's
   refresh budget (complications are heavily rate-limited — this is
   "eventually", not "instantly").
6. The complication shows a sane placeholder before the first sync and in the
   gallery/editing view.
7. All in-scope complication families render legibly.

---

## Hardware dependencies

- A paired Apple Watch + the phone.
- watchOS deployment target decision (watchOS 10+ for the modern WidgetKit
  complication API; older needs ClockKit `CLKComplicationDataSource`).
- Complications essentially cannot be developed without the hardware; the watch
  simulator helps for layout only.
- New target = new signing / provisioning profile for the watch app + extension.

---

## OPEN QUESTIONS (all load-bearing — this item is barely specified)

1. **What single fact does it show?** Candidates: days since last workout;
   workouts this week/month; today's total volume; current-exercise best; a
   streak count. Pick one primary (complications are tiny). The master spec
   gives no guidance.
   > **Resolved 2026-09-15:** Days since last workout. Trivially computed
   > (`history.filter(\.isEnded)`, most recent `endedAt`, no per-exercise
   > `ExerciseProgress` projection needed), reads sensibly even with zero
   > history (a placeholder dash), and it's the single glanceable fact that
   > most directly answers PRODUCT.md's own success framing — "keep logging
   > consistently... rather than abandoning logging altogether" — over a
   > raw count (workouts this week) or a value (today's volume) that says
   > nothing about consistency at a glance.
2. **Which complication families?** `.accessoryCircular`, `.accessoryRectangular`,
   `.accessoryInline`, `.accessoryCorner`? More families = more layout work.
   Recommend circular + inline for a v1.1.
   > **Resolved 2026-09-15:** `.accessoryCircular` + `.accessoryInline`, per
   > this spec's own recommendation — the two lowest-effort, most-supported
   > families across watch face styles, matching the "read-only, minimal"
   > framing. `.accessoryRectangular`/`.accessoryCorner` deferred; add later
   > if device use reveals a real gap.
3. **Is a hosting watch app in scope, or complication-only?** You need *a* watch
   app target to ship a complication, but does it have any UI itself (a one-screen
   summary), or is it an empty shell? Empty shell is less work and matches
   "read-only".
   > **Resolved 2026-09-15:** Empty shell. A single `WindowGroup` showing
   > only the app name/icon, no functional UI, no logging capability, no
   > navigation. It exists only because WidgetKit complications require a
   > companion watch app target to host the extension — it's not a second
   > product surface.
4. **Transport: `WatchConnectivity` now, or wait for CloudKit (7a)?** If 7a
   lands, the watch could read the synced store directly and skip `WCSession`.
   Sequencing decision.
   > **Resolved 2026-09-15:** `WatchConnectivity` now. 7a (CloudKit sync) is
   > un-implemented and unscheduled — every other Cluster 7 item has shipped
   > independently of it, and blocking 7f on 7a would stall it indefinitely.
   > `WCSession.updateApplicationContext` with the small `WatchSummary`
   > struct, per this spec's own recommendation. If 7a lands later, the
   > watch's data source can migrate then; not this cluster's concern.
5. **Refresh expectations.** Complications get a small daily refresh budget.
   "Read-only" and "updated occasionally" is the honest promise — confirm that's
   acceptable rather than users expecting real-time.
   > **Resolved 2026-09-15:** Confirmed acceptable — "eventually consistent
   > within the OS's complication refresh budget," never promised as
   > real-time, matching acceptance test 5's own framing. No code
   > implication beyond not over-promising in any UI copy.
6. **watchOS deployment target** (drives ClockKit vs. WidgetKit API).
   > **Resolved 2026-09-15:** watchOS 10.0. Pairs with the phone app's
   > existing iOS 17 floor (watchOS 10 shipped alongside iOS 17), and is
   > fully within the modern WidgetKit complication API — no ClockKit
   > `CLKComplicationDataSource` fallback needed. The installed SDK
   > (watchOS 26.5, confirmed via `xcodebuild -showsdks`) supports it.
7. **Does it use the same semantic palette as 7e?** If light mode ships, the
   complication should honour the same colour meanings.
   > **Resolved 2026-09-15:** Yes, so far as it applies — 7e (merged)
   > introduced no dedicated `Palette`/asset-catalogue file, only standard
   > SwiftUI dynamic system colors on non-HUD screens. The complication
   > follows the same approach: standard dynamic colors, no new palette
   > file. In practice this affects little — `.accessoryCircular`/
   > `.accessoryInline` are rendered in the system's own tint per watch
   > face and mostly ignore app-supplied color regardless of theme.
8. **Priority.** Given how thin the spec is and the new-target cost, is this
   actually a v1.1 item or a "nice someday"? Worth confirming before investing.
   > **Resolved 2026-09-15:** In scope — confirmed by the explicit request
   > to start this cluster.

---

## Effort

Medium — dominated by new-target scaffolding + `WatchConnectivity` plumbing +
device iteration, not by logic (the numbers already exist). **`writing-plans`
pass recommended** once OPEN QUESTIONS 1–4 are settled. Do late in the cluster;
after 7a if CloudKit is happening (it changes the transport decision).

## Status

- [x] OPEN QUESTIONS resolved (esp. 1 primary fact, 3 scope, 4 transport). Done 2026-09-15.
- [x] `writing-plans` → plan file. `docs/superpowers/plans/2026-09-15-cluster-7f-watch-complication.md`.
- [x] watchOS app + widget-extension targets in `project.yml`. `TrackitWatch` + `TrackitWatchWidgets`, verified via a real `xcodebuild` (watchOS platform installed 2026-09-15) — `** BUILD SUCCEEDED **` for both the `Trackit` scheme (embeds `TrackitWatch.app`) and the `TrackitWatch` scheme.
- [x] `WatchSummary` + phone publisher + watch timeline provider. `SystemWatchSummaryTransport` (phone) → `WCSession.updateApplicationContext` → `WatchConnectivitySessionReceiver` (watch) → App Group `UserDefaults` → `DaysSinceLastWorkoutProvider` (`TimelineProvider`, refreshes on push + at local midnight).
- [ ] paired-watch device verification. Out of scope for this pass (no physical device available), same as every prior cluster's device step.
- [x] update parent roadmap + memory. `docs/superpowers/specs/2026-09-11-v1.1-remaining-INDEX.md` + `MEMORY.md`.
