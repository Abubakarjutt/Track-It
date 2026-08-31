# App Shell Skeleton + Voice Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a second SwiftPM package `WorkoutLoggerApp` that persists workouts to SwiftData and runs the full spoken-set → readback → haptic loop over the frozen `WorkoutLoggerCore` engine, plus a thin XcodeGen-generated iOS app target that wires the real Speech/TTS/haptic frameworks.

**Architecture:** `WorkoutLoggerCore` stays a pure logic package (one additive change: `Codable` on its value types). A new sibling package `WorkoutLoggerApp` holds an `@Observable` `WorkoutSessionModel` that owns a `WorkoutEngine`, a SwiftData-backed `WorkoutStore`, a pure `readbackPlan` composer, and protocol + fake collaborators for speech / voice / haptics — all covered by `swift test`. A thin `App/` Xcode target (generated from `project.yml`) contains only `@main`, one placeholder view, and the three `System*` framework wrappers.

**Tech Stack:** Swift 6, Swift Testing, SwiftData, SwiftUI, `Observation`, Speech.framework + AVFoundation + CoreHaptics (app target only), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-08-30-app-shell-skeleton-voice-pipeline-design.md`

## Global Constraints

- Swift tools version `6.0`. Swift language mode 6 (strict concurrency).
- `WorkoutLoggerCore` platforms stay `.iOS(.v17), .macOS(.v13)`. Its logic is frozen; the only permitted edit in this plan is adding `: Codable` conformances to its value types.
- `WorkoutLoggerApp` platforms are `.iOS(.v17), .macOS(.v14)` (Observation + SwiftData need macOS 14 for the `swift test` host).
- No third-party package dependencies. `WorkoutLoggerApp` depends only on `WorkoutLoggerCore` via `.package(path: "../WorkoutLoggerCore")`.
- This environment runs `swift test` but **cannot** run Xcode or `xcodebuild`. Every task except Task 1, Task 10, and Task 11 ends with `swift test` green in `Packages/WorkoutLoggerApp`. Task 3 ends with `swift test` green in `Packages/WorkoutLoggerCore`.
- Strict TDD: write the failing test, watch it fail, minimal implementation, watch it pass, commit. One vertical slice per task.
- The repo is a git repo on `main`. Commit at the end of every task.
- After the Task 1 restructure, core tests run from `Packages/WorkoutLoggerCore`, app tests from `Packages/WorkoutLoggerApp`.
- All types that touch SwiftData or `WorkoutSessionModel` in tests run on the main actor — mark those `@Suite` / `@Test` bodies `@MainActor`.

---

### Task 1: Restructure the repo into `Packages/` + `App/`

**Files:**
- Move: repo-root `Sources/`, `Tests/`, `specs/`, `CONTEXT.md`, `Package.swift` → `Packages/WorkoutLoggerCore/`
- Move: repo-root `docs/adr/` → `Packages/WorkoutLoggerCore/docs/adr/`
- Keep at repo root: `.gitignore`, `docs/superpowers/`
- Create: `Packages/WorkoutLoggerCore/` (destination dir)

**Interfaces:**
- Consumes: nothing.
- Produces: `Packages/WorkoutLoggerCore/Package.swift` — the existing core package, unchanged, at its new path. Later tasks reference it as `.package(path: "../WorkoutLoggerCore")` from `Packages/WorkoutLoggerApp/`.

- [ ] **Step 1: Create the destination directory and move the core tree with git**

```bash
cd /Users/Apple/projects/trackit
mkdir -p Packages/WorkoutLoggerCore/docs
git mv Sources Packages/WorkoutLoggerCore/Sources
git mv Tests Packages/WorkoutLoggerCore/Tests
git mv specs Packages/WorkoutLoggerCore/specs
git mv CONTEXT.md Packages/WorkoutLoggerCore/CONTEXT.md
git mv Package.swift Packages/WorkoutLoggerCore/Package.swift
git mv docs/adr Packages/WorkoutLoggerCore/docs/adr
```

- [ ] **Step 2: Verify the core package still builds and tests green at the new path**

Run: `cd Packages/WorkoutLoggerCore && swift test`
Expected: `Test run with 95 tests in 9 suites passed`.

- [ ] **Step 3: Verify nothing stale remains at the root**

Run: `cd /Users/Apple/projects/trackit && ls && git status --short`
Expected: root now shows `Packages/`, `docs/`, `.gitignore` (and `.build/` untracked). `git status` shows the renames staged, no deletions of tracked content.

- [ ] **Step 4: Commit**

```bash
cd /Users/Apple/projects/trackit
git add -A
git commit -m "Restructure: move WorkoutLoggerCore into Packages/

Pure git mv of the existing tree into Packages/WorkoutLoggerCore/ to make
room for a second package (WorkoutLoggerApp) and an App/ target. No file
contents change; docs/superpowers/ stays at the repo root.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 2: `WorkoutLoggerApp` package skeleton + `WorkoutRecord` (de-risk headless SwiftData)

**Files:**
- Create: `Packages/WorkoutLoggerApp/Package.swift`
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/WorkoutRecord.swift`
- Create: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutRecordTests.swift`

**Interfaces:**
- Consumes: `Packages/WorkoutLoggerCore` as a path dependency.
- Produces:
  - `WorkoutRecord` — `@Model final class`, `public`, `init(startedAt: Date, endedAt: Date?, payload: Data)`, stored `var startedAt: Date` (`@Attribute(.unique)`), `var endedAt: Date?`, `var payload: Data`.

- [ ] **Step 1: Write the package manifest**

`Packages/WorkoutLoggerApp/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkoutLoggerApp",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WorkoutLoggerApp", targets: ["WorkoutLoggerApp"]),
    ],
    dependencies: [
        .package(path: "../WorkoutLoggerCore"),
    ],
    targets: [
        .target(
            name: "WorkoutLoggerApp",
            dependencies: [.product(name: "WorkoutLoggerCore", package: "WorkoutLoggerCore")]
        ),
        .testTarget(
            name: "WorkoutLoggerAppTests",
            dependencies: [
                "WorkoutLoggerApp",
                .product(name: "WorkoutLoggerCore", package: "WorkoutLoggerCore"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Write the failing test**

`Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutRecordTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
@testable import WorkoutLoggerApp

@Suite("WorkoutRecord persistence")
@MainActor
struct WorkoutRecordTests {

    @Test("a record inserts into an in-memory store and reads back")
    func insertAndFetch() throws {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let started = Date(timeIntervalSince1970: 1_000)

        context.insert(WorkoutRecord(startedAt: started, endedAt: nil, payload: Data([1, 2, 3])))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<WorkoutRecord>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.startedAt == started)
        #expect(fetched.first?.endedAt == nil)
        #expect(fetched.first?.payload == Data([1, 2, 3]))
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test`
Expected: FAIL — `cannot find 'WorkoutRecord' in scope`.

- [ ] **Step 4: Write minimal implementation**

`Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/WorkoutRecord.swift`:

```swift
import Foundation
import SwiftData

/// One persisted workout: the engine's per-session `startedAt` as the natural
/// key, `endedAt` mirrored out for cheap "is a workout still open" checks, and
/// the whole `WorkoutLoggerCore.Workout` value JSON-encoded in `payload`.
@Model
public final class WorkoutRecord {
    @Attribute(.unique) public var startedAt: Date
    public var endedAt: Date?
    public var payload: Data

    public init(startedAt: Date, endedAt: Date?, payload: Data) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.payload = payload
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd Packages/WorkoutLoggerApp && swift test`
Expected: PASS — `Test run with 1 test in 1 suite passed`.

- [ ] **Step 6: Commit**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerApp
git commit -m "WorkoutLoggerApp: package skeleton + WorkoutRecord @Model

De-risks headless SwiftData first: an in-memory ModelContainer insert/fetch
round-trip under swift test on macOS, before anything is built on it.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 3: `Codable` on the core value types

**Files:**
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/Model.swift` — add `Codable` to `Exercise`, `LoadType`, `EffortMeasure`, `SetRole`, `Grouping`, `MassUnit`
- Modify: `Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift` — add `Codable` to `Workout`, `Entry`, `LoggedSet`, `PersonalRecord`
- Create: `Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutCodableTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Workout`, `Entry`, `LoggedSet`, `Exercise`, `PersonalRecord`, `LoadType`, `EffortMeasure`, `SetRole`, `Grouping`, `MassUnit` all conform to `Codable` (synthesised). JSON round-trips are stable and lossless.

- [ ] **Step 1: Write the failing test**

`Packages/WorkoutLoggerCore/Tests/WorkoutLoggerCoreTests/WorkoutCodableTests.swift`:

```swift
import Testing
import Foundation
import WorkoutLoggerCore

@Suite("Workout Codable round-trip")
struct WorkoutCodableTests {

    @Test("a workout exercising every axis survives JSON encode/decode")
    func roundTrip() throws {
        let set = LoggedSet(
            loadType: .added, effort: .reps, role: .working, grouping: .superset,
            loadKilograms: 42.5, reps: 8, durationSeconds: nil, distanceMeters: nil,
            supersetRunID: 2, loggedAt: Date(timeIntervalSince1970: 1_234),
            note: "felt heavy"
        )
        let timed = LoggedSet(
            loadType: .bodyweight, effort: .duration, role: .warmup, grouping: .straight,
            loadKilograms: nil, reps: nil, durationSeconds: 60, distanceMeters: nil,
            supersetRunID: nil, loggedAt: Date(timeIntervalSince1970: 1_300), note: nil
        )
        let workout = Workout(
            entries: [Entry(exercise: Exercise(name: "Bench Press", aliases: ["bench"]), sets: [set, timed])],
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 5_000),
            note: "morning session"
        )

        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(Workout.self, from: data)

        #expect(decoded == workout)
    }

    @Test("a personal record round-trips")
    func personalRecordRoundTrip() throws {
        let pr = PersonalRecord(exercise: Exercise(name: "Squat"), estimatedOneRepMaxKilograms: 180.25)
        let data = try JSONEncoder().encode(pr)
        #expect(try JSONDecoder().decode(PersonalRecord.self, from: data) == pr)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerCore && swift test --filter WorkoutCodableTests`
Expected: FAIL — `instance method 'encode(to:)' requires that 'Workout' conform to 'Encodable'` (or similar).

- [ ] **Step 3: Add the conformances**

In `Model.swift`, change each declaration line:

```swift
public struct Exercise: Equatable, Sendable, Codable {
```
```swift
public enum MassUnit: Equatable, Sendable, Codable {
```
```swift
public enum LoadType: Equatable, Sendable, Codable {
```
```swift
public enum EffortMeasure: Equatable, Sendable, Codable {
```
```swift
public enum SetRole: Equatable, Sendable, Codable {
```
```swift
public enum Grouping: Equatable, Sendable, Codable {
```

In `WorkoutEngine.swift`, change each declaration line:

```swift
public struct Workout: Equatable, Sendable, Codable {
```
```swift
public struct Entry: Equatable, Sendable, Codable {
```
```swift
public struct LoggedSet: Equatable, Sendable, Codable {
```
```swift
public struct PersonalRecord: Equatable, Sendable, Codable {
```

- [ ] **Step 4: Run the full core suite to verify nothing regressed**

Run: `cd Packages/WorkoutLoggerCore && swift test`
Expected: PASS — `Test run with 97 tests in 10 suites passed` (95 existing + 2 new).

- [ ] **Step 5: Commit**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerCore
git commit -m "Core: add Codable to the workout value types

Additive only — Swift synthesises Codable, no behaviour change, all existing
tests still green. Needed because the app package persists a Workout as a
JSON blob and cross-module extension conformances don't get synthesis.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 4: `SwiftDataWorkoutStore`

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/SwiftDataWorkoutStore.swift`
- Create: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/SwiftDataWorkoutStoreTests.swift`

**Interfaces:**
- Consumes: `WorkoutRecord` (Task 2); `WorkoutLoggerCore.WorkoutStore`, `Workout`, `Entry`, `LoggedSet`, `Exercise` (`Codable` from Task 3).
- Produces:
  - `SwiftDataWorkoutStore` — `public final class`, conforms to `WorkoutLoggerCore.WorkoutStore`.
    - `public init(context: ModelContext)`
    - `public func save(_ workout: Workout)` — upserts one `WorkoutRecord` keyed on `workout.startedAt`.
    - `public func history() -> [Workout]` — all records, decoded, sorted ascending by `startedAt`.
    - `public func openWorkout() -> Workout?` — the last decoded workout with `isEnded == false`, or `nil`.

- [ ] **Step 1: Write the failing test**

`Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/SwiftDataWorkoutStoreTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("SwiftDataWorkoutStore")
@MainActor
struct SwiftDataWorkoutStoreTests {

    private func makeStore() throws -> SwiftDataWorkoutStore {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return SwiftDataWorkoutStore(context: ModelContext(container))
    }

    private func workout(startedAt: TimeInterval, reps: Int, endedAt: TimeInterval? = nil) -> Workout {
        let set = LoggedSet(
            loadType: .external, effort: .reps, role: .working, grouping: .straight,
            loadKilograms: 100, reps: reps, durationSeconds: nil, distanceMeters: nil,
            supersetRunID: nil, loggedAt: Date(timeIntervalSince1970: startedAt + 10), note: nil
        )
        return Workout(
            entries: [Entry(exercise: Exercise(name: "Bench Press"), sets: [set])],
            startedAt: Date(timeIntervalSince1970: startedAt),
            endedAt: endedAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    @Test("save then history returns the workout")
    func saveAndRead() throws {
        let store = try makeStore()
        store.save(workout(startedAt: 1_000, reps: 5))

        let history = store.history()
        #expect(history.count == 1)
        #expect(history.first?.entries.first?.sets.first?.reps == 5)
    }

    @Test("saving the same session twice updates in place")
    func upsert() throws {
        let store = try makeStore()
        store.save(workout(startedAt: 1_000, reps: 5))
        store.save(workout(startedAt: 1_000, reps: 8)) // same startedAt, grown

        let history = store.history()
        #expect(history.count == 1)
        #expect(history.first?.entries.first?.sets.first?.reps == 8)
    }

    @Test("two sessions are two records, ordered by startedAt")
    func twoSessions() throws {
        let store = try makeStore()
        store.save(workout(startedAt: 2_000, reps: 3))
        store.save(workout(startedAt: 1_000, reps: 5))

        let history = store.history()
        #expect(history.map(\.startedAt) == [
            Date(timeIntervalSince1970: 1_000), Date(timeIntervalSince1970: 2_000),
        ])
    }

    @Test("openWorkout is the un-ended one, nil once every workout is ended")
    func openWorkout() throws {
        let store = try makeStore()
        store.save(workout(startedAt: 1_000, reps: 5, endedAt: 1_500))
        store.save(workout(startedAt: 2_000, reps: 5)) // open
        #expect(store.openWorkout()?.startedAt == Date(timeIntervalSince1970: 2_000))

        store.save(workout(startedAt: 2_000, reps: 5, endedAt: 2_500)) // now ended
        #expect(store.openWorkout() == nil)
        #expect(store.history().count == 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter SwiftDataWorkoutStoreTests`
Expected: FAIL — `cannot find 'SwiftDataWorkoutStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Persistence/SwiftDataWorkoutStore.swift`:

```swift
import Foundation
import SwiftData
import WorkoutLoggerCore

/// SwiftData-backed `WorkoutStore`. The engine calls `save` on every set with the
/// whole growing `Workout`; this upserts one `WorkoutRecord` per session keyed on
/// `startedAt`. Reads decode the JSON payload back into `Workout` values for the
/// pure `WorkoutLoggerCore` functions (progress, stale-check) to consume.
public final class SwiftDataWorkoutStore: WorkoutStore {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(context: ModelContext) {
        self.context = context
    }

    public func save(_ workout: Workout) {
        guard let payload = try? encoder.encode(workout) else { return }
        let key = workout.startedAt
        let descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.startedAt == key }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.payload = payload
            existing.endedAt = workout.endedAt
        } else {
            context.insert(WorkoutRecord(
                startedAt: workout.startedAt, endedAt: workout.endedAt, payload: payload
            ))
        }
        try? context.save()
    }

    public func history() -> [Workout] {
        let descriptor = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return records.compactMap { try? decoder.decode(Workout.self, from: $0.payload) }
    }

    public func openWorkout() -> Workout? {
        history().last { !$0.isEnded }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter SwiftDataWorkoutStoreTests`
Expected: PASS — 4 tests pass.

- [ ] **Step 5: Run the whole app suite**

Run: `cd Packages/WorkoutLoggerApp && swift test`
Expected: PASS — 5 tests (1 from Task 2 + 4 here).

- [ ] **Step 6: Commit**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerApp
git commit -m "WorkoutLoggerApp: SwiftDataWorkoutStore (upsert by startedAt)

save() encodes the whole Workout to a blob and upserts one WorkoutRecord
per session; history()/openWorkout() decode back to Workout values for the
pure core functions. In-memory config covers all four seams under swift test.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 5: Feedback vocabulary — protocols, cues, and fakes

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/Feedback.swift`
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/Fakes.swift`
- Create: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/FakesTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum ReadbackPlan: Equatable, Sendable { case speak(String); case earcon }`
  - `enum HapticCue: Equatable, Sendable { case logged, notCaught, personalRecord, restReached, none }`
  - `protocol TranscriptSource: AnyObject { func beginUtterance(); func endUtterance() async throws -> [String] }`
  - `protocol ReadbackVoice: AnyObject { func perform(_ plan: ReadbackPlan) }`
  - `protocol Haptics: AnyObject { func play(_ cue: HapticCue) }`
  - `final class ScriptedTranscriptSource: TranscriptSource` — `init(_ queue: [[String]])`; `var throwWhenExhausted = false`; `private(set) var beganCount: Int`; dequeues one `[String]` per `endUtterance()`, returns `[]` when empty (or throws `ScriptedTranscriptSource.Failure.exhausted` if `throwWhenExhausted`).
  - `final class SpyReadbackVoice: ReadbackVoice` — `init()`; `private(set) var performed: [ReadbackPlan]`.
  - `final class SpyHaptics: Haptics` — `init()`; `private(set) var played: [HapticCue]`.

- [ ] **Step 1: Write the failing test**

`Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/FakesTests.swift`:

```swift
import Testing
@testable import WorkoutLoggerApp

@Suite("Fakes")
struct FakesTests {

    @Test("scripted transcript source dequeues utterances in order, then empties")
    func scriptedDequeue() async throws {
        let source = ScriptedTranscriptSource([["start workout"], ["bench 100 for 5"]])

        source.beginUtterance()
        let first = try await source.endUtterance()
        let second = try await source.endUtterance()
        let third = try await source.endUtterance()

        #expect(first == ["start workout"])
        #expect(second == ["bench 100 for 5"])
        #expect(third == [])
        #expect(source.beganCount == 1)
    }

    @Test("scripted source can be told to throw once exhausted")
    func scriptedThrows() async {
        let source = ScriptedTranscriptSource([])
        source.throwWhenExhausted = true

        await #expect(throws: ScriptedTranscriptSource.Failure.self) {
            try await source.endUtterance()
        }
    }

    @Test("spies record what they were asked to do")
    func spiesRecord() {
        let voice = SpyReadbackVoice()
        let haptics = SpyHaptics()

        voice.perform(.speak("hi"))
        voice.perform(.earcon)
        haptics.play(.logged)

        #expect(voice.performed == [.speak("hi"), .earcon])
        #expect(haptics.played == [.logged])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter FakesTests`
Expected: FAIL — `cannot find 'ScriptedTranscriptSource' in scope`.

- [ ] **Step 3: Write the vocabulary and protocols**

`Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/Feedback.swift`:

```swift
import Foundation

/// What the app should say (or not say) back after an utterance.
public enum ReadbackPlan: Equatable, Sendable {
    case speak(String)
    case earcon
}

/// The distinct haptic patterns the session fires. `none` means "no haptic".
public enum HapticCue: Equatable, Sendable {
    case logged
    case notCaught
    case personalRecord
    case restReached
    case none
}

/// Push-to-talk speech capture. `beginUtterance` on press, `endUtterance` on
/// release yields the recogniser's final n-best hypotheses (best first).
public protocol TranscriptSource: AnyObject {
    func beginUtterance()
    func endUtterance() async throws -> [String]
}

/// Speaks a readback plan (or plays the earcon tone).
public protocol ReadbackVoice: AnyObject {
    func perform(_ plan: ReadbackPlan)
}

/// Plays one of the fixed haptic patterns.
public protocol Haptics: AnyObject {
    func play(_ cue: HapticCue)
}
```

`Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/Fakes.swift`:

```swift
import Foundation

/// A `TranscriptSource` that replays a fixed script — one entry per
/// `endUtterance()`. Used by tests and SwiftUI previews.
public final class ScriptedTranscriptSource: TranscriptSource {
    public enum Failure: Error { case exhausted }

    private var queue: [[String]]
    public var throwWhenExhausted = false
    public private(set) var beganCount = 0

    public init(_ queue: [[String]]) {
        self.queue = queue
    }

    public func beginUtterance() {
        beganCount += 1
    }

    public func endUtterance() async throws -> [String] {
        guard !queue.isEmpty else {
            if throwWhenExhausted { throw Failure.exhausted }
            return []
        }
        return queue.removeFirst()
    }
}

/// Records every readback plan it is handed.
public final class SpyReadbackVoice: ReadbackVoice {
    public private(set) var performed: [ReadbackPlan] = []
    public init() {}
    public func perform(_ plan: ReadbackPlan) { performed.append(plan) }
}

/// Records every haptic cue it is handed.
public final class SpyHaptics: Haptics {
    public private(set) var played: [HapticCue] = []
    public init() {}
    public func play(_ cue: HapticCue) { played.append(cue) }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter FakesTests`
Expected: PASS — 3 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerApp
git commit -m "WorkoutLoggerApp: feedback vocabulary, collaborator protocols, fakes

ReadbackPlan / HapticCue enums; TranscriptSource / ReadbackVoice / Haptics
protocols; ScriptedTranscriptSource + SpyReadbackVoice + SpyHaptics for
tests and previews.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 6: `readbackPlan` — the pure spoken-sentence composer

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Readback/ReadbackComposer.swift`
- Create: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/ReadbackComposerTests.swift`

**Interfaces:**
- Consumes: `WorkoutLoggerCore.ParseResult`, `ParsedSet`, `ReadbackStyle`, `Exercise`, `MassUnit`, `Command`; `ReadbackPlan` (Task 5).
- Produces:
  - `public func readbackPlan(for result: ParseResult, style: ReadbackStyle, exerciseName: String?) -> ReadbackPlan`
    - `style == .earcon` → `.earcon`.
    - `result` is `.command` → `.earcon`.
    - `result` is `.lowConfidence` → `.speak("Didn't catch that.")`.
    - `result` is `.announcement(e)` → `.speak("\(e.name).")` (both styles).
    - `result` is `.set(s)`, `style == .terse` → `.speak(<terse body>)`.
    - `result` is `.set(s)`, `style == .full` → `.speak("Logged. " + <"name, " if exerciseName> + <full body> + ".")`.
    - Bodies, using the spoken `s.load` / `s.loadUnit` (not kilograms conversion):
      - reps set with load: terse `"<load> for <reps>"`, full `"<load> <unitWord> for <reps> reps"`
      - reps set, no load: terse `"<reps> reps"`, full `"<reps> reps"`
      - duration: terse `"<seconds> seconds"`, full `"<seconds> seconds"`
      - distance: terse `"<meters> meters"`, full `"<meters> meters"`
    - `unitWord`: `.kilograms` → `"kilograms"`, `.pounds` → `"pounds"`; missing unit → `"kilograms"`.
    - number formatting: whole values render without a decimal (`100`, not `100.0`); fractional values keep it (`102.5`).

- [ ] **Step 1: Write the failing test**

`Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/ReadbackComposerTests.swift`:

```swift
import Testing
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("Readback composer")
struct ReadbackComposerTests {

    private func repsSet(load: Double?, unit: MassUnit? = .kilograms, reps: Int) -> ParseResult {
        .set(ParsedSet(
            loadType: load == nil ? .bodyweight : .external,
            effort: .reps, role: .working, grouping: .straight,
            load: load, loadUnit: load == nil ? nil : unit, reps: reps
        ))
    }

    @Test("full readback of a loaded set names the exercise and spells it out")
    func fullLoaded() {
        let plan = readbackPlan(
            for: repsSet(load: 100, reps: 5), style: .full, exerciseName: "Bench Press"
        )
        #expect(plan == .speak("Logged. Bench Press, 100 kilograms for 5 reps."))
    }

    @Test("terse readback of a loaded set is just the numbers")
    func terseLoaded() {
        let plan = readbackPlan(for: repsSet(load: 100, reps: 5), style: .terse, exerciseName: nil)
        #expect(plan == .speak("100 for 5"))
    }

    @Test("a spoken pounds unit is read back in pounds")
    func poundsUnit() {
        let plan = readbackPlan(
            for: repsSet(load: 225, unit: .pounds, reps: 3), style: .full, exerciseName: "Squat"
        )
        #expect(plan == .speak("Logged. Squat, 225 pounds for 3 reps."))
    }

    @Test("a fractional load keeps its decimal")
    func fractionalLoad() {
        let plan = readbackPlan(
            for: repsSet(load: 102.5, reps: 2), style: .terse, exerciseName: nil
        )
        #expect(plan == .speak("102.5 for 2"))
    }

    @Test("terse readback of a bodyweight set")
    func terseBodyweight() {
        let plan = readbackPlan(for: repsSet(load: nil, reps: 12), style: .terse, exerciseName: nil)
        #expect(plan == .speak("12 reps"))
    }

    @Test("full readback of a duration set")
    func fullDuration() {
        let set = ParseResult.set(ParsedSet(
            loadType: .bodyweight, effort: .duration, role: .working, grouping: .straight,
            durationSeconds: 60
        ))
        #expect(readbackPlan(for: set, style: .full, exerciseName: "Plank") == .speak("Logged. Plank, 60 seconds."))
    }

    @Test("an announcement reads the exercise name")
    func announcement() {
        let plan = readbackPlan(
            for: .announcement(Exercise(name: "Deadlift")), style: .full, exerciseName: nil
        )
        #expect(plan == .speak("Deadlift."))
    }

    @Test("a low-confidence result asks for a repeat")
    func lowConfidence() {
        let plan = readbackPlan(
            for: .lowConfidence(reason: .unrecognisedExercise, bestGuesses: []),
            style: .full, exerciseName: nil
        )
        #expect(plan == .speak("Didn't catch that."))
    }

    @Test("earcon style always yields an earcon")
    func earconStyle() {
        #expect(readbackPlan(for: repsSet(load: 100, reps: 5), style: .earcon, exerciseName: "X") == .earcon)
    }

    @Test("a command yields an earcon")
    func command() {
        #expect(readbackPlan(for: .command(.undo), style: .terse, exerciseName: nil) == .earcon)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter ReadbackComposerTests`
Expected: FAIL — `cannot find 'readbackPlan' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Readback/ReadbackComposer.swift`:

```swift
import Foundation
import WorkoutLoggerCore

/// Turns a parser result + a chosen `ReadbackStyle` into the concrete thing the
/// app says. Pure. Speaks the set's values *as spoken* (the parser's `load` /
/// `loadUnit`), so "225 pounds" is read back in pounds. Unit-preference
/// conversion is a later polish, not needed to confirm an utterance.
public func readbackPlan(
    for result: ParseResult,
    style: ReadbackStyle,
    exerciseName: String?
) -> ReadbackPlan {
    if style == .earcon { return .earcon }

    switch result {
    case .command:
        return .earcon
    case .lowConfidence:
        return .speak("Didn't catch that.")
    case .announcement(let exercise):
        return .speak("\(exercise.name).")
    case .set(let set):
        switch style {
        case .earcon:
            return .earcon
        case .terse:
            return .speak(terseBody(set))
        case .full:
            let lead = exerciseName.map { "\($0), " } ?? ""
            return .speak("Logged. \(lead)\(fullBody(set)).")
        }
    }
}

private func terseBody(_ set: ParsedSet) -> String {
    switch set.effort {
    case .reps:
        if let load = set.load, let reps = set.reps {
            return "\(number(load)) for \(reps)"
        }
        return "\(set.reps ?? 0) reps"
    case .duration:
        return "\(set.durationSeconds ?? 0) seconds"
    case .distance:
        return "\(number(set.distanceMeters ?? 0)) meters"
    }
}

private func fullBody(_ set: ParsedSet) -> String {
    switch set.effort {
    case .reps:
        if let load = set.load, let reps = set.reps {
            return "\(number(load)) \(unitWord(set.loadUnit)) for \(reps) reps"
        }
        return "\(set.reps ?? 0) reps"
    case .duration:
        return "\(set.durationSeconds ?? 0) seconds"
    case .distance:
        return "\(number(set.distanceMeters ?? 0)) meters"
    }
}

private func unitWord(_ unit: MassUnit?) -> String {
    switch unit {
    case .pounds: return "pounds"
    case .kilograms, .none: return "kilograms"
    }
}

private func number(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter ReadbackComposerTests`
Expected: PASS — 10 tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerApp
git commit -m "WorkoutLoggerApp: readbackPlan composer (pure)

Maps a ParseResult + ReadbackStyle to .speak(String) / .earcon. Speaks the
set as spoken (parser load + unit), full form names the exercise, terse is
just the numbers.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 7: `WorkoutSessionModel` — lifecycle, logging, readback verbosity

**Files:**
- Create: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift`
- Create: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift`

**Interfaces:**
- Consumes: `WorkoutLoggerCore` (`WorkoutEngine`, `Workout`, `Exercise`, `ExerciseLibrary`, `MassUnit`, `PersonalRecord`, `parse`, `postProcess`, `readbackStyle`, `WorkoutContext`); `TranscriptSource`, `ReadbackVoice`, `Haptics`, `HapticCue`, `ReadbackPlan` (Task 5); `readbackPlan` (Task 6); `SwiftDataWorkoutStore` only in tests.
- Produces:
  - `@MainActor @Observable public final class WorkoutSessionModel`
    - `public init(engine: WorkoutEngine, transcriptSource: TranscriptSource, readbackVoice: ReadbackVoice, haptics: Haptics, library: ExerciseLibrary, unit: MassUnit = .kilograms, capReadbackAtEarcon: Bool = false, now: @escaping () -> Date = Date.init)`
    - `public private(set) var workout: Workout?`
    - `public private(set) var personalRecords: [PersonalRecord]`
    - `public private(set) var restStartedAt: Date?`
    - `public private(set) var restElapsed: TimeInterval`
    - `public private(set) var isListening: Bool`
    - `public private(set) var tapSelectCandidates: [Exercise]?`
    - `public private(set) var lastReadback: ReadbackPlan?`
    - `public func pressed()`
    - `public func released() async`
    - `public func tick()` — recompute `restElapsed`; fire `.restReached` once per rest period (used by Task 9, present from here)
    - `public func resolveTapSelect(_ exercise: Exercise)` — (used by Task 8, present from here as a stub that clears candidates and re-applies)

- [ ] **Step 1: Write the failing test**

`Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
import WorkoutLoggerCore
@testable import WorkoutLoggerApp

@Suite("WorkoutSessionModel")
@MainActor
struct WorkoutSessionModelTests {

    private static let bench = Exercise(name: "Bench Press", aliases: ["bench"])
    private static let library = ExerciseLibrary([bench])

    private struct Rig {
        let model: WorkoutSessionModel
        let source: ScriptedTranscriptSource
        let voice: SpyReadbackVoice
        let haptics: SpyHaptics
    }

    private func makeRig(
        script: [[String]],
        capAtEarcon: Bool = false,
        knownBests: [String: Double] = [:],
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }
    ) throws -> Rig {
        let container = try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let engine = WorkoutEngine(
            store: store, library: Self.library, knownBests: knownBests, now: now
        )
        let source = ScriptedTranscriptSource(script)
        let voice = SpyReadbackVoice()
        let haptics = SpyHaptics()
        let model = WorkoutSessionModel(
            engine: engine, transcriptSource: source, readbackVoice: voice,
            haptics: haptics, library: Self.library, capReadbackAtEarcon: capAtEarcon, now: now
        )
        return Rig(model: model, source: source, voice: voice, haptics: haptics)
    }

    private func say(_ rig: Rig) async {
        rig.model.pressed()
        await rig.model.released()
    }

    @Test("a start-workout utterance opens a workout")
    func startsWorkout() async throws {
        let rig = try makeRig(script: [["start workout"]])
        await say(rig)
        #expect(rig.model.workout != nil)
        #expect(rig.model.workout?.isEnded == false)
    }

    @Test("a spoken set is logged, fires the logged haptic, and reads back full the first time")
    func firstSet() async throws {
        let rig = try makeRig(script: [["start workout"], ["bench 100 for 5"]])
        await say(rig) // start
        await say(rig) // bench 100 for 5

        #expect(rig.model.workout?.entries.first?.exercise == Self.bench)
        #expect(rig.model.workout?.entries.first?.sets.count == 1)
        #expect(rig.haptics.played.contains(.logged))
        #expect(rig.model.lastReadback == .speak("Logged. Bench Press, 100 kilograms for 5 reps."))
    }

    @Test("the second set of the same exercise reads back terse")
    func secondSetTerse() async throws {
        let rig = try makeRig(script: [
            ["start workout"], ["bench 100 for 5"], ["bench 100 for 5"],
        ])
        await say(rig); await say(rig); await say(rig)

        #expect(rig.model.workout?.entries.first?.sets.count == 2)
        #expect(rig.model.lastReadback == .speak("100 for 5"))
    }

    @Test("capReadbackAtEarcon makes every readback an earcon")
    func earconCap() async throws {
        let rig = try makeRig(
            script: [["start workout"], ["bench 100 for 5"]], capAtEarcon: true
        )
        await say(rig); await say(rig)
        #expect(rig.model.lastReadback == .earcon)
    }

    @Test("released() resets isListening even when the source throws")
    func throwingSourceResetsListening() async throws {
        let rig = try makeRig(script: [])
        rig.source.throwWhenExhausted = true
        rig.model.pressed()
        #expect(rig.model.isListening == true)
        await rig.model.released()
        #expect(rig.model.isListening == false)
        #expect(rig.model.workout == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSessionModelTests`
Expected: FAIL — `cannot find 'WorkoutSessionModel' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift`:

```swift
import Foundation
import Observation
import WorkoutLoggerCore

/// The single object the view layer binds to. Owns a `WorkoutEngine`, forwards
/// spoken utterances into it, copies its state out into observed properties, and
/// drives readback + haptics from what the parser produced.
@MainActor
@Observable
public final class WorkoutSessionModel {
    public private(set) var workout: Workout?
    public private(set) var personalRecords: [PersonalRecord] = []
    public private(set) var restStartedAt: Date?
    public private(set) var restElapsed: TimeInterval = 0
    public private(set) var isListening = false
    public private(set) var tapSelectCandidates: [Exercise]?
    public private(set) var lastReadback: ReadbackPlan?

    @ObservationIgnored private let engine: WorkoutEngine
    @ObservationIgnored private let transcriptSource: TranscriptSource
    @ObservationIgnored private let readbackVoice: ReadbackVoice
    @ObservationIgnored private let haptics: Haptics
    @ObservationIgnored private let library: ExerciseLibrary
    @ObservationIgnored private let unit: MassUnit
    @ObservationIgnored private let capReadbackAtEarcon: Bool
    @ObservationIgnored private let now: () -> Date

    @ObservationIgnored private var announcedThisWorkout: Set<String> = []
    @ObservationIgnored private var lastTranscript = ""
    @ObservationIgnored private var restReachedFired = false

    public init(
        engine: WorkoutEngine,
        transcriptSource: TranscriptSource,
        readbackVoice: ReadbackVoice,
        haptics: Haptics,
        library: ExerciseLibrary,
        unit: MassUnit = .kilograms,
        capReadbackAtEarcon: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.engine = engine
        self.transcriptSource = transcriptSource
        self.readbackVoice = readbackVoice
        self.haptics = haptics
        self.library = library
        self.unit = unit
        self.capReadbackAtEarcon = capReadbackAtEarcon
        self.now = now
        syncFromEngine()
    }

    public func pressed() {
        transcriptSource.beginUtterance()
        isListening = true
    }

    public func released() async {
        isListening = false
        let hypotheses: [String]
        do {
            hypotheses = try await transcriptSource.endUtterance()
        } catch {
            return
        }
        apply(hypotheses)
    }

    public func resolveTapSelect(_ exercise: Exercise) {
        guard tapSelectCandidates != nil else { return }
        tapSelectCandidates = nil
        apply([rewrite(lastTranscript, toName: exercise.name)])
    }

    public func tick() {
        guard let startedAt = restStartedAt else {
            restElapsed = 0
            return
        }
        restElapsed = now().timeIntervalSince(startedAt)
        if engine.isRestTargetReached, !restReachedFired {
            restReachedFired = true
            haptics.play(.restReached)
        }
    }

    // MARK: - Applying an utterance

    private func apply(_ hypotheses: [String]) {
        let transcript = postProcess(hypotheses, library: library)
        lastTranscript = transcript
        let results = parse(transcript, context: WorkoutContext(unit: unit), library: library)

        if results.contains(where: { isStartWorkout($0) }) {
            announcedThisWorkout = []
        }

        let setsBefore = totalSetCount(workout)
        let prBefore = engine.personalRecords.count

        engine.hear(hypotheses)
        syncFromEngine()

        let setsAfter = totalSetCount(workout)
        let loggedASet = setsAfter > setsBefore

        fireHaptic(results: results, loggedASet: loggedASet, prGrew: engine.personalRecords.count > prBefore)
        speakReadback(results: results)
        captureTapSelect(results: results)

        if loggedASet { restReachedFired = false }
    }

    private func fireHaptic(results: [ParseResult], loggedASet: Bool, prGrew: Bool) {
        let cue: HapticCue
        if prGrew {
            cue = .personalRecord
        } else if loggedASet {
            cue = .logged
        } else if results.contains(where: { isLowConfidence($0) }) {
            cue = .notCaught
        } else {
            cue = .none
        }
        if cue != .none { haptics.play(cue) }
    }

    private func speakReadback(results: [ParseResult]) {
        guard let salient = salientResult(results) else { return }
        let name = exerciseName(for: salient, in: results)
        let style = readbackStyle(
            for: salient,
            isNewExercise: consumeIsNewExercise(for: salient, in: results),
            capAtEarcon: capReadbackAtEarcon
        )
        let plan = readbackPlan(for: salient, style: style, exerciseName: name)
        lastReadback = plan
        readbackVoice.perform(plan)
    }

    private func captureTapSelect(results: [ParseResult]) {
        for case .lowConfidence(_, let candidates) in results {
            tapSelectCandidates = candidates
            return
        }
    }

    private func syncFromEngine() {
        workout = engine.workout
        personalRecords = engine.personalRecords
        restStartedAt = engine.restStartedAt
    }

    // MARK: - Small helpers

    private func totalSetCount(_ workout: Workout?) -> Int {
        workout?.entries.reduce(0) { $0 + $1.sets.count } ?? 0
    }

    private func salientResult(_ results: [ParseResult]) -> ParseResult? {
        results.first { isSet($0) }
            ?? results.first { isAnnouncement($0) }
            ?? results.first { isLowConfidence($0) }
    }

    private func exerciseName(for salient: ParseResult, in results: [ParseResult]) -> String? {
        for case .announcement(let exercise) in results { return exercise.name }
        if isAnnouncement(salient), case .announcement(let exercise) = salient { return exercise.name }
        return workout?.entries.last?.exercise.name
    }

    private func consumeIsNewExercise(for salient: ParseResult, in results: [ParseResult]) -> Bool {
        guard let name = exerciseName(for: salient, in: results) else { return true }
        let isNew = !announcedThisWorkout.contains(name)
        announcedThisWorkout.insert(name)
        return isNew
    }

    /// Replaces the leading name span (everything before the first all-digit
    /// token) with `name`, keeping the numeric tail. "skuat 100 for 5" -> "Squat 100 for 5".
    private func rewrite(_ transcript: String, toName name: String) -> String {
        let tokens = transcript.split(separator: " ").map(String.init)
        guard let firstNumber = tokens.firstIndex(where: { Int($0) != nil }) else { return name }
        return ([name] + tokens[firstNumber...]).joined(separator: " ")
    }

    private func isSet(_ r: ParseResult) -> Bool { if case .set = r { return true }; return false }
    private func isAnnouncement(_ r: ParseResult) -> Bool { if case .announcement = r { return true }; return false }
    private func isLowConfidence(_ r: ParseResult) -> Bool { if case .lowConfidence = r { return true }; return false }
    private func isStartWorkout(_ r: ParseResult) -> Bool {
        if case .command(.startWorkout) = r { return true }; return false
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSessionModelTests`
Expected: PASS — 5 tests pass.

- [ ] **Step 5: Run the whole app suite**

Run: `cd Packages/WorkoutLoggerApp && swift test`
Expected: PASS — all suites green.

- [ ] **Step 6: Commit**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerApp
git commit -m "WorkoutLoggerApp: WorkoutSessionModel — lifecycle, logging, readback verbosity

@Observable @MainActor model owns a WorkoutEngine, forwards utterances,
snapshot-copies engine state, and drives the logged haptic + full/terse
readback off the re-derived parse results. tick()/resolveTapSelect present
as seams for the next two tasks.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 8: `WorkoutSessionModel` — parse failure, personal record, tap-select

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift` — add a nested `@Suite` or more `@Test`s
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift` — only if a test exposes a gap; the Task 7 implementation already covers `.notCaught`, `.personalRecord`, and `tapSelectCandidates`, so expect this task to be test-only plus a small `rewrite` fix if needed.

**Interfaces:**
- Consumes: everything from Task 7.
- Produces: no new public surface. Confirms `tapSelectCandidates`, `.notCaught`, `.personalRecord`, and `resolveTapSelect` behaviour.

- [ ] **Step 1: Write the failing tests**

Append to `WorkoutSessionModelTests.swift` (inside the existing `struct`, reusing `makeRig` / `say`):

```swift
    @Test("an unparseable utterance fires notCaught, offers candidates, logs nothing")
    func parseFailure() async throws {
        let rig = try makeRig(script: [["start workout"], ["flurbo"]])
        await say(rig); await say(rig)

        #expect(rig.haptics.played.contains(.notCaught))
        #expect(rig.model.tapSelectCandidates != nil)
        #expect(rig.model.workout?.entries.isEmpty == true)
    }

    @Test("resolveTapSelect logs the set against the chosen exercise and clears candidates")
    func tapSelectResolution() async throws {
        // "bench pruss 100 for 5" — close enough to resolve but below the auto-log bar
        let rig = try makeRig(script: [["start workout"], ["bench pruss 100 for 5"]])
        await say(rig); await say(rig)
        try #require(rig.model.tapSelectCandidates?.isEmpty == false)

        rig.model.resolveTapSelect(Self.bench)

        #expect(rig.model.tapSelectCandidates == nil)
        #expect(rig.model.workout?.entries.first?.exercise == Self.bench)
        #expect(rig.model.workout?.entries.first?.sets.first?.reps == 5)
    }

    @Test("a set that beats the known best fires the personalRecord haptic")
    func personalRecord() async throws {
        // knownBests below the e1RM of 100x5 (Epley: 100 * 35 / 30 = 116.67)
        let rig = try makeRig(
            script: [["start workout"], ["bench 100 for 5"]],
            knownBests: ["Bench Press": 100]
        )
        await say(rig); await say(rig)

        #expect(rig.haptics.played.contains(.personalRecord))
        #expect(rig.model.personalRecords.count == 1)
    }

    @Test("a personal record takes readback priority over the logged haptic")
    func prReplacesLoggedHaptic() async throws {
        let rig = try makeRig(
            script: [["start workout"], ["bench 100 for 5"]],
            knownBests: ["Bench Press": 100]
        )
        await say(rig); await say(rig)

        // exactly one feedback haptic for the set utterance, and it's the PR one
        #expect(rig.haptics.played == [.personalRecord])
    }
```

- [ ] **Step 2: Run tests to verify they fail (or reveal a gap)**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSessionModelTests`
Expected: `parseFailure`, `personalRecord`, `prReplacesLoggedHaptic` PASS immediately (Task 7 covers them). `tapSelectResolution` may FAIL on the `rewrite` handling if `"bench pruss 100 for 5"` post-processes to a form whose leading span isn't cleanly before the first digit — inspect the failure message.

- [ ] **Step 3: Fix `rewrite` only if `tapSelectResolution` failed**

If the failure shows `rewrite` produced the wrong string, make it drop any leading non-numeric tokens and keep from the first number, which the Task 7 version already does — but guard the empty-tail case:

```swift
    private func rewrite(_ transcript: String, toName name: String) -> String {
        let tokens = transcript.split(separator: " ").map(String.init)
        guard let firstNumber = tokens.firstIndex(where: { Int($0) != nil }),
              firstNumber < tokens.count else { return name }
        return ([name] + tokens[firstNumber...]).joined(separator: " ")
    }
```

If `tapSelectResolution` passed in Step 2, skip this step.

- [ ] **Step 4: Run the whole app suite**

Run: `cd Packages/WorkoutLoggerApp && swift test`
Expected: PASS — all suites green.

- [ ] **Step 5: Commit**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerApp
git commit -m "WorkoutLoggerApp: session model — parse failure, PR, tap-select coverage

Pins notCaught on unparseable input, personalRecord priority over logged,
and resolveTapSelect logging against the chosen exercise.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 9: `WorkoutSessionModel` — rest tick

**Files:**
- Modify: `Packages/WorkoutLoggerApp/Tests/WorkoutLoggerAppTests/WorkoutSessionModelTests.swift` — add rest-tick tests
- Modify: `Packages/WorkoutLoggerApp/Sources/WorkoutLoggerApp/Session/WorkoutSessionModel.swift` — only if a test reveals a gap; `tick()` from Task 7 should already satisfy these.

**Interfaces:**
- Consumes: everything from Task 7; `WorkoutEngine.isRestTargetReached`, `restStartedAt`.
- Produces: no new public surface. Confirms `tick()` recomputes `restElapsed` and fires `.restReached` exactly once per rest period.

- [ ] **Step 1: Write the failing tests**

Append to `WorkoutSessionModelTests.swift`. These use a mutable clock:

```swift
    @Test("tick fires restReached once after the rest target passes, then not again")
    func restReachedOnce() async throws {
        var clock = Date(timeIntervalSince1970: 1_000)
        let rig = try makeRig(
            script: [["start workout"], ["bench 100 for 5"]],
            now: { clock }
        )
        await say(rig) // start (clock 1000)
        await say(rig) // set logged — rest starts at 1000, default target 120s

        clock = Date(timeIntervalSince1970: 1_030) // 30s elapsed
        rig.model.tick()
        #expect(rig.model.restElapsed == 30)
        #expect(rig.haptics.played.contains(.restReached) == false)

        clock = Date(timeIntervalSince1970: 1_125) // 125s elapsed, past 120
        rig.model.tick()
        rig.model.tick() // second tick must not re-fire
        #expect(rig.haptics.played.filter { $0 == .restReached }.count == 1)
    }

    @Test("a new set resets the rest-reached latch")
    func latchResetsPerSet() async throws {
        var clock = Date(timeIntervalSince1970: 1_000)
        let rig = try makeRig(
            script: [["start workout"], ["bench 100 for 5"], ["bench 100 for 5"]],
            now: { clock }
        )
        await say(rig) // start
        await say(rig) // set 1, rest starts 1000

        clock = Date(timeIntervalSince1970: 1_130)
        rig.model.tick() // fires restReached (1st)

        await say(rig) // set 2, rest restarts at 1130, latch cleared
        clock = Date(timeIntervalSince1970: 1_260) // 130s after 1130
        rig.model.tick() // fires restReached (2nd)

        #expect(rig.haptics.played.filter { $0 == .restReached }.count == 2)
    }
```

- [ ] **Step 2: Run tests to verify they pass or reveal a gap**

Run: `cd Packages/WorkoutLoggerApp && swift test --filter WorkoutSessionModelTests`
Expected: both PASS if the Task 7 `tick()` and the `if loggedASet { restReachedFired = false }` line are correct. If `latchResetsPerSet` fails because the second set's `hear` didn't restart `restStartedAt`, confirm the engine auto-starts rest on each set (it does, via `restStartedAt = set.loggedAt`) and that `syncFromEngine()` copies it — add `restStartedAt = engine.restStartedAt` to `syncFromEngine` if missing.

- [ ] **Step 3: Apply the fix only if a test failed**

If `restElapsed` was stale, ensure `tick()` reads `now()` fresh (Task 7 version does). If the latch didn't reset, the fix is the already-present line in `apply`:

```swift
        if loggedASet { restReachedFired = false }
```

Confirm it is there and after `syncFromEngine()`.

- [ ] **Step 4: Run the whole app suite**

Run: `cd Packages/WorkoutLoggerApp && swift test`
Expected: PASS — all suites green.

- [ ] **Step 5: Commit**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerApp
git commit -m "WorkoutLoggerApp: session model — rest tick + restReached latch

tick() recomputes restElapsed off the injected clock and fires .restReached
exactly once per rest period; a new set clears the latch.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 10: Thin iOS app target (`App/` + `project.yml`)

**Files:**
- Create: `project.yml`
- Create: `App/TrackitApp.swift`
- Create: `App/Views/RootView.swift`
- Create: `App/System/SystemSpeechRecognizer.swift`
- Create: `App/System/SystemReadbackVoice.swift`
- Create: `App/System/SystemHaptics.swift`
- Create: `App/Info.plist`
- Create: `App/Trackit.entitlements`

**Interfaces:**
- Consumes: `WorkoutLoggerApp` (`WorkoutSessionModel`, `WorkoutRecord`, `SwiftDataWorkoutStore`, `TranscriptSource`, `ReadbackVoice`, `Haptics`, `ReadbackPlan`, `HapticCue`); `WorkoutLoggerCore` (`WorkoutEngine`, `ExerciseLibrary`, `Exercise`).
- Produces: an Xcode project (after the user runs `xcodegen`) with one app target `Trackit` and one empty `TrackitTests` target. **Not `swift test`-covered** — this task's verification is "the files are complete and internally consistent"; the user runs `xcodegen && open Trackit.xcodeproj` and builds.

- [ ] **Step 1: Write `project.yml`**

```yaml
name: Trackit
options:
  bundleIdPrefix: com.abubakarsahi
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
packages:
  WorkoutLoggerCore:
    path: Packages/WorkoutLoggerCore
  WorkoutLoggerApp:
    path: Packages/WorkoutLoggerApp
targets:
  Trackit:
    type: application
    platform: iOS
    sources:
      - App
    settings:
      base:
        TARGETED_DEVICE_FAMILY: "1"
        SWIFT_VERSION: "6.0"
        INFOPLIST_FILE: App/Info.plist
        CODE_SIGN_ENTITLEMENTS: App/Trackit.entitlements
        PRODUCT_BUNDLE_IDENTIFIER: com.abubakarsahi.trackit
    dependencies:
      - package: WorkoutLoggerCore
        product: WorkoutLoggerCore
      - package: WorkoutLoggerApp
        product: WorkoutLoggerApp
  TrackitTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - Path: App/Tests
        createIntermediateGroups: true
        optional: true
    dependencies:
      - target: Trackit
```

- [ ] **Step 2: Write `App/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Trackit</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>UILaunchScreen</key>
    <dict/>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
    </array>
    <key>NSMicrophoneUsageDescription</key>
    <string>Trackit listens while you speak each set.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Trackit turns your spoken sets into a workout log, on device.</string>
</dict>
</plist>
```

- [ ] **Step 3: Write `App/Trackit.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

- [ ] **Step 4: Write the three `System*` adapters**

`App/System/SystemSpeechRecognizer.swift`:

```swift
import Foundation
import Speech
import AVFoundation
import WorkoutLoggerApp

/// Real push-to-talk speech capture: on-device `SFSpeechRecognizer` over an
/// `AVAudioEngine` tap. `endUtterance()` stops the tap, waits for the final
/// result, and returns its transcriptions as the n-best list.
final class SystemSpeechRecognizer: TranscriptSource {
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<[String], Error>?

    func beginUtterance() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        self.request = request

        let input = audioEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try? audioEngine.start()

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result, result.isFinal {
                let hypotheses = result.transcriptions.map(\.formattedString)
                self.finish(.success(hypotheses.isEmpty ? [result.bestTranscription.formattedString] : hypotheses))
            } else if let error {
                self.finish(.failure(error))
            }
        }
    }

    func endUtterance() async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            request?.endAudio()
        }
    }

    private func finish(_ outcome: Result<[String], Error>) {
        continuation?.resume(with: outcome)
        continuation = nil
        task = nil
        request = nil
    }
}
```

`App/System/SystemReadbackVoice.swift`:

```swift
import Foundation
import AVFoundation
import AudioToolbox
import WorkoutLoggerApp

/// Real readback: `AVSpeechSynthesizer` for spoken plans, a short system sound
/// for the earcon.
final class SystemReadbackVoice: ReadbackVoice {
    private let synthesizer = AVSpeechSynthesizer()

    func perform(_ plan: ReadbackPlan) {
        switch plan {
        case .speak(let text):
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synthesizer.speak(utterance)
        case .earcon:
            AudioServicesPlaySystemSound(1103)
        }
    }
}
```

`App/System/SystemHaptics.swift`:

```swift
import Foundation
import UIKit
import WorkoutLoggerApp

/// Real haptics: a `UINotificationFeedbackGenerator` mapping for the four cues.
/// (A bespoke CoreHaptics pattern set is a later polish; the notification
/// generator gives four distinguishable feels now.)
final class SystemHaptics: Haptics {
    private let notify = UINotificationFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .rigid)

    func play(_ cue: HapticCue) {
        switch cue {
        case .logged:         impact.impactOccurred()
        case .notCaught:      notify.notificationOccurred(.error)
        case .personalRecord: notify.notificationOccurred(.success)
        case .restReached:    notify.notificationOccurred(.warning)
        case .none:           break
        }
    }
}
```

- [ ] **Step 5: Write `App/Views/RootView.swift`**

```swift
import SwiftUI
import WorkoutLoggerApp

/// Placeholder root. Enough to smoke-test the whole voice loop on a device;
/// the calm high-contrast HUD is subsystem C.
struct RootView: View {
    @State var model: WorkoutSessionModel

    var body: some View {
        VStack(spacing: 24) {
            Text(model.workout?.entries.last?.exercise.name ?? "No exercise")
                .font(.title2)

            if let set = model.workout?.entries.last?.sets.last {
                Text("\(set.loadKilograms.map { "\($0) kg " } ?? "")\(set.reps.map { "x \($0)" } ?? "")")
                    .font(.largeTitle.bold())
            }

            Text(model.restStartedAt == nil ? "" : "Rest \(Int(model.restElapsed))s")
                .foregroundStyle(.secondary)

            Button(model.isListening ? "Listening…" : "Hold to talk") {}
                .buttonStyle(.borderedProminent)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !model.isListening { model.pressed() } }
                        .onEnded { _ in Task { await model.released() } }
                )

            if let candidates = model.tapSelectCandidates, !candidates.isEmpty {
                ForEach(candidates, id: \.name) { exercise in
                    Button("Did you mean \(exercise.name)?") { model.resolveTapSelect(exercise) }
                }
            }
        }
        .padding()
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            model.tick()
        }
    }
}
```

- [ ] **Step 6: Write `App/TrackitApp.swift`**

```swift
import SwiftUI
import SwiftData
import WorkoutLoggerCore
import WorkoutLoggerApp

@main
struct TrackitApp: App {
    @State private var model: WorkoutSessionModel

    init() {
        let container = try! ModelContainer(for: WorkoutRecord.self)
        let store = SwiftDataWorkoutStore(context: ModelContext(container))
        let library = ExerciseLibrary(TrackitApp.seedExercises)
        let engine = WorkoutEngine(store: store, library: library)
        _model = State(initialValue: WorkoutSessionModel(
            engine: engine,
            transcriptSource: SystemSpeechRecognizer(),
            readbackVoice: SystemReadbackVoice(),
            haptics: SystemHaptics(),
            library: library
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }

    static let seedExercises: [Exercise] = [
        Exercise(name: "Barbell Bench Press", aliases: ["bench", "bench press"]),
        Exercise(name: "Barbell Back Squat", aliases: ["squat", "squats", "back squat"]),
        Exercise(name: "Conventional Deadlift", aliases: ["deadlift", "deads"]),
        Exercise(name: "Overhead Press", aliases: ["ohp", "overhead press", "press"]),
        Exercise(name: "Barbell Row", aliases: ["row", "barbell row", "bent row"]),
        Exercise(name: "Pull-Up", aliases: ["pull up", "pull ups", "pullups"]),
    ]
}
```

- [ ] **Step 7: Consistency check (no build here)**

Re-read the six Swift files. Confirm:
- every `import WorkoutLoggerApp` type used (`WorkoutSessionModel`, `SwiftDataWorkoutStore`, `WorkoutRecord`, `TranscriptSource`, `ReadbackVoice`, `Haptics`, `ReadbackPlan`, `HapticCue`) is `public` in the package (they are, per Tasks 2/4/5/7).
- `RootView`'s `set.loadKilograms` / `set.reps` are the `LoggedSet` field names (they are).
- `WorkoutEngine(store:library:)` matches the core init (it does — other params default).

- [ ] **Step 8: Commit**

```bash
cd /Users/Apple/projects/trackit
git add project.yml App
git commit -m "App: thin iOS target (project.yml + @main + placeholder view + System adapters)

XcodeGen project.yml, TrackitApp composition root, a placeholder RootView
wired to press-to-talk, and SystemSpeechRecognizer / SystemReadbackVoice /
SystemHaptics. Run 'brew install xcodegen && xcodegen' then build in Xcode.
Not swift-test covered by design.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

---

### Task 11: Reconcile spec and memory

**Files:**
- Modify: `Packages/WorkoutLoggerCore/specs/v1-voice-logging.md` — note the app-shell A+B landing under the relevant module bullets
- Modify: `/Users/Apple/.claude/projects/-Users-Apple-projects-trackit/memory/phase-progress.md`
- Modify: `/Users/Apple/.claude/projects/-Users-Apple-projects-trackit/memory/MEMORY.md` — refresh the one-line pointer

**Interfaces:**
- Consumes: the finished state of Tasks 1–10.
- Produces: docs/memory consistent with the code.

- [ ] **Step 1: Update the spec**

In `Packages/WorkoutLoggerCore/specs/v1-voice-logging.md`, under `### Module boundaries (conceptual)`, append to the **Speech capture** bullet:

```
  The app-shell realisation of this interface is `TranscriptSource`
  (`beginUtterance` / `endUtterance() async -> [String]`); `SystemSpeechRecognizer`
  wraps `SFSpeechRecognizer` + `AVAudioEngine`, and a `ScriptedTranscriptSource`
  fake drives the session model in `swift test`.
```

Under `### Testing Decisions` (or the nearest testing section), add:

```
- **App skeleton + voice pipeline (subsystems A+B).** A second SwiftPM package
  `WorkoutLoggerApp` holds the `@Observable WorkoutSessionModel`, a SwiftData
  `WorkoutStore` (one `@Model` per session, `Workout` JSON blob keyed on
  `startedAt`), the pure `readbackPlan` composer, and protocol + fake
  collaborators. All covered by `swift test`. The Xcode app target (`App/`,
  generated from `project.yml`) holds only `@main`, one placeholder view, and the
  `System*` framework wrappers, and is not `swift test`-covered.
```

- [ ] **Step 2: Update `phase-progress.md`**

Replace the "Everything else in Phase 5 is app-shell/infra" sentence's lead-in with a new paragraph before "Rhythm:":

```
- **App shell — subsystems A+B (skeleton + voice pipeline) DONE (package scope).**
  New `Packages/WorkoutLoggerApp` package alongside `Packages/WorkoutLoggerCore`
  (the tree was restructured under `Packages/`). `SwiftDataWorkoutStore` persists
  each session as a JSON `Workout` blob in one `@Model WorkoutRecord` keyed on
  `startedAt` (upsert). `@Observable @MainActor WorkoutSessionModel` owns a
  `WorkoutEngine`, snapshot-copies its state after each command, re-derives
  `parse` for the readback/haptic/tap-select decision, and calls `engine.hear`
  to apply. Pure `readbackPlan` composer. `TranscriptSource` /
  `ReadbackVoice` / `Haptics` protocols with `Scripted*` / `Spy*` fakes; real
  `System*` wrappers live in the un-tested `App/` Xcode target
  (`project.yml` + XcodeGen). One additive core edit: `Codable` on the value
  types. Subsystems C (HUD), D (progress/edit screens), E (onboarding/settings),
  F (HealthKit/export/telemetry) are still to come, each its own cycle.
  Design + plan: `docs/superpowers/{specs,plans}/`.
```

- [ ] **Step 3: Update `MEMORY.md` pointer**

Replace the phase-progress line with:

```
- [Phase progress](phase-progress.md) — WorkoutLoggerCore Phases 1–5 package scope done; app shell A+B (skeleton + voice pipeline) done in Packages/WorkoutLoggerApp; C–F still to come
```

- [ ] **Step 4: Commit**

```bash
cd /Users/Apple/projects/trackit
git add Packages/WorkoutLoggerCore/specs
git commit -m "Docs: reconcile spec with the app-shell A+B landing

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SLGb8gwCoF3tUx59nHYCYo"
```

(The memory files under `~/.claude/` are outside the repo and are not committed.)

---

## Self-Review

**1. Spec coverage:**

| Spec element | Task |
|---|---|
| Second SwiftPM package `WorkoutLoggerApp`, thin Xcode target via XcodeGen | 1, 2, 10 |
| Restructure to `Packages/` + `App/` | 1 |
| `@Model` blob keyed on `startedAt`, upsert, `history()`, `openWorkout()` | 4 |
| `Codable` on core types (revised decision — in core, not app) | 3 |
| `@Observable WorkoutSessionModel`, snapshot-copy after each command | 7 |
| Model re-derives `parse` for feedback; `engine.hear` applies | 7 |
| `TranscriptSource` async request/response + fake | 5 |
| `ReadbackVoice` / `Haptics` protocols + spies | 5 |
| `readbackPlan` composer, full/terse/earcon, precedence | 6 |
| Push-to-talk flow, `isNewExercise` tracking | 7 |
| Parse failure → `.notCaught` + `tapSelectCandidates`; `resolveTapSelect` | 8 |
| PR → `.personalRecord` (priority over `.logged`) | 8 |
| `capReadbackAtEarcon` → all earcon | 7 |
| Rest tick latch on injected clock, once per period, reset per set | 9 |
| `project.yml`, Info.plist permissions, entitlements | 10 |
| `TrackitApp` composition root, `RootView` placeholder, `System*` wrappers | 10 |
| Launch stale-workout check | Deferred — `openWorkout()` is built (Task 4); the launch prompt UI is noted in the spec as minimal and lands with subsystem C/E. Flagged here so it is not lost. |
| Spec + memory reconciliation | 11 |

Gap accepted: the launch-time resume-or-discard prompt. `SwiftDataWorkoutStore.openWorkout()` + `Workout.isStale` give the data; wiring a prompt is UI and belongs with the HUD (C). Recorded in Task 11's spec note is not required — but the plan explicitly acknowledges it here.

**2. Placeholder scan:** No "TBD"/"TODO"/"add error handling" placeholders. Every code step has complete code. Task 8 and Task 9 steps are written as "expect pass, fix only if" because the Task 7 implementation deliberately builds those seams — the fix code is still spelled out inline.

**3. Type consistency:**
- `readbackPlan(for:style:exerciseName:)` — same signature in Task 6 (definition) and Task 7 (call site). ✓
- `HapticCue` cases `logged / notCaught / personalRecord / restReached / none` — same in Task 5, 7, 8, 9, 10. ✓
- `ReadbackPlan` cases `speak(String) / earcon` — same in Task 5, 6, 7, 10. ✓
- `ScriptedTranscriptSource(_ queue:)`, `.throwWhenExhausted`, `.beganCount`, `.Failure.exhausted` — same in Task 5 (definition) and Tasks 7–9 (use). ✓
- `SwiftDataWorkoutStore(context:)`, `.save(_:)`, `.history()`, `.openWorkout()` — same in Task 4 (definition) and Task 7/10 (use). ✓
- `WorkoutSessionModel.init` param list — Task 7 definition matches Task 7/8/9 `makeRig` and Task 10 `TrackitApp`. ✓
- `WorkoutRecord(startedAt:endedAt:payload:)` — Task 2 definition, Task 4 use. ✓
- `tick()` / `resolveTapSelect(_:)` — declared in Task 7 interfaces, exercised in Tasks 8–9. ✓

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-08-31-app-shell-skeleton-voice-pipeline.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
