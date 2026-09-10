# Cluster 6 — Launch-gate accuracy metric (real-recogniser corpus + CI gate)

**Prerequisite reading:** `2026-09-11-v1.1-remaining-onboarding.md`.
**Parent roadmap:** `2026-09-06-v1.1-deferred-work-design.md` § "Cluster 6".

The master spec's accuracy launch gate: **≥ 85 % of sets logged with no
correction**. Cluster 6 is now only the accuracy half of the gate (latency moved
to cluster 5c). The package harness exists and passes on hand-authored data; what
is missing is real recogniser output over real gym-noise recordings, and the
promotion of the assertion from a *tracked metric* to a *hard CI gate*.

Split as usual into **[IN-REPO]** (now) and **[DEVICE/DATA]** (needs 5a's
recogniser on a phone + volunteers).

---

## What already exists

`Packages/WorkoutLoggerCore/Sources/WorkoutLoggerCore/CorpusScore.swift`:

```swift
public struct CorpusEntry {
    public let hypotheses: [String]     // an n-best list, as the recogniser would emit
    public let expected: [ParseResult]  // what postProcess→parse must produce
    public let note: String             // human label for the row
}

public struct CorpusScore {
    public let total: Int
    public let matched: Int
    public let failures: [String]       // notes of the rows that missed
    public var rate: Double             // matched / total; an empty corpus scores 1.0
}

/// Runs each entry's hypotheses through `postProcess(_:library:)` then
/// `parse(_:context:library:)` with a fresh `WorkoutContext()`, and counts an
/// exact `==` match against `expected`.
public func score(_ entries: [CorpusEntry], library: ExerciseLibrary) -> CorpusScore
```

`Tests/WorkoutLoggerCoreTests/CorpusScoreTests.swift`:

- `launchGateCorpus` — **14 hand-authored rows**: one per set-axis combination,
  one per command, plus 2 post-processor recovery rows. Fixtures used:
  `pullUp`, `plank`, `carry` (Farmer's Carry), `bench`, `rdl`.
- `corpusClearsLaunchGateFloor` — asserts `score(launchGateCorpus, library:).rate >= 0.85`.
  **Currently 1.0** (all 14 pass).

This is a *tracked metric*: the test exists and is green, but it runs on
synthetic n-best lists a human wrote to look like recogniser output. It does not
yet prove the real recogniser clears 85 %.

---

## [IN-REPO] prep — do these now, before any recordings exist

### 6.1 Widen the hand-authored corpus

14 rows is one example per axis combo. Expand `launchGateCorpus` toward the
breadth a real corpus will need, still hand-authored, still exact-match:

- Every `load type` × `effort measure` × `role` × `grouping` combination that is
  actually reachable by voice (see `CONTEXT.md` for the axis vocabulary and
  ADR-0001 for which combinations are legal).
- Each command form (`start workout`, `next exercise`, `rest`, `undo`, …) with
  at least one natural phrasing variant.
- Homophone / mishearing rows: `"to"`/`"two"`, `"for"`/`"four"`, `"won"`/`"one"`,
  `"weight"`/`"wait"`, `"rep"`/`"rip"`, exercise-name manglings the post-processor
  is meant to recover (`"RDL"` heard as `"our deal"`, `"incline"` as `"in line"`).
- Multi-hypothesis rows where hypothesis 1 is wrong and hypothesis 2 is right —
  this is what n-best is *for*, and the current corpus only has 2 such rows.

Each new row is a red→green slice: add the row, watch `rate` drop below 1.0 (or
a targeted assertion fail), fix the parser/post-processor **only if the spec says
that phrasing is in scope for v1** — otherwise the row belongs in cluster 7d
(grammar long-tail), not here. Keep `rate` at 1.0 for the rows that are in scope.

### 6.2 Restructure the harness to load fixtures from disk

Today `launchGateCorpus` is a Swift literal. A real corpus is dozens-to-hundreds
of rows, each tied to an audio clip. Prepare for that now:

- Define an on-disk fixture format — suggest one JSON file per clip:
  `{ "note": "...", "hypotheses": ["...", "..."], "expected": [ <ParseResult JSON> ] }`.
  Whether `ParseResult` is `Codable` is an **open question** (see below); if not,
  add a small test-only decoder in the test target rather than making Core types
  `Codable` for a test's sake (Core is frozen — see onboarding).
- Add `func loadCorpus(from directory: URL) -> [CorpusEntry]` in the **test
  target** (not Core) that reads every `*.json` under a fixtures dir.
- Put the 14 (soon more) hand-authored rows in
  `Tests/WorkoutLoggerCoreTests/Fixtures/corpus/` as individual files, and have
  `corpusClearsLaunchGateFloor` load them via `loadCorpus`. Same assertion,
  same result — this is a pure refactor, do it as its own reviewed commit.
- The real recordings' transcripts drop into the same directory later with zero
  harness change.

### 6.3 Document the recording protocol

Write `docs/superpowers/checklists/<date>-accuracy-corpus-recording.md`
(new file) capturing exactly how the [DATA] step must be run so results are
reproducible:

- Device, iOS version, `requiresOnDeviceRecognition = true`, `.dictation` hint.
- Noise conditions to cover (quiet, music, clanking plates, a second person
  talking, a fan/AC) and roughly how many clips per condition.
- Speakers: self + N volunteers, varied accents.
- Utterance script: the full set of phrasings to read, derived from the widened
  6.1 corpus so [DATA] and [IN-REPO] cover the same ground.
- How each clip's recogniser n-best is captured to a fixture file (a debug
  build affordance in `SystemSpeechRecognizer`, or a tiny standalone capture
  harness — see OPEN QUESTIONS).

---

## [DEVICE/DATA] — blocked on cluster 5a's recogniser front-end

1. Record the clips per the 6.3 protocol.
2. Run each through the real on-device recogniser; capture the n-best list.
3. Write one fixture file per clip into `Tests/WorkoutLoggerCoreTests/Fixtures/corpus/`,
   with the hand-verified `expected` `ParseResult`(s).
4. Run `corpusClearsLaunchGateFloor`. Investigate every miss: is it a recogniser
   error the post-processor *should* recover (fix the post-processor), an
   in-scope phrasing the parser misses (fix the parser), or genuinely
   out-of-scope for v1 (exclude the row, note it for cluster 7d)?
5. When `rate` is **stably ≥ 0.85 across independent recording sessions**,
   promote the assertion.

---

## Promoting to a hard CI gate

Once real numbers are stable:

- Change `corpusClearsLaunchGateFloor` from a plain `#expect(rate >= 0.85)` that
  is "tracked" to a build-blocking gate: it already fails the suite if it
  regresses, so "promotion" mostly means (a) it now runs against the real
  fixtures, (b) CI treats a failure as release-blocking not informational, and
  (c) a short `docs/` note records the current rate and the date it was measured
  so a later drop is visibly a regression.
- Add a second assertion on a **held-out** slice of the corpus (rows not used
  while tuning the post-processor) so the gate measures generalisation, not
  overfit.

---

## OPEN QUESTIONS

1. **How are recogniser n-best lists captured on device?** Options: a
   `#if DEBUG` hook in `SystemSpeechRecognizer` that writes each utterance's
   hypotheses to a file; a separate one-screen capture app target; or manual
   transcription from `SFSpeechRecognitionResult` logging. The first is least
   effort and reusable for cluster 5c's latency capture.
2. **Is `ParseResult` `Codable`?** Confirm. If not: test-only decoder vs. a
   sanctioned Core change (the latter needs an explicit budget decision — Core
   is frozen).
3. **Corpus size target.** How many clips per noise condition / speaker is
   "enough" for the gate to be meaningful? (Master spec doesn't quantify.)
4. **Where do the audio files themselves live?** They may be large. Options:
   commit small compressed clips under `Tests/.../Fixtures/audio/`; keep only
   the derived n-best JSON in-repo and store audio in a separate LFS repo /
   drive; keep audio entirely out of the repo and treat the JSON fixtures as
   the artifact of record. The harness only needs the JSON.
5. **Who are the volunteers and is there consent** for storing/keeping their
   voice recordings? (Even short gym-command clips.)
6. **Does the gate share a harness with cluster 5c** (CI audio replay)? If the
   5c latency gate also replays recorded audio through the real recogniser,
   the fixture format and loader should be common.

---

## Effort

6.1 + 6.2 + 6.3 (all [IN-REPO]): ~1 day, worth a short `writing-plans` pass
because 6.2 is a real refactor with review. The [DATA] step is bounded by
recording logistics, not code. Promotion is small once numbers are stable.

## Status

- [ ] 6.1 widen hand-authored corpus (in-scope rows only, `rate` stays 1.0)
- [ ] 6.2 disk-fixture format + `loadCorpus` in test target + move existing rows
- [ ] 6.3 recording-protocol checklist
- [ ] [DATA] record clips, capture n-best, write fixtures
- [ ] investigate misses; tune post-processor / parser for in-scope failures
- [ ] promote to release-blocking CI gate + held-out slice + dated rate note
- [ ] update parent roadmap Cluster 6 status + memory
