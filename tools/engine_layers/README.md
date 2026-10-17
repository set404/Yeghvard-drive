# Engine layers

Steady-rev engine loops for car.gd's `engine_layers`, cut from recordings in
`data/sounds/` and written to `data/sounds/layers/` (tools/build_sounds.gd turns
those into `audio/layers/*.res`). Needs Node.js.

1. Decode each recording to 48 kHz mono 32-bit float (`<name>.f32`, raw samples),
   for example by playing it in Godot with `--write-movie out.png` and taking the
   samples from the `.wav` it writes beside the frames.
2. Where the revs change, `ridge.js` follows one harmonic line of the engine through
   the recording (`node ridge.js in.f32 out.json startTime startHz [from to]`); the
   revs are that line's frequency times a scale worked out from a known point (the idle).
   `ridge_audi.json` (x10) and `ridge_etype.json` (x20) are kept here.
3. `spec.json` says, for each loop, which recording, where in it, how its revs are
   known (a constant `rpm`, a `line` [t0, rpm0, t1, rpm1] or a `ridge` and `scale`),
   and the revs `at` to make it; run from the folder with the `.f32` files:
   `node layers.js spec.json ../../data/sounds/layers` (fix the ridge paths if you
   run it elsewhere).

Each loop is 6 s (`seconds` in the spec), built from 80 ms grains taken where the
recording is within 5% of the wanted revs, each resampled to exactly those revs and
lined up with what came before it, wrapping round so the loop has no seam. The grains
wander through that stretch at random rather than in order, so the loop has no
shorter pattern in it: a short loop played over and over is heard as a repeating
sound. car.gd keeps every loop playing (from different points) while the engine runs.

## Higher revs from one recording

`pulses.js` makes loops at other revs from one steady loop the way an engine revs: it
cuts the loop into its firing pulses and lays them closer together (keeping the gaps
between them as recorded, so a lumpy engine stays lumpy), with only part of the change
made by playing faster. Plain speeding-up raises the exhaust's ring too, which sounds
like a chipmunk. `pulses.json` lists the jobs (source loop, its revs, cylinders, the
share made by playing faster, and the revs to make); the pulses keep their recorded
order, a little louder or softer each, over a 6 s loop, and about three times a second
(`JUMP`) the sequence moves elsewhere: to the pulse, from the same cylinder, most like
the one due next. Jumping more often, or to any pulse, or moving the pulses' timing,
smears the overlapping pulses into a hollow, spacey sound; run from this folder:
`node pulses.js pulses.json ../../data/sounds/layers`. It is used above the top of
each recorded set: the Mercedes (both share the E55's set above idle, recorded from a
Barracuda V8's idle and blip up to 1350 rpm), Compass, Volga and Land Cruiser. Make
higher revs from a loop recorded under some throttle, not from an idle: an idle is all
low rumble, and squeezed up to high revs it sounds like wind rather than an engine.

## Tone

`eq.js` tilts finished loops' tone in place (a bass shelf and a treble shelf, in dB),
keeping their loudness: `node eq.js bassDb bassHz trebleDb trebleHz files...`. The
Mercedes loops above idle had `node eq.js 5 180 -2 3000` run twice for a deep
note under throttle; do the same after rebuilding them.
