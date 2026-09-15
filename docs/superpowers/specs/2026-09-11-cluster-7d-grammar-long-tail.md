# Cluster 7d — Grammar long-tail (relative / contextual phrasings)

**Prerequisite reading:** `2026-09-11-v1.1-remaining-onboarding.md`.
**Parent:** `2026-09-06-v1.1-deferred-work-design.md` § "Cluster 7" → "Grammar long-tail".
**Master spec framing:** *"'add a plate', 'same as last time', 'back-off set', and
other relative / contextual phrasings. Depends on cluster 1b (`previousSet`
wired) and possibly 1c."*

Cluster 1b is **merged** — the engine already populates `WorkoutContext.previousSet`.
The parser does not consume it yet. This cluster is the pure-Core work of adding
relative grammar forms that lean on that context.

Impl-ready brief; the *scope list* of phrasings is the main open question.

---

## What exists today

`Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/Parser.swift`:

```swift
public func parse(_ transcript: String, context: WorkoutContext, library: ExerciseLibrary) -> [ParseResult]
```

- A **fixed, priority-ordered list of forms** (comments in the file number them):
  1. Commands (exact phrases: `undo`, `start rest`, …)
  2–3. Keyword load sets, then the straight set
  4. Inline set — `<name> <load> [unit] for <reps>`
  5. Duration effort — `<name> for <n> seconds`; Distance — `<name> <n> metres`
  6. Bodyweight set — `<name> <n>`
  7. Bare exercise name / alias — switch active exercise
  Ordering is deliberate and documented: keyword forms must precede the generic
  `<name> <number>` forms or the greedy form swallows everything.
- `private let maxPlausibleReps = 100`, `maxPlausibleLoad = 1000.0`,
  `isPlausible(_ set: ParsedSet) -> Bool` — sanity ceilings.
- **Only `context.unit` currently shapes parsing** (lines 138, 154: fall back to
  `context.unit` when no unit was spoken). `context.previousSet` and
  `context.activeExercise` are carried in the seam but unused by the parser.

`Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/Model.swift`:

- `WorkoutContext` (line 119) — `Equatable, Sendable`; `var previousSet: ParsedSet?`
  (default `nil`), `var unit`, `activeExercise`. Comment: *"carried here so the
  seam does not change shape when [a relative grammar lands]"* — i.e. **this
  cluster is what that sentence anticipated.**

`Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/WorkoutEngine.swift`:

- Line 408–410: builds the context with `previousSet: activePreviousParsedSet`.
- Line 468: `private var activePreviousParsedSet: ParsedSet?` — *"`nil` when no
  [prior set on the active exercise]"*.
- Line 406–407 comment already anticipates *"a tighter repeat-to-retry tolerance,
  relative [grammar]"* leaning on the previous set.

Cluster 6's corpus harness (`CorpusScore.score`) is the natural place to prove
each new form: add a `CorpusEntry` with the spoken phrasing and the expected
`ParseResult`, watch it fail, implement the form, watch it pass.

---

## The seam

**No API change.** `parse` already receives `context.previousSet`. This cluster
adds new *form branches* inside `parse` (and their regex + helper functions) that,
on match, read `context.previousSet` to fill in what the phrasing left implicit.

Placement in the priority list matters: relative forms with distinctive keywords
("same as last time", "add a plate", "back-off set") should sit **near the top**
(with the commands / keyword forms) so they're recognised before the greedy
generic forms. A relative form must **fail closed** — if `context.previousSet` is
`nil`, it should not match (or should produce a "didn't catch that" result), never
guess.

If a form needs richer prior context than `ParsedSet` carries (e.g. "add a plate"
needs to know the bar setup / unit to know what "a plate" weighs), that is a
`WorkoutContext` field decision — call it out, don't silently widen the type.

---

## Candidate phrasings (SCOPE IS AN OPEN QUESTION — see below)

| Phrasing | Means | Needs from `previousSet` |
|---|---|---|
| "same as last time" / "same again" / "again" | repeat the previous set exactly | whole `ParsedSet` |
| "add a plate" / "plate more" | previous load + 2×plate (per side) | load + unit + a "plate" constant |
| "drop a plate" / "take a plate off" | previous load − 2×plate | same |
| "add 10" / "ten more" / "up 10" | previous load + 10 (spoken unit or context unit) | load + unit |
| "down 10" / "ten less" | previous load − 10 | load + unit |
| "back-off set" | a working set at a % of the previous load (typically ~85–90%), same reps | load + reps + a back-off % |
| "two more reps" / "same weight one more rep" | previous load, previous reps ± n | load + reps |
| "one more" (bare, mid-exercise) | previous set repeated | whole `ParsedSet` |
| "half" / "drop set" phrasings | dropset grouping at reduced load | load + grouping axis |

---

## Acceptance tests

All package-level, in `CorpusScoreTests` / `ParserTests` style:

1. Each in-scope phrasing produces the exact `ParseResult` a fully-spoken
   equivalent would, given a specific `context.previousSet`.
2. Each relative phrasing with `context.previousSet == nil` **does not** produce
   a set — it yields whatever the parser's "unrecognised" result is (confirm what
   that is: empty `[]`, or a `.command`/`.miss` shape).
3. A relative phrasing still loses to a fully-explicit set in the same utterance
   (priority ordering holds — add an ordering test).
4. `isPlausible` still guards the computed set (e.g. "add a plate" ten times
   can't push load past `maxPlausibleLoad` silently — decide: clamp, or reject).
5. The 14→N hand-authored corpus rate stays 1.0 for in-scope rows; out-of-scope
   phrasings are explicitly excluded with a note.
6. `WorkoutContext` remains `Equatable, Sendable`; if a field is added, its
   `Codable`-ness / default is covered.

No device work. This is the one Cluster 7 item that is fully verifiable with
`swift test`.

---

## OPEN QUESTIONS

> **All 7 resolved 2026-09-14** (owner route: "go ahead with the
> recommendations"). The shipped scope is the relative forms the master spec
> names plus the Q6-blessed repeat; the plate / back-off numbers are pinned by
> ADR-0004; `ParsedSet.load` is the total (no bar concept, Q4); 1b's
> `previousSet` alone is enough (no 1c signal, Q5); and the relative forms run
> unchanged inside the `postProcess → parse` loop (Q7). Each in-scope form
> has a parameterised test in `RelativeParserTests` (loaded + loadless +
> fail-closed). The corpus harness builds `WorkoutContext()` with no `previousSet`,
> so the relative forms stay out of it and the launch-gate rate is unchanged at
> 1.0 (7d acceptance test #5: out-of-corpus by design, noted here).

1. **Exact scope list.** Which of the candidate phrasings ship in v1.1? The
   master spec names only "add a plate", "same as last time", "back-off set" as
   examples. Pin the full list — each is a small slice, but the total is a
   product decision about how much relative grammar to teach.
      > **Resolved 2026-09-14:** v1.1 ships exactly the forms the master spec names
      > plus the Q6 repeat, and nothing beyond:
      > - **verbatim repeat** — "again", "repeat", "same", "same again",
      > "same as last", "same as last time", and the bare "one more" (Q6)
      > — reproduces the whole previous set at full confidence, a loadless
      > (timed / distance) set included.
      > - **plate steps** — "add a plate" / "drop a plate" (one standard plate
      > per unit; Q2 / ADR-0004).
      > - **numeric delta in the spoken / context unit** — "up N", "add N",
      > "plus N", "down N", "drop N", "N less", "less N".
      > - **back-off** — "back off" / "backoff" / "back off set" (Q3 / ADR-0004).
      > Deferred to a later pass (documented, not shipped): word-number deltas
      > ("ten more" — needs number-word expansion, a parser feature of its own);
      > the synonym spellings "plate more" / "take a plate off"; the reps-adjustment
      > forms ("one more rep" / "two more reps" / "N fewer reps" = previous reps
      > ± N); and "half" / dropset-at-reduced-load. Rationale: the shipped set
      > covers every master-spec example + the Q6 recommendation; the deferred forms
      > need a parser feature (number words) or a further product call, so they sit
      > outside the v1.1 sanctioned-core-extension budget.
2. **"A plate" = how many kg/lb?** 20 kg / 45 lb per side (so +40 kg / +90 lb to
   the bar)? Is it always per-pair, or does "add a plate" mean one plate total?
   Does it depend on the spoken unit / `context.unit`? This needs a constant and
   a rule.
      > **Resolved 2026-09-14 (ADR-0004):** one standard plate **per unit** —
      > 20 kg / 45 lb, applied in the load's own unit (the previous set's
      > `loadUnit`, falling back to the context unit), so "add a plate" on 100 kg
      > gives 120 kg and on 100 lb gives 145 lb. A drop floors at zero. **Not**
      > per-side (×2): the utterance says "a plate", singular. `plateSize(for:)`
      > is the single source of truth; a future user-facing "plate size" setting
      > overrides it rather than re-hardcoding.
3. **"Back-off set" percentage.** 85%? 90%? A fixed value, or does the phrasing
   allow "back-off to 80"? Rounding rule (nearest 2.5 kg / 5 lb)?
      > **Resolved 2026-09-14 (ADR-0004):** a back-off is the previous load at
      > **90%**, rounded to the nearest **smallest plate** (2.5 kg / 2.5 lb) — a
      > fixed fraction the phrasing does not parameterise ("back-off to N%" is not a
      > form). "back off", "backoff", and "back off set" all map to the same form.
      > `backOffFraction` (0.9) and `backOffRoundIncrement(for:)` (2.5 / 2.5) are
      > the source of truth.
4. **Does "add a plate" need bar weight?** If the previous set's load is the
   *total* load, "+a plate" is just arithmetic on that number and no bar concept
   is needed. Confirm `ParsedSet.load` semantics (total vs. added) — likely
   total, per ADR-0002 canonicalisation, but verify.
      > **Resolved 2026-09-14: no bar weight.** `ParsedSet.load` is the **total**
      > load (ADR-0002 canonicalisation), so "+a plate" / "+N" / a back-off is plain
      > arithmetic on that total; no bar-setup concept is needed or stored. Verified
      > against the ADR-0002 tests, which assert the stored load is the bar-inclusive
      > total.
5. **Depends on cluster 1c?** The parent spec says "possibly 1c" (parser
   confidence on confident results). 1c is merged. Confirm whether any relative
   form needs a confidence signal, or whether 1b's `previousSet` alone is enough.
      > **Resolved 2026-09-14: no.** 1b's `previousSet` alone is enough — each
      > relative form is deterministic given the previous set and reports full
      > confidence (1.0), so no confidence signal from 1c is consumed. 1c remains
      > merged and available for other work.
6. **Ambiguity: "one more".** Could mean "one more rep than last set" or "one
   more set, same as last". Which? (Recommend: "one more" = repeat the set;
   "one more rep" = previous reps + 1.)
      > **Resolved 2026-09-14:** "one more" = **repeat the set** — shipped; it
      > joins the verbatim-repeat family (Q1). "one more rep" = previous reps + 1 is
      > the *recommended* reading but is **not** shipped: it needs a reps-adjustment
      > form that does not exist yet and is deferred with the reps±n forms (Q1).
      > No bare-vs-rep collision today, because "one more rep" is not a form yet.
7. **Interaction with n-best.** If hypothesis 1 is "add a plate" and hypothesis 2
   is "add a play", the post-processor picks — does the relative-grammar form
   run inside the existing `postProcess → parse` loop unchanged? (It should
   — confirm no special-casing needed.)
      > **Resolved 2026-09-14: confirmed, no special-casing.** The relative forms
      > run unchanged inside the existing `postProcess → parse` loop — the
      > post-processor picks among n-best by its existing scoring, and each surviving
      > hypothesis then flows through `parse` (which now consults
      > `context.previousSet`). No change to the post-processor or the n-best loop;
      > proven by cluster 6's corpus harness, which runs the whole chain and holds at
      > 1.0.

---

## Effort

Small-to-medium, and low-risk: pure Core, `swift test` only, one slice per
phrasing. **Best first Cluster 7 item.** No `writing-plans` pass needed if the
scope list (Q1) is short; write one if it grows past ~6 phrasings. Respects the
"one core-reopen" note only loosely — this is a *sanctioned* Core extension the
seam was explicitly built for, but confirm with the owner that it doesn't need
its own budget line.

## Status

- [x] OPEN QUESTIONS resolved and written back (Q2/Q3 via ADR-0004, Q4 via
   ADR-0002) — done 2026-09-14, the seven resolutions above.
- [x] one TDD slice per in-scope phrasing, proven in `RelativeParserTests`
    (loaded + loadless + fail-closed) — the verbatim-repeat / plate-step /
   numeric-delta / back-off forms landed on the cluster-1b `previousSet` seam;
   the bare "one more" repeat landed 2026-09-14 this cycle
    (`feat(parser): a bare "one more" repeats the current set`). Each form has a
   parameterised test.
- [x] priority-ordering test + nil-`previousSet` fail-closed tests —
    `explicitSetBeatsRelative` (a fully-explicit set wins),
    `failsClosedWithoutPreviousSet` (now incl. "one more" — no previous set
    ⇒ no set), `plateStepNeedsALoad` (a loadless previous set is not a load
   form), and `implausibleDeltaIsFlagged` (a delta past `maxPlausibleLoad` is
   flagged `.implausibleValue`, not logged).
- [x] update parent roadmap + memory — done 2026-09-14 (parent roadmap
    "Cluster 7 → Grammar long-tail" note + this Status). The 7d scope is pinned
   and the deferred forms recorded above for a later pass.
