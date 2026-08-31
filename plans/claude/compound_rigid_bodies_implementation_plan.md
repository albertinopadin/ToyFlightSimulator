# Compound Rigid Bodies — Implementation Plan

**Started:** 2026-07-19 · **Revised:** 2026-08-27 (post-meterization + external review — see Changelog)
**Source of truth for design decisions:** `research/claude/compound_rigid_bodies_research_combined.md` (§4 is the phase outline this plan executes; §2–§3 hold the argued verdicts).
**Supporting docs:** `research/claude/compound_rigid_bodies_research_2026-07-14.md` (type definitions §2.3, F-22 spec §2.3, overlay sketch §2.7), `research/codex/compound_rigid_bodies_and_articulated_landing_gear_research_2026-07-14.md`.

## How this document works

- **Steps are living text.** They get edited in place to stay true to the current contract. (The original
  append-only rule was retired 2026-08-27: it had begun actively obscuring the contract — the executable
  steps still described the pre-meterization scale-3 units world.)
- **History** lives in two places: dated `> **Addendum (YYYY-MM-DD):**` blocks are kept where they still
  explain a *why*; every substantive revision gets a **Changelog** entry below.
- **Checkboxes** (`- [ ]`) get ticked in place as steps land.
- Every step cites the research-doc section it implements so the "why" is one hop away.

## Changelog

- **2026-08-31** (camera fix) — **PhysicsStressTestScene camera fixed on main**: `[0, 15, +40]`
  → `[0, 15, −40]` with a comment naming the +Z-forward convention and the bisect. Verified by
  booting the scene on main (temporary Preferences flip, reverted): spheres render and settle,
  same framing as the branch check; the −15° pitch is correct (spheres sit slightly below view
  center, exactly where a 15°-down pitch puts them from 40 m — an up-pitch would have framed
  them out). Test branch `pre-phase-a-stress-check` deleted after serving the bisect (its two
  commits were test-only scaffolding: boot-into-scene + the camera experiment). Criterion 7 now
  waits only on the owner's frame-rate/feel pass.
- **2026-08-31** (stress-scene bisect) — **The all-black PhysicsStressTestScene is NOT a Phase A
  regression, and its root cause is found.** On branch `pre-phase-a-stress-check` (off
  `ae1c8f4`, pre-Phase-A, booting straight into the scene) the render is identically black
  while physics runs perfectly (stress stats stream to stdout throughout). Root cause: the
  scene's `DebugCamera` sits at `[0, 15, +40]` with no yaw — under the +Z-forward convention it
  faces AWAY from the sphere grid (spawned in x/z ∈ [−8, 8]) — a leftover from before the
  +Z-forward migration, unnoticed because nobody had run the scene since. Confirmed by flipping
  the camera to z = −40 on the test branch: the scene renders (spheres visible, settling). The
  one-line fix on main is deferred to the owner's follow-up commit, which should also re-check
  the −15° pitch sign. Bonus: criterion 7's stats leg was measured from stdout on both trees —
  see the criterion's annotation for the numbers (step cost ~1.4× at sub-ms scale, broad-phase
  behavior identical).
- **2026-08-31** (in-app verification) — **Exit criterion 4 CLOSED by the project owner**: a
  rolled touch logs the wings by name (`[Contact] F-22_CGTrader.wings touched Quad (depth
  0.007 m)`), the X-key overlay shows only the red live-collider volumes (yellow ghost gone),
  and ground contact was already confirmed. Criterion 7 got a partial — BallPhysicsScene feels
  right and holds > 60 fps from the contact-heavy start — but stays open on a **known issue**:
  PhysicsStressTestScene currently renders all black (owner-deferred to a follow-up commit; not
  yet bisected, so it may or may not predate Phase A). Remaining Phase A exit items: 6 (CI when
  the commits reach the remote) and 7 (blocked on the stress-scene render fix).
- **2026-08-31** (latest) — **Step A.7 landed → A-aircraft commit COMPLETE** (hand-implemented by
  the project owner, then review-verified; comments, the two doc flips, and `CompoundBodyTests`
  completed at review). `FlightboxWithPhysics.applyAircraftSwap` now builds the player body from
  `AircraftColliderSpec` — the CGTrader F-22 gets a plain `RigidBody` carrying the Phase
  0-verified three-primitive compound, spec-less aircraft keep the legacy 2 m sphere, and a
  per-swap `ContactDebugLogger` instance reports named contacts (throttled, print-only,
  per-instance — no process-wide state). The spec's doc comment flipped PLACEHOLDERS →
  overlay-verified-and-live (the deferred half of Phase 0 criterion 2), and the overlay's ghost
  branch documents that the yellow legacy sphere disappears for compound aircraft BY
  CONSTRUCTION. `CompoundBodyTests` pins the pipeline end to end Metal-free: the detached
  compound settles at y ≈ 1.05 on "fuselage" only (the legacy sphere rested at 2.0), and the
  90°-banked pose contacts "wings" alone at depth ≈ 1.6. The project owner verified in-app the
  same day that the compound F-22 contacts the ground plane correctly; exit criterion 4's
  remaining eyeballs (a rolled touch logging `wings`, the X-key overlay showing red volumes
  with no yellow ghost) stay open until flown. Exit criterion 5 (no process-wide state) closes
  here: the determinism test is green, the suite passes under Swift Testing's default
  in-process concurrency, and review confirms Phase A added no static mutable state (the
  response's statics are `let` constants; the logger is per-instance).
- **2026-08-31** (later) — **Step A.6 landed → A-response commit COMPLETE** (hand-implemented by
  the project owner, then review-verified against the listings; comments and test deliverables
  completed at review). The response math matched the A.6 listing operation-for-operation on
  arrival — constants, β/slop correction, approach guard, threshold, always-applied impulse; the
  review's additions were the plan's doc comments (the constants' rationale, the numbered step
  comments, and replacing the now-stale "A-ROUTING TRANSCRIPTION — behavior-frozen" doc that
  still sat on the corrected body) plus the whole regolden/test track. **One amendment to A.6
  File 2**: `applyLegacyEulerResponse` (and its `restSpeedThresholdSquared`) is RETAINED as
  clearly-marked unreferenced reference code instead of deleted — project-owner decision; the
  doc comment on it says exactly that, nothing calls it, and `eulerPathRests` + the regoldened
  `single_bounce_euler` pin the shared corrected response as the live path. Regolden review
  (diffs read like code against the 0.7/A.6 signature table): `single_bounce_verlet`/`_euler`
  diverge first at steps 59/58 (first contact ≈ 57–58; free fall identical before), apex
  sequences strictly decreasing (4.144→3.452→2.890 / 4.280→3.687), gravity on at the window end;
  `rest_latch` diverges from the first post-contact sample (step 45 — first contact ≈ 43–44 from
  the 2.5 m fall; the table's "~step 66" was the OLD latch step, not first contact) and lands
  the predicted equilibrium: final |v| = 0.1635 = exactly g·dt, last y = 0.4882 (1.18 cm =
  slop + sink/β residual), gravity ON — the latch signature is gone from the JSON;
  `head_on_pair` is the strongest confirmation: the contact lands at depth EXACTLY 0 (3 m gap,
  10 m/s closing, dt 1/60 → the inclusive boundary), so correction is 0 in both eras and the
  e=1 equal-mass swap is structurally identical — the regolden differs only in last-ulp fp
  noise (≤ ~3e-7, the inverse-mass association), mirror symmetry exact to 0.0, velocities swap
  to exactly ±5; `ball_cluster_16` diverges at the first sampled step because bodies 1–2 spawn
  0.742 m apart (< 0.8 sum — the OLD response rest-latched that pair at spawn, the new one
  support-cycles it), `stress_grid_50` at step 63 ≈ the first floor contacts from the 5 m spawn
  floor; both chaos scenarios finite, within UN-EDITED speed budgets, all
  finalShouldApplyGravity true. The characterization test flipped to `restingKeepsGravityOn`
  (observed equilibrium recorded in its comment), `CollisionResponseTests` landed (8 semantic
  pins incl. the latch regression and the Euler-path rest), and
  `grep "shouldApplyGravity = " Physics/` shows exactly the two initializer assignments — zero
  solver writes. Full serial suite green: 286 tests / 45 suites + XCTest. Exit criterion 2
  closes here.
- **2026-08-31** — **A.8 routing-track suites backfilled** (own commit, sequenced before the
  A-response commit). The A-routing commit landed without the A.8 suites owed to it — this
  commit pays that debt: `WorldColliderBuilderTests` (7 hand-computed pose/AABB pins),
  `NarrowPhaseTests` (the §4.7 geometry matrix: translated AND tilted planes for all three
  shapes, every separated-nil case, box-box pinned nil-even-overlapping, sphere-in-box
  least-axis + x→y→z tie determinism, the three Ericson capsule-capsule cases, capsule-box
  approximation sanity, flipped-pair metadata both ways, the two legacy-exact sphere-sphere
  pins, plane-as-A flip with deepest-index survival), `RigidBodyTests` additions (rebuild-count
  cache discipline via a @testable subclass hook, synthesized sphere view + nil metadata,
  `collisionRadius.didSet`, compound AABB union, empty-list zero-AABB fallback), the
  `CollisionFilteringTests` mask truth table, `PhysicsSolverTests`' collider-less-pair pin
  (the old force-cast crash site), and the two `PhysicsWorldSmokeTests` additions (attached
  onContact smoke both ways; same-GameObject exclusion). All response-independent — green
  against the old response at this commit and the corrected one after it. Exit criterion 3
  (general planes) closes here.
- **2026-08-30** (later) — **Step A.5 landed → A-routing commit COMPLETE** (hand-implemented by the
  project owner, then review-verified against the listings). Both response paths now run ONE
  `NarrowPhase.generateContacts` per pair via the shared `resolvePair` shape (filter guard →
  narrow phase → symmetric insertion → deepest-contact response → per-contact events), and the
  entire `CollisionShape` layer is deleted (PhysicsWorld's `collided`×4 / `getCollisionData` /
  `CollisionData` / both `getPenetrationDepth`s, y=0 hack included / `getDistance`; the enum +
  protocol requirement; RigidBody's stored property + both init params; the four subclass
  assignments; the `TestRigidBody`/`RigidBodyTests` mechanical edits). Review caught three
  transcription slips before anything ran, all fixed to the listings: (1) the Hecker broad-phase
  loop called `resolvePair(entityA, entityA)` — every candidate pair narrow-phased a body against
  itself and the real pair never resolved; (2) `EulerSolver.resolvePair` still pre-gated on the
  doomed `PhysicsWorld.collided` and lacked the A.4 `shouldCollide` guard; (3) `EulerSolver`'s
  static-A branch consumed the strict B→A normal directly (missing the `legacyVector`
  reconstruction — wrong-sign reflection whenever the static body arrives as `ei`). Gate results:
  build + full serial suite green (240 tests / 40 suites), goldens byte-untouched, and the regen
  dry-run rewrote all six goldens **byte-identical** (designed failure observed; `git diff
  --exit-code` on Baselines/ empty; clean re-run green). Two notes: the plan's
  "`resolveCollisionsAllPairs` callers gain the scratch" landed as the pair-consuming
  `EulerSolver.step` test caller instead (the only affected call site), and PhysicsParityTests'
  floorPlane comment was rewritten (it named the deleted `getPenetrationDepth(ball:plane:)`;
  origin+up stays load-bearing via A.5's bit-exactness argument 3). The in-app
  FlightboxWithPhysics eyeball was confirmed by the project owner the same day — physics plays
  as before — closing the A-routing verification checklist and exit criterion 1 (criterion 6's
  CI leg runs when the commits reach the remote).
- **2026-08-30** — **Steps A.1–A.4 landed** (the first half of the A-routing commit — hand-implemented
  by the project owner from the spec blocks, then review-verified against the listings
  operation-for-operation). The routing itself has NOT flipped yet: `Contact`/`NarrowPhase` compile
  but nothing calls them until A.5 rewires the response paths, and the legacy
  `collided`/`getCollisionData` flow still runs every pair. Behavior-neutral by construction — the
  only live change is A.4's broad-phase `shouldCollide` guard, inert under the default masks
  (verified: full serial suite green, 240 tests / 40 suites, goldens byte-untouched). One
  micro-deviation from the A.3 listing: `capsuleSegment` / `capsuleAsSphere` return named tuple
  members (`(p0:, p1:, radius:)` / `(center:, radius:)`) for readability — callers destructure
  positionally, so the listed call sites are unchanged. A.5 remains open; the A-routing golden
  gate (bit-for-bit regen dry-run) applies when it lands.
- **2026-08-29** — **Phase 0 closed ✅; Phase A planned** (full section appended below). Exit
  criteria 1 and 2 verified in-app by the project owner (X-cycle checklist including
  swap/reset/renderer-switch survival; spec numbers eyeballed in both overlay modes and accepted
  as authored — no retune needed, so no spec-number commit; the spec file's PLACEHOLDER doc comment
  flips to "overlay-verified" in step A.7, when the numbers become load-bearing). Criterion 5
  closed by CI: the macOS Tests workflow is green on main at `0ec9a3e` (run 33221486316,
  2026-08-28), which contains the whole Phase 0 parity track. The Phase A plan implements combined
  doc §4.2 amended by all four pre-Phase-A corrections, split into **three separately verified
  commits** (A-routing: goldens must match bit-for-bit; A-response: reviewed regolden + semantic
  asserts; A-aircraft: the F-22 compound goes live). Planning-time findings recorded as Phase A
  deviations: (1) the world-collider cache is **dirty-flag** based — the research sketch's static
  `currentStepIndex` token is eliminated entirely, resolving corrections 1 and 2 with one
  mechanism; (2) `SphereRigidBody` **stays a body-level shape** — its `collisionRadius` is WORLD
  meters while `LocalCollider` dimensions are local×`uniformScale`, so the research's
  "install a one-sphere collider list" would double-scale every scaled ball (FlightboxWithPhysics'
  dispersed objects run node scale ≈ radius); (3) the narrow phase emits **strict B→A normals**
  from day one, with the routing-commit response transcribed via exact IEEE sign symmetry
  (the legacy convention was shape-dependent); (4) `EulerSolver`'s bespoke response unifies onto
  the corrected shared response in A-response.
- **2026-08-28** (night) — **Steps 0.6, 0.7, 0.8 landed; 0.3b closed** (Phase 0 code complete). The
  0.6 inits and 0.7's SplitMix64 were hand-transcribed from the spec blocks; verification caught one
  transcription bug before anything ran: `init(detachedAt:)` assigned `isStandalone = false` (copied
  from the attached init's line), which would have parked every harness body at `.zero` and recorded
  flatline goldens. Fixed, spec doc comments filled in. All six goldens recorded via
  `TEST_RUNNER_TFS_REGEN_PHYSICS_BASELINES=1` (regen run fails by design; clean re-run green;
  trajectories spot-checked — bounce decay, latch settling at y=0.499 with v exactly zero, head-on
  rebound mirror-exact to ±9.0 m). 0.8's suites landed: `ColliderShapeTests`,
  `AircraftColliderSpecTests`, `ColliderOverlayMappingTests`, `MeshBoundsTests`,
  `NodeOwnershipTests` (closing 0.3b), plus the `NodeTests` XCTest additions and `RigidBodyTests`
  detached-mode tests. Full serial app-hosted run: 240 Swift Testing tests in 40 suites + XCTest,
  all green. Exit criteria 3 and 4 ✓; 1–2 (manual visual) and 5 (CI) remain open.
- **2026-08-28** (evening) — **0.7 fully specified**: the harness pseudocode is replaced by the complete
  implementation — `SplitMix64` written out (the SplittableRandom mixer); a `ParityScenario` enum
  (String raw values = golden filenames, `CaseIterable` feeds the parameterized test) with all six
  builders, whose RNG draw order is pinned as part of the golden contract; `ParityRunner` with
  fail-fast `#require` invariants on every step and first-divergence-only golden reporting; and the
  regen command (`TEST_RUNNER_` prefix forwards the env var into the app-hosted runner; the regen run
  fails by design). Details the scenario table left open are now pinned in code: rest_latch's plane
  e = 1.0 (min() picks the ball's 0.2; latch fires on the third contact, ~70 steps in),
  head_on_pair keeps gravity ON (lockstep fall keeps the contact normal X-pure, so the e=1 swap stays
  exact), sampleEvery 1 (simple) / 3 (chaotic), seeds `0xF22_0005`/`_0006`, per-scenario speed
  budgets, 1 m tunneling slack, and a new `allFinite(SIMD3<Float>)` overload in TestSupport/Finite.swift.
  (Recorded mid-transcription: SeededRandom.swift already sits in the tree as an empty skeleton.)
- **2026-08-28** (later still) — **0.6's `RigidBody` code fully specified**: the `init(detachedAt:)`
  sketch is now the complete implementation (full parameter list mirroring the attached designated
  init, full body), plus the constraint that forces a second *designated* init: delegation to
  `init(gameObject:)` is impossible because `isStandalone` is a `let` that init assigns `false`, and
  a shared private designated init would rewrite the attached init whose fallbacks
  `RigidBodyTests.rigidBodyToleratesNilGameObject` pins. Recorded mid-transcription — at this
  revision the storage, accessors, and the attached init's `isStandalone = false` line were already
  in the (uncommitted) working tree; the remaining 0.6 code is the three `detachedAt` inits (base +
  both `BasicRigidBodies` subclasses) and the storage doc comment.
- **2026-08-28** (later) — **Step 0.5 done**: the pending in-app anchor check ran. Verified via a
  temporary update-thread auto-trigger firing the overlay's normal `cycle` path once in
  FlightboxWithPhysics (keystroke injection isn't available headlessly; the X-key wiring itself was
  already verified in 0.4's landing), with app stdout captured: the fuselage capsule prints exactly
  **18.90 m at uniformScale 1.0** (real F-22: 18.92 m), the wings/empennage/legacy-sphere lines match
  their spec arithmetic, and the `uniformScale` debug assert stayed quiet. Log excerpt in the 0.5
  addendum; the trigger was reverted after the run. Visual fit/tuning (exit criterion 2) remains open.
- **2026-08-28** — **Step 0.4 landed** (all five files; macOS Debug build green; X cycle verified
  visually in-app), together with **0.3b's code half** (`Node.parent` and
  `SubMeshGameObject.parentMeshGameObject` → `weak`; `NodeOwnershipTests` still owed) and one extra
  same-class fix found during review: `Mesh.parentModel` → `weak` (write-only strong back-reference;
  the Model ↔ Mesh cycle would have leaked each bespoke capsule volume's one-off Model per overlay
  show). Deviations recorded in the 0.4 addendum: `cubeMeshSize` naming (listing updated), overlay
  track landed before the parity track (0.6/0.7), `logWorldDimensions` prints filled in during review
  so 0.5's in-app anchor check is still pending.
- **2026-08-27** — Phase 0 revision incorporating the Codex verification review. Every finding was
  re-verified against the tree before adoption (ModelIO semantics were measured directly, not taken on
  faith — see 0.5):
  1. **Units contract rewritten for landed meterization** (see `plans/claude/meter_scale_implementation_plan_2026-07-23.md`):
     colliders are authored in post-import engine-local **meters**; aircraft run at scale **1.0**
     (`FlightboxWithPhysics.applyAircraftSwap`). All scale-3 arithmetic deleted; step 0.2 re-authored
     with meter placeholders (fuselage capsule now spans nose→tail ≈ 18.9 m, resolving the old
     17.1 m-vs-nose→tail contradiction in favor of nose→tail); the sanity anchor is now 18.9 m at ×1.
  2. **Capsule mesh mapping corrected from measurement**: `MDLMesh(capsuleWithExtent: [x, y, z])` treats
     x/z as the **radius** and y as the **total cap-to-cap length**, so `capsuleMeshParams` must return
     `2·(halfHeight + radius)`, not `2·halfHeight`. The planned one-time *visual* calibration is replaced
     by a CPU bounding-box regression test. (Bonus finding: `sphereWithExtent` is also radius-semantics —
     `SphereMesh(radius:)` builds a 2× mesh. Latent today; the overlay never uses `SphereMesh`; pinned by
     the same test.)
  3. **New step 0.3b**: `Node.parent` (and `SubMeshGameObject.parentMeshGameObject`) become `weak`.
     With both strong, every detached ≥2-node subtree is a retain cycle — aircraft swaps AND
     `teardownScene()` (which only detaches top-level children) leak the old aircraft plus its
     afterburner emitters today. The overlay lifecycle rules in 0.4 are rewritten on top of this fix.
  4. **Overlay gains a hull-hidden mode** (X cycles off → volumes-over-hull → volumes-only): depth-tested
     translucent volumes can reveal overfit (protrusion) but never underfit (fully-contained volumes are
     occluded, and back-face culling hides them from inside too). The old "accepted limitation" was
     stronger than the tool could verify.
  5. **Parity plan corrected**: Phase A's slop+β positional correction (research combined doc §3.3/§4.2)
     diverges from the *first contact* in every scenario including the dynamic/dynamic head-on pair, so
     the old "identical" expectations were wrong. Verification is split into a routing-only commit (exact
     golden match) and a response commit (reviewed regolden + semantic asserts); chaotic cluster/stress
     goldens are shortened and backed by long-run invariants; `SplitMix64` derives Floats directly
     instead of through `Float.random(in:using:)`.
  6. **Step 0.6 redesigned**: explicit `init(detachedAt:)` standalone mode instead of relaxing production
     inits to `GameObject?` — the old design silently changed the *tested* released-weak-reference
     fallback behavior (`RigidBodyTests.rigidBodyToleratesNilGameObject`).
  7. **Verification commands fixed**: the macOS scheme's Build action builds only the app (verified in the
     .xcscheme), so `build` + `test-without-building` was unreliable; use `build-for-testing` +
     `test-without-building`, or serial `xcodebuild test`. 0.8 additionally gains NodeTests for the 0.3
     rotation dirty-flag fixes, which landed untested.
  Plus smaller items: pre-Phase-A design corrections recorded (per-world step/scratch state,
  world-collider cache invalidation, world-transform contract), `worldSpan` → `worldDimensions`,
  exhaustive `AircraftType` switch in the spec, finite/positive dimension asserts.

**Verification commands** (corrected 2026-08-27 — the scheme's Build action builds the app only, so a
plain `build` does NOT produce the test bundle):

```bash
# Build tests + app
xcodebuild build-for-testing -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Scoped suite run (add -only-testing for one suite); serial per project rule
xcodebuild test-without-building -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug -parallel-testing-enabled NO \
  -only-testing:"ToyFlightSimulatorTests/<SuiteName>" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Or the one-step full suite (serial matches CI and avoids app-host deadlocks)
xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Note: `-parallel-testing-enabled NO` serializes test *bundles/clones*, not Swift Testing's in-process
concurrency — parameterized `@Test` cases still run concurrently inside one process. Test designs (and
the physics engine itself — see the pre-Phase-A corrections) must not rely on process-wide statics.

---

# Phase 0 — Debug overlay, units contract, parity harness

Implements combined doc **§4.1**. Everything in this phase is **behavior-neutral for the running game**,
with one deliberate exception: step 0.3b fixes the scene-graph ownership direction, so detached subtrees
now deallocate (that IS the observable change, and it's what the step's tests pin). No physics semantics
change, no render-path change. Phase 0 exists so that (a) every collider/strut number in Phases A/B can
be eyeballed against the real model before physics consumes it, and (b) Phase A's response-path rewrite
diffs against a recorded baseline instead of against memory.

**Deliverables:**
1. A collider overlay on the player aircraft, cycled with the **X** key through three states —
   off → translucent volumes over the hull → volumes with the hull hidden — showing the proposed
   compound spec (red) next to the legacy 2 m physics sphere (yellow).
2. The units contract (collider dimensions are post-import engine-local **meters**; `uniformScale` is a
   pass-through multiplier that is 1.0 for every meterized aircraft) enforced by a debug assertion and
   sanity-checked against the CGTrader F-22.
3. A Metal-free, deterministic trajectory-capture harness with committed golden baselines ("goldens":
   recorded known-good reference outputs — here `ToyFlightSimulatorTests/Physics/Baselines/*.json` —
   that later runs are diffed against) for the current physics behavior, plus the verification protocol
   Phase A will follow against them.

**Non-goals (deferred):** `WorldCollider` + narrow phase (Phase A), any `RigidBody.colliders` storage
(Phase A), strut visualization as `Line`s (Phase B, when `SuspensionStrut` exists), iOS menu toggle for
the overlay (X-key macOS only for now), a depth-disabled x-ray/wireframe overlay *pass* (a real
render-path change touching multiple renderers — the hull-hidden mode in 0.4 covers the underfit-tuning
need without one).

### Deviations from the research docs (deliberate, small)

| Deviation | Why |
|---|---|
| The **data-only half of A1** (`ColliderShape`, `ColliderGroup`, `LocalCollider`) is pulled forward into Phase 0 | The overlay's entire purpose is rendering *proposed specs* before physics exists; defining the real vocabulary now means the overlay and specs are written once, against the final types. Phase A's A1 shrinks to: add `WorldCollider`, the reserved `material` field, and the `RigidBody` integration. |
| `RigidBody` + `SphereRigidBody`/`PlaneRigidBody` gain explicit **`init(detachedAt:)` standalone inits** | Not in either research doc. Required for a Metal-free parity harness: the current narrow phase force-casts to these `final` classes (`PhysicsWorld.collided`), so `TestRigidBody` doubles cannot traverse the collision path, and the production inits demand a non-optional `GameObject` (→ Metal). Production call sites keep the non-optional inits; attached-body behavior (including the tested released-weak fallbacks) is untouched. |
| Overlay also draws the **legacy collision sphere** (yellow) | One glance shows what the compound replaces — directly motivates spec tuning. Costs ~10 lines. |
| Overlay gets a **hull-hidden mode** backed by a small `SceneManager` hide/unhide hook | Not in the research docs' overlay sketch. Depth-tested translucency cannot reveal an underfit collider (see 0.4); reliable visual fitting is Phase 0's main purpose, so the tool must be able to show volumes unoccluded. Chosen over a depth-disabled x-ray *render pass* because it reuses the existing registration machinery and touches zero renderers. |
| Struts-as-`Line`s omitted from the Phase 0 overlay | Combined doc §4.1 mentions them, but strut specs are Phase B data (`SuspensionStrut`); drawing them before the type exists would invent throwaway structure. The overlay grows a strut layer in Phase B. |

---

## Step 0.1 — Collider vocabulary, data-only ✅

- [x] New file `ToyFlightSimulator Shared/Physics/Collision/ColliderShape.swift` (add to all three app targets, like the rest of Shared)

Taken verbatim from the original research doc §2.3, minus `WorldCollider` (Phase A — it's narrow-phase
output, nothing in Phase 0 consumes it) and minus the reserved `material` field (Phase A):

```swift
import simd

/// Convex collision primitives, in the cost order every surveyed engine
/// documents (sphere < capsule < box). Dimensions are authored in the owning
/// model's post-import local space — which meterization makes METERS — and
/// multiplied by the GameObject's uniform scale (1.0 for meterized aircraft)
/// when world-space colliders are computed.
enum ColliderShape: Equatable {
    /// Ball of the given radius.
    case sphere(radius: Float)
    /// Segment along local Y from -halfHeight to +halfHeight, inflated by
    /// radius (total height = 2·(halfHeight + radius)). Orient with the
    /// collider's localRotation (e.g. Y→Z for a fuselage along +Z).
    case capsule(radius: Float, halfHeight: Float)
    /// Oriented box with the given half extents.
    case box(halfExtents: float3)

    func scaled(by s: Float) -> ColliderShape { ... }

    /// Debug validation: every dimension finite and > 0 (capsule halfHeight
    /// may be 0 — that's a legal sphere-equivalent). Asserted in
    /// LocalCollider.init and unit-tested per authored spec.
    var hasFinitePositiveDimensions: Bool { ... }
}

/// Which functional part of the object a collider represents ...
enum ColliderGroup { case airframe, landingGear, structure }

/// One primitive rigidly attached to a body at a local offset — the per-child
/// entry of a compound (Bullet btCompoundShape child, Unity child collider,
/// Jolt compound sub-shape).
struct LocalCollider {
    var name: String
    var shape: ColliderShape
    var localPosition: float3
    var localRotation: simd_quatf
    var group: ColliderGroup
    /// Cheap runtime on/off (Jolt MutableCompoundShape's role).
    var isEnabled: Bool

    init(...) {
        assert(shape.hasFinitePositiveDimensions,
               "Collider '\(name)' has non-finite or non-positive dimensions")
        ...
    }
}
```

Phase A will append to this file (`WorldCollider`, `material`), not restructure it.

> **Addendum (2026-07-19):** Step 0.1 is implemented, with one improvement over the pseudocode above: a documented `simd_quatf.identity` constant now lives in `Math/Transform.swift` (alongside the existing `float4x4.identity`), and `LocalCollider.localRotation`'s default reads `.identity` instead of the raw `simd_quatf(real: 1, imag: .zero)` spelling — which existed only because simd ships no identity-quaternion constant. (Related footgun, documented on the constant: the auto-imported `simd_quatf()` default init is the invalid ZERO quaternion — never use it.) Later phases should spell identity rotations as `.identity` too. Target membership is automatic (the project uses filesystem-synchronized folders), so the "add to all three app targets" note in 0.1 is a no-op.

> **Addendum (2026-08-27):** `hasFinitePositiveDimensions` + the `LocalCollider.init` assert are a
> review-driven addition (landed with the 0.2 re-author); the 2026-07-19 implementation predates them.

## Step 0.2 — Placeholder aircraft specs ✅

- [x] New file `ToyFlightSimulator Shared/Physics/Collision/AircraftColliderSpec.swift`
  *(originally landed 2026-07-20 in pre-meterization model units; re-authored in meters 2026-08-27 —
  numbers remain placeholders until overlay-tuned in 0.5)*

Mirrors the `AircraftThumbnailSpec.spec(for:)` pattern (one spec per `AircraftType`, central file).
Phase 0 authors **only** the CGTrader F-22 (the default player aircraft); other types return `[]` — the
overlay shows their legacy sphere and logs "no compound spec yet" rather than us inventing numbers we
can't eyeball this phase. The switch is **exhaustive with no `default`** (same convention as
SceneManager's registration switches): adding an `AircraftType` case forces a conscious authored-or-empty
decision here at compile time.

**Units:** dimensions and offsets are post-import engine-local units, which meterization
(`realWorldLength: 18.92` in `ModelLibrary.makeLibrary()`) makes **meters**. `FlightboxWithPhysics`
builds aircraft at scale 1.0, so world meters = spec meters × `uniformScale` = spec meters. The
placeholder numbers are the pre-meterization values × 3 (the scale the old contract assumed), with the
fuselage capsule then stretched to span nose→tail — real F-22: length 18.92 m, wingspan 13.56 m:

```swift
private static let f22CGTrader: [LocalCollider] = [
    LocalCollider(name: "fuselage",
                  // Total 2·(8.1 + 1.35) = 18.9 m — spans nose→tail (real 18.92 m).
                  shape: .capsule(radius: 1.35, halfHeight: 8.1),
                  localPosition: [0, 0.3, 0.6],
                  // Capsule axis is local Y; rotate Y→Z so it runs nose–tail.
                  localRotation: simd_quatf(angle: .halfPi, axis: X_AXIS),
                  group: .airframe),
    LocalCollider(name: "wings",
                  // 13.2 m span vs 13.56 m real wingspan.
                  shape: .box(halfExtents: [6.6, 0.18, 2.7]),
                  localPosition: [0, 0.15, -1.2],
                  group: .airframe),
    LocalCollider(name: "empennage",
                  shape: .box(halfExtents: [3.0, 1.35, 1.5]),
                  localPosition: [0, 1.05, -6.6],
                  group: .airframe),
]
```

Tuning these numbers against the model **is** a Phase 0 exit criterion; the tuned values get committed
here with a short comment noting they were overlay-verified.

> **Addendum (2026-07-20, historical):** the original landing settled two spellings that still hold — use
> `.halfPi` / `X_AXIS` (documented constants) rather than raw `.pi / 2, axis: [1, 0, 0]`, and no per-file
> `import simd` is needed anywhere in the target (the bridging header `TFSCommon.h` imports
> `<simd/simd.h>` target-wide). The model-unit numbers that landing carried (capsule total 5.7 units ≈
> 66% of the fuselage) are superseded by the meter re-author above.

## Step 0.3 — Small support APIs (Node / GameObject) ✅

- [x] `Node.setRotation(_ q: simd_quatf)` — the overlay must pose children from `LocalCollider.localRotation`. One line through the existing `rotationMatrix` setter.
- [x] `Node.uniformScale` — the units-contract accessor (combined doc §4.1), written once here, reused by Phase A's `worldColliders(frame:)`:

```swift
/// Uniform-scale contract for physics colliders: spec dimensions are model
/// units, world meters = model units × this. Debug-asserts the scale is
/// actually uniform so a stray setScale(x,y,z) can't silently skew colliders.
var uniformScale: Float { ... }
```

- [x] `GameObject.init(name:model:)` — capsule colliders need **bespoke mesh dimensions** (a capsule cannot be non-uniformly scaled without distorting its hemispherical caps). Mirrors `init(name:modelType:)` minus the library lookup. Mesh construction on the update thread is established practice (scene resets rebuild whole scenes there).

> **Addendum (2026-07-20):** Step 0.3 is implemented, with one **correction** to the original text: the claim that the `rotationMatrix` setter "handles the dirty-flagging" was wrong — that setter was a bare `_rotationMatrix` store, so the one-line `setRotation(_:)` silently never took effect (the cached local/world matrices were never invalidated). Fixed at the root: `Node.rotationMatrix`'s setter now routes through `updateModelMatrixAndMarkTransformDirty`, which also repairs a latent order-dependence in `F18.weaponReleaseSetup` (its direct `rotationMatrix =` assignment only worked because the `setScale` on the next line happened to dirty the node). `setRotation(_ q:)` additionally calls `afterRotation()` so both `setRotation` overloads fire the subclass hook identically. macOS Debug build green with 0.3 in the tree. **(2026-08-27:** these fixes landed without tests — 0.8 now includes NodeTests pinning both the quaternion overload and direct `rotationMatrix =` dirty propagation.)

## Step 0.3b — Scene-graph ownership fix: `Node.parent` becomes `weak` *(added 2026-08-27)* ✅

- [x] `Node.parent` → `weak var parent: Node?` *(landed 2026-08-28, same commit as 0.4)*
- [x] `SubMeshGameObject.parentMeshGameObject` → `weak` (same commit — it's the same class of back-reference)
- [x] Back-reference audit + deallocation tests (below) — landed 2026-08-28 as `NodeOwnershipTests`
  (0.8): detached island, 3-deep detached chain, reparent survival, weak zeroing — all four green

> **Addendum (2026-08-28):** the two weak flips landed with 0.4 (whose lifecycle rules assume them). A
> third back-reference of the same class surfaced while landing 0.4 and was flipped in the same commit:
> `Mesh.parentModel` (strong, and **write-only** — no reader anywhere in the tree) made every
> Model ↔ Mesh pair a retain cycle. Library models mask it (process-lifetime cache), but 0.4's bespoke
> capsule volumes are the first runtime-built one-off Models — each overlay show would have leaked a
> Model + CapsuleMesh (MTLBuffers included) per cycle. `NodeOwnershipTests` remain owed before 0.3b is
> done. *(Landed 2026-08-28 — all four green; see 0.8. Step 0.3b ✅.)*

**Why this is in Phase 0:** the overlay parents render-only volumes to the aircraft, and its lifecycle
rules (0.4) depend on what happens to a detached subtree. Today `Node.parent` is **strong**
(Node.swift), so parent ↔ child references form a retain cycle in every subtree with ≥ 2 nodes.
`SceneManager.RemoveObject(prevAc)` detaches the aircraft from the scene root and unregisters the
subtree, but the internal aircraft ↔ afterburner (and aircraft ↔ overlay-volume) links survive — the
island never deallocates. `GameScene.teardownScene()` has the same hole: `removeAllChildren()` nils
`parent` for *top-level* children only. Net: **every aircraft swap and every scene reset currently leaks
the old aircraft subtree**, per-instance afterburner particle pools included. The fix is the standard
scene-graph ownership direction: parents own children (strong `children` array), children point back
weakly.

Audit checklist (call sites that must keep their subject alive by other means — all verified owners
exist today, the audit re-confirms at implementation time):
- `GameScene` root: owned by `SceneManager.CurrentScene` (static) ✓
- Cameras: `CameraManager` registry array owns them; scenes also hold `attachedCamera`/`debugCamera`
  properties ✓ (`AttachedCamera.attach(to:)` detaches-then-reattaches; unaffected)
- Lights: `LightManager` + scene child both hold them ✓
- Overlay volumes: `ColliderDebugOverlay.volumes` while shown; aircraft's `children` while attached ✓
- `SubMeshGameObject.parentMeshGameObject`: with `Node.parent` weak, this **strong** back-reference
  would become the F-18's remaining cycle (aircraft.children → SMGO strong, SMGO.parentMeshGameObject →
  aircraft strong) — hence it flips to weak in the same commit. The parent F-18 is owned by the scene.
- Weapons/`SubMeshGameObject`s that reparent to the scene root on release: scene owns them post-release ✓

Tests (Metal-free, plain `Node`s — the cycle mechanics don't need GameObjects; new Swift Testing suite
`NodeOwnershipTests`, `.tags(.gameObjects)`):
- parent + child island: drop the last external strong ref to the parent → BOTH deallocate (this fails
  before the fix — it's the red test that motivates the change)
- 3-deep chain detached from a root: island deallocates
- child removed via `removeChild` then re-added elsewhere: parent pointer correct, no premature dealloc
  while the new parent lives
- `parent` reads nil after the parent deallocates (weak zeroing observed, no crash)

**Behavior note:** this is the one deliberate behavior change in Phase 0 — detached subtrees now
deallocate (and their `deinit`s run). Nothing in the tree relies on resurrecting a detached-but-leaked
subtree (verified by audit); the existing swap/reset flows only ever re-add freshly constructed objects.

## Step 0.4 — The collider debug overlay ✅

*(2026-08-27: fleshed out from sketch to full implementation code — the earlier draft left `cycle`
bodiless and the wiring as fragments. Code below is presented per file, path first. One naming
correction along the way: the discrete command is `CycleColliderOverlay`, not `ToggleColliderOverlay` —
it's a three-state cycle, and `CycleCamera` already established the verb.)*

Files touched, in landing order (each has a full listing below):

- [x] **File 1 (edit):** `ToyFlightSimulator Shared/Managers/SceneManager.swift` —
  `SetRenderableHidden(_:_:)` hide/unhide hook (single node, non-recursive) + `rehideExtractedSubmeshes(of:)`
- [x] **File 2 (new):** `ToyFlightSimulator Shared/Physics/Debug/ColliderDebugOverlay.swift` —
  `ColliderOverlayMapping` (pure, unit-tested) + `ColliderDebugOverlay` (scene-graph work)
- [x] **File 3 (edit):** `ToyFlightSimulator Shared/Managers/InputManager.swift` —
  `DiscreteCommand.CycleColliderOverlay` + X-key mapping
- [x] **File 4 (edit):** `ToyFlightSimulator Shared/Scenes/GameScene.swift` —
  overlay ownership, `playerAircraftType`, X handler in `doUpdate`, reset in `teardownScene`
- [x] **File 5 (edit):** `ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift` —
  re-home hook at the end of `applyAircraftSwap`

### Registration rules this must obey (the part that's easy to get wrong)

- Overlay volumes are parented to the **aircraft**, not the scene root. `GameScene.addChild` is the only
  auto-registering path, so the overlay must call `SceneManager.Register(volume)` itself after
  `aircraft.addChild(volume)`.
- `setColor` with alpha < 1 **before** registering — `Register` resolves `objectType` (→ transparent
  collection) at registration time.
- User-initiated hide (X back to off) must use `removeFromScene()` (removeChild + Unregister) per the
  scene-graph rule; a bare `removeChild` leaves frozen ghost renderables.
- Aircraft swap: `applyAircraftSwap` calls `SceneManager.RemoveObject(prevAc)`, which unregisters the
  prev aircraft's **whole subtree** — overlay volumes included. The overlay then drops its references
  and re-applies its mode to the new aircraft. With 0.3b in place, dropping the refs is also what lets
  the detached island (old aircraft + volumes) deallocate; calling `removeFromScene()` on those stale
  refs would be redundant scene-graph surgery on an already-dead subtree — don't.
- Scene teardown (`Cmd+R` / menu reset): same story via `TeardownScene`; the overlay resets its
  bookkeeping (mode → off; the rebuilt scene starts clean).
- Hull-hidden state is exactly "the aircraft's own renderable registration is temporarily absent" (see
  the hook below), so subtree Unregister during a swap and wholesale teardown both handle it with **no
  special cases** — an unregistered node is a no-op for both.

### File 1 — SceneManager: the hull-hide hook

**Path:** `ToyFlightSimulator Shared/Managers/SceneManager.swift` *(edit — add the two methods below
inside `SceneManager`, alongside the existing `Register`/`Unregister` block)*

Depth-tested translucent volumes reveal **overfit** (portions protruding from the hull) but not
**underfit**: a volume fully inside the hull is occluded from outside, and from inside the volume its
faces are back-face-culled (global clockwise-front + cull-back), so flying the camera through doesn't
help. Since reliable visual fitting is this phase's main purpose, the overlay needs to show volumes
unoccluded — done by temporarily hiding the hull, not by a new render pass:

```swift
    // MARK: - Debug-overlay support (ColliderDebugOverlay)

    /// Temporarily removes ONE node's own renderable registration
    /// (non-recursive — children like afterburner emitters stay registered
    /// and drawn). Reuses the marker-captured add/remove machinery, so
    /// "hidden" is indistinguishable from "not currently registered": subtree
    /// Unregister (aircraft swap) and TeardownScene need no special cases —
    /// an unregistered node is a no-op for both. Update-thread only, like all
    /// registration traffic.
    static func SetRenderableHidden(_ gameObject: GameObject, _ hidden: Bool) {
        if hidden {
            // Already hidden, or never registered → no-op.
            guard let marker = gameObject.registeredObjectType else { return }
            remove(gameObject, from: marker)
            gameObject.registeredObjectType = nil
        } else if gameObject.registeredObjectType == nil {
            Register(gameObject)
            rehideExtractedSubmeshes(of: gameObject)
        }
    }

    /// F-18 caveat: un-hiding can rebuild the model's ModelData from scratch
    /// (CreateModelData), which resurrects submeshes that SubMeshGameObject
    /// registration had hidden in the parent's draw lists — that side effect
    /// is deliberately not undone on unregister, and re-registering the
    /// PARENT doesn't re-run it. So re-run the hide pass for every extracted
    /// submesh in the subtree. hideSubmeshInParentModel is idempotent (a
    /// submesh already absent from the opaque lists is skipped), so
    /// over-calling is harmless — e.g. when a second live instance of the
    /// same Model kept the ModelData alive and nothing was actually rebuilt.
    private static func rehideExtractedSubmeshes(of gameObject: GameObject) {
        for node in subtreeNodes(of: gameObject) {
            if let subMeshChild = node as? SubMeshGameObject {
                hideSubmeshInParentModel(subMeshChild)
            }
        }
    }
```

Two corrections to the earlier sketch, both simplifications:
- `hideSubmeshInParentModel` **stays `static private`** — the sketch said "exposed internally" because
  it imagined the overlay calling it, but the re-hide pass lives inside `SceneManager` itself, so
  nothing outside the type needs it.
- The subtree walk uses the existing pure `subtreeNodes(of:)` instead of the sketch's
  `children.compactMap` — extracted submeshes nested deeper than direct children (mirroring how
  `registerChildObject` recurses grandchildren) are covered too.

This must be handled now even though only the F-22 has a spec this phase: without it, toggling
hull-hide on an F-18 would double-draw its control surfaces.

### File 2 — the overlay itself

**Path:** `ToyFlightSimulator Shared/Physics/Debug/ColliderDebugOverlay.swift` *(new file; target
membership is automatic — the project uses filesystem-synchronized folders, per the 0.1 addendum)*

Two types in one file. `ColliderOverlayMapping` is the pure, Metal-free half — per the
Metal-free-test-design rule, all the shape→transform math the tests need to hit lives here
(`ColliderOverlayMappingTests`, 0.8) without constructing GameObjects. `ColliderDebugOverlay` does the
scene-graph work and is deliberately **not** unit-tested (constructing GameObjects pulls in Metal); it
also carries `logWorldDimensions`, which is step 0.5's units log. `import Foundation` is for
`String(format:)` only (simd comes in target-wide via the bridging header). Complete file:

```swift
//
//  ColliderDebugOverlay.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/27/26.
//

import Foundation

/// Maps ColliderShape (meters) onto the engine's debug meshes.
/// Child transforms are in the PARENT's model space — the parent's uniform
/// scale (1.0 for meterized aircraft) composes via the normal matrix
/// hierarchy, so the mesh-facing functions never see the scale.
/// (worldDimensions reports WORLD sizes for the 0.5 units log, so it alone
/// takes the parent scale as a parameter.)
enum ColliderOverlayMapping {
    /// ModelType.Sphere is ObjModel("sphere"), radius exactly 1.0 (measured —
    /// see meter_scale_units_research_2026-07-20.md). NOT SphereMesh, whose
    /// MDLMesh(sphereWithExtent:) call is radius-semantics and builds 2× the
    /// requested size (measured 2026-08-27; latent, pinned by MeshBoundsTests).
    static let sphereMeshRadius: Float = 1.0
    /// ModelType.Cube wraps CubeMesh(size: 1.0) = MDLMesh(boxWithExtent: [1,1,1]);
    /// box extent IS full extent (measured) → side 1.0, half-extent 0.5.
    static let cubeMeshSize: Float = 1.0

    /// Scale for a volume built from the unit meshes above. Capsules return
    /// .one: their mesh is built bespoke at exact dimensions and must never
    /// be scaled (non-uniform scale distorts the hemispherical caps).
    static func childScale(for shape: ColliderShape) -> float3 {
        switch shape {
            case .sphere(radius: let r):
                return float3(repeating: r / sphereMeshRadius)
            case .box(halfExtents: let he):
                // Per-axis; non-uniform is fine for render-only children.
                return (2.0 * he) / cubeMeshSize
            case .capsule:
                return .one
        }
    }

    /// MEASURED (2026-08-27, ModelIO on macOS 26; locked by MeshBoundsTests):
    /// MDLMesh(capsuleWithExtent: [x, y, z]) treats x/z as the RADIUS (not
    /// diameter) and y as the TOTAL cap-to-cap length — extent [2,6,2] yields
    /// bounds ±[2,3,2]; [1,2,1] degenerates to the unit sphere. So
    /// CapsuleMesh(radius:length:) builds exactly radius r, total length L,
    /// and a collider capsule (halfHeight = cylinder half-segment) maps as:
    static func capsuleMeshParams(radius: Float, halfHeight: Float) -> (radius: Float, length: Float) {
        (radius, 2 * (halfHeight + radius))
    }

    /// Axis-aligned LOCAL dimensions of a collider × the parent's uniform
    /// scale, for the units log (0.5). Deliberately not "worldSpan": it
    /// ignores rotation/translation, so it reports sizes, not extents.
    /// longestAxisMeters is the 0.5 sanity anchor (fuselage capsule → 18.9).
    static func worldDimensions(of collider: LocalCollider,
                                parentScale: Float) -> (dims: String, longestAxisMeters: Float) {
        switch collider.shape.scaled(by: parentScale) {
            case .sphere(radius: let r):
                return ("sphere ø \(formatMeters(2 * r))", 2 * r)
            case .capsule(radius: let r, halfHeight: let hh):
                let total = 2 * (hh + r)   // the same cap-to-cap span capsuleMeshParams renders
                return ("capsule ø \(formatMeters(2 * r)) × \(formatMeters(total)) end-to-end", total)
            case .box(halfExtents: let he):
                let full = 2 * he
                return ("box \(formatMeters(full.x)) × \(formatMeters(full.y)) × \(formatMeters(full.z))",
                        max(full.x, full.y, full.z))
        }
    }

    private static func formatMeters(_ value: Float) -> String {
        String(format: "%.2f m", value)
    }
}

/// Render-only volumes visualizing an aircraft's collider spec (red) and its
/// legacy physics sphere (yellow). Owns no physics state; update-thread only
/// (all scene-graph mutation happens in doUpdate — same rule as CycleCamera).
///
/// X cycles: off → volumesOverHull (translucent, catches OVERFIT via
/// protrusion) → volumesOnly (hull hidden, catches UNDERFIT — end caps and
/// silhouettes visible; A/B against volumesOverHull for placement) → off.
final class ColliderDebugOverlay {
    enum Mode {
        case off
        case volumesOverHull
        case volumesOnly

        var next: Mode {
            switch self {
                case .off:             return .volumesOverHull
                case .volumesOverHull: return .volumesOnly
                case .volumesOnly:     return .off
            }
        }
    }

    /// Research doc §2.7 colors. Alpha < 1 is load-bearing: it makes
    /// isTransparent true, which routes the volumes into the transparent
    /// collection at registration — hence setColor BEFORE Register.
    static let specColor: float4   = [1, 0, 0, 0.3]
    static let legacyColor: float4 = [1, 1, 0, 0.25]

    private(set) var mode: Mode = .off
    private var volumes: [GameObject] = []
    private weak var host: GameObject?

    /// X-key entry point (GameScene.doUpdate): advance the mode on `target`.
    func cycle(on target: GameObject, spec: [LocalCollider]) {
        assert(mode == .off || host === target,
               "[ColliderDebugOverlay] host changed without hostWasReplaced — swap wiring is missing")
        apply(mode.next, on: target, spec: spec)
    }

    /// Aircraft swap (FlightboxWithPhysics.applyAircraftSwap): the old host's
    /// subtree was already detached AND unregistered wholesale by
    /// SceneManager.RemoveObject — our volumes included, and a hidden hull
    /// needed no special case ("hidden" is just "not registered"). Dropping
    /// our refs is what lets the detached island (old aircraft + volumes)
    /// deallocate (0.3b); calling removeFromScene() on the stale refs would
    /// be redundant scene-graph surgery on an already-dead subtree — don't.
    /// Then re-apply the surviving mode to the new host.
    func hostWasReplaced(by newTarget: GameObject?, spec: [LocalCollider]) {
        let previousMode = mode
        reset()
        if previousMode != .off, let newTarget {
            apply(previousMode, on: newTarget, spec: spec)
        }
    }

    /// Bookkeeping-only clear — no scene-graph calls. Callers guarantee the
    /// volumes' subtree is already gone (swap) or being torn down wholesale
    /// (teardownScene).
    func reset() {
        volumes.removeAll()
        host = nil
        mode = .off
    }

    /// Single mutation point for mode transitions. Hull hidden-ness is
    /// applied LAST on the way in and FIRST on the way out, so no partial
    /// transition can strand a hidden aircraft.
    private func apply(_ newMode: Mode, on target: GameObject, spec: [LocalCollider]) {
        guard newMode != mode else { return }

        if newMode == .off {
            SceneManager.SetRenderableHidden(target, false)   // un-hide FIRST
            for volume in volumes {
                // Per the scene-graph rule: removeChild + Unregister. A bare
                // removeChild would leave frozen ghost renderables.
                volume.removeFromScene()
            }
            reset()
            return
        }

        if mode == .off {   // entering: build, attach, register, log
            host = target
            buildVolumes(on: target, spec: spec)
            logWorldDimensions(spec, on: target)
        }
        mode = newMode

        // LAST (see doc comment above):
        SceneManager.SetRenderableHidden(target, newMode == .volumesOnly)
    }

    /// One volume per enabled spec collider, plus the yellow legacy-sphere
    /// ghost. Ordering rules (see "Registration rules" above): setColor
    /// BEFORE Register; target.addChild — plain Node reparenting, because
    /// GameScene.addChild is the only auto-registering path and the volumes
    /// hang off the aircraft, not the scene root — THEN SceneManager.Register.
    private func buildVolumes(on target: GameObject, spec: [LocalCollider]) {
        if spec.isEmpty {
            print("[ColliderDebugOverlay] no compound spec for \(target.getName()) yet — legacy sphere only")
        }

        for collider in spec where collider.isEnabled {
            let volume = makeVolume(for: collider.shape, name: "ColliderOverlay_\(collider.name)")
            volume.setColor(Self.specColor)
            volume.setPosition(collider.localPosition)
            volume.setRotation(collider.localRotation)
            volume.setScale(ColliderOverlayMapping.childScale(for: collider.shape))
            attach(volume, to: target)
        }

        // The legacy physics sphere sits on the body origin (SphereRigidBody
        // has no local offset), so the ghost keeps the default zero position.
        // collisionRadius is WORLD meters and the ghost is a CHILD of the
        // aircraft, so the parent's scale divides back out — 1.0 for
        // meterized aircraft, kept explicit so a deliberately scaled aircraft
        // still ghosts correctly.
        if let sphereBody = target.rigidBody as? SphereRigidBody {
            let ghost = GameObject(name: "ColliderOverlay_legacySphere", modelType: .Sphere)
            ghost.setColor(Self.legacyColor)
            ghost.setScale(sphereBody.collisionRadius /
                           (ColliderOverlayMapping.sphereMeshRadius * target.uniformScale))
            attach(ghost, to: target)
        }
    }

    private func attach(_ volume: GameObject, to target: GameObject) {
        target.addChild(volume)
        SceneManager.Register(volume)
        volumes.append(volume)
    }

    /// Sphere/box volumes reuse the unit library models; capsules get a
    /// bespoke mesh at exact dimensions through GameObject(name:model:)
    /// (0.3). Mesh construction on the update thread is established practice
    /// — scene resets rebuild whole scenes there.
    private func makeVolume(for shape: ColliderShape, name: String) -> GameObject {
        switch shape {
            case .sphere:
                // OBJ sphere, radius exactly 1.0 — never SphereMesh (2× quirk).
                return GameObject(name: name, modelType: .Sphere)
            case .box:
                return GameObject(name: name, modelType: .Cube)
            case .capsule(radius: let radius, halfHeight: let halfHeight):
                let p = ColliderOverlayMapping.capsuleMeshParams(radius: radius, halfHeight: halfHeight)
                let mesh = CapsuleMesh(radius: p.radius, length: p.length)
                return GameObject(name: name, model: Model(name: name, mesh: mesh))
        }
    }

    /// Step 0.5's units log, printed on every overlay show. Sanity anchor:
    /// the fuselage capsule must read ≈ 18.90 m at scale 1.0 (real F-22:
    /// 18.92 m).
    private func logWorldDimensions(_ spec: [LocalCollider], on target: GameObject) {
        guard !spec.isEmpty else { return }
        let scale = target.uniformScale
        print("[ColliderDebugOverlay] \(target.getName()) collider world dimensions (uniformScale \(scale)):")
        for collider in spec where collider.isEnabled {
            let (dims, _) = ColliderOverlayMapping.worldDimensions(of: collider, parentScale: scale)
            print("  \(collider.name): \(dims)")
        }
        if let sphereBody = target.rigidBody as? SphereRigidBody {
            print("  legacy sphere: ø \(String(format: "%.2f m", 2 * sphereBody.collisionRadius)) (world)")
        }
    }
}
```

Implementation notes, tied to the registration rules above:
- `cycle`'s assert pins the wiring invariant: a host change while visible must arrive via
  `hostWasReplaced`, never via `cycle` — otherwise volumes would be attached to a second aircraft
  while the first still holds the old set.
- The loop applies `childScale` uniformly; for capsules it returns `.one`, so the bespoke mesh is
  never scaled and the loop needs no special case.
- The mode-`.off` branch un-hides against `target` (== `host` by the assert) *before* touching the
  volumes, mirroring "hull state LAST" on the way in — whichever direction a future edit bails out
  of, the aircraft is never left hidden.
- The scene-teardown path never reaches `apply`: `GameScene.teardownScene` calls bare `reset()`
  because the whole subtree (and every batched collection) is being dropped wholesale anyway.

### File 3 — InputManager: the X key

**Path:** `ToyFlightSimulator Shared/Managers/InputManager.swift` *(edit — two touch points)*

Key: **X** (free; taken today: p l space n m j f g c w a s d q e y h arrows, Cmd+R). Keyboard-only —
no controller/joystick mapping (debug affordance); `HasDiscreteCommandDebounced` already skips devices
with no mapping for a command, so nothing else changes.

The `DiscreteCommand` enum gains one case, grouped with the other Toggle*/Cycle* commands:

```swift
enum DiscreteCommand {
    case FireMissileAIM9
    case FireMissileAIM120
    case DropBomb
    case JettisonFuelTank

    case ResetLoadout

    case ToggleFlaps
    case ToggleGear
    case CycleCamera
    /// Collider debug overlay: off → volumesOverHull → volumesOnly → off.
    case CycleColliderOverlay

    case Pause
    case ClickSelect
}
```

and `keyboardMappingsDiscrete` gains one entry:

```swift
    nonisolated(unsafe) private static var keyboardMappingsDiscrete: [DiscreteCommand: Keycodes] = [
        .Pause: .p,
        .ResetLoadout: .l,
        .FireMissileAIM9: .space,
        .FireMissileAIM120: .n,
        .DropBomb: .m,
        .JettisonFuelTank: .j,
        .ToggleFlaps: .f,
        .ToggleGear: .g,
        .CycleCamera: .c,
        .CycleColliderOverlay: .x
    ]
```

### File 4 — GameScene: ownership, X handler, teardown

**Path:** `ToyFlightSimulator Shared/Scenes/GameScene.swift` *(edit — three touch points)*

The base class owns the overlay so any scene that sets `playerAircraft` + `playerAircraftType` gets
the X cycle for free. The handler runs on the **update thread** via the `CycleCamera` debounce pattern
in `doUpdate` — NOT in `MacGameUIView`'s main-thread timer (scene-graph mutation must stay on the
update thread).

Properties, next to the existing `playerAircraft`:

```swift
    internal var playerAircraft: Aircraft? = nil

    /// Keys the collider overlay's spec lookup. Scenes that assign
    /// playerAircraft set this alongside it (FlightboxWithPhysics: on every
    /// swap). nil ⇒ the X key is a no-op in this scene.
    internal var playerAircraftType: AircraftType? = nil

    /// Debug collider overlay (X key) — base-class-owned so every
    /// player-aircraft scene gets the cycle without per-scene wiring.
    let colliderOverlay = ColliderDebugOverlay()
```

In `doUpdate()`, next to the `CycleCamera` handler:

```swift
        InputManager.HasDiscreteCommandDebounced(command: .CycleColliderOverlay) {
            // Update-thread scene-graph mutation, same rule as CycleCamera.
            guard let aircraft = playerAircraft, let type = playerAircraftType else { return }
            colliderOverlay.cycle(on: aircraft, spec: AircraftColliderSpec.spec(for: type))
        }
```

`teardownScene()` gains its final line:

```swift
    func teardownScene() {
        SceneManager.Paused = true
        LightManager.RemoveAllLights()
        CameraManager.RemoveAllCameras()
        removeAllChildren()
        // The subtree is going away wholesale (SceneManager.TeardownScene
        // clears every batched collection right after this returns) —
        // bookkeeping-only reset, no scene-graph surgery on the dying
        // subtree. With 0.3b, dropping these refs is what lets the detached
        // volumes deallocate. The rebuilt scene starts with the overlay off.
        colliderOverlay.reset()
    }
```

### File 5 — FlightboxWithPhysics: the swap hook

**Path:** `ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift` *(edit — end of
`applyAircraftSwap(_:installEntities:)`)*

Two lines after the existing `addChild(playerAircraft)` — the order matters: `hostWasReplaced`
re-registers volumes on the new aircraft and may re-hide its hull, so the aircraft must already be in
the scene graph. Existing tail of the method shown for placement:

```swift
            if let prevAc {
                SceneManager.RemoveObject(prevAc)
            }

            addChild(playerAircraft)

            // Overlay survives the swap in whatever mode it was in.
            // RemoveObject above already detached + unregistered the old
            // subtree (overlay volumes included); hostWasReplaced drops the
            // stale refs and re-applies the mode to the new aircraft.
            // buildScene's initial call runs with the overlay off, so this
            // reduces to bookkeeping there.
            playerAircraftType = aircraft
            colliderOverlay.hostWasReplaced(by: playerAircraft,
                                            spec: AircraftColliderSpec.spec(for: aircraft))
```

A depth-disabled x-ray/wireframe overlay *pass* (volumes visible through the hull simultaneously) stays
deferred — it's a genuine render-path change across four renderers; the two visible modes cover both
failure directions for tuning.

> **Addendum (2026-08-28) — landed.** All five files are in, macOS Debug build green, and the X cycle
> was verified visually in the running game (FlightboxWithPhysics). Notes from the landing:
> 1. **Naming deviation from the listing above (adopted, listing updated):** the cube constant is
>    `cubeMeshSize`, not `cubeMeshSide` — it mirrors the `CubeMesh(size:)` parameter it documents.
> 2. **Ordering deviation:** 0.4 landed before 0.6/0.7 (and with 0.3b's tests still owed). Allowed —
>    the overlay and parity tracks are declared independent; 0.3b's *code* (the part 0.4's lifecycle
>    rules assume) landed in the same commit.
> 3. **Extra fix:** `Mesh.parentModel` → `weak` (see the 0.3b addendum) so the bespoke capsule volume's
>    one-off Model actually deallocates when the overlay is cycled off.
> 4. The first landing had `logWorldDimensions` computing dimensions but not printing them; the print
>    statements were filled in during review. **0.5's in-app anchor check (fuselage ≈ 18.9 m in the
>    log) has therefore not run yet** — it needs one more in-app X press. *(Ran later that day — see
>    the 0.5 addendum; step 0.5 ✅.)*
> 5. The full exit-criterion-1 checklist (swap while visible, Cmd+R while visible, renderer switch,
>    ghost-free repeated cycling) is still open — only the basic cycle has been eyeballed so far.

## Step 0.5 — Units contract: sanity anchor + mesh-mapping regression ✅

**Contract (post-meterization):** collider dimensions and offsets are authored in post-import
engine-local units = **meters** (import folds `realWorldLength / nativeLength` into the basis transform;
`ModelLibrary` registers the CGTrader F-22 at 18.92 m). `Node.uniformScale` remains in the world-collider
math as an optional gameplay multiplier — every meterized aircraft runs at 1.0, and the debug assert
(uniformity) plus Phase A's `scaled(by:)` path keep colliders correct if a scene ever scales an aircraft
deliberately. The old "model units × 3.0 = world meters" contract is dead; nothing may reintroduce it.

- [x] `logWorldDimensions` (the code ships inside 0.4's `ColliderDebugOverlay`; this checkbox is the
  in-app verification — **ran 2026-08-28**, addendum below) prints, on every overlay show, one line per collider: name, shape,
  world-space dimensions (spec meters × `uniformScale`). **Sanity anchor:** fuselage capsule total
  = 2·(8.1 + 1.35)·1.0 = **18.9 m** against the real jet's 18.92 m. If the printed number and the
  on-screen capsule disagree with the model's visible nose-tail span, the spec numbers (or the import
  meterization) are wrong — fix before Phase A consumes them.
- [x] **Capsule mesh mapping settled by measurement, not by eye** *(2026-08-27)*:
  `MDLMesh(capsuleWithExtent: [x, y, z])` → x/z = radius, y = total cap-to-cap length (extent [2,6,2]
  bounds ±[2,3,2]; [1,5,1] → ±[1,2.5,1]; [1,2,1] → unit sphere). Box extent is full-extent
  (boxWithExtent [1,2,3] → ±[0.5,1,1.5]); sphere extent is radius-semantics (sphereWithExtent [2,2,2] →
  radius 2 — the latent `SphereMesh(radius:)` 2× quirk; the overlay uses the OBJ `.Sphere` model,
  radius 1.0, and must never use `SphereMesh`). The verdict is encoded in
  `ColliderOverlayMapping.capsuleMeshParams` = `(radius, 2·(halfHeight + radius))` and locked by a
  CPU-side bounding-box regression test (0.8 `MeshBoundsTests` — constructs `MDLMesh` with a nil
  allocator, no Metal, and asserts the three shapes' bounds), replacing the previously planned one-time
  visual calibration.
- [x] `Node.uniformScale` assertion active in debug builds (step 0.3) — this *is* the enforcement of the
  contract; Codex's full `assetToBodyMeters` transform stays deferred per combined doc §4.1.

> **Addendum (2026-08-28) — the in-app anchor check ran; step complete.** Method: a temporary
> auto-trigger on the update thread fired the same `colliderOverlay.cycle` call as the X handler once,
> ~4 s into a FlightboxWithPhysics run (keystroke injection isn't available headlessly — no
> Accessibility — and the X-key wiring itself was already verified visually in 0.4's landing; the
> trigger was reverted after the run, tree back to the 0.4 commit's state, rebuild green). Captured
> app stdout:
>
> ```
> [ColliderDebugOverlay] F-22_CGTrader collider world dimensions (uniformScale 1.0):
>   fuselage: capsule ø 2.70 m × 18.90 m end-to-end
>   wings: box 13.20 m × 0.36 m × 5.40 m
>   empennage: box 6.00 m × 2.70 m × 3.00 m
>   legacy sphere: ø 4.00 m (world)
> ```
>
> The fuselage line IS the sanity anchor (18.90 m at scale 1.0 vs the real jet's 18.92 m); every other
> line matches its spec arithmetic (wings 2·[6.6, 0.18, 2.7], empennage 2·[3.0, 1.35, 1.5], legacy
> sphere ø = 2 × the 2.0 m `collisionRadius`), the bespoke capsule mesh built cleanly on the update
> thread, and the `uniformScale` debug assert stayed quiet. The checkbox's escalation clause (printed
> number vs. on-screen capsule vs. the model's visible nose–tail span) is exit criterion 2's A/B
> eyeballing and stays open there.

## Step 0.6 — Metal-free parity enabler: explicit detached bodies (behavior-neutral) ✅

*(Redesigned 2026-08-27 — the original "relax inits to `GameObject?` + fallback storage" would have
silently changed tested behavior: `RigidBodyTests.rigidBodyToleratesNilGameObject` pins that an attached
body whose weak `gameObject` was released answers `getPosition() == .zero` and treats `setPosition` as a
no-op. Routing those through fallback storage flips both expectations and erases the distinction between
"intentional standalone body" and "attached body whose object died unexpectedly".)*

- [x] `Physics/World/RigidBody.swift`: explicit standalone mode (full implementation — transcribe as-is)
  *(landed 2026-08-28 — see the addendum at the end of this step for the one transcription bug caught in review)*

```swift
/// Standalone-mode storage (parity-harness bodies built with init(detachedAt:)).
/// Attached bodies never touch this: a released weak gameObject keeps the
/// tested .zero / no-op fallbacks — that state is a bug signal, not a mode.
private let isStandalone: Bool
private var standalonePosition: float3 = .zero

// The attached designated init gains exactly ONE line, at the end of its
// stored-property block; everything else — parameters, defaults, the trailing
// back-registration — stays byte-identical:
internal init(gameObject: GameObject?, /* existing parameters unchanged */) {
    // ... existing stored-property assignments unchanged ...
    self.shouldApplyGravity = shouldApplyGravity
    self.isStandalone = false

    // Register with object this is attached to:
    gameObject?.rigidBody = self
}

/// Parity-harness bodies: the REAL physics classes, no GameObject, no Metal.
/// Internal — production code constructs attached bodies only.
///
/// A second DESIGNATED init on purpose. Delegating to init(gameObject:) is
/// impossible — `isStandalone` is a `let` that init assigns `false`, and a
/// delegating init can't reassign it — and extracting a shared private
/// designated init would mean rewriting the attached init, whose
/// released-weak fallback behavior is pinned by
/// RigidBodyTests.rigidBodyToleratesNilGameObject. Parameters mirror
/// init(gameObject:) exactly (same names, order, defaults; `detachedAt
/// position` stands in for `gameObject`), and both bodies repeat the full
/// stored-property block in the same order, so the two diff cleanly and a
/// future default-less stored property is a compile error in BOTH inits.
internal init(detachedAt position: float3,
              collisionShape: CollisionShape = .Sphere,
              collidedWith: Set<ObjectIdentifier> = [],
              mass: Float = 1,
              velocity: float3 = .zero,
              acceleration: float3 = .zero,
              force: float3 = .zero,
              restitution: Float = 1,
              isStatic: Bool = false,
              shouldApplyGravity: Bool = true) {
    self.gameObject = nil
    self.collisionShape = collisionShape
    self.collidedWith = collidedWith
    self.mass = mass
    self.velocity = velocity
    self.acceleration = acceleration
    self.force = force
    self.restitution = restitution
    self.isStatic = isStatic
    self.shouldApplyGravity = shouldApplyGravity
    self.isStandalone = true
    self.standalonePosition = position
    // Deliberately NO back-registration: there is no GameObject to attach
    // to. Harness code hands the body straight to PhysicsWorld
    // (addEntity/setEntities).
}

func setPosition(_ position: float3) {
    if isStandalone {
        standalonePosition = position
    }
    else {
        self.gameObject?.setPosition(position)
    }
}

func getPosition() -> float3 {
    isStandalone ? standalonePosition : (self.gameObject?.getPosition() ?? .zero)
}
```

- [x] `Physics/World/BasicRigidBodies.swift`: detached convenience inits on the `final` subclasses
  (production inits keep their **non-optional** `GameObject`) *(landed 2026-08-28, verbatim)*:

```swift
// SphereRigidBody
init(detachedAt position: float3, collisionRadius: Float = 1.0) {
    super.init(detachedAt: position)
    self.collisionRadius = collisionRadius
    self.collisionShape = .Sphere
}
// PlaneRigidBody
init(detachedAt position: float3, collisionNormal: float3 = [0, 1, 0]) {
    super.init(detachedAt: position)
    self.collisionNormal = collisionNormal.normalize()
    self.collisionShape = .Plane
}
```

Why this is required: the parity harness must drive the **real collision path** (`PhysicsWorld.collided`
/ `getCollisionData` force-cast to the `final` classes `SphereRigidBody`/`PlaneRigidBody`, so
`TestRigidBody` can't traverse it), and it must do so Metal-free (constructing any `GameObject` pulls in
`Assets.Models` → Metal; see the project's Metal-free-test-design rule). With detached bodies:
`SphereRigidBody.getAABB()` reads `getPosition()` + `collisionRadius`, `PlaneRigidBody.getAABB()` reads
`getPosition()` — both work on standalone storage, so broad phase, narrow phase, response, and both
solvers all run without a scene. (`getState()` still returns nil for standalone bodies — it needs the
node's basis vectors; the harness exercises collision/solver paths, not flight models.) Existing
`PhysicsWorldSmokeTests` (GameObject-backed) keep guarding the attached path; the released-weak tests
keep guarding the fallbacks.

> **Addendum (2026-08-28, landing):** hand-transcribed and verified against the spec block above.
> One transcription bug caught in review before anything ran: the detached init assigned
> `isStandalone = false` (copied from the attached init's line), which routes set/getPosition through
> the nil gameObject — every detached body would have sat at `.zero` forever and 0.7's goldens would
> have recorded flatlines. Fixed to `true`; the `RigidBodyTests` detached-mode tests (0.8) pin the
> position round-trip so the mistake can't recur silently. Attached-path and released-weak suites
> unchanged and green, as the redesign promised.

## Step 0.7 — Parity harness + golden baselines ✅

- [x] `ToyFlightSimulatorTests/TestSupport/SeededRandom.swift` — seedable `SplitMix64: RandomNumberGenerator`, **plus direct Float derivation** (Swift's default RNG is unseedable, and `Float.random(in:using:)`'s u64→Float mapping is a stdlib implementation detail — goldens outlive toolchains, so the harness owns the mapping):

```swift
/// SplitMix64 (Steele/Lea/Flood — the java.util.SplittableRandom mixer).
/// Tiny, seedable, and written out in full HERE so goldens never depend on
/// stdlib RNG internals. No imports needed.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension SplitMix64 {
    /// Uniform in [0, 1): top 24 bits → Float. Bypasses Float.random(in:using:).
    mutating func unitFloat() -> Float { Float(next() >> 40) * 0x1p-24 }
    mutating func float(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + (range.upperBound - range.lowerBound) * unitFloat()
    }
}
```

- [x] `ToyFlightSimulatorTests/TestSupport/Finite.swift` — add the `float3` overload the harness
  invariants use (the file currently covers only `SIMD4`/`float4x4`):

```swift
func allFinite(_ v: SIMD3<Float>) -> Bool {
    v.x.isFinite && v.y.isFinite && v.z.isFinite
}
```

- [x] `ToyFlightSimulatorTests/Physics/PhysicsParityTests.swift` — scenarios + runner + comparisons (`.tags(.physics)`, Swift Testing)
- [x] `ToyFlightSimulatorTests/Physics/Baselines/*.json` — committed goldens (test-target membership irrelevant; loaded via `#filePath`)

> **Addendum (2026-08-28, landing):** the harness landed as the implementation section below,
> transcribed as-is; all six goldens were recorded the same day (single_bounce ~20 KB each,
> head_on 19 KB, rest_latch 41 KB, cluster 84 KB, stress 180 KB of sortedKeys pretty JSON). The
> regen run failed by design with the six "regenerated" issues while determinism + rest-latch
> passed; the clean re-run is fully green, invariants included. Trajectory spot checks: the Verlet
> bounce is still airborne at step 300 (e=0.9 outlives the 5 s window, as the arithmetic predicted),
> rest_latch settles at y=0.499 with finalVelocity exactly [0,0,0] and gravity latched off,
> head_on_pair contacts at exactly ±0.5 and rebounds mirror-exact to ±9.0 with lockstep fall. The
> `TEST_RUNNER_` prefix forwarded the regen flag into the app-hosted runner as documented.

### What the harness is for, and how Phase A verifies against it

Record the **current** engine's trajectories now. Phase A then lands in **two separately verified
commits**:

1. **A-routing** (behavior-preserving): narrow-phase routing / "one narrow phase per pair" / plumbing
   refactors. **Must match every golden unchanged** (within tolerance). Any diff = a routing bug.
2. **A-response** (deliberate behavior change): rest-latch removal, impulse-discard removal, restitution
   velocity threshold, approach guard, slop+β positional correction (β ≈ 0.2, slop ≈ 5 mm — combined doc
   §3.3), ×2-correction fix. **Every scenario diverges from its first contact onward** — positional
   correction changes the post-contact state in all branches, dynamic/dynamic included. Verification =
   flip the characterization asserts deliberately + assert the semantic invariants below + regenerate
   goldens via `TFS_REGEN_PHYSICS_BASELINES=1` with the diff reviewed like code.

Scenario table (all Metal-free via 0.6 detached bodies; fixed seeds — `0xF22_0005` cluster,
`0xF22_0006` stress, the only two scenarios that draw randomness — live next to the definitions;
cluster/grid run broad phase **on** because response applies in pair order — pair *ordering* is part of
the locked-in behavior):

| Scenario | Setup | Solver / broad phase | Golden steps @ dt | A-response expectation (A-routing must match ALL goldens) |
|---|---|---|---|---|
| `single_bounce_verlet` | sphere r=0.5, m=1, e=0.9, dropped from y=5 onto y=0 plane (e=0.9) | HeckerVerlet / off | 300 @ 1/60 | identical through free fall; diverges at first ground contact (correction + threshold). Semantics: apex sequence decreasing, settles ≤ slop, `shouldApplyGravity` stays true |
| `single_bounce_euler` | same | NaiveEuler / off | 300 @ 1/60 | same |
| `rest_latch` | sphere r=0.5, e=0.2, dropped from y=3 | HeckerVerlet / off | 600 @ 1/60 | **changes wholesale** — documents the latch |
| `head_on_pair` | two spheres r=0.5, m=1, e=1, closing at ±5 m/s on X | HeckerVerlet / off | 120 @ 1/60 | identical until impact; **diverges at first contact** (pen/2-each teleport → slop+β correction). Semantics: e=1 velocity swap, exact symmetry \|vA\|=\|vB\| preserved |
| `ball_cluster_16` | 16 spheres r=0.4, m=1, e=0.9, seeded positions in [-7,7]×[1,10]×[-7,0] (BallPhysicsScene distribution), plane e=1 | HeckerVerlet / **on** | golden **180** @ 1/60; invariant run 600 | full regolden expected |
| `stress_grid_50` | 50 spheres r=0.3, e=0.8, grid + seeded jitter + seeded initial velocities (PhysicsStressTestScene distribution), plane e=0.9 | HeckerVerlet / **on** | golden **120** @ 1/60; invariant run 600 | full regolden expected |

**Chaos policy:** multi-body contact ordering amplifies float noise exponentially, so the cluster/stress
goldens cover only the first seconds (above), and the remainder of each 600-step run asserts **invariants
that hold for current AND Phase A behavior**: every position/velocity finite; no tunneling
(y ≥ plane − r − ε for every sphere); speed bounded by a generous initial+gravity budget. Invariants are
asserted from day one — they're the part of the contract that survives regoldens.

### Harness implementation (full — transcribe as-is)

All of `PhysicsParityTests.swift`. The code below is the authority on details the scenario table
leaves open: plane restitutions, seeds, sampling cadence, gravity staying on in `head_on_pair`, and
the invariant budgets. Imports match the other physics suites: `import Foundation`, `import Testing`,
`import simd`, `@testable import ToyFlightSimulator`.

```swift
// MARK: - Scenarios

/// One case per row of the scenario table; rawValue == golden filename stem.
enum ParityScenario: String, CaseIterable, CustomTestStringConvertible {
    case singleBounceVerlet = "single_bounce_verlet"
    case singleBounceEuler  = "single_bounce_euler"
    case restLatch          = "rest_latch"
    case headOnPair         = "head_on_pair"
    case ballCluster16      = "ball_cluster_16"
    case stressGrid50       = "stress_grid_50"

    var testDescription: String { rawValue }

    var solver: PhysicsUpdateType { self == .singleBounceEuler ? .NaiveEuler : .HeckerVerlet }

    var useBroadPhase: Bool {
        switch self {
            case .ballCluster16, .stressGrid50: return true
            default: return false
        }
    }

    var dt: Float { 1.0 / 60.0 }

    /// Steps covered by the committed golden.
    var goldenSteps: Int {
        switch self {
            case .singleBounceVerlet, .singleBounceEuler: return 300
            case .restLatch:     return 600
            case .headOnPair:    return 120
            case .ballCluster16: return 180
            case .stressGrid50:  return 120
        }
    }

    /// Total steps run; the tail past goldenSteps is invariant-checked only
    /// (the chaos policy: goldens stay short where contact ordering amplifies
    /// float noise, invariants carry the rest of the run).
    var totalSteps: Int {
        switch self {
            case .ballCluster16, .stressGrid50: return 600
            default: return goldenSteps
        }
    }

    /// Sampling cadence inside the golden window (t=0 always included).
    /// Dense for the simple scenarios (readable Phase A diffs), thinned for
    /// the many-body ones (keeps committed JSON in the tens of KB).
    var sampleEvery: Int {
        switch self {
            case .ballCluster16, .stressGrid50: return 3
            default: return 1
        }
    }

    /// Invariant bound. Deliberately ~2× the max physically attainable speed
    /// (initial speed + fall from max spawn height): catches energy blowups,
    /// not micro-noise, and must keep holding after Phase A's response
    /// rewrite.
    var speedBudget: Float {
        switch self {
            case .singleBounceVerlet, .singleBounceEuler, .restLatch:
                return 20   // impact from ≤ 5 m ≈ 7 m/s
            case .headOnPair:
                return 40   // ±5 m/s closing + 2 s free fall ≈ 20 m/s
            case .ballCluster16:
                return 30   // fall from ≤ 10 m ≈ 14 m/s
            case .stressGrid50:
                return 50   // fall from ≤ 20 m ≈ 20 m/s, + ≤ 2.8 m/s initial
        }
    }

    /// Ground-plane height for the tunneling invariant; nil = no floor
    /// (head_on_pair falls freely by design — see build()).
    var floorY: Float? { self == .headOnPair ? nil : 0 }

    var sphereRadius: Float {
        switch self {
            case .ballCluster16: return 0.4
            case .stressGrid50:  return 0.3
            default:             return 0.5
        }
    }

    struct Built {
        let world: PhysicsWorld
        /// Tracked bodies, index-aligned with the golden's tracks. The static
        /// plane (when present) is in the world but never tracked.
        let spheres: [SphereRigidBody]
    }

    /// All bodies via the 0.6 detached inits — no GameObject, no Metal.
    /// Masses stay at the RigidBody default (1), matching the table.
    func build() -> Built {
        switch self {
            case .singleBounceVerlet, .singleBounceEuler:
                let ball = SphereRigidBody(detachedAt: [0, 5, 0], collisionRadius: 0.5)
                ball.restitution = 0.9
                return Built(world: makeWorld([ball, floorPlane(restitution: 0.9)]),
                             spheres: [ball])

            case .restLatch:
                // Plane e = 1.0, so min() picks the ball's 0.2: impacts decay
                // 7 → 1.4 → 0.28 m/s, and the third contact is under
                // HeckerCollisionResponse's 0.55 m/s rest threshold against a
                // static body ⇒ the one-way latch fires (velocity/acceleration
                // zeroed, shouldApplyGravity = false) within ~70 steps.
                let ball = SphereRigidBody(detachedAt: [0, 3, 0], collisionRadius: 0.5)
                ball.restitution = 0.2
                return Built(world: makeWorld([ball, floorPlane(restitution: 1.0)]),
                             spheres: [ball])

            case .headOnPair:
                // No plane, gravity left ON: both spheres fall in lockstep, so
                // the contact normal stays X-pure and the e=1 equal-mass
                // velocity swap plus the |vA| == |vB| mirror symmetry are
                // exact. (Restitution stays at the RigidBody default 1.)
                let a = SphereRigidBody(detachedAt: [-2, 0, 0], collisionRadius: 0.5)
                a.velocity = [5, 0, 0]
                let b = SphereRigidBody(detachedAt: [2, 0, 0], collisionRadius: 0.5)
                b.velocity = [-5, 0, 0]
                return Built(world: makeWorld([a, b]), spheres: [a, b])

            case .ballCluster16:
                // BallPhysicsScene's spawn distribution with the scene's
                // unseeded `.random` swapped for the harness RNG. DRAW ORDER
                // IS PART OF THE GOLDEN CONTRACT: x, y, z per ball, balls in
                // order. (The scene's color draw is not mirrored — the
                // harness stream is its own.)
                var rng = SplitMix64(seed: 0xF22_0005)
                var balls: [SphereRigidBody] = []
                for _ in 0..<16 {
                    let pos = float3(rng.float(in: -7...7),
                                     rng.float(in: 1...10),
                                     rng.float(in: -7...0))
                    let ball = SphereRigidBody(detachedAt: pos, collisionRadius: 0.4)
                    ball.restitution = 0.9
                    balls.append(ball)
                }
                return Built(world: makeWorld(balls + [floorPlane(restitution: 1.0)]),
                             spheres: balls)

            case .stressGrid50:
                // PhysicsStressTestScene.createSpheres(count: 50): 8×8 grid
                // (Int(sqrt(50))+1), spacing 2, origin -8; jittered x/z;
                // y and initial velocity seeded; plane e = 0.9. Draw order
                // per ball: xJitter, y, zJitter, vx, vz.
                var rng = SplitMix64(seed: 0xF22_0006)
                let gridSize = 8
                let spacing: Float = 2.0
                let start = -Float(gridSize) * spacing / 2
                var balls: [SphereRigidBody] = []
                for i in 0..<50 {
                    let pos = float3(start + Float(i % gridSize) * spacing + rng.float(in: -0.5...0.5),
                                     rng.float(in: 5...20),
                                     start + Float(i / gridSize) * spacing + rng.float(in: -0.5...0.5))
                    let ball = SphereRigidBody(detachedAt: pos, collisionRadius: 0.3)
                    ball.restitution = 0.8
                    ball.velocity = [rng.float(in: -2...2), 0, rng.float(in: -2...2)]
                    balls.append(ball)
                }
                return Built(world: makeWorld(balls + [floorPlane(restitution: 0.9)]),
                             spheres: balls)
        }
    }

    private func floorPlane(restitution: Float) -> PlaneRigidBody {
        // Position .zero + up normal is load-bearing: the sphere/plane narrow
        // phase hardcodes a plane through the origin
        // (PhysicsWorld.getPenetrationDepth(ball:plane:)).
        let plane = PlaneRigidBody(detachedAt: .zero, collisionNormal: [0, 1, 0])
        plane.restitution = restitution
        plane.isStatic = true
        return plane
    }

    private func makeWorld(_ entities: [RigidBody]) -> PhysicsWorld {
        let world = PhysicsWorld(entities: entities, updateType: solver)
        world.useBroadPhase = useBroadPhase
        return world
    }
}

// MARK: - Baseline model + runner

/// Golden-file schema. Codable → JSON; Equatable → the determinism test.
/// Flat [Float] triples, not float3: keeps the synthesized Codable output a
/// plain JSON array. (Float round-trips JSON exactly — the 1e-4 compare
/// tolerance exists for FMA/toolchain variance, not serialization.)
struct PhysicsBaseline: Codable, Equatable {
    struct BodyTrack: Codable, Equatable {
        var samples: [[Float]]              // [x,y,z]: t=0, then every sampleEvery-th step of the golden window
        var finalVelocity: [Float]          // at the END of the golden window (not totalSteps)
        var finalShouldApplyGravity: Bool   // makes the rest latch visible in the data
    }

    var scenario: String
    var solver: String
    var useBroadPhase: Bool
    var dt: Float
    var steps: Int                          // golden window length (== goldenSteps)
    var sampleEvery: Int
    var tracks: [BodyTrack]                 // index-aligned with Built.spheres
}

enum ParityRunner {
    /// Steps the scenario to totalSteps: samples the golden window, snapshots
    /// final state at goldenSteps, and #requires the chaos-policy invariants
    /// on EVERY step (fail-fast: one readable failure, not a cascade of
    /// thousands once a body blows up).
    static func run(_ scenario: ParityScenario) throws -> PhysicsBaseline {
        let built = scenario.build()
        var samples: [[[Float]]] = built.spheres.map { [flat($0.getPosition())] }
        var finalVelocity: [[Float]] = []
        var finalGravity: [Bool] = []

        for step in 1...scenario.totalSteps {
            built.world.update(deltaTime: scenario.dt)

            if step <= scenario.goldenSteps && step % scenario.sampleEvery == 0 {
                for (i, ball) in built.spheres.enumerated() {
                    samples[i].append(flat(ball.getPosition()))
                }
            }
            if step == scenario.goldenSteps {
                finalVelocity = built.spheres.map { flat($0.velocity) }
                finalGravity  = built.spheres.map { $0.shouldApplyGravity }
            }

            for (i, ball) in built.spheres.enumerated() {
                let p = ball.getPosition()
                let v = ball.velocity
                try #require(allFinite(p) && allFinite(v),
                             "body \(i) non-finite at step \(step): p=\(p) v=\(v)")
                if let floorY = scenario.floorY {
                    // 1 m slack: the response can leave a frame of transient
                    // penetration, but a tunneled ball falls away forever and
                    // trips this within a few steps.
                    try #require(p.y > floorY - scenario.sphereRadius - 1.0,
                                 "body \(i) tunneled at step \(step): y=\(p.y)")
                }
                try #require(simd_length(v) <= scenario.speedBudget,
                             "body \(i) over the speed budget at step \(step): |v|=\(simd_length(v))")
            }
        }

        return PhysicsBaseline(scenario: scenario.rawValue,
                               solver: String(describing: scenario.solver),
                               useBroadPhase: scenario.useBroadPhase,
                               dt: scenario.dt,
                               steps: scenario.goldenSteps,
                               sampleEvery: scenario.sampleEvery,
                               tracks: built.spheres.indices.map {
                                   .init(samples: samples[$0],
                                         finalVelocity: finalVelocity[$0],
                                         finalShouldApplyGravity: finalGravity[$0])
                               })
    }

    private static func flat(_ v: float3) -> [Float] { [v.x, v.y, v.z] }

    /// Committed goldens live next to the tests; #filePath works on both the
    /// local checkout and CI's.
    static var baselinesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // …/ToyFlightSimulatorTests/Physics/
            .appendingPathComponent("Baselines")
    }

    /// TFS_REGEN_PHYSICS_BASELINES=1 (mirrors TFS_REGEN_THUMBNAILS) rewrites
    /// the golden instead of comparing, then records an issue so a regen run
    /// can never silently pass CI.
    static func assertMatchesGolden(_ fresh: PhysicsBaseline,
                                    tolerance: Float = 1e-4,
                                    sourceLocation: SourceLocation = #_sourceLocation) throws {
        let url = baselinesDir.appendingPathComponent("\(fresh.scenario).json")

        if ProcessInfo.processInfo.environment["TFS_REGEN_PHYSICS_BASELINES"] == "1" {
            try FileManager.default.createDirectory(at: baselinesDir,
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]   // stable diffs — regoldens are reviewed like code
            try encoder.encode(fresh).write(to: url)
            Issue.record("regenerated \(fresh.scenario).json — review the diff, then re-run without TFS_REGEN_PHYSICS_BASELINES",
                         sourceLocation: sourceLocation)
            return
        }

        let golden = try JSONDecoder().decode(PhysicsBaseline.self,
                                              from: Data(contentsOf: url))

        // Metadata compares EXACTLY — solver/steps/dt drift is a harness bug,
        // never something to tolerance past.
        try #require(fresh.scenario == golden.scenario
                     && fresh.solver == golden.solver
                     && fresh.useBroadPhase == golden.useBroadPhase
                     && fresh.dt == golden.dt
                     && fresh.steps == golden.steps
                     && fresh.sampleEvery == golden.sampleEvery
                     && fresh.tracks.count == golden.tracks.count,
                     "metadata mismatch vs \(fresh.scenario).json — regenerate deliberately",
                     sourceLocation: sourceLocation)

        // Report only the FIRST divergent (body, step): everything after the
        // first contact-order flip is downstream noise, and one readable
        // location is what makes a Phase A routing bug debuggable.
        for (body, (f, g)) in zip(fresh.tracks, golden.tracks).enumerated() {
            for (s, (fs, gs)) in zip(f.samples, g.samples).enumerated() {
                if (0..<3).contains(where: { abs(fs[$0] - gs[$0]) > tolerance }) {
                    Issue.record("body \(body) diverges at sample \(s) (step \(s * fresh.sampleEvery)): fresh \(fs) vs golden \(gs)",
                                 sourceLocation: sourceLocation)
                    return
                }
            }
            if f.finalShouldApplyGravity != g.finalShouldApplyGravity
                || (0..<3).contains(where: { abs(f.finalVelocity[$0] - g.finalVelocity[$0]) > tolerance }) {
                Issue.record("body \(body) final state diverges: v \(f.finalVelocity) vs \(g.finalVelocity), gravity \(f.finalShouldApplyGravity) vs \(g.finalShouldApplyGravity)",
                             sourceLocation: sourceLocation)
                return
            }
        }
    }
}

// MARK: - Tests

@Suite("Physics parity", .tags(.physics))
struct PhysicsParityTests {
    @Test("current behavior matches the committed golden",
          arguments: ParityScenario.allCases)
    func matchesGolden(_ scenario: ParityScenario) throws {
        try ParityRunner.assertMatchesGolden(try ParityRunner.run(scenario))
    }

    @Test("harness is deterministic — two fresh runs agree bit-for-bit")
    func harnessIsDeterministic() throws {
        // Validates the harness itself (seeding, no hidden global state) on
        // the scenario with the most RNG + broad-phase surface.
        let first  = try ParityRunner.run(.ballCluster16)
        let second = try ParityRunner.run(.ballCluster16)
        #expect(first == second)
    }

    @Test("CURRENT behavior: rest latch freezes gravity (A-response flips this)")
    func restLatchCharacterization() throws {
        let track = try ParityRunner.run(.restLatch).tracks[0]
        // The one-way latch zeroes velocity/acceleration and clears
        // shouldApplyGravity; with gravity off, Verlet then holds the state
        // bit-exactly — so EXACT zero (not approx) is the honest assert.
        #expect(track.finalShouldApplyGravity == false)
        #expect(track.finalVelocity == [0, 0, 0])
    }
}
```

Regenerating goldens (first landing, and A-response's reviewed regolden) — the `TEST_RUNNER_` prefix
forwards the variable into the app-hosted runner process; the regen run FAILS by design
(`Issue.record`), so the sequence is regen → review/commit the JSON → re-run without the flag → green:

```bash
TEST_RUNNER_TFS_REGEN_PHYSICS_BASELINES=1 xcodebuild test-without-building \
  -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug -parallel-testing-enabled NO \
  -only-testing:"ToyFlightSimulatorTests/PhysicsParityTests" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Tolerance note: same-machine reruns should be exact; 1e-4 absorbs toolchain/FMA variance between local
and CI for the short/simple scenarios. If CI diverges beyond that on the cluster/stress goldens even at
their shortened windows, shorten further or regen on CI's toolchain and note it in the Changelog.
Parameterized cases run concurrently in-process (see the note under Verification commands) — each
scenario builds its own `PhysicsWorld` and bodies, and nothing in the harness may touch process-wide
state.

## Step 0.8 — Unit tests (Metal-free, Swift Testing, `.physics` / `.utils` / `.gameObjects` tags) ✅

*(All landed 2026-08-28. Full serial app-hosted run: 240 Swift Testing tests in 40 suites + the XCTest
suites, all green — existing suites untouched.)*

- [x] `ColliderShapeTests`: `scaled(by:)` for all three shapes; `hasFinitePositiveDimensions` (rejects
  NaN/∞/negative, accepts halfHeight 0); `LocalCollider` defaults (identity rotation, `.airframe`, enabled)
- [x] `AircraftColliderSpecTests`: f22_cgtrader returns 3 enabled colliders with expected names/groups
  and **unique names**; all dimensions finite/positive; unauthored types return `[]` (exhaustive switch —
  compile-time enforced, test documents it); **fuselage total length = 2·(8.1+1.35) ≈ 18.9 m at scale
  1.0** (the sanity anchor, as a test so it can't rot)
- [x] `MeshBoundsTests` (`.utils`): pins measured ModelIO semantics with nil-allocator `MDLMesh` —
  capsule extent [1,5,1] → bounds ±[1,2.5,1] (x/z=radius, y=total); box [1,2,3] → ±[0.5,1,1.5]
  (full extent); sphere [2,2,2] → ±2 (radius semantics — documents the latent `SphereMesh` 2× quirk)
- [x] `ColliderOverlayMappingTests`: sphere child scale = radius; box child scale = 2·halfExtents
  (non-uniform); capsule child scale = 1 and `capsuleMeshParams(radius:halfHeight:)` =
  `(radius, 2·(halfHeight + radius))`; `worldDimensions` numbers (strings + longest-axis, at scale 1
  and scale 2)
- [x] `NodeOwnershipTests` (0.3b): weak-parent deallocation suite as specified there
- [x] `NodeTests` additions (XCTest, existing file): direct `rotationMatrix =` assignment dirties the
  cached local/world matrices (modelMatrix reflects it with no other setter call); `setRotation(_ q:)`
  equivalent to `setRotation(angle:axis:)` for the same rotation and fires the same dirty path — pins
  the 0.3 root fix and the F18 order-dependence repair
- [x] `RigidBody` detached-mode tests (in existing `RigidBodyTests`): `init(detachedAt:)` set/get
  round-trips; detached `SphereRigidBody`/`PlaneRigidBody` AABBs correct; **existing attached-path and
  released-weak tests unchanged and green** (that's the point of the redesign)
- [x] `PhysicsParityTests` as in step 0.7 (determinism + goldens + invariants + rest-latch characterization)
- [x] Overlay class itself: **not** unit-tested (constructs GameObjects → Metal; per project rule the
  logic lives in the pure mapping enum instead). Manual verification checklist below.

## Phase 0 exit criteria

1. - [x] **Overlay works in-app** *(verified in-app by the project owner 2026-08-29)* (manual,
   FlightboxWithPhysics, macOS): X cycles off → volumes-over-hull
   → volumes-only → off; volumes-only hides the F-22 hull but keeps afterburners visible; repeated
   cycling leaves no ghost renderables and no stranded-hidden aircraft; overlay survives: aircraft swap
   while visible (re-attaches to the new aircraft in the same mode), Cmd+R reset while visible (comes
   back clean on next X), renderer switch.
2. - [x] **Spec numbers eyeballed and committed** *(verified in-app 2026-08-29 — the authored values
   fit well in both overlay modes and were accepted unchanged, so no retune commit exists; the spec
   file's "PLACEHOLDERS until tuned" doc comment flips to "overlay-verified" in Phase A step A.7,
   when the numbers become load-bearing physics)*: overfit checked in volumes-over-hull (nothing
   protrudes that shouldn't), underfit checked in volumes-only (capsule end caps reach nose and tail,
   wings box reaches the wingtips, empennage box covers the tails — A/B cycling against the hull for
   placement) — tuned values recorded in `AircraftColliderSpec` with overlay screenshots in
   `debugging/screenshots/`.
3. - [x] **Units anchor holds** *(2026-08-28)*: overlay log prints fuselage total ≈ **18.9 m at scale 1.0**
   (vs 18.92 m real F-22 — ran in 0.5); `MeshBoundsTests` + `ColliderOverlayMappingTests` green (the
   measured capsule mapping can't rot).
4. - [x] **Parity baselines committed** *(2026-08-28)*: all six scenario goldens recorded, parity suite
   green against them on a clean re-run (determinism + invariants included), run Metal-free via the
   corrected `build-for-testing` / `test-without-building` pattern.
5. - [x] **No unintended behavior change** *(closed 2026-08-29: macOS Tests workflow green on main at
   `0ec9a3e` — CI run 33221486316, 2026-08-28 — with the full Phase 0 tree in; in-app play verified
   alongside criterion 1)*: full existing test suite green in CI; `PhysicsWorldSmokeTests`
   (attached-body path) untouched and green; game plays identically with the overlay off. The one
   deliberate change is 0.3b's ownership fix — detached subtrees (old aircraft after a swap/reset) now
   deallocate, pinned by `NodeOwnershipTests`.

**Implementation order within Phase 0:** 0.1 ✓ → 0.2 ✓(re-authored) → 0.3 ✓ → 0.3b ✓ → 0.4 ✓ → 0.5 ✓ →
0.6 ✓ → 0.7 ✓ (baselines locked before any later phase touches physics) → 0.8 ✓. **Phase 0 code
complete 2026-08-28; all five exit criteria closed 2026-08-29 — Phase 0 ✅ done** (criteria 1–2
verified in-app by the project owner, criterion 5 by the CI run noted on its checkbox). 0.3b
preceded the overlay because 0.4's lifecycle rules assume it; the overlay
steps (0.4/0.5) landed before the parity steps (0.6/0.7) — the two tracks are independent and either
order was allowed; both before Phase A starts.

---

# Pre-Phase-A design corrections (recorded 2026-08-27, before Phase A is planned)

Corrections to the declared source-of-truth design (combined doc §3.4/§4.2 sketches) that Phase A's plan
section must adopt when it's appended:

1. **No static step/scratch state.** The §4.2 sketch declares
   `PhysicsWorld.currentStepIndex` as `static` and keys per-step scratch caches off it. Step indices,
   contact scratch arrays, and world-collider scratch must be **per-`PhysicsWorld` instance** state:
   parameterized Swift Testing parity cases run concurrently in one process (serial
   `-parallel-testing-enabled NO` does not serialize in-process Swift Testing), so multiple live
   `PhysicsWorld`s are the *norm* in tests, not an edge case.
2. **World-collider cache invalidation.** A once-per-step world-pose snapshot goes stale the moment
   response positional correction moves a body mid-step (any multi-contact step). Either recompute the
   corrected body's world colliders after each positional correction, or version the cache per body
   (bump on `setPosition`) — decide in Phase A planning; a blanket once-per-step cache is wrong.
3. **World-transform contract.** The physics path composes poses from `getPosition()` /
   `getRotationMatrix()`, which are **local**. That's valid only while rigid-body owners are scene-root
   children (true for every current owner). Phase A must either build world colliders from the actual
   world transform (`getWorldPosition()` + world rotation) or debug-assert
   `gameObject.parent is GameScene` when a body with colliders is registered. The assert is the cheap
   Phase A answer; revisit if bodies ever nest.
4. **Two-commit verification split** (defined in 0.7): A-routing must match the Phase 0 goldens exactly;
   A-response regoldens with reviewed diffs + semantic asserts. No single commit may both refactor
   routing and change response behavior.

---

# Phase A — colliders on `RigidBody`, one narrow phase, corrected contact response

*(Planned 2026-08-29, against the tree at `0ec9a3e` with Phase 0 fully closed.)*

Implements combined doc **§4.2** (its A1–A5), amended by the four pre-Phase-A design corrections
above and by the planning-time findings recorded in the deviations table below. At the end of this
phase: every body's collision geometry flows through one `WorldCollider`-based narrow phase that
emits typed `Contact`s (all collider pairs, not booleans); the response is the corrected impulse
model (restitution velocity threshold, slop+β positional correction, approach guard — the rest
latch and the impulse-discard hack are gone, `shouldApplyGravity` stops being solver state); pair
filtering exists; the `CollisionShape` enum and the force-cast switches are deleted; and the
CGTrader F-22 collides as the Phase 0-verified three-primitive compound instead of a 2 m sphere,
reporting per-collider contacts by name through `onContact`.

**The three-commit protocol** (expands 0.7's two-commit split — the aircraft flip gets its own
commit because it changes *which geometry exists*, which neither golden track covers):

| Commit | Steps | Verification gate |
|---|---|---|
| **A-routing** | A.1–A.5 | Behavior-preserving. All six parity goldens must pass **unchanged** — the expectation is bit-for-bit, not merely within the 1e-4 tolerance (the argument for why bit-exactness is achievable is in A.5). Full suite green. Game plays identically. Any golden diff = a routing bug, full stop. |
| **A-response** | A.6 | The deliberate behavior change. Regolden all six scenarios with the JSON diff reviewed like code against the per-scenario expectations in 0.7's table; flip the rest-latch characterization test; land the new response-semantics suite. Chaos-policy invariants must hold un-edited. |
| **A-aircraft** | A.7 | The F-22 swaps sphere → compound. No goldens involve aircraft; verified by a new Metal-free detached-compound settle test + in-app contact logging + the overlay (whose red volumes are now the live colliders). |

Steps map to the combined doc as: A.1↔A1, A.2↔A2, A.3↔A3, A.4↔A4, A.5+A.6↔A5 (split on the
routing/response boundary), A.7↔the §4.2 exit criterion's aircraft wiring. A.8 is the test ledger,
like 0.8.

**Where each pre-Phase-A correction lands:**

| Correction | Resolution | Step |
|---|---|---|
| 1. No static step/scratch state | The step-index cache token is **eliminated, not instanced**: world-collider snapshots are dirty-flag cached per body (deviation 1), and the contact scratch array is owned by each `PhysicsWorld` instance and passed `inout` to the response/solvers. No `currentStepIndex` exists anywhere in Phase A. | A.2, A.5 |
| 2. World-collider cache invalidation | `RigidBody.setPosition` is the funnel through which every mid-step move happens (response corrections, solver integration) and it sets the dirty flag — a later pair in the same step narrow-phases against the corrected pose automatically. Between-step node changes (attitude rotation, teleports) are covered by the world invalidating every entity at the top of each step. | A.2 |
| 3. World-transform contract | The cheap answer, as pre-decided: `rebuildWorldColliders()` debug-asserts `node.parent == nil \|\| node.parent is GameScene` for attached bodies with colliders. | A.2 |
| 4. Two-commit verification split | The three-commit protocol above (routing/response exactly as 0.7 defined them; A-aircraft added on top). | all |

### Deviations from the research docs (deliberate, argued)

| Deviation | Why |
|---|---|
| **Dirty-flag world-collider cache; no `frame:` token, no `currentStepIndex` at all** | The research sketch (§4.2 A2) keyed the cache on a static step counter — banned by correction 1, and merely instancing the counter would still leave correction 2 unsolved (a once-per-step token can't see mid-step position corrections). A per-body `worldCollidersDirty` flag set by `setPosition` / `colliders.didSet` / the world's start-of-step sweep resolves both corrections with one mechanism, is the codebase's own idiom (Node's transform dirty flags), and needs no parameter threading through `getAABB()`/narrow-phase signatures. Phase B's accumulator can add a per-instance counter if something ever needs one. |
| **`SphereRigidBody` stays a body-level shape — it does NOT install a one-sphere `LocalCollider` list** (research §3.5 said it should) | Units conflict found while planning: `collisionRadius` is **world meters** (the Phase 0 overlay's legacy-ghost math documents this — it divides by parent scale), but `LocalCollider` dimensions are **local meters × `uniformScale`**. Installing `.sphere(radius: collisionRadius)` would make the effective radius `collisionRadius × scale` — and the scaled callers are not hypothetical: `FlightboxWithPhysics.makeRandomDispersedObjects` builds balls with node scale ≈ `collisionRadius` (unit-radius mesh scaled to size), which would double-scale every one of them. Instead the sphere synthesizes a **single `WorldCollider` view** (radius used as world meters, scale deliberately not applied, nil metadata) inside the same `worldColliders()` entry point — so the narrow phase still has exactly ONE collider-based dispatch and the flat-compound end state holds. Migrating ball call sites to local-space colliders (`radius: 1` at scale s) is exact but pure churn; deferred until something needs it. |
| **Narrow phase emits strict "B → A" normals from day one; the routing-commit response adapts by exact sign symmetry** | The legacy normal convention is *shape-dependent*: sphere-sphere returns `posA − posB` (B→A), but sphere-plane returns the plane's normal **whichever side the plane is on** — i.e. "static-body-outward" — and the response's asymmetric branches were written against that mix. Baking the mix into `NarrowPhase` would poison the new vocabulary permanently. Emitting strict B→A and transcribing the response with an explicit `legacyNormal = -contact.normal` where the conventions differ is bit-identical for every reachable configuration (IEEE argument in A.5). One knowingly-accepted divergence: the legacy `(A static, B dynamic)` **sphere-sphere** branch pushed the dynamic body *toward* the static one (a latent position-correction bug); no scene or golden contains a static sphere, and the transcription silently fixes it. Dynamic planes are likewise unreachable (every `PlaneRigidBody` is static) and remain unsupported. |
| **Contact gates are inclusive (`depth >= 0`)** where the research listings used strict `> 0` | The legacy gates are inclusive (`<=` on both the sphere-sphere and sphere-plane predicates), and a depth-exactly-0 contact triggers the legacy response. Measure-zero in practice, but the routing commit transcribes rather than editorializes; the new capsule/box primitives adopt the same boundary for consistency. |
| **Legacy-exact `sphereVsSphere`** (inclusive gate; coincident-centers → **zero normal**, not the research's `[0,1,0]` fallback) | Same transcription discipline: the degenerate fallback is reachable (perfect overlap) and therefore part of the locked-in behavior. A-response may not change it either — it's response-independent geometry; if a better fallback is ever wanted it's its own reviewed regolden. |
| **`EulerSolver`'s bespoke response is deleted in A-response; both solvers share the corrected `applyCollisionResponse`** | The per-axis velocity-reflection code is an axis-aligned-plane special case (exactly the class of wrongness as the y=0 depth hack) and its rest hack zeroes *both* bodies' velocities with no static gate. The A-response semantic invariants (apex decay, settle ≤ slop, gravity stays on) cannot hold under it. For up-normal planes its reflection ≈ the impulse response (`v_y → −e·v_y`, tangent untouched), so `single_bounce_euler`'s regolden diverges exactly as 0.7's table already predicts. Routing (A.5) still transcribes it faithfully — the deletion happens only against the reviewed regolden. |
| **`PhysicsMaterial` is defined now, consumed by nothing** | A1 reserves the field on `LocalCollider` so specs don't churn when Phase D's friction lands (combined doc, minor-differences table). Defining the two-field struct now costs ~6 lines and makes the reservation compile-checked. |
| **`onContact` fires from the routing commit; classification stays out** | The event plumbing is behavior-neutral (nobody registered) and routing is exactly when the all-contacts scratch loop is written; wiring it later would mean re-touching the response loops. Crash/landing *classification* built on these events remains Phase B3. |

## Step A.1 — Vocabulary completion (edit `Physics/Collision/ColliderShape.swift`) — A-routing ✅

Phase 0 pulled the data-only half of A1 forward; this step appends the remainder to the same file
(per 0.1's "Phase A will append, not restructure"): the reserved material, the world-space snapshot
type, and the pure builder that turns one into the other.

- [x] `PhysicsMaterial` (reserved) + `LocalCollider.material` field

```swift
/// Reserved per-collider surface override (combined doc, minor-differences
/// table): friction / restitution per collider arrive with tangent friction in
/// Phase D. Until then body-level restitution applies and NOTHING reads this —
/// it exists so authored specs don't churn when Phase D lands.
struct PhysicsMaterial: Equatable {
    var friction: Float = 0.5
    /// nil ⇒ inherit the body's restitution.
    var restitution: Float? = nil
}
```

`LocalCollider` gains the stored field and one init parameter, both defaulted so no Phase 0 call
site (spec file, overlay, tests) changes:

```diff
     /// Cheap runtime on/off (Jolt MutableCompoundShape's role). Disabled
     /// colliders generate no contacts, don't contribute to the AABB, and the
     /// debug overlay skips them.
     var isEnabled: Bool
+    /// Reserved: per-collider friction/restitution override (Phase D).
+    /// Body-level restitution applies until then.
+    var material: PhysicsMaterial?

     init(name: String,
          shape: ColliderShape,
          localPosition: float3 = .zero,
          localRotation: simd_quatf = .identity,
          group: ColliderGroup = .airframe,
-         isEnabled: Bool = true) {
+         isEnabled: Bool = true,
+         material: PhysicsMaterial? = nil) {
         assert(shape.hasFinitePositiveDimensions,
                "Collider '\(name)' has non-finite or non-positive dimensions: \(shape)")
         ...
+        self.material = material
     }
```

- [x] `WorldCollider` — the derived per-query snapshot (research §3.4's split). **One change from
  the research listing:** the identity fields are optional, because a `WorldCollider` can also be
  the *synthesized view of a legacy body-level shape* (deviation 2 — `SphereRigidBody`), and
  `Contact`'s documented contract is "collider names/groups are nil for simple bodies". A real
  compound child always carries all three.

```swift
/// A LocalCollider transformed into world space for one narrow-phase query.
/// Derived and read-only (research §3.4: LocalCollider = authored spec,
/// WorldCollider = per-step snapshot). Obtain via RigidBody.worldColliders();
/// never store across steps — the backing array is reused scratch.
struct WorldCollider {
    let shape: ColliderShape        // dimensions already × uniformScale
    let position: float3            // world center
    let rotation: float3x3          // world orientation (orthonormal)
    /// Identity of the authored LocalCollider. All three are nil for the
    /// synthesized view of a legacy body-level shape (SphereRigidBody), which
    /// is what keeps Contact's "nil for simple bodies" contract truthful.
    let sourceIndex: Int?
    let name: String?
    let group: ColliderGroup?

    /// World-axis-aligned bounds (broad-phase input; compound AABB = union).
    var aabb: AABB {
        switch shape {
            case .sphere(radius: let r):
                return AABB(center: position, radius: r)
            case .capsule(radius: let r, halfHeight: let hh):
                // Segment endpoint extents + radius inflation.
                let axisExtent = abs(rotation.columns.1 * hh)
                return AABB(center: position,
                            halfExtents: axisExtent + float3(repeating: r))
            case .box(halfExtents: let he):
                // World-axis extents of an oriented box: |R| · he
                let extents = abs(rotation.columns.0) * he.x
                            + abs(rotation.columns.1) * he.y
                            + abs(rotation.columns.2) * he.z
                return AABB(center: position, halfExtents: extents)
        }
    }
}
```

- [x] `WorldColliderBuilder` — the pure local→world transform, extracted per the Metal-free test
  rule (the `RigidBody` wrapper feeds node state in; tests feed poses directly and never construct
  a GameObject):

```swift
/// Pure LocalCollider × body-pose → WorldCollider transform. Kept free of
/// RigidBody/Node so the math is unit-testable Metal-free (the attached-body
/// wrapper in RigidBody.rebuildWorldColliders is three lines of state
/// gathering around this).
enum WorldColliderBuilder {
    /// Appends the world snapshot of every ENABLED collider into `out`
    /// (cleared first, capacity kept — reused-scratch discipline).
    static func build(_ colliders: [LocalCollider],
                      bodyPosition: float3,
                      bodyRotation: float3x3,
                      uniformScale: Float,
                      into out: inout [WorldCollider]) {
        out.removeAll(keepingCapacity: true)
        for (index, collider) in colliders.enumerated() where collider.isEnabled {
            out.append(WorldCollider(
                shape: collider.shape.scaled(by: uniformScale),
                position: bodyPosition + bodyRotation * (collider.localPosition * uniformScale),
                rotation: bodyRotation * float3x3(collider.localRotation),
                sourceIndex: index,
                name: collider.name,
                group: collider.group))
        }
    }
}
```

Notes:
- `float3x3(collider.localRotation)` is the simd overlay's quaternion→matrix init; no helper needed.
- The offset transform order (`rotate(localPosition × scale)`) matches the research A2 sketch and the
  overlay's scene-graph composition (child transforms compose under the parent's rotation and scale),
  so physics and the rendered volumes agree by construction.

## Step A.2 — `RigidBody` integration (edit `Physics/World/RigidBody.swift`, `BasicRigidBodies.swift`) — A-routing ✅

The flat-compound storage (research D1/§3.5), the dirty-flag snapshot cache (deviation 1), the
compound AABB, filtering state, and the contact event. All additive — nothing consumes `colliders`
until A.3/A.5 route the narrow phase through it, and no existing body has a non-empty list until
A.7, so this lands behavior-neutral by construction.

- [x] `RigidBody` additions (full listing — insert after the `shouldApplyGravity` stored property,
  before the `gameObject` declaration):

```swift
    /// Compound collision geometry: primitive colliders at body-local offsets
    /// (combined doc D1/§3.5 — one body, many shapes; the model every surveyed
    /// engine uses). Empty ⇒ the body has no compound volume: PlaneRigidBody
    /// is special-cased at body level in the narrow phase, SphereRigidBody
    /// synthesizes a one-sphere view (see rebuildWorldColliders — the legacy
    /// classes deliberately IGNORE this list), and a plain RigidBody with no
    /// colliders generates no contacts.
    var colliders: [LocalCollider] = [] {
        didSet { invalidateWorldColliders() }
    }

    /// Collision filtering (research §1.5): a pair is narrow-phased only if
    /// each body's category intersects the other's mask. Defaults preserve
    /// today's behavior — everything collides with everything.
    var categoryMask: UInt32 = CollisionCategory.default
    var collidesWithMask: UInt32 = CollisionCategory.all

    /// Fired once per contact this body participates in, on the UpdateThread,
    /// during collision resolution (after the response for that pair; every
    /// collider-pair contact fires, not just the deepest one the linear
    /// response consumed). The Contact is expressed with self as A. Keep the
    /// handler cheap, and never mutate physics state from inside it — the
    /// step is mid-flight.
    var onContact: ((Contact, RigidBody) -> Void)?

    /// World-space collider snapshot, dirty-flag cached (Phase A deviation 1 —
    /// replaces the research sketch's static step-index token). Invalidation:
    ///  - PhysicsWorld invalidates every entity at the top of each step
    ///    (covers node transforms changed BETWEEN steps: attitude rotation,
    ///    teleports, scene setup);
    ///  - setPosition invalidates (covers MID-step moves — response position
    ///    corrections and solver integration all funnel through it — which is
    ///    the pre-Phase-A correction-2 requirement: a later pair in the same
    ///    step narrow-phases against the corrected pose);
    ///  - colliders.didSet (and SphereRigidBody.collisionRadius.didSet)
    ///    invalidate on shape changes.
    /// Code that mutates a body's node OUTSIDE a stepped world (tests, tools)
    /// must either go through setPosition or call invalidateWorldColliders().
    /// `worldCollidersScratch` is internal ONLY so subclass rebuild overrides
    /// can write it; everything else reads via worldColliders().
    internal var worldCollidersScratch: [WorldCollider] = []
    private var worldCollidersDirty = true

    func invalidateWorldColliders() {
        worldCollidersDirty = true
    }

    /// The body's enabled colliders in world space. The returned array is
    /// reused scratch — consume within the current step, never store (same
    /// rule as the broad phase's pairs array).
    func worldColliders() -> [WorldCollider] {
        if worldCollidersDirty {
            rebuildWorldColliders()
            worldCollidersDirty = false
        }
        return worldCollidersScratch
    }

    /// Override point (SphereRigidBody synthesizes its legacy view here).
    internal func rebuildWorldColliders() {
        guard !colliders.isEmpty else {
            worldCollidersScratch.removeAll(keepingCapacity: true)
            return
        }
        if let node = gameObject {
            // Pre-Phase-A correction 3: the physics path composes LOCAL
            // transforms (getPosition/getRotationMatrix), valid only while
            // rigid-body owners are scene-root children. Revisit (world
            // transforms) if bodies ever nest.
            assert(node.parent == nil || node.parent is GameScene,
                   "RigidBody colliders on nested node '\(node.getName())' — world-collider math assumes a scene-root child")
            WorldColliderBuilder.build(colliders,
                                       bodyPosition: node.getPosition(),
                                       bodyRotation: node.getRotationMatrix().upperLeft3x3,
                                       uniformScale: node.uniformScale,
                                       into: &worldCollidersScratch)
        } else {
            // Standalone (parity-harness) bodies AND the released-weak
            // fallback state: identity pose at getPosition() — for released
            // attached bodies that's .zero, matching their pre-Phase-A AABB
            // behavior (the zombie already collided at the origin).
            WorldColliderBuilder.build(colliders,
                                       bodyPosition: getPosition(),
                                       bodyRotation: matrix_identity_float3x3,
                                       uniformScale: 1.0,
                                       into: &worldCollidersScratch)
        }
    }

    /// Symmetric filtering predicate (research §1.5), consumed by the broad
    /// phase at pair emission and by both legacy O(n²) paths: category/mask
    /// both ways, plus never pair two bodies attached to the same GameObject
    /// (a future multi-body object must not self-collide). Bodies with nil
    /// gameObjects (detached harness bodies) never match each other.
    func shouldCollide(with other: RigidBody) -> Bool {
        guard (categoryMask & other.collidesWithMask) != 0,
              (other.categoryMask & collidesWithMask) != 0 else { return false }
        if let mine = gameObject, let theirs = other.gameObject, mine === theirs {
            return false
        }
        return true
    }
```

- [x] `RigidBody.setPosition` — one added line in the shared mutation funnel:

```diff
     func setPosition(_ position: float3) {
+        invalidateWorldColliders()
         if isStandalone {
             standalonePosition = position
         }
         else {
             self.gameObject?.setPosition(position)
         }
     }
```

- [x] `RigidBody.getAABB()` — compound union when colliders exist, unchanged delegate otherwise
  (no plain-`RigidBody` entity exists before A.7, so this is dead code until then — which is the
  point: it lands inside the golden-verified routing commit anyway):

```diff
     func getAABB() -> AABB {
-        self.gameObject?.getAABB() ?? AABB(center: .zero, radius: .zero)
+        let worlds = worldColliders()
+        guard var merged = worlds.first?.aabb else {
+            // No colliders: the legacy node-AABB delegate, unchanged.
+            return self.gameObject?.getAABB() ?? AABB(center: .zero, radius: .zero)
+        }
+        for collider in worlds.dropFirst() {
+            merged = merged.merged(with: collider.aabb)
+        }
+        return merged
     }
```

- [x] `CollisionCategory` (same file, below the class — research §1.5 vocabulary; **assignment of
  non-default categories to scene bodies is deliberately deferred** until something needs filtering,
  because with `collidesWithMask = .all` everywhere the masks are inert):

```swift
/// Bitmask vocabulary for collision filtering. Extend as needed; assign
/// categories when a scene actually needs to filter (Phase B/C) — the
/// defaults (default category, all-mask) keep every pair live.
enum CollisionCategory {
    static let `default`: UInt32 = 1 << 0
    static let world: UInt32     = 1 << 1   // ground plane, terrain
    static let vehicle: UInt32   = 1 << 2   // player + AI aircraft
    static let structure: UInt32 = 1 << 3   // buildings, towers
    static let debris: UInt32    = 1 << 4   // random physics objects
    static let all: UInt32       = .max
}
```

- [x] `SphereRigidBody` (BasicRigidBodies.swift) — the legacy view (deviation 2). `collisionRadius`
  gains an invalidating `didSet` (FlightboxWithPhysics assigns it post-init); the AABB override
  **stays** (reads live position directly — cheaper than the union-of-one and bit-identical to it):

```diff
 public final class SphereRigidBody: RigidBody {
-    var collisionRadius: Float = 1.0
+    var collisionRadius: Float = 1.0 {
+        didSet { invalidateWorldColliders() }
+    }
+
+    /// Legacy body-level sphere → one synthesized WorldCollider view, so the
+    /// narrow phase has a single collider-based dispatch (Phase A deviation
+    /// 2): collisionRadius is WORLD meters, so node scale is deliberately NOT
+    /// applied, and the metadata is nil — Contact reports nil collider names
+    /// for simple bodies, per its doc contract. The `colliders` list is
+    /// ignored on this class by design (a compound body is a plain RigidBody).
+    override internal func rebuildWorldColliders() {
+        assert(colliders.isEmpty,
+               "SphereRigidBody ignores `colliders` — use a plain RigidBody for compounds")
+        worldCollidersScratch.removeAll(keepingCapacity: true)
+        worldCollidersScratch.append(WorldCollider(shape: .sphere(radius: collisionRadius),
+                                                   position: getPosition(),
+                                                   rotation: matrix_identity_float3x3,
+                                                   sourceIndex: nil,
+                                                   name: nil,
+                                                   group: nil))
+    }
```

`PlaneRigidBody` is untouched: the narrow phase special-cases planes at body level (an infinite
static plane is world geometry, not a compound child — both research docs agree), its `getAABB()`
huge-slab override stands, and its inherited `rebuildWorldColliders()` yields an empty scratch
that nothing queries.

### Why the dirty-flag cache is correct (the reasoning correction 2 demanded)

The cache can only be consulted from the update thread, and there are exactly two windows where a
body's world pose changes:

1. **Between steps** (aircraft attitude via `Node.setRotation`, scene setup, teleports): none of
   these route through `RigidBody.setPosition`, so the flag alone would go stale — that's what the
   world's start-of-step sweep (`invalidateWorldColliders()` next to `resetCollisions()`, A.5) is
   for. This sweep is load-bearing, not belt-and-braces: a settled aircraft writes NO transforms
   (the attitude filter snaps to zero), but a banking one rotates every frame without ever calling
   `setPosition`.
2. **Mid-step** (response position corrections; solver integration): every one of these goes
   through `RigidBody.setPosition` — grep the solvers and response, there is no other position
   write — so the flag flips and the *next* `worldColliders()` call rebuilds. This exactly
   reproduces the legacy timing, where `getCollisionData` read `getPosition()` live at each pair:
   a pair resolved after an earlier pair moved a shared body sees the corrected pose in both
   worlds, old and new. (That equivalence is part of the bit-exactness argument in A.5.)

Rotation cannot change mid-step (nothing in the solvers or response touches rotation), so a
mid-step rebuild reusing the start-of-step rotation is not a staleness hole today. When Phase D
makes rotation solver state, its pose writes must funnel through a rigid-body setter that
invalidates, same as position — noted here so the requirement doesn't get lost.

## Step A.3 — `Contact` + `NarrowPhase` (new files) — A-routing ✅

Adopts the original research doc §2.3 listings with the D3 hybrid amendment (emit ALL collider-pair
contacts, return the deepest's index for the linear response) and this plan's deviations (no
`frame:` parameter; strict B→A normals; legacy-exact sphere primitives; inclusive gates; optional
collider metadata flowing from `WorldCollider`).

- [x] **File (new):** `ToyFlightSimulator Shared/Physics/Collision/Contact.swift`

```swift
/// One collision contact produced by the narrow phase.
/// `normal` is unit length and points from B toward A — the direction that
/// separates A. NOTE: this is a STRICT convention; the legacy code's normal
/// was shape-dependent (sphere-plane pairs always carried the plane's normal,
/// whichever side the plane was on). The A-routing response transcription
/// accounts for the difference explicitly — see the sign-symmetry note there.
struct Contact {
    let normal: float3
    let depth: Float
    /// Representative world-space contact point. Unused by the linear-only
    /// response; populated from day one so it becomes the lever arm when
    /// angular dynamics land (combined doc D2 prep).
    let point: float3
    /// Sub-collider names/groups for compound bodies (nil for simple bodies —
    /// a legacy sphere's synthesized view and the infinite plane carry no
    /// collider identity).
    let colliderNameA: String?
    let colliderGroupA: ColliderGroup?
    let colliderNameB: String?
    let colliderGroupB: ColliderGroup?

    /// Geometry + metadata from the colliders that produced the contact
    /// (either may be nil: plane side, or a legacy body-level shape's view —
    /// whose own metadata fields are nil anyway, and optional chaining
    /// flattens them straight through).
    init(normal: float3, depth: Float, point: float3,
         collider a: WorldCollider? = nil, against b: WorldCollider? = nil) {
        self.normal = normal
        self.depth = depth
        self.point = point
        self.colliderNameA = a?.name
        self.colliderGroupA = a?.group
        self.colliderNameB = b?.name
        self.colliderGroupB = b?.group
    }

    private init(normal: float3, depth: Float, point: float3,
                 colliderNameA: String?, colliderGroupA: ColliderGroup?,
                 colliderNameB: String?, colliderGroupB: ColliderGroup?) {
        self.normal = normal
        self.depth = depth
        self.point = point
        self.colliderNameA = colliderNameA
        self.colliderGroupA = colliderGroupA
        self.colliderNameB = colliderNameB
        self.colliderGroupB = colliderGroupB
    }

    /// The same contact expressed with A and B swapped.
    var flipped: Contact {
        Contact(normal: -normal, depth: depth, point: point,
                colliderNameA: colliderNameB, colliderGroupA: colliderGroupB,
                colliderNameB: colliderNameA, colliderGroupB: colliderGroupA)
    }
}
```

- [x] **File (new):** `ToyFlightSimulator Shared/Physics/Collision/NarrowPhase.swift`

```swift
import simd

/// Pure narrow phase: WorldCollider geometry in, Contacts out. No body
/// mutation, no Metal — every function below is unit-testable per the
/// project's Metal-free rule (research §3.4: the Local/World split is what
/// makes this a pure function).
///
/// The sphere-sphere and sphere-plane paths are TRANSCRIPTIONS of the deleted
/// PhysicsWorld shape switches — operation-for-operation, so the A-routing
/// commit is bit-identical against the Phase 0 goldens. Do not "improve" the
/// arithmetic here without a deliberate, reviewed golden regeneration.
enum NarrowPhase {
    // MARK: - Body-level dispatch

    /// Appends EVERY contacting collider pair between the two bodies into
    /// `contacts` (combined doc D3 hybrid: events and classification need all
    /// of them — a wingtip and the belly can scrape simultaneously). Returns
    /// the ABSOLUTE index (into `contacts`) of the deepest appended contact —
    /// the linear-only response consumes exactly that one; Phase D's solver
    /// will consume them all and the return value disappears. nil ⇒ no
    /// intersection (nothing appended).
    @discardableResult
    static func generateContacts(_ a: RigidBody, _ b: RigidBody,
                                 into contacts: inout [Contact]) -> Int? {
        // Planes are infinite static world geometry, special-cased at body
        // level (research §3.5); always presented to the shape tests as the
        // B side, flipped back on exit if the plane arrived as A.
        if a is PlaneRigidBody {
            guard !(b is PlaneRigidBody) else { return nil }   // plane/plane: nothing to do
            let firstNew = contacts.count
            guard let deepest = generateContacts(b, a, into: &contacts) else { return nil }
            for i in firstNew..<contacts.count {
                contacts[i] = contacts[i].flipped
            }
            return deepest
        }

        if let plane = b as? PlaneRigidBody {
            let planePoint = plane.getPosition()
            let planeNormal = plane.collisionNormal
            var deepest: Int? = nil
            for collider in a.worldColliders() {
                if let contact = shapeVsPlane(collider,
                                              planePoint: planePoint,
                                              planeNormal: planeNormal) {
                    contacts.append(contact)
                    if deepest == nil || contact.depth > contacts[deepest!].depth {
                        deepest = contacts.count - 1
                    }
                }
            }
            return deepest
        }

        // Volume vs volume: children × children. A legacy SphereRigidBody's
        // "children" are its one synthesized view, so this loop IS the
        // sphere-sphere, sphere-compound, and compound-compound path at once.
        var deepest: Int? = nil
        for colliderA in a.worldColliders() {
            for colliderB in b.worldColliders() {
                if let contact = shapeVsShape(colliderA, colliderB) {
                    contacts.append(contact)
                    if deepest == nil || contact.depth > contacts[deepest!].depth {
                        deepest = contacts.count - 1
                    }
                }
            }
        }
        return deepest
    }

    // MARK: - Shape vs plane

    /// Sphere/capsule/box vs the infinite plane through planePoint. The
    /// sphere case is the legacy sphere-plane test in general-plane form —
    /// bit-identical for every plane that exists today (they all sit at the
    /// origin with a +Y normal; equivalence argued in the A.5 notes), and
    /// CORRECT for tilted/translated planes, which the deleted
    /// getPenetrationDepth(ball:plane:) y=0 hardcode never was.
    /// Gates are inclusive (depth >= 0), matching the legacy `<=` boundaries.
    static func shapeVsPlane(_ collider: WorldCollider,
                             planePoint: float3,
                             planeNormal n: float3) -> Contact? {
        switch collider.shape {
            case .sphere(radius: let r):
                let signedDistance = dot(collider.position - planePoint, n)
                let depth = r - signedDistance
                guard depth >= 0 else { return nil }
                return Contact(normal: n, depth: depth,
                               point: collider.position - n * signedDistance,
                               collider: collider)

            case .capsule(radius: let r, halfHeight: let hh):
                // Deeper end-cap center decides. A capsule lying flat on the
                // plane picks one end — adequate for the linear response
                // (co-normal contacts resolve with one impulse); Phase D's
                // manifold work refines this.
                let axis = collider.rotation.columns.1
                let p0 = collider.position - axis * hh
                let p1 = collider.position + axis * hh
                let d0 = dot(p0 - planePoint, n)
                let d1 = dot(p1 - planePoint, n)
                let (endCenter, signedDistance) = d0 < d1 ? (p0, d0) : (p1, d1)
                let depth = r - signedDistance
                guard depth >= 0 else { return nil }
                return Contact(normal: n, depth: depth,
                               point: endCenter - n * signedDistance,
                               collider: collider)

            case .box(halfExtents: let he):
                let c0 = collider.rotation.columns.0
                let c1 = collider.rotation.columns.1
                let c2 = collider.rotation.columns.2
                // Projection radius of the OBB onto the plane normal.
                let projectionRadius = he.x * abs(dot(c0, n))
                                     + he.y * abs(dot(c1, n))
                                     + he.z * abs(dot(c2, n))
                let signedDistance = dot(collider.position - planePoint, n)
                let depth = projectionRadius - signedDistance
                guard depth >= 0 else { return nil }
                // Deepest corner: step against the normal on each box axis.
                func axisSign(_ x: Float) -> Float { x >= 0 ? 1 : -1 }
                let corner = collider.position
                    - c0 * (he.x * axisSign(dot(c0, n)))
                    - c1 * (he.y * axisSign(dot(c1, n)))
                    - c2 * (he.z * axisSign(dot(c2, n)))
                return Contact(normal: n, depth: depth, point: corner,
                               collider: collider)
        }
    }

    // MARK: - Shape vs shape

    static func shapeVsShape(_ a: WorldCollider, _ b: WorldCollider) -> Contact? {
        switch (a.shape, b.shape) {
            case (.sphere(radius: let ra), .sphere(radius: let rb)):
                return sphereVsSphere(centerA: a.position, radiusA: ra,
                                      centerB: b.position, radiusB: rb,
                                      a: a, b: b)

            case (.sphere(radius: let r), .capsule):
                // Closest point on B's segment to A's center → sphere-sphere.
                let (pB, rB) = capsuleAsSphere(b, towards: a.position)
                return sphereVsSphere(centerA: a.position, radiusA: r,
                                      centerB: pB, radiusB: rB, a: a, b: b)
            case (.capsule, .sphere):
                return shapeVsShape(b, a)?.flipped

            case (.capsule, .capsule):
                let (segA0, segA1, rA) = capsuleSegment(a)
                let (segB0, segB1, rB) = capsuleSegment(b)
                let (pA, pB) = closestPointsOnSegments(segA0, segA1, segB0, segB1)
                return sphereVsSphere(centerA: pA, radiusA: rA,
                                      centerB: pB, radiusB: rB, a: a, b: b)

            case (.sphere(radius: let r), .box(halfExtents: let he)):
                return sphereVsBox(center: a.position, radius: r,
                                   box: b, halfExtents: he, a: a, b: b)
            case (.box, .sphere):
                return shapeVsShape(b, a)?.flipped

            case (.capsule, .box(halfExtents: let he)):
                // Approximation: nearest point of the capsule segment to the
                // box CENTER, then sphere-vs-box. Adequate for crash
                // detection; exact segment-OBB (or GJK) is the Phase C/D
                // upgrade path (combined doc §4.4).
                let (p, r) = capsuleAsSphere(a, towards: b.position)
                return sphereVsBox(center: p, radius: r, box: b, halfExtents: he,
                                   a: a, b: b)
            case (.box, .capsule):
                return shapeVsShape(b, a)?.flipped

            case (.box, .box):
                // Not needed while structures are static and vehicle compounds
                // are capsule/box-vs-sphere/plane dominated. Upgrade path:
                // SAT (15 axes) or GJK/EPA — Phase C decides if it's ever hit.
                return nil
        }
    }

    // MARK: - Primitive helpers (pure — unit-testable without Metal)

    /// LEGACY-EXACT transcription of the deleted PhysicsWorld sphere-sphere
    /// pair: squared-distance gate, INCLUSIVE boundary, one sqrt on the hit
    /// path, and the degenerate coincident-centers case yields a ZERO normal
    /// (as before — reachable via perfect overlap and therefore pinned;
    /// changing it to an arbitrary up-vector is a behavior change requiring a
    /// golden regen of its own).
    private static func sphereVsSphere(centerA: float3, radiusA: Float,
                                       centerB: float3, radiusB: Float,
                                       a: WorldCollider, b: WorldCollider) -> Contact? {
        let radiusSum = radiusA + radiusB
        let delta = centerA - centerB
        let distanceSquared = simd_length_squared(delta)
        guard distanceSquared <= radiusSum * radiusSum else { return nil }
        let distance = simd_length(delta)
        let normal: float3 = distance > 0 ? delta / distance : .zero
        return Contact(normal: normal, depth: radiusSum - distance,
                       point: centerB + normal * radiusB,
                       collider: a, against: b)
    }

    private static func sphereVsBox(center: float3, radius: Float,
                                    box: WorldCollider, halfExtents he: float3,
                                    a: WorldCollider, b: WorldCollider) -> Contact? {
        // Sphere center in box-local space (R orthonormal: inverse = transpose).
        let local = box.rotation.transpose * (center - box.position)
        let clamped = simd_clamp(local, -he, he)

        if local.x == clamped.x && local.y == clamped.y && local.z == clamped.z {
            // Center inside the box: push out along the axis of least
            // penetration (depth = face distance + radius).
            let distances = he - abs(local)
            var axis = 0
            if distances.y < distances.x { axis = 1 }
            if distances.z < distances[axis] { axis = 2 }
            var localNormal = float3.zero
            localNormal[axis] = local[axis] >= 0 ? 1 : -1
            return Contact(normal: box.rotation * localNormal,
                           depth: distances[axis] + radius,
                           point: center,
                           collider: a, against: b)
        }

        let closest = box.position + box.rotation * clamped
        let delta = center - closest
        let distance = simd_length(delta)
        guard distance <= radius else { return nil }
        let normal: float3 = distance > 0 ? delta / distance : [0, 1, 0]
        return Contact(normal: normal, depth: radius - distance, point: closest,
                       collider: a, against: b)
    }

    private static func capsuleSegment(_ c: WorldCollider) -> (float3, float3, Float) {
        guard case .capsule(radius: let r, halfHeight: let hh) = c.shape else {
            fatalError("capsuleSegment on non-capsule collider")
        }
        let axis = c.rotation.columns.1
        return (c.position - axis * hh, c.position + axis * hh, r)
    }

    private static func capsuleAsSphere(_ c: WorldCollider,
                                        towards target: float3) -> (float3, Float) {
        let (p0, p1, r) = capsuleSegment(c)
        return (closestPointOnSegment(p0, p1, to: target), r)
    }

    static func closestPointOnSegment(_ p0: float3, _ p1: float3,
                                      to point: float3) -> float3 {
        let segment = p1 - p0
        let lengthSquared = simd_length_squared(segment)
        guard lengthSquared > .ulpOfOne else { return p0 }
        let t = max(0, min(1, dot(point - p0, segment) / lengthSquared))
        return p0 + segment * t
    }

    /// Closest points between two segments (Ericson, Real-Time Collision
    /// Detection §5.1.9, clamped form).
    static func closestPointsOnSegments(_ p1: float3, _ q1: float3,
                                        _ p2: float3, _ q2: float3) -> (float3, float3) {
        let d1 = q1 - p1, d2 = q2 - p2, r = p1 - p2
        let a = dot(d1, d1), e = dot(d2, d2), f = dot(d2, r)
        var s: Float = 0, t: Float = 0
        if a <= .ulpOfOne && e <= .ulpOfOne { return (p1, p2) }
        if a <= .ulpOfOne {
            t = max(0, min(1, f / e))
        } else {
            let c = dot(d1, r)
            if e <= .ulpOfOne {
                s = max(0, min(1, -c / a))
            } else {
                let b = dot(d1, d2)
                let denominator = a * e - b * b
                s = denominator > .ulpOfOne ? max(0, min(1, (b * f - c * e) / denominator)) : 0
                t = (b * s + f) / e
                if t < 0 {
                    t = 0
                    s = max(0, min(1, -c / a))
                } else if t > 1 {
                    t = 1
                    s = max(0, min(1, (b - c) / a))
                }
            }
        }
        return (p1 + d1 * s, p2 + d2 * t)
    }
}
```

Implementation notes, the parts that are easy to get wrong:

- **The plane-as-A flip is an in-place rewrite of the appended slice.** The recursive call appends
  contacts expressed with the volume body as A; the loop then flips each one so the caller's (A=plane,
  B=volume) orientation holds, and the deepest index survives untouched because flipping preserves
  both position-in-array and depth. Forgetting the flip would hand the response a normal pointing
  *into* the dynamic body.
- **`sphereVsBox`'s center-inside branch cannot return nil** — the sphere center inside the box is
  always a hit regardless of radius. The subscript-based axis selection (`distances[axis]`) is the
  standard least-penetration face pick; ties resolve toward x→y→z in that order, deterministically.
- **`shapeVsShape`'s flipped-swap cases must not double-tag metadata**: the swapped call already
  builds the contact with (b, a) metadata, and `.flipped` swaps it back — A's collider info ends up
  on the A side. The tests in A.8 pin this with a named capsule vs named sphere both ways.
- **Deepest-index bookkeeping is per-call, absolute.** The response caller records `firstNew =
  contacts.count` before the call for its event slice; the returned index is already absolute, so
  no offset math (an off-by-firstNew here would fire the response on the wrong pair's contact —
  ugly and silent in single-contact scenes).
- *(Landed 2026-08-30 with one micro-deviation: `capsuleSegment` and `capsuleAsSphere` return named
  tuple members — `(p0:, p1:, radius:)` and `(center:, radius:)` — for readability; callers
  destructure positionally, so the call sites above are unchanged.)*

## Step A.4 — Pair filtering (edit `BroadPhase/BroadPhaseCollisionDetector.swift` + the pair consumers) — A-routing ✅

The predicate itself (`RigidBody.shouldCollide(with:)`) and the `CollisionCategory` vocabulary land
in A.2; this step is the three application points. With the default masks (`default` category,
`all` mask) and no two bodies sharing a GameObject, every guard evaluates true today — inert by
construction, pinned by the goldens.

- [x] Broad phase — filter at pair emission (both loops), so filtered pairs never reach the narrow
  phase at all:

```diff
                 // Check full AABB overlap (Y and Z axes)
-                if aabbA.overlaps(aabbB) {
+                if aabbA.overlaps(aabbB)
+                    && dynamicEntities[i].shouldCollide(with: dynamicEntities[j]) {
                     pairsScratch.append((dynamicEntities[i], dynamicEntities[j]))
                 }
```

```diff
-                if dynamicAABB.overlaps(staticAABBs[si]) {
+                if dynamicAABB.overlaps(staticAABBs[si])
+                    && dynamicEntities[di].shouldCollide(with: staticEntities[si]) {
                     pairsScratch.append((dynamicEntities[di], staticEntities[si]))
                 }
```

- [x] Both legacy O(n²) paths guard at pair visit (inside the shared `resolvePair`s — see A.5's
  listings), otherwise masks would silently not work under `useBroadPhase == false`, which is
  exactly the configuration the parity harness runs four of six scenarios in. The guard is also
  re-evaluated on broad-phase pairs there — redundant by two integer ANDs, kept because a single
  choke point is worth more than two saved cycles.

(The research doc placed `shouldCollide` as a static on the broad phase; it lives on `RigidBody`
instead because three call sites across two subsystems consume it and it's a body-pair predicate,
not a sweep-and-prune detail. Micro-deviation, recorded here.)

## Step A.5 — One narrow phase per pair: routing the responses + the deletions — completes A-routing ✅

The heart of the routing commit. Both response paths stop calling
`PhysicsWorld.collided`/`getCollisionData` (which ran the geometry twice per pair) and consume one
`NarrowPhase.generateContacts` call; contact events fire; then the entire `CollisionShape` layer is
deleted. **The response math is transcribed, not improved** — every hack survives to A.6, because
this commit's contract is bit-identical goldens.

### File 1 — `Physics/World/PhysicsWorld.swift`

- [x] Per-instance contact scratch + start-of-step invalidation + scratch plumbing:

```diff
 final class PhysicsWorld {
     public static let gravity: float3 = [0, -9.81, 0]
     ...
     private var broadPhase = BroadPhaseCollisionDetector()
+    /// Per-instance contact scratch (pre-Phase-A correction 1: parameterized
+    /// parity cases run multiple live worlds concurrently in one process — no
+    /// statics anywhere in the step path). Cleared and refilled by the
+    /// response each step; contents are reused scratch, same discipline as
+    /// the broad phase's pairs array.
+    private var contactsScratch: [Contact] = []

     public func update(deltaTime: Float) {
         for entity in entities {
             entity.resetCollisions()
+            // Deviation 1: start-of-step invalidation covers node transforms
+            // changed since the last step — attitude rotation never routes
+            // through RigidBody.setPosition, so the dirty flag alone can't
+            // see it. Mid-step moves are covered by setPosition itself.
+            entity.invalidateWorldColliders()
         }
```

and the four private update methods pass the scratch through:

```swift
    private func naiveUpdate(deltaTime: Float, collisionPairs: [(RigidBody, RigidBody)]) {
        EulerSolver.step(deltaTime: deltaTime,
                         gravity: PhysicsWorld.gravity,
                         entities: entities,
                         collisionPairs: collisionPairs,
                         contactsScratch: &contactsScratch)
    }

    private func heckerVerletUpdate(deltaTime: Float, collisionPairs: [(RigidBody, RigidBody)]) {
        HeckerCollisionResponse.resolveCollisions(deltaTime: deltaTime,
                                                  collisionPairs: collisionPairs,
                                                  contactsScratch: &contactsScratch)
        VerletSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: entities)
    }

    private func naiveUpdateOriginal(deltaTime: Float) {
        EulerSolver.step(deltaTime: deltaTime,
                         gravity: PhysicsWorld.gravity,
                         entities: entities,
                         contactsScratch: &contactsScratch)
    }

    private func heckerVerletUpdateOriginal(deltaTime: Float) {
        HeckerCollisionResponse.resolveCollisions(deltaTime: deltaTime,
                                                  entities: entities,
                                                  contactsScratch: &contactsScratch)
        VerletSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: entities)
    }
```

### File 2 — `Physics/CollisionResponse/HeckerCollisionResponse.swift`

- [x] Both `resolveCollisions` variants collapse onto one `resolvePair`; the response consumes the
  deepest contact; events fire per contact, after the response (handlers observe post-response
  state):

```swift
    /// Broad-phase pair path.
    static func resolveCollisions(deltaTime: Float,
                                  collisionPairs: [(RigidBody, RigidBody)],
                                  contactsScratch: inout [Contact]) {
        contactsScratch.removeAll(keepingCapacity: true)
        for (entityA, entityB) in collisionPairs {
            resolvePair(entityA, entityB, contacts: &contactsScratch)
        }
    }

    /// Legacy O(n²) path for `useBroadPhase == false`. Visits each unordered
    /// pair once, as before.
    static func resolveCollisions(deltaTime: Float,
                                  entities: [RigidBody],
                                  contactsScratch: inout [Contact]) {
        contactsScratch.removeAll(keepingCapacity: true)
        for a in 0..<entities.count {
            for b in (a + 1)..<entities.count {
                resolvePair(entities[a], entities[b], contacts: &contactsScratch)
            }
        }
    }

    /// ONE narrow phase per pair (the old flow ran geometry twice — collided()
    /// then getCollisionData()). Bookkeeping order preserved exactly: the
    /// already-collided guard, then narrow phase, then symmetric insertion,
    /// then response. New and inert-by-default: the filtering guard (A.4) and
    /// the per-contact events (nobody registered until A.7).
    private static func resolvePair(_ entityA: RigidBody, _ entityB: RigidBody,
                                    contacts: inout [Contact]) {
        guard entityA.shouldCollide(with: entityB),
              !entityA.collidedWith.contains(ObjectIdentifier(entityB)) else { return }

        let firstNew = contacts.count
        guard let deepest = NarrowPhase.generateContacts(entityA, entityB,
                                                         into: &contacts) else { return }

        entityA.collidedWith.insert(ObjectIdentifier(entityB))
        entityB.collidedWith.insert(ObjectIdentifier(entityA))

        applyCollisionResponse(entityA, entityB, contact: contacts[deepest])

        // Events fire for EVERY contact of the pair (combined doc D3) —
        // classification needs them all, not just the one the linear
        // response consumed.
        for contact in contacts[firstNew...] {
            entityA.onContact?(contact, entityB)
            entityB.onContact?(contact.flipped, entityA)
        }
    }
```

- [x] The transcribed response — **behavior-frozen through the routing commit** (full listing; the
  per-branch comments are part of the deliverable, they carry the convention bookkeeping):

```swift
    /// A-ROUTING TRANSCRIPTION — behavior-frozen. This is the pre-routing
    /// response verbatim (rest latch, minDeltaVelo impulse discard, ×2 static
    /// corrections and all), consuming the pair's deepest Contact instead of
    /// re-running geometry through PhysicsWorld.getCollisionData. Where the
    /// strict B→A normal differs from the legacy shape-dependent normal,
    /// `legacyNormal` reconstructs the old value exactly (IEEE negation is
    /// exact — see the plan's sign-symmetry note). Do NOT clean anything up
    /// here: A.6 replaces this body deliberately, against regenerated goldens.
    private static func applyCollisionResponse(_ entityA: RigidBody, _ entityB: RigidBody,
                                               contact: Contact) {
        // Hack (dies in A.6): the one-way rest latch, preserved bit-for-bit.
        if simd_length_squared(entityA.velocity - entityB.velocity) < restSpeedThresholdSquared {
            if entityB.isStatic {
                entityA.velocity = .zero
                entityA.acceleration = .zero
                entityA.shouldApplyGravity = false

                print("[HeckerCollisionResponse resolveCollisions] Gravity should not apply to entity: \(ObjectIdentifier(entityA))")
            }

            if entityA.isStatic {
                entityB.velocity = .zero
                entityB.acceleration = .zero
                entityB.shouldApplyGravity = false

                print("[HeckerCollisionResponse resolveCollisions] Gravity should not apply to entity: \(ObjectIdentifier(entityB))")
            }

            return
        }

        let penetrationDepth = contact.depth
        let collisionNormal = contact.normal   // unit, strict B → A

        if !entityA.isStatic && !entityB.isStatic {
            // Legacy normal == strict normal in this branch (sphere-sphere was
            // already B→A; dynamic planes don't exist). Verbatim.
            entityA.setPosition(entityA.getPosition() + collisionNormal * (penetrationDepth / 2))
            entityB.setPosition(entityB.getPosition() - collisionNormal * (penetrationDepth / 2))

            let relativeVelo = entityA.velocity - entityB.velocity
            let e = min(entityA.restitution, entityB.restitution)
            var j = -(1 + e) * dot(relativeVelo, collisionNormal)
            j /= ((1.0 / entityA.mass) + (1.0 / entityB.mass))

            let entityADeltaVelo = j / entityA.mass * collisionNormal
            let entityBDeltaVelo = j / entityB.mass * collisionNormal

            entityA.velocity += simd_length_squared(entityADeltaVelo) > minDeltaVeloSquared ? entityADeltaVelo : .zero
            entityB.velocity -= simd_length_squared(entityBDeltaVelo) > minDeltaVeloSquared ? entityBDeltaVelo : .zero

            return
        }

        if !entityA.isStatic && entityB.isStatic {
            // Legacy normal == strict normal here too: with B static, B is
            // the plane (normal toward A) or a static sphere (B→A formula
            // either way). Verbatim, ×2 overshoot included.
            entityA.setPosition(entityA.getPosition() + collisionNormal * (penetrationDepth * 2))

            let relativeVelo = entityA.velocity
            let e = min(entityA.restitution, entityB.restitution)
            var j = -(1 + e) * dot(relativeVelo, collisionNormal)
            j /= 1.0 / entityA.mass

            let entityADeltaVelo = j / entityA.mass * collisionNormal
            entityA.velocity += simd_length_squared(entityADeltaVelo) > minDeltaVeloSquared ? entityADeltaVelo : .zero

            return
        }

        if entityA.isStatic && !entityB.isStatic {
            // The one convention-divergent branch. The legacy normal here was
            // the static body's OUTWARD normal (the plane's normal, pointing
            // toward B — not B→A); strict B→A is its exact negation, so
            // reconstruct it and keep the body verbatim. For the unreachable
            // static-SPHERE-as-A configuration this silently fixes the legacy
            // inverted position correction (impulse term is bit-identical in
            // both configurations — the sign symmetry note has the algebra).
            let legacyNormal = -collisionNormal
            entityB.setPosition(entityB.getPosition() + legacyNormal * (penetrationDepth * 2))

            let relativeVelo = entityB.velocity
            let e = min(entityA.restitution, entityB.restitution)
            var j = -(1 + e) * dot(relativeVelo, legacyNormal)
            j /= 1.0 / entityB.mass

            let entityBDeltaVelo = j / entityB.mass * legacyNormal
            entityB.velocity += simd_length_squared(entityBDeltaVelo) > minDeltaVeloSquared ? entityBDeltaVelo : .zero

            return
        }
    }
```

### File 3 — `Physics/Solver/EulerSolver.swift`

- [x] Step overloads gain the scratch (the 3-arg protocol requirement survives as a wrapper);
  `resolvePair` gets the identical routing treatment with its own frozen transcription:

```swift
    /// PhysicsSolver conformance — allocates a local scratch. Kept for the
    /// protocol and for direct test calls; PhysicsWorld always passes its own
    /// scratch via the overloads below, so no hot path allocates.
    public static func step(deltaTime: Float, gravity: float3, entities: [RigidBody]) {
        var contacts: [Contact] = []
        step(deltaTime: deltaTime, gravity: gravity, entities: entities,
             contactsScratch: &contacts)
    }

    /// Legacy O(n²) step — the useBroadPhase == false comparison baseline.
    public static func step(deltaTime: Float, gravity: float3, entities: [RigidBody],
                            contactsScratch: inout [Contact]) {
        applyForces(deltaTime: deltaTime, gravity: gravity, entities: entities)
        contactsScratch.removeAll(keepingCapacity: true)
        resolveCollisionsAllPairs(entities: entities, contacts: &contactsScratch)
        moveObjects(deltaTime: deltaTime, entities: entities)
        zeroForces(entities: entities)
    }

    /// P1: broad-phase-driven step.
    public static func step(deltaTime: Float, gravity: float3, entities: [RigidBody],
                            collisionPairs: [(RigidBody, RigidBody)],
                            contactsScratch: inout [Contact]) {
        applyForces(deltaTime: deltaTime, gravity: gravity, entities: entities)
        contactsScratch.removeAll(keepingCapacity: true)
        for (ei, ej) in collisionPairs {
            resolvePair(ei, ej, contacts: &contactsScratch)
        }
        moveObjects(deltaTime: deltaTime, entities: entities)
        zeroForces(entities: entities)
    }

    static func resolveCollisionsAllPairs(entities: [RigidBody],
                                          contacts: inout [Contact]) {
        for i in 0..<entities.count {
            for j in (i + 1)..<entities.count {
                resolvePair(entities[i], entities[j], contacts: &contacts)
            }
        }
    }

    /// Narrow phase + response for one candidate pair — same routing shape as
    /// HeckerCollisionResponse.resolvePair (guard order preserved exactly).
    private static func resolvePair(_ ei: RigidBody, _ ej: RigidBody,
                                    contacts: inout [Contact]) {
        guard ei.shouldCollide(with: ej),
              !ei.collidedWith.contains(ObjectIdentifier(ej)) else { return }

        let firstNew = contacts.count
        guard let deepest = NarrowPhase.generateContacts(ei, ej,
                                                         into: &contacts) else { return }

        ei.collidedWith.insert(ObjectIdentifier(ej))
        ej.collidedWith.insert(ObjectIdentifier(ei))

        applyLegacyEulerResponse(ei, ej, contact: contacts[deepest])

        for contact in contacts[firstNew...] {
            ei.onContact?(contact, ej)
            ej.onContact?(contact.flipped, ei)
        }
    }

    /// A-ROUTING TRANSCRIPTION — behavior-frozen (see the Hecker twin). The
    /// per-axis reflection and the zero-both-velocities rest hack survive
    /// routing verbatim; A.6 deletes this whole function in favor of the
    /// shared corrected response.
    private static func applyLegacyEulerResponse(_ ei: RigidBody, _ ej: RigidBody,
                                                 contact: Contact) {
        let collisionVector = contact.normal      // unit, strict B → A
        let restitution = min(ei.restitution, ej.restitution)
        let unormCollisionVector = contact.normal * contact.depth

        // Hack to prevent infinite bouncing (dies in A.6; zeroes BOTH bodies,
        // no static gate — preserved exactly, single_bounce_euler pins it):
        if simd_length_squared(ei.velocity - ej.velocity) < restSpeedThresholdSquared {
            ei.velocity = .zero
            ej.velocity = .zero
            return
        }

        if !ei.isStatic && !ej.isStatic {
            // Legacy normal == strict normal in this branch. Verbatim.
            ei.setPosition(ei.getPosition() + unormCollisionVector)
            ei.velocity = (ei.velocity + collisionVector) * restitution

            ej.setPosition(ej.getPosition() - unormCollisionVector)
            ej.velocity = (ej.velocity - collisionVector) * restitution
            return
        }

        if !ei.isStatic && ej.isStatic {
            // Legacy normal == strict normal here. Verbatim, ×2 included.
            ei.setPosition(ei.getPosition() + unormCollisionVector * 2)
            let vX = collisionVector.x != 0 ? ei.velocity.x * -collisionVector.x * restitution : ei.velocity.x
            let vY = collisionVector.y != 0 ? ei.velocity.y * -collisionVector.y * restitution : ei.velocity.y
            let vZ = collisionVector.z != 0 ? ei.velocity.z * -collisionVector.z * restitution : ei.velocity.z
            ei.velocity = [vX, vY, vZ]
            return
        }

        if ei.isStatic && !ej.isStatic {
            // Convention-divergent branch: reconstruct the legacy
            // static-outward normal (exact negation), then verbatim.
            let legacyVector = -collisionVector
            let legacyUnorm = legacyVector * contact.depth
            ej.setPosition(ej.getPosition() + legacyUnorm * 2)
            let vX = legacyVector.x != 0 ? ej.velocity.x * -legacyVector.x * restitution : ej.velocity.x
            let vY = legacyVector.y != 0 ? ej.velocity.y * -legacyVector.y * restitution : ej.velocity.y
            let vZ = legacyVector.z != 0 ? ej.velocity.z * -legacyVector.z * restitution : ej.velocity.z
            ej.velocity = [vX, vY, vZ]
            return
        }
    }
```

### The deletions (same commit, once nothing references them)

- [x] `PhysicsWorld`: `collided(entityA:entityB:)` + the three shape-pair `collided(...)` helpers,
  `getCollisionData`, the `CollisionData` struct, both `getPenetrationDepth` overloads (the
  ball/plane one IS the y=0 hack — its death is what makes tilted/translated planes work), and
  `getDistance` (zero callers, verified 2026-08-29).
- [x] `CollisionShape` enum + the `collisionShape` protocol requirement (`PhysicsEntity.swift`).
- [x] `RigidBody`: the stored property and both designated inits' `collisionShape`
  parameter/assignment. The two inits still mirror each other line-for-line afterwards, so 0.6's
  mirroring contract survives; update that doc comment only if the diff makes it stale.
- [x] `SphereRigidBody` / `PlaneRigidBody`: the four `self.collisionShape = ...` lines.
- [x] Test edits (mechanical, behavior-neutral): `TestRigidBody` drops its `collisionShape`
  parameter + pass-through (PhysicsSolverTests.swift); `RigidBodyTests` drops its four
  `#expect(... .collisionShape == ...)` lines (assertions about a deleted property — every other
  expectation in those tests stands). `EulerSolver.resolveCollisionsAllPairs` callers in tests, if
  any, gain the scratch argument.
- [x] `PhysicsEntity.shouldApplyGravity`'s `// Hack...` comment **stays** — it's still true until
  A.6.

### Why the goldens must not move — the bit-exactness argument

The routing commit's gate is *stronger* than the harness tolerance: the goldens should be
**byte-identical**. That's provable, not hopeful, because every reachable configuration reduces to
the legacy arithmetic operation-for-operation:

1. **Sphere-sphere** — transcribed: same inclusive squared-distance gate
   (`simd_distance_squared(a,b)` ≡ `simd_length_squared(a − b)`, the same fused expression), same
   one-sqrt data path (`simd_length(delta)` ≡ `sqrt(length_squared(delta))`), same depth and
   zero-normal degenerate.
2. **Sphere-plane, gate** — legacy `dot(planePos − spherePos, −n) ≤ r` vs new
   `r − dot(spherePos − planePos, n) ≥ 0`. Two exact steps: `dot(−v, n) = −dot(v, n)` bit-exactly
   (per-component negation is exact; the negated products sum to the negated sum), and
   `fl(r − d) ≥ 0 ⟺ d ≤ r` because IEEE-754 subtraction of distinct floats never rounds to zero
   (x − y = 0 ⟺ x = y), so the sign of the computed difference is the sign of the real difference.
3. **Sphere-plane, depth** — every existing plane sits at the origin with normal `[0, 1, 0]`
   (`addGround` never repositions the Quad; the harness `floorPlane` is `detachedAt: .zero`; the
   normalize of `[0,1,0]` is exact). Then `dot(c − 0, [0,1,0])` evaluates to `c.y` exactly (`±0`
   terms are absorbed), and `r − c.y` is the legacy expression verbatim.
4. **The static-A response branch** — `legacyNormal = -collisionNormal` is exact, and every
   downstream expression consumes `legacyNormal` where the legacy code consumed its normal, so the
   floating-point evaluations are literally the same. (This is why the transcription reconstructs
   the legacy normal instead of algebraically folding the sign in — reviewability AND exactness.)
5. **The legacy-sphere world view** adds no arithmetic — `position` and `radius` are copied fields.
6. **Cache timing** reproduces legacy live reads — argued in A.2; in particular a pair resolved
   after an earlier pair corrected a shared body sees the corrected pose in both worlds.
7. **Pair ordering is untouched** — same broad-phase emission order, same O(n²) loop order, same
   `collidedWith` bookkeeping order.

And the empirical check, which outranks the proof: with the routing commit in the tree, run the
regen command from 0.7 and then `git diff --exit-code "ToyFlightSimulatorTests/Physics/Baselines"`
— it must come back **empty** (all six JSONs rewritten byte-identical). Discard the regen run's
designed failure, re-run the suite clean, green. Any diff at all means a transcription slipped;
fix the routing, never the golden.

### A-routing verification checklist

- [x] `build-for-testing` green; full serial suite green against **unchanged** goldens
- [x] Regen dry-run byte-identical (protocol above)
- [x] `PhysicsWorldSmokeTests` untouched and green (attached-body path)
- [x] In-app FlightboxWithPhysics eyeball: dispersed balls bounce, settle, and (still) latch
  exactly as before; aircraft sphere behavior unchanged
- [x] Commit message marks this as the A-routing commit per the 0.7 protocol

## Step A.6 — The corrected response (rest fix) — the A-response commit ✅

Implements research §3.2's five-point replacement, verbatim in intent: restitution velocity
threshold, always-applied impulses, approach guard, slop+β position correction, gravity never
touched. Both hacks die together (they interlock — removing either alone breaks resting), the ×2
overshoot dies, and `EulerSolver` unifies onto the shared response (deviation: its per-axis
reflection is an axis-aligned special case the semantic invariants can't hold under). **Every
scenario diverges from its first contact — that is the point.** Verification is the 0.7 protocol:
flip the characterization assert, regolden with the diff reviewed like code, land the semantic
suite whose assertions hold for the NEW behavior and would have failed under the old.

### File 1 — `HeckerCollisionResponse.swift` (the ~40 lines that pay for the whole phase)

- [x] Constants replaced:

```diff
 final class HeckerCollisionResponse {
-    /// Below this relative speed a contact is treated as resting (squared — no sqrt).
-    private static let restSpeedThresholdSquared: Float = 0.55 * 0.55
-    /// Impulse delta-v below this squared magnitude is discarded (1.0² == 1.0).
-    private static let minDeltaVeloSquared: Float = 1.0
+    /// Below this normal approach speed, restitution is 0: the impulse solves
+    /// the normal velocity to exactly zero instead of bouncing, so resting is
+    /// an equilibrium re-established every step — gravity stays ON. (Box2D's
+    /// b2_velocityThreshold and Jolt's restitution threshold are both ≈ 1 m/s.)
+    private static let restitutionVelocityThreshold: Float = 1.0
+    /// Penetration allowed before position correction engages (meters). The
+    /// slop keeps persistent contacts measurably touching instead of
+    /// oscillating across the surface.
+    private static let penetrationSlop: Float = 0.005
+    /// Fraction of (depth − slop) corrected per step (Baumgarte-style); damps
+    /// correction-induced energy. Replaces the legacy full-depth teleports
+    /// and the ×2 static-branch overshoot.
+    private static let positionCorrectionBeta: Float = 0.2
```

- [x] `applyCollisionResponse` — the routed transcription's body is replaced wholesale
  (`internal` now: `EulerSolver` shares it). Full listing:

```swift
    /// Corrected linear contact response (research §3.2; combined doc A5).
    /// Consumes the pair's deepest contact; symmetric in inverse mass, so the
    /// static/dynamic branching of the legacy code collapses (a static body
    /// has infinite mass ⇒ inverse mass 0 ⇒ it neither moves nor changes
    /// velocity). deltaTime-independent by design until Phase B's fixed step
    /// (β is per-step, matching the legacy correction's shape).
    internal static func applyCollisionResponse(_ entityA: RigidBody, _ entityB: RigidBody,
                                                contact: Contact) {
        let n = contact.normal                       // unit, B → A
        let invMassA: Float = entityA.isStatic ? 0 : 1 / entityA.mass
        let invMassB: Float = entityB.isStatic ? 0 : 1 / entityB.mass
        let invMassSum = invMassA + invMassB
        guard invMassSum > 0 else { return }         // two statics: nothing to move

        // 1) Position correction with slop, split by inverse mass. Corrects
        //    only the penetration BEYOND the slop, and only a β-fraction of
        //    it per step.
        let correction = positionCorrectionBeta * max(0, contact.depth - penetrationSlop) / invMassSum
        if correction > 0 {
            if !entityA.isStatic {
                entityA.setPosition(entityA.getPosition() + n * (correction * invMassA))
            }
            if !entityB.isStatic {
                entityB.setPosition(entityB.getPosition() - n * (correction * invMassB))
            }
        }

        // 2) Impulse only when approaching (n points toward A, so approaching
        //    means relative velocity along −n). The legacy response applied
        //    impulses to separating contacts too, which can add energy.
        let relativeVelocity = entityA.velocity - entityB.velocity
        let approach = dot(relativeVelocity, n)
        guard approach < 0 else { return }

        // 3) Restitution only above the threshold; below it e = 0 ⇒ the
        //    normal velocity is solved to exactly zero (the support impulse).
        let e = -approach > restitutionVelocityThreshold
            ? min(entityA.restitution, entityB.restitution)
            : 0

        // 4) ALWAYS applied — the deleted minDeltaVelo discard threw away the
        //    per-step support impulse (≈ m·g·dt) that resting requires; that
        //    impulse IS the normal force integrated over the step.
        let j = -(1 + e) * approach / invMassSum
        if !entityA.isStatic {
            entityA.velocity += n * (j * invMassA)
        }
        if !entityB.isStatic {
            entityB.velocity -= n * (j * invMassB)
        }
    }
```

Sanity traces (worth keeping in the doc — they're the review anchors for the regolden):
- **Resting ball on the plane** (plane is B, n = up): each step gravity adds `−g·dt` of normal
  velocity; `approach ≈ −g·dt`, `−approach ≈ 0.16 m/s < 1` ⇒ `e = 0`; `j = m·g·dt` cancels it
  exactly. Gravity never touched; jitter bounded by `g·dt²` (≈ 2.7 mm at 60 Hz, ≈ 68 µm at Phase
  B's 120 Hz — the bound becomes constant when B1's fixed step lands).
- **head_on_pair** (e = 1, equal masses, n = B→A = −x̂ for A on the left): `approach = −10`,
  `e = 1`, `j = 10`; A gets `+n·j·1 = −5 − 5`… i.e. the exact velocity swap, mirror symmetry
  preserved — the golden's semantic asserts survive.
- **Degenerate zero normal** (coincident centers, pinned legacy behavior): zero correction
  direction, `approach = 0` ⇒ guard exits ⇒ no impulse. Same net no-op as the legacy code's
  zero-vector arithmetic.

### File 2 — `EulerSolver.swift` (unification)

- [x] `resolvePair`'s response line becomes the shared corrected call (below). **Amended at
  landing**: the deletion half did NOT happen — `applyLegacyEulerResponse` and its
  `restSpeedThresholdSquared` are retained as clearly-marked, UNREFERENCED reference code
  (project-owner decision, 2026-08-31 changelog); nothing calls them, and
  `CollisionResponseTests.eulerPathRests` + the regoldened `single_bounce_euler` pin the shared
  response as the live path:

```diff
-        applyLegacyEulerResponse(ei, ej, contact: contacts[deepest])
+        HeckerCollisionResponse.applyCollisionResponse(ei, ej, contact: contacts[deepest])
```

The Euler step keeps its own structure (forces → resolve → move); only the per-pair response math
is shared. For up-normal planes the old reflection was already ≈ the impulse response
(`v_y → −e·v_y`, tangent untouched), so `single_bounce_euler`'s divergence signature matches the
0.7 table: identical free fall, first-contact divergence from the correction + threshold, no
wholesale reshape.

### File 3 — `PhysicsEntity.swift` (one comment)

- [x] `shouldApplyGravity`'s `// Hack...` note finally becomes honest:

```diff
-    var shouldApplyGravity: Bool { get set }  // Hack...
+    /// Static/kinematic gravity opt-out, set by authoring only. No longer
+    /// solver state: the response never writes it (the rest latch died in
+    /// Phase A — resting is a per-step contact-impulse equilibrium, research
+    /// §3.2).
+    var shouldApplyGravity: Bool { get set }
```

After this commit, `grep -rn "shouldApplyGravity = " "ToyFlightSimulator Shared/Physics"` must
show **zero writes** outside solver gravity *reads* and authoring sites (`floorPlane`-style
static setup) — that grep is part of the exit criteria.

### Regolden + test changes (same commit)

- [x] **Regolden all six** via the 0.7 command (`TEST_RUNNER_TFS_REGEN_PHYSICS_BASELINES=1`, regen
  run fails by design, clean re-run green). Review the JSON diffs against these expected
  signatures before committing:

| Scenario | Expected diff signature |
|---|---|
| `single_bounce_verlet` / `_euler` | Samples identical through free fall (first contact ≈ step 57: 4.5 m of fall); divergence begins at the first post-contact sample and never before. Bounces persist (impact ≈ 9.4 m/s ≫ threshold; e = 0.9), apex sequence strictly decreasing, ball still airborne-or-settling at step 300 with `finalShouldApplyGravity == true`. |
| `rest_latch` | Wholesale change after first contact (~step 66). Final: gravity **on**, speed ≤ ~one gravity step (g·dt ≈ 0.163 m/s), y within ~3 cm of 0.5 (slop + β-equilibrium residual). The latch's `false`/exact-zero signature must be GONE from the JSON. |
| `head_on_pair` | Identical until impact (~step 18); post-impact the ±x symmetry holds sample-for-sample (mirror-exactness is a review check, not just a tolerance), velocities swap to ±5 on X with lockstep Y fall. |
| `ball_cluster_16` / `stress_grid_50` | Full regolden, no sample-level review expected beyond spot checks; the **chaos-policy invariants must pass UN-EDITED** (finite, no tunneling at 1 m slack, speed budgets) — they were designed to survive exactly this change. If a budget trips, that's a response bug, not a budget to raise. |

- [x] **Flip the characterization test** (PhysicsParityTests.swift) — the old
  `restLatchCharacterization` documented the latch; its replacement documents the equilibrium:

```swift
    @Test("A-response behavior: resting keeps gravity on (the latch is gone)")
    func restingKeepsGravityOn() throws {
        let track = try ParityRunner.run(.restLatch).tracks[0]
        // Support-cycle equilibrium: the e=0 impulse cancels each step's
        // gravity, so the boundary-frame velocity is at most ~one gravity
        // step (g·dt ≈ 0.163 m/s), and the ball floats within slop + β
        // residual of touching. EXACT zeros would be dishonest now — that
        // was the latch's signature.
        #expect(track.finalShouldApplyGravity == true)
        let v = track.finalVelocity
        #expect(simd_length(float3(v[0], v[1], v[2])) <= 0.25)
        // β-equilibrium depth ≈ slop + (per-step gravity sink)/β ≈ 1–2 cm at
        // 60 Hz — the 0.03 bound is deliberately loose; record the observed
        // equilibrium in a comment when the regolden lands, then tighten.
        let restingY = track.samples.last![1]
        #expect(abs(restingY - 0.5) <= 0.03)
    }
```

- [x] **New suite** `ToyFlightSimulatorTests/Physics/CollisionResponseTests.swift` (Metal-free —
  detached bodies through real `PhysicsWorld`s; `.tags(.physics)`). Full listing — these are the
  semantic pins research §4.7 asked for:

```swift
import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Corrected contact response", .tags(.physics))
struct CollisionResponseTests {
    private static let dt: Float = 1.0 / 60.0

    private func makeRestingWorld(updateType: PhysicsUpdateType = .HeckerVerlet)
        -> (world: PhysicsWorld, ball: SphereRigidBody) {
        let ball = SphereRigidBody(detachedAt: [0, 0.499, 0], collisionRadius: 0.5)
        ball.restitution = 0.2
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true
        let world = PhysicsWorld(entities: [ball, plane], updateType: updateType)
        world.useBroadPhase = false
        return (world, ball)
    }

    @Test("resting body keeps gravity on forever (the latch regression)")
    func restingKeepsGravity() {
        let (world, ball) = makeRestingWorld()
        for _ in 0..<600 { world.update(deltaTime: Self.dt) }
        #expect(ball.shouldApplyGravity)
        // β-equilibrium ≈ slop + per-step-sink/β ≈ 1–2 cm at 60 Hz; loose
        // bound on purpose — tighten once the landed equilibrium is measured.
        #expect(abs(ball.getPosition().y - 0.5) <= 0.03)
        #expect(simd_length(ball.velocity) <= 0.25)             // ≤ ~one gravity step
    }

    @Test("a pushed resting body still falls afterward (old latch made it float away)")
    func pushedRestingBodyStillFalls() {
        let (world, ball) = makeRestingWorld()
        for _ in 0..<300 { world.update(deltaTime: Self.dt) }   // settle
        ball.velocity = [0, 3, 0]                               // pop it upward
        for _ in 0..<240 { world.update(deltaTime: Self.dt) }   // 4 s: up ≈ 0.46 m and back
        #expect(ball.shouldApplyGravity)
        #expect(ball.getPosition().y <= 0.6, "gravity must bring it back down")
    }

    @Test("no impulse on separating contacts (legacy applied one, adding energy)")
    func separatingContactGetsNoImpulse() {
        let a = SphereRigidBody(detachedAt: [0, 0, 0], collisionRadius: 0.5)
        a.velocity = [0, 5, 0]
        a.shouldApplyGravity = false
        let b = SphereRigidBody(detachedAt: [0, -0.9, 0], collisionRadius: 0.5)
        b.velocity = [0, -5, 0]
        b.shouldApplyGravity = false
        let world = PhysicsWorld(entities: [a, b], updateType: .HeckerVerlet)
        world.useBroadPhase = false
        world.update(deltaTime: Self.dt)
        // Overlapping (depth 0.1) but separating: position correction may act,
        // velocities must not change (gravity off ⇒ integration is exact too).
        #expect(approxEqual(a.velocity, [0, 5, 0]))
        #expect(approxEqual(b.velocity, [0, -5, 0]))
    }

    @Test("below the restitution threshold even e=1 does not bounce")
    func noBounceBelowThreshold() {
        // 3 cm drop ⇒ impact ≈ 0.77 m/s < 1 m/s ⇒ e forced to 0.
        let ball = SphereRigidBody(detachedAt: [0, 0.53, 0], collisionRadius: 0.5)
        ball.restitution = 1.0
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true
        let world = PhysicsWorld(entities: [ball, plane], updateType: .HeckerVerlet)
        world.useBroadPhase = false
        var maxYAfterContact: Float = 0
        var touched = false
        for _ in 0..<180 {
            world.update(deltaTime: Self.dt)
            let y = ball.getPosition().y
            if y < 0.5 { touched = true }
            if touched { maxYAfterContact = max(maxYAfterContact, y) }
        }
        #expect(touched)
        #expect(maxYAfterContact <= 0.52, "sub-threshold impact must settle, not bounce")
    }

    @Test("above the restitution threshold it bounces at ≈ e·impact")
    func bouncesAboveThreshold() {
        // 2 m drop ⇒ impact ≈ 6.3 m/s; e = 0.5 ⇒ apex ≈ e²·h = 0.5 m above rest.
        let ball = SphereRigidBody(detachedAt: [0, 2.5, 0], collisionRadius: 0.5)
        ball.restitution = 0.5
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true
        let world = PhysicsWorld(entities: [ball, plane], updateType: .HeckerVerlet)
        world.useBroadPhase = false
        var touched = false
        var apexAfterBounce: Float = 0
        for _ in 0..<240 {
            world.update(deltaTime: Self.dt)
            let y = ball.getPosition().y
            if y < 0.55 { touched = true }
            if touched { apexAfterBounce = max(apexAfterBounce, y) }
        }
        #expect(touched)
        #expect(apexAfterBounce >= 0.8 && apexAfterBounce <= 1.15,
                "first rebound apex ≈ 0.5 + e²·2.0 = 1.0 m (window absorbs correction losses)")
    }

    @Test("dynamic pair splits the position correction by inverse mass")
    func correctionSplitsByInverseMass() {
        // Pure-overlap pair at rest, gravity off: only the correction acts.
        // mass 1 vs mass 3 ⇒ displacement magnitudes 3 : 1, moving apart.
        let a = SphereRigidBody(detachedAt: [0, 0, 0], collisionRadius: 0.5)
        a.mass = 1
        a.shouldApplyGravity = false
        let b = SphereRigidBody(detachedAt: [0.9, 0, 0], collisionRadius: 0.5)
        b.mass = 3
        b.shouldApplyGravity = false
        let world = PhysicsWorld(entities: [a, b], updateType: .HeckerVerlet)
        world.useBroadPhase = false
        world.update(deltaTime: Self.dt)
        let movedA = -a.getPosition().x          // A pushed toward −x (n = B→A = −x̂)
        let movedB = b.getPosition().x - 0.9     // B pushed toward +x
        #expect(movedA > 0 && movedB > 0, "correction separates the pair")
        #expect(approxEqual(movedA / movedB, 3.0, tolerance: 1e-3))
    }

    @Test("the Euler path rests too (the reflection hack is gone)")
    func eulerPathRests() {
        let (world, ball) = makeRestingWorld(updateType: .NaiveEuler)
        for _ in 0..<300 { world.update(deltaTime: Self.dt) }
        #expect(ball.shouldApplyGravity)
        #expect(abs(ball.getPosition().y - 0.5) <= 0.03)
        #expect(simd_length(ball.velocity) <= 0.25)
    }
}
```

*(If `approxEqual(_:_:tolerance:)` for scalars doesn't already exist in TestSupport/ApproxEqual,
add the overload there rather than inline.)*

### Interim variable-dt caveat (recorded, accepted)

The response is dt-independent, but the *equilibrium jitter* bound is `g·dt²` with dt still the
frame delta until Phase B: ≈ 10.9 mm at the menu's 30 Hz floor, 2.7 mm at 60, 0.68 mm at 120.
Visible-ish at 30 Hz on close inspection; accepted for the A→B window because B1's 1/120 s fixed
substeps make the bound constant (combined doc D4 already commits to this). Don't tune β/slop to
mask 30 Hz jitter — fix the timestep in B1 instead.

## Step A.7 — The F-22 compound goes live — the A-aircraft commit ✅

The Phase 0-verified spec becomes the player aircraft's real collision geometry. Sequenced AFTER
A.6 deliberately: the compound resting on its fuselage capsule needs the corrected response (under
the legacy response it would rest-latch mid-air on first belly contact and freeze there).

- [x] **FlightboxWithPhysics.applyAircraftSwap** — spec-driven body construction (unauthored
  aircraft keep the legacy sphere, so the F-16/F-18/F-35 swap paths are untouched until their
  specs are written):

```diff
         if let playerAircraft {
-            let acRigidBody = SphereRigidBody(gameObject: playerAircraft)
-            acRigidBody.collisionRadius = 2.0
-            acRigidBody.restitution = 0.2
+            // Compound-spec'd aircraft get the real Phase A body; aircraft
+            // without an authored spec keep the legacy 2 m sphere
+            // (AircraftColliderSpec returns [] for them — the exhaustive
+            // switch forces the decision per type).
+            let spec = AircraftColliderSpec.spec(for: aircraft)
+            let acRigidBody: RigidBody
+            if spec.isEmpty {
+                let sphereBody = SphereRigidBody(gameObject: playerAircraft)
+                sphereBody.collisionRadius = 2.0
+                acRigidBody = sphereBody
+            } else {
+                acRigidBody = RigidBody(gameObject: playerAircraft)
+                acRigidBody.colliders = spec
+            }
+            acRigidBody.restitution = 0.2
+
+            // Debug scaffolding (A.7 exit criterion): named contact reporting,
+            // throttled so a resting aircraft doesn't spam 60 lines/s.
+            let contactLogger = ContactDebugLogger(bodyLabel: playerAircraft.getName())
+            acRigidBody.onContact = { contact, other in
+                contactLogger.log(contact, against: other)
+            }
```

`Aircraft.rigidBody`'s mass-sync `didSet` fires on the init's back-registration exactly as it did
for the sphere (the override is on `Aircraft`, keyed on `RigidBody`, not the subclass), so the
flight-model mass plumbing is untouched either way.

- [x] **File (new):** `ToyFlightSimulator Shared/Physics/Debug/ContactDebugLogger.swift`

```swift
/// Debug-only contact reporter: prints which named collider touched what, at
/// most once per interval per collider name. Installed into RigidBody.onContact
/// (fires on the UpdateThread during the physics step — GameTime is owned by
/// the same thread, so reading it here is safe), so keep it print-only.
final class ContactDebugLogger {
    private let bodyLabel: String
    private let interval: Double
    private var lastLogTime: [String: Double] = [:]

    init(bodyLabel: String, interval: Double = 1.0) {
        self.bodyLabel = bodyLabel
        self.interval = interval
    }

    func log(_ contact: Contact, against other: RigidBody) {
        let name = contact.colliderNameA ?? "body"
        let now = GameTime.TotalGameTime
        if let last = lastLogTime[name], now - last < interval { return }
        lastLogTime[name] = now
        let otherLabel = other.gameObject?.getName() ?? "static geometry"
        print("[Contact] \(bodyLabel).\(name) touched \(otherLabel)"
              + String(format: " (depth %.3f m)", contact.depth))
    }
}
```

- [x] **AircraftColliderSpec doc comment**: flip "Numbers are PLACEHOLDERS until tuned with the
  X-key debug overlay" → "Numbers overlay-verified in-app 2026-08-29 (Phase 0 exit criterion 2);
  now live physics geometry — re-run the X-key overlay after any edit." (This is the deferred
  half of Phase 0 criterion 2's closure.)
- [x] **ColliderDebugOverlay doc note**: the yellow legacy-sphere ghost keys on
  `rigidBody as? SphereRigidBody`, so it disappears for compound-bodied aircraft *by
  construction* — the red volumes are now the LIVE colliders, not a proposal. One doc-comment
  line on `buildVolumes`' ghost branch saying so; zero code change.

### Behavior notes (expected, reviewed in-app — write these into the commit message)

- **Ride height changes**: the sphere held the F-22's origin at y = 2.0 on the ground; the
  fuselage capsule's lowest surface is `localPosition.y − radius = 0.3 − 1.35 = −1.05`, so the
  origin now rests at ≈ 1.05 (minus the β-equilibrium residual). The jet visibly sits lower and
  longer — nose and tail overhang match the hull instead of a 2 m ball.
- **It rests on its belly** — with gear down the wheels clip the ground exactly as they already
  did with the sphere. Correct-looking gear contact is Phase B's raycast suspension
  (`.landingGear` colliders stay reserved); not a regression, just newly visible honesty.
- **Wingtip/tail strikes now exist**: rolling into the ground contacts "wings" (and "empennage"
  when pitched), each reported by name through the logger. The 2 m sphere could never say which
  part hit.

### Metal-free integration pins (new suite `ToyFlightSimulatorTests/Physics/CompoundBodyTests.swift`)

Full listing — this is the A.7 regression net (detached plain `RigidBody` + spec colliders: the
0.6 detached machinery makes the REAL compound path testable without Metal):

```swift
import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Compound body integration", .tags(.physics))
struct CompoundBodyTests {
    private static let dt: Float = 1.0 / 60.0

    /// The live F-22 spec on a detached body settles on its fuselage capsule:
    /// lowest surface = localPosition.y − radius = 0.3 − 1.35 = −1.05, so the
    /// body origin rests at ≈ +1.05 (minus the β-equilibrium residual). The
    /// legacy sphere rested at 2.0 — this pins the compound actually driving
    /// the response, end to end (broad phase AABB union → narrow phase →
    /// corrected response), and pins WHICH collider carries the contact.
    @Test("F-22 compound settles on the fuselage capsule, reported by name")
    func f22CompoundSettlesOnFuselage() {
        let body = RigidBody(detachedAt: [0, 5, 0])
        body.colliders = AircraftColliderSpec.spec(for: .f22_cgtrader)
        body.restitution = 0.2
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true
        let world = PhysicsWorld(entities: [body, plane], updateType: .HeckerVerlet)
        world.useBroadPhase = false

        var contactNames: Set<String> = []
        body.onContact = { contact, _ in
            if let name = contact.colliderNameA { contactNames.insert(name) }
        }

        for _ in 0..<600 { world.update(deltaTime: Self.dt) }

        #expect(body.shouldApplyGravity)
        #expect(simd_length(body.velocity) <= 0.25)
        let restY = body.getPosition().y
        #expect(abs(restY - 1.05) <= 0.05,
                "origin should rest ≈ 1.05 (fuselage capsule bottom), not the sphere's 2.0")
        #expect(contactNames == ["fuselage"],
                "level settle touches the fuselage only — wings/empennage sit higher")
    }

    /// A 90°-banked pose contacts the plane with the WINGS alone — the
    /// wingtip-strike identity the 2 m sphere could never report. Pure
    /// geometry (WorldColliderBuilder + shapeVsPlane), no stepping: detached
    /// bodies can't rotate, and this needs no world — which also makes it the
    /// direct unit pin for rotated compound poses.
    @Test("banked 90°, only the wings box reaches the ground, by name")
    func bankedPoseContactsWingsOnly() {
        let spec = AircraftColliderSpec.spec(for: .f22_cgtrader)
        let roll90 = float3x3(simd_quatf(angle: .halfPi, axis: Z_AXIS))
        var worlds: [WorldCollider] = []
        WorldColliderBuilder.build(spec,
                                   bodyPosition: [0, 5, 0],
                                   bodyRotation: roll90,
                                   uniformScale: 1.0,
                                   into: &worlds)

        var touching: [String] = []
        for collider in worlds {
            if let contact = NarrowPhase.shapeVsPlane(collider,
                                                      planePoint: .zero,
                                                      planeNormal: [0, 1, 0]) {
                touching.append(contact.colliderNameA ?? "?")
                // Rolled wings: half-span 6.6 projects fully onto the plane
                // normal → depth = 6.6 − (5 + rotated local offset) ≈ 1.6.
                #expect(contact.depth > 1.0 && contact.depth < 2.5)
            }
        }
        #expect(touching == ["wings"],
                "at 5 m banked 90°, fuselage (r 1.35) and empennage (3.0 span) stay clear")
    }
}
```

*(`Z_AXIS` exists in Math.swift alongside `X_AXIS` — verified 2026-08-29, no new constant needed.
The quat→matrix spelling was also compile-checked: `simd_float3x3(simd_quatf(angle:axis:))` is the
simd overlay init, and π/2-about-X does map the capsule's local Y axis onto Z as the fuselage spec
assumes.)*

## Step A.8 — Test ledger (Metal-free unless noted, Swift Testing, `.physics` / `.gameObjects` tags) ✅

Suites land inside their step's commit — listed here 0.8-style so nothing is owed at the end:

**A-routing commit:**
- [x] `WorldColliderBuilderTests` (new): known pose compositions (offset × rotation × scale against
  hand-computed positions/rotations — including the fuselage Y→Z capsule); disabled-child omission;
  `scaled(by:)` flowing into shapes; `WorldCollider.aabb` for a rotated capsule and box vs
  hand-computed bounds; empty-collider list → empty output.
- [x] `NarrowPhaseTests` (new): the §4.7 geometry matrix —
  sphere/capsule/box vs **translated AND tilted** planes (known depths/normals/points — the tests
  the y=0 hack made impossible); every `shapeVsShape` nil (separated) case; sphere-in-box
  least-penetration axis (incl. tie determinism); capsule-capsule via `closestPointsOnSegments`
  (parallel, crossing, degenerate-point Ericson cases); capsule-box approximation sanity (contact
  exists where obviously overlapping, nil where obviously clear); flipped-pair metadata (named
  capsule vs named sphere both ways — A metadata stays on A); **legacy-exact sphere-sphere pins**:
  inclusive boundary (surfaces exactly touching ⇒ contact, depth 0) and coincident centers ⇒ zero
  normal; plane-as-A flip (normal negated, names swapped, deepest index valid into the array).
- [x] `RigidBodyTests` additions: `worldColliders()` rebuilds after `setPosition` /
  `invalidateWorldColliders` / `colliders` mutation (and NOT in between — cache identity check);
  `SphereRigidBody` view = world-meter radius at live position with nil metadata;
  `collisionRadius.didSet` invalidates; compound `getAABB` union on a detached multi-collider
  body + empty-list fallback to the legacy delegate.
- [x] Filtering: mask-combination truth table on detached bodies (`shouldCollide` is pure); the
  same-GameObject exclusion lives in **`PhysicsWorldSmokeTests`** (app-hosted — GameObjects are
  legal there, per the Metal-free-design rule's split).
- [x] `PhysicsParityTests`: UNCHANGED, green against UNCHANGED goldens — this suite *is* the
  routing gate, plus the byte-identical regen dry-run from A.5.
- [x] Mechanical edits: `TestRigidBody` loses `collisionShape`; `RigidBodyTests` loses its four
  `.collisionShape` expectations; solver-step test call sites gain the scratch argument.
  (Bonus effect worth a test: `TestRigidBody` pairs — which the legacy narrow phase would
  force-cast-crash on — now safely yield zero contacts: no colliders, no legacy shape.)
- [x] `PhysicsWorldSmokeTests` addition: `onContact` fires for an attached colliding pair
  (event plumbing smoke on the GameObject-backed path).

**A-response commit:**
- [x] `CollisionResponseTests` as listed in A.6 (the semantic pins: latch regression, approach
  guard, threshold both sides, inverse-mass correction split, Euler-path rest).
- [x] `PhysicsParityTests`: regoldened baselines + the flipped characterization test.

**A-aircraft commit:**
- [x] `CompoundBodyTests` as listed in A.7 (settle-by-name; banked-wings-only).
- [x] `AircraftColliderSpecTests`: unchanged and green (the spec is now load-bearing — its
  existing name/dimension/anchor pins carry more weight, none change).

## Phase A non-goals (deferred, with their homes)

Fixed timestep + force generators (B1); raycast gear suspension (B2 — `.landingGear` colliders
stay reserved); crash/landing *classification* on the contact events (B3); **sleeping** (the
legitimate optimization the rest latch was a broken version of — post-A, research §3.2's closing
note); assigning non-default `CollisionCategory` values to scene bodies (when filtering is first
needed); box-box narrow phase and exact capsule-box (Phase C/D, if fidelity demands); CCD (D+);
angular response consuming `Contact.point` (D); migrating ball call sites from
`collisionRadius` to local-space colliders (only if something needs it); overlay/menu parity on
iOS (unchanged from Phase 0's non-goals).

## Phase A exit criteria

1. - [x] **A-routing is invisible**: full serial suite green against unchanged goldens; the regen
   dry-run rewrites all six baselines **byte-identical** (`git diff --exit-code` on Baselines/);
   `PhysicsWorldSmokeTests` untouched and green; FlightboxWithPhysics plays identically by eye
   (balls still bounce, settle, and latch exactly as before this commit).
2. - [x] **A-response semantics hold**: regoldens reviewed against the A.6 signature table and
   committed; `CollisionResponseTests` green (latch regression included); the flipped
   characterization test green; chaos-policy invariants passed **un-edited**;
   `grep -rn "shouldApplyGravity = " "ToyFlightSimulator Shared/Physics"` shows zero writes
   outside authoring/setup sites.
3. - [x] **General planes are correct**: `NarrowPhaseTests`' tilted + translated plane cases green
   (the y=0 hardcode is deleted, not routed around).
4. - [x] **The compound is live and speaks**: `CompoundBodyTests` green (settles at ≈ 1.05 on
   "fuselage"; banked pose reports "wings" only); in-app, a belly touch logs `fuselage`, a rolled
   touch logs `wings`, and the overlay's red volumes match the live collider set (yellow ghost
   gone for the F-22 — by design). *(All confirmed by the project owner 2026-08-31: ground
   contact, the rolled-touch log — `[Contact] F-22_CGTrader.wings touched Quad (depth 0.007 m)`
   — and the red-volumes-only overlay.)*
5. - [x] **No process-wide state**: the parity determinism test stays green, the full suite passes
   under Swift Testing's default in-process concurrency, and review confirms no static mutable
   state was added anywhere in the step path (correction 1 held).
6. - [ ] **CI green** on all three commits (serial app-hosted run, as configured).
7. - [ ] **Perf sanity**: PhysicsStressTestScene frame rate and broad-phase stats comparable
   pre/post (the routed path adds one narrow phase per pair — replacing two — plus one array
   append per contact; nothing else joined the hot path). *(Status 2026-08-31: BallPhysicsScene
   feels right and holds > 60 fps even at the contact-heavy start. The all-black stress scene
   was BISECTED — NOT a Phase A regression (identical at pre-Phase-A `ae1c8f4`; branch
   `pre-phase-a-stress-check`): the scene's DebugCamera at [0, 15, +40] faces +Z — away from
   the sphere grid — a leftover from before the +Z-forward migration; flipping it to z = −40
   on the test branch renders the scene. The camera fix on main is the owner's follow-up
   commit. The STATS leg was measured meanwhile via stdout (the scene logs even while black):
   50 spheres BP-on avg step 0.49–0.74 ms pre vs 0.67–0.94 ms post (~1.4× — the expected cost
   of the collider narrow phase plus resting bodies doing real support-impulse work every step
   instead of sitting latched; ~5% of a 60 fps frame), broad-phase reduction identical
   (93–95% both eras), 100 spheres ~1.5 ms post. The camera fix landed on main the same day
   (z = −40; rendering verified by screenshot — spheres visible and settling; the −15° pitch
   confirmed correct by the branch framing geometry). Remaining for this box: the owner's
   frame-rate/feel pass on the now-visible scene.)*

**Implementation order within Phase A:** A.1 → A.2 → A.3 → A.4 → A.5 as ONE commit (A-routing,
gated by criterion 1) → A.6 as one commit (A-response, gated by criterion 2) → A.7 (A-aircraft,
gated by criterion 4). A.8's suites land inside their listed commits. No step may straddle a
commit boundary: the 0.7 protocol (now three-way) is the verification story, and it only works if
each commit is exactly one of "routing", "response", "geometry".

---

*(Phase B plan will be appended here.)*
