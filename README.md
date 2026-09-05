# Trackit

**Log a set by saying it.**

Trackit is a voice-first iOS workout logger. Press to talk, say the exercise
once, say each set as you finish it — *"225 for 5"* — and it's logged, read
back, and confirmed with a haptic. No unlocking the phone, no tapping through
a form between sets, no signal required.

![Platform](https://img.shields.io/badge/platform-iOS_17%2B-000000?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-6.0-000000?style=flat-square&logo=swift&logoColor=white)
![Stack](https://img.shields.io/badge/stack-SwiftUI_%2B_SwiftData-000000?style=flat-square)
![Speech](https://img.shields.io/badge/speech-on--device%2C_offline-30D158?style=flat-square)
![Status](https://img.shields.io/badge/status-pre--launch-lightgrey?style=flat-square)

---

## Why voice

Between sets you have chalky hands, thirty seconds, and no interest in
looking at a screen. Trackit's voice loop is the entire product, not a
shortcut bolted onto a tap-based logger:

```
 you   ›  "start workout"
 app   ›  ♪  tone

 you   ›  "bench press"
 app   ›  🔊 "Bench Press."          — full, first time this exercise comes up

 you   ›  "warmup 60 for 10"
 app   ›  🔊 "60 for 10"             — terse from here on, same exercise

 you   ›  "225 for 5"
 app   ›  🔊 "225 for 5"  📳          — logged; rest clock starts

 you   ›  "225 for 5"                — said again, hands still full
 app   ›  🔊 "225 for 5"  📳          — logged again

 you   ›  "undo"
 app   ›  ♪  tone                    — last set removed, no need to look up
```

Recognition and parsing run entirely on-device — the app is built to work
mid-workout in a gym with no network at all, permanently, not as a v1
limitation.

## Architecture

Logic and UI are split across two Swift packages plus a thin app shell, so
every rule the parser or the engine enforces is unit-tested without ever
touching SwiftUI:

```
Packages/
├── WorkoutLoggerCore/     pure domain logic — no I/O, no SwiftUI
│   ├── Model, WorkoutEngine, WorkoutEditing, WorkoutTemplate
│   ├── Parser, PostProcessor, Resolver     — transcript → structured intent
│   ├── Readback, ExerciseProgress, CorpusScore
│   └── CONTEXT.md                          — the domain glossary
│
└── WorkoutLoggerApp/      @Observable app layer over the core
    ├── Session/           WorkoutSessionModel — the live-workout state machine
    ├── HUD/               HUDProjection — the pure view-model the HUD renders
    ├── History/, Progress/, Persistence/, Readback/, Formatting/

App/                       SwiftUI shell — dumb renderers over the above
├── Views/                 HUDView, HistoryListView, ExerciseProgressView, …
└── System/                thin adapters to Speech, haptics, readback
```

`WorkoutLoggerCore` never imports SwiftUI or SwiftData. `WorkoutSessionModel`
owns all mutable state; `HUDProjection` and friends are pure, `Equatable`
snapshots of it — every formatting and fallback rule lives in a projection,
never in a view.

## Design

One screen carries the app's whole visual identity — the live HUD reads like
a gym scoreboard: black canvas, huge SF Rounded numerals, one accent color
that means exactly one thing. Everything else (history, editing, progress)
is plain system List/Form UI, deliberately undecorated.

See **[PRODUCT.md](PRODUCT.md)** for who this is for and what it commits to,
and **[DESIGN.md](DESIGN.md)** for the full token set and component rules —
the "Blackout Board" design system.

## Getting started

```bash
git clone https://github.com/Abubakarjutt/Track-It.git trackit
cd trackit
```

**Core logic and app layer** (pure Swift, no Xcode required):

```bash
(cd Packages/WorkoutLoggerCore && swift test)   # parser, engine, editing, progress
(cd Packages/WorkoutLoggerApp   && swift test)   # session model, HUD projection, history, progress
```

**The app itself** is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml`:

```bash
xcodegen generate
open Trackit.xcodeproj
```

## Status

Built subsystem by subsystem, each merged only once its own package tests
are green:

- [x] App shell + voice pipeline (press-to-talk, transcript → parse → engine)
- [x] Live-workout HUD (the Blackout Board)
- [x] Post-workout history, editing, and per-exercise progress
- [ ] Onboarding & settings
- [ ] HealthKit sync, export, telemetry

## License

No license has been chosen yet — all rights reserved by default until one
is added.
