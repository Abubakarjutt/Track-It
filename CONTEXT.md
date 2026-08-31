# Voice Workout Logger

A voice-first iPhone app for logging resistance-training workouts. Lifters speak
each set as they perform it; the app records, confirms, and charts progress. This
is the project's single context.

## Language

### Workout structure

**Workout**:
A single training occasion and its record — the exercises, entries, and sets
performed on one date. May be planned, in progress, or completed.
_Avoid_: session, training session, log entry

**Active workout**:
A workout that has been started and not yet ended.
_Avoid_: current session, live workout, open session

**Completed workout**:
A workout that has been ended; its totals are final.
_Avoid_: past session, finished session

**Entry**:
One exercise's slot within a single workout or template, holding an ordered list
of sets. "My bench press today" is an Entry; the movement it points to is an
Exercise.
_Avoid_: block, section, exercise (when the in-workout grouping is meant)

**Template**:
A reusable, dateless workout shape — an ordered list of entries with target set
counts and an optional rest target, but no loads. Starting a template creates a
new workout.
_Avoid_: routine, plan, workout template, preset

**Program**:
A multi-week sequence of planned workouts with prescribed progression. Not built
in v1.
_Avoid_: cycle, mesocycle, plan

**Rest target**:
The intended rest duration after a set, taken from the active template or a
global default.
_Avoid_: rest time, break, interval

### Exercises

**Exercise**:
A movement in the app's library, e.g. "Barbell Bench Press" — the catalog entry,
independent of any workout.
_Avoid_: lift, movement (as the canonical noun)

**Custom exercise**:
An Exercise created by the user rather than drawn from the curated library,
optionally carrying its own aliases.
_Avoid_: user exercise, my exercise

**Alias**:
An alternative spoken name that resolves to a canonical Exercise, e.g. "OHP" →
Overhead Press.
_Avoid_: synonym, nickname

### Sets and their axes

**Set**:
A single bout of work at a given load, recorded as a rep count, a duration, or a
distance. Described by four independent axes: load type, effort measure, role,
and grouping.
_Avoid_: rep set

**Load type** _(axis)_:
How resistance is provided — one of: `external` (weight on a bar or dumbbell),
`bodyweight`, `added` (bodyweight plus extra load), `assisted` (bodyweight minus
machine or band assistance).

**Effort measure** _(axis)_:
What a set counts — one of: `reps`, `duration`, `distance`.

**Role** _(axis)_:
Whether a set counts toward progress — `working` (counts) or `warmup` (excluded
from volume, personal records, and estimated 1RM).

**Grouping** _(axis)_:
How a set relates to adjacent sets — `straight` (ungrouped, the default),
`superset`, or `dropset`.

**Working set**:
A set with the working role.
_Avoid_: hard set, real set

**Warmup set**:
A set with the warmup role; excluded from all progress metrics.
_Avoid_: prep set

**Straight set**:
A set that is not part of a superset or dropset. The default grouping.
_Avoid_: normal set, standard set

**Superset**:
A grouping in which two or more exercises are alternated set-for-set with minimal
rest.
_Avoid_: giant set, circuit, compound set

**Dropset**:
A grouping in which one exercise is taken across consecutive sets at descending
load with no rest between.
_Avoid_: drop set (two words), strip set

**Rep**:
One repetition of an exercise. A positive whole number in this app; partial reps,
AMRAP counts, and RIR/RPE are not modelled.
_Avoid_: repetition

**Load**:
The number attached to a set, in the user's chosen unit — the weight on the
implement for external sets, the added weight for added sets, or the assistance
amount for assisted sets. Zero for plain bodyweight sets. "Weight" is acceptable
in user-facing copy for external sets only.
_Avoid_: resistance, weight (as the canonical field name)

### Progress

**Volume**:
Total tonnage for an exercise or workout — the sum of load × reps across working
sets.
_Avoid_: tonnage, total weight, workload

**Set volume**:
A count of working sets, optionally per muscle group, used to gauge training
stimulus. Distinct from Volume; not surfaced in v1.
_Avoid_: hard sets, weekly sets

**One-rep max** _(1RM)_:
The heaviest load a lifter can lift for a single rep of an exercise. Rarely
tested directly in this app.
_Avoid_: max

**Estimated 1RM**:
The 1RM predicted from a working set's load and reps.
_Avoid_: e1RM (in prose), projected max, one-rep max

**Personal record** _(PR)_:
A new best estimated 1RM for an exercise, from any working set. One value per
exercise.
_Avoid_: personal best, PB, lifetime max

### Voice interaction

**Utterance**:
One push-to-talk recording — everything the user says between pressing and
releasing the button.
_Avoid_: recording, voice input, phrase

**Transcript**:
The text produced from an utterance by on-device speech recognition after domain
post-processing.
_Avoid_: transcription, recognition result, STT output

**Announcement**:
An utterance that names the exercise to log against rather than recording a set,
e.g. "now squats".
_Avoid_: exercise call, switch command

**Command**:
An utterance that instructs the app rather than logging a set, e.g. "undo",
"start rest", "help", "end workout". A fixed, small vocabulary.
_Avoid_: voice command, instruction

**Readback**:
The app speaking a just-logged set back for confirmation — terse, full, or an
earcon depending on confidence.
_Avoid_: confirmation, playback, echo

**Earcon**:
A short non-speech sound standing in for a spoken readback.
_Avoid_: chime, tone, beep

**Phrasebook**:
The in-app reference listing every phrase and command the app understands.
_Avoid_: cheat sheet, help screen, grammar reference
