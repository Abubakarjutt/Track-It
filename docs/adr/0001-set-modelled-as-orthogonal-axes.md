# Set is modelled as four orthogonal axes, not a flat type enum

A **Set** is described by four independent axes — **load type** (external /
bodyweight / added / assisted), **effort measure** (reps / duration / distance),
**role** (working / warmup), and **grouping** (straight / superset / dropset) —
rather than by a single `type` enum. We chose this because the axes genuinely
compose: a set can be a warmup *and* bodyweight *and* timed at the same time, and
a flat enum would need a combinatorial explosion of cases (`warmupBodyweightTimed`)
or would silently lose information. The four-axis model keeps the parser grammar,
the progress calculations, and the schema each dealing with one concern.

## Considered Options

- **Flat `type` enum** (`straight`, `warmup`, `bodyweight`, `assisted`, `timed`,
  `distance`) — the shape used by Strong, Hevy, and most logging apps. Rejected:
  the values are not mutually exclusive, so the enum can't represent "warmup
  bodyweight hold" without either extra flags bolted on (which is the four-axis
  model in disguise) or lost detail.
- **Four orthogonal axes** — chosen.

## Consequences

- A future engineer will see four axis fields on `Set` and may assume it's
  over-engineered relative to comparable apps. It is deliberate; do not collapse
  it back to a single enum.
- Progress math filters on `role == working` and branches on `effort measure`;
  it never switches on a single combined type.
- The parser produces the axes independently, which is what lets one grammar
  handle all five set-type user stories without a special case per combination.
