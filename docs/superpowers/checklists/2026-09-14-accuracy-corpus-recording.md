# trackit accuracy-corpus recording protocol

Runs the **[DATA]** half of cluster 6 — turn the hand-authored launch-gate
corpus (`Tests/WorkoutLoggerCoreTests/Fixtures/corpus/`, 21 rows as of 6.2)
into a corpus of *real on-device recogniser* n-best over real gym-noise
recordings, so `corpusClearsLaunchGateFloor` stops measuring a human's idea of
what Apple mangles and starts measuring what it actually mangles.

This is the "Slower / metric tests" slice of `specs/v1-voice-logging.md`. The
[IN-REPO] prep (6.1 widen, 6.2 disk fixtures + `loadCorpus`) is done; this file
is 6.3 — the reproducible protocol for the [DATA] step and its promotion.

**Parent:** `2026-09-11-cluster-6-accuracy-gate.md`. Read its `[DEVICE/DATA]`
and "Promoting to a hard CI gate" sections — this checklist is how those run.

---

## 0. Pre-flight (decide the open questions first)

The cluster-6 spec's OPEN QUESTIONS gate this work. Resolve before recording so
the captured fixtures match a harness that already exists:

- [ ] **Q1 — how n-best is captured on device.** Least effort and reusable for
   cluster 5c's latency capture: add a `#if DEBUG` hook in
    `App/System/SystemSpeechRecognizer.swift` that, on a final result, writes the
   utterance's hypotheses to a fixture file (in addition to returning them via
    `endUtterance()`). The recogniser already emits the n-best as
    `result.transcriptions.map(\.formattedString)` (SystemSpeechRecognizer.swift:90);
   the hook just persists it. Decide the on-disk filename + field order now so
   the capture and the test target's `loadCorpus` agree.
    *Alt:* a one-screen capture app target, or manual transcription from
    `SFSpeechRecognitionResult` logging (more effort, less reusable).
- [ ] **Q3 — corpus-size target.** "Enough" is unquantified in the master spec.
    **Proposed:** >= 6 utterances x every noise condition (sec 3), across self +
    3 volunteers, each condition repeated so each phrasing has >= 3 recordings --
    ~100+ clips per pass. Record the chosen target here before starting.
- [ ] **Q4 — where audio lives.** The harness only needs the derived n-best JSON
    (that's what `loadCorpus` reads). **Proposed:** keep raw audio out of the
    repo (LFS/drive or throwaway); commit only `Fixtures/corpus/*.json`.
- [ ] **Q5 — volunteers + consent.** Even short gym-command clips are voice
    recordings; get explicit consent to store/keep them (or anonymise/transcribe
    only). Record who + consent here.
- [ ] **Q6 — shared harness with 5c.** If cluster 5c's latency gate also replays
    recorded audio through the real recogniser, the fixture format + `loadCorpus`
    should be common to both -- design the fixture once.
- [x] **Q2 — is `ParseResult` `Codable`?** Resolved by 6.2: it is **not**, and we
    keep Core frozen -- the test target decodes a JSON mirror by hand
    (`CorpusFixture.swift`). No Core change.

## 1. Build the capture build

- [ ] `xcodegen generate` -> `xcodebuild -scheme Trackit -destination
   'platform=iOS Simulator,name=iPhone 15'` builds; install a **Debug** build
   (the Q1 hook is `#if DEBUG`) on a physical iPhone.
- [ ] Fresh install -> onboarding priming -> "Continue" grants mic + speech
    (`SystemSpeechAuthorization`). The loop below needs no network -- flip
    **airplane mode ON** for the whole session (on-device only, by design).

## 2. Device, recogniser config, and why

- [ ] **Device + iOS version** (iOS 17+). Note model + OS at the top of this run.
- [ ] **`requiresOnDeviceRecognition = true`** -- already set at
    `SystemSpeechRecognizer.swift:66`. This is the whole point: the corpus must
    measure *on-device* mangling, not the cloud engine.
- [ ] **`taskHint = .dictation`** -- already set at
    `SystemSpeechRecognizer.swift:67`. Dictation bias is what produces the
    spoken-number runs ("two twenty five") and dropped-"for" artefacts the
    post-processor is built to recover; keep it.
- [ ] Audio session `.record / .measurement / .duckOthers` (line 69) -- leave as
    is; it is the real capture path.

## 3. Noise conditions and clip counts

Cover the gym's real acoustic mix. **Proposed ~6 utterances per condition**
(scale by the Q3 target). Keep each recording <= a few seconds (one utterance).

- [ ] **Quiet** -- empty room / controlled baseline.
- [ ] **Music** -- moderate background (a phone playing, not earbuds on the
    lifter).
- [ ] **Clanking plates** -- plates/rack movement near the lifter.
- [ ] **Second person talking** -- a conversation at ~1 m.
- [ ] **Fan / AC** -- steady mechanical hum.

For each condition, run every utterance in sec 4 (repeat the phrasings enough to
hit the Q3 per-phrasing minimum). Note the dominant noise in each fixture's
`note` field so a miss is diagnosable ("...@ clanking-plates, vol-2").

## 4. Speakers

- [ ] **Self** (the primary lifter) -- the canonical voice.
- [ ] **>= 3 volunteers** with varied accents / speaking rates / ages. Record the
    roster + consent (Q5) up top.
- [ ] Each speaker runs the full sec-4 script in at least the **quiet** and
    **clanking-plates** conditions (the two that bound real use); other
    conditions are self-covered at minimum.

## 5. Utterance script (derived from the 6.1 corpus)

Read these -- they are the 21 launch-gate phrasings, grouped by the axis each
exercises, so [DATA] and [IN-REPO] cover the same ground. **Speak each as a
natural, single breath** the way a lifter would mid-set. For the recovery rows,
read the *clean* form; the recogniser supplies the mishear.

**Set axes (load type x effort x role x grouping):**
- [ ] "two twenty five for five" -- external / working / straight, compound load
- [ ] "warmup one thirty five for ten" -- warmup role
- [ ] "dropset forty for twelve" -- dropset grouping
- [ ] "plus twenty five for eight" -- added load
- [ ] "assisted eight minus forty" -- assisted load
- [ ] "pull ups twelve" -- bodyweight reps, inline name
- [ ] "plank for sixty seconds" -- duration effort
- [ ] "farmer carry forty meters" -- distance effort
- [ ] "bench one eighty five for eight" -- inline name + set
- [ ] "two twenty five lb for five" -- explicit spoken `lb` overrides the kg default
- [ ] "drop set twenty for twelve" -- spaced "drop set" form

**Commands:**
- [ ] "start workout" / "end workout" / "undo" / "start rest" / "skip rest"
- [ ] "superset" / "end superset" / "help"

**Post-processor recovery (read the clean form; let the recogniser mangle):**
- [ ] "bench press two twenty five for five" -- n-best pick (expect a "bench
    breast"-style mishear in some recordings)
- [ ] "romanian deadlift three fifteen for three" -- name-span bias (expect a
    "romanian deadlif"-style truncation in some recordings)

**Still-open breadth (6.1 flagged these as not yet in the corpus -- add rows as
recordings justify, and route each out-of-scope miss to cluster 7d, *not* a
parser fix):**
- [ ] Homophones: "to"/"two", "for"/"four", "won"/"one", "weight"/"wait",
    "rep"/"rip" -- one phrasing that isolates each, so a mishear is visible.
- [ ] Multi-hypothesis: rows where hypothesis 1 is wrong and hypothesis 2 is
    right (n-best's actual use). Only 2 such rows exist today.
- [ ] Exercise-name manglings the post-processor must recover: "RDL" -> "our
    deal", "incline" -> "in line".

## 6. Capture procedure (per utterance)

- [ ] Press-and-hold the talk button, speak **one** utterance, release.
- [ ] Confirm no crash (the Swift-6 audio-callback isolation watch -- see the
    device smoke test); a transcript/hypothesis list comes back.
- [ ] The Q1 `#if DEBUG` hook writes `Fixtures/corpus/<slug>.json` with:
    - `note`: axis + condition + speaker (e.g. "external/working/straight @
      clanking-plates, vol-2").
    - `hypotheses`: the recogniser's n-best, best-first, **verbatim** (do not
      "clean" them -- the mangling is the data).
    - `expected`: the hand-verified `[ParseResult]` (what a correct log yields),
      in the 6.2 JSON shape (`kind` + `set`/`exercise`/`command`). Verify by eye
      against the grammar; the parser does *not* fill this in.
- [ ] Re-read the same utterance 2-3x (or use a fresh recording) to capture
    recogniser variance; keep the rows that show real-world behaviour.
- [ ] Drop each new file into `Fixtures/corpus/` (Q4: audio itself stays out of
    the repo).

## 7. Run, investigate, promote

- [ ] `cd Packages/WorkoutLoggerCore && swift test` -- `corpusClearsLaunchGateFloor`
    reports the no-correction rate over the real corpus and lists every miss by
    `note`.
- [ ] For **every** miss, classify: (a) recogniser error the post-processor
    *should* recover -> fix the post-processor; (b) in-scope phrasing the parser
    misses -> fix the parser; (c) genuinely out-of-scope for v1 -> exclude the
    row and note it for cluster 7d. Keep in-scope `rate` at 1.0; the floor is
    >= 0.85.
- [ ] Repeat sec 1-6 across **independent recording sessions** until `rate` is
    stably >= 0.85 (not a one-shot lucky pass).
- [ ] **Promote to a hard CI gate:** (a) the assertion now runs against the real
    fixtures; (b) CI treats a failure as release-blocking, not informational;
    (c) a short `docs/` note records the current `rate` + the date measured, so a
    later drop reads as a regression.
- [ ] Add a second assertion on a **held-out** slice (rows not used while tuning
    the post-processor) so the gate measures generalisation, not overfit.
- [ ] Update the parent roadmap's Cluster 6 status + memory when done.
