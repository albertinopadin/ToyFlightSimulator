# Procedural Terrain Generation — Implementation Plan

**Started:** 2026-11-22 · **Agent:** claude
**Design source:** `research/claude/planet_scale_terrain_research_2026-11-12.md`. The decisions used
here are in 1.2.8 ("Fully procedural": fBm, value noise, the limit of noise), 1.2.9 (rules 1, 2, 5
and 6: one source of truth, interpolation, sample format), 2.1 (what the current terrain is) and
2.2 ("Is procedural generation a good fit?" and steps 1 to 3 of the simple version).
**Status:** in progress (Milestones 1, 2, 3 and 4 landed)
**Related plans:** `plans/claude/tessellation_terrain_fix.md` (out of date; its struct listings no
longer match the source). No other plan covers terrain.

## How this document works

- The owner writes the code from the pseudocode. The agent implements a milestone only when asked.
- Milestones are edited in place to match the code. History goes in the Changelog, newest first,
  one line per entry.
- A milestone header gets `✅ (landed YYYY-MM-DD, <commit>)` when it lands. Checkboxes (`- [ ]`)
  track the items inside it.
- Review findings that change the plan are folded in; the changelog line names the review and
  says which numbers were re-checked with a scratch script.

## Changelog

- **2026-11-26** — Milestone 4, a range check for the focus, after a question from the owner
  (is the finite focus that still stopped the program worth fixing?). The answer was "only as
  one line": `recenteredCenterSampleIndex` now answers nothing for every focus that is not a
  usable position, which is NaN, infinite, or more than 2^53 samples from sample 0. The owner
  replaced the `isFinite` guard with one comparison, and the limit became the static constant
  `ProceduralTerrain.maxFocusDistanceFromOriginInSamples` (`0x1p53`). Edited to match: one row
  in the data table, "Names in the code", the pseudocode, two tests added
  (`maxFocusDistanceIsTheLastExactWholeNumber`, `focusBeyondTheMaxDistanceDoesNotRecentre`),
  one edge case rewritten and one added (a snap step of 0). Numbers from scratch builds of the
  real `ProceduralTerrain.swift`: 2^53 is 9,007,199,254,740,992 samples, which is
  9.007 × 10^17 m with 100 m spacing, or 95.2 light-years; the gap between neighbouring
  Doubles is 1 just below 2^53 and 2 at it; NaN, both infinities, 10^21 m, 10^300 m, the
  largest Float and −10^30 m give nothing; a focus exactly at the limit gives centre 2^53 and
  the next Double after it gives nothing; 400 m, 400.5 m, a tie and 123,456 m give the same
  answers as before; a snap step of 0 stops the program (exit status 133). The real
  `ProceduralTerrainTests.swift` was run in the scratch SwiftPM package against six broken
  copies of the guard. Three ended the test process (only NaN and infinity checked, the guard
  removed, `abs` left out); `<` for `<=` failed `focusBeyondTheMaxDistanceDoesNotRecentre`;
  a constant of 2^52 and one of 2^54 each failed that test and
  `maxFocusDistanceIsTheLastExactWholeNumber`. Checks run, each in a build folder of its own:
  the macOS build and test bundle (the log lists `ProceduralTerrain.swift` and
  `ProceduralTerrainTests.swift` under the test target; no new warning); the two terrain
  suites (52 tests); the full suite one test at a time (612 Swift Testing tests in 80 suites
  and the 20 XCTest tests); the iOS simulator build. Not run: the flight of the completion
  criteria. tvOS was not built.
- **2026-11-26** — Milestone 4, after the review notes of 2026-11-25: the owner applied four of
  the five, and the plan was edited to match. `snapStepInSamples` is an `Int`;
  `storedPositionOfTerrainCenter` takes the two centre indices as `Int`; the log line has its
  closing parenthesis; `recenteredCenterSampleIndex` answers nothing for a focus that is NaN or
  infinite (a `guard`, now in the pseudocode too). The debug flag stays `true`. With the code:
  the doc comments that described the old types were rewritten, and one test was added,
  `focusThatIsNotFiniteDoesNotRecentre`. In the plan: "Names in the code", one edge case
  rewritten and one added. CLAUDE.md gained a floating-origin rule: a value kept in the
  original frame, such as the terrain's centre sample index, is not shifted. Numbers from a
  scratch build of the real `ProceduralTerrain.swift`: a focus of NaN, +infinity or −infinity
  gives nothing; a focus of 9 × 10^20 m still gives a centre (sample index 9 × 10^18) and
  10^21 m stops the program (exit status 133); a focus at 400 m, at 400.5 m and on a tie, and
  the small example, give the same answers as before. With the `guard` taken out, the new test ends the test process
  ("cannot be converted to Int because it is either infinite or NaN"). Checks run, each in a
  build folder of its own (`-derivedDataPath`): the macOS build and test bundle (no new
  warning); the two terrain suites (50 tests); the full suite one test at a time (610 Swift
  Testing tests in 80 suites and the 20 XCTest tests); the iOS simulator build. A first run in
  the shared DerivedData folder was discarded: `build-for-testing` there linked the test
  bundle without compiling the test target's Swift files, so the old 49 and 609 tests ran and
  the log line still lacked its parenthesis. The cause was not found; Xcode was open on the
  project. Not run again: the broken copies of 2026-11-25 (the tests they ran against are
  unchanged) and the flight of the completion criteria. tvOS was not built.
- **2026-11-25** — Milestone 4 landed (6bcc16c) and was edited to match the code: the names and
  types the code uses are listed (the snap step, the threshold and the centre indices are
  passed as `Double`; the rounding is `.rounded(.toNearestOrEven)`; `follow` uses a `switch`
  over the height source; the scene reads the offset once and calls its terrain `ground`); the
  six listed tests are ticked with what each now checks; nine tests were added (4 Metal-free,
  5 app-hosted tests of `follow`); three edge cases were added; the debug flag is `true` in the
  commit. The review before landing found no defect in the code as committed. One defect was
  found and fixed by the owner earlier the same day, while the code was being written: the
  first draft rounded with `round()`, which sends a tie away from zero (centre 4, focus
  1000 m gave 12, not 8). The review added the doc comments and the tests and changed no line
  of code: with comments and blank lines removed, the five source files are identical to the
  owner's. Readability notes went to the owner and were not applied: the debug flag is on, the
  log line lacks a closing parenthesis, and whole numbers of samples are passed as `Double`.
  A second commit (2f6a686) raises `Aircraft._moveSpeed` from 25 to 50; it is not part of this
  plan. Numbers from scratch scripts: every expected value of the new tests came from a Python
  script written from the pseudocode, `m4_crosscheck.py` (Python's `round` sends a tie to the
  even number): the single cases; the flight out and back (7 recentres, ending on centre 4);
  63,744 recentres in the sweep, the focus at most 2.0 samples from the new centre and no
  second recentre; (−812, −432, 440); 10.75 against 8 when narrowed first; the shift example;
  and the centres the `follow` tests expect. The statements of the new doc comments were run
  against the real `ProceduralTerrain.swift`: with a threshold of 1 the rule answers the
  centre it was given; a hundred crossings of a line cause 100 recentres with a threshold of 2
  and one with a threshold of 4; a step of 2.5 gives 8 where the multiple is 10; a NaN or an
  infinite focus stops the program (exit status 133); the float gap at 123,456,800 is 8. The
  real `ProceduralTerrainTests.swift` was run in a scratch SwiftPM package against 13
  deliberately broken copies of the two new functions (a tie away from zero, floor, cut off
  toward zero, `<` for `<=`, the distance measured from sample 0, the spacing ignored in
  either function, the step not multiplied back, one patch at a time, the offset added, X and
  Z swapped, y left at 0, narrowed before the subtraction). Each failed at least one test; the
  tie away from zero failed only `recentreSnapsToTheNearestPatch`. `TerrainHeightTextureTests`
  was run in the test host against 10 deliberately broken copies of `follow`, each made from
  the committed file and undone afterwards (the bake's X start taken from the Z centre, the
  new texture not stored, the old texture overwritten in place, the offset ignored, Z asked
  with the focus's x, a recentre only when both axes are past the threshold, the grid one
  sample late, the node not moved, the new Z centre not stored, the new samples not stored).
  Each failed at least one test; overwriting the old texture in place failed only
  `followRecentresAndBakesANewTexture`. The unbroken code was then built and run again.
  Checks run: the macOS build and test bundle (no new warning); the two terrain suites (49
  tests); the full suite one test at a time (609 Swift Testing tests in 80 suites and the 20
  XCTest tests); the iOS simulator build. The twelve bakes of three runs of the unbroken tests
  took 17.4 to 19.4 ms each (Debug build, Apple M1 Max; the scratch figure under "Simple
  version, then optimized version" is 15.7 ms). Not run: the flight of the completion criteria, because key presses
  cannot be sent to the app from the command line. The scene's call in `doUpdate` and the
  picture on screen were therefore read, not executed. tvOS was not built.
- **2026-11-25** — Milestone 4, after two requests from the owner: the `follow` pseudocode used
  `samplesPerSide` and `parameters` without defining them. `samplesPerSide` was a local variable
  of `makeProceduralTerrain` in Milestone 3 and is not a property of `TerrainObject`; the line
  `samplesPerSide = TerrainObject.proceduralSamplesPerSide` was added above `halfSideInSamples`.
  `parameters` is the `ProceduralTerrainParameters` value that the `procedural` case of
  `heightSource` carries; a line after the source check now reads it out. No number changed:
  129 and 64 were already in the plan. Nothing was compiled or run for this entry.
- **2026-11-25** — Milestone 3 landed (a889b83) and was edited to match the code: the names the
  code uses are listed (`sampleSpacing` is a `Double?`, nil for the image source;
  `makeProceduralTerrain` is a static function; the scene's terrain property is `ground`);
  `makeHeightTexture` checks the array's length with a `precondition`; the listed test is
  ticked and four tests were added (5 in `TerrainHeightTextureTests`); two rows were added to
  Pitfalls. One correction to part A: the image source's two thresholds are the old shader's
  literals, −0.5 and 0.3, not "× height" (the old shader compared them with the decoded height
  whatever `height` was). The review before landing found two defects, which the owner fixed
  before the commit. (1) The scene passed the side length as `12_8000`, which is 128,000 m:
  the sample spacing was 1,000 m and the narrowest octave's 400 m cells were 0.4 samples wide.
  (2) The image source had `heightScale: height, heightOffset: 0`, so its heights ran
  0 … height and nothing was below the grass threshold. Numbers from scratch scripts run for
  the review: with the real `ProceduralTerrain.swift`, a 129 × 129 bake centred on the origin
  has its lowest sample at −329.05 m, its highest at 533.93 m and its middle sample at
  −172.99 m with 100 m spacing; the gap between the height function and two flat triangles per
  cell, taken at the centres of a 10 × 10 sub-grid in each of the 128 × 128 cells, is at most
  9.1 m (1.3 m root-mean-square) with 100 m spacing and at most 247 m (41 m) with 1,000 m
  spacing, cells split along the 00–11 diagonal (8.7 m and 216 m along the other; the 9.2 m in
  Design decisions used its own sub-grid and was not re-run); on `mountain.png` the old decode
  gives 76.7 % grass, 19.2 % rock and 4.1 % snow, and the defect gave 0 %, 80.0 % and 20.0 %.
  Checks run: the macOS build and test bundle; the full suite one test at a time (594 Swift
  Testing tests in 80 suites and the 20 XCTest tests); the iOS simulator build;
  `readHeightBetweenSamples` and `decodedLocalHeight`, cut out of the source file, on the GPU
  of an Apple M1 Max against a 129 × 129 `r32Float` texture (22.5 for the small example, the
  exact texel on a sample, at both edges and one sample outside them, 102,060 coordinates
  within 2.4e-7, relative, of a CPU version); the `Terrain` struct is 32 bytes with the same
  field offsets in Metal and in C; the two texture tests fail against three deliberately broken
  copies of `makeHeightTexture` (rows reversed, rows and columns swapped, and each row starting
  one sample early, which imitates a wrong `bytesPerRow`); screenshots of the app with the
  TiledMSAATessellated renderer for both height sources. The image terrain was judged on its
  own, not against a build of the commit before. Not tested: the side length the scene passes
  (a scene builds itself when it is created), and the `precondition`. tvOS was not built.
  This commit also carries the part B revision of the entry below, which was not yet
  committed.
- **2026-11-25** — Milestone 3 part B, after a request from the owner: every variable, parameter
  and return value of the shader pseudocode now carries its Metal type, with a table of the
  types and seven rules where Metal differs from Swift. Three lines of the old pseudocode could
  not be typed as written and were changed: `heightMap.read(lowerColumn, lowerRow)` compiles but
  reads texel (lowerColumn, lowerColumn) of mip level lowerRow, and is now
  `read(uint2(lowerColumn, lowerRow)).r`; `min(floor(…), lastColumn - 1)` mixes `float` and
  `uint` ("call to 'min' is ambiguous") and now converts first; the clamp bounds and the
  (width − 1, height − 1) factor are built as `float2`. `.color` of the output struct receives
  `float4(localHeight)`, because the variable it was filled from is gone. Added: two edge cases
  and one Pitfalls row. No number changed. Checks run, all on scratch files outside the repo
  (Metal compiler 32023.922, against the real `ShaderDefinitions.h` and `TFSCommon.h`):
  `type_probe.metal` asserts the type of 19 expressions; `run_probes.sh` compiles 24 one-line
  shaders, 14 accepted and 10 refused, which is where the quoted error messages come from; a
  hand transcription of all of part B into a copy of `Tessellation.metal`,
  `part_b_transcribed.metal`, compiles without warnings for macOS, iOS and the iOS simulator;
  `plan_to_metal.py` reads the three functions and the vertex-function lines out of this file
  and turns them into Metal by mechanical rewriting (each type moved in front of its name,
  braces and semicolons added, the vertex-function lines wrapped in a function), and the result
  compiles for macOS and iOS; `run_helper_on_gpu.swift` ran the two helpers from both
  transcriptions on an Apple M1 Max against a 129 × 129 `r32Float` texture: 22.5 for the small
  example, the exact texel on a sample, at both edges and one sample outside them, and 102,060
  coordinates within 2.4e-7 (relative) of a CPU version written from the pseudocode;
  `texel_components.swift` confirmed (stored number, 0, 0, 1), `uint(2.9)` = 2 and the
  wrap-around. Not executed: the engine build and the app, because the working tree holds part
  B half-written.
- **2026-11-24** — Milestone 2 landed (49680b6) and was edited to match the code: the names the
  code uses are listed, the five listed tests check more than first listed, and two tests were
  added (7 in all; the suite now has 29). The review before landing found no defect in
  `bakeHeightSamples`; it added the doc comment and the tests. Checks run: the macOS build and
  test bundle, the full test suite one test at a time (589 Swift Testing tests and the 20
  XCTest tests), and the iOS build. The numbers of the tests were recomputed with a new scratch
  script written from the pseudocode, `bake_crosscheck.py` (default parameters, the 129 × 129
  grid that starts at sample index (−64, −64)): 16,641 samples; −328.78198 and −172.99075; a
  move of 4 samples shares 125 columns and no shared sample differs; storing a Float changes a
  height by at most 0.000026 m in this grid; its lowest sample is −329.05 m and its highest
  533.93 m, as Milestone 3 says. The test file was also run against eight deliberately broken
  copies of the bake (rows and columns swapped, the first indices swapped, the spacing
  ignored, the parameters ignored, and four more); each failed at least one test.
- **2026-11-24** — Milestone 1 landed (c795cb6) and was edited to match the code: `octaveCount`
  is `UInt32`, the parameter fields are `let` behind an initializer that checks `octaveCount`,
  the names the code uses are listed, and twelve tests were added to the list (22 in all). The
  review before landing found two defects, both fixed by the owner: `latticeValue` divided and
  subtracted in `UInt32` before converting to Double, and `valueNoise` computed the Z fraction
  from x. Checks run: the macOS build and test bundle, the full test suite (582 Swift Testing
  tests and the XCTest suites), and the iOS build. No number of the worked example changed. The
  thresholds of the new tests were checked with a scratch sweep over a corrected copy of the
  code (fade curve at 0.001: 9.985e-9; lattice values −1 to 0.99998; heights −489.6 m to
  509.8 m; the 1 mm step at 5,000 km: 0.00005 m).
- **2026-11-24** — Milestone 1, after a question from the owner: said that `low32Bits` is
  Swift's `UInt32(truncatingIfNeeded:)`, how the floor becomes an `Int` lattice index, and which
  types the parameter fields have (and that they are `var`). The conversions were run in a
  scratch script, `low32bits_check.swift` (−1 → 4,294,967,295; 4,294,967,297 → 1;
  `UInt32(clamping: -1)` → 0). No number in the plan changed.
- **2026-11-22** — Plan created from the research document and the current source. Every number
  was reproduced with one of two scratch scripts: `procedural_terrain_scratch.swift` (compiled
  twice, with and without optimization: the worked example, statistics, the gap to the drawn
  surface, bake times, the recentre rule) and an independent Python script,
  `terrain_crosscheck.py` (the worked example again, plus the small arithmetic examples in the
  milestones). Both live outside the repo; their inputs are listed under "Verification
  commands". The two scripts agree on every value they share. Not executed: the shader changes
  and the texture upload were reasoned from the source; nothing in the engine was compiled or
  run for this plan.

## Goal and what you will learn

When this plan is finished, `FlightboxWithTerrain` shows hills that no file describes. A small
function turns a position and a seed into a height. The engine evaluates that function on a grid
around the aircraft, uploads the grid as a texture, and the existing tessellated `TerrainObject`
draws it. When you fly away, the grid follows you, so there is ground wherever you go, and the
same place always has the same shape.

The plan is deliberately small. It adds one new source file, changes one shader file, one shared
struct, `TerrainObject` and one scene. It adds no new renderer, pipeline or draw path.

Learning objectives:
- How a hash function replaces stored random numbers, so a "random" world needs no storage.
- How value noise turns random numbers on a grid into a smooth surface, and why the shape of the
  blend curve matters for lighting.
- How summing noise at several scales (fBm) gives terrain-like detail, and why the grid you draw
  with limits how many scales are worth adding.
- How to sample a function onto a grid so that two grids agree exactly where they overlap.
- How the procedural world and the floating origin fit together: which numbers are absolute, which
  are relative, and where Double is needed.

Not in scope (each is a later plan; the research document's milestone list names them):
- Level of detail. The terrain is one grid with 100 m between vertices, and its edge is visible.
- Ground contact. The aircraft can fly through a hill. Physics needs its own height query that
  matches the drawn triangles (research 1.2.9).
- Terrain in the shadow pass, and terrain in the five renderers that do not draw it today.
- Baking on a worker thread, tile caches, real elevation data, a spherical planet.
- Better-looking noise (gradient noise, ridges, domain warping, erosion). The height function is
  one function; it can be swapped later without touching anything else in this plan.

## Terms

- **Procedural** — computed by a rule when needed, not loaded from a file.
- **Pure function** — a function whose result depends only on its inputs. Same inputs, same result,
  every time, on every launch.
- **Seed** — a number that selects one world out of all possible worlds. Changing it changes every
  height.
- **Hash function** — a function that scrambles a number so that nearby inputs give unrelated
  outputs. Here it stands in for a table of random numbers.
- **Lattice** — the grid of whole-number points in noise space: (0, 0), (1, 0), (0, 1) and so on.
  A **lattice point** is one of them. A **lattice cell** is the unit square between four of them.
- **Value noise** — a smooth function made by giving every lattice point a random value and
  blending between the four nearest ones.
- **Fade curve** — the S-shaped curve used for that blending. It is flat at both ends.
- **Octave** — one layer of noise. Each octave has cells half as wide as the octave before
  (**lacunarity** 2) and half the height (**gain** 0.5).
- **fBm (fractional Brownian motion)** — the sum of several octaves. Called "fractal noise" in the
  pseudocode.
- **Height sample** — one height, in meters, at one grid point. **Sample spacing** is the distance
  between neighbouring samples: 100 m here.
- **Sample index** — a whole number that names a sample's place on a grid that covers the entire
  world. Sample index 5 along X is at 500 m, in the original frame, forever.
- **Bake** — to evaluate the height function at every sample of a grid and store the results.
- **Original frame** — the scene's coordinates before any floating-origin shift. The codebase
  already uses this name (`kinematicFloorHeightInOriginalFrame`). A stored position plus
  `SceneManager.floatingOriginOffset` is a position in the original frame.
- **Current frame** — the coordinates stored positions use right now, after the shifts so far.
- **Focus** — the point the terrain is centred around: the player aircraft.
- **Recentre** — to move the terrain so the focus is near its middle again, and bake new samples.
- **Patch** — one square of the terrain's 32 × 32 input grid. The GPU's tessellator splits each
  patch into smaller cells. **Tessellation factor** is the number of cells along a patch edge.
- **Texel** — one element of a texture. Here one texel holds one height sample.
- **Bilinear interpolation** — blending four neighbouring values by position, first along one axis
  and then along the other.
- **Float gap** — the distance between one 32-bit float and the next larger one. It grows with the
  size of the number.

## The idea in plain words

**The problem.** The terrain today reads its heights from one image, `mountain.png`, stretched over
an 800 m square. To have ground everywhere without a file for everywhere, the heights must come
from a rule. The rule must give the same height for the same place every time it is asked, however
far the aircraft has flown and however many times the floating origin has shifted.

**The idea.** Use a pure function `heightInMeters(x, z, seed)`. It comes from three ideas stacked
on top of each other, all described in the research document (1.2.8) and its sources:

1. *A hash instead of stored random numbers.* Give each lattice point a pseudo-random value by
   scrambling its coordinates and the seed. Nothing is stored, and any point can be asked at any
   time.
2. *Value noise.* Inside a lattice cell, blend the four corner values with a smooth curve. The
   result is a continuous, gently rolling surface.
3. *Octaves.* Add the same noise again with cells half as wide and half as tall, several times.
   Wide octaves make mountains, narrow ones make bumps on the mountains.

The function is evaluated on the CPU in Double, at positions in the original frame. The results
are stored as 32-bit floats in a 129 × 129 grid and uploaded as a texture. The existing terrain
shader reads that texture instead of the image. The GPU never sees a large number: it gets a
small texture and a terrain position in the current frame.

**The steps.**
1. Write the height function and test it without Metal (Milestone 1).
2. Bake a grid of samples from it and test that neighbouring grids agree (Milestone 2).
3. Upload the grid as a texture and draw it with the existing `TerrainObject` (Milestone 3).
4. Make the grid follow the aircraft (Milestone 4).
5. Optional: shade the slopes with normals computed from the same samples (Milestone 5).

Milestones 1 to 3 are the generator and the smallest wiring that shows it. They stand alone: stop
after 3 and you have a fixed 12.8 km square of procedural hills. Milestone 4 makes it endless.
Milestone 5 depends only on 3.

## Worked example

Inputs: seed 2026, base cell size 3,200 m, height amplitude 600 m, 4 octaves, lacunarity 2,
gain 0.5. Position in the original frame: x = 1,000 m, z = −500 m. The negative z is on purpose: it
shows why the lattice index must be rounded down, not toward zero.

Step 1 — convert to noise space: divide by the base cell size.
(1000 / 3200, −500 / 3200) = (0.3125, −0.15625).

Step 2 — octave 0 (cell size 3,200 m, seed 2026). Lattice cell = floor of each coordinate =
(0, −1). Fraction inside the cell = (0.3125 − 0, −0.15625 − (−1)) = (0.3125, 0.84375).
Truncating toward zero would give cell (0, 0) and fraction −0.15625, which is wrong.

Step 3 — the four corner values. `scrambleBits(2026)` = 0x41cfd7c2.

| Lattice point | Hash | Top 24 bits | Value = bits / 8,388,608 − 1 |
|---|---|---|---|
| (0, −1) | 0x2fd06d87 | 3,133,549 | −0.626452 |
| (1, −1) | 0x548d2c8c | 5,541,164 | −0.339442 |
| (0, 0) | 0x58eb345b | 5,827,380 | −0.305322 |
| (1, 0) | 0xce553f58 | 13,522,239 | 0.611977 |

Step 4 — blend. fadeCurve(0.3125) = 0.180006 and fadeCurve(0.84375) = 0.970235.
Along X on the edge z = −1: −0.626452 + (−0.339442 − (−0.626452)) × 0.180006 = −0.574788.
Along X on the edge z = 0: −0.305322 + (0.611977 − (−0.305322)) × 0.180006 = −0.140203.
Along Z between the two: −0.574788 + (−0.140203 − (−0.574788)) × 0.970235 = **−0.153138**.

Step 5 — the other octaves, each with its own seed.

| Octave | Cell size | Point in that octave | Seed | Noise value | Amplitude | Contribution |
|---|---|---|---|---|---|---|
| 0 | 3,200 m | (0.3125, −0.15625) | 2026 | −0.153138 | 1 | −0.153138 |
| 1 | 1,600 m | (0.625, −0.3125) | 2027 | −0.533755 | 0.5 | −0.266878 |
| 2 | 800 m | (1.25, −0.625) | 2028 | −0.612561 | 0.25 | −0.153140 |
| 3 | 400 m | (2.5, −1.25) | 2029 | 0.268727 | 0.125 | 0.033591 |

Step 6 — sum and scale. Sum = −0.539565. Sum of amplitudes = 1.875. Fractal noise =
−0.539565 / 1.875 = −0.287768.

Result: height = 600 × −0.287768 = **−172.6609 m**.

Three more values for tests: height at (0, 0) is −172.9908 m; at (3200, 6400) it is 533.9311 m;
at (6400, 6400) it is −110.4141 m.

## Data, units, and conventions

| Quantity | Symbol | Name in pseudocode and code | Unit | Frame | Sign or convention |
|---|---|---|---|---|---|
| World selector | — | `seed` | — | — | unsigned 32-bit |
| Width of the widest octave's cells | — | `baseCellSize_m` | m | — | 3,200 by default |
| Largest height the function can return | A | `heightAmplitude_m` | m | — | heights lie in −A … +A |
| Number of octaves | n | `octaveCount` | — | — | at least 1; 4 by default |
| Cell-size ratio between octaves | — | `lacunarity` | — | — | 2 |
| Height ratio between octaves | — | `gain` | — | — | 0.5 |
| Position the height is asked for | (x, z) | `xInOriginalFrame_m`, `zInOriginalFrame_m` | m | original frame | Double; +Y is up |
| Lattice point | (i, k) | `latticeX`, `latticeZ` | — | noise space | signed whole numbers |
| Fraction inside a lattice cell | — | `fractionX`, `fractionZ` | — | noise space | 0 ≤ fraction < 1 |
| Distance between samples | d | `sampleSpacing_m` | m | — | 100 |
| Samples along one side of the grid | N | `samplesPerSide` | — | — | 129 = 32 patches × 4 cells + 1 |
| Place of a sample on the world-wide grid | — | `sampleIndexX`, `sampleIndexZ` | — | original frame | position = index × `sampleSpacing_m` |
| Sample the terrain is centred on | — | `centerSampleIndexX`, `centerSampleIndexZ` | — | original frame | a multiple of `snapStepInSamples` |
| Recentre step | — | `snapStepInSamples` | samples | — | 4 = one patch = 400 m |
| Distance that triggers a recentre | — | `recenterThresholdInSamples` | samples | — | 4 = 400 m |
| Farthest a focus may be from sample 0 | — | `maxFocusDistanceFromOriginInSamples` | samples | original frame | 2^53; a focus beyond it, NaN or infinite → no recentre |
| Baked heights | — | `heightSamples` | m | original frame | row-major: index = row × N + column; column runs along +X, row along +Z |
| Place of a vertex on the sample grid | — | `sampleCoordinate` | samples | terrain-local | 0 … N − 1; whole numbers are samples |

Sizes that follow: the terrain is (129 − 1) × 100 m = 12,800 m on a side, a patch is 400 m, and at
the lowest tessellation factor (4) there is exactly one vertex per sample.

```
one side of the grid:  129 samples, 128 cells of 100 m, 32 patches of 4 cells

sample column:   0    1    2    3    4    5   ...  124  125  126  127  128
                 |----|----|----|----|----|--  ...  --|----|----|----|----|
patch:           [      patch 0      ][   patch 1 ...        patch 31     ]
local x (m):   -6400               -6000                               +6400
```

Update order (all on the UpdateThread, inside one tick):
1. `FlightboxWithTerrain.doUpdate()` asks the terrain to follow the focus. If a recentre is due,
   the terrain bakes, swaps its texture and calls `setPosition`.
2. The scene traversal then calls `TerrainObject.update()`, which caches `modelConstants` with the
   new position. Step 1 must come first, or the new texture is drawn at the old position for one
   frame.
3. `SceneManager.updateFloatingOrigin()` may then shift every direct child of the scene, the
   terrain included. The terrain needs no special handling: its heights are tied to sample
   indices, not to stored positions.

Engine conventions that apply: left-handed, +Y up, meters; the scene graph and `TerrainObject`
state are written only on the UpdateThread; the render thread reads `heightMap`, `terrain` and the
cached `modelConstants` after the update handshake; a stored position is relative to the current
floating origin, and a value in the original frame is obtained by adding
`SceneManager.floatingOriginOffset` in Double.

## Engine integration points

New files:
- `ToyFlightSimulator Shared/GameObjects/Tesselation/ProceduralTerrain.swift` — the pure
  functions and the parameter struct. No Metal, no engine state, so tests can call it directly
  (the same shape as `Managers/FloatingOrigin.swift`).
- `ToyFlightSimulatorTests/GameObjects/ProceduralTerrainTests.swift` — Metal-free tests.
- `ToyFlightSimulatorTests/GameObjects/TerrainHeightTextureTests.swift` — the app-hosted tests
  (Milestones 3 and 4).

Changed files:
- `Graphics/Shaders/TFSCommon.h` — the `Terrain` struct (Milestone 3).
- `Graphics/Shaders/Tessellation.metal` — `tessellation_vertex`, `SampleTerrainLayer` and the two
  fragment functions that call it (Milestones 3 and 5). `compute_tessellation` is not touched.
- `Graphics/Shaders/ShaderDefinitions.h` — `TessellationVertexOut` (Milestone 5 only).
- `GameObjects/Tesselation/TerrainObject.swift` — the height source, the texture, `follow`
  (Milestones 3 and 4).
- `Scenes/FlightboxWithTerrain.swift` — `addTerrain`, the jet's start height, `doUpdate`
  (Milestones 3 and 4).
- `Core/Preferences.swift` — one debug flag next to `DEBUG_FLOATING_ORIGIN` (Milestone 4).

Not changed: `SceneManager`, `DrawManager`, `FloatingOrigin`, the renderers, the pipelines, the
compute kernel, `TessellationRendering`.

Constraints from CLAUDE.md that shape the plan:
- Both source folders are synchronized folders. A new file created inside them joins the targets
  by itself. After adding the files, run `git diff` on `project.pbxproj`: it should show no new
  `membershipExceptions`.
- The terrain is drawn only by `TiledMSAATessellatedRenderer`. To see it, set
  `Preferences.StartingSceneType` to `.FlightboxWithTerrain` (the line is already there,
  commented out).
- A test that constructs a `GameObject` needs a Metal device and the app as host. Everything in
  `ProceduralTerrain.swift` is testable without that.
- Three frames can be in flight. A resource a frame was encoded with must not change under it.

## Design decisions and where they came from

Each entry gives the choice, the alternative that was rejected, and why.

**The generator**

- [source: research 1.2.8 and 2.2] **Heights come from a pure function of position and seed.**
  Rejected: a larger height image (needs data that does not exist yet) and erosion simulation
  (the height at one point depends on a whole watershed, so it cannot be asked point by point).
  Why: constant memory, any point at any time, the same answer every time. The research document
  recommends "procedural first, real data second", because only the function that fills the grid
  changes later.
- [source: research 2.2 step 2] **Value noise is the first noise.** Rejected: gradient ("Perlin")
  noise, simplex noise, and Apple's GameplayKit noise classes. Why: value noise is the simplest
  noise there is (random heights on a grid, blended), so every line can be explained. Gradient
  noise looks better but adds a second idea (random slopes and dot products). A library call
  would hide the algorithm this plan exists to teach. Known cost: value noise shows faint
  streaks along X and Z; see Pitfalls.
- [source: Wellons 2018] **Lattice values come from an integer hash, `lowbias32`.** Rejected:
  (a) Swift's `Hasher` or `hashValue`, which are seeded differently on every launch, so the world
  would change each run; (b) the `fract(sin(x) × 43758.5453)` trick common in shader tutorials,
  which depends on how each platform computes `sin` and breaks down at large inputs; (c) a
  256-entry permutation table as in Perlin's original code, which repeats every 256 cells and is
  stored state. Why: integer operations give identical bits everywhere, and the function is
  seven lines.
- [source: Perlin 1985, as described by Jarzynski and Olano 2020, section 4.2] **Two coordinates
  and the seed are combined by nesting:** `hash(x + hash(z + hash(seed)))`. Rejected: multiplying
  each coordinate by a prime and XOR-ing (what FastNoiseLite does). Why: nesting needs no extra
  constants and has a published description.
- [source: Perlin 2002] **The fade curve is 6t⁵ − 15t⁴ + 10t³.** Rejected: a straight line
  (visible creases along every lattice line) and the cubic 3t² − 2t³. Why: Perlin's paper says the
  cubic's second derivative is not zero at 0 and 1, and that the resulting discontinuities
  "become noticeable when a Noise-displaced surface" is shaded. This terrain is exactly a
  noise-displaced, shaded surface. The fifth-degree curve has zero first and second derivatives
  at both ends.
- [source: research 1.2.8, Quilez] **Lacunarity 2 and gain 0.5.** Why: with these, every octave is
  the same shape at half the size ("a mountain that is higher is also wider at its base by the
  same amount"), which is the usual choice for mountains.
- [design; the reference implementation FastNoiseLite does the same with `seed++`] **Each octave
  uses its own seed (`seed + octaveIndex`).** Rejected: one seed for all octaves. Why: with one
  seed, lattice point (0, 0) has the same value in every octave, so the origin of the world would
  always be an extreme peak or pit.
- [design, from the sampling theorem; numbers by script] **The octave count is limited by the
  sample spacing: the narrowest octave's cells must be at least 4 samples wide.** With 100 m
  spacing and a 3,200 m base cell that allows 4 octaves (3,200, 1,600, 800, 400 m). Rejected:
  "more octaves is more detail". Why: an octave narrower than the grid cannot be drawn. It only
  makes the drawn surface disagree with the function. At the lowest tessellation factor the
  drawn surface is two flat triangles per 100 m cell. Measured largest gap between that surface
  and the function: 9.2 m with 4 octaves, 16.7 m with 5, 26 m with 7 (root-mean-square 1.3, 2.6
  and 3.7 m). Splitting the cells along the other diagonal gives 9.2, 16.7 and 24 m.

**Coordinates and precision**

- [codebase: the floating-origin rules in CLAUDE.md] **The function takes positions in the
  original frame, in Double, on the CPU.** Rejected: evaluating the noise in the vertex shader.
  Why: Metal shaders have no Double. A float position 100 km from the start has a 7.8 mm gap,
  which is the problem the floating origin was built to remove. Heights that exist only on the
  GPU are also invisible to a later physics query (research 1.2.9, rule 5).
- [source: research 2.2, "Cost per sample"] **Bake once per recentre, not per vertex per frame.**
  Why: one bake is 16,641 samples. Per frame it would be the same work 60 times a second.
- [design; checked by script] **A sample is addressed by a whole-number sample index, and its
  position is index × spacing.** Rejected: computing each sample's position as
  "grid corner + column × spacing" from a floating-point corner. Why: with whole-number indices,
  two bakes that cover the same sample compute it from the same inputs and get the same bits. The
  script confirms that a bake moved by 4 samples equals the old bake everywhere they overlap.

**Storage and drawing**

- [source: research 2.2 step 3] **Samples are 32-bit floats in meters, in an `r32Float` texture.**
  Rejected: `r8Unorm` like the current image (255 steps over a 1,200 m range is 4.7 m per step),
  `r16Float` (0.5 m gap at 600 m), and 16-bit integers with a scale and offset (the research
  document lists that as a later memory optimization). Why: the CPU array and the texture hold the
  same bits, with a 0.06 mm gap at 600 m, and no decode step to get wrong. Cost: 65 KB.
- [design; fact from Apple's Metal Feature Set Tables, footnote 6] **The shader reads four texels
  with `read()` and blends them itself.** Rejected: a linear sampler. Why: filtering 32-bit float
  textures is not guaranteed on Apple GPUs (a device reports it in
  `MTLDevice.supports32BitFloatFiltering`), and this project also builds for iOS and tvOS. Doing
  the blend by hand also makes the vertex-to-sample mapping explicit (a sampler hides a half-texel
  offset). Note what the blend is and is not: it gives the height of a vertex the tessellator
  adds *between* samples, which happens only near the camera. At the lowest factor every vertex
  is on a sample and the drawn surface is two flat triangles per cell. A later CPU height query
  must reproduce those triangles, not the blend (research 1.2.9, rule 2).
- [codebase] **Reuse `TerrainObject` and the tessellation pipeline.** Rejected: (a) the CDLOD
  renderer the research document recommends as the end state, which needs a quadtree, a morph
  shader and a pipeline per renderer, and deserves its own plan; (b) building ordinary meshes on
  the CPU, which needs a new path through `Model` and `Mesh` and runtime registration. Why: the
  change set stays inside files that already exist for terrain, and nothing baked here is wasted
  later: a CDLOD tile is the same samples in the same texture format.
- [design; codebase constraint: `SceneManager.tessellatables` is read at encode time without a
  lock] **One terrain object that moves, not tile objects that are added and removed.** Why: no
  runtime registration, no cache, no eviction. Tiles belong to the level-of-detail plan.
- [project rule: keep superseded code that still teaches something] **`mountain.png` stays
  selectable through a `TerrainHeightSource` value.** Both sources go through the same shader
  code; only the numbers in the `Terrain` struct differ.
- [design] **The height decode and the colour thresholds become fields of the `Terrain` struct.**
  Rejected: new constants written into the shader. Why: the image stores 0 … 1 and the procedural
  texture stores meters, so the shader needs a scale and an offset; and the old thresholds (−0.5
  and 0.3) are in the image's units, so in meters everything would be drawn with one texture.

**Following the aircraft**

- [design] **The terrain's centre is always a multiple of one patch (4 samples, 400 m) on the
  world-wide sample grid.** Rejected: centring exactly on the aircraft every tick. Why: when the
  centre only moves by whole patches, every sample and every vertex lands on a world point that
  had a sample before. The ground keeps its shape and does not "swim" as you fly.
- [design; the pattern is `FloatingOrigin.getOffset`, which returns nil when no shift is due] **A
  recentre happens only when the focus is more than 400 m from the centre, and then the centre
  snaps to the nearest patch.** Rejected: "recentre whenever the nearest patch changes". Why:
  after a recentre the focus is within 200 m of the centre and must travel another 200 m before
  the next one, so flying along a boundary cannot cause a bake on every tick.
- [codebase] **The focus is the player aircraft's stored position plus
  `SceneManager.floatingOriginOffset`, and the scene passes it in.** Rejected: reading the current
  camera's world position inside the terrain. Why: the aircraft is a direct child of the scene, so
  its stored position and the offset total are shifted together and are always consistent. A
  camera parented to the aircraft is not: on the tick after a shift its world position is still
  the old one until its parent updates (the comment in `GameScene.update()` measures this as
  "about 1 km off"). The terrain is added to the scene before the jet, so it would read exactly
  that stale value and recentre 1 km away for one tick.
- [design; codebase: three frames in flight] **Each bake makes a new texture and the terrain
  swaps the reference.** Rejected: `replace(region:)` on the texture already bound. Why: frames
  encoded earlier may not have run on the GPU yet. They would draw the new heights at the old
  terrain position, a 400 m jump for one frame. A command buffer keeps the old texture alive until
  it finishes.
- [design] **The colour textures repeat 128 times across the terrain (once per 100 m).** Why: the
  texture coordinate is measured across the terrain, so it moves with the terrain. A recentre
  moves the terrain by 400 m. If 400 m is a whole number of repeats (here 4), the pattern lands on
  itself and nothing appears to slide.

**Normals (optional milestone)**

- [source: Apple's terrain sample derives normals from height differences (research 1.3); design:
  where it runs] **Normals are computed in the vertex function from the same four neighbouring
  heights.** Rejected: baking a normal texture on the CPU and binding it to the fragment
  function's existing `normalTexture` slot. Why: that needs a signed, filterable texture format,
  packing code, a linear sampler and a second copy of the vertex-to-sample mapping. The vertex
  function already has the texture and the mapping; it needs one new output field and a few
  lines.

## Verification commands

```bash
# Build the app and the test bundle (the scheme's Build action builds the app only)
xcodebuild build-for-testing -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Run one suite, serial per project rule
xcodebuild test-without-building -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug -parallel-testing-enabled NO \
  -only-testing:"ToyFlightSimulatorTests/ProceduralTerrainTests" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# The shader change must also compile for iOS
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator iOS" \
  -sdk iphonesimulator -configuration Debug
```

Scratch script inputs, so the numbers can be regenerated: the algorithm exactly as in Milestones
1, 2 and 4; seed 2026 (and 7 for one comparison); base cell 3,200 m and 6,400 m; amplitude 600 m
and 1,000 m; 3 to 7 octaves; sample spacing 100 m; 129 samples per side; a 1,025 × 1,025 survey
grid centred on the origin for the statistics; a 10 × 10 sub-grid inside each of 128 × 128 cells
for the gap between the function and the drawn surface, with each cell split into two triangles
along either diagonal (`triangleSurfaceHeight` from the research document, 1.2.9); timing as the
best of 20 bakes on an Apple M1 Max, compiled with `swiftc -O` and with `swiftc -Onone`.

## Milestones

### Milestone 1 — The height function ✅ (landed 2026-11-24, c795cb6)

- **Learning objective:** how a hash, a blend and a sum of octaves make a deterministic terrain
  height, and how to test such a function without drawing anything.
- **Prerequisites:** the Terms above and the worked example.
- **Engine integration points:** new file `GameObjects/Tesselation/ProceduralTerrain.swift`. It
  holds a struct `ProceduralTerrainParameters` (the six fields of the table above, with the
  defaults seed 2026, 3,200 m, 600 m, 4, 2, 0.5) and a caseless enum `ProceduralTerrain` whose
  static functions are the ones below. Write it like `Managers/FloatingOrigin.swift`: no stored
  state, everything passed in. Field types: `seed` and `octaveCount` are `UInt32` (so the seed
  of an octave is `seed &+ octaveIndex` with no conversion), and the other four are `Double`, so
  that no step of the height function is narrower than Double. The fields are `let`. The struct
  has a hand-written initializer whose six arguments carry the defaults, so a caller names only
  what it changes (the tests pass a different seed), and which stops the program with a
  `precondition` when `octaveCount` is 0. A parameters value that exists is therefore valid.
  This is the pattern of `ValueCurve.init(keys:)` in `Utils/ValueCurve.swift`. New test file
  `ToyFlightSimulatorTests/GameObjects/ProceduralTerrainTests.swift`, tagged `.gameObjects`.
- **Names in the code.** The owner's code drops the unit suffix and shortens three names. Where
  the pseudocode of this plan says `baseCellSize_m`, `heightAmplitude_m`, `parameters`,
  `octaveIndex`, `xInOriginalFrame_m` and `zInOriginalFrame_m`, the code says `baseCellSize`,
  `heightAmplitude`, `params`, `octaveIdx`, `xInOriginalFrame` and `zInOriginalFrame`. The
  units are the same (meters) and are stated in the doc comments. `linearBlend` takes `start`,
  `end` and `weight`; `fadeCurve` takes `t`.
- **Algorithm:**

Three details are easy to get wrong in Swift. First, the two multiplies and the two adds in the
hash must *wrap*: keep the low 32 bits and discard the rest. A plain `*` or `+` on `UInt32` traps
on overflow; the wrapping operators are `&*` and `&+`. Second, a lattice index is the *floor* of
the coordinate, not the coordinate truncated toward zero. They differ for every negative value.
In Swift the floor of a Double is still a Double (`x.rounded(.down)`): convert it to `Int` for the
lattice index, and keep the Double for the subtraction that gives the fraction.

Third, `low32Bits` is not a function you have to write. It is this plan's name for a conversion
the Swift standard library already has: the initializer `UInt32(truncatingIfNeeded:)`, which
every whole-number type provides. A signed whole number is stored in *two's complement*, where −1
is "all bits set". The initializer copies the lowest 32 of those bits and drops the rest, so −1
becomes 4,294,967,295, −2 becomes 4,294,967,294, and 4,294,967,297 (2³² + 1) becomes 1. Keep the
lattice index as an `Int` (64 bits) and convert it only inside `hashOfLatticePoint`. The other
conversions are wrong here: `UInt32(latticeX)` traps on a negative index, and
`UInt32(clamping: latticeX)` turns every negative index into 0, so all lattice points with a
negative index would share one value. (`UInt32(bitPattern:)` does the same job as
`truncatingIfNeeded`, but only accepts an `Int32`.)

```pseudocode
// Scrambles the 32 bits of a number so that inputs differing in one bit give unrelated outputs.
// This is "lowbias32" (Wellons 2018). All values are unsigned 32-bit.
// Each step mixes bits in one direction: the shift-and-XOR folds high bits into low bits,
// and the multiply by a large odd constant spreads low bits into high bits.
function scrambleBits(value) -> unsigned32
    x = value
    x = x XOR (x shiftedRightBy 16)
    x = wrappingMultiply(x, 0x7feb352d)        // wrapping: keep only the low 32 bits of the product
    x = x XOR (x shiftedRightBy 15)
    x = wrappingMultiply(x, 0x846ca68b)
    x = x XOR (x shiftedRightBy 16)
    return x

// One pseudo-random number per lattice point and seed. Nesting the hash makes the result depend
// on all three inputs: change any one of them and the output changes completely.
function hashOfLatticePoint(latticeX, latticeZ, seed) -> unsigned32
    // low32Bits keeps the lowest 32 bits of a signed whole number and reads them as unsigned,
    // so -1 becomes 4,294,967,295. In Swift: UInt32(truncatingIfNeeded:), see the note above.
    seedHash = scrambleBits(seed)
    zHash = scrambleBits(wrappingAdd(low32Bits(latticeZ), seedHash))
    return scrambleBits(wrappingAdd(low32Bits(latticeX), zHash))

// The lattice point's random value, from -1 up to (but not including) +1.
function latticeValue(latticeX, latticeZ, seed) -> Double
    top24Bits = hashOfLatticePoint(latticeX, latticeZ, seed) shiftedRightBy 8    // 0 … 16,777,215
    return top24Bits / 8388608 - 1                                               // 8,388,608 = 2^23

// Perlin's fifth-degree fade curve: 0 at t = 0, 1 at t = 1, and flat (zero slope, zero
// curvature) at both ends, so neighbouring cells join without a crease.
function fadeCurve(t) -> Double
    return t * t * t * (t * (t * 6 - 15) + 10)

function linearBlend(startValue, endValue, weight) -> Double
    return startValue + (endValue - startValue) * weight

// Smooth noise in -1 … +1. x and z are in noise space: one unit is one lattice cell.
function valueNoise(x, z, seed) -> Double
    latticeX = floor(x)                         // FLOOR, not truncation: floor(-0.15625) is -1
    latticeZ = floor(z)
    fractionX = x - latticeX                    // 0 ≤ fraction < 1, also for negative x
    fractionZ = z - latticeZ
    valueAtLowXLowZ   = latticeValue(latticeX,     latticeZ,     seed)
    valueAtHighXLowZ  = latticeValue(latticeX + 1, latticeZ,     seed)
    valueAtLowXHighZ  = latticeValue(latticeX,     latticeZ + 1, seed)
    valueAtHighXHighZ = latticeValue(latticeX + 1, latticeZ + 1, seed)
    weightX = fadeCurve(fractionX)
    weightZ = fadeCurve(fractionZ)
    alongLowZEdge  = linearBlend(valueAtLowXLowZ,  valueAtHighXLowZ,  weightX)
    alongHighZEdge = linearBlend(valueAtLowXHighZ, valueAtHighXHighZ, weightX)
    return linearBlend(alongLowZEdge, alongHighZEdge, weightZ)

// The sum of octaves, scaled back into -1 … +1.
function fractalNoise(x, z, parameters) -> Double
    sum = 0
    amplitude = 1                               // height of the current octave
    frequency = 1                               // how many of its cells fit in one base cell
    amplitudeTotal = 0
    for each octaveIndex in 0 ..< parameters.octaveCount
        octaveSeed = wrappingAdd(parameters.seed, octaveIndex)     // each octave is its own noise
        sum = sum + amplitude * valueNoise(x * frequency, z * frequency, octaveSeed)
        amplitudeTotal = amplitudeTotal + amplitude
        amplitude = amplitude * parameters.gain
        frequency = frequency * parameters.lacunarity
    return sum / amplitudeTotal                 // dividing by the largest possible sum keeps |result| ≤ 1

// The terrain height at one point. Inputs are meters in the scene's original frame, as Double.
function heightInMeters(xInOriginalFrame_m, zInOriginalFrame_m, parameters) -> Double
    noiseX = xInOriginalFrame_m / parameters.baseCellSize_m
    noiseZ = zInOriginalFrame_m / parameters.baseCellSize_m
    return parameters.heightAmplitude_m * fractalNoise(noiseX, noiseZ, parameters)
```

Everything inside is Double. The inputs can be millions of meters and the fraction inside a cell
is still exact to far below a millimeter; there is nothing to think about. The result is narrowed
to Float only when it is stored (Milestone 2).

- **Tests** (all Metal-free; values from the worked example and the scratch script):
  - [x] `ProceduralTerrainTests.scrambleBitsMatchesReferenceValues` — `scrambleBits(0)` is 0,
    `scrambleBits(1)` is 0x688990c0, `scrambleBits(2026)` is 0x41cfd7c2,
    `scrambleBits(0xffffffff)` is 0x6768824a.
  - [x] `latticeHashMatchesWorkedExample` — the four hashes of the worked example's table, for
    seed 2026. This is the test that catches a missing wrap or a wrong nesting order.
  - [x] `latticeValueStaysInRange` — for 41 × 41 lattice points and 5 seeds, −1 ≤ value < 1,
    and the values reach below −0.99 and above 0.99.
  - [x] `fadeCurveValues` — 0 at 0, 1 at 1, 0.5 at 0.5, 0.103515625 at 0.25, 0.896484375 at 0.75.
  - [x] `valueNoiseEqualsLatticeValueAtLatticePoints` — `valueNoise(1, 2, seed 2026)` is
    0.964206 and equals `latticeValue(1, 2, 2026)`; the same equality at four more lattice
    points, three of them with a negative index.
  - [x] `valueNoiseUsesFloorForNegativeCoordinates` — `valueNoise(0.3125, −0.15625, 2026)` is
    −0.153138 within 1e-6.
  - [x] `valueNoiseIsContinuousAcrossCellEdges` — values 1e-9 on either side of the edges at
    −1, 0 and 1 differ by less than 1e-6, crossing along X and crossing along Z.
  - [x] `heightMatchesWorkedExample` — −172.6609 m at (1000, −500), −172.9908 m at (0, 0),
    533.9311 m at (3200, 6400), −110.4141 m at (6400, 6400), each within 1e-3 m, default
    parameters.
  - [x] `heightIsDeterministicAndDependsOnTheSeed` — two calls agree exactly; seed 7 gives a
    different height at (1000, −500).
  - [x] `heightStaysWithinTheAmplitude` — over 73 × 73 points 1,370 m apart, |height| ≤ 600 m,
    and the terrain is not flat: some point is below −300 m and some point above 300 m.

  Twelve more tests were added with the code (review of 2026-11-24):
  - [x] `latticeHashDependsOnEveryInput` — the hash of (1, 0) differs from the hash of (0, 1),
    and from the hash of (1, 0) with seed 2027.
  - [x] `latticeHashRepeatsEveryTwoToThe32Cells` — a lattice index and the same index plus or
    minus 2³² give the same hash.
  - [x] `latticeValueMatchesWorkedExample` — the four values of the worked example's table,
    each within 1e-6.
  - [x] `latticeValueOfTheAllZeroInput` — seed 0 at lattice point (0, 0) gives exactly −1.
  - [x] `fadeCurveIsFlatAtBothEnds` — the curve moves less than 1e-7 in the first and in the
    last thousandth of the cell. A straight line or the curve 3t² − 2t³ fails this.
  - [x] `linearBlendValues` — from −2 to 6: −2 at weight 0, 0 at 0.25, 2 at 0.5, 6 at 1.
  - [x] `valueNoiseMatchesWorkedExampleOctaves` — the four noise values of the worked example's
    octave table, each within 1e-6.
  - [x] `valueNoiseStaysInRange` — over 61 × 61 points between the lattice points, the noise
    stays between −1 and +1.
  - [x] `fractalNoiseWithOneOctaveIsValueNoise` — with `octaveCount` 1 the two are equal.
  - [x] `fractalNoiseMatchesWorkedExample` — −0.287768 within 1e-6.
  - [x] `heightScalesWithAmplitudeAndBaseCellSize` — twice the amplitude gives exactly twice
    the height; twice the base cell size gives the same height at twice the distance.
  - [x] `heightIsSmoothFarFromTheOrigin` — 5,000 km from the origin, a step of 1 mm changes the
    height by less than 1 cm (a Float there can only hold multiples of 0.5 m).

  The `precondition` on `octaveCount` has no test: a failed precondition stops the test process.
- **Observable completion criteria:** the suite passes. Nothing changes in the app yet.
- **Edge cases and expected results:**
  - A negative coordinate → the cell to its left or below, fraction between 0 and 1 (worked
    example, step 2).
  - A point exactly on a lattice point → the fraction is 0, the weights are 0, and the result is
    that lattice point's value.
  - Seed 0 at lattice point (0, 0) → `scrambleBits(0)` is 0, so the hash is 0 and the value is
    exactly −1. Harmless: it is one lattice point of one octave.
  - `octaveCount` 0 → the initializer of `ProceduralTerrainParameters` stops the program
    (`precondition`). Without the check, `fractalNoise` would divide zero by zero and every
    height would be NaN.
  - Very large coordinates → the lattice index wraps after 2³² cells. For the narrowest octave
    (400 m) that is 1.7 × 10¹² m. The world repeats after 1.7 billion km.

### Milestone 2 — Baking a grid of height samples ✅ (landed 2026-11-24, 49680b6)

- **Learning objective:** how to sample a continuous function onto a grid so that any two grids
  agree exactly where they overlap, and how the memory layout of the grid is defined.
- **Prerequisites:** Milestone 1.
- **Engine integration points:** one more static function in `ProceduralTerrain`, below
  `heightInMeters`. More tests in `ProceduralTerrainTests`.
- **Names in the code.** As in Milestone 1, the code drops the unit suffix. Where the
  pseudocode says `sampleSpacing_m`, `parameters`, `xInOriginalFrame_m`, `zInOriginalFrame_m`
  and `height_m`, the code says `sampleSpacing`, `params`, `xInOriginalFrame`,
  `zInOriginalFrame` and `height`. The units are the same (meters) and are stated in the doc
  comment. `narrowToFloat` is `toFloat()`, the extension on Double in
  `Core/Types/MetalTypes.swift`: it is `Float(value)`, which rounds to the nearest Float. The
  two first sample indices and `samplesPerSide` are `Int`.
- **Algorithm:**

```pseudocode
// Evaluates the height function on a square grid. The grid is a window onto a world-wide grid
// of samples: sample index i along X sits at i * sampleSpacing_m in the original frame.
// Returns samplesPerSide * samplesPerSide heights in meters, row by row.
// Row r holds the samples with Z index firstSampleIndexZ + r; inside a row, column c holds the
// sample with X index firstSampleIndexX + c.
function bakeHeightSamples(firstSampleIndexX, firstSampleIndexZ, samplesPerSide,
                           sampleSpacing_m, parameters) -> list of Float
    heightSamples = list of (samplesPerSide * samplesPerSide) Floats
    for each row in 0 ..< samplesPerSide
        // whole number times spacing, in Double: the same sample index always gives the same position
        zInOriginalFrame_m = (firstSampleIndexZ + row) * sampleSpacing_m
        for each column in 0 ..< samplesPerSide
            xInOriginalFrame_m = (firstSampleIndexX + column) * sampleSpacing_m
            height_m = heightInMeters(xInOriginalFrame_m, zInOriginalFrame_m, parameters)
            heightSamples[row * samplesPerSide + column] = narrowToFloat(height_m)
    return heightSamples
```

A grid centred on sample (`centerSampleIndexX`, `centerSampleIndexZ`) starts at
`center − (samplesPerSide − 1) / 2`. With 129 samples that is `center − 64`.

- **Tests** (Metal-free):
  - [x] `bakeHasOneFloatPerSample` — 129 samples per side gives 16,641 values, all finite.
  - [x] `bakeMatchesTheHeightFunction` — on a 9 × 9 grid, every sample equals
    `heightInMeters` at its position, narrowed to Float. Nothing in this grid is symmetric: it
    starts at sample index (−3, 5), the spacing is 250 m and the seed is 7. Swapped rows and
    columns, swapped first indices, an ignored spacing and ignored parameters each fail it.
  - [x] `bakeLayoutIsRowsAlongZColumnsAlongX` — first index (−64, −64), 129 per side, spacing
    100 m: element 0 is −328.78198 (the sample at (−6400, −6400) m); element 64 × 129 + 64 is
    −172.99075 (the sample at the origin); element 1 equals the height at (−6300, −6400) m and
    element 129 equals the height at (−6400, −6300) m. Three heights of the worked example are
    read at their places, each within 1e-3 m: −172.6609 in column 74 of row 59 (the sample at
    (1000, −500) m), 533.9311 in column 96 of row 128 ((3200, 6400) m) and −110.4141 in the
    last element ((6400, 6400) m). With rows and columns swapped the second of these would be
    −138.6.
  - [x] `neighbouringBakesShareTheirBorderExactly` — the last column of a bake starting at X
    index 0 equals, with `==`, the first column of a bake starting at X index 128. The same
    for its last row and the first row of a bake starting at Z index 128.
  - [x] `overlapOfTwoBakesIsBitEqual` — a bake starting 4 samples further along X equals the old
    one on all 125 shared columns. The same for a move of 4 samples along Z and for a move of
    (−4, 8) samples. The comparison is of the bits (`bitPattern`).

  Two more tests were added with the code (review of 2026-11-24):
  - [x] `bakeUsesTheSampleSpacing` — a 9 × 9 bake with 200 m spacing equals, with `==`, every
    second sample of a 17 × 17 bake with 100 m spacing that covers the same square.
  - [x] `bakeStoresEachHeightWithinHalfAFloatGap` — over the 129 × 129 grid, a stored Float
    differs from the Double height by at most 0.0000305 m, half the float gap at 600 m.
- **Observable completion criteria:** the suite passes. Nothing changes in the app yet.
- **Edge cases and expected results:**
  - Negative sample indices → positions left of or behind the origin; no special case.
  - An even `samplesPerSide` → the grid has no centre sample. Use an odd count (129).
  - Narrowing to Float → at most half a float gap: 0.03 mm for heights up to 600 m.
  - `samplesPerSide` 0 → an empty array. A negative `samplesPerSide` → the program stops at
    the range `0..<samplesPerSide`. The function has no check of its own.

### Milestone 3 — Drawing the baked samples with the existing terrain ✅ (landed 2026-11-25, a889b83)

- **Learning objective:** how a grid of numbers on the CPU becomes the height of GPU vertices:
  the texture upload, the mapping from a vertex to its sample, and bilinear interpolation
  written out by hand.
- **Prerequisites:** Milestones 1 and 2. Read `Tessellation.metal` and `TerrainObject.swift`
  first; this milestone changes both.
- **Engine integration points:** `TFSCommon.h`, `Tessellation.metal`, `TerrainObject.swift`,
  `FlightboxWithTerrain.swift`, one new app-hosted test file.
- **Names in the code.** As in Milestones 1 and 2, the code drops the unit suffix. Where the
  pseudocode says `sampleSpacing_m`, `sideLength_m`, `parameters` and `heightAmplitude_m`, the
  code says `sampleSpacing`, `sideLength`, `params` and `heightAmplitude`. `sampleSpacing` is a
  `let` of type `Double?`: it is nil for the image source, which has no grid of samples in
  meters. Optional and not a default number, so that code that needs the spacing must first
  deal with a terrain that has none. `makeProceduralTerrain(params:sideLength:)` is a static
  function that returns a `TerrainObject`, not a convenience initializer. The designated
  initializer is `init(terrain:heightTexture:heightSource:sampleSpacing:heightSamples:)`; its
  last two parameters default to nil. The scene's terrain property is `ground`, a
  `TerrainObject!`.
- **Algorithm:** in five parts, A to E, below. Parts A to C change the code that both height
  sources share, so after part C the old terrain should look as it did (slightly smoother).
  Check that before doing part D.

**Part A — the `Terrain` struct** (`TFSCommon.h`, the struct marked "Temporary" at the end).
Delete the field `height`. Add five `float` fields:

| Field | Meaning | Image source | Procedural source |
|---|---|---|---|
| `heightScale` | local height = `heightOffset` + texel × `heightScale` | 2 × height | 1 |
| `heightOffset` | see above | −height | 0 |
| `grassBelowHeight` | local height below which grass is drawn | −0.5 | −50 |
| `snowAboveHeight` | local height at and above which snow is drawn | 0.3 | 200 |
| `colorTextureRepeatCount` | repeats of the colour textures across the terrain | 1 | 128 |

The image values reproduce today's behaviour exactly: −height + r × 2 × height is the old
(r × 2 − 1) × height. The two thresholds are the old shader's literals. It compared them with
the decoded height whatever `height` was, so they are not multiplied by `height` (an earlier
version of this table said "× height", which agrees only when `height` is 1). With these
values, 76.7 % of the texels of `mountain.png` are grass, 19.2 % rock and 4.1 % snow. With the
procedural values and seed 2026, a survey of a 102 km square puts 39.9 % of the ground in
grass, 47.5 % in rock and 12.5 % in snow.

**Part B — the shader** (`Tessellation.metal`).

In `tessellation_vertex`, the lines from `float2 xy = ...` to `position.y = height;` currently
sample the image with a default sampler (nearest texel, no filtering) and decode it as
`(color.r * 2 - 1) * terrain.height`. Replace the sampling and the decode with the two helpers
below; keep `xy`, because the fragment functions still use it as the texture coordinate. Put the
helpers above `compute_tessellation`, next to `SampleTerrainLayer`.

Line by line: `float2 xy = …` stays. It is the variable the pseudocode below calls
`positionAcrossTerrain`; keep the name `xy` or rename it, but declare it once. Three lines are
deleted: `constexpr sampler sample;`, `float4 color = heightMap.sample(sample, xy);` and
`float height = (color.r * 2 - 1) * terrain.height;`. `position.y = height;` becomes the last
line of the pseudocode, `position.y = localHeight;`.

*Metal types used in this part.* The pseudocode in part B gives every variable, parameter and
return value its type in the Metal Shading Language (MSL). The type is written after the name,
`name: type`, as Swift writes it. In the file the type comes first, as in C:
`uint lastColumn = …;`. Conversions and texture calls are spelled the way Metal spells them, so
this part is closer to source than the rest of the plan. That is on purpose: the names of the
types and calls are what cannot be guessed.

| Metal type | What it holds | Swift type on the CPU side |
|---|---|---|
| `float` | one 32-bit floating-point number | `Float` |
| `uint` | one unsigned 32-bit whole number; it cannot be negative | `UInt32` |
| `float2`, `float3`, `float4` | 2, 3 or 4 floats. The components are `.x .y .z .w`; `.r .g .b .a` are other names for the same four | `SIMD2<Float>`, `SIMD3<Float>`, `SIMD4<Float>` |
| `uint2` | two `uint`s. Here: the (column, row) of a texel | `SIMD2<UInt32>` |
| `texture2d<float>` | a handle to a 2-D texture. `<float>` says how a texel arrives in the shader, not how it is stored: an `r8Unorm` texel (the image) arrives as 0 … 1, an `r32Float` texel (the bake) arrives as the stored number | `MTLTexture` |
| `sampler` | the filtering and addressing rules that `sample` uses | `MTLSamplerState` |
| `Terrain` | the struct from `TFSCommon.h`. In a shader its `size` is a `float2`, `maxTessellation` is a `uint`, and the five fields of part A are `float` | `Terrain` (the same struct, imported from the header) |

Seven places where Metal's rules differ from Swift's. Each was checked with the Metal compiler,
and the quoted text is the compiler's error message. The comments in the pseudocode refer to
these rules by number.

1. *One number converts to another kind of number by itself.* `float fraction = someUint;`
   compiles. Swift never allows that. The pseudocode writes every conversion anyway, as Swift
   would, so that none is hidden. A conversion looks like a Swift initializer with a lower-case
   name: `float(lowerColumn)`, `uint(someFloat)`, `float2(a, b)`. `uint(someFloat)` drops the
   fraction: `uint(2.9)` is 2. Unlike Swift's `UInt32(…)` it does not stop the program when the
   float is negative, and the result is then not a value to rely on. So clamp first and convert
   afterwards.
2. *A vector does not convert to another kind of vector by itself.* `float2 * uint2` is an
   error: "implicit conversions between vector types … are not permitted". Build a `float2`
   first.
3. *One number does turn into a vector by itself, by filling every component.*
   `float4(localHeight)` is (h, h, h, h). This rule hides a trap:
   `heightMap.read(lowerColumn, lowerRow)` compiles. The function is
   `read(uint2 coord, uint lod = 0)`, where `lod` is the mip level (a mip level is one of the
   smaller copies of a texture; level 0 is the full-size one). Given two numbers, it takes the
   first as both column and row and the second as the mip level: "texel
   (lowerColumn, lowerColumn) of mip level lowerRow". Always pass one `uint2`:
   `heightMap.read(uint2(lowerColumn, lowerRow))`.
4. *`min`, `max`, `clamp` and `mix` do not accept a float next to a whole number, or an `int`
   next to a `uint`.* `min(floor(x), lastColumn - 1)` has a `float` and a `uint`: "call to 'min'
   is ambiguous". An `int` with a `uint` fails the same way, and a `uint2` bound given to a
   `clamp` of a `float2` is "no matching function for call to 'clamp'". One `float` next to
   `float2`s is fine: `tessellation_vertex` already calls `mix(float2, float2, float)`, which
   blends both components by the same amount.
5. *`read` and `sample` on a `texture2d<float>` always return a `float4`,* even when the texture
   stores one number per texel. An `r32Float` texel arrives as (stored number, 0, 0, 1). Take
   `.r`. Putting the `float4` into a `float` is an error.
6. *Texel positions and texture sizes are `uint`, not `int`.* `get_width()` and `get_height()`
   return `uint`, and `read` refuses an `int2` ("no matching member function for call to
   'read'"). `int lastColumn = heightMap.get_width() - 1;` does compile, by rule 1, but an `int`
   next to a `uint` then fails at `min` (rule 4). With `uint` for every index no conversion is
   needed between `get_width()`, `min` and `read`. A `uint` wraps around below zero and the
   program carries on: `uint(0) - 1` is 4,294,967,295.
7. *A helper function takes a struct by value:* `Terrain terrain`, the way `getCameraDistance`
   in the same file takes `float4x4 modelMatrix`. The entry point's own argument stays
   `constant Terrain &terrain [[ buffer(TFSBufferIndexTerrain) ]]`, and passing it on copies the
   struct. `constant` is an address space: it says the data lives in read-only buffer memory. A
   plain C++ `const Terrain &` parameter does not compile, because a reference without an
   address space cannot point into that memory. `constant Terrain &` as a helper parameter does
   compile; by value is simpler.

```pseudocode
// Reads the height texture at a position between samples. sampleCoordinate is measured in
// samples: (2.0, 7.0) is exactly the texel in column 2, row 7; (2.5, 7.0) is halfway to column 3.
// Uses exact texel reads (read, not sample), so it works for a 32-bit float texture on every GPU.
function readHeightBetweenSamples(heightMap: texture2d<float>, sampleCoordinate: float2) -> float
    lastColumn: uint = heightMap.get_width() - 1            // 128 for the bake; get_width() returns a uint
    lastRow: uint = heightMap.get_height() - 1
    // the same two numbers as floats: clamp refuses a uint2 bound next to a float2 (rules 2 and 4)
    lastSampleCoordinate: float2 = float2(lastColumn, lastRow)
    // keep the position on the grid, so a caller may ask one sample past the edge. This happens
    // while the value is still a float: a coordinate below 0 must become 0 before it becomes a
    // uint (rule 1)
    clampedCoordinate: float2 = clamp(sampleCoordinate, float2(0, 0), lastSampleCoordinate)
    // the lower-index corner of the cell; never the last column or row, so "+ 1" stays inside.
    // floor returns a float, uint(…) converts it, and min then compares two uints (rule 4)
    lowerColumn: uint = min(uint(floor(clampedCoordinate.x)), lastColumn - 1)
    lowerRow: uint = min(uint(floor(clampedCoordinate.y)), lastRow - 1)
    fractionAlongColumns: float = clampedCoordinate.x - float(lowerColumn)        // 0 … 1
    fractionAlongRows: float = clampedCoordinate.y - float(lowerRow)
    // read takes one uint2 (column, row) and returns a float4; .r is the texel's value (rules 3 and 5)
    valueAtLowColumnLowRow: float   = heightMap.read(uint2(lowerColumn,     lowerRow    )).r
    valueAtHighColumnLowRow: float  = heightMap.read(uint2(lowerColumn + 1, lowerRow    )).r
    valueAtLowColumnHighRow: float  = heightMap.read(uint2(lowerColumn,     lowerRow + 1)).r
    valueAtHighColumnHighRow: float = heightMap.read(uint2(lowerColumn + 1, lowerRow + 1)).r
    // mix(a, b, t) is a + (b - a) * t; all three arguments are float here
    alongLowRow: float  = mix(valueAtLowColumnLowRow,  valueAtHighColumnLowRow,  fractionAlongColumns)
    alongHighRow: float = mix(valueAtLowColumnHighRow, valueAtHighColumnHighRow, fractionAlongColumns)
    return mix(alongLowRow, alongHighRow, fractionAlongRows)

// The terrain's height in local units at a position on the sample grid.
// terrain is taken by value (rule 7).
function decodedLocalHeight(heightMap: texture2d<float>, sampleCoordinate: float2, terrain: Terrain) -> float
    texelValue: float = readHeightBetweenSamples(heightMap, sampleCoordinate)
    return terrain.heightOffset + texelValue * terrain.heightScale          // float + float * float

// Inside tessellation_vertex, after `position` (a float4) holds the interpolated local x and z.
// heightMap and terrain are the function's existing arguments.
    // position.xz is a float2 made of the x and z components; terrain.size is a float2.
    // The result runs 0 … 1 across the terrain; this is today's `xy`
    positionAcrossTerrain: float2 = (position.xz + terrain.size / 2.0) / terrain.size
    // N samples span N - 1 cells, so the far edge of the terrain is sample N - 1, not N.
    // Built as a float2 so that it can multiply a float2 (rule 2)
    lastSampleCoordinate: float2 = float2(heightMap.get_width() - 1, heightMap.get_height() - 1)
    // float2 * float2 multiplies component by component; 0 … 128 for the bake
    sampleCoordinate: float2 = positionAcrossTerrain * lastSampleCoordinate
    localHeight: float = decodedLocalHeight(heightMap, sampleCoordinate, terrain)
    position.y = localHeight
```

Small example of the mapping and the blend: the terrain is 12,800 m wide with 129 samples. A
vertex at local x = −6,150 m is 250 m from the left edge: 250 / 12800 = 0.01953125 across, times
128 = sample coordinate 2.5, halfway between columns 2 and 3. If the four texels around
(2.5, 7.25) are 10 and 20 in row 7 and 30 and 60 in row 8, the blend along the columns gives 15
and 45, and the blend along the rows gives 15 + (45 − 15) × 0.25 = 22.5.

The output struct is `TessellationVertexOut`: `position` and `color` are `float4`, `height` is
`float`, `uv` is `float2` and `worldPosition` is `float3`. The local variables `height` and
`color` that two of its fields were filled from no longer exist, so:

- `.height` receives `localHeight` (`float`).
- `.uv` receives `positionAcrossTerrain` (`float2`).
- `.color` receives `float4(localHeight)`: the height copied into all four components (rule 3).
  No fragment function reads `.color`; the line only has to compile.

`SampleTerrainLayer` and its two callers (`tessellation_fragment` and
`tessellation_gbuffer_fragment`):

```pseudocode
// Picks the ground texture by height. Thresholds come from the Terrain struct, in the same
// local units as the height the vertex function wrote.
// `terrain: Terrain` (by value, rule 7) takes the place of today's third parameter, `float tiling`.
function SampleTerrainLayer(localHeight: float, textureCoordinate: float2, terrain: Terrain,
                            grass: texture2d<float>, cliff: texture2d<float>, snow: texture2d<float>,
                            repeatingSampler: sampler) -> float4
    // float2 * float multiplies each component by the float
    repeatedCoordinate: float2 = textureCoordinate * terrain.colorTextureRepeatCount
    if localHeight < terrain.grassBelowHeight                                // float < float
        return grass.sample(repeatingSampler, repeatedCoordinate)            // float4: red, green, blue, alpha
    if localHeight < terrain.snowAboveHeight
        return cliff.sample(repeatingSampler, repeatedCoordinate)
    return snow.sample(repeatingSampler, repeatedCoordinate)
```

- Both fragment functions gain one argument: the `Terrain` struct at buffer index
  `TFSBufferIndexTerrain`, the same index the vertex function uses. Its declaration is the
  vertex function's line, word for word:
  `constant Terrain &terrain [[ buffer(TFSBufferIndexTerrain) ]]`. `&` makes it a reference to
  the bytes bound at that index (rule 7 explains `constant`). Metal matches an argument to its
  binding by the `[[ … ]]` attribute, so its place in the argument list does not matter.
- Both pass `in.height` (`float`), `in.uv` (`float2`), `terrain`, the three textures and the
  sampler to `SampleTerrainLayer`, and receive a `float4` as today.
- Both declare the sampler they pass with linear filtering, linear mip filtering and *repeat*
  addressing. A sampler declared inside a shader has the type `sampler` and is written
  `constexpr sampler repeatingSampler(filter::linear, mip_filter::linear, address::repeat);`.
  `constexpr` means "fixed when the shader is compiled": the sampler is part of the shader, and
  no `MTLSamplerState` is bound from Swift. `filter::linear` sets the filter for both shrinking
  and enlarging. `Skybox.metal` declares its `linearSampler` the same way. This line replaces
  `constexpr sampler sample;`. The default sampler they declare today clamps to the edge, which
  would smear the last texel over every repeat after the first. In
  `tessellation_gbuffer_fragment` the line `normalTexture.sample(sample, in.uv)` uses the old
  sampler's name; give it the new name. Delete the two `float tiling = 1.0;` lines; the struct
  field replaces them. The engine's shared linear sampler cannot be used here: it clamps too.

**Part C — `TerrainObject.swift`.**

- Above the class, add an enum `TerrainHeightSource` with two cases: `heightMapImage` and
  `procedural` (carrying a `ProceduralTerrainParameters`).
- Next to `patches`, add two static constants and build the others from them:
  `patchesPerSide` = 32 and `cellsPerPatchEdgeAtLowestTessellation` = 4. `patches` returns
  (`patchesPerSide`, `patchesPerSide`). `proceduralSamplesPerSide` = 32 × 4 + 1 = 129. The 4 is
  the floor in `compute_tessellation` (`max(4.0, …)`); a comment should say that the two must
  change together.
- `heightMap` changes from `let` to `private(set) var`, because Milestone 4 replaces it.
- New stored properties: `heightSource`, and for the procedural source `sampleSpacing_m`
  (an optional Double: the image source has none), `centerSampleIndexX` and `centerSampleIndexZ` (Int, both 0 at first) and
  `heightSamples` (the baked array, kept for Milestone 4's optimized version and for a later CPU
  height query).
- `init(terrain:)` currently looks up `Assets.Textures[.MountainHeightMap]` in its `guard`. Take
  that lookup out: the designated initializer receives the height texture and the height source
  as parameters. The existing `convenience init(size:height:)` passes the image texture and
  fills the five new struct fields from the "Image source" column of the table in part A.
- Add a way to build the procedural source: in the code, the static function
  `makeProceduralTerrain`. It takes the parameters and the side length in meters, and does
  this:

```pseudocode
function makeProceduralTerrain(parameters, sideLength_m) -> TerrainObject
    samplesPerSide = TerrainObject.proceduralSamplesPerSide                  // 129
    sampleSpacing_m = sideLength_m / (samplesPerSide - 1)                     // 12,800 / 128 = 100
    firstSampleIndex = 0 - (samplesPerSide - 1) / 2                          // centred on sample (0, 0): -64
    heightSamples = ProceduralTerrain.bakeHeightSamples(firstSampleIndex, firstSampleIndex,
                                                        samplesPerSide, sampleSpacing_m, parameters)
    heightTexture = makeHeightTexture(heightSamples, samplesPerSide)
    terrain = Terrain(size: (sideLength_m, sideLength_m),
                      heightScale: 1, heightOffset: 0,                       // the texture already holds meters
                      grassBelowHeight: -50, snowAboveHeight: 200,
                      colorTextureRepeatCount: 128,
                      maxTessellation: as today)
    return TerrainObject(terrain, heightTexture, heightSource: procedural(parameters))
           with sampleSpacing_m, heightSamples and the centre (0, 0) stored

// One texel per sample, 32-bit float, single channel. Static, so a test can call it.
function makeHeightTexture(heightSamples, samplesPerSide) -> texture
    // replace (below) reads samplesPerSide * samplesPerSide Floats and does not check the
    // array's length, so a shorter array would be read past its end
    stop the program unless count(heightSamples) == samplesPerSide * samplesPerSide
    descriptor = 2-D texture, pixel format r32Float, width and height samplesPerSide,
                 one mip level, usage shaderRead
    engine: texture = Engine.Device.makeTexture(descriptor)
    // rows are written in the order they are stored: row 0 of the array becomes row 0 of the texture
    engine: texture.replace(whole region, mip level 0, bytes of heightSamples,
                            bytesPerRow: samplesPerSide * 4)                  // 4 bytes per Float
    texture.label = "Procedural Terrain Height Map"
    return texture
```

  `TextureLoader.MakeSolid2DTexture` is an existing example of the same two calls.
- In `setRenderState`, next to the existing `setVertexBytes(&terrain, …)` line, add the same
  bytes for the fragment stage (`setFragmentBytes`, same length, same index). Without it the
  fragment function's new `Terrain` argument has nothing bound.

**Part D — `FlightboxWithTerrain.swift`.**

- Add a stored property that chooses the source, for example
  `terrainHeightSource = procedural(default parameters)`, and a stored optional property for the
  terrain object (Milestone 4 needs it; `ground` is a local variable today).
- `addTerrain()` branches on the source. The `heightMapImage` branch is today's code, unchanged
  (size [8, 8], `rotateX(−20°)`, `setScale(100)`). The `procedural` branch creates the terrain
  with side length 12,800 m and adds it, with **no** scale and **no** rotation. Both would break
  it: the scale would multiply the heights by 100, and a tilted terrain's height is no longer a
  function of world x and z.
- In `buildScene()`, for the procedural source, start the jet above every possible height:
  `jet.setPosition(0, heightAmplitude_m + 200, 0)`, which is 800 m. The ground at the origin is at
  −173 m, so the jet starts 973 m above it. The other objects of the scene are placed relative to
  `jetPos` and follow by themselves.
- For the procedural source, set `jet.kinematicFloorHeightInOriginalFrame` to
  `−heightAmplitude_m` (−600) instead of 0. The floor is flat; it only stops a dive from going on
  forever. With hills, a floor at 0 would stop the jet in mid-air above every valley.

**Part E — one app-hosted test.** `makeHeightTexture` is the only new code that needs a Metal
device. The header comment of `AfterburnerEmitterTests.swift` describes the pattern: the test
touches `Engine.Device` but not `Engine.renderer`, so the host-app launch race does not apply.

- **Tests:**
  - [x] `TerrainHeightTextureTests.textureHoldsTheSamplesInRowOrder` (app-hosted) — bake a 9 × 9
    grid, make the texture, read it back with `getBytes`, and compare with the array using `==`.
    Also check the pixel format (`r32Float`), the size (9 × 9) and the mip level count (1).
    This catches a wrong `bytesPerRow` and a flipped row order. The test first requires the
    first and the last row of the bake to differ, because otherwise it could not notice rows
    in the wrong order.
  - [x] All suites of Milestones 1 and 2 still pass.

  Four more tests were added with the code (review of 2026-11-25), all app-hosted, in the same
  file:
  - [x] `texelAtColumnAndRowIsTheMatchingElement` — a 9 × 9 texture whose element in row `row`
    and column `column` is 1000 × row + column. Six single texels are read back at
    (column, row), the way the shader's `read(uint2(column, row))` addresses them: texel (2, 7)
    is 7002 and texel (7, 2) is 2007.
  - [x] `samplesPerSideMatchesThePatchGrid` — `proceduralSamplesPerSide` is 129, equals
    `patchesPerSide` × `cellsPerPatchEdgeAtLowestTessellation` + 1, and is odd.
  - [x] `proceduralTerrainIsABakeCentredOnTheOrigin` — `makeProceduralTerrain` with a side of
    12,800 m: the spacing is 100, the centre is sample (0, 0), the source is procedural; three
    of Milestone 2's heights are at their places within 1e-3 m (−328.78198 first, −172.99075
    in the middle, 533.9311 in column 96 of row 128); the texture is `r32Float`, 129 × 129, and
    reads back equal (`==`) to `heightSamples`; the struct has size (12800, 12800), scale 1
    and offset 0.
  - [x] `imageSourceKeepsTheOldHeightDecode` — `TerrainObject(size: [8, 8], height: 3)`: for
    the texel values 0, 0.25, 0.5, 0.65 and 1, `heightOffset` + r × `heightScale` equals
    (r × 2 − 1) × 3 within 1e-5; the thresholds are −0.5 and 0.3; the repeat count is 1;
    `sampleSpacing` is nil and `heightSamples` is empty. A height of 3 is used because with 1
    a missing or a wrong "× height" would still pass.
- **Observable completion criteria:**
  - After parts A to C, with the source set to `heightMapImage`: the old tilted terrain looks as
    before, with smoother slopes (the heights are now interpolated between texels).
  - After part D, with `Preferences.StartingSceneType = .FlightboxWithTerrain` and the
    TiledMSAATessellated renderer: a 12.8 km square of hills below the jet. Low ground is grass,
    the middle band is rock, the tops are snow. In this first grid the lowest point is −329 m and
    the highest is +534 m, a hill about 7 km from the start. Every launch shows the same hills.
    Changing the seed gives different ones.
  - Expected and not a bug: the slopes are not shaded (the normal is still a constant; Milestone
    5), the square's edge is visible, the jet can fly through a hill, and flying 6.4 km in any
    direction leaves the terrain behind (Milestone 4).
  - Checked by screenshot on 2026-11-25, with the jet at its start position: the procedural
    source shows hills with grass low, rock in the middle and one snow top, and the edge of
    the square; the image source shows the tilted square, grass with one mountain of rock and
    snow. The image terrain was judged on its own, not against a build of the commit before.
- **Edge cases and expected results:**
  - A vertex exactly on a sample (every vertex at tessellation factor 4) → both fractions are 0,
    and the vertex gets that sample's value exactly.
  - A vertex between samples → the partition mode is `pow2`, so factors are 4, 8, 16, 32 or 64
    and vertices sit at whole, half, quarter, eighth or sixteenth sample positions. Factors above
    4 occur only within 16 m of the terrain's base plane. Those vertices get the bilinear blend.
  - A vertex on the far edge → sample coordinate 128; the lower corner is clamped to 127 and the
    fraction is 1, so the last texel is returned and no read goes outside the texture.
  - A sample coordinate below 0 (Milestone 5 asks for one sample before the edge) → the clamp
    makes it 0 while it is still a `float`, and the edge texel is returned. Converting to `uint`
    before clamping would convert a negative number, which has no dependable result.
  - A height texture only one texel wide or tall → `lastColumn - 1` wraps around to
    4,294,967,295 (a `uint` has no −1), `min` then limits nothing, and the "+ 1" read leaves the
    texture. Not handled: the bake is 129 × 129 and `mountain.png` is 512 × 512.
  - A device that cannot filter 32-bit float textures → no effect; the shader never filters.
  - A `heightSamples` array that does not hold `samplesPerSide` × `samplesPerSide` values →
    the `precondition` in `makeHeightTexture` stops the program, in Debug and in Release
    builds. No test exercises it: a failed `precondition` ends the test process.
  - A side length other than 12,800 m → the sample spacing is side length / 128, no longer
    100 m. The default parameters are chosen for 100 m (design decision "the narrowest
    octave's cells must be at least 4 samples wide"). With 128,000 m the spacing is 1,000 m,
    the narrowest cells are 0.4 samples wide, and the drawn surface misses the height
    function by up to 247 m. No test covers the side length the scene passes: a scene builds
    itself when it is created (`GameScene.init` calls `buildScene`), so a test that made one
    would register a second scene's objects with the `SceneManager` of the running host app.

### Milestone 4 — The terrain follows the aircraft ✅ (landed 2026-11-25, 6bcc16c)

- **Learning objective:** how an endless world is made from a finite grid, why the grid must move
  in whole steps, and how absolute and relative coordinates meet at the floating origin.
- **Prerequisites:** Milestone 3, and the floating-origin section of CLAUDE.md.
- **Engine integration points:** two more static functions in `ProceduralTerrain`; one method on
  `TerrainObject`; one call in `FlightboxWithTerrain.doUpdate()`; one flag in `Preferences.swift`.
- **Names in the code.** As in Milestones 1 to 3, the code drops the unit suffix. Where the
  pseudocode says `sampleSpacing_m`, `parameters` and `focusPositionInOriginalFrame_m`, the code
  says `sampleSpacing`, `params` and `focusPositionInOriginalFrame`.
  `recenteredCenterSampleIndex` returns an `Int?`, nil for "nothing". Its `snapStepInSamples`
  is an `Int`, because a centre is a sample index and a step with a fraction could not land on
  one; the function converts it to Double for the one division. `recenterThresholdInSamples`
  is a `Double`, and `follow` converts its `Int` constant in the call. The check for a focus
  that is not a usable position is
  `guard abs(focusInSamples) <= maxFocusDistanceFromOriginInSamples else { return nil }`. The
  limit is a static constant at the top of `ProceduralTerrain`, a `Double` written `0x1p53`
  (a hexadecimal floating-point literal: 1 × 2^53). `roundToNearestWholeNumber` is `.rounded(.toNearestOrEven)`. `round()` sends a tie
  away from zero and fails `recentreSnapsToTheNearestPatch`. `storedPositionOfTerrainCenter`
  takes the two centre indices as `Int` and converts them to Double for the multiply;
  `narrowToFloat3` is `toFloat3()`. (Until 2026-11-26 the step and the two centre indices were
  passed as `Double`; see the changelog.) `follow` checks the source with a `switch` over `heightSource`, whose
  `procedural` case also hands over `params`, and unwraps `sampleSpacing` with `if let` inside
  that case. The bake alone is timed, with `timeit` (`Utils/TimeIt.swift`, nanoseconds). In the
  scene the terrain is `ground`.
- **Algorithm:**

```pseudocode
// Decides, for one axis, whether the terrain must be recentred. Returns the new centre sample
// index, or nothing when the focus is still close enough. Pure: no engine state.
// Shaped like FloatingOrigin.getOffset, which also returns nothing when no shift is due.
function recenteredCenterSampleIndex(currentCenterSampleIndex, focusPositionInOriginalFrame_m,
                                     sampleSpacing_m, snapStepInSamples,
                                     recenterThresholdInSamples) -> whole number, or nothing
    focusInSamples = focusPositionInOriginalFrame_m / sampleSpacing_m           // Double
    // Not a usable position: NaN, infinite, or more than 2^53 samples from sample 0 (beyond
    // 2^53 a Double cannot tell one sample from the next). The threshold check below would
    // not stop any of the three. One comparison covers them: a comparison with NaN is false.
    if not (absoluteValue(focusInSamples) <= maxFocusDistanceFromOriginInSamples)   // 2^53
        return nothing                                      // nothing to centre on: the terrain stays
    if absoluteValue(focusInSamples - currentCenterSampleIndex) <= recenterThresholdInSamples
        return nothing
    // the nearest multiple of the snap step; a tie goes to the even multiple
    nearestStep = roundToNearestWholeNumber(focusInSamples / snapStepInSamples)
    return nearestStep * snapStepInSamples

// Where the terrain node must be stored so that its centre sits on the given sample.
// The centre is known in the original frame; a stored position is in the current frame.
function storedPositionOfTerrainCenter(centerSampleIndexX, centerSampleIndexZ, sampleSpacing_m,
                                       floatingOriginOffset) -> float3
    // Double arithmetic on whole meters: exact
    centerInOriginalFrame_m = (centerSampleIndexX * sampleSpacing_m, 0, centerSampleIndexZ * sampleSpacing_m)
    return narrowToFloat3(centerInOriginalFrame_m - floatingOriginOffset)
```

```pseudocode
// TerrainObject method. Update thread only. Does nothing for the image source.
function follow(focusPositionInOriginalFrame, floatingOriginOffset)
    if heightSource is not procedural
        return
    // The `procedural` case carries the ProceduralTerrainParameters the terrain was built with.
    // In the code the check and this line are one step: `case .procedural(params: let params)`.
    parameters = the value carried by the `procedural` case of heightSource
    // In the code `sampleSpacing` is a Double? (nil for the image source). Unwrap it in the
    // same guard that checks the source.
    snapStepInSamples = TerrainObject.cellsPerPatchEdgeAtLowestTessellation     // 4 samples = one patch
    recenterThresholdInSamples = snapStepInSamples                              // 4 samples = 400 m
    newCenterX = recenteredCenterSampleIndex(centerSampleIndexX, focusPositionInOriginalFrame.x,
                                             sampleSpacing_m, snapStepInSamples, recenterThresholdInSamples)
    newCenterZ = recenteredCenterSampleIndex(centerSampleIndexZ, focusPositionInOriginalFrame.z,
                                             sampleSpacing_m, snapStepInSamples, recenterThresholdInSamples)
    if newCenterX is nothing and newCenterZ is nothing
        return                                             // the usual case: one division and one compare per axis
    centerSampleIndexX = newCenterX, or the old value if nothing
    centerSampleIndexZ = newCenterZ, or the old value if nothing
    // the same constant makeProceduralTerrain reads: the bake and the texture keep their size
    samplesPerSide = TerrainObject.proceduralSamplesPerSide // 129
    halfSideInSamples = (samplesPerSide - 1) / 2            // 64
    heightSamples = ProceduralTerrain.bakeHeightSamples(centerSampleIndexX - halfSideInSamples,
                                                        centerSampleIndexZ - halfSideInSamples,
                                                        samplesPerSide, sampleSpacing_m, parameters)
    // a NEW texture: frames already encoded keep the old one until they finish
    heightMap = makeHeightTexture(heightSamples, samplesPerSide)
    engine: setPosition(storedPositionOfTerrainCenter(centerSampleIndexX, centerSampleIndexZ,
                                                      sampleSpacing_m, floatingOriginOffset))
    engine: DebugLog("terrain recentred on sample (x, z), bake took … ms", DEBUG_PROCEDURAL_TERRAIN)
```

```pseudocode
// FlightboxWithTerrain.doUpdate(), after super.doUpdate(). The scene's doUpdate runs before
// its children update, so the terrain's new position is cached in this same tick.
    // read once, so the focus and the position follow stores are computed from the same value
    floatingOriginOffset = SceneManager.floatingOriginOffset
    // the jet is a direct child of the scene: its stored position and the offset total are
    // always shifted together, so their sum is the jet's position in the original frame
    focusPositionInOriginalFrame = toDouble3(jet.getPosition()) + floatingOriginOffset
    engine: ground.follow(focusPositionInOriginalFrame, floatingOriginOffset)
```

The jet moves later in the same tick, in its own `doUpdate`, so the focus is one tick old. That
is a few meters at most, against a threshold of 400 m.

Why the floating origin needs no change. When the origin shifts, `FloatingOrigin.applyOffset`
subtracts the offset from the terrain's stored position (it is a direct child of the scene) and
`SceneManager` adds the same offset to the total. The terrain's position in the original frame,
stored position + total, does not change. Neither does the focus's. The centre sample index stays
the same, so no bake happens and the texture stays valid.

Small example: the centre sample is (520, −172), which is (52,000, 0, −17,200) m in the original
frame. The offset total is (52,812, 432, −17,640). The stored position is the difference:
(−812, −432, 440). The stored y is −432 because the terrain's base is at height 0 in the original
frame and the origin has moved 432 m up.

Add `DEBUG_PROCEDURAL_TERRAIN` to `Core/Preferences.swift`, on the line after
`DEBUG_FLOATING_ORIGIN`. In the landing commit the flag is `true`, so the log line prints; every
other debug flag there is `false`.

- **Tests** (Metal-free, in `ProceduralTerrainTests`; spacing 100 m, snap step 4, threshold 4):
  - [x] `noRecentreAtExactlyTheThreshold` — centre 0: focus 0, 399, 400 and −400 m → nothing;
    centre 4 (at 400 m): focus 0 and 800 m → nothing, because the distance is measured from the
    centre and not from sample 0.
  - [x] `recentreJustPastTheThreshold` — centre 0, focus 400.5 m → 4; focus −400.5 m → −4.
  - [x] `recentreSnapsToTheNearestPatch` — centre 0: focus 600.5 m → 8, focus 1000.5 m → 12,
    focus 123,456 m → 1236, focus −123,456 m → −1236. Ties: centre 0, focus 600 m → 8;
    centre 4, focus 1000 m → 8; centre 12, focus 1800 m → 16; centre −4, focus −1000 m → −8.
    `round()` gives 12, 20 and −12 for the last three.
  - [x] `flyingStraightRecentresOncePerPatch` — move the focus from 0 to 2,000 m in 0.5 m steps
    and feed each result back in: exactly four recentres, at 400.5, 800.5, 1200.5 and 1600.5 m,
    to 4, 8, 12 and 16.
  - [x] `focusInOriginalFrameIsUnchangedByAFloatingOriginShift` — a plain `Node` stored at
    (812.375, 431.5, −640.25) with offset total (52000, 0, −17000). `FloatingOrigin.getOffset`
    returns the whole-meter offset (812, 432, −640) and `FloatingOrigin.applyOffset` applies
    it. The sum is (52812.375, 431.5, −17640.25) before and after, compared with `==`, and from
    centre (520, −172) the recentre rule answers (528, −176) both times.
  - [x] `storedPositionOfTerrainCenterSubtractsTheOffset` — the small example above, and centre
    (12, −4) with a zero offset → (1200, 0, −400).

  Four more Metal-free tests were added with the code (review of 2026-11-25):
  - [x] `flyingBackRecentresOncePerPatch` — from centre 16, the focus goes from 2,000 m back to
    0 m in 0.5 m steps: three recentres, at 1199.5, 799.5 and 399.5 m, to 12, 8 and 4. The
    flight ends on centre 4, not on centre 0 where the outward flight began: 0 m is exactly
    400 m from sample 4.
  - [x] `hoveringOnABoundaryRecentresOnce` — the focus alternates between 400.5 m and 399.5 m a
    hundred times: one recentre, to 4.
  - [x] `afterARecentreTheFocusIsWithinHalfAPatch` — the focus at every 12.5 m from −100 km to
    +100 km, from centres −8, 0, 4 and 12: 63,744 recentres; every new centre is a multiple of
    4; the focus is at most 2 samples from it; asked again from the new centre, the rule
    answers nothing every time.
  - [x] `storedPositionIsSubtractedInDouble` — centre sample 1,234,568 (123,456,800 m) with an
    offset of 123,456,789.25 m → 10.75. Narrowed to Float before the subtraction, the offset
    becomes 123,456,792 and the result is 8.
  - [x] `focusThatIsNotFiniteDoesNotRecentre` (added 2026-11-26 with the `guard`) — a focus of
    NaN, +infinity or −infinity → nothing, from centre 0 and from centre 520. Without the
    `guard` this test does not fail: it ends the test process.
  - [x] `maxFocusDistanceIsTheLastExactWholeNumber` (added 2026-11-26 with the constant) — the
    constant is 9,007,199,254,740,992 = 2^53; one less is a different Double; one more rounds
    back to the same Double; the gap to the next Double is 2.
  - [x] `focusBeyondTheMaxDistanceDoesNotRecentre` (added 2026-11-26 with the range check) — a
    focus of 10^21 m, 10^300 m, 3.4 × 10^38 m (the largest Float) or −10^30 m → nothing. A
    focus exactly 2^53 samples from sample 0 (2^53 × 100 m) → centre 2^53, and the same with a
    minus sign. The next Double after that position → nothing. With a guard that checks only
    for NaN and infinity, this test ends the test process.

  Five app-hosted tests of `follow` itself were added to `TerrainHeightTextureTests`. Each
  builds a `TerrainObject` and hands `follow` a focus and an offset; no scene is needed:
  - [x] `followDoesNothingWithinTheThreshold` — focus (400, 750, −400): the centre, the
    position, the samples and the texture object (`===`) are unchanged.
  - [x] `followRecentresAndBakesANewTexture` — focus (1000.5, 750, −450): centre (12, −4),
    stored position (1200, 0, −400), the samples equal the bake that starts at sample index
    (−52, −68), and the sample at the world's origin (−172.99075 m) has the same bits at
    column 52 of row 68 as it had in the middle of the old grid. The texture is a new object
    that holds the new samples, and the old texture still holds the old ones. A second call
    with the same focus keeps the same texture object.
  - [x] `followRecentresOnlyTheAxisPastTheThreshold` — focus (1000.5, 0, 399) → centre (12, 0);
    focus (−399, 0, −1000.5) → centre (0, −12).
  - [x] `followStoresThePositionInTheCurrentFrame` — focus (52010, 1200, −17190) with offset
    (52812, 432, −17640): centre (520, −172), stored position (−812, −432, 440), and the
    samples equal the bake around that centre, whatever the offset.
  - [x] `followDoesNothingForTheImageSource` — an image terrain 100 km from the focus keeps its
    texture object and its position.
- **Observable completion criteria:** fly in a straight line for a minute. There is ground below
  the whole time. With the debug flag on, the log shows one recentre per 400 m flown. Hills
  already on screen do not change shape when a recentre happens; only the far edge moves outward
  by one patch and the near edge moves in. Turn around and fly back: the same hills are in the
  same places. The floating origin's own log line (`DEBUG_FLOATING_ORIGIN`) appears about once
  per kilometer, and nothing visible happens to the terrain when it does.
  - Not checked by the review of 2026-11-25: the flight needs key presses, which cannot be sent
    to the app from the command line. The tests above check each step of a recentre, but not
    the scene's call or what is on screen.
- **Edge cases and expected results:**
  - Hovering on a boundary → no repeated bakes. After a recentre the focus is at most 200 m from
    the centre and the threshold is 400 m.
  - Flying out and back → the centre does not end where it started. After 2 km out and 2 km
    back the terrain is centred on sample 4, with the focus at sample 0. The ground is the same
    either way: heights belong to sample indices, not to the centre.
  - A threshold below half the snap step → not usable. With a threshold of 1 sample and a step
    of 4, a focus 1.5 samples from centre 0 is past the threshold, but the nearest multiple of
    4 is still 0: the rule answers 0 on every tick and `follow` bakes on every tick. With a
    threshold of exactly half a step (2), a focus that crosses the 200 m line a hundred times
    causes a hundred bakes.
  - A focus that is NaN or infinite → nothing, so the terrain stays where it is
    (`focusThatIsNotFiniteDoesNotRecentre`). The `guard` in `recenteredCenterSampleIndex` does
    this. Without it, NaN gets past the threshold check, because NaN compares false with
    everything, and the conversion to `Int` stops the program.
  - A finite focus more than 2^53 samples from sample 0 (9 × 10^17 m with 100 m spacing, about
    95 light-years) → nothing (`focusBeyondTheMaxDistanceDoesNotRecentre`). The same `guard`
    does this. No flight gets there, but a diverging position passes through huge finite
    values before it becomes infinity, and without the check a sample index too large for an
    `Int` stops the program (from about 9 × 10^20 m).
  - A snap step of 0 → the program stops: the division gives infinity. Not handled; the step
    is the constant 4.
  - A jump of many kilometers (a scene reset or a teleport) → one recentre directly to the
    nearest patch; the bake covers a completely new area.
  - A recentre and a floating-origin shift in the same tick → correct. `follow` runs first with
    the old offset; the shift then moves the terrain with everything else.
  - The aircraft is replaced or missing → the scene decides what the focus is. `follow` only
    needs a position.
  - The game is paused → no update tick runs, so nothing is baked.

### Milestone 5 (optional) — Normals from the same samples

- **Learning objective:** how a surface normal follows from the slope of a height function, and
  how to estimate the slope from neighbouring samples.
- **Prerequisites:** Milestone 3. Independent of Milestone 4.
- **Engine integration points:** `ShaderDefinitions.h` (`TessellationVertexOut` gains a
  `float3 worldNormal` field after `worldPosition`), `Tessellation.metal`.
- **Algorithm:**

Symbols: for a surface y = h(x, z), a step along X moves along the vector (1, ∂h/∂x, 0) and a
step along Z moves along (0, ∂h/∂z, 1). The normal is perpendicular to both. It is
(−∂h/∂x, 1, −∂h/∂z), scaled to length 1. ∂h/∂x maps to `slopeAlongX` and ∂h/∂z to `slopeAlongZ`.
A slope is estimated from the two neighbours on either side (a "central difference").

```pseudocode
// In tessellation_vertex, after the height. sampleCoordinate, heightMap and terrain are the ones
// already used for the height. readHeightBetweenSamples clamps, so asking one sample past the
// edge is safe.
    localSampleSpacingX = terrain.size.x / (heightMap.width - 1)
    localSampleSpacingZ = terrain.size.y / (heightMap.height - 1)
    heightTowardNegativeX = decodedLocalHeight(heightMap, sampleCoordinate + (-1,  0), terrain)
    heightTowardPositiveX = decodedLocalHeight(heightMap, sampleCoordinate + ( 1,  0), terrain)
    heightTowardNegativeZ = decodedLocalHeight(heightMap, sampleCoordinate + ( 0, -1), terrain)
    heightTowardPositiveZ = decodedLocalHeight(heightMap, sampleCoordinate + ( 0,  1), terrain)
    // rise over run, across two sample spacings
    slopeAlongX = (heightTowardPositiveX - heightTowardNegativeX) / (2 * localSampleSpacingX)
    slopeAlongZ = (heightTowardPositiveZ - heightTowardNegativeZ) / (2 * localSampleSpacingZ)
    localNormal = normalize((-slopeAlongX, 1, -slopeAlongZ))
    // the normal matrix carries the terrain's rotation and scale (the image terrain is tilted and scaled)
    out.worldNormal = normalize(modelConstants.normalMatrix * localNormal)
```

In `tessellation_gbuffer_fragment`, the constant `float4(0.0, 1.0, 0.0, …)` marked `// TODO`
becomes `normalize(in.worldNormal)` with the same fourth component. The `normalTexture` branch
below it stays.

Small example: spacing 100 m, heights 100 m toward −X and 130 m toward +X, 110 m toward −Z and
90 m toward +Z. `slopeAlongX` = 30 / 200 = 0.15 and `slopeAlongZ` = −20 / 200 = −0.10. The normal
is (−0.15, 1, 0.10) divided by its length 1.0161: (−0.1476, 0.9841, 0.0984). The ground rises
toward +X, so the normal leans toward −X.

- **Tests:** none can run without Metal; the check is visual, plus the small example above worked
  by hand. All earlier suites still pass, and the iOS build compiles.
- **Observable completion criteria:** the scene's sun is almost straight overhead: its direction
  is its position, (0, jet height + 100, 4), which is 0.25° from vertical when the jet starts at
  800 m. Under that sun a slope is only darker by the cosine of its angle: 3 % darker at the
  typical 13°, 26 % darker at the steepest 42°, the same on every side of a hill. So for this
  check, slant the sun: in `buildScene()` give `sun.setPosition` equal x and y (for example
  `(jetPos.y + 100, jetPos.y + 100, 4)`), which puts it 45° above the horizon toward +X. Then a
  13° slope facing the sun is at 85 % brightness and one facing away at 53 %; a 42° slope is at
  100 % and 5 %. Hills have a lit side and a dark side, and the shading stays attached to the
  ground when you fly around them. The image terrain is shaded too. Put the sun back afterwards,
  or keep it slanted. (These percentages are of the sun's direct term; the scene's ambient light
  adds a constant on top.)
- **Edge cases and expected results:**
  - A vertex on the terrain's edge → the neighbour outside is clamped to the edge sample, so the
    slope across the edge comes out at half its real value. Only the outermost row is affected.
  - Flat ground → slopes 0, normal (0, 1, 0), the old constant.
  - Cost → 16 more texel reads per vertex, for about 16,641 vertices.

## Simple version, then optimized version

- **Simple version:** Milestone 4 as written. Every recentre bakes all 16,641 samples on the
  update thread. It stays in the code as the reference.
- **Optimized version:** reuse the overlap. A one-patch move along one axis leaves 125 of 129
  columns unchanged, so only 516 samples (3.1 %) are new. The new array is filled by copying each
  sample that the old array already holds and baking only the rest:

```pseudocode
function bakeHeightSamplesReusingOverlap(oldHeightSamples, oldFirstSampleIndexX, oldFirstSampleIndexZ,
                                         newFirstSampleIndexX, newFirstSampleIndexZ,
                                         samplesPerSide, sampleSpacing_m, parameters) -> list of Float
    columnShift = newFirstSampleIndexX - oldFirstSampleIndexX
    rowShift = newFirstSampleIndexZ - oldFirstSampleIndexZ
    for each row in 0 ..< samplesPerSide
        for each column in 0 ..< samplesPerSide
            oldRow = row + rowShift                     // where this same world sample was in the old grid
            oldColumn = column + columnShift
            if oldRow and oldColumn are both inside 0 ..< samplesPerSide
                newSample = oldHeightSamples[oldRow * samplesPerSide + oldColumn]
            else
                newSample = narrowToFloat(heightInMeters((newFirstSampleIndexX + column) * sampleSpacing_m,
                                                         (newFirstSampleIndexZ + row) * sampleSpacing_m,
                                                         parameters))
            newHeightSamples[row * samplesPerSide + column] = newSample
    return newHeightSamples
```

- **Runtime switch:** a Bool on `TerrainObject`, `reusesOverlapOnRecenter`, false by default. The
  pattern is `useBroadPhase` in `PhysicsWorld`.
- **Comparison:** same seed, same flight path. Measure the bake time in the `DebugLog` line of
  `follow`. Measured with the scratch script on an Apple M1 Max, best of 20:

| Build | Full bake | Reusing the overlap, one-patch move |
|---|---|---|
| Unoptimized (`-Onone`, what a Debug build runs) | 15.7 ms | 2.3 ms |
| Optimized (`-O`, what a Release build runs) | 0.47 ms | 0.03 ms |

  A frame at 60 Hz is 16.7 ms. In a Debug build the simple version therefore uses almost a whole
  frame once per 400 m flown (every 1.6 s at 250 m/s), which can show as a small, regular hitch.
  In a Release build neither version is noticeable. Measured in the engine on 2026-11-25, from
  the `DebugLog` line of `follow` in a Debug build of the test host (Apple M1 Max, twelve
  recentres in three test runs): 17.4 to 19.4 ms per full bake, a little more than one frame. A test compares the two functions' outputs
  with `==` for moves of (4, 0), (4, 4), (−4, 8) and (200, 0) samples; the last has no overlap and
  bakes everything.
- **Fidelity note:** speed only. The two versions return identical arrays.

The larger optimizations (baking on a worker thread, level of detail, tile caches) change the
structure, not this function, and belong to the next terrain plan.

Things to try once it works, each a change to `heightInMeters` only: a different seed; amplitude
1,000 m; a 6,400 m base cell with 5 octaves (gentler: the survey's steepest slope drops from 42°
to 25°); raising the noise to a power to flatten valleys (Patel, "Redistribution").

## Pitfalls and how to detect them

| Symptom | Likely cause | How to check |
|---|---|---|
| Crash in the hash with "arithmetic overflow" | `*` or `+` instead of the wrapping `&*`, `&+` | `scrambleBitsMatchesReferenceValues` |
| A straight cliff or crease along x = 0 or z = 0 | Truncation toward zero instead of floor | `valueNoiseUsesFloorForNegativeCoordinates` |
| The world is different on every launch | Swift's `Hasher` or `hashValue` was used | `heightMatchesWorkedExample` |
| One huge peak or pit at the world's origin | All octaves share one seed | Compare the height at (0, 0) with −172.99 m |
| Terrain is a wall of spikes, 100 times too tall | `setScale(100)` kept on the procedural terrain | Part D: no scale, no rotation |
| Everything is one colour | Thresholds still in the image's units, or `Terrain` not bound to the fragment stage | Part A table; the `setFragmentBytes` line in `setRenderState` |
| The colour bands are straight-edged polygons about 1 km across | The side length is not 12,800 m, so the samples are not 100 m apart (`12_8000` is 128,000: Swift ignores where the underscore is) | Part D; `proceduralTerrain.sampleSpacing` should be 100 |
| The image terrain has no grass and half its old relief | The image source's decode is not scale 2 × height, offset −height | Part A table; `imageSourceKeepsTheOldHeightDecode` |
| Colour is correct in one strip and smeared elsewhere | The colour sampler still clamps to the edge | Part B: repeat addressing |
| Terrain looks sheared or mirrored | Rows and columns swapped, or a wrong `bytesPerRow` | `textureHoldsTheSamplesInRowOrder`, `bakeLayoutIsRowsAlongZColumnsAlongX` |
| Hills change shape slightly at every recentre | The snap step is not a whole number of patches, or sample positions are not computed from whole-number indices | `overlapOfTwoBakesIsBitEqual`; snap step 4 |
| The ground texture slides at every recentre | 400 m is not a whole number of texture repeats | `colorTextureRepeatCount` must be a multiple of 32 |
| The whole terrain jumps 400 m for one frame | The texture was overwritten in place, or `follow` runs after `TerrainObject.update()` | A new texture per bake; `follow` in the scene's `doUpdate` |
| The terrain jumps about 1 km for one tick after an origin shift | The focus was read from a camera parented to the aircraft | Use the aircraft's stored position plus the offset total |
| Terrain looks blocky near the camera and steps between texels | The old default sampler is still used for the height | Part B: `readHeightBetweenSamples` |
| Terrain is flat except for a strip along one edge | `heightMap.read(column, row)` was given two numbers, so the row was taken as the mip level (on an M1 Max a missing mip level read as 0) | Part B, rule 3: `read(uint2(column, row))` |
| A small regular hitch in Debug builds | The 15.7 ms bake | Build Release, or turn on `reusesOverlapOnRecenter` |
| Faint ridges running exactly along X and Z | Value noise. Its hills line up with the lattice | Expected. Gradient noise removes most of it; a later change to one function |
| Very rough ground that looks random at vertex scale | Too many octaves for the sample spacing | Narrowest cell ≥ 4 samples: 4 octaves at 100 m and a 3,200 m base cell |
| The square edge of the world is visible and moves in steps | No level of detail and no fog | Expected in this plan |

## References

Tags as in the research document: **[verified]** I extracted the text myself this session;
**[fetched]** retrieved and read in part; **[unverified]** from memory or a secondary source.

1. **Origin:**
   - Ken Perlin, "An Image Synthesizer", SIGGRAPH 1985 (doi 10.1145/325165.325247). Lattice noise
     and the sum of noise at several scales. Not fetched. The attribution of the nested hash to
     this paper is from Jarzynski and Olano, section 4.2 [verified]; the date and title are from
     Wikipedia [fetched].
   - Ken Perlin, "Improving Noise", SIGGRAPH 2002 — https://mrl.cs.nyu.edu/~perlin/paper445.pdf —
     two pages. Read section 2 (the cubic's second derivative) and the first paragraph of section
     3 (the fifth-degree replacement). The source of the fade curve. [verified]
   - Chris Wellons, "Prospecting for Hash Functions", 2018 —
     https://nullprogram.com/blog/2018/07/31/ and the README at
     https://github.com/skeeto/hash-prospector — the `lowbias32` function and its constants,
     released into the public domain. [verified]
   - Value noise has no single origin that I could establish. Wikipedia defines it as "a lattice
     of points which are assigned random values" with interpolation between them [fetched].
   - Terrain from fractional Brownian motion: Wikipedia's "Fractal landscape" credits Mandelbrot
     with first proposing it and cites F. K. Musgrave's 1993 dissertation, "Methods for Realistic
     Landscape Imaging", for its limits [fetched]. I did not read either.
2. **Detailed explanation:**
   - The research document, sections 1.2.8 and 1.2.9. It carries the verified quotations from
     Inigo Quilez's articles on fBm (https://iquilezles.org/articles/fbm/), which answer automated
     clients with an error; open them in a browser.
   - Amit Patel, "Making maps with noise functions" —
     https://www.redblobgames.com/maps/terrain-from-noise/ — read "Frequency", "Octaves"
     (including dividing by the sum of amplitudes), "Redistribution" and "To infinity and beyond"
     (why a function of position gives infinite terrain). Interactive. [fetched]
   - Mark Jarzynski and Marc Olano, "Hash Functions for GPU Rendering", JCGT vol. 9 no. 3, 2020 —
     https://jcgt.org/published/0009/03/02/ — section 4 on turning a one-number hash into a
     several-number hash. Why a good hash matters and how to judge one. [verified]
   - Scratchapixel, "Value Noise and Procedural Patterns" — linked from Wikipedia's value noise
     page as a lesson with C++ examples. The site refused my client, so its content is
     [unverified].
   - Apple, Metal Feature Set Tables — https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf
     — the `R32Float` row and footnote 6 on 32-bit float filtering. [verified]
3. **Reference implementation:**
   - FastNoiseLite, Jordan Peck, MIT — https://github.com/Auburn/FastNoiseLite — file
     `Cpp/FastNoiseLite.h`. Study `SingleValue` (two-dimensional value noise: floor, blend
     weights, four lattice values, three linear blends), `ValCoord` (hash to value) and
     `GenFractalFBm` (the octave loop, with `seed++` per octave). [verified]
   - Apple, "Rendering Terrain Dynamically with Argument Buffers" —
     `TerrainKnl_ComputeNormalsFromHeightmap` in `AAPLTerrainRenderer.metal`: normals from height
     differences, in a compute kernel. Verified in the research document, not re-read here.

Adaptations made for this engine: FastNoiseLite's value noise uses the cubic fade and a
multiply-by-primes hash; this plan uses Perlin's fifth-degree fade (because the surface is
displaced and shaded) and the nested `lowbias32` (because both have a published description).
The function runs in Double on the CPU in the scene's original frame, which no reference needs,
because none has a floating origin. Samples are addressed by whole-number index so that bakes
agree bit for bit. The grid size, snap step and threshold follow from the existing 32 × 32 patch
grid and its tessellation floor of 4. Normals are computed in the vertex function, not in a
compute kernel.
