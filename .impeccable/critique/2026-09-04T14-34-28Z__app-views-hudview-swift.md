---
target: HUDView
total_score: 25
max_score: 40
na_heuristics: 
p0_count: 2
p1_count: 4
target_identity: "file:/Users/Apple/projects/trackit/App/Views/HUDView.swift"
target_fingerprint: "sha256:0a08e6aec28e8ac4edcd3618e7c53a5624e143fbf978456bcdb716e67bb23389"
target_path: /Users/Apple/projects/trackit/App/Views/HUDView.swift
timestamp: 2026-09-04T14-34-28Z
slug: app-views-hudview-swift
closed: true
---
Method: dual-agent (A: design-director review · B: native mechanical/HIG audit — substituted for `detect.mjs`/browser evidence, which are web-only and don't apply to this SwiftUI screen; this environment also has no Xcode/xcodebuild, so no Simulator screenshot was obtainable either. B audited from source against `ios.md` and `DESIGN.md`'s pinned tokens instead, the same substitution `/impeccable audit`'s native variant makes.)

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|---|---|---|
| 1 | Visibility of System Status | 2/4 | No transient "processing/confirmed" state between releasing the talk button and the next render — button just flips back to idle (HUDView.swift:129-144). Confirmed independently by B: zero press-state feedback beyond the model round-trip. |
| 2 | Match Between System and Real World | 3/4 | Scoreboard framing, "225 for 5"-style lines, plain gym copy. |
| 3 | User Control and Freedom | 3/4 | Swipe-up edit/delete sheet works well; tap-select dismiss path is ambiguous. |
| 4 | Consistency and Standards | 2/4 | Talk button is `Text` + raw `DragGesture`, not a `Button` (HUDView.swift:129-144) — no standard control semantics. B confirms mechanically: no `.buttonStyle`, no built-in highlight. |
| 5 | Error Prevention | 3/4 | Tap-select disambiguation (HUDView.swift:89-93) prevents wrong-exercise logging well. |
| 6 | Recognition Rather Than Recall | 2/4 | Swipe-up-to-see-set-list (HUDView.swift:109-112) has zero on-screen affordance. |
| 7 | Flexibility and Efficiency | 3/4 | Press-hold suits the target user; appropriate for a single-path voice flow. |
| 8 | Aesthetic and Minimalist Design | 4/4 | Nothing extraneous; matches the documented "Blackout Board" system exactly — B confirms zero drift between code and DESIGN.md's pinned tokens. |
| 9 | Help Recognize/Diagnose/Recover from Errors | 1/4 | No on-screen signal for a mis-hear; tap-select dismiss silently drops the utterance (HUDView.swift:41-47). |
| 10 | Help and Documentation | 2/4 | "Hold to talk" is the only in-context instruction; no first-run cue. |
| **Total** | | **25/40** | **Acceptable** |

## Design Specificity Verdict

**A (design review):** This reads as authored for the stated use case, not generic. The "Two Numbers Rule" (HUDView.swift:63,118 — one 64pt bold-rounded number for the last set, one 40pt medium-rounded number for rest) genuinely optimizes for a glance rather than a read, and press-and-hold rather than tap (HUDView.swift:139-143) matches a hands-busy/chalky-grip interaction model no generic dashboard would bother with. Where it stops feeling bespoke: the confirmation moment is entirely silent — a screen built around "you shouldn't have to look" has no signal *for when you do look* right after releasing.

**B (mechanical cross-check):** DESIGN.md's self-description matches the code exactly, value for value — talk button (24pt radius, 96pt height, white/green fill), rest capsule (16pt radius, 2pt stroke, 12/24pt padding), display type (64pt/700 and 40pt/500, both `design: .rounded`) all check out against HUDView.swift/RootView.swift with **no drift found**. Zero raw hex or `Color(red:)` anywhere — the "semantic colors only" claim is literally true, not aspirational. This is a real, deliberately-built system, not a documentation exercise layered on top after the fact.

## Overall Impression

The one screen with a real design point of view earns it — black canvas, two huge numbers, one accent color, built for a glance not a read. But the design's entire premise ("confirm without demanding attention... you shouldn't need to look at the screen") is only half-built: it's silent to a screen reader (2 blocking accessibility gaps) and silent to a sighted user's actual glance right after releasing the button (no confirm/processing state). The biggest opportunity is closing that second gap — it's a design/motion fix, not a rewrite, and it would also naturally give VoiceOver something to hook an announcement to.

## What's Working

- **The Two Numbers Rule is enforced structurally, not just documented** — `lastSetLine` (64pt bold rounded) and `restLine` (40pt medium rounded) are the only two things at that scale anywhere in the screen (HUDView.swift:62-68).
- **Every pixel value in code matches the pinned DESIGN.md tokens exactly** — talk button, rest capsule, and both display type sizes cross-checked with zero discrepancies. The design system is real, not decorative.
- **`isListening` drives both fill color and label text** ("Hold to talk" ↔ "Listening…", HUDView.swift:130,137) — one state, at least, gets a genuine multi-channel signal instead of color alone.

## Priority Issues

**[P0] Talk button has no VoiceOver exposure.** *What:* `talkButton` (HUDView.swift:129-144) is a `Text` driven by a raw `.simultaneousGesture(DragGesture)`, with zero `.accessibilityLabel`/`.accessibilityAddTraits`/`.accessibilityHint` anywhere in the file or its four sheets (grep-confirmed by both assessments). *Why it matters:* VoiceOver's touch-exploration model doesn't map to a bare drag gesture — a screen-reader user cannot execute this app's one core interaction at all. *Fix:* give the control real accessibility semantics (`.accessibilityAddTraits(.isButton)` at minimum) plus a documented accessible activation path — a paired `.accessibilityAction` for start/stop, since VoiceOver users can't literally hold-and-drag the way a sighted user does. *Suggested command:* `/impeccable harden`.

**[P0] Swipe-up-to-edit is entirely unreachable via VoiceOver.** *What:* the gesture that reveals the set-list sheet (HUDView.swift:109-112, `DragGesture(minimumDistance: 20)`, threshold -40pt) has no `.accessibilityAction` fallback. *Why it matters:* every edit/delete path on this screen routes through that sheet — a VoiceOver user has no way in, at all, not even a degraded one. *Fix:* add an explicit accessible entry point (an always-present, VoiceOver-reachable button that opens the same sheet) alongside the gesture. *Suggested command:* `/impeccable harden`.

**[P1] No confirm/processing state after releasing the talk button.** *What:* between `released()` and the next render there is only idle/listening (HUDView.swift:130,137) — no transient state for "captured, resolving." *Why it matters:* this directly undercuts the product's own principle ("confirm without demanding attention") at the exact moment a glance would matter most — and independently, B found zero press-state feedback on the same control, compounding the gap. *Fix:* a brief transient state on `lastSetLine`'s change (`.contentTransition`, a short pulse/flash) so a mid-transition glance still reads success. *Suggested command:* `/impeccable animate`.

**[P1] Hard-coded 64pt/40pt display sizes ignore Dynamic Type.** *What:* `.font(.system(size: 64...))` (HUDView.swift:63) and `.font(.system(size: 40...))` (line 118) don't scale with the user's text-size setting, against ios.md's explicit "no hard-coded point sizes" rule. *Why it matters:* both assessments flagged this, but disagreed on severity (A: P2, defensible as an intentional glanceable-distance constant per the Two Numbers Rule; B: P1, a literal platform-rule violation regardless of intent) — reconciled here as P1, because the two truths coexist: the *design intent* behind fixed sizes is legitimate, but it doesn't exempt the app's two most important numbers from growing for a low-vision user, which is a real, uncovered gap either way. *Fix:* `@ScaledMetric` off a text-style base, capped at a sane maximum so layout doesn't break. *Suggested command:* `/impeccable typeset`.

**[P1] No press-state feedback on the talk button.** *What:* a bare `Text` + gesture with no `.buttonStyle`, scale, or opacity change on touch-down (HUDView.swift:129-144) — the only visual change is the `isListening` fill swap, which depends on a model round-trip, not the touch itself. *Why it matters:* the single most-used control in the app gives no immediate physical feedback that a touch registered, before the app has even processed it. *Fix:* add an immediate `.scaleEffect`/opacity dip on gesture-began, independent of `isListening`. *Suggested command:* `/impeccable delight`.

**[P1] Tap-select dismiss silently drops the spoken set.** *What:* dismissing `TapSelectSheet` without picking calls `model.dismissTapSelect()` (HUDView.swift:44) with no resulting on-screen state change — the code's own comment says it "leaves the workout untouched," but the user has no way to distinguish "I cancelled" from "my set vanished." *Why it matters:* directly contradicts the product's central trust claim ("don't make me look at the screen to know it logged correctly"). *Fix:* surface a brief "Not logged" state on dismiss-without-pick. *Suggested command:* `/impeccable clarify`.

## Persona Red Flags

**Sam (accessibility-dependent):** Total accessibility blackout, mechanically confirmed — zero `.accessibility*` modifiers anywhere in HUDView.swift or its sheets. The talk button, the tap-select-vs-set-list sheet routing (line 35-48), and the rest capsule's color-only state change (green = target reached, line 119) all depend on sight plus a gesture VoiceOver can't drive out of the box.

**Casey (one-handed/interrupted):** The swipe-up gesture (line 109-112) can fire from an awkward one-handed adjustment mid-set, popping a sheet that fully covers the rest timer with no confirm step — exactly the moment the product claims you shouldn't need to look, and now you're forced to.

**Jordan (first-timer):** The very first set of a workout renders `exerciseName = "No exercise yet"` (HUDProjection.swift:46) next to `lastSetLine ?? "—"` (HUDView.swift:62) with a generic "Hold to talk" button — no state-specific copy telling a brand-new user what to actually do.

## Minor Observations

- Rest-target-reached (HUDView.swift:119,124) is conveyed by color change alone — no accompanying icon, text, or shape change (B, P2).
- `SetEditView` has no explicit Cancel button in its toolbar (only `.confirmationAction` "Save") — swipe-to-dismiss genuinely covers it (no `.interactiveDismissDisabled` found anywhere), so this is soft, but ios.md calls for a "clear Cancel/Done" (B, P2).
- The `historyUnavailable` banner (HUDView.swift:52-56) uses the same `.footnote`/secondary style as the routine "vs last time" line — an error condition that's easy to visually merge with normal copy.
- `restCard` disappearing entirely when there's no `restLine` reflows the whole VStack rather than reserving space — a layout jump between sets.
- Rest capsule's idle stroke, `Color.secondary.opacity(0.4)` (line 124), is a low-opacity boundary — worth a contrast sanity-check even though the estimated ratios elsewhere came back safe.

## Questions to Consider

1. If VoiceOver support is truly "undecided" per PRODUCT.md, is that a real product stance, or is it functioning as permission to ship a control the target user (older/injured lifters skew toward accessibility needs) literally cannot operate?
2. The product's trust claim is "don't make me look at the screen to know it logged correctly" — but the screen currently gives zero visual signal in the 1-2 seconds after release. Is that silence intentional, or did nobody actually look?
3. What's the recovery story when a tap-select sheet gets dismissed by accident mid-set — does the lifter only find out their rep is unlogged at the end of the workout?
