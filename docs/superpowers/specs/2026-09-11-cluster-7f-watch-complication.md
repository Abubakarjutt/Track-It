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
2. **Which complication families?** `.accessoryCircular`, `.accessoryRectangular`,
   `.accessoryInline`, `.accessoryCorner`? More families = more layout work.
   Recommend circular + inline for a v1.1.
3. **Is a hosting watch app in scope, or complication-only?** You need *a* watch
   app target to ship a complication, but does it have any UI itself (a one-screen
   summary), or is it an empty shell? Empty shell is less work and matches
   "read-only".
4. **Transport: `WatchConnectivity` now, or wait for CloudKit (7a)?** If 7a
   lands, the watch could read the synced store directly and skip `WCSession`.
   Sequencing decision.
5. **Refresh expectations.** Complications get a small daily refresh budget.
   "Read-only" and "updated occasionally" is the honest promise — confirm that's
   acceptable rather than users expecting real-time.
6. **watchOS deployment target** (drives ClockKit vs. WidgetKit API).
7. **Does it use the same semantic palette as 7e?** If light mode ships, the
   complication should honour the same colour meanings.
8. **Priority.** Given how thin the spec is and the new-target cost, is this
   actually a v1.1 item or a "nice someday"? Worth confirming before investing.

---

## Effort

Medium — dominated by new-target scaffolding + `WatchConnectivity` plumbing +
device iteration, not by logic (the numbers already exist). **`writing-plans`
pass recommended** once OPEN QUESTIONS 1–4 are settled. Do late in the cluster;
after 7a if CloudKit is happening (it changes the transport decision).

## Status

- [ ] OPEN QUESTIONS resolved (esp. 1 primary fact, 3 scope, 4 transport)
- [ ] `writing-plans` → plan file
- [ ] watchOS app + widget-extension targets in `project.yml`
- [ ] `WatchSummary` + phone publisher + watch timeline provider
- [ ] paired-watch device verification
- [ ] update parent roadmap + memory
