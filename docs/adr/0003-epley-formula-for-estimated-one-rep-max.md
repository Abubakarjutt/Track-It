# Estimated 1RM uses the Epley formula

Personal-record detection compares sets by their **estimated one-rep max**, and
that estimate is computed with **Epley**: `1RM ≈ load × (1 + reps / 30)`, written
in code as `load × (30 + reps) / 30` so that round rep counts produce exact
`Double` values (`100 × 33 / 30 == 110.0`, not `110.000…1`). A single rep is
returned unchanged. Warmup and timed / distance sets are excluded by the caller,
not the formula.

We picked one formula and recorded it because the choice is hard to reverse: the
running best (`bestOneRepMax`) and the stored `PersonalRecord` values are all in
this scale, and changing the formula later re-scales every historical comparison
and can silently make an old PR look beaten or unbeaten.

## Considered Options

- **Epley** — chosen. One multiply and one add; the most widely tabulated
  formula, so a lifter's mental "225 for 5 ≈ 253" matches what the app shows.
- **Brzycki** (`load × 36 / (37 − reps)`) — very close to Epley up to ~10 reps,
  then diverges (and blows up as reps approach 37). No practical advantage here.
- **Lombardi** (`load × reps^0.10`) — needs `pow`, and is less familiar to the
  target user. Rejected for no upside.
- **Averaging several formulas** — more code and a number that matches no
  published table. Rejected.

## Consequences

- `estimatedOneRepMax(loadKilograms:reps:)` is the one place the formula lives;
  volume and any future strength-trend math should call it rather than re-derive.
- The estimate runs on **stored kilogram** loads (see ADR-0002), never on the
  parser's as-spoken `ParsedSet`.
- If a later release exposes a user-visible 1RM or lets the user pick a formula,
  that is a new decision — supersede this ADR rather than quietly swapping the
  expression.
