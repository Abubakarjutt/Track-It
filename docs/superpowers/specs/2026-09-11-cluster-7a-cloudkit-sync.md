# Cluster 7a — CloudKit sync across devices

**Prerequisite reading:** `2026-09-11-v1.1-remaining-onboarding.md`.
**Parent:** `2026-09-06-v1.1-deferred-work-design.md` § "Cluster 7" → first bullet.
**Master spec framing:** "Not in v1 (planned for v1.1)" → "CloudKit sync across
devices". Also flagged in the master spec's Further Notes as *"CloudKit sync and
the earbud button are the two areas most likely to stall a first-time iOS
developer for weeks."* Treat this as the largest, riskiest v1.1 item. Do it last,
on its own branch, with its own `writing-plans` pass.

This is an **impl-ready brief with design questions open** — not a finished
design. Resolve the OPEN QUESTIONS with the repo owner first.

---

## What exists today (v1: local-only)

- **Persistence** is SwiftData. `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/HUD/StoreProvisioning.swift`
  builds the container:
  ```swift
  let schema = Schema([WorkoutRecord.self, ExerciseRecord.self, SyncedWorkoutRecord.self])
  // ModelConfiguration(schema: schema, url: onDiskURL)   — NO cloudKitDatabase option
  // enum result: .ready(ModelContainer) / .degraded(ModelContainer)  (in-memory fallback)
  ```
  There is **no CloudKit configuration** anywhere.
- `@Model` types:
  - `WorkoutRecord` — `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/` (the persisted completed-workout row; `SwiftDataWorkoutStore` maps it to/from the Core `Workout` value type).
  - `ExerciseRecord` — the persisted custom-exercise-library row.
  - `SyncedWorkoutRecord` — `Persistence/SyncedWorkoutRecord.swift`, `@Attribute(.unique) var startedAt: Date`. This is cluster 4's Apple-Health dedupe ledger; it keys on `startedAt`.
- **Stores** (protocol + SwiftData impl + in-memory fake) sit behind every model:
  `SwiftDataWorkoutStore` / `WorkoutHistoryStore`, `ExerciseLibraryStore`,
  `SwiftDataSyncedWorkoutStore`, `SettingsStore` (UserDefaults, not SwiftData).
- **Manual export** already exists (subsystem F): `SettingsModel.exportDocument(format:now:)`
  → `WorkoutHistoryExport.document(...)` → share sheet. That is v1's only
  cross-device story.
- `App/Trackit.entitlements` currently has `com.apple.developer.healthkit` only.
- The Core domain (`Workout`, `Exercise`, sets, etc.) is pure value types and is
  **frozen** — a sync layer must live entirely in the App package + `App/`.

---

## The seam a sync implementation plugs into

SwiftData + CloudKit's supported path (`ModelConfiguration(..., cloudKitDatabase:
.private("iCloud.<container>"))` + NSPersistentCloudKitContainer semantics under
the hood) means the natural insertion point is **`StoreProvisioning.swift`** —
the single place the `ModelContainer` is built. If sync is done through
SwiftData's built-in mirroring, *no store or model API changes* — the records
just start syncing. Everything downstream (`SwiftDataWorkoutStore`, the models,
the views) is unchanged because they already talk to the container through the
store protocols.

The store protocols are the isolation layer that makes this feasible:
`WorkoutHistoryStore`, `ExerciseLibraryStore`, `SyncedWorkoutStore`,
`SettingsStore`. A sync design that stays behind these protocols is
low-blast-radius; one that leaks conflict/merge concepts up into the models is
not.

---

## Acceptance tests (what "done" must prove)

Package-level, against fakes / an injected sync-state stub:

1. **Two-device convergence (simulated).** Given store A and store B backed by a
   shared fake "cloud" log, a workout completed on A appears in B's history
   after a sync tick, and vice versa.
2. **Offline-first unchanged.** With the sync layer present but "cloud"
   unreachable, every existing `WorkoutLoggerApp` test still passes and the
   logging loop never awaits sync. (Run the full suite `--no-parallel`.)
3. **Conflict resolution is deterministic.** Two edits to the same workout
   (`startedAt` collision) from two devices resolve to one defined winner per
   the rule chosen in OPEN QUESTION 3 — with a test that pins the rule.
4. **Delete propagates.** "Delete all workout data" (`SettingsModel.deleteAllWorkoutData`)
   and single-workout delete (cluster 3's `WorkoutHistoryStore.deleteWorkout(startedAt:)`)
   remove the row on the other device too — no tombstone resurrection.
5. **`SyncedWorkoutRecord` semantics survive sync.** The Apple-Health dedupe
   ledger keys on `startedAt`; confirm a synced workout doesn't get
   double-written to HealthKit from a second device (interaction with cluster 4).
6. **Library merge.** Custom exercises created independently on two devices union
   without duplicating by name (case-insensitive), matching
   `ExerciseLibraryValidation`'s existing dupe rule.

Device-only (manual, needs two real devices + iCloud accounts): actual
end-to-end sync latency, the iCloud sign-in / sign-out lifecycle, account-change
handling, and CloudKit quota behaviour.

---

## Hardware / account dependencies

- Two physical iOS devices signed into the **same** iCloud account.
- An Apple Developer account with a CloudKit container provisioned.
- `com.apple.developer.icloud-services` + `com.apple.developer.icloud-container-identifiers`
  in `App/Trackit.entitlements`, plus the iCloud + CloudKit capability in
  `project.yml`.
- CloudKit Dashboard access to inspect/reset the schema during development.
- Cannot be meaningfully verified in the Simulator or without iCloud.

---

## OPEN QUESTIONS — resolved 2026-09-15

1. **SwiftData native mirroring vs. hand-rolled CloudKit.** ✅ **Native**
   (`cloudKitDatabase:` on `ModelConfiguration`). Owner's call, weighing ~1
   week + schema fallout against multiple weeks of a hand-rolled engine.
   Direct consequence: this cluster has **no app-owned sync-transport
   object** to inject a fake into — CloudKit's own mirroring is opaque
   framework machinery. Acceptance tests 1/3 ("two-device convergence",
   "conflict resolution") therefore target the app-level code this choice
   *does* require us to write (the dedupe/merge logic replacing `.unique`,
   OPEN QUESTION 4) rather than a simulated transport; the actual
   cross-device CloudKit behaviour stays device-only, same as every other
   device-only item in this doc.
2. **What syncs?** ✅ **Completed workouts + the custom exercise library.**
   Settings (unit, HealthKit opt-in, analytics opt-in) stay in
   `UserDefaults`, untouched, per-device — the opt-ins are privacy choices
   that should not silently follow an iCloud account across devices.
3. **Conflict rule.** ✅ **Last-writer-wins by edit timestamp.** A completed
   workout is immutable once ended (conflicts only arise from cluster 3's
   post-hoc edits), and CloudKit's own record-level merge is already
   effectively last-writer-wins by server modification time — native
   mirroring gives us this for free at the transport layer. No app-level
   conflict-resolution code to write; acceptance test 3 is satisfied by this
   being the documented, device-verified behaviour rather than a unit test
   (there is nothing at the app layer to unit test — see OPEN QUESTION 1).
4. **Uniqueness without `.unique`.** ✅ Audited all three `@Attribute(.unique)`
   sites:
   - `WorkoutRecord.startedAt` — `SwiftDataWorkoutStore.save` already
     fetches by `startedAt` and updates the existing record instead of
     inserting a second one. `.unique` was redundant; removing it changes
     nothing.
   - `SyncedWorkoutRecord.startedAt` — `SwiftDataSyncedWorkoutStore.markSynced`
     already guards on `isSynced(startedAt:)` before inserting. Same:
     `.unique` was redundant.
   - `ExerciseRecord.name` — genuinely needs new logic. `add(_:)` does not
     pre-check; the case-insensitive dedupe rule lives one level up in
     `ExerciseLibraryValidation`, which cannot see another device's
     not-yet-synced state. Two devices independently adding
     case-insensitively-matching names before their first sync would land
     two raw records. Resolved by merging case-insensitive collisions at
     read time in `SwiftDataExerciseLibraryStore.all()` (union the aliases,
     return one entry) rather than mutating storage on every read — `add`/
     `update`/`delete` are unchanged; a rare not-yet-reconciled duplicate
     under a direct `update(named:)` is an accepted edge case, same style as
     `TrackitApp.knownBests`'s documented self-healing discontinuity.
   - All three models also need every attribute to be optional or carry a
     default value (a separate, unrelated CloudKit-mirroring requirement,
     not just the `.unique` removal) — added as part of this change.
5. **Migration.** ✅ No explicit one-time migration UI. Native mirroring
   uploads existing local rows automatically once `cloudKitDatabase:` is
   set on the `ModelConfiguration`. Two devices with pre-existing
   local-only data each push their own rows on first sync; OPEN QUESTION 4's
   fetch-before-insert guards (`WorkoutRecord`/`SyncedWorkoutRecord`) and
   read-time merge (`ExerciseRecord`) mean both devices' pre-sync data
   unions without loss, modulo the same near-zero-probability
   simultaneous-`startedAt`-collision edge case cluster 4 already accepted
   for the HealthKit dedupe ledger.
6. **UI surface.** ✅ Fully invisible. No sync-status indicator, no manual
   "sync now", no iCloud-account-missing state. Matches v1's offline-first
   ethos and keeps this cluster's surface area to persistence + entitlements.
7. **Interaction with the manual export.** ✅ Unchanged — kept as-is, the
   "get my data out" story regardless of sync.
8. **Entitlement / container naming.** ✅ `iCloud.com.abubakarsahi.trackit`,
   matching the bundle id `com.abubakarsahi.trackit` in `project.yml`.

---

## Effort

Largest item in v1.1. Native-mirroring route: ~1 week including the schema
constraints fallout. Hand-rolled: multiple weeks. **Mandatory `writing-plans`
pass** before any code, and its own long-lived branch. Expect the schema
constraint work (OPEN QUESTION 4) to touch cluster 4's code.

## Status

- [x] OPEN QUESTIONS resolved and written back into this spec. Done 2026-09-15.
- [ ] `writing-plans` → `docs/superpowers/plans/<date>-v1.1-cluster-7a-cloudkit-sync.md`
- [ ] implementation
- [ ] two-device manual verification
