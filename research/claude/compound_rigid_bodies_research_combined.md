# Compound Rigid Bodies — Combined Research & Implementation Plan

**Date:** 2026-07-18
**Inputs:**
- `research/claude/compound_rigid_bodies_research_2026-07-14.md` ("the Claude doc") — deep-research pipeline with adversarial claim verification, plus a TFS-specific phased plan (A–D).
- `research/codex/compound_rigid_bodies_and_articulated_landing_gear_research_2026-07-14.md` ("the Codex doc") — engine-survey research plus a broader refactor proposal (Phases 0–5) including 6-DOF dynamics and a Jolt-integration option.
- A fresh audit of the current code (`Physics/`, `GameObjects/Node.swift`, `GameObjects/Aircraft.swift`, `Scenes/FlightboxWithPhysics.swift`) — every code claim below was re-verified against the working tree on 2026-07-18.
- Six open questions raised in review of the Claude doc (answered in §3; the answers materially changed the recommended design — see §4.0).

**Purpose:** Compare and contrast the two research docs, resolve their disagreements, answer the open questions, and produce one recommended implementation plan with code.

---

## Executive Summary

The two docs were researched independently (different pipelines, different source sets) and **converge on every load-bearing conclusion**. That convergence is itself the strongest result: the industry pattern for "collision that matches the object's shape" is unambiguous.

**Consensus (both docs, independently verified):**

1. A complex rigid object is **one rigid body with many primitive colliders** (a compound), not many bodies. Joints are for *mechanisms* (parts that move relative to each other under physics), not for assembling a hull.
2. The primitive vocabulary is **sphere / capsule / box** (+ convex hull later; plane and triangle mesh static-only). Dynamic concave meshes are effectively banned across engines.
3. **Landing gear is not made of bodies.** The industry pattern (Bullet `btRaycastVehicle`, Jolt `VehicleConstraint`, Unity `WheelCollider`, JSBSim `FGLGear`) is raycast/sweep **suspension struts on the aircraft body**: spring + damper force at the strut, gated by the existing gear animation scalar. Animation owns *deployment*; physics owns *compression*.
4. **Control surfaces never get bodies** — they are animation + aerodynamic force contributions.
5. Narrow phase must produce a **`Contact`** (normal, depth, point, sub-collider identity), not a boolean; crash-vs-landing classification is a *collider-role + contact-event* problem, not a geometry problem.
6. **Collision filtering** (category/mask bits) should exist before object counts grow.
7. **Angular dynamics (orientation, torque, inertia tensors) are the prerequisite for joints**, contacts-with-lever-arms, and torque-true touchdowns — and the gear model may never need joints at all.
8. The **rest hack** (`shouldApplyGravity = false`) must be removed, not worked around: gravity stays on, resting is an emergent property of per-step contact impulses.
9. Physics stays on the UpdateThread, CPU-side; Metal's role is **debug visualization** of colliders/contacts.

**Material disagreements, and the verdicts (argued in §2):**

| # | Topic | Codex doc | Claude doc | Verdict |
|---|---|---|---|---|
| D1 | Where collider lists live | `colliders` array on `RigidBody` itself | New `CompoundRigidBody` subclass | **Codex** — flat data on `RigidBody`; the subclass buys nothing (§3.5) |
| D2 | Angular dynamics sequencing | Early (Phase 2, before gear) | Late (Phase D, after gear) | **Claude** — linear-first ships value sooner; but adopt Codex's prep (contact points, force-at-point API) early |
| D3 | Contact multiplicity | Full manifolds per collider pair; never dedupe by body | Deepest single contact per body pair | **Hybrid** — collect *all* collider-pair contacts (events/classification need them); linear response consumes the deepest |
| D4 | Fixed timestep | Yes, 1/120 s accumulator now | Keep variable dt, note the risk | **Codex** — the menu exposes 30–120 Hz refresh; physics behavior must not vary with display rate |
| D5 | Update-order fix | Three-phase participant protocol | Accept the one-frame force latency | **Middle path** — keep the current step site, move force computation *into* the step via per-substep force generators (§3.3) |
| D6 | Rest-hack treatment | Remove it (inside a full solver rewrite) | Per-body `freezeOnRestingContact` opt-out flag | **Codex's principle, implemented now** — the correct fix doesn't need the full solver (§3.2); the opt-out flag would leave a latent bug on every other body |
| D7 | Build vs buy | Seriously evaluate Jolt behind an adapter | Custom Swift assumed | **Custom Swift**, with Codex's backend-agnostic authoring layer kept as the Jolt exit ramp (§4.6) |
| D8 | Skeleton→collider binding | `jointModelPoses` diff in `Skeleton` now | Not needed in early phases | **Claude** — fixed strut/collider offsets are adequate through Phase C; touch the (subtle, tested) skinning path only when mid-transit gear collision matters |

**The combined plan** (§4): Phase 0 — collider debug overlay + parity tests. Phase A — shape vocabulary and `LocalCollider`/`WorldCollider` on `RigidBody`, a pure-function `NarrowPhase` emitting all contacts, filtering masks, contact events, and the rest-hack replacement (restitution velocity threshold + always-applied impulses + penetration slop). Phase B — fixed-timestep accumulator with per-substep force generators, then raycast landing-gear suspension and crash classification. Phase C — static structures. Phase D — angular dynamics → sequential impulses → joints only if gameplay ever demands them. Phase E — an explicit go/no-go gate for Jolt before Phase D.

---

## 1. Where the two docs agree (and why that matters)

Both docs surveyed overlapping but non-identical engine sets (both: Unity/PhysX, Bullet, Jolt, Box2D; Codex additionally: Unreal/Chaos, Godot, JSBSim, MSFS; Claude additionally: Defold, with adversarial verification of each claim). They agree on all nine consensus points above. Two agreements deserve emphasis because they kill tempting wrong turns:

**"More precise collision" does NOT mean mesh collision.** Both docs independently found that every engine bans concave triangle meshes on dynamic bodies (Unity runtime-errors; PhysX requires an SDF escape hatch; Bullet routes them to static geometry) and caps even convex hulls (PhysX: 255 vertices/faces) *specifically to force decomposition into a handful of primitives*. Three to six primitives per aircraft is not a cheap approximation of the right answer — it **is** the right answer, as shipped by Unity, Unreal, Jolt, and Bullet titles.

**"Articulated landing gear" does NOT mean jointed landing gear.** Both docs independently landed on the same three-level fidelity ladder and both recommend the same rung: one aircraft body + animated gear geometry + raycast suspension forces. Codex cites JSBSim's `FGLGear` (compression → spring/damper → force *and moment* applied at the gear point); Claude cites Bullet's manual verbatim ("the entire vehicle is represented as a single rigidbody... collision detection of the wheels is approximated by ray casts"). Full articulations (Codex Level C / Claude's "separate bodies + hinges") are flagged by both as a much later, possibly-never tier.

Since the docs were produced independently, treat these shared conclusions as **settled** — the design below does not revisit them.

---

## 2. Where they differ — analysis

### D1. `CompoundRigidBody` subclass vs. colliders on `RigidBody`

The Claude doc adds a `CompoundRigidBody: RigidBody` subclass holding the collider list, plus a `.Compound` case in `CollisionShape`; legacy `SphereRigidBody`/`PlaneRigidBody` stay untouched and the narrow phase adapts between them. The Codex doc puts `colliders: ContiguousArray<Collider>` directly on `RigidBody` and retires shape-based subclass dispatch entirely.

**Verdict: Codex.** The full argument is §3.5 (it was one of the open questions). Summary: the subclass has *no* performance benefit — the hot loops already store concrete `RigidBody` (see `NOTE(P6)` in PhysicsWorld.swift:24), and a subclass actually adds `as?` downcasts to every world-collider access. It also forces transitional churn: adding `.Compound` to `CollisionShape` breaks the exhaustive `(shape, shape)` switches in `PhysicsWorld.collided`/`getCollisionData`, so you'd extend dead code just to delete it a phase later. The Claude doc's subclass was a migration tactic, not an end state; going directly to the flat design skips a full rewrite-the-rewrite cycle.

### D2. When to build angular dynamics

Codex sequences 6-DOF rigid bodies (quaternion pose, angular velocity, inertia, contact manifolds with lever arms) as Phase 2, *before* the gear model; Claude defers all of it to Phase D, shipping gear on the existing linear-only solver.

**Verdict: Claude's sequencing, Codex's preparation.** Linear-only gear already delivers the original ask — the aircraft rests and lands *at its wheels' actual positions* instead of on a 2 m sphere, and belly/wingtip/tail strikes classify correctly. That is shippable weeks before a solver rewrite. What linear-only cannot do is *torque from asymmetric contact* (one-wheel touchdown rolling the aircraft, nose settling after main-gear touchdown) — worth having, not worth blocking on. But Codex is right that retrofitting is expensive if the data model didn't plan for it, so Phase A/B bake in the cheap preparation: `Contact.point` is produced from day one, the narrow phase returns *all* contacts (D3), and `addForce(_:atWorldPoint:)` exists from Phase B (accumulating torque into a field the integrator ignores until Phase D — documented as such).

### D3. One contact per body pair vs. manifolds per collider pair

Claude's narrow phase returns the single deepest contact per body pair, justified because a linear-only response can only apply one impulse anyway. Codex insists on manifolds keyed by collider pair: "a fuselage and both wheels may legitimately contact the runway in one step; each manifold matters. De-duplicate by collider pair and feature ID, not by body identity."

**Verdict: hybrid, leaning Codex.** The *response* can keep consuming the deepest contact while the solver is linear-only (on flat ground all airframe-vs-plane contacts share a normal, so one impulse + position correction along it resolves the set). But *classification and events* need every contact: a simultaneous wingtip + belly scrape must report both colliders, and touchdown telemetry wants per-strut data. So `NarrowPhase.generateContacts(into:)` appends **all** collider-pair contacts to a scratch array; the response picks the deepest per body pair; `onContact` fires per contact. When Phase D's sequential-impulse solver lands, the response-side "deepest" filter is deleted and nothing else changes shape.

### D4. Fixed timestep

Codex: fixed `1/120 s` accumulator with bounded substeps, now. Claude: keep render-frame dt, listing sub-stepping only as a touchdown-oscillation fallback.

**Verdict: Codex, promoted to a Phase B prerequisite.** Three reasons, one of them TFS-specific:
- The menu's `RefreshRatePicker` runs the game at 30–120 Hz, and `physicsWorld.update(deltaTime:)` currently consumes raw `GameTime.DeltaTime` — physics behavior *today* varies with the selected refresh rate. Codex's exit criterion ("30/60/120 Hz rendering produces nearly identical physics trajectories") names the right invariant.
- Suspension springs sized for a 30 t aircraft (`k ≈ 1.1 MN/m`, §4.3) are stiff relative to a long variable frame; a fixed small step plus the accumulator's spiral-of-death clamp bounds the worst case (and replaces the ad-hoc `GameTime.DeltaTime < 1.0` guard in `FlightboxWithPhysics.doUpdate`).
- The rest-hack replacement (§3.2) stabilizes at "jitter ≈ g·dt²" — fixed dt makes that bound constant.

### D5. Update ordering

Codex proposes a three-phase `PhysicsParticipant` protocol (`preparePhysics` / `accumulateForces` / `didSimulatePhysics`); Claude documents the existing one-frame force latency and lives with it.

**Verdict: a middle path that came out of answering open question 3 (§3.3).** Keep the physics step exactly where it is (top of the scene's `doUpdate`, *before* children traverse — that placement is what lets children, including the attached camera, see post-physics transforms in the same frame). Fix the latency by moving force *computation* into the step: the world calls registered force generators once per fixed substep. That is Codex's `accumulateForces` phase, minus the other two phases until something needs them. Do **not** reorder `Node.update()` — §3.3 explains why that breaks parent→child data flow.

### D6. The rest hack

Codex: "do not turn gravity off to fake resting contact" — but embeds the fix inside the full Phase-2 solver rewrite. Claude: add `freezeOnRestingContact = false` so the *aircraft* opts out while every other body keeps the hack.

**Verdict: neither; fix it for all bodies in Phase A, no solver rewrite required.** The audit (§3.2) found the hack is worse than either doc recorded: `shouldApplyGravity = false` is a **one-way latch** — nothing in the codebase ever sets it back to `true` — and it interlocks with a second hack (`minDeltaVeloSquared` discarding impulses below 1 m/s) such that removing either alone breaks resting. The correct replacement (restitution velocity threshold + always-applied impulses + slop-based position correction) is ~30 lines inside the existing `HeckerCollisionResponse` and benefits every scene, not just the aircraft. Claude's opt-out flag would have shipped a latent float-away bug for every ball that ever comes to rest and later gets pushed.

### D7. Build vs. buy (Jolt)

Codex gives Jolt a serious treatment: macOS/iOS support confirmed, a narrow `PhysicsBackend` protocol sketched, and a recommendation to spike it before committing to Phases 2–5 from scratch. Claude assumes the custom Swift path throughout.

**Verdict: continue the custom Swift engine, keep the exit ramp.** This project's evident purpose is owning the machinery — the renderer, solvers, animation system, and broad phase are all hand-built, and phases A–C are well inside what the existing codebase can absorb. But Codex's structural advice costs nothing and is adopted: collider specs, gear specs, and contact-event consumers are plain data / narrow protocols with no solver types leaked through them, so if Phase D's scope (sequential impulses, warm starting, stacking, CCD, convex hulls) ever exceeds appetite, a Jolt adapter swap replaces the *core* without touching the authoring layer. §4.6 defines the explicit decision gate.

### D8. Skeleton binding for collider poses

Codex includes a `Skeleton.jointModelPoses` diff (preserving raw model-space joint transforms alongside the skinning palette) so physics colliders can follow animated joints. Claude's phases A–C never bind colliders to the skeleton — struts are fixed body-local offsets, gear state arrives as one scalar (`gearAnimationProgress`).

**Verdict: Claude for now.** The strut attach points barely move relative to the airframe in the deployed state, and the deployment gate is already a scalar. `Skeleton.evaluateWorldPoses` is subtle (basis conjugation, in-place palette write, allocation-free) and covered by tests; touching it buys nothing until either (a) mid-retraction gear collision must be detected against the actual swinging geometry, or (b) per-joint colliders (control surfaces, doors) arrive. Park Codex's diff — it is the right shape when that day comes, including its test list (rest-pose composition, skinning-output invariance, `B⁻¹·J·B` convention).

### Minor differences, quickly resolved

- **Collider material:** Codex puts `PhysicsMaterial` (friction, restitution) per collider; Claude reuses body-level `restitution`. → Body-level until tangent friction exists (Phase D); the `LocalCollider` struct reserves the field as optional so specs don't churn.
- **Collider roles:** Codex's `AircraftColliderPart` enum is aircraft-specific (its own doc flags this); Claude's `ColliderGroup` (.airframe/.landingGear/.structure) + free-form name is generic. → Claude's shape.
- **Capsule axis:** Codex encodes an axis enum; Claude orients via `localRotation`. → Claude — one concept fewer, and the rotation is needed anyway.
- **Compression velocity:** Codex derives it by finite difference of compression; Claude projects body velocity onto the strut. → Finite difference (equivalent today, stays correct when attitude dynamics start moving the strut, and it needs no point-velocity machinery).
- **Suspension damping:** Codex splits compression vs. rebound damping and clamps to `maxSupportForce` (feeding a gear-overload event); Claude has one damping rate. → Codex's split, it's three lines and the overload event is the hook crash scoring wants.
- **Debug visualization:** Same idea in both; Claude's (translucent existing meshes as child nodes, auto-registered as transparent renderables) reuses the render path as-is; Codex's ring-buffered wireframe instancing is the eventual nicer version. → Claude's first.
- **CCD:** Codex lists sweep/speculative CCD for missiles/fast debris in Phase 4; Claude omits it. → Noted as a Phase D+ item; nothing earlier needs it (the aircraft is large relative to per-step travel; weapons currently despawn on proximity, not contact).

---

## 3. Answers to the open questions

These were asked about the Claude doc specifically; the answers below are grounded in the current code and fed directly into §4's design (traceability table in §4.0).

### 3.1 What is an inertia tensor, and how does it apply to a game engine?

**Mass is to pushing what the inertia tensor is to twisting.** Newton's second law has two halves for a rigid body:

```
F = m·a                 (linear:  force    → acceleration,          m is a scalar)
τ = I·ω̇ + ω × (I·ω)     (angular: torque   → angular acceleration,  I is a 3×3 matrix)
```

`I` is the **inertia tensor**: a symmetric 3×3 matrix (units kg·m²) that encodes how the body's mass is *distributed* around its center of mass. It must be a matrix, not a scalar, because resistance to rotation depends on the axis: an F-22 has most of its mass packed close to the roll axis (long, slender fuselage) but spread far from the pitch and yaw axes (nose-to-tail distance), so `Ixx` (roll) is much smaller than `Iyy`/`Izz` — which is *why* real fighters roll fast and pitch slower. The diagonal entries are the moments of inertia about each axis; the off-diagonal entries (products of inertia) are zero when the axes align with the body's symmetry planes, which is why engines prefer principal-axis frames (Bullet's `calculatePrincipalAxisTransform` exists exactly to find that frame for a compound).

In a game engine the tensor shows up in exactly three places:

1. **Integration.** Each step: `ω += I_world⁻¹ · τ · dt`. You store `I_body⁻¹` (constant, body space) and conjugate into world space by the current rotation: `I_world⁻¹ = R · I_body⁻¹ · Rᵀ`. The gyroscopic term `ω × (I·ω)` is what makes tumbling objects wobble (the "tennis-racket theorem"); games commonly drop it at first — both docs agree it's optional in the first milestone.
2. **Contact/constraint impulses.** The impulse denominator at a contact point with lever arm `r` is `1/mA + 1/mB + n·((I_A⁻¹(r_A×n))×r_A) + n·((I_B⁻¹(r_B×n))×r_B)` — the "effective mass" felt along the normal at that point. This term is why an off-center hit spins a body: the same impulse produces `Δω = I⁻¹(r × j·n)`. Without a tensor there is no lever arm, which is precisely why today's `HeckerCollisionResponse` is the point-mass reduction of Hecker's formula.
3. **Authoring.** Primitives have closed forms (solid sphere `(2/5)mr²·𝟙`; box `Ixx = m(h_y²+h_z²)/3` in half-extent form; capsule = cylinder + two half-spheres via the parallel-axis theorem), and compounds compose by summing child tensors rotated into the body frame plus parallel-axis translation terms — the `composeMassProperties` sample in the Claude doc §2.6. For aircraft, both docs agree: **author** mass/COM/inertia per aircraft (fuel, engines, and stores dominate the distribution, not uniformly-dense collision boxes), and freeze it — don't recompute as the gear animates (Unity's documented COM caveat; PhysX's `setLocalPose` likewise never auto-updates inertia).

TFS connection: the engine already fakes the tensor's *effect* kinematically — `AttitudeDynamics` gives each axis its own `maxRate` and time constant τ, which is a hand-tuned stand-in for `I` being different per axis. Phase D replaces the fake with the real thing: control-surface and gear-contact torques feed `ω̇ = I⁻¹τ`, and the per-axis feel gets tuned through the tensor + damping instead of rate caps.

### 3.2 How can the "rest hack" be properly and correctly fixed?

**What the hack is** (`HeckerCollisionResponse.applyCollisionResponse`, lines 57–80): when relative speed against a static body drops below 0.55 m/s, the code zeroes velocity *and* sets `shouldApplyGravity = false`. The audit found two aggravating facts neither doc fully recorded:

- **It is a one-way latch.** `shouldApplyGravity = false` appears in exactly two places (both in the hack); *nothing ever sets it back to `true`*. A ball that comes to rest and is later hit by another ball gets impulse-driven velocity but no gravity — it drifts off horizontally and never falls again.
- **It interlocks with a second hack.** `minDeltaVeloSquared = 1.0` discards any impulse whose Δv < 1 m/s. Remove the rest branch alone and resting still breaks: the per-step contact impulse a resting ball needs is Δv ≈ g·dt ≈ 0.16 m/s at 60 Hz — below the discard threshold — so the ball would sink through the floor. Both hacks must go together.

**Why the hack exists:** without it, a resting body integrates gravity each step, gains downward velocity, penetrates, and the restitution impulse bounces it — micro-bouncing forever (or sinking, with the discard hack). The hack treats the *symptom* (jitter at rest) by freezing state. The correct treatment makes rest an **equilibrium the contact solver reproduces every step**, which is what every production engine does:

1. **Restitution velocity threshold.** Only bounce above a normal approach speed of ~1 m/s; below it use `e = 0`, so the impulse solves the normal velocity to exactly zero instead of reflecting it. (Box2D's `b2_velocityThreshold` and Jolt's restitution threshold are both ~1 m/s.) At rest the step-to-step cycle becomes: gravity adds `−g·dt·n̂`; the e=0 impulse cancels it. Positional jitter is bounded by `g·dt²` ≈ **68 µm** at 120 Hz — invisible.
2. **Always apply the impulse** — delete the `minDeltaVeloSquared` discard. Small impulses are not noise; they *are* the support force (`j ≈ m·g·dt` per step is literally the normal force integrated over the step).
3. **Skip separating contacts.** Only apply an impulse when the bodies approach (`dot(v_rel, n) < 0`) — the current code applies regardless, which can add energy.
4. **Position correction with slop.** Instead of teleporting by the full depth (the current code even pushes `penetrationDepth * 2` in the static branches — an outright bug that doubles the correction), correct a *fraction* of the penetration beyond a small allowance: `correction = β · max(0, depth − slop)`, with β ≈ 0.2 and slop ≈ 5 mm. The slop leaves contacts measurably touching (stable), and β damps correction-induced energy.
5. **Gravity is never touched.** `shouldApplyGravity` reverts to what it was designed for (static bodies, kinematic objects) and stops being solver state.

Concretely (Phase A diff in §4.2): delete the rest branch, delete the discard, add the threshold/slop constants, add the approach guard, fix the ×2. No sequential-impulse solver is required for this — it drops into the existing single-impulse response.

**Sleeping is the *optimization*, not the fix.** Real engines additionally put bodies to sleep (skip integration) after their velocity stays below thresholds for ~0.5 s — but sleep is (a) island-based (a sleeping box under a falling box must wake), (b) fully reversible on any new contact/force, and (c) state-preserving. It's worth adding *after* Phase A for the stress-test scenes, and the aircraft simply sets `allowSleep = false` (a body held up by per-substep suspension forces must never sleep). The current hack is best understood as sleep's three properties done wrong: pair-triggered, irreversible, and state-destroying.

### 3.3 Can `doUpdate()` run *after* traversing children in `Node.update()`? Should physics step after the whole tree updates?

**Reordering `Node.update()`: no — your instinct is correct.** `Node.update()` (Node.swift:135) runs `doUpdate()` first, then pushes `parentModelMatrix` down and recurses. Children-first would break both data flows that the current order guarantees:

- **Logic flow (your planet-orbiting-sun case):** any child whose `doUpdate` reads parent state — an orbiting body reading the planet's position, the `AttachedCamera` following the aircraft, control-surface children reading aircraft input state — would consume *last frame's* parent state. One frame of lag on everything parented, forever.
- **Transform flow:** the traversal is what propagates a parent's new world matrix into children (`child.parentModelMatrix = world; child._transformDirty = true`). Children-first would mean a parent that moves in `doUpdate` renders correctly itself while its whole subtree renders at last frame's parent transform. That is precisely the camera/aircraft desync class the update/render semaphore handshake was built to eliminate.

So the traversal order is not an implementation accident — it's the contract ("`update()` computes the world matrix once for all children"). Leave it alone.

**Stepping `physicsWorld` after the full traversal: valid, but it has a hidden cost.** This was the Codex doc's phase ordering (forces accumulate during traversal → substeps run → poses publish). It genuinely fixes the force latency. But whoever moves bodies *after* traversal inherits the transform-flow problem above: `setPosition` on the aircraft dirties its subtree, and nothing re-pushes `parentModelMatrix` into the children before `writeFrameSnapshot` reads matrices — so the attached camera (a child of the aircraft!) would view from the pre-physics pose while the aircraft renders at the post-physics pose. Fixing *that* requires a second propagation pass over physics-moved subtrees between the step and the snapshot. Workable (the pass is cheap — only dirty subtrees), but it's new traversal machinery and a new ordering invariant to defend.

**The recommended fix needs neither.** Notice *why* the current call site is actually well-placed: `FlightboxWithPhysics.doUpdate` steps physics at the **top of the scene root's `doUpdate` — before any child updates**. Bodies move first; then the normal traversal propagates every new transform to every child the same frame. The camera never lags. The only real defect in today's ordering is that **forces are computed in the wrong place** — `Aircraft.doUpdate` (a child, running after the step) writes `rigidBody.force`, which the step only consumes *next* frame.

So: move the force *computation* into the step, not the step after the forces. `PhysicsWorld` gains registered **force generators**, called once per fixed substep (§4.3):

```
UpdateThread frame:
  scene.doUpdate                      ← physics steps HERE (unchanged site)
    physicsWorld.update(frameDelta)
      per fixed substep:
        forceGenerators.accumulate()  ← flight model + suspension, from LIVE state
        broad phase → contacts → response → integrate → zero forces
  children traverse                   ← aircraft: input sampling, attitude, animation
                                        camera & subtree see post-physics transforms
  writeFrameSnapshot                  ← coherent
```

This removes the one-frame *force* latency entirely (forces are now computed from current-substep state, which is what stiff suspension springs need for stability), keeps parent-before-child semantics untouched, and needs no second propagation pass. The remaining one-frame *input* latency (stick input sampled in `Aircraft.doUpdate` feeds the next frame's substeps) is ~8–16 ms — standard in engines that decouple input sampling from fixed steps, and imperceptible next to the attitude filter's time constants. Gear-animation progress read by the suspension is similarly one frame stale; gear extension takes seconds, so this is irrelevant.

Codex's fuller three-phase protocol (`preparePhysics`/`accumulateForces`/`didSimulatePhysics`) remains the end state if more hooks are ever needed (e.g., post-step strut-compression visuals); the force-generator hook is its middle phase, shipped alone.

### 3.4 What is the difference between `LocalCollider` and `WorldCollider`? Why two types?

They are different data with different lifetimes, mutability, and consumers — the same split the engine already uses for transforms, where a node's **local** position/rotation (authored, mutable) is distinct from its cached **world** `modelMatrix` (derived, rebuilt when dirty).

| | `LocalCollider` | `WorldCollider` |
|---|---|---|
| **What it is** | The *authored spec*: shape dimensions in model space, offset from the body origin, group/role, enabled flag | A *derived snapshot*: the same shape transformed into world space for one physics step |
| **Lifetime** | Persistent — lives as long as the body | Scratch — valid for exactly one step (`frame:` cache token) |
| **Mutated by** | Authoring, tuning, animation (`isEnabled`, future animated poses) | Nobody — it's read-only output |
| **Consumed by** | Spec authoring, debug overlay setup, tests | Broad phase (AABB union), narrow phase (every candidate pair), debug draw |
| **Space** | Body/model space (survives the body moving) | World space (invalidated every time the body moves — i.e., every frame) |

Why not one type with both sets of fields? Because the world-space half would be *stale by construction* — the body moves every frame, so a merged type would carry world fields that are only valid immediately after some recompute call, and nothing in the type system marks when. That's an aliasing/staleness bug generator (exactly the class of bug the Node matrix cache solves with explicit dirty flags and generation counters). Two value types make the contract structural: if you're holding a `WorldCollider`, someone already resolved the frame it belongs to; the narrow phase takes only `WorldCollider`s and becomes a **pure function** — which is what makes it unit-testable Metal-free, per the project's test-design rule.

The Codex doc technically fuses them (`Collider` + a `worldCollider(at:)` accessor computing poses on demand) — workable, but materializing the snapshot once per step is better here because each world pose is consumed multiple times (its AABB for the broad-phase union, then narrow-phase tests against potentially several partners, then debug draw), and the reused scratch array (`worldScratch.removeAll(keepingCapacity: true)`) keeps it zero-allocation steady-state, matching the broad phase's existing discipline.

### 3.5 Why a new `CompoundRigidBody` type instead of refactoring `RigidBody`? Is there a performance benefit to two body types?

**There is no performance benefit — and the combined plan drops the subclass.** Measured against how the code actually dispatches:

- The solver/broad-phase loops store **concrete `RigidBody`** (`PhysicsWorld.entities: [RigidBody]` — see the `NOTE(P6)` comment), so method calls are direct class dispatch either way. Adding stored properties to `RigidBody` doesn't change that.
- Per-instance cost of putting `colliders` on every body is one array reference + a couple of small fields (~tens of bytes); at this entity count (dozens) it's unmeasurable. A `ContiguousArray<LocalCollider>` of value types is cache-tight regardless of which class holds it.
- The subclass actually *adds* work on the hot path: every narrow-phase access needs an `as? CompoundRigidBody` / `as? SphereRigidBody` adapter (visible in the Claude doc's `worldColliders(of:)`), where the flat design just reads `body.colliders`.
- Transitional churn: the subclass design adds `case Compound` to `CollisionShape`, which breaks the exhaustive `(shape, shape)` switches in `PhysicsWorld.collided`/`getCollisionData` — code that Phase A deletes anyway. You'd be extending dead code to keep it compiling for one phase.

The honest reading of the Claude doc is that `CompoundRigidBody` was a **migration convenience** (leave `SphereRigidBody`/`PlaneRigidBody` and their switches untouched while the new path grows), not a performance choice — and as an end state it's strictly worse: two divergent body representations, double the code paths, downcasts. The Codex doc's flat model is the end state every surveyed engine uses (a body *has* shapes; shape count is not a type distinction — PhysX attaches N `PxShape`s to one actor, Jolt wraps N children in a compound shape on one body, Bullet sets one `btCompoundShape` on one `btRigidBody`).

What survives from the legacy classes: `SphereRigidBody` and `PlaneRigidBody` remain as thin **conveniences** — `SphereRigidBody.init` installs a one-sphere collider list (and its `collisionRadius` setter syncs it, since call sites assign post-init); `PlaneRigidBody` keeps `collisionNormal` and stays special-cased at body level in the narrow phase (an infinite static plane is world geometry, not a compound child — both docs agree planes are static-only). `CollisionShape` and the force-cast switches are deleted at the end of Phase A; the exhaustive-switch style means the compiler walks you through every stale call site.

### 3.6 Why `Int` instead of `UInt32`/`UInt64` for `worldColliders(frame:)` and `PhysicsWorld.currentStepIndex`?

Because in Swift, unsigned types are the wrong default even for values that can't be negative — per the language's own guidance (The Swift Programming Language, "The Basics"):

> "Use `UInt` only when you specifically need an unsigned integer type with the same size as the platform's native word size. If this isn't the case, `Int` is preferred, even when the values to be stored are known to be nonnegative. A consistent use of `Int` for integer values aids code interoperability, avoids the need to convert between different number types, and matches integer type inference."

Applied to this specific counter:

- **No implicit conversions exist in Swift.** Every place a `UInt32` step index met an `Int` (array indices, `count`s, loop variables, the `frame:` parameter of anything else) would need an explicit `Int(...)`/`UInt32(...)` wrapper. That's permanent call-site noise for zero benefit.
- **Unsigned arithmetic traps on underflow.** `frame - 1` — say, "compare against the previous step" — crashes at frame 0 with `UInt`. With `Int` it's just `-1`, which is also exactly the **sentinel** the cache uses: `worldCollidersFrame = -1` means "never computed", requiring no `Optional` and no magic max value. An unsigned version needs `UInt32?` (extra branch + width) or reserving `.max` (a value the counter can actually reach — see next point).
- **The unsigned "safety" is illusory here, and `UInt32` is the only variant that can realistically overflow.** `Int` is 64-bit on every Apple platform: at 120 substeps/s it overflows after ~2.4 × 10⁹ years. `UInt32` wraps after 2³² steps ≈ **414 days** of continuous simulation — far-fetched for a game session, but it's the one choice in the set with a reachable failure mode, and cache-token wraparound (`frame == worldCollidersFrame` matching a stale entry) is exactly the kind of bug nobody would ever find. `UInt64` avoids that but keeps all the conversion noise.
- **Signedness carries no meaning for this value.** It's an equality-compared cache token (never ordered, never arithmetic'd on the hot path); the type should optimize for ergonomics and uniformity, and the codebase (like the Swift standard library — `Array.count`, indices, etc.) is `Int` throughout.

So: `Int`, matching both the language guideline and the codebase's existing conventions. (If a fixed-width type were ever forced — e.g., writing the counter into a GPU buffer — `UInt32` with `&+` wraparound *and* a wraparound-safe comparison would be the deliberate exception, documented at the site.)

---

## 4. The combined implementation approach

### 4.0 Decisions at a glance

| Decision | Source | Driven by |
|---|---|---|
| Colliders live on `RigidBody`; no `CompoundRigidBody` subclass; `CollisionShape` deleted end of Phase A | Codex D1 | Q 3.5 |
| `LocalCollider` / `WorldCollider` split with per-step scratch cache | Claude | Q 3.4 |
| `currentStepIndex: Int`, `-1` sentinel for "never cached" | Claude (type choice affirmed) | Q 3.6 |
| Narrow phase emits **all** collider-pair contacts; linear response consumes deepest per body pair; events fire per contact | Hybrid D3 | — |
| Rest hack + impulse-discard hack replaced by restitution threshold + slop correction, all bodies, Phase A | New (audit) | Q 3.2 |
| Fixed 1/120 s substeps + accumulator, Phase B | Codex D4 | Q 3.3 |
| Physics step site unchanged (top of scene `doUpdate`); force computation moves into per-substep generators | New (middle path D5) | Q 3.3 |
| `Node.update()` ordering untouched | — | Q 3.3 |
| Gear = raycast suspension gated by `gearAnimationProgress`; compression/rebound damping split + `maxSupportForce` | Both + Codex details | — |
| Angular dynamics Phase D; `Contact.point` + `addForce(atWorldPoint:)` staged early | Claude sequencing, Codex prep (D2) | Q 3.1 |
| Authored per-aircraft mass/COM/inertia when Phase D lands; never recomputed from animated colliders | Both | Q 3.1 |
| Custom Swift core; authoring layer stays backend-agnostic (Jolt gate before Phase D) | D7 | — |
| Skeleton `jointModelPoses` deferred until animated colliders matter | Claude (D8) | — |

Phase labels continue the Claude doc's A–D (its per-step tables §2.8 still apply where unchanged); Codex-phase equivalences noted inline.

### 4.1 Phase 0 — debug overlay, units, parity harness (Codex Phase 0, lightweight)

- **Collider debug overlay first.** Translucent `Sphere`/`Capsule`/`Cube` child nodes at each `LocalCollider` pose (`setColor([1, 0, 0, 0.3])` — they auto-register as transparent renderables), struts as `Line`s, toggled by a debug key. Every spec number in §4.2/§4.3 is a placeholder until eyeballed against the model with this overlay. Remember `removeFromScene()` on toggle-off (registration rule).
- **Units contract, the lightweight version:** spec dimensions are model units; world meters = model units × the node's uniform scale (`scale.x`; assert uniformity in debug builds). Sanity anchor: the CGTrader F-22 fuselage capsule at scale 3.0 spans ≈ 17 m against the real jet's 18.9 m. Codex's full `assetToBodyMeters` transform is deferred until an asset with non-uniform normalization forces it.
- **Parity harness:** capture BallPhysicsScene / PhysicsStressTestScene trajectories (positions over N steps for a fixed seed) as a baseline before touching the response path, so A3's routing change and the rest-hack replacement diff against known behavior. Metal-free via `TestRigidBody` doubles per the established pattern.

### 4.2 Phase A — colliders on `RigidBody`, contact narrow phase, filtering, rest fix

#### A1. Shape vocabulary and collider types (new file `Physics/Collision/ColliderShape.swift`)

As in the Claude doc §2.3 (`ColliderShape` enum with `.sphere/.capsule/.box` + `scaled(by:)`; `ColliderGroup`; `LocalCollider`; `WorldCollider` with the `aabb` property) with two changes from §2/§3:

```swift
struct LocalCollider {
    var name: String
    var shape: ColliderShape
    var localPosition: float3
    var localRotation: simd_quatf
    var group: ColliderGroup
    var isEnabled: Bool
    /// Reserved: per-collider friction/restitution override (Phase D).
    /// Body-level restitution applies until then.
    var material: PhysicsMaterial? = nil
}
```

`ColliderGroup` stays generic (`.airframe`, `.landingGear`, `.structure` — extend as needed), never aircraft-part-specific; per-part identity is the free-form `name`.

#### A2. `RigidBody` gains the collider list (diff, `Physics/World/RigidBody.swift`)

```diff
 public class RigidBody: PhysicsEntity {
     ...
     var isStatic: Bool
     var shouldApplyGravity: Bool
+
+    /// Compound collision geometry: primitive colliders at body-local offsets.
+    /// Every surveyed engine models complex dynamic objects this way (one
+    /// body, many shapes). Empty ⇒ no volume (PlaneRigidBody overrides the
+    /// narrow-phase path instead).
+    var colliders: [LocalCollider] = [] {
+        didSet { worldCollidersFrame = -1 }
+    }
+
+    /// Collision filtering (§1.5 of both research docs). A pair is tested only
+    /// if each body's category intersects the other's mask.
+    var categoryMask: UInt32 = CollisionCategory.default
+    var collidesWithMask: UInt32 = CollisionCategory.all
+
+    /// Fired once per contact this body participates in, on the UpdateThread,
+    /// during collision resolution. Contact is expressed with self as A.
+    var onContact: ((Contact, RigidBody) -> Void)?
+
+    /// Per-step world-space collider snapshot (see research doc §3.4:
+    /// LocalCollider = authored spec, WorldCollider = derived per-step cache).
+    private var worldScratch: [WorldCollider] = []
+    private var worldCollidersFrame: Int = -1   // -1 ⇒ never computed
+
+    func worldColliders(frame: Int) -> [WorldCollider] {
+        if frame == worldCollidersFrame { return worldScratch }
+        worldCollidersFrame = frame
+        worldScratch.removeAll(keepingCapacity: true)
+        guard let node = gameObject else { return worldScratch }
+        let bodyPosition = node.getPosition()
+        let bodyRotation = node.getRotationMatrix().upperLeft3x3
+        let scale = node.getScale().x   // uniform scale contract (§4.1)
+        for (index, collider) in colliders.enumerated() where collider.isEnabled {
+            worldScratch.append(WorldCollider(
+                shape: collider.shape.scaled(by: scale),
+                position: bodyPosition + bodyRotation * (collider.localPosition * scale),
+                rotation: bodyRotation * float3x3(collider.localRotation),
+                sourceIndex: index,
+                name: collider.name,
+                group: collider.group))
+        }
+        return worldScratch
+    }
+
+    /// Compound AABB: union of enabled child AABBs (broad-phase input).
+    func getAABB() -> AABB {   // replaces the per-subclass overrides for volumes
+        let worlds = worldColliders(frame: PhysicsWorld.currentStepIndex)
+        guard var merged = worlds.first?.aabb else {
+            return AABB(center: getPosition(), radius: 0.5)
+        }
+        for collider in worlds.dropFirst() { merged = merged.merged(with: collider.aabb) }
+        return merged
+    }
```

Legacy classes become conveniences (`BasicRigidBodies.swift`):

```diff
 public final class SphereRigidBody: RigidBody {
-    var collisionRadius: Float = 1.0
+    var collisionRadius: Float = 1.0 {
+        didSet {   // call sites assign post-init (FlightboxWithPhysics did)
+            colliders = [LocalCollider(name: "sphere",
+                                       shape: .sphere(radius: collisionRadius))]
+        }
+    }

     init(gameObject: GameObject, collisionRadius: Float = 1.0) {
         super.init(gameObject: gameObject)
-        self.collisionRadius = collisionRadius
-        self.collisionShape = .Sphere
+        defer { self.collisionRadius = collisionRadius }   // triggers didSet
     }
-
-    override func getAABB() -> AABB { ... }               // base compound AABB serves
 }
```

`PlaneRigidBody` is unchanged (keeps `collisionNormal` and its huge-slab `getAABB()`); the narrow phase special-cases planes at body level. **End of Phase A:** `CollisionShape`, `PhysicsWorld.collided`, `getCollisionData`, and the `y = 0` plane hack (`getPenetrationDepth(ball:plane:)`) are deleted; the compiler's exhaustive-switch errors enumerate every stale call site.

#### A3. Narrow phase — all contacts, pure functions (new files `Contact.swift`, `NarrowPhase.swift`)

The Claude doc's `NarrowPhase` (§2.3: plane-side normalization, sphere/capsule/box vs. plane, the pair-dispatch `shapeVsShape`, Ericson closest-point helpers) is adopted wholesale **except** the deepest-only reduction, per D3:

```swift
enum NarrowPhase {
    /// Appends EVERY contacting collider pair between the two bodies into
    /// `contacts` (events and classification need all of them — wingtip and
    /// belly can scrape simultaneously). Returns the index of the deepest
    /// appended contact, which the linear-only response consumes; the Phase D
    /// solver will consume them all and this return value disappears.
    @discardableResult
    static func generateContacts(_ a: RigidBody, _ b: RigidBody,
                                 frame: Int,
                                 into contacts: inout [Contact]) -> Int?
}
```

`Contact` is the Claude doc's struct unchanged (normal from B toward A matching the existing response convention, depth, world point, collider names/groups both sides, `flipped`). The `point` field is populated from day one even though the linear response ignores it (D2 prep).

#### A4. Filtering (diff, `BroadPhaseCollisionDetector.swift`)

As in the Claude doc §2.3: `shouldCollide(_:_:)` (symmetric category/mask test + never pair two bodies of the same GameObject) applied at pair emission in both the dynamic-dynamic and dynamic-static loops, plus the `CollisionCategory` bitmask vocabulary (`default`/`world`/`vehicle`/`structure`/`debris`).

#### A5. Response routing + the rest-hack replacement (diff, `HeckerCollisionResponse.swift`)

One narrow phase per pair (the old flow ran geometry twice — `collided` then `getCollisionData`), then the corrected response:

```diff
 final class HeckerCollisionResponse {
-    /// Below this relative speed a contact is treated as resting (squared — no sqrt).
-    private static let restSpeedThresholdSquared: Float = 0.55 * 0.55
-    /// Impulse delta-v below this squared magnitude is discarded (1.0² == 1.0).
-    private static let minDeltaVeloSquared: Float = 1.0
+    /// Below this normal approach speed, restitution is 0: the impulse solves
+    /// the normal velocity to exactly zero instead of bouncing. Resting becomes
+    /// an equilibrium re-established every step — gravity stays ON.
+    /// (Box2D b2_velocityThreshold and Jolt's restitution threshold ≈ 1 m/s.)
+    private static let restitutionVelocityThreshold: Float = 1.0
+    /// Penetration allowed before position correction engages (meters).
+    private static let penetrationSlop: Float = 0.005
+    /// Fraction of (depth − slop) corrected per step (Baumgarte-style).
+    private static let positionCorrectionBeta: Float = 0.2

     static func resolveCollisions(deltaTime: Float, collisionPairs: [(RigidBody, RigidBody)]) {
+        contactsScratch.removeAll(keepingCapacity: true)
         for (entityA, entityB) in collisionPairs {
             let alreadyCollided = entityA.collidedWith.contains(ObjectIdentifier(entityB))
-            if !alreadyCollided && PhysicsWorld.collided(entityA: entityA, entityB: entityB) {
-                entityA.collidedWith.insert(ObjectIdentifier(entityB))
-                entityB.collidedWith.insert(ObjectIdentifier(entityA))
-                applyCollisionResponse(entityA, entityB)
-            }
+            guard !alreadyCollided else { continue }
+            let firstNew = contactsScratch.count
+            guard let deepestIndex = NarrowPhase.generateContacts(
+                entityA, entityB,
+                frame: PhysicsWorld.currentStepIndex,
+                into: &contactsScratch) else { continue }
+
+            entityA.collidedWith.insert(ObjectIdentifier(entityB))
+            entityB.collidedWith.insert(ObjectIdentifier(entityA))
+
+            // Linear-only response: one impulse along the deepest contact
+            // resolves the (co-normal) set. Phase D iterates them all.
+            applyCollisionResponse(entityA, entityB, contact: contactsScratch[deepestIndex])
+
+            // Events fire for EVERY contact — classification needs them all.
+            for contact in contactsScratch[firstNew...] {
+                entityA.onContact?(contact, entityB)
+                entityB.onContact?(contact.flipped, entityA)
+            }
         }
     }

-    private static func applyCollisionResponse(_ entityA: RigidBody, _ entityB: RigidBody) {
-        // Hack: ... rest branch: zero velocity, shouldApplyGravity = false ...
-        if simd_length_squared(entityA.velocity - entityB.velocity) < restSpeedThresholdSquared { ... return }
-        let collisionData = PhysicsWorld.getCollisionData(entityA, entityB)
+    private static func applyCollisionResponse(_ entityA: RigidBody, _ entityB: RigidBody,
+                                               contact: Contact) {
+        let n = contact.normal                       // unit, B → A
+        let relativeVelo = entityA.velocity - entityB.velocity
+        let approach = dot(relativeVelo, n)          // < 0 ⇒ approaching
+
+        // Position correction with slop — replaces full-depth teleports (and
+        // the old ×2 overshoot in the static branches).
+        let correction = positionCorrectionBeta * max(0, contact.depth - penetrationSlop)
+        // split by inverse mass for dynamic/dynamic; full for dynamic/static
+        ...
+
+        guard approach < 0 else { return }           // separating: no impulse
+
+        // Restitution only above the threshold; below it e = 0 ⇒ v_n → 0.
+        let e = -approach > restitutionVelocityThreshold
+            ? min(entityA.restitution, entityB.restitution)
+            : 0
+
+        var j = -(1 + e) * approach
+        j /= inverseMassSum                          // per static/dynamic branch, as today
+        // Impulses are ALWAYS applied — the old minDeltaVelo discard threw
+        // away the per-step support impulse (≈ m·g·dt) that resting requires.
+        entityA.velocity += (j / entityA.mass) * n   // dynamic branches as today
+        ...
     }
 }
```

`EulerSolver.resolvePair` gets the identical contact-in treatment. The step counter lands in `PhysicsWorld`:

```diff
 final class PhysicsWorld {
     public static let gravity: float3 = [0, -9.81, 0]
+    /// Monotonic step counter — cache token for per-step world-collider
+    /// snapshots. Int per Swift guidance (research doc §3.6); -1 is the
+    /// "never cached" sentinel on the body side.
+    public private(set) static var currentStepIndex: Int = 0
```

**Exit criteria (A):** parity harness matches for BallPhysicsScene pre/post routing (modulo the intentional rest-behavior change: balls now settle with gravity on and never latch); a tilted/translated ground plane works (y = 0 hack gone); an F-22 compound spec (fuselage capsule + wing box + empennage box, Claude doc §2.3 numbers) reports wingtip vs. belly vs. tail contacts by name through `onContact`.

### 4.3 Phase B — fixed timestep, force generators, landing gear

#### B1. Fixed-step accumulator + force generators (diff, `PhysicsWorld.swift`)

Resolves D4 and D5 (design argued in §3.3):

```swift
protocol PhysicsForceGenerator: AnyObject {
    /// Called once per fixed substep, before collision/integration, on the
    /// UpdateThread. Read live body state; accumulate into body.force
    /// (and body torque, Phase D). Never mutate transforms here.
    func accumulateForces(substepDelta: Float)
}

final class PhysicsWorld {
    private let fixedDelta: Float = 1.0 / 120.0
    private let maxSubstepsPerFrame = 8
    private var accumulator: Float = 0
    private var forceGenerators: [PhysicsForceGenerator] = []   // scene-managed

    public func update(frameDelta: Float) {
        // Clamp: a breakpoint/hitch never triggers a spiral of death.
        // (Replaces FlightboxWithPhysics's `GameTime.DeltaTime < 1.0` guard.)
        accumulator = min(accumulator + frameDelta, Float(maxSubstepsPerFrame) * fixedDelta)
        while accumulator >= fixedDelta {
            Self.currentStepIndex += 1
            for generator in forceGenerators { generator.accumulateForces(substepDelta: fixedDelta) }
            step(deltaTime: fixedDelta)   // existing: reset → broad phase → contacts/response → integrate → zeroForces
            accumulator -= fixedDelta
        }
    }
}
```

Forces are zeroed at the end of each substep (existing `zeroForces`) and re-accumulated by generators at the top of the next — the lifecycle Codex specified ("clear force/torque after each fixed step, not once after an arbitrary display frame"). `Aircraft` conforms: the flight-model force computation **moves out of `doUpdate`** into `accumulateForces` (reading a `controlInput` property that `doUpdate` refreshes from `InputManager` each frame); `doUpdate` keeps input sampling, attitude filtering, and `animator?.update`. Scene wiring registers/unregisters generators alongside rigid bodies in `buildScene`/`applyAircraftSwap` (extend `swappedEntities`' contract to cover both).

Add `addForce(_:atWorldPoint:)` now (D2 prep):

```swift
extension RigidBody {
    /// Accumulates force; the torque component is stored but ignored by the
    /// integrator until Phase D (angular dynamics). Call sites written against
    /// this API today become torque-correct for free later.
    func addForce(_ force: float3, atWorldPoint point: float3) {
        self.force += force
        // Phase D: torque += cross(point - worldCenterOfMass, force)
    }
}
```

#### B2. Suspension (new file `Physics/Vehicle/LandingGearSuspension.swift`)

The Claude doc's `SuspensionStrut`/`LandingGearSuspension` (§2.4 — struts in model units, ray vs. ground plane along body −Y, `gearExtension > 0.99` gate, weight-on-wheels from compressions) with the Codex refinements from D-minor:

```swift
struct SuspensionStrut {
    var name: String
    var attachLocal: float3
    var restLength: Float
    var maxTravel: Float
    var wheelRadius: Float
    var springRate: Float           // N/m — k = W_strut / x_static
    var compressionDamping: Float   // N·s/m — c = 2ζ√(k·m_strut), ζ ≈ 0.5–0.7
    var reboundDamping: Float       // typically ≥ compressionDamping for oleos
    var maxSupportForce: Float      // clamp + gear-overload event threshold
}
```

Per-strut compression velocity by finite difference (`(new − old) / substepDelta`, stateful — stays correct when attitude dynamics tilt the strut later); damping selected by the sign of the compression rate; force clamped to `[0, maxSupportForce]` (a strut pushes, never pulls) and applied via `addForce(_:atWorldPoint: contactPoint)` — a no-op difference today, the pitch/roll moments in Phase D. Driven from `Aircraft.accumulateForces` every substep — **outside** any focus/input guard (a parked aircraft must be held up; Claude doc already flagged this).

Spring sizing carries over verbatim from the Claude doc §2.4 (F-22 at 30 t: mains `k ≈ 1.1 MN/m`, `c ≈ 146 kN·s/m`; nose `k ≈ 268 kN/m`, `c ≈ 34 kN·s/m`; static check sums to ≈ W). With 1/120 s substeps these are comfortably stable (spring-damper time constants ≫ dt); the old caveat about 60 Hz variable frames is retired by B1.

#### B3. Crash-vs-landing classification

Merged from both docs: the Claude doc's `handleContact` (any `.airframe` contact + impact speed threshold + `isGearDown`) plus Codex's outcome vocabulary — `supportedByGear(strut, load)` (from compressions, no contact event involved), `scrape` vs. `overload` by impulse threshold, `gearOverload` fired when a strut hits `maxSupportForce` or bottoms out (`compression == maxTravel`). Touchdown scoring reads sink rate + per-strut compression at the frame `isWeightOnWheels` flips true.

**Exit criteria (B):** aircraft settles at correct ride height on its three struts with gravity on (no rest latch); physics trajectories match across 30/60/120 Hz refresh settings; gear-up pass over the runway → belly `fuselage` crash event; hard landing → `gearOverload`.

### 4.4 Phase C — static structures

As in the Claude doc §2.5: static `RigidBody` + box/capsule collider lists for towers/hangars/trees (`isStatic = true`, `shouldApplyGravity = false`, `.structure` category), colliding through the already-built sphere/capsule/box-vs-* paths. The dynamic-vs-static broad-phase loop already exists; the capsule-vs-box approximation upgrades to exact segment-OBB (or SAT/GJK) only if wing-clips-corner fidelity demands it.

### 4.5 Phase D — angular dynamics → sequential impulses → joints (Codex Phases 2 + 5)

Deferred, unblocked by everything above, in dependency order:

1. **Angular state on `RigidBody`** (quaternion pose becomes authoritative for dynamic bodies, published to the `Node` once per frame after substeps — Codex §2.3's `setPhysicsPose`, one subtree-dirty per frame), `angularVelocity`, `torque`, `inverseInertiaLocal`, world-space conjugation `R·I⁻¹·Rᵀ`, semi-implicit integration with normalized quaternion update. The gyroscopic term stays optional until tested.
2. **Authored mass properties per aircraft** (mass/COM/inertia in the collider spec — see §3.1; the `composeMassProperties` parallel-axis sample in the Claude doc §2.6 serves debris/crates, not aircraft).
3. **Contact impulses with lever arms** (Hecker's full formula — the denominator from §3.1; `Contact.point` finally consumed) and the response iterating **all** contacts from A3's scratch list instead of the deepest.
4. **Sequential impulses** with accumulated-impulse clamping and warm starting (Catto GDC 2005/2009), friction cones (`|j_t| ≤ μ·j_n`), Baumgarte or split position correction — `collidedWith` retires here.
5. **Joints last, and only if gameplay demands them** (both docs, emphatically): fixed/hinge/prismatic with limits and PD drives (`stiffness·(target−pos) + damping·(targetVel−vel)`), prototyped on one gear leg before converting anything. The gear itself never requires them — raycast suspension is what shipping titles use even with a full joint solver available. CCD (swept casts for missiles/fast debris) slots in here too.

### 4.6 The Jolt gate (before starting Phase D)

Phase D is where scope risk lives ("robust convex contacts, persistent manifolds, friction, stacking, CCD, sleeping, joints... form a mature physics engine" — Codex §2.14). Before starting it, hold an explicit go/no-go: if by then the goal is *shipping more vehicle/structure gameplay*, run Codex's Jolt spike (one compound body + three suspension queries behind the narrow `PhysicsBackend` protocol sketched in Codex §2.14) and compare; if the goal remains *owning the solver*, build Phase D natively and stop at the fidelity actually needed. Everything in Phases 0–C (specs, gear model, events, classification, debug overlay, tests) survives either choice unchanged — that's what keeping the authoring layer backend-agnostic buys.

### 4.7 Testing (merged matrix)

All Metal-free (pure narrow-phase/suspension functions; `TestRigidBody` doubles; plain `Node`s), Swift Testing under `.physics`:

- **Geometry** (Claude §2.7 + Codex §2.13): shape-vs-plane depths/normals/points for translated *and tilted* planes; rotated box/capsule AABBs; compound AABB union incl. disabled-child omission and empty-body fallback; every `shapeVsShape` nil (separated) case; collider names/groups surfacing in contacts; filtering masks; same-GameObject exclusion.
- **Rest fix**: resting body retains `shouldApplyGravity == true` forever; settles to ≤ slop penetration with bounded jitter; approach-guard (no impulse when separating); no bounce below the restitution threshold, bounce above it; pushed resting body falls normally afterward (the latch regression test).
- **Determinism** (Codex): fixed-step trajectories invariant to frame-delta partitioning (one 1/30 s frame ≡ four 1/120 s frames).
- **Suspension**: static-load balance at expected compression; strut-never-pulls clamp; compression vs. rebound damping selection; `maxSupportForce` clamp fires the overload signal; gear-up ⇒ zero forces and zero compressions; weight-on-wheels transitions.
- **Scenarios** (integration-level, from Codex §2.13 as they become expressible): level three-point settle, one-wheel-first roll moment (Phase D), belly landing classification, aircraft swap / scene reset leaving no bodies, colliders, or force generators registered.

---

## 5. References

### Newly visited for this combined doc (2026-07-18)

- https://docs.swift.org/swift-book/documentation/the-swift-programming-language/thebasics/ — The Swift Programming Language, "The Basics" (page is JS-rendered; content confirmed via the book's source, next entry)
- https://raw.githubusercontent.com/swiftlang/swift-book/main/TSPL.docc/LanguageGuide/TheBasics.md — verbatim `UInt`-vs-`Int` guidance quoted in §3.6

### Carried over — load-bearing sources (full lists in the two source docs)

Via the **Claude doc** (adversarially verified there): Unity compound-collider and collider-cost manuals; Unity `Rigidbody` / WheelCollider references (spring/damper defaults, `GetWorldPose` pattern); PhysX geometry limits (255-vertex hulls; no dynamic trimeshes without SDF); Bullet 2.80 manual (`btCompoundShape`, `btRaycastVehicle` "widely used in commercial driving games"); Jolt `Architecture.md` (shape cost order, Static/MutableCompoundShape, 13-constraint catalog, motor formula, filtering pipeline); Catto, *Modeling and Solving Constraints* (GDC 2009) and *Iterative Dynamics* (GDC 2005); Ericson, *Real-Time Collision Detection* (closest-point primitives); Hecker, *Physics Part 3* (the response formula, cited in the existing code).

Via the **Codex doc**: PhysX Rigid Body Dynamics / Joints / Articulations; Unreal Physics Bodies & Physics Asset Editor; JSBSim `FGLGear` / `FGGroundReactions` (aircraft-specific gear force + moment model); Unity CCD; Box2D overview/collision/simulation (solver organization; sleeping); Jolt repository (platform support); Swift/C++ interop (the Jolt adapter path); Apple CPU/GPU synchronization (debug-draw ring discipline).

### Project documents

- `research/claude/compound_rigid_bodies_research_2026-07-14.md` — full verified-claims research (Part 1), Phase A–D code (Part 2)
- `research/codex/compound_rigid_bodies_and_articulated_landing_gear_research_2026-07-14.md` — engine survey, 6-DOF/solver design, gear hybrid model, Jolt evaluation
- `plans/claude/damped_attitude_response.md` — the kinematic attitude model that Phase D's torque-driven rotation eventually replaces
