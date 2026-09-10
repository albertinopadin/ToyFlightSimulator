---
name: tfs-plan
description: Write or revise an implementation plan for a ToyFlightSimulator system or feature following plans/PLAN_TEMPLATE.md, in pseudocode, from an existing research document or the codebase. Use when the owner asks to plan, design, or write an implementation plan, or asks how they would implement something and wants a plan rather than a short explanation. Not for implementing code and not for research.
argument-hint: "<topic> [path to the research document]"
allowed-tools: Read, Grep, Glob
---

# tfs-plan

Plan request: $ARGUMENTS

The owner writes the Swift from this plan. The plan is pseudocode, references, tests, and checks,
not source code. Rules: `AGENT_PROJECT_RULES.md` at the repo root. Format: `plans/PLAN_TEMPLATE.md`.
If the request above is empty, plan what the owner asked for in the conversation.

## Steps

1. **Read the rules and the template.** `AGENT_PROJECT_RULES.md` and `plans/PLAN_TEMPLATE.md`.
2. **Find the design source.** If the request names a research document, read it. Otherwise look
   in `research/*/` for the topic. If nothing fits and the topic is nontrivial, stop and say a
   research document should come first (the `tfs-research` skill). Small changes can be planned
   from the codebase alone.
3. **Read the engine where the plan lands.** Files, types, threads, and registration paths. Verify
   every name you will cite with grep. Check the constraints in CLAUDE.md (thread ownership,
   registration, reverse-Z depth, meters, Metal-free tests) and the recipes in the
   `extending-the-engine` skill.
4. **Check for an existing plan** on the topic in `plans/*/`. If one is open, revise it in place
   and add a changelog line instead of starting a new file.
5. **Fill the template in order.** Milestones are small enough to implement and check alone. Each
   has a learning objective, prerequisites, engine integration points, pseudocode, tests,
   observable completion criteria, and edge cases with expected results. Tag design decisions
   [codebase], [source: name], or [design].
6. **Plan the simple version first** and the optimized version behind a runtime switch, with what
   to measure and the expected result. Say whether the optimization changes fidelity or only speed.
7. **Reproduce every number** (worked example, expected values, rate sizing) with a scratch script
   outside the repo, and state the script's inputs in the plan.
8. **Write the plan** to `plans/claude/<topic_snake_case>_<YYYY-MM-DD>.md` with today's date, or
   edit the existing plan.

## Do not

- Write Swift. Pseudocode in the house style at the end of the template; a call-site example of a
  few lines that shows an existing engine API is the only exception.
- Change anything outside `plans/`. A plan does not authorize source edits, and approval of the
  plan is not a request to implement it.
- Skip references. Every plan ends with origin, detailed explanation, and reference implementation.

## Before finishing, check

- [ ] No `swift` code fences.
- [ ] Every cited type, function, and file exists in the source (grep).
- [ ] Every milestone has all seven fields.
- [ ] Every number was reproduced, and the changelog says so.
- [ ] Terms are defined before use; symbols are mapped to names; units and frames are stated.
- [ ] References are annotated in three tiers, and design decisions carry their origin tag.

## Report

Reply with the plan path, one line per milestone, the decisions left to the owner, and which
checks were actually run.
