# App shell: skeleton + voice pipeline (subsystems A + B)

**Date:** 2026-08-30
**Status:** approved, ready for implementation plan
**Scope:** the app skeleton and the live voice loop only. The active-workout HUD (C),
post-workout + progress screens (D), onboarding/settings/phrasebook (E), and
HealthKit/export/telemetry (F) are separate later cycles, each with its own spec.

## Context

`WorkoutLoggerCore` is a feature-complete Swift 6 SwiftPM package (Phases 1–5
package scope, 95 tests, 9 suites, committed at `ad16393`). It exposes pure seams:

- `parse(_:context:library:) -> [ParseResult]`
- `postProcess(_ hypotheses: [String], library:) -> String`
- `resolve(_:in:) -> ExerciseResolution`
- `readbackStyle(for:isNewExercise:capAtEarcon:) -> ReadbackStyle`
- `exerciseProgress(for:across:) -> ExerciseProgress`
- `WorkoutEditing` transforms on `Workout`
- `WorkoutEngine` — `final class`, `hear(_ hypotheses: [String])` runs the whole
  `postProcess → parse → apply` chain internally; `save(_:)` is called on the
  injected `WorkoutStore` on every set. State is `private(set)`: `workout`,
  `personalRecords`, `restStartedAt`; plus `restElapsedSeconds`,
  `currentRestTargetSeconds`, `isRestTargetReached`; clock injected as
  `now: () -> Date`.
- `WorkoutStore` — `protocol WorkoutStore: AnyObject { func save(_ workout: Workout) }`

The spec `specs/v1-voice-logging.md` already fixes the platform: native iOS,
SwiftUI, iOS 17+, iPhone only, portrait only, on-device persistence via SwiftData,
no backend, no accounts.

**Constraint:** this environment can run `swift test` but cannot run Xcode or
`xcodebuild`. The design puts every testable unit into a SwiftPM package and keeps
the un-runnable Xcode target as thin as possible.

## Decisions

Five decisions were settled in brainstorming:

1. **Layout** — a second local SwiftPM package `WorkoutLoggerApp` holds everything
   that is not a SwiftUI view and not a live OS-framework call. A thin Xcode app
   target holds `@main`, the view tree, and the real framework wrappers. The
   `.xcodeproj` is generated from a checked-in XcodeGen `project.yml`; the
   `project.pbxproj` is never hand-edited.
2. **Engine binding** — `WorkoutLoggerApp`'s `@Observable WorkoutSessionModel`
   owns a `WorkoutEngine` and copies its state into its own observed stored
   properties after every command. `WorkoutLoggerCore` takes no dependency on the
   Observation framework.
3. **Persistence** — one `@Model WorkoutRecord { startedAt (unique), endedAt,
   payload: Data }` holding the JSON-encoded `Workout`. `save` upserts by
   `startedAt` (the engine's per-session timestamp). Read side decodes all.
   `Codable` is added to the core value types **in `WorkoutLoggerCore`** (a
   one-line `: Codable` on each — Swift only synthesises `Codable` in the type's
   own module, so a cross-module extension would need hand-written coders). This
   is the one core edit: purely additive, no behaviour change, no test breakage.
4. **Speech interface** — `protocol TranscriptSource { func beginUtterance();
   func endUtterance() async throws -> [String] }`. Press → `beginUtterance`,
   release → `endUtterance` yields the final n-best. Real impl wraps
   `SFSpeechRecognizer` + `AVAudioSession`; fake returns a scripted `[String]`.
5. **Parse visibility** — the model re-derives
   `parse(postProcess(hypotheses, library:), context: WorkoutContext(unit: unit),
   library:)` to inspect what the parser produced (for readback style, haptic
   choice, tap-select), then calls `engine.hear(hypotheses)` to apply. `parse`
   runs twice per utterance: both pure, both sub-millisecond, once per ~10 s of
   human action. `WorkoutLoggerCore`'s logic stays frozen — the only edit is the
   additive `: Codable` from decision 3.

## Repository layout

One-time restructure (pure `git mv` of the current tree — no file contents change):

```
trackit/
├── project.yml                       # XcodeGen source of truth (checked in)
├── docs/superpowers/specs/           # design docs (repo-level; stays at root)
├── Packages/
│   ├── WorkoutLoggerCore/            # everything currently at repo root, moved verbatim
│   │   ├── Package.swift             #   unchanged — iOS 17 / macOS 13
│   │   ├── Sources/ Tests/ docs/adr/ specs/ CONTEXT.md
│   └── WorkoutLoggerApp/             # NEW library package — iOS 17 / macOS 14
│       ├── Package.swift             #   .package(path: "../WorkoutLoggerCore")
│       ├── Sources/WorkoutLoggerApp/
│       │   ├── Persistence/
│       │   ├── Session/
│       │   └── Readback/
│       └── Tests/WorkoutLoggerAppTests/
└── App/                              # NEW thin Xcode target (generated)
    ├── TrackitApp.swift
    ├── Views/RootView.swift
    ├── System/{SystemSpeechRecognizer,SystemReadbackVoice,SystemHaptics}.swift
    ├── Info.plist
    └── Trackit.entitlements
```

- Core tests continue to run as `cd Packages/WorkoutLoggerCore && swift test`.
- App-package tests run as `cd Packages/WorkoutLoggerApp && swift test`.
- `WorkoutLoggerApp` platforms are `.iOS(.v17), .macOS(.v14)` (Observation and
  SwiftData both require macOS 14; the `swift test` host satisfies this).

## Persistence (`WorkoutLoggerApp/Persistence/`)

```swift
@Model final class WorkoutRecord {
    @Attribute(.unique) var startedAt: Date
    var endedAt: Date?
    var payload: Data                       // JSON-encoded WorkoutLoggerCore.Workout
    init(startedAt: Date, endedAt: Date?, payload: Data)
}

final class SwiftDataWorkoutStore: WorkoutStore {
    init(context: ModelContext)
    func save(_ workout: Workout)           // encode; fetch by startedAt; update or insert; context.save()
    func history() -> [Workout]             // fetch all, sorted by startedAt, decode each
    func openWorkout() -> Workout?          // the record with endedAt == nil, decoded
}
```

- `WorkoutStore` (the protocol in the core) stays save-only and engine-facing.
  `history()` / `openWorkout()` are concrete methods used by the launch check and
  later by the progress screens; they are **not** added to the core protocol.
- `Codable` conformances (synthesized, added in `WorkoutLoggerCore`): `Workout`, `Entry`,
  `LoggedSet`, `Exercise`, `PersonalRecord`, `LoadType`, `EffortMeasure`,
  `SetRole`, `Grouping`, `MassUnit`.
- Tests use `ModelConfiguration(isStoredInMemoryOnly: true)`.
- **First implementation slice de-risks headless SwiftData**: insert one
  `WorkoutRecord`, read it back, before anything is built on top.

### Persistence test seams (`swift test`)

- save → `history()` returns one workout, entries/sets/loads intact
- save the same session twice (growing workout) → `history().count == 1`, latest content
- two sessions (distinct `startedAt`) → `history().count == 2`, ordered by `startedAt`
- after `endWorkout`'s save → `openWorkout()` is nil, the record remains in `history()`
- `Codable` round-trip on a workout exercising every axis + a set note + a superset run id

## Session model & voice loop (`WorkoutLoggerApp/Session/`)

```swift
@MainActor @Observable
final class WorkoutSessionModel {
    // injected collaborators
    //   engine: WorkoutEngine, transcriptSource: TranscriptSource,
    //   readbackVoice: ReadbackVoice, haptics: Haptics,
    //   library: ExerciseLibrary, unit: MassUnit, capReadbackAtEarcon: Bool

    // observed state, snapshot-copied from the engine after each command
    private(set) var workout: Workout?
    private(set) var personalRecords: [PersonalRecord]
    private(set) var restStartedAt: Date?
    private(set) var restElapsed: TimeInterval
    private(set) var isListening: Bool
    private(set) var tapSelectCandidates: [Exercise]?
    private(set) var lastReadback: ReadbackPlan?

    func pressed()
    func released() async
    func resolveTapSelect(_ exercise: Exercise)

    static func live(container: ModelContainer) -> WorkoutSessionModel
    init(/* all collaborators explicit — tests & previews */)
}
```

### Push-to-talk flow

1. `pressed()` → `transcriptSource.beginUtterance()`; `isListening = true`.
2. `released()` → `let hypotheses = try await transcriptSource.endUtterance()`;
   `isListening = false`.
3. Inspect (identical to what the engine will do):
   `let transcript = postProcess(hypotheses, library: library)`
   `let results = parse(transcript, context: WorkoutContext(unit: unit), library: library)`
4. Snapshot `before = (engine.workout, engine.personalRecords.count)`.
5. `engine.hear(hypotheses)` — apply.
6. `syncFromEngine()` — copy `workout` / `personalRecords` / `restStartedAt`.
7. Feedback, from `results` + the before/after delta:
   - **Haptic** (`HapticCue`): PR count ↑ → `.personalRecord`; else a set landed →
     `.logged`; else `results` contains `.lowConfidence` → `.notCaught`; else
     `.none`. `haptics.play(cue)`.
   - **Readback** (`ReadbackPlan`): pick the result to read back by fixed
     precedence — `.set` if present, else `.announcement`, else `.lowConfidence`,
     else none — call
     `readbackStyle(for:isNewExercise:capAtEarcon: capReadbackAtEarcon)`, map to
     `.speak(String)` or `.earcon`, `readbackVoice.perform(plan)`, store `lastReadback`.
   - **Tap-select**: a `.lowConfidence(_, candidates)` sets `tapSelectCandidates`.
     `resolveTapSelect(_:)` re-issues the utterance with the chosen exercise's
     name in place of the unresolved leading span, then clears
     `tapSelectCandidates`. The model retains the last raw `transcript` for this;
     the exact rewrite rule (replace the leading name span, keep the numeric tail)
     is settled in implementation against a test. The fallback UI itself is
     subsystem C.
8. `isNewExercise`: the model keeps `announcedThisWorkout: Set<String>`; an
   `.announcement` for a name not in the set is new (then inserted). Cleared when
   a `start workout` command resets the session.

### Rest tick

While `restStartedAt != nil`, a 1 Hz async loop recomputes
`restElapsed = now() - restStartedAt`. The first time `engine.isRestTargetReached`
flips true, `haptics.play(.restReached)` fires exactly once (latched until the
next logged set). The loop uses the same `now` clock injected into the engine, so
tests drive it deterministically.

### Protocols & fakes (in `WorkoutLoggerApp`, shared by tests and previews)

```swift
protocol TranscriptSource { func beginUtterance(); func endUtterance() async throws -> [String] }
protocol ReadbackVoice   { func perform(_ plan: ReadbackPlan) }
protocol Haptics         { func play(_ cue: HapticCue) }

enum ReadbackPlan: Equatable { case speak(String), earcon }
enum HapticCue: Equatable    { case logged, notCaught, personalRecord, restReached, none }

struct ScriptedTranscriptSource: TranscriptSource   // queue: [[String]]
final class SpyReadbackVoice: ReadbackVoice          // performed: [ReadbackPlan]
final class SpyHaptics: Haptics                       // played: [HapticCue]
```

### Session-model test seams (`swift test`, fakes + in-memory store + injected clock)

- `"start workout"` scripted → `model.workout` non-nil and persisted
- `"bench 100 for 5"` → set present in `workout`; `.logged` played; `lastReadback`
  is `.speak(...)` at full verbosity (new exercise this session)
- same utterance again → `lastReadback` is `.speak(...)` at terse verbosity
- `capReadbackAtEarcon == true` → every plan is `.earcon`
- unparseable input → `.notCaught` played, `tapSelectCandidates` populated,
  `workout` unchanged
- `resolveTapSelect(_:)` after a `.lowConfidence` → the set is logged against the
  chosen exercise, `tapSelectCandidates` cleared
- a heavier working set after a lighter one on a known exercise → `.personalRecord`
  played, `personalRecords` grew
- clock advanced past the rest target after a set → `.restReached` played exactly once
- `endUtterance()` throws → `isListening` resets, no crash

## Thin iOS target (`App/`) — not `swift test`-covered

- **`project.yml`** — one app target `Trackit` (iOS 17.0, iPhone, portrait only),
  `INFOPLIST_KEY_NSMicrophoneUsageDescription`,
  `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription`, no background modes; one
  near-empty `TrackitTests` target (snapshot tests arrive with subsystem C); both
  local packages as `packages:` path references; bundle id
  `com.abubakarsahi.trackit`.
- **`TrackitApp.swift`** — `@main`; builds the `ModelContainer` for
  `WorkoutRecord.self`; `WorkoutSessionModel.live(container:)`; environment
  injection. On launch: `store.openWorkout()` + `Workout.isStale(now:staleAfter:)`
  → minimal resume-or-discard prompt.
- **`Views/RootView.swift`** — placeholder: current exercise, last set,
  `restElapsed` text, and a press-to-talk button bound to
  `model.pressed()` / `model.released()`. Enough to smoke-test the B loop on a
  device. The calm high-contrast HUD is subsystem C.
- **`System/SystemSpeechRecognizer.swift`** — `SFSpeechRecognizer` +
  `AVAudioSession` (`.record`), `requiresOnDeviceRecognition = true`, request
  `taskHint = .dictation`; `endUtterance()` finalizes and returns
  `result.transcriptions.map(\.formattedString)` as the n-best list.
- **`System/SystemReadbackVoice.swift`** — `AVSpeechSynthesizer` for `.speak`;
  a short `AudioServicesPlaySystemSound` for `.earcon`.
- **`System/SystemHaptics.swift`** — `UINotificationFeedbackGenerator` + a
  four-pattern `CHHapticEngine` set (logged / notCaught / personalRecord /
  restReached).

## Testing boundary

| Covered by `swift test` in `Packages/WorkoutLoggerApp` | Deferred (needs `xcodebuild` / device / a later subsystem) |
|---|---|
| `SwiftDataWorkoutStore` round-trip, upsert, `history()`, `openWorkout()` | the `.xcodeproj` actually building |
| `Codable` format round-trip | real `SFSpeechRecognizer` n-best behaviour |
| `WorkoutSessionModel` full voice loop against fakes | `AVSpeechSynthesizer` / haptic feel |
| `ReadbackPlan` + `HapticCue` selection | view snapshots (subsystem C) |
| rest-tick latch on the injected clock | HealthKit / export / telemetry (subsystem F) |

Process: strict TDD as in the core — one vertical slice per red→green, refactor a
separate stage. `swift test` in `Packages/WorkoutLoggerApp` each cycle;
`xcodegen && xcodebuild` (or Xcode) at milestones to confirm the app target
compiles and to smoke-test on device.

## Non-goals for A + B

- The calm high-contrast HUD, keep-awake, and the tap-select fallback UI (C).
- Post-workout edit screen, per-exercise progress charts, save-as-template (D).
- Onboarding, guided practice, phrasebook, settings screens beyond the
  `capReadbackAtEarcon` flag the model already needs (E).
- HealthKit writer, file export, telemetry queue (F).
- Partial/streaming transcripts and a "listening…" shimmer (optional later
  addition to `TranscriptSource`, contract unchanged).
- Any change to `WorkoutLoggerCore` beyond the additive `: Codable` conformances.

## Risks

- **Headless SwiftData under `swift test`.** Mitigated by making the very first
  slice a bare insert/read-back with the in-memory config.
- **`@Observable` snapshot-copy churn.** `Workout` is a value type and already
  `Equatable`; copying on each command is cheap. If view updates thrash, revisit
  by diffing before assigning.
- **XcodeGen not installed.** The user runs `brew install xcodegen` once; the
  `project.yml` is the checked-in source of truth and reviewable without building.
