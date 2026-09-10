# <Topic> — Research

<!--
How to use this template
- Copy it to research/<agent>/topic_name_YYYY-MM-DD.md and keep the section order.
- Replace every <angle-bracket> placeholder. Delete guidance comments like this one.
- Write in simple technical English. Define a term before using it. Explain the problem,
  then the idea, then the steps.
- Research does not authorize source edits. A plan is a separate request and starts from
  plans/PLAN_TEMPLATE.md.
- Pseudocode follows the style section at the end of plans/PLAN_TEMPLATE.md.
- Rules for all agents: AGENT_PROJECT_RULES.md at the repo root.
-->

**Date:** YYYY-MM-DD · **Agent:** claude | codex | gemini
**Question:** <the one question this document answers, in a sentence>
**Method:** <how the sources were found and checked: fetched and read directly, search results,
or prior knowledge; which claims were verified against primary sources>

## Executive summary

<!-- Numbered claims: one bold sentence each, then a sentence of support. Tag each claim
     [verified] when checked against a primary source, [fetched] when the source was read
     directly, or [unverified] when it comes from memory or a secondary source. -->

1. **<Claim.>** <Support.> [verified]
2. **<Recommendation for this engine.>** <Why.>

## Terms

- **<Term>** — <definition in plain words>.

## Part 1 — The problem and the ideas

### 1.1 The problem

<What must be computed, simulated, or rendered. Why it is hard. What the naive approach does
and where it fails.>

### 1.2 The core idea

<!-- Repeat this block for each competing idea. Intuition first, then the math with every symbol
     defined, then the algorithm's steps. -->

**Intuition.** <The idea in plain words.>

**The math.** <Equations with each symbol defined once and mapped to a descriptive name. State
units, frames, and sign conventions.>

**The steps.**
1. <Step.>
2. <Step.>

**Worked example.** <A small numeric case traced by hand, where it helps. Reproduce the numbers
with a scratch script.>

**Assumptions and limits.** <Approximations, edge cases, and when the idea stops working.>

### 1.3 How existing engines and simulators do it

<!-- One entry per engine, simulator, or library. Name the file, class, or function to study and
     what it shows. Language does not matter. -->

- **<Engine or library>** — <approach>. Study: `<file or function>` — <what it shows>. [verified | fetched | unverified]

### 1.4 Tradeoffs

| Approach | Correctness | Complexity to implement | Runtime cost | What it teaches | Origin |
|---|---|---|---|---|---|
| <name> | | | | | <person, company, or paper> |

### 1.5 Evidence quality

<!-- For aircraft behavior, separate documented facts, general physical principles, simulation
     approximations, and unavailable data. -->

- Documented facts: <with source>.
- General physical principles: <>.
- Simulation approximations used by games and simulators: <>.
- Unavailable or classified data, and what stands in for it: <>.

### 1.6 What did not survive verification

<!-- Claims that were checked and found wrong, so later work does not re-import them. Also list
     coverage gaps: what was not researched. -->

- <Claim> — <why it is wrong, and what the source actually says>.
- Not covered: <topics or engines outside this document's scope>.

## Part 2 — Applying it to ToyFlightSimulator

### 2.1 Where the engine is today

<Files, types, and constraints that matter, checked against the current source. Note any older
plan or research doc that is now out of date.>

### 2.2 Recommended approach

- **Simple version first:** <the simplest correct implementation that makes the idea visible, and
  how it fits the engine's constraints>.
- **Optimized version later:** <what would change, why it should help, and how it would be
  measured. Say whether it changes fidelity or only speed.>
- **Runtime selection:** <the enum or flag so both versions run in the game, when practical>.

### 2.3 Suggested milestones

<!-- Short. The plan expands these. Each milestone is small enough to implement and check alone. -->

1. <Milestone> — observable result: <what you see in the app, a log, or a test>.

### 2.4 Risks and pitfalls

| Symptom | Likely cause | How to check |
|---|---|---|
| | | |

## Open questions

- <A decision the owner must make, or something the sources did not settle.>

## References

<!-- Annotate every entry: what it is, which section, function, or file to read, and why. Group
     by tier. Say so when attribution could not be established. -->

### Origin sources
- <Person, company, university, paper, or talk where the idea originated> — <what to read>.

### Detailed explanations
- <Book chapter, article, course notes, or documentation> — <what to read>.

### Reference implementations
- <Project> — `<file or function>` — <what it shows, and the language>.

### Engine and simulator documentation
- <Vendor docs> — <version and date checked>.

### Non-URL references
- <Book or paper> — <edition, chapter, pages>.

Attribution notes: <where the original source could not be established, and what was used instead>.
