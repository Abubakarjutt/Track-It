# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

Serious lifters running a structured strength or hypertrophy program (barbell
and dumbbell training), who log every working set — not narrowed to a single
training style (powerlifting, bodybuilding, etc.). Their situation: mid-workout,
often with chalky or sweaty hands, resting between sets in a gym that may have
no signal. Their job: capture load, reps, and set structure (warmups, bodyweight
and assisted work, timed/distance efforts, supersets, dropsets) accurately, in
the moment, without breaking training focus to operate a phone.

## Product Purpose

Trackit lets a lifter speak each set as they finish it instead of tapping
through a logging UI between sets. Press-to-talk, say the exercise once, say
each set ("225 for 5"); the app logs it immediately with a spoken readback and
haptic confirmation, no need to look at the screen. Success means lifters keep
logging consistently and accurately through an entire workout — rather than
reconstructing sets from memory afterward or abandoning logging altogether —
and end up with a clean, editable record and per-exercise progress over time.

## Positioning

The voice loop is the entire product, not a feature bolted onto a tap-based
logger — a neighboring app (Strong, Hevy, etc.) could add a voice shortcut
without truthfully making this claim. Trackit works fully offline in a loud
gym, understands the vocabulary of structured barbell/dumbbell training
(warmups, bodyweight/assisted work, timed and distance efforts, supersets,
dropsets), and lets the user correct mistakes by repeating the set or saying
"undo" — all without unlocking the phone or hunting through menus mid-set.

## Operating Context

Used live, mid-workout, in a gym: noisy, hands often chalky/sweaty, phone
frequently not looked at during a set. Must work with no network connectivity.
The core loop is push-to-talk → speak exercise/set → spoken readback + haptic
confirmation → rest timer to the next set. After the workout, the user reviews
and edits the completed record and per-exercise progress on-screen (this part
is a normal touch UI, not voice-driven).

## Capabilities and Constraints

- On-device speech recognition and offline operation are a **permanent
  product commitment**, not a v1-only limitation: the app must keep working
  fully offline in a loud gym with no signal, and processing stays on-device
  (the App's own copy already markets "on device" — see Brand Commitments).
  Future work must not quietly introduce a cloud-processing dependency for
  core logging.
- Domain vocabulary and structure (Workout, Entry, Exercise, Set's four
  orthogonal axes, Template, Estimated 1RM, etc.) is canonically defined in
  `Packages/WorkoutLoggerCore/CONTEXT.md` — treat it as the glossary
  authority, not this file.
- Loads are canonicalized and stored in kilograms (ADR-0002); Estimated 1RM
  uses the Epley formula (ADR-0003).
- Multi-week Programs (prescribed progression across workouts) are explicitly
  out of scope for v1.
- iOS only (SwiftUI, SwiftData, iOS 17.0+ deployment target); no Android or
  web surface exists or is implied by the current codebase.
- Portrait-only orientation.

## Brand Commitments

- Product name: **Trackit** (bundle id `com.abubakarsahi.trackit`).
- Existing in-product copy (Info.plist usage strings) already commits to a
  voice-first, on-device framing and should guide tone for future copy:
  - "Trackit listens while you speak each set."
  - "Trackit turns your spoken sets into a workout log, on device."

## Evidence on Hand

None. The product is pre-launch: no App Store presence, no real user
testing, testimonials, screenshots, or press yet. Future work must not
fabricate any of these — state absence rather than inventing placeholder
evidence.

## Product Principles

1. **The voice loop is the product.** Every core logging interaction should
   be completable without looking at or touching the screen beyond
   push-to-talk; touch UI is for before/after the set, not during it.
2. **Never break the set to fix a mistake.** Correction happens by speaking
   again (repeat the set, say "undo") — not by stopping to tap through a
   correction UI mid-workout.
3. **Offline and on-device is non-negotiable.** The app must work fully in a
   gym with no signal; this is a durable trust commitment, not a fallback
   mode.
4. **Confirm without demanding attention.** Spoken readback plus a distinct
   haptic is how the app tells the lifter it heard them correctly — quick,
   peripheral, not a screen the lifter must check.
5. **The post-workout review is where screen UI belongs.** Editing history,
   correcting entries, and viewing progress charts are normal, careful touch
   interactions — precision and clarity matter there in a way they don't
   mid-set.

## Accessibility & Inclusion

No accessibility requirement has been established beyond what the
voice-first, hands-free/eyes-free design inherently provides (no dedicated
VoiceOver, low-vision, or motor-accessibility mandate has been stated). Do
not assume one; treat this as undecided rather than satisfied.
