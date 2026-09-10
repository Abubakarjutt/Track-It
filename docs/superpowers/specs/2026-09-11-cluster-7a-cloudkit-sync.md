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

## OPEN QUESTIONS (resolve before implementation)

1. **SwiftData native mirroring vs. hand-rolled CloudKit.**
   - *Native* (`cloudKitDatabase:` on `ModelConfiguration`): least code, but
     imposes constraints — every non-optional attribute needs a default or must
     become optional, `@Attribute(.unique)` is **not supported** with CloudKit
     mirroring (this directly affects `SyncedWorkoutRecord.startedAt` and
     possibly others), no cross-record uniqueness, limited migration control.
   - *Hand-rolled* (`CKRecord` sync in a dedicated sync engine behind the store
     protocols): full control, much more code, own conflict handling, own
     retry/backoff, own schema migration. Weeks of work.
   - **Decision needed**, and it dictates almost everything below.
2. **What syncs?** Completed workouts only? Also the custom-exercise library?
   Also settings (unit, opt-ins)? Settings are in UserDefaults today, not
   SwiftData — syncing them means `NSUbiquitousKeyValueStore` or moving them.
   The Apple-Health opt-in and analytics opt-in arguably should **not** sync
   (per-device privacy choices).
3. **Conflict rule.** Last-writer-wins by modification timestamp? Field-level
   merge? "A completed workout is immutable once ended, so conflicts only
   happen on post-hoc edits (cluster 3) — take the most recent edit"? Pick one
   and make it testable.
4. **Uniqueness without `.unique`.** If native mirroring is chosen,
   `SyncedWorkoutRecord`'s `@Attribute(.unique)` must go. What replaces the
   dedupe guarantee — a fetch-before-insert in `SwiftDataSyncedWorkoutStore`, a
   deterministic record id derived from `startedAt`, something else? Same
   question for any other `.unique` attribute in the schema (audit
   `WorkoutRecord` / `ExerciseRecord`).
5. **Migration.** Existing users have a local-only store. Turning on CloudKit
   changes the store description. Is there a one-time migration, and what
   happens to a user with data on two devices *before* first sync (both sets
   must survive the union)?
6. **UI surface.** Is there a sync-status indicator / a manual "sync now" / an
   iCloud-account-missing state in Settings, or is it fully invisible? The
   master spec says nothing.
7. **Interaction with the manual export.** Does export stay? (Probably yes — it's
   the "get my data out" story regardless of sync.)
8. **Entitlement / container naming.** `iCloud.com.abubakarsahi.trackit`?
   Confirm the bundle id (`com.abubakarsahi.trackit` per `project.yml`).

---

## Effort

Largest item in v1.1. Native-mirroring route: ~1 week including the schema
constraints fallout. Hand-rolled: multiple weeks. **Mandatory `writing-plans`
pass** before any code, and its own long-lived branch. Expect the schema
constraint work (OPEN QUESTION 4) to touch cluster 4's code.

## Status

- [ ] OPEN QUESTIONS resolved and written back into this spec
- [ ] `writing-plans` → `docs/superpowers/plans/<date>-v1.1-cluster-7a-cloudkit-sync.md`
- [ ] implementation
- [ ] two-device manual verification
