---
name: Trackit
description: A voice-first workout logger with a black-canvas, glanceable live HUD and plain system screens everywhere else.
colors:
  hud-black: "#000000"
  hud-white: "#FFFFFF"
  go-green: "#30D158"
  pr-yellow: "#FFD60A"
  error-red: "#FF453A"
typography:
  display:
    fontFamily: "SF Pro Rounded, ui-rounded, -apple-system"
    fontSize: "64pt"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "normal"
  display-secondary:
    fontFamily: "SF Pro Rounded, ui-rounded, -apple-system"
    fontSize: "40pt"
    fontWeight: 500
    lineHeight: 1
    letterSpacing: "normal"
  headline:
    fontFamily: "SF Pro Text, -apple-system"
    fontSize: "22pt"
    fontWeight: 600
    lineHeight: 1.2
  body:
    fontFamily: "SF Pro Text, -apple-system"
    fontSize: "17pt"
    fontWeight: 400
    lineHeight: 1.3
  label:
    fontFamily: "SF Pro Text, -apple-system"
    fontSize: "12pt"
    fontWeight: 400
    lineHeight: 1.2
rounded:
  sm: "16pt"
  lg: "24pt"
spacing:
  sm: "12pt"
  md: "24pt"
  lg: "28pt"
  xl: "32pt"
  xxl: "40pt"
components:
  talk-button:
    backgroundColor: "{colors.hud-white}"
    textColor: "#000000"
    typography: "{typography.headline}"
    rounded: "{rounded.lg}"
    height: "96pt"
    width: "100%"
  talk-button-listening:
    backgroundColor: "{colors.go-green}"
    textColor: "#000000"
    typography: "{typography.headline}"
    rounded: "{rounded.lg}"
    height: "96pt"
    width: "100%"
  rest-capsule:
    backgroundColor: "transparent"
    textColor: "{colors.hud-white}"
    typography: "{typography.display-secondary}"
    rounded: "{rounded.sm}"
    padding: "12pt 24pt"
  rest-capsule-reached:
    backgroundColor: "transparent"
    textColor: "{colors.go-green}"
    typography: "{typography.display-secondary}"
    rounded: "{rounded.sm}"
    padding: "12pt 24pt"
---

# Design System: Trackit

## Overview

**Creative North Star: "The Blackout Board"**

Trackit has exactly one screen with a real visual identity — the live-workout
HUD — and it reads like a gym scoreboard or digital clock readout mounted on a
dark wall: a black canvas, a handful of huge SF Rounded numerals, one accent
color, and nothing to focus your eyes on beyond what you need mid-set. Every
other screen (history, workout detail, set editing, exercise progress) is
plain, unstyled system List/Form UI — no custom chrome at all. That split is
deliberate, not unfinished: the HUD is used mid-set, hands busy, not really
looking; everything else is a normal careful touch review done after the
workout, where a stock iOS list is exactly right and any decoration would be
noise.

The mood is calm, utilitarian, no-nonsense — closer to purpose-built gym
equipment than a consumer fitness app. **Anti-reference:** gamified fitness
apps with badges, streak flames, confetti, and bright multi-color dashboards.
Trackit has exactly one celebratory moment (the personal-record trophy) and
otherwise stays quiet.

**Key Characteristics:**
- One screen (the HUD) carries the whole visual identity; the rest is stock system UI.
- Pure black background, forced dark appearance app-wide — never light mode.
- One accent color (green) means "go / on-target"; everything else is white, black, or system gray.
- Huge SF Rounded, bold numerals for the two numbers that matter mid-set (last set logged, rest clock).
- Flat everywhere — no shadows anywhere in the app.
- Monospaced digits wherever a number is meant to be scanned (set lines, rest clock, last-set line).

## Colors

Small, disciplined palette: mostly black/white/gray, with color reserved for one meaning.

### Primary
- **Blackout Black** (`#000000`): The HUD's entire background (`Color.black.ignoresSafeArea()` in `RootView`), forced app-wide via `.preferredColorScheme(.dark)`. Not "dark mode support" — the app has no light appearance.
- **Board White** (`#FFFFFF`): Primary text on the HUD (exercise name, last-set line) and the idle talk-button's fill with black text on top.

### Secondary
- **Go Green** (`#30D158`, system `Color.green`, dark-appearance value): The app's one accent, meaning "go / on-target" — the talk button fills green while actively listening, and the rest-timer capsule turns from white-on-transparent to green once the rest target is reached. It never appears for anything else.

### Neutral
- **System Secondary** (dynamic, `Color.secondary` / `.foregroundStyle(.secondary)`): Supporting text throughout — the "vs last time" line, history row subtitles, empty-state descriptions. Left as the system semantic token, not a fixed hex, so it tracks the platform.
- **PR Yellow** (`#FFD60A`, system `Color.yellow`): The personal-record trophy badge (`trophy.fill`) in workout detail — the app's one deliberately celebratory mark.
- **Error Red** (`#FF453A`, system `Color.red`): Reserved for things that went wrong and need the lifter's attention — save-error text in the workout detail list, and the live HUD's "Not logged" notice when a spoken set is dismissed unresolved. Not used for anything else.

### Named Rules
**The One Meaning Rule.** Green means exactly one thing — "go / on-target" (listening, rest target reached). It is never used decoratively and never means anything else.

**The Undecorated Accent Rule.** Outside the HUD, interactive elements (links, chart lines, the segmented picker) use the plain system tint color, left completely untouched — no `.tint()` override exists anywhere in the app. This is a deliberate non-choice: the system default is correct here, not a placeholder waiting to be branded.

## Typography

**Display Font:** SF Pro Rounded (`design: .rounded`), used only for the HUD's two headline numbers.
**Body Font:** SF Pro Text (the system default), used everywhere else via the standard Dynamic Type text styles.

**Character:** Rounded, heavy numerals for the two numbers you need at a glance mid-set; restrained system type for everything you read carefully after the workout.

### Hierarchy
- **Display** (bold 700, 64pt, SF Rounded): The last set logged (`"225 for 5"`) — the single biggest, boldest thing on screen.
- **Display Secondary** (medium 500, 40pt, SF Rounded): The rest-timer readout (`"1:05 / 2:00"`), inside the rest capsule.
- **Headline** (semibold 600, ~22pt / `.title2`–`.title3`): The active exercise name on the HUD; row titles (history dates, section headers).
- **Body** (regular, 17pt): List rows, form fields, note text. **Monospaced-digit variant** wherever the text is a formatted set line (e.g. `"225 lb x 5"`) — history detail rows, the swipe-up set list — so numbers align and don't jiggle.
- **Label** (regular, ~12pt / `.caption`–`.footnote`): Secondary/supporting lines — "vs last time," row subtitles, empty-state descriptions.

### Named Rules
**The Two Numbers Rule.** SF Rounded display type is reserved for exactly two values: the last set logged and the rest clock. Nothing else on the HUD, and nothing off the HUD, uses it.

Both hold their 64pt/40pt size through every standard Dynamic Type step — a scoreboard readout that doesn't reflow underfoot — and only grow past that at the accessibility text sizes, via `@ScaledMetric` borrowing largeTitle's/title's own scale ratio rather than a hand-picked multiplier.

## Layout

Two distinct layout modes:

- **The HUD** is a single centered `VStack` (28pt spacing) padded 32pt from the edges: exercise name → last-set line → rest capsule → "vs last time" → spacer → full-width talk button. Nothing scrolls; everything fits one screen. A swipe-up gesture (drag past -40pt) reveals the current entry's set list as a sheet sized to `[.medium, .large]` detents.
- **Everything else** is a standard `NavigationStack` over system `List`/`Form` with `Section`s — history, workout detail, set editing, exercise progress. No custom grid, no bespoke card layout; density and spacing follow the system list/form defaults throughout.
- The stale-workout resume gate (`LaunchGateView`) is a centered `VStack` (32pt spacing, 40pt padding) — the one other screen that shares the HUD's black canvas and centered-column layout rather than a list.

## Elevation & Depth

Flat by design — **no `.shadow()` call exists anywhere in the app.** Depth and state are conveyed by fill vs. stroke, not by shadow or blur: a filled shape reads as active/on (the talk button's white or green fill), a stroked outline reads as idle/tracking (the rest capsule's default state, a 2pt stroke at `Color.secondary.opacity(0.4)`). System sheets and navigation use the platform's own material and elevation; the app never adds any of its own.

### Named Rules
**The No-Shadow Rule.** Depth is fill vs. stroke and color, never a drop shadow. If a control needs to look "raised," give it a solid fill instead.

## Shapes

Two corner radii cover the entire app: **16pt** (the rest-timer capsule) and **24pt** (the talk button — the largest, most rounded shape in the app, matched to its status as the one control used under pressure). Everywhere else, shape comes from the system (list rows, form sections, sheet corners, system buttons) and is never touched directly.

## Components

### Talk Button (signature component)
- **Character:** Blunt and confident — the app's one unmissable control, sized and shaped to be hit without looking.
- **Shape:** 24pt corner radius, full width, 96pt tall (well over the 44pt touch-target minimum).
- **Idle:** White fill (`#FFFFFF`), black `.title3.weight(.semibold)` label ("Hold to talk").
- **Listening:** Fill switches to Go Green (`#30D158`), same black label, text changes to "Listening…". Driven by a `simultaneousGesture` press, not a tap — hold, don't tap.
- **Processing:** Fill stays white (never a second accent), label reads "Working…", with a slow breathing opacity pulse while the released speech is still finalizing/parsing — off entirely under Reduce Motion, where the label change alone carries the state.
- **Press:** The instant a touch (or VoiceOver's synthesized touch) registers — before `isListening` even flips — the button scales to 0.97 and a light impact haptic fires. Purely a touch acknowledgment, decoupled from listening/processing, so it never waits on the model.

### Rest Capsule (signature component)
- **Character:** Blunt and confident, same as the talk button, at a smaller scale.
- **Shape:** 16pt corner radius, 24pt horizontal / 12pt vertical padding, 2pt stroke (no fill).
- **Idle/counting:** White display-secondary text, `Color.secondary.opacity(0.4)` stroke.
- **Target reached:** Text and stroke both switch to Go Green — the same accent, same meaning, as the listening talk button.

### Lists (History, Set List, Progress)
- **Style:** Stock system `List`, default styling, no custom row backgrounds or dividers.
- **Row content:** `VStack`, 4pt spacing, headline → secondary subheadline → caption totals (history rows); monospaced-digit body text for set lines, with a yellow `trophy.fill` badge trailing any personal-record set.
- **Empty states:** `ContentUnavailableView` with an SF Symbol, system default — no custom illustration.

### Forms (Set Editor)
- **Style:** Stock system `Form`/`Section`, no customization — segmented `Picker` for set role, `Stepper` for reps, `Toggle` for dropset, destructive-role `Button` for delete.
- **Save/confirm:** `.confirmationAction` toolbar placement (top-right "Save"), the system default location, never a custom footer button.

### Charts
- **Style:** Swift Charts `LineMark` + `PointMark`, default system chart styling and default tint — no custom chart colors. Fixed 160pt height per series (Load, Volume, Estimated 1RM).

## Do's and Don'ts

### Do:
- **Do** keep the HUD's black canvas and forced dark appearance — the app has no light mode, and that's intentional, not a gap.
- **Do** reserve Go Green for exactly one meaning: "go / on-target." Never introduce it as decoration.
- **Do** use SF Rounded display type only for the last-set line and the rest clock — the "Two Numbers Rule."
- **Do** use monospaced digits for any text that's a formatted quantity (set lines, timers) so numbers don't jiggle when they update.
- **Do** default to stock system List/Form/NavigationStack for every screen outside the HUD — that plainness is correct for post-workout review, not a placeholder waiting for polish.
- **Do** size any new mid-workout control at least as generously as the talk button (96pt) — it may be used without looking.

### Don't:
- **Don't** add shadows, blur, or glassmorphism anywhere — depth comes from fill vs. stroke only.
- **Don't** give the app a second accent color. One green, used one way, is the whole rule.
- **Don't** add badges, streaks, confetti, or other gamification chrome — the personal-record trophy is the app's only celebratory moment, and it stays that way.
- **Don't** style the history/detail/edit/progress screens with custom chrome to "match" the HUD — they're deliberately plain system UI, and that split between "live" and "review" screens is load-bearing, not incidental.
