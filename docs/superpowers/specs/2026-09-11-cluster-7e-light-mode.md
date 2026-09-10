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
2. **Setting vs. pure system-follow.** If light mode ships, is there an in-app
   `system/light/dark` picker (like many apps) or does it just honour the OS
   setting with no control? A picker is more work (step 4) but expected by users.
3. **Light palette design.** Who designs it? The dark palette is essentially
   `black / white / green / secondary`. The light equivalent is not "invert" —
   `green` on white, the talk-button fill, and the "rest target reached" signal
   all need deliberate choices. Needs a design consultation, and it interacts
   with 7c's Live Activity and 7f's Watch complication (both should use the same
   semantic palette).
4. **High contrast / accessibility variants.** Asset catalogue supports
   "any/light/dark" × "normal/high contrast". In scope, or just light/dark?
5. **The `one-meaning` colour rule.** The README work (`git log`: *"drop
   decorative green per one-meaning rule"*) suggests the project has a rule that
   a colour carries exactly one meaning. The light palette must preserve that —
   green = "good / target reached", nothing else. Confirm the rule and apply it.

---

## Effort

If (a): zero code, just close it. If (b): ~half a day. If (c): 1–2 days of code
(the literal-colour sweep is the bulk) **plus a design pass that is the real
gate**. `writing-plans` pass only for (c). Contained to `App/Views/` +
`Assets.xcassets` + one small `SettingsStore`/`SettingsModel` slice.

## Status

- [ ] OPEN QUESTION 1 resolved — decide (a) / (b) / (c)
- [ ] (if b/c) light palette designed
- [ ] (if b/c) semantic colour layer + literal-colour sweep
- [ ] (if b/c) `appearance` setting slice + Settings picker
- [ ] (if b/c) contrast checks light + dark, device eyeball
- [ ] update parent roadmap + memory
