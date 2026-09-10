---
name: tfs-review
description: Review the owner's implementation of a plan milestone in ToyFlightSimulator against the plan and the engine's rules, and write the findings to code_reviews/claude/ following code_reviews/REVIEW_TEMPLATE.md. Explains each defect and why it occurs, proposes minimal changes, and never rewrites the code. Runs only when the owner asks for a review.
argument-hint: "<plan path and milestone> [files or commit range]"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob
disallowed-tools: Edit, NotebookEdit
---

# tfs-review

Review request: $ARGUMENTS

The owner wrote this code to learn. The review explains what is wrong and why, keeps the owner's
approach where it works, and proposes rather than rewrites. Rules: `AGENT_PROJECT_RULES.md` at the
repo root. Format: `code_reviews/REVIEW_TEMPLATE.md`.

## Steps

1. **Read the rules and the review template.**
2. **Fix the scope.** The plan and milestone named in the request, and the changed files: the
   files named, a commit range, or `git diff` against the last commit. If the request names no
   plan, look for the open plan under `plans/*/` that matches the files. If there is none, review
   against the engine rules alone and say so in the Scope line.
3. **Read the milestone** in the plan: pseudocode, tests, completion criteria, edge cases. Then read
   the implementation in full, not only the diff hunks, and its tests.
4. **Run what can be run and record exactly what ran:** the build, the relevant suite with
   `-parallel-testing-enabled NO`, and a scratch script outside the repo for every number you
   check. Never report a check that did not execute.
5. **Classify every finding.**
   - **Correctness:** wrong result, crash, race, NaN, unit or frame error, thread-ownership
     violation. Give the failing input and the wrong output.
   - **Deviation from plan:** where the code differs from the milestone, and whether that is a
     valid alternative, a bug, or an error in the plan. The plan can be wrong; say which.
   - **Readability:** naming, term definitions, comments that explain the algorithm, structure.
     Judge against the naming rule in `AGENT_PROJECT_RULES.md`.
   - **Optimization, optional:** deferred to the optimized version unless it changes behavior.
6. **For each finding:** file and line, what happens, why it happens (the idea the code misses,
   not only the fix), and a proposed change as a minimal diff or pseudocode that keeps the owner's
   structure.
7. **Write the review** to `code_reviews/claude/<topic_snake_case>_review_<YYYY-MM-DD>.md` with
   today's date.

## Do not

- Edit source, tests, or the plan. If the plan needs a change, say so in the review; the owner
  folds it in with a changelog line.
- Rewrite the owner's code into your own version.
- Report a check as run when it was not.

## Before finishing, check

- [ ] Every finding has a category, a location, a cause, and a proposal.
- [ ] "Checks executed" lists each command that ran and its result, and what was not run.
- [ ] Positive notes say why the choice is right, so they teach; no filler.
- [ ] Every number checked appears under "Numbers checked" with the script result.

## Report

Reply with the review path, the count per category, the most important finding first, and which
checks were actually run.
