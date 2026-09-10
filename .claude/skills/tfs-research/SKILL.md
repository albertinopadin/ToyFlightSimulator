---
name: tfs-research
description: Research how a game engine or flight simulator technique works and write a research document for ToyFlightSimulator following research/RESEARCH_TEMPLATE.md. Use when the owner asks to research, investigate, survey, or compare approaches for a system or feature (physics, rendering, flight dynamics, aircraft systems, audio, AI, weather) before planning it. Pass the full research question as the argument, because this skill runs in a fork with no chat history. Not for questions answerable from the codebase alone, and not for writing a plan.
argument-hint: "<the full question to research>"
context: fork
agent: general-purpose
allowed-tools: Read, Grep, Glob, WebSearch, WebFetch, Write
disallowed-tools: Edit, NotebookEdit
---

# tfs-research

Research request: $ARGUMENTS

You are writing a research document for a learning project. The owner reads it to understand
the ideas, and later writes the code from a plan made in a separate request. The rules for every
agent are in `AGENT_PROJECT_RULES.md` at the repo root (imported into CLAUDE.md). This skill runs
in a forked context with no chat history, so everything you need is in the request above, the
rules, and the repository. If the request above is empty, stop and ask for the question.

## Steps

1. **Read the rules and the template.** `AGENT_PROJECT_RULES.md` and
   `research/RESEARCH_TEMPLATE.md`. Keep the template's section order.
2. **Check prior work.** List `research/*/` and `plans/*/` and grep them for the topic. Read
   anything related so the new document extends it instead of repeating it, and note where an
   older document is now out of date.
3. **Read the engine where the topic lands.** Find the files, types, and threads the technique
   would touch, starting from the architecture sections of CLAUDE.md. Part 2 of the template is
   grounded in the current source, not in older documents.
4. **Find the sources, in tiers.** For each idea: the origin (person, company, university, paper,
   or talk), the clearest detailed explanation, and a reference implementation with the file or
   function to study. Prefer primary sources: papers, vendor documentation, engine source.
   Language does not matter; C++ and pseudocode are fine.
5. **Verify before you assert.** Tag each claim [verified] when checked against a primary source,
   [fetched] when the source was read directly, or [unverified]. If an origin cannot be
   established, say so and give a reliable explanation instead. Record refuted claims under
   "What did not survive verification".
6. **Explain for a junior engineer.** Problem, then idea, then the algorithm's steps. Define terms
   before use. Define every symbol once and map it to a descriptive name. State units, coordinate
   frames, sign conventions, and update order. Add a worked example where it helps, and reproduce
   its numbers with a scratch script outside the repo.
7. **Separate evidence kinds for aircraft behavior:** documented facts, general physical
   principles, simulation approximations, and unavailable data.
8. **Recommend the simple version first,** the optimized version later, and how to select and
   measure both in the running game.
9. **Write the document** to `research/claude/<topic_snake_case>_<YYYY-MM-DD>.md` with today's
   date. Pseudocode follows the style section at the end of `plans/PLAN_TEMPLATE.md`.

## Do not

- Create or change anything outside `research/claude/`. Research does not authorize source edits.
- Write a plan. The suggested milestones in Part 2 stay short; the plan is a separate request.
- Paste long source listings. Name the file and function and say what to study.
- Use Swift code fences. Pseudocode only.

## Before finishing, check

- [ ] Every template section is present, in order, or marked "not applicable" with a reason.
- [ ] Every claim in the executive summary carries a tag.
- [ ] Every code name in Part 2 was grepped in the source and exists.
- [ ] Every number in a worked example was reproduced by a script.
- [ ] Every reference is annotated: what it is, what to read, and why.
- [ ] No `swift` code fences anywhere in the document.

## Report

Reply with the document path, the executive summary claims, the open questions, and which
verification steps were actually run.
