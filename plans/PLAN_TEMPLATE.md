# <System or feature> — Implementation Plan

<!--
How to use this template
- Copy it to plans/<agent>/topic_name_YYYY-MM-DD.md and keep the section order.
- Replace every <angle-bracket> placeholder. Delete guidance comments like this one.
- Write in simple technical English. Define a term before using it. Explain the problem,
  then the idea, then the steps.
- The implementation goes in pseudocode (style section at the end of this file). Real Swift
  appears only when the request asks for it, or as a call-site example of a few lines that
  shows an existing engine API.
- Rules for all agents: AGENT_PROJECT_RULES.md at the repo root.
-->

**Started:** YYYY-MM-DD · **Agent:** claude | codex | gemini
**Design source:** `research/<agent>/<topic>_YYYY-MM-DD.md` (name the sections that carry the decisions)
**Status:** draft | in progress | complete
**Related plans:** <paths, or "none">

## How this document works

- The owner writes the code from the pseudocode. The agent implements a milestone only when asked.
- Milestones are edited in place to match the code. History goes in the Changelog, newest first,
  one line per entry.
- A milestone header gets `✅ (landed YYYY-MM-DD, <commit>)` when it lands. Checkboxes (`- [ ]`)
  track the items inside it.
- Review findings that change the plan are folded in; the changelog line names the review and
  says which numbers were re-checked with a scratch script.

## Changelog

- **YYYY-MM-DD** — Plan created from `<research doc>`.

## Goal and what you will learn

<One paragraph: what the system does when finished, and how you will see it in the app.>

Learning objectives:
- <Idea or technique the owner should understand after this plan.>

Not in scope:
- <Things deliberately left for later, with the plan or phase that owns them.>

## Terms

<!-- Define every term or acronym before the plan relies on it. One or two sentences each. -->

- **<Term>** — <definition in plain words>.

## The idea in plain words

**The problem.** <What must be computed, simulated, or rendered, and where the naive approach fails.>

**The idea.** <The insight that makes the solution work, in a few sentences. Name where it came from.>

**The steps.**
1. <Step in prose.>
2. <Step in prose.>

## Worked example

<!-- One small case traced by hand: concrete inputs, every intermediate value, the expected output.
     Reuse it as a test case in a milestone below. Reproduce the numbers with a scratch script. -->

Inputs: <values with units>
Step 1: <intermediate value>
Step 2: <intermediate value>
Result: <expected output>

## Data, units, and conventions

| Quantity | Symbol | Name in pseudocode and code | Unit | Frame | Sign or convention |
|---|---|---|---|---|---|
| <mass> | m | `mass` | kg | — | — |

Update order: <what is computed before what, and why the order matters>.
Engine conventions that apply: <left-handed, +Z forward, reverse-Z main depth, meters,
UpdateThread ownership of the scene graph and physics, and so on>.

## Engine integration points

<!-- Where this touches existing code: files, types, threads, registration paths, and the
     constraints from CLAUDE.md / AGENTS.md that apply. -->

- `<File.swift>` — <what changes there and why>.
- Thread: <UpdateThread / render thread / main thread> — <who owns the data and when it may be written>.

## Design decisions and where they came from

<!-- Mark each decision: [codebase] follows an existing engine pattern; [source: name] follows
     a reference; [design] is this plan's own choice. -->

- [source: <name>] <decision>.
- [codebase] <decision>.
- [design] <decision, the alternative rejected, and why>.

## Verification commands

```bash
# Build the app and the test bundle (the scheme's Build action builds the app only)
xcodebuild build-for-testing -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Run one suite, serial per project rule
xcodebuild test-without-building -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug -parallel-testing-enabled NO \
  -only-testing:"ToyFlightSimulatorTests/<SuiteName>" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Milestones

<!-- Each milestone is small enough to implement and check on its own. Repeat the block. -->

### Milestone 1 — <name>

- **Learning objective:** <what this milestone teaches>.
- **Prerequisites:** <milestones, terms, or reading needed first>.
- **Engine integration points:** <files and types touched>.
- **Algorithm:**

```pseudocode
function <descriptiveName>(<inputs with units>) -> <output>
    // each comment says what the step does and which frame or unit it is in
```

- **Tests** (Metal-free where possible):
  - [ ] `<SuiteName>.<testName>` — <what it checks and the expected value>.
- **Observable completion criteria:** <what the owner sees in the app, in a log line, or in
  test output when this is correct>.
- **Edge cases and expected results:**
  - <input> → <expected outcome>.

### Milestone 2 — <name>

<same structure>

## Simple version, then optimized version

<!-- Every system gets the simplest correct version first. Plan the optimized version when it
     is educationally useful, and keep the simple version as a reference. -->

- **Simple version:** milestones <n–m>. Stays in the code as the reference after the optimized
  version lands.
- **Optimized version:** <what changes, why it should help, and which part of the model stays
  the same>.
- **Runtime switch:** <the enum or flag that selects the version in the running game; the
  existing pattern is `PhysicsUpdateType` and `useBroadPhase` in `PhysicsWorld`>.
- **Comparison:** same inputs, scenes, and validation cases for both versions. Measure
  <quantity> with <the stats overlay, the Metal HUD, a log line, or a test>. Expected:
  <number, and how it was estimated>.
- **Fidelity note:** <say whether the optimization computes the same model faster, or changes
  simulation fidelity or visual quality>.

## Pitfalls and how to detect them

| Symptom | Likely cause | How to check |
|---|---|---|
| <what you see on screen or in the log> | <why> | <test, log line, overlay, or GPU capture step> |

## References

<!-- Three tiers. Annotate each entry: what it is, which section or function to read, and why.
     Say so when the origin could not be established. Language does not matter. -->

1. **Origin:** <person, company, university, paper, or talk where the idea originated>.
2. **Detailed explanation:** <the clearest thorough explanation>.
3. **Reference implementation:** <project, file, function, and what to study>.

Adaptations made for this engine: <what differs from the sources and why>.

## Pseudocode style

<!-- Used by every plan and research doc in this repo. Language-independent and readable by a
     junior engineer. -->

- Structure with `function name(inputs) -> output`, `for each`, `while`, `if / else`, and
  `return`. No language-specific syntax and no real API calls. An engine touchpoint is written
  as `engine: SceneManager.RemoveObject(object)`.
- Names are descriptive. A quantity name carries its unit as a suffix: `_m`, `_s`, `_mps`, `_N`,
  `_rad`. Frames are named where they matter: `worldVelocity_mps`, `bodyLocalAttachPoint_m`.
- One idea per line. A comment says what a step does, not what the syntax is.
- When the math uses symbols, define each symbol once, above the block, and map it to the
  name used in the pseudocode.

Example:

```pseudocode
// One landing-gear strut as a spring-damper along a ray. Inputs are in the aircraft body frame.
function computeStrutForce(strut, rayHitDistance_m, previousCompression_m, deltaTime_s) -> supportForce_N
    // compression is how far the strut is pushed in from full extension; never below zero, never past its travel
    compression_m = clamp(strut.reachLength_m - rayHitDistance_m, 0, strut.maxTravel_m)
    compressionRate_mps = (compression_m - previousCompression_m) / deltaTime_s
    springForce_N = strut.springRate_NPerM * compression_m
    // compressing and rebounding use different damping, like a real oleo strut
    if compressionRate_mps > 0
        dampingRate_NsPerM = strut.compressionDamping_NsPerM
    else
        dampingRate_NsPerM = strut.reboundDamping_NsPerM
    dampingForce_N = dampingRate_NsPerM * compressionRate_mps
    return max(0, springForce_N + dampingForce_N)    // a strut pushes; it never pulls the aircraft down
```
