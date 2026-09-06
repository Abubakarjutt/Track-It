# Trackit

**Log a set by saying it.**

A voice-first iOS workout logger. Press to talk, name the exercise once, and say
each set as you finish it — *"225 for 5"* — and it is logged, read back, and
confirmed with a haptic. No unlocking, no form to tap between sets, no signal
required. Recognition and parsing run entirely on-device, so the loop works in a
loud, signal-free gym — a standing product commitment, not a v1 shortcut.

![Platform](https://img.shields.io/badge/platform-iOS_17%2B-0a0a0a?style=flat&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.0-0a0a0a?style=flat&logo=swift&logoColor=white)
![Stack](https://img.shields.io/badge/stack-SwiftUI_%2B_SwiftData-0a0a0a?style=flat)
![On-device](https://img.shields.io/badge/on--device-offline-30D158?style=flat&logoColor=black)
![Status](https://img.shields.io/badge/status-pre--launch-9a9a9a?style=flat)

---

## The loop

The voice loop is the whole product — not a feature bolted onto a tap-based
logger. Between sets you have chalky hands, thirty seconds, and no interest in
looking at a screen. The app confirms every set *peripherally*, without pulling
your eyes back to a display:

```
  you   ›  "start workout"
  app   ›  ♪                            tone

  you   ›  "bench press"
  app   ›  🔊 "Bench Press."            full, first time this exercise comes up

  you   ›  "warmup 60 for 10"
  app   ›  🔊 "60 for 10"              terse from here on, same exercise

  you   ›  "225 for 5"
  app   ›  🔊 "225 for 5"  📳         logged; rest clock starts

  you   ›  "225 for 5"                 said again, hands still full
  app   ›  🔊 "225 for 5"  📳         logged again

  you   ›  "undo"
  app   ›  ♪                            last set removed — no need to look up
```

One accent color carries one meaning: **Go Green means "go / on-target."** A
spoken set is confirmed by voice and haptic together, so the lifter never stops
for a screen. Mistakes are fixed the same way — say the set again, or say
*"undo"* — rather than tapping through a correction UI mid-workout.

---

## The product

Trackit is for serious lifters running structured barbell and dumbbell
programs — powerlifting, hypertrophy, and the training styles between — who log
every working set and want a clean, editable record with per-exercise progress
over time. The voice loop is used *during* the workout; the rest is a careful,
normal touch UI used *after* it.

Five principles govern the design:

| Principle | What it means |
| --- | --- |
| **The voice loop is the product** | Every core logging action is completable without looking at the screen; touch UI is for before and after the set, not during it. |
| **Never break the set to fix a mistake** | Corrections happen by speaking again — repeat the set, say *"undo"* — not by stopping to tap. |
| **Offline and on-device, permanently** | The app works in a gym with no signal. This is a durable trust commitment, never a fallback mode. |
| **Confirm without demanding attention** | Voice readback plus a distinct haptic is how the app says *I heard that* — quick and peripheral, not a screen to check. |
| **Review belongs on screen** | Editing history, correcting entries, and reading progress charts are deliberate touch interactions, and they stay that way. |

Loads are stored canonically in kilograms (Epley for estimated 1RM); the domain
glossary of record is [`CONTEXT.md`](Packages/WorkoutLoggerCore/CONTEXT.md).

---

## Architecture

Logic and UI are split across two Swift packages and a thin app shell, so every
rule the parser or the engine enforces is unit-tested without ever touching
SwiftUI:

```
Packages/
├── WorkoutLoggerCore/        pure domain logic — no I/O, no SwiftUI
│    ├── Model, WorkoutEngine, WorkoutEditing, WorkoutTemplate
│    ├── Parser, PostProcessor, Resolver      transcript → structured intent
│    ├── Readback, ExerciseProgress, CorpusScore
│    └── CONTEXT.md                          the domain glossary
│
└── WorkoutLoggerApp/         @Observable app layer over the core
     ├── Session/              WorkoutSessionModel — the live-workout state machine
     ├── HUD/                  HUDProjection — the pure view-model the HUD renders
     └── History/, Progress/, Persistence/, Readback/, Formatting/

App/                          SwiftUI shell — dumb renderers over the above
├── Views/                    HUDView, HistoryListView, ExerciseProgressView, …
└── System/                   thin adapters to Speech, haptics, readback, HealthKit
```

`WorkoutLoggerCore` never imports SwiftUI or SwiftData. `WorkoutSessionModel`
owns all mutable state; the projections are pure, `Equatable` snapshots of it —
every formatting and fallback rule lives in a projection, never in a view.

---

## Design

One screen carries the app's whole visual identity — the live-workout HUD reads
like a gym scoreboard: a black canvas, huge SF Rounded numerals, and one accent
color. Every other screen (history, detail, editing, progress, settings) is
plain system UI, deliberately undecorated. That split is the point: the HUD is
used mid-set, hands busy, not really looking; the rest is a careful review done
after the workout, where a stock iOS list is exactly right. The mood is calm and
utilitarian — closer to purpose-built gym equipment than a consumer fitness app.
There is exactly one celebratory moment (the personal-record trophy) and nothing
else that gamifies.

### The Blackout Board, at a glance

A small, disciplined palette — mostly black, white, and gray, with color
reserved for a single meaning:

| | Token | Hex | Use |
| --- | --- | --- | --- |
| <span style="display:inline-block;width:14px;height:14px;border-radius:4px;background:#000000;border:1px solid #3a3a3a"></span> | Blackout Black | `#000000` | The HUD's entire canvas, forced app-wide — there is no light mode. |
| <span style="display:inline-block;width:14px;height:14px;border-radius:4px;background:#FFFFFF"></span> | Board White | `#FFFFFF` | Primary text on the HUD; the idle talk-button fill. |
| <span style="display:inline-block;width:14px;height:14px;border-radius:4px;background:#30D158"></span> | Go Green | `#30D158` | The one accent — "go / on-target." Listening, rest reached. Never decorative. |
| <span style="display:inline-block;width:14px;height:14px;border-radius:4px;background:#FFD60A"></span> | PR Yellow | `#FFD60A` | The personal-record trophy — the app's only celebratory mark. |
| <span style="display:inline-block;width:14px;height:14px;border-radius:4px;background:#FF453A"></span> | Error Red | `#FF453A` | Reserved for failure the lifter must notice — save errors, "Not logged." |

Depth is flat throughout: no shadow anywhere. Full token set, type scale, and
component rules live in [`DESIGN.md`](DESIGN.md).

---

## Getting started

```bash
git clone https://github.com/Abubakarjutt/Track-It.git trackit
cd trackit
```

**Core logic and the app layer** — pure Swift, no Xcode required:

```bash
(cd Packages/WorkoutLoggerCore && swift test)    # parser, engine, editing, progress
(cd Packages/WorkoutLoggerApp     && swift test) # session model, HUD, history, progress, HealthKit
```

**The app itself** is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml`:

```bash
xcodegen generate
open Trackit.xcodeproj
```

---

## Roadmap

Built subsystem by subsystem, each merged only once its own package tests are
green, in the cadence of the build log:

| Subsystem | Status |
| --- | --- |
| App shell + voice pipeline (press-to-talk, transcript → parse → engine) | ✅ Landed |
| Live-workout HUD (the Blackout Board) | ✅ Landed |
| Post-workout history, editing, and per-exercise progress | ✅ Landed |
| Onboarding & settings | ✅ Landed |
| Export — JSON / CSV archive to the share sheet | ✅ Landed |
| Apple Health sync — one-way write on workout end | ✅ Landed |
| Telemetry & failed-utterance review | ⏳ Pending |

---

## License

No license has been chosen yet — all rights reserved by default until one is
added.
