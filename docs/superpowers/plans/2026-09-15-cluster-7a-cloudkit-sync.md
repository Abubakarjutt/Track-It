# Cluster 7a — CloudKit Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn on SwiftData's native CloudKit mirroring for completed workouts
and the custom exercise library, with zero new UI and zero change to
package-test behaviour.

**Architecture:** Add `cloudKitDatabase:` to the on-disk `ModelConfiguration`
built by `StoreProvisioning.provisionStore`, gated behind a new optional
parameter so the package's own tests never touch real CloudKit. Remove the
three now-unsupported `@Attribute(.unique)` sites and give every attribute a
default (CloudKit mirroring's requirement). Two of those three sites are
already redundant with app-level fetch-before-insert/guard logic and need no
new code; the third (`ExerciseRecord.name`) gets a read-time case-insensitive
merge in `SwiftDataExerciseLibraryStore.all()`. Add the iCloud + CloudKit
entitlements. No sync-transport object exists to fake — native mirroring is
opaque framework machinery — so every test here targets app-level code, not
simulated cloud behaviour.

**Tech Stack:** Swift 6.0, SwiftData, CloudKit (via SwiftData mirroring only —
no direct `CloudKit`/`CKRecord` import), `xcodegen`/`project.yml`.

**Spec:** `docs/superpowers/specs/2026-09-11-cluster-7a-cloudkit-sync.md` (all
8 OPEN QUESTIONS resolved 2026-09-15 — read that section before this plan;
it's the authority this plan argues from).

## Global Constraints

- Swift 6.0 / Approachable Concurrency, `@MainActor`-by-default inference
  (App target only; the WorkoutLoggerApp package is not App-target code —
  match each file's existing isolation style, do not add annotations that
  aren't already there).
- Core (`WorkoutLoggerCore`) is frozen — nothing in this cluster touches it.
- `swift test --no-parallel` in `Packages/WorkoutLoggerApp` must stay green
  throughout (currently 281/281) — this is acceptance test 2 ("offline-first
  unchanged"), not optional.
- No new UI, no new Settings surface (OPEN QUESTION 6).
- Settings/opt-ins stay in `UserDefaults`, untouched (OPEN QUESTION 2).
- Entitlement/container id: `iCloud.com.abubakarsahi.trackit` (OPEN QUESTION 8).
- `graft/` must never be committed (already gitignored).
- Commits and the PR description end with:
  `Claude-Session: https://claude.ai/code/session_01NPXLzSUXbBwoLLFVo2hg6z`

---

### Task 1: Drop the three now-unsupported `.unique` attributes, add required defaults

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/WorkoutRecord.swift`
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/ExerciseRecord.swift`
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/SyncedWorkoutRecord.swift`
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/HealthKit/SyncedWorkoutStore.swift` (doc comment only)
- Test: no new test file — this task's proof is the *existing* suite staying
  green (see Step 3). Two tests already pin the behaviour that made `.unique`
  redundant: `SwiftDataWorkoutStoreTests.swift`'s "saving the same session
  twice updates in place" and `SyncedWorkoutStoreTests.swift`'s "the SwiftData
  store marking the same start time twice does not throw or duplicate".

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new — same public API, same behaviour. Task 3 depends on
  these three files compiling without `.unique` before it adds
  `cloudKitDatabase:` to the schema that contains them (CloudKit mirroring
  refuses to activate a schema with an unsupported `.unique` attribute
  present, so this must land first).

- [ ] **Step 1: Remove `.unique`, add defaults**

  `WorkoutRecord.swift`:
  ```swift
  @Model
  public final class WorkoutRecord {
      public var startedAt: Date = Date.distantPast
      public var endedAt: Date?
      public var payload: Data = Data()

      public init(startedAt: Date, endedAt: Date?, payload: Data) {
          self.startedAt = startedAt
          self.endedAt = endedAt
          self.payload = payload
      }
  }
  ```

  `ExerciseRecord.swift`:
  ```swift
  @Model
  public final class ExerciseRecord {
      public var name: String = ""
      public var aliases: [String] = []

      public init(name: String, aliases: [String]) {
          self.name = name
          self.aliases = aliases
      }
  }
  ```

  `SyncedWorkoutRecord.swift`:
  ```swift
  @Model
  public final class SyncedWorkoutRecord {
      public var startedAt: Date = Date.distantPast

      public init(startedAt: Date) {
          self.startedAt = startedAt
      }
  }
  ```

  The `Date.distantPast` / `""` / `[]` / `Data()` defaults are never actually
  read in practice — every real instance is built through `init`, which
  always sets every field. They exist only because CloudKit mirroring
  requires every attribute to be optional or carry a default, so the
  framework can materialize a partially-merged record. Say this in a one-line
  comment above each `@Model` (not one per field — that's noise).

- [ ] **Step 2: Fix the stale doc comment**

  In `SyncedWorkoutStore.swift`, `SwiftDataSyncedWorkoutStore`'s doc comment
  currently reads:
  > `@Attribute(.unique)` on `SyncedWorkoutRecord.startedAt` makes `markSynced`
  > idempotent

  That's no longer true (the attribute is gone) and was arguably never the
  real reason — `markSynced`'s own `guard !isSynced(startedAt:) else { return }`
  is what makes it idempotent. Replace with:
  ```swift
  /// `markSynced`'s own `isSynced` guard (below) makes it idempotent — no
  /// `@Attribute(.unique)` on `SyncedWorkoutRecord.startedAt` (CloudKit
  /// mirroring, cluster 7a, doesn't support it).
  ```

- [ ] **Step 3: Run the existing suite — this is the regression test**

  Run: `cd Packages/WorkoutLoggerApp && swift test --no-parallel`
  Expected: 281/281 still green, including the two tests named above in
  "Test:" — they already pin the exact behaviour `.unique` used to
  (redundantly) guarantee.

- [ ] **Step 4: Commit**

  ```bash
  git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/WorkoutRecord.swift \
          Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/ExerciseRecord.swift \
          Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/SyncedWorkoutRecord.swift \
          Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/HealthKit/SyncedWorkoutStore.swift
  git commit -m "feat(7a): drop @Attribute(.unique) from the three CloudKit-mirrored models"
  ```

---

### Task 2: Case-insensitive merge in `SwiftDataExerciseLibraryStore.all()`

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/ExerciseLibraryStore.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/ExerciseLibraryStoreTests.swift`

**Interfaces:**
- Consumes: `ExerciseRecord` (Task 1's version — no `.unique`).
- Produces: `SwiftDataExerciseLibraryStore.all() -> [Exercise]` — same
  signature, same sort order, but now merges same-case-insensitive-name raw
  records into one `Exercise` with the union of their aliases. `add`,
  `update`, `delete` are unchanged (they still operate on the raw,
  unmerged `records()`).

- [ ] **Step 1: Write the failing test**

  This is acceptance test 6 ("Library merge... union without duplicating by
  name (case-insensitive)"), written directly against two raw records —
  simulating what a not-yet-reconciled cross-device sync would leave behind,
  since there is no sync transport to simulate the two devices themselves:

  ```swift
  @Test("two records that only differ by case merge into one, aliases unioned")
  func caseInsensitiveDuplicatesMerge() throws {
      let (store, context) = try makeStore()
      // Two raw records a not-yet-reconciled cross-device sync could leave —
      // each device added its own before either had seen the other's row.
      context.insert(ExerciseRecord(name: "Bench Press", aliases: ["bench"]))
      context.insert(ExerciseRecord(name: "bench press", aliases: ["bp"]))
      try context.save()

      let all = store.all()

      #expect(all.count == 1)
      #expect(all.first?.name == "Bench Press")
      #expect(all.first?.aliases.sorted() == ["bench", "bp"])
  }
  ```

- [ ] **Step 2: Run test to verify it fails**

  Run: `cd Packages/WorkoutLoggerApp && swift test --filter ExerciseLibraryStoreTests`
  Expected: FAIL — `all()` currently returns 2 entries, not 1.

- [ ] **Step 3: Implement the merge**

  ```swift
  public func all() -> [Exercise] {
      var merged: [String: Exercise] = [:]  // keyed by lowercased name
      for record in records() {
          let key = record.name.lowercased()
          if let existing = merged[key] {
              merged[key] = Exercise(
                  name: existing.name,
                  aliases: Array(Set(existing.aliases + record.aliases))
              )
          } else {
              merged[key] = Exercise(name: record.name, aliases: record.aliases)
          }
      }
      return merged.values
          .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
  ```

  The first-seen record's `name` casing wins (matches `records()`'s existing
  fetch order — no explicit ordering guarantee across the merge, which is
  fine: this only matters for the sub-second race window before a first sync
  reconciles either device's next edit anyway).

- [ ] **Step 4: Run test to verify it passes, then the full suite**

  Run: `cd Packages/WorkoutLoggerApp && swift test --filter ExerciseLibraryStoreTests`
  Expected: PASS.
  Run: `swift test --no-parallel`
  Expected: 282/282 (281 + this one new test), all green — confirms the merge
  didn't change `all()`'s behavior for the non-duplicate case every other
  existing test in this file already exercises.

- [ ] **Step 5: Commit**

  ```bash
  git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/ExerciseLibraryStore.swift \
          Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/ExerciseLibraryStoreTests.swift
  git commit -m "feat(7a): merge case-insensitive duplicate exercise names at read time"
  ```

---

### Task 3: `provisionStore` gains an opt-in CloudKit container id

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/HUD/StoreProvisioning.swift`
- Modify: `App/TrackitApp.swift`
- Test: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/StoreProvisioningTests.swift`

**Interfaces:**
- Consumes: Task 1's `.unique`-free schema.
- Produces: `provisionStore(onDiskURL: URL, cloudKitContainerIdentifier: String? = nil) -> StoreAvailability`.
  The default keeps every existing call site (both package tests) unchanged
  and CloudKit-free — this is what makes acceptance test 2 ("offline-first
  unchanged... every existing test still passes") true by construction rather
  than by hoping a real CloudKit container behaves innocuously inside
  `swift test`, which has no entitlements to grant it one.

- [ ] **Step 1: Write the failing test**

  A parameter-plumbing test, not a real-CloudKit test (there is no way to
  observe CloudKit's own behavior from a package unit test — see the spec's
  OPEN QUESTION 1 resolution):

  ```swift
  @Test("passing a CloudKit container identifier still yields a ready, working container")
  func cloudKitIdentifierStillWorks() throws {
      let url = FileManager.default.temporaryDirectory
          .appending(path: "trackit-test-\(UUID().uuidString).store")
      defer { try? FileManager.default.removeItem(at: url) }

      let availability = provisionStore(
          onDiskURL: url, cloudKitContainerIdentifier: "iCloud.com.abubakarsahi.trackit"
      )
      #expect(availability.isDegraded == false)

      let context = ModelContext(availability.container)
      context.insert(WorkoutRecord(
          startedAt: Date(timeIntervalSince1970: 0), endedAt: nil, payload: Data("{}".utf8)
      ))
      try context.save()
      #expect(try context.fetchCount(FetchDescriptor<WorkoutRecord>()) == 1)
  }
  ```

- [ ] **Step 2: Run test to verify it fails**

  Run: `cd Packages/WorkoutLoggerApp && swift test --filter StoreProvisioningTests`
  Expected: FAIL — `provisionStore` doesn't take this parameter yet (compile
  error).

- [ ] **Step 3: Implement**

  ```swift
  public func provisionStore(
      onDiskURL: URL, cloudKitContainerIdentifier: String? = nil
  ) -> StoreAvailability {
      let schema = Schema([WorkoutRecord.self, ExerciseRecord.self, SyncedWorkoutRecord.self])
      let cloudKitDatabase: ModelConfiguration.CloudKitDatabase =
          cloudKitContainerIdentifier.map { .private($0) } ?? .none
      do {
          let container = try ModelContainer(
              for: schema,
              configurations: [ModelConfiguration(
                  schema: schema, url: onDiskURL, cloudKitDatabase: cloudKitDatabase
              )]
          )
          return .ready(container)
      } catch {
          // The degraded fallback is in-memory-only and CloudKit mirroring
          // requires a persistent store — this path already means "no
          // history available", so it stays cloud-free regardless of the
          // caller's identifier.
          let fallback = try! ModelContainer(
              for: schema,
              configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
          )
          return .degraded(fallback)
      }
  }
  ```

  Update the doc comment above `provisionStore` to mention the new parameter
  in one line.

- [ ] **Step 4: Wire the real identifier in `TrackitApp.init()`**

  In `App/TrackitApp.swift`, change:
  ```swift
  let availability = provisionStore(onDiskURL: storeURL)
  ```
  to:
  ```swift
  let availability = provisionStore(
      onDiskURL: storeURL, cloudKitContainerIdentifier: "iCloud.com.abubakarsahi.trackit"
  )
  ```

- [ ] **Step 5: Run test to verify it passes, then the full suite**

  Run: `swift test --filter StoreProvisioningTests`
  Expected: PASS.

  **Ruling (2026-09-15, made during execution):** the `cloudKitIdentifierStillWorks`
  test from Step 1 was run and reproducibly **crashed the whole `swift test`
  process** — an uncatchable `NSInternalInconsistencyException`
  ("bundleIdentifier != nil") thrown from CloudKit/PushKit off a background
  queue when the CloudKit-mirroring `ModelContainer` deallocated, not a normal
  test failure. An SPM test binary has no app bundle identifier for CloudKit
  to register against. This is exactly the spec's OPEN QUESTION 1 resolution
  ("there is no way to observe CloudKit's own behavior from a package unit
  test") landing as a process-fatal bug rather than an inert no-op, so the
  test was **removed**, replaced with a comment explaining why it can't
  exist. The `cloudKitContainerIdentifier` parameter's real behavior is
  verified only by the `xcodebuild` build (Task 4) and the device step.
  Run: `swift test --no-parallel`
  Expected: 282/282, all green (281 baseline + Task 2's one new test; Task 3
  adds no net test given the ruling above).

- [ ] **Step 6: Commit**

  ```bash
  git add Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/HUD/StoreProvisioning.swift \
          Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/StoreProvisioningTests.swift \
          App/TrackitApp.swift
  git commit -m "feat(7a): provisionStore takes an opt-in CloudKit container identifier"
  ```

---

### Task 4: Entitlements + `project.yml`

**Files:**
- Modify: `App/Trackit.entitlements`
- Modify: `project.yml`

**Interfaces:**
- Consumes: nothing code-level — this task only changes build configuration.
- Produces: the `Trackit` target gains the iCloud + CloudKit capability so
  the container id Task 3 wires in has an actual entitlement backing it on a
  real device (device-only to verify per the spec — a Simulator build has no
  iCloud account to actually sync with regardless of entitlements).

- [ ] **Step 1: Read the current entitlements file, then add the iCloud keys**

  `App/Trackit.entitlements` currently has only
  `com.apple.developer.healthkit`. Add:
  ```xml
  <key>com.apple.developer.icloud-services</key>
  <array>
      <string>CloudKit</string>
  </array>
  <key>com.apple.developer.icloud-container-identifiers</key>
  <array>
      <string>iCloud.com.abubakarsahi.trackit</string>
  </array>
  ```

- [ ] **Step 2: Add the CloudKit capability to `project.yml`**

  Find the `Trackit` target's `capabilities` (or equivalent xcodegen key —
  read the file first; add whichever structure the existing HealthKit
  capability already uses, mirroring its shape rather than inventing a new
  one) and add an iCloud/CloudKit entry alongside it, following whatever
  pattern `project.yml` already uses for HealthKit's capability + entitlement
  pairing.

- [ ] **Step 3: Regenerate and build**

  Run: `xcodegen generate`
  Run: `xcodebuild -project Trackit.xcodeproj -scheme Trackit -destination 'generic/platform=iOS Simulator' build`
  Expected: `** BUILD SUCCEEDED **`. A Simulator build with "Sign to Run
  Locally" does not require a real Apple Developer CloudKit container to be
  provisioned — that provisioning step (creating the container in the
  CloudKit Dashboard) is itself a device/account-only step per the spec's
  "Hardware / account dependencies" section, out of scope here. If the build
  fails specifically on entitlement/capability validation, that is real
  signal this task's `project.yml`/entitlements shape is wrong — stop and
  report the exact error rather than guessing a fix.

- [ ] **Step 4: Commit**

  ```bash
  git add App/Trackit.entitlements project.yml
  git commit -m "feat(7a): add iCloud + CloudKit capability/entitlements to the Trackit target"
  ```

---

### Task 5: Verification, two-axis code review, PR

**Files:** none new — this task is process, not code.

- [ ] **Step 1: Full verification pass**

  Run: `cd Packages/WorkoutLoggerCore && swift test` — expect 169/169
  unchanged (this cluster never touches Core).
  Run: `cd Packages/WorkoutLoggerApp && swift test --no-parallel` — expect
  282/282 green (281 + Task 2's new test; Task 3 adds no net test per its
  Step 5 ruling above).
  Run: `xcodebuild -project Trackit.xcodeproj -scheme Trackit -destination 'generic/platform=iOS Simulator' build`
  — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Two-axis code review**

  Fixed point: this branch's first commit (the OPEN QUESTIONS resolution,
  `b2a2515`, or `main`'s tip before this branch — use `git merge-base main HEAD`
  if unsure). Spec: `docs/superpowers/specs/2026-09-11-cluster-7a-cloudkit-sync.md`.
  Dispatch both axes per `mattpocock-skills:code-review`. Fold any real
  findings; judgement-call findings are noted, not necessarily changed.

- [ ] **Step 3: Tick this spec's Status checklist**

  In `docs/superpowers/specs/2026-09-11-cluster-7a-cloudkit-sync.md`: tick
  "OPEN QUESTIONS resolved" (already done), "`writing-plans`", and
  "implementation". Leave "two-device manual verification" unticked —
  explicitly device-only, deferred like every prior cluster's device step.

- [ ] **Step 4: PR, rebase-merge, sync `main`, update memory**

  Follow the same rhythm as every prior cluster (7b/7c/7e/7f): open a PR
  against `main` with the Claude-Session trailer, rebase-merge, delete the
  branch, sync local `main`, then update `phase-progress.md`, `MEMORY.md`,
  and `docs/superpowers/specs/2026-09-11-v1.1-remaining-INDEX.md` to record
  the merge — noting this closes out **every** Cluster 7 item, and that the
  device-only two-device verification (like every other cluster's device
  step) remains outstanding.

## Self-Review Notes

- **Spec coverage:** all 8 resolved OPEN QUESTIONS map to a task — 1/3
  (native mirroring, no fake transport) shapes every task's testing
  strategy; 2 (workouts+library only) bounds Task 1/2's scope; 4 (uniqueness)
  is Task 1+2; 5 (migration) needs no code — it's a consequence of Task 1-3's
  fetch-before-insert/merge logic, documented in the spec, not a separate
  task; 6 (no UI) is why there's no Task for a Settings surface; 7 (export
  unchanged) needs no task; 8 (container id) is Task 3+4.
- **Acceptance tests:** 1 and 3 (two-device convergence, conflict
  resolution) have no package-level equivalent under native mirroring — see
  OPEN QUESTION 1's resolution — and stay device-only. 2 (offline-first
  unchanged) is Task 3's whole reason for the opt-in-parameter design. 4
  (delete propagates) is unchanged app behavior, no new code, verified by
  the existing delete tests staying green. 5 (SyncedWorkoutRecord survives
  sync) is Task 1, verified by existing tests staying green. 6 (library
  merge) is Task 2's new test.
- **Risk flagged in Task 4, Step 3:** whether the Simulator build tolerates
  the new entitlements without a real provisioned CloudKit container is
  unverified until that step actually runs — if it fails, this plan's Task 4
  needs a follow-up decision (e.g., is the capability real in the connected
  Apple Developer account?), not a guessed workaround.
