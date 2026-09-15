# Cluster 7e — Light mode

**Prerequisite reading:** `2026-09-11-v1.1-remaining-onboarding.md`.
**Parent:** `2026-09-06-v1.1-deferred-work-design.md` § "Cluster 7" → "Light mode".
**Master spec framing:** *"v1 is forced-dark; the HUD *is* the brand."*

So the first question is not "how" but **"should this exist at all"** — the
forced-dark decision is a deliberate brand stance, and "light mode" here may mean
anything from "full light palette" to "respect the system setting on the
non-HUD screens only". Resolve OPEN QUESTION 1 before writing code.

Impl-ready brief; the product decision is open.

---

## What exists today

Forced-dark is applied in exactly one place and colours are hardcoded:

- `App/Views/RootView.swift:58` — `.preferredColorScheme(.dark)` on the root.
- `App/Views/RootView.swift:25` — `Color.black.ignoresSafeArea()` background.
- `App/Views/HUDView.swift` — literal colours throughout:
  - `.foregroundStyle(.white)` on the exercise name, last-set line (lines 91, 95).
  - talk button: `.foregroundStyle(.black)` label (195), fill
    `hud.isListening ? Color.green : Color.white` (201).
  - rest ring/line: `hud.restTargetReached ? Color.green : Color.secondary`
    (176), stroke `Color.secondary.opacity(0.4)` (181).
- `App/Views/LaunchGateView.swift:12`, `OnboardingView.swift:19` —
  `.foregroundStyle(.white)`.
- **No colour abstraction.** There is no `Palette` / `Theme` / semantic-colour
  enum, no asset catalogue colour set. Every colour is a literal at its use site.
- `App/Info.plist` has **no** `UIUserInterfaceStyle` key (the SwiftUI modifier
  does the forcing).

No `Color(...)` asset references, no `@Environment(\.colorScheme)` reads anywhere.

---

## The seam / the work

There is no seam yet — creating one is most of the job:

1. **Introduce a semantic colour layer.** Either an asset-catalogue colour set
   with light/dark variants (`Assets.xcassets`, referenced as
   `Color("hudBackground")` etc.), or a Swift `enum Palette` returning
   `Color` values that branch on `@Environment(\.colorScheme)`. Asset catalogue
   is the idiomatic choice and gets automatic dark/light + high-contrast
   variants for free. Names should be **semantic** (`surface`, `onSurface`,
   `accent`, `restActive`, `warning`) not literal (`white`, `green`).
2. **Replace every literal colour** in `App/Views/` with a semantic reference.
   Mechanical but touches most view files — do it as one reviewed commit per
   view or one sweep, your call.
3. **Gate the forcing.** Replace the unconditional `.preferredColorScheme(.dark)`
   with a value derived from a setting (see OPEN QUESTIONS): `.dark`, `.light`,
   or `nil` (follow system).
4. **Add the setting.** `SettingsStore` (UserDefaults) gains an
   `appearance: Appearance` (`.system` / `.light` / `.dark`, default `.dark` to
   preserve current behaviour). `SettingsModel` exposes it; `SettingsView` gets
   a picker. This is the only package-layer change and it's a small TDD slice
   (`SettingsModel` already has the pattern: a mirrored `@Observable` property +
   a setter that writes through to `SettingsStore` — see `unit`,
   `analyticsEnabled`).
5. **Design the light palette.** Not a code task — a design pass. The HUD is a
   glanceable, arms-length, mid-workout surface; a naive white background may
   fail the "readable across a gym" bar the dark design was chosen for.

---

## Acceptance tests

Package-level:

1. `SettingsStore` round-trips `appearance`; default is `.dark`.
2. `SettingsModel.appearance` mirrors the store and the setter persists +
   re-renders (mirror the existing `unit` / `analyticsEnabled` tests).

View-level (`TrackitTests`, needs the Xcode build):

3. A snapshot/appearance UI test of the HUD in light and in dark — the big
   number, the talk button, and the rest ring all have sufficient contrast in
   both. (If snapshot testing isn't set up, this is a manual checklist line.)
4. Toggling the setting flips the whole app including the HUD, with no restart.
5. `.system` follows the device setting live.
6. Existing accessibility checks (Larger Text on the HUD number, Reduce Motion)
   still pass in light mode.

Device: eyeball the light HUD outdoors / under gym lighting — the reason dark
was chosen in the first place.

---

## OPEN QUESTIONS

> **All 4 resolved 2026-09-15** (owner route: accepted every recommendation via
> `AskUserQuestion`). Scope = **(b) non-HUD only**: `HUDView` (and only
> `HUDView`) stays permanently forced-dark; everything else in `RootView` —
> `OnboardingView`, `LaunchGateView`, and every screen reachable through the
> `NavigationStack`'s pushed destinations (`HistoryListView`,
> `MuscleGroupStimulusView`, `SettingsView`, `ExerciseLibraryView`,
> `ExerciseEditView`, `SetEditView`, `WorkoutDetailView`,
> `RecognitionReviewView`, `SetListSheet`, `TapSelectSheet`, `ShareSheet`) —
> respects a new explicit `appearance` setting (`.system`/`.light`/`.dark`,
> default `.dark`). High-contrast variants are out of scope for this pass. A
> re-grep of every `App/Views/*.swift` file except `HUDView.swift` (done as
> part of resolving Q3, see below) found the non-HUD screens already use only
> SwiftUI's dynamic system colours (`.secondary`, `.primary`, `.red`,
> `.yellow`) — no asset-catalogue colour set or custom `Palette` enum is
> needed. The only two literal-colour offenders are `LaunchGateView.swift:12`
> and `OnboardingView.swift:19` (each a single `.foregroundStyle(.white)`).
> This considerably shrinks the "Effort" estimate below — see the updated
> section at the end of this file.

1. **Does light mode ship at all, and how far?** Options:
   - (a) **No.** Keep forced-dark; close this item as "won't do, brand
     decision". Legitimate given the master spec's stance.
   - (b) **Non-HUD only.** History / Progress / Settings / Export respect the
     system setting; the HUD stays forced-dark ("the HUD is the brand, the rest
     is a normal app").
   - (c) **Full light mode** with a designed light palette everywhere including
     the HUD, plus a `system/light/dark` setting.
   This choice determines whether steps 1–5 above are all needed or just a
   subset.
      > **Resolved 2026-09-15: (b) non-HUD only.** The exact boundary is
      > `HUDView` — the screen rendered by `RootView`'s `else` branch (`if
      > onboardingModel.shouldShowOnboarding { OnboardingView } else if
      > model.pendingStaleWorkout != nil { LaunchGateView } else { NavigationStack
      > { HUDView … } }`). Only `HUDView` keeps a scoped, unconditional
      > `.preferredColorScheme(.dark)`. `OnboardingView` and `LaunchGateView`
      > are classified as "the rest of the app," not "the HUD" — they're
      > infrequently-seen framing screens (first-run, resume-prompt), not the
      > glanceable mid-workout surface the brand language is about, and the
      > original spec's own framing ("the rest is a normal app") reads them in.
      > Every screen reached through the `NavigationStack`'s pushed
      > destinations (`HistoryListView`, `MuscleGroupStimulusView`,
      > `SettingsView`, and everything nested under those —
      > `ExerciseLibraryView`, `ExerciseEditView`, `SetEditView`,
      > `WorkoutDetailView`, `RecognitionReviewView`, `SetListSheet`,
      > `TapSelectSheet`, `ShareSheet`) also respects the setting — pushed
      > destinations do **not** inherit a `.preferredColorScheme` applied only
      > to `HUDView`'s own content, since they're separate views inserted onto
      > the stack, not descendants of that content — so no extra work is needed
      > to keep them out of the forced-dark scope.
      > **Mechanical consequence for `RootView.swift`:** the shared
      > `Color.black.ignoresSafeArea()` at line 25 currently paints behind all
      > three branches (Onboarding, LaunchGate, HUD). It must move from the
      > outer `ZStack` to specifically the HUD branch (wrapped around
      > `NavigationStack { HUDView … }` alongside the relocated
      > `.preferredColorScheme(.dark)`), or Onboarding/LaunchGate would render
      > light-mode text on a hardcoded black background. This is the one
      > structural change `RootView.swift` needs beyond the setting itself.
2. **Setting vs. pure system-follow.** If light mode ships, is there an in-app
   `system/light/dark` picker (like many apps) or does it just honour the OS
   setting with no control? A picker is more work (step 4) but expected by users.
      > **Resolved 2026-09-15: explicit picker.** `SettingsStore` gains an
      > `appearance: Appearance` (`.system`/`.light`/`.dark`) property,
      > `default .dark` — preserving the current out-of-the-box look for
      > non-HUD screens until a user opts in, mirroring the existing
      > `unit`/`analyticsEnabled` pattern (`SettingsStore` persists,
      > `SettingsModel` mirrors as `@Observable` + a setter that writes
      > through). `SettingsView` gets a picker. `RootView` maps
      > `settingsModel.appearance` to a `ColorScheme?` (`nil` for `.system`)
      > and applies it to everything **except** the `HUDView` branch, which
      > stays hardcoded `.dark` regardless of this setting.
3. **Light palette design.** Who designs it? The dark palette is essentially
   `black / white / green / secondary`. The light equivalent is not "invert" —
   `green` on white, the talk-button fill, and the "rest target reached" signal
   all need deliberate choices. Needs a design consultation, and it interacts
   with 7c's Live Activity and 7f's Watch complication (both should use the same
   semantic palette).
      > **Resolved 2026-09-15: proposed now, and it turns out to be nearly
      > free.** Re-grepped every `App/Views/*.swift` file except `HUDView.swift`
      > for colour literals (`Color\.`, `.white`, `.black`, `foregroundStyle`,
      > `foregroundColor`, `.background(`). Result: non-HUD screens already use
      > **only SwiftUI's dynamic system colours** — `.secondary` (11 sites:
      > `ExerciseLibraryView`, `MuscleGroupStimulusView`, `LaunchGateView`,
      > `HistoryListView`, `SetEditView`, `OnboardingView`, `SettingsView` ×4),
      > `.primary` (`RecognitionReviewView`), `.red` (error text in
      > `ExerciseEditView`, `WorkoutDetailView`), `.yellow` (the PR-trophy badge
      > in `WorkoutDetailView`) — every one of which already auto-adapts to
      > light/dark with zero code changes. There is **no** decorative `.green`
      > anywhere outside `HUDView` (confirms Q5 below). The only two literal
      > offenders are `LaunchGateView.swift:12` and `OnboardingView.swift:19`
      > (`.foregroundStyle(.white)` on each screen's headline) — both become
      > `.foregroundStyle(.primary)` (or drop the modifier: `.primary` is the
      > default). **No asset-catalogue colour set and no custom `Palette` enum
      > are needed for this scope** — the "semantic colour layer" the original
      > spec anticipated already exists as SwiftUI's built-in dynamic colours,
      > because forced-dark previously masked the fact that non-HUD screens were
      > never actually hardcoded beyond those two spots. The
      > `black/white/green/secondary` palette this question describes is
      > `HUDView`'s alone (out of scope, Q1) — nothing here interacts with 7c's
      > Live Activity or 7f's Watch complication, since neither touches non-HUD
      > screens; if 7c or 7f ever need a semantic palette of their own, that is
      > a separate, later design pass.
4. **High contrast / accessibility variants.** Asset catalogue supports
   "any/light/dark" × "normal/high contrast". In scope, or just light/dark?
      > **Resolved 2026-09-15: just light/dark.** High-contrast variants are
      > explicitly out of scope for this pass — a later accessibility pass, if
      > wanted. Consistent with Q3's finding: there is no asset catalogue in
      > play here to add variants to.
5. **The `one-meaning` colour rule.** The README work (`git log`: *"drop
   decorative green per one-meaning rule"*) suggests the project has a rule that
   a colour carries exactly one meaning. The light palette must preserve that —
   green = "good / target reached", nothing else. Confirm the rule and apply it.
      > **Resolved 2026-09-15: confirmed, already respected, no change needed.**
      > The Q3 grep is exhaustive for non-HUD screens and found zero uses of
      > `Color.green` or `.green` outside `HUDView.swift` — the rule already
      > holds today, this diff doesn't touch it, and there is nothing to remap.
      > `WorkoutDetailView`'s `.yellow` trophy badge is a distinct colour for a
      > distinct meaning (a PR achievement, not "target reached") and doesn't
      > collide with the rule. Worth reasserting as a review criterion on any
      > future PR that touches `App/Views/`, but no doc changes are needed by
      > this resolution alone.

---

## Effort

**Resolved 2026-09-15 — smaller than originally estimated.** No design pass
needed (Q3's grep found the palette was already SwiftUI-dynamic everywhere
except two literals). Real work: (1) `SettingsStore`/`SettingsModel`
`appearance` slice — a small TDD slice, same shape as `unit`; (2)
`SettingsView` picker; (3) `RootView.swift` restructuring — move
`.preferredColorScheme(.dark)` and `Color.black.ignoresSafeArea()` from the
shared `ZStack` to scope around the HUD branch only, and apply
`settingsModel.appearance` to the rest; (4) swap the two `.white` literals in
`LaunchGateView.swift`/`OnboardingView.swift` to `.primary`. No `Assets.xcassets`
work, no new `Palette` type. Rough: **2–3 hours**, not half a day. No
`writing-plans` pass needed — small enough for direct TDD slices. No device
work beyond an eyeball check of light mode on a simulator/device (not a hard
gate — nothing here is arms-length/gym-lighting-critical like the HUD).

## Status

- [x] OPEN QUESTION 1 resolved — **(b) non-HUD only**, boundary = `HUDView`
      alone stays forced-dark. Done 2026-09-15.
- [x] OPEN QUESTIONS 2–5 resolved — explicit picker (Q2), palette designed
      and found to need no new abstraction (Q3), light/dark only, no
      high-contrast (Q4), one-meaning rule confirmed already respected (Q5).
      Done 2026-09-15.
- [x] `appearance` setting slice (`SettingsStore` + `SettingsModel`) — TDD.
      Done 2026-09-15 (`850c7de`, `1a386cd`): `Appearance` enum, protocol +
      `InMemorySettingsStore` conformance, mirrored `SettingsModel.appearance`.
- [x] `SettingsView` picker. Done 2026-09-15 (`d697704`): segmented
      System/Light/Dark picker with a footer noting the HUD stays dark.
- [x] `RootView.swift`: scope `.preferredColorScheme(.dark)` +
      `Color.black.ignoresSafeArea()` to the HUD branch only; apply
      `settingsModel.appearance` elsewhere. Done 2026-09-15 (`d697704`) —
      attached to `HUDView`'s own content inside the `NavigationStack`
      (not the stack itself), per Q2's inheritance note, so pushed
      destinations pick up `settingsModel.appearance` instead.
- [x] `LaunchGateView.swift:12` / `OnboardingView.swift:19`: `.white` →
      `.primary`. Done 2026-09-15 (`d697704`).
- [ ] light-mode eyeball check (simulator/device), not a hard gate —
      left for the device-verification pass (cluster 5); nothing here is
      gym-lighting-critical like the HUD.
- [x] update parent roadmap + memory. Done 2026-09-15: merged via PR #17;
      `2026-09-11-v1.1-remaining-INDEX.md`'s status snapshot updated.
