# <Topic> — Review

<!--
How to use this template
- Copy it to code_reviews/<agent>/topic_name_review_YYYY-MM-DD.md and keep the section order.
- Replace every <angle-bracket> placeholder. Delete guidance comments like this one.
- A review explains defects and why they occur, preserves the owner's approach where practical,
  and proposes changes. It does not edit source, tests, or the plan. If the plan is wrong, the
  review says so and the owner folds the fix into the plan with a changelog line.
- Write in simple technical English. Define a term before using it.
- Rules for all agents: AGENT_PROJECT_RULES.md at the repo root.
-->

**Date:** YYYY-MM-DD · **Agent:** claude | codex | gemini
**Scope:** <plan path and milestone; the files or commit range reviewed>
**Baseline:** <commit hash the review was made against>

## Summary

<Two or three sentences: does the milestone meet its completion criteria, what must change before
it lands, and what can wait.>

| Category | Count |
|---|---|
| Correctness | 0 |
| Deviation from plan | 0 |
| Readability | 0 |
| Optimization (optional) | 0 |

## Checks executed

<!-- Only what actually ran: the command, its result, and what it showed. Say what was not run
     and why. Never report a check that did not run. -->

- `<command>` — <result>.
- Not run: <what and why>.

## Findings

<!-- Most important first. Repeat the block per finding. -->

### F1 — <short title>

- **Category:** correctness | deviation from plan | readability | optimization (optional)
- **Where:** `<File.swift:line>`
- **What happens:** <the observable problem; for correctness, the failing input and the wrong output>.
- **Why it happens:** <the underlying idea the code misses, in plain words, and the rule or source it
  goes against>.
- **Proposed change:** <a minimal diff or pseudocode that keeps the owner's structure>.
- **Plan impact:** none | <the plan is wrong here, and what it should say instead>.

## What is right, and why

<!-- Specific choices that are correct and teach something. No filler praise. -->

- <choice> — <why it is right>.

## Questions for the owner

- <A decision or intent the reviewer could not infer from the code or the plan.>

## Numbers checked

<!-- Every number verified, with the scratch script's inputs and result. -->

- <quantity>: plan says <value>, script gives <value>, code gives <value>.
