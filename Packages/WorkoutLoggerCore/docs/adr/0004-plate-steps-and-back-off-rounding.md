# Plate steps and back-off round to a physical plate

The relative / contextual grammar (cluster 7d, "the grammar long-tail") lets a
lifter adjust the **previous** set's load instead of re-stating it: "add a
plate", "drop a plate", "up 10", "down 10", "back-off", and a verbatim repeat
("again", "same", …). Two of these need a physical-plate convention the parser
had no opinion about, so we record it here rather than leave it implicit.

## Plate step = one standard plate per unit

"Add a plate" / "drop a plate" move the load by **one standard plate**,
interpreted per unit:

- kilograms → **20 kg** (a 20 kg plate)
- pounds → **45 lb** (a standard competition plate)

The move is made in the load's own unit (the previous set's `loadUnit`, falling
back to the context unit), so "add a plate" on a 100 kg set gives 120 kg and on a
100 lb set gives 145 lb. A drop is floored at zero — you cannot go negative.

We picked the plate's own weight (not "one plate each side", i.e. ×2) because the
utterance says "a plate", singular, and a lifter adding a plate adds the plate
weight to the total they speak in. The ×2 "per side" reading is a likely
follow-up; supersede this ADR rather than doubling the constant silently.

## Back-off = 90% of the previous load, rounded to the smallest plate

A "back-off" set is the previous load at **90%**, rounded to the nearest
**smallest fractional plate each side owns**: 2.5 kg / 2.5 lb. 110 × 0.9 = 99 →
nearest 2.5 kg → 100. Rounding to a plate (not to a round number or a whole
integer) means the computed load is one the lifter can actually load, which is the
whole point of a back-off.

## Considered Options

- **Fixed 5 kg / 10 lb step** — too coarse for a back-off, which is about a
  *small* reduction; rejected.
- **Round to the nearest integer** — not physical; you can't load 99 kg; rejected.
- **Round to the largest standard plate (20 kg / 45 lb)** — too coarse for a
  back-off; rejected.
- **One plate per unit for steps, smallest plate for back-off rounding** — chosen.
  The two constants answer two different questions ("how much is a plate?" vs.
  "what granularity can I load?") and conflating them would make either one wrong.

## Consequences

- `plateSize(for:)` (20 / 45) and `backOffRoundIncrement(for:)` (2.5 / 2.5) are
  the single source of truth for these numbers; a future user-facing "plate size"
  setting should override them rather than re-hardcoding.
- A relative delta that would exceed the plausible-load ceiling (see `isPlausible`
  in `Parser.swift`) is flagged `.implausibleValue` and **not** logged — the same
  fail-closed behaviour an explicit oversized set gets — with the active exercise
  offered as the best guess for tap-select.
- A relative form with no previous set, or a plate/numeric step against a loadless
  (timed or distance) previous set, produces **no set** and the utterance falls
  through to the name forms; a verbatim repeat ("again") works even for a loadless
  previous set.
