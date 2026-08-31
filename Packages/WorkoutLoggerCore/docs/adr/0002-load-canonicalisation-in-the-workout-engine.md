# Load canonicalisation happens in the workout engine, not the parser

The parser emits a set's load exactly as spoken, tagged with its unit (the user's
default, or an explicit spoken one like "100 kilos"). Conversion to the canonical
storage unit — kilograms — happens in the **workout engine** as it applies parser
results. We chose this so the parser stays a pure text-to-structure function with
no arithmetic and no opinion about storage, and so parser test cases assert on
literal spoken values ("225", `.pounds`) rather than conversion results
(`102.058...`), which keeps the case suite readable and non-tautological.

An earlier draft of the spec said units are "normalised on parse", which is
superseded by this: the parser normalises *which unit applies* (explicit spoken
unit beats the default); it does not normalise the *value*.

## Consequences

- `ParsedSet.load` + `ParsedSet.loadUnit` are "as heard". Anything downstream that
  compares or sums loads must canonicalise first — only the workout engine's
  stored `Set` is guaranteed to be in kilograms.
- Volume, estimated 1RM, and personal-record maths run on stored (kilogram) sets,
  never on `ParsedSet`.
