# Agent Project Rules

Read this file before any task. It is the working agreement between the owner and every
AI agent (Claude, Codex, Gemini). `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` hold the engine
architecture reference; this file holds purpose, workflow, and document rules. It loads into
every session, so it stays short.

## Project purpose and learning goals

ToyFlightSimulator is a personal learning project. Its purpose is to understand game engine
programming and flight simulation by implementing systems and observing their behavior.

Topics include graphics and rendering, physics, water and weather, audio, game AI, VR,
realistic flight dynamics, and aircraft systems such as radar and electronic warfare.

Help the owner understand the ideas, implement them, verify correctness, and eventually
understand their performance tradeoffs.

## Collaboration workflow

- Research, explanation, planning, review, and implementation are distinct requests.
  Complete the requested stage without automatically moving into the next one.
- Treat questions about how to implement something as requests for explanation or planning.
- The owner normally writes the Swift implementation. Implementation plans contain
  language-independent pseudocode unless actual source code is requested.
- Research, planning, and review requests do not authorize source edits. Write documentation
  files only when requested. Approval of a plan does not itself request implementation.
- When implementation is explicitly requested, implement within scope and provide the
  relevant explanations, references, and verification.
- Scale explanations to the task. Small changes do not require a full research report.

## Where documents go

- Research: `research/<agent>/`. Plans: `plans/<agent>/`. Reviews: `code_reviews/<agent>/`.
  Debugging notes and screenshots: `debugging/`. `<agent>` is `claude`, `codex`, or `gemini`.
- File names are snake_case and end with the date: `topic_name_YYYY-MM-DD.md`.
- Research documents follow `research/RESEARCH_TEMPLATE.md`. Plans follow
  `plans/PLAN_TEMPLATE.md`, which also defines the pseudocode style. Reviews follow
  `code_reviews/REVIEW_TEMPLATE.md`.
- Older documents are historical context. Verify them against the current source before
  following them. Plans started before this file existed (2026-09-10) carry Swift listings
  and keep their own conventions until they close; new plans follow the template.

## Explanation and naming

- Use simple, precise technical English suitable for a junior engineer. Define unfamiliar
  terms and acronyms before relying on them.
- Explain the problem, then the underlying idea, then the algorithm's individual steps.
- Use descriptive variable, function, and type names in pseudocode and source code. A name
  says what the thing is and, where it matters, its frame or role: `localCapsuleCoreStart`,
  not `local0`; `psoType`, not `t`. Single-letter math names appear only next to a comment
  that defines them.
- Define mathematical symbols and connect them to implementation names. State units,
  coordinate frames, sign conventions, and update order wherever they affect correctness.
- Make the algorithm being studied visible. Explain nontrivial helper operations instead of
  hiding the central idea behind an unexplained function or library call.
- Explain assumptions, approximations, edge cases, and known limitations.

## References and evidence

- For nontrivial algorithms and systems, provide an annotated set of references: the
  original publication or authoritative source where identifiable, a detailed explanation,
  and a reference implementation when available.
- Verify attribution. If the original source cannot be established, say so and provide a
  reliable explanation.
- Reference implementations may use pseudocode, C++, or other languages. Identify useful
  sections, functions, or files and explain what to study.
- Distinguish source material from adaptations made for this engine. Mark each design
  decision with where it came from: the codebase, a named source, or the agent's own design.
- For aircraft behavior, distinguish documented facts, general physical principles,
  simulation approximations, and unavailable data.
- Reproduce every number in a plan or a review with a scratch script before adopting it.
  Record adopted review changes in the plan's changelog.

## Plans and validation

- Break plans into small milestones that can be implemented and checked independently.
- For each milestone, include the learning objective, prerequisites, relevant engine
  integration points, algorithm pseudocode, tests, and observable completion criteria.
- Include a small worked example where useful, plus edge cases and expected results that
  the owner can check independently.
- Prefer Metal-free tests for logic: pure static helpers, `Node`, detached rigid bodies, and
  the `TestRigidBody` double. Constructing a `GameObject` or touching `Assets.Models` needs a
  Metal device and an app-hosted test.
- During review, explain concrete defects and why they occur. Preserve the owner's approach
  where practical.
- Separate correctness problems, readability suggestions, and optional optimizations.
  Clearly state which checks were actually executed.

## Simple and optimized implementations

- Begin with the simplest correct implementation that makes the central idea clear and
  respects the engine's required constraints.
- Where educationally useful, plan a later optimized implementation and preserve the simple
  version as a reference.
- Use comparable inputs, scenes, and validation cases for both versions. Provide runtime
  selection when practical and useful for learning. The existing pattern is `PhysicsWorld`:
  `PhysicsUpdateType` selects the solver and `useBroadPhase` keeps the O(n²) path selectable.
- Explain what each optimization changes, why it should help, and how its effect will be
  measured.
- Distinguish faster computation of the same model from changes to simulation fidelity or
  visual quality.
- Avoid abstractions introduced only for hypothetical future needs.
- Keep superseded code that still teaches something. Mark it with a deprecation comment and
  route it through the surviving API instead of deleting it.
