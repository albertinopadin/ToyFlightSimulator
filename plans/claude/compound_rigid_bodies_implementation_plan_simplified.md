# Compound Rigid Bodies — Implementation Plan (simplified)

**Started:** 2026-07-19 · **Rewritten:** 2026-09-02 (simplified; this is now the living plan)
**Design source:** `research/claude/compound_rigid_bodies_research_combined.md` (§4 is the phase outline; §2–§3 hold the design decisions).
**Original plan:** `plans/claude/compound_rigid_bodies_implementation_plan_original.md` holds the full changelog, every landed listing, and the reasoning behind each Phase 0 / Phase A decision. This document restates what still matters in plain English, adds a Phase A cleanup list, and re-plans Phase B.

## How this document works

- Steps are edited in place to match the code. History goes in the Changelog, one line per entry.
- Checkboxes (`- [ ]`) are ticked as steps land.
- Code listings are the contract for hand transcription. The comments in them are the comments to ship, and they are short on purpose.

## Changelog

- **2026-09-03** — B-timestep landed (B.3): fixed 1/120 s substeps behind a per-world accumulator (at most 8 per update); the four scenes drop their hitch guards. All six goldens regenerated and reviewed ("Observed" under B.3). `FixedTimestepTests` added; `ForceGeneratorTests` expectations flipped to substep values. Two review-table expectations were wrong: Verlet free fall is not step-independent (the solver bootstraps from a = 0 and runs h/2 late), and `head_on_pair`'s exact-tangency contact moved one substep later by float rounding. `PhysicsWorldSmokeTests.onContactFiresOnAttachedPath` needed one edit (it counted one contact per update; it now steps one `fixedDelta`).
- **2026-09-03** — B-generators landed (B.1–B.2): `RigidBody.forceGenerator`, called by `PhysicsWorld` at the top of every step; `Aircraft.generateForces` computes the flight force inside the step from the input cached in `doUpdate`. `ForceGeneratorTests` added (plus a third test pinning that force does not persist between steps). Goldens byte-identical under the dry run.
- **2026-09-03** — Phase A cleanup closed by owner. Still open for a later plumbing commit: the four deprecated `PhysicsWorld` update methods (C3, third item) and O1.
- **2026-09-02** — Phase A cleanup landed (C1–C10) as one plumbing commit. Deviations: the four private `PhysicsWorld` update methods are kept as deprecated, unused code by owner decision (C3, third item); the two `*Original` bodies were rerouted through `appendAllPairs` so the O(n²) solver overloads C1/C2 delete could go. O1 not taken.
- **2026-09-02** — Simplified rewrite. Phase 0 and Phase A summarized (both done). New "Phase A cleanup" section listing the code changes to make. Phase B re-planned with the design changes listed under "What changed from the original plan".
- **2026-08-31** — Phase B planned (original doc). Phase A closed: all seven exit criteria met, CI green.
- **2026-08-30 / 31** — Phase A landed as three commits (A-routing, A-response, A-aircraft) plus a test-backfill commit.
- **2026-08-29** — Phase 0 closed (overlay and spec numbers verified in-app, CI green).
- **2026-08-27 / 28** — Phase 0 landed after the Codex review revision.

## What changed from the original plan

Language: figurative wording ("load-bearing", "pins", "island", "honest", "eyeball", "funnel", "zombie", "dies") is replaced by plain terms, emphasis capitals are gone, and each phase states its gates once.

Code, already landed (Phase A), to change under the cleanup section below:
1. `resolvePair` exists once, in `HeckerCollisionResponse`; `EulerSolver` calls it.
2. `PhysicsWorld.update` has one code path; the broad-phase-off mode builds an all-pairs list.
3. `HeckerCollisionResponse.resolveCollisions` loses its unused `deltaTime`.
4. `RigidBody` has one designated init and one optional `standalonePosition`.
5. `RigidBody.pose()` is the single source of a body's position, rotation, and scale.
6. `Contact` has one initializer.
7. Reserved-but-unread API is removed (`PhysicsMaterial`, `LocalCollider.material`, `PhysicsEntity.isDynamic`).
8. Long narrative doc comments are shortened.

Code, planned (Phase B), different from the original Phase B plan:
1. Force generation is a closure on `RigidBody` (`forceGenerator`), not a registry of protocol objects. No add/remove bookkeeping on aircraft swaps.
2. No `addForce(_:atWorldPoint:)`; the suspension adds to `force` directly.
3. The suspension reads the body pose through `RigidBody.pose()`; four parameters fewer.
4. The overlay takes an `AircraftType` and looks up collider and strut specs itself.
5. Pre-impact velocity is `RigidBody.stepStartVelocity`, written by the world; no cache on `Aircraft`.
6. The accumulator counts substeps by division and subtracts once; exact at every selectable refresh rate.
7. `raycastStaticPlanes` returns the nearest distance only.
8. `ContactDebugLogger` is deleted when `TouchdownReporter` replaces it.

## Verification commands

The macOS scheme's Build action builds the app only, so a plain `build` does not produce the test bundle.

```bash
# Build tests + app
xcodebuild build-for-testing -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Scoped suite run (serial per project rule)
xcodebuild test-without-building -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug -parallel-testing-enabled NO \
  -only-testing:"ToyFlightSimulatorTests/<SuiteName>" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Full suite in one step
xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

`-parallel-testing-enabled NO` serializes test bundles, not Swift Testing's in-process concurrency: parameterized `@Test` cases still run concurrently inside one process.

## Rules that apply to every phase

1. **No process-wide mutable state in the step path.** Tests run several `PhysicsWorld`s at once in one process. Scratch arrays, accumulators, and event state are per instance.
2. **Two kinds of commit.** A plumbing commit changes no behavior: the six parity goldens must come back byte-identical from a regeneration dry run. A behavior commit regenerates the goldens, reviews the JSON diff, and adds tests that state the new behavior. A commit is one or the other, never both.
3. **Metal-free tests.** Any `GameObject` construction needs Metal. Logic tests use detached bodies (`init(detachedAt:)`) and pure helpers; only `PhysicsWorldSmokeTests` and the XCTest suites are app-hosted.
4. **World-collider cache.** A body's world colliders are rebuilt on demand behind a dirty flag. `setPosition` and collider changes set the flag; the world sets it for every body at the start of each step, because node rotation does not go through `setPosition`.
5. **Local transforms.** Attached bodies read their node's local position and rotation. That is valid only for scene-root children, and `RigidBody.pose()` asserts it.
6. **Debug objects in the scene graph.** Call `SceneManager.Register` after `addChild`; call `setColor` with alpha < 1 before registering; remove with `removeFromScene()`, never a bare `removeChild`.

## Golden regeneration

```bash
TEST_RUNNER_TFS_REGEN_PHYSICS_BASELINES=1 xcodebuild test-without-building \
  -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug -parallel-testing-enabled NO \
  -only-testing:"ToyFlightSimulatorTests/PhysicsParityTests" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

The regeneration run fails on purpose (it records an issue per rewritten golden). Sequence for a behavior commit: regenerate, review the JSON diff like code, commit the JSON, re-run without the variable, green.

Dry run for a plumbing commit: regenerate, then `git diff --exit-code ToyFlightSimulatorTests/Physics/Baselines` must print nothing. Any diff is a bug in the change, never a golden to update.

---

# Phase 0 — overlay, units contract, parity harness ✅ (closed 2026-08-29)

Implements combined doc §4.1. Behavior-neutral for the running game except one deliberate change: `Node.parent` and the other back-references became `weak`, so detached subtrees now deallocate (`NodeOwnershipTests`).

## What landed

| Where | What |
|---|---|
| `Physics/Collision/ColliderShape.swift` | `ColliderShape` (sphere / capsule / box, meters), `ColliderGroup`, `LocalCollider` (Phase A appended `WorldCollider` and `WorldColliderBuilder`) |
| `Physics/Collision/AircraftColliderSpec.swift` | One spec per `AircraftType`; only `.f22_cgtrader` is authored (fuselage capsule, wings box, empennage box). Exhaustive switch, no `default`. |
| `Physics/Debug/ColliderDebugOverlay.swift` | `ColliderOverlayMapping` (pure shape-to-mesh math, unit-tested) and `ColliderDebugOverlay` (X key; scene-graph work, not unit-tested) |
| `Managers/SceneManager.swift` | `SetRenderableHidden(_:_:)` hides one node's own renderable registration; re-hides extracted submeshes on un-hide |
| `Managers/InputManager.swift` | `DiscreteCommand.CycleColliderOverlay` on the X key (keyboard only) |
| `Scenes/GameScene.swift` | Owns the overlay; `playerAircraftType`; X handler in `doUpdate`; `colliderOverlay.reset()` in `teardownScene` |
| `Scenes/FlightboxWithPhysics.swift` | `colliderOverlay.hostWasReplaced(...)` at the end of `applyAircraftSwap` |
| `Node` / `GameObject` / `Mesh` | `setRotation(_ q:)`, `uniformScale` (asserts uniform scale), `GameObject.init(name:model:)`; `Node.parent`, `SubMeshGameObject.parentMeshGameObject`, `Mesh.parentModel` are weak |
| `Physics/World/RigidBody.swift`, `BasicRigidBodies.swift` | `init(detachedAt:)` detached bodies: the real classes with no GameObject, for Metal-free tests |
| `ToyFlightSimulatorTests/TestSupport/SeededRandom.swift` | `SplitMix64` with its own Float derivation, so goldens do not depend on stdlib RNG internals |
| `ToyFlightSimulatorTests/Physics/PhysicsParityTests.swift`, `Baselines/*.json` | The parity harness and six goldens |

## Units contract

- Collider dimensions and offsets are post-import engine-local units, which meterization makes meters (`ModelLibrary` registers the CGTrader F-22 at 18.92 m).
- Aircraft run at scale 1.0. World meters = spec meters × `uniformScale` = spec meters. `uniformScale` stays in the world-collider math only as an optional gameplay multiplier; the debug assert in `Node.uniformScale` rejects non-uniform scale.
- Sanity check: the fuselage capsule prints 18.90 m at scale 1.0 in the overlay log (real jet 18.92 m). `AircraftColliderSpecTests` asserts the arithmetic.
- Mesh facts measured with ModelIO and asserted by `MeshBoundsTests`: `MDLMesh(capsuleWithExtent: [x, y, z])` takes x/z as the radius and y as the total cap-to-cap length; box extent is the full extent; `sphereWithExtent` is radius semantics, so `SphereMesh(radius:)` builds twice the size. The overlay uses the OBJ `.Sphere` model (radius 1.0), never `SphereMesh`.

## Overlay

X cycles off → volumes over hull (translucent red, shows colliders that stick out) → volumes only (hull hidden, shows colliders that are too small) → off. Spec-less aircraft show only the yellow legacy sphere. Since Phase A the yellow sphere is drawn only for aircraft that still use a `SphereRigidBody`; for the F-22 the red volumes are the live colliders.

Rules the overlay follows (rule 6 above, plus):
- Volumes are children of the aircraft, so the overlay registers them itself after `addChild`.
- Aircraft swap: `SceneManager.RemoveObject` already detached and unregistered the old subtree, volumes included. The overlay drops its references and re-applies its mode to the new aircraft; calling `removeFromScene()` on the stale references would be redundant.
- Scene teardown: `reset()` only; the whole subtree is being dropped.
- Hull hidden means "the aircraft's own renderable registration is absent", so swaps and teardown need no special handling.

## Parity harness

All scenarios use detached bodies, `dt = 1/60`, the RigidBody default mass 1. The two random scenarios use fixed seeds (`0xF22_0005` cluster, `0xF22_0006` grid), and the RNG draw order is part of the golden contract. Pair order is also part of the contract: the response is applied in pair order.

| Scenario | Setup | Solver / broad phase | Golden steps | Total steps |
|---|---|---|---|---|
| `single_bounce_verlet` | sphere r 0.5, e 0.9, dropped from y 5 onto a plane | HeckerVerlet / off | 300 | 300 |
| `single_bounce_euler` | same | NaiveEuler / off | 300 | 300 |
| `rest_latch` | sphere r 0.5, e 0.2, dropped from y 3 | HeckerVerlet / off | 600 | 600 |
| `head_on_pair` | two spheres r 0.5, e 1, closing at ±5 m/s on X, no plane, gravity on | HeckerVerlet / off | 120 | 120 |
| `ball_cluster_16` | 16 spheres r 0.4, e 0.9, seeded positions, plane e 1 | HeckerVerlet / on | 180 | 600 |
| `stress_grid_50` | 50 spheres r 0.3, e 0.8, grid + seeded jitter and velocities, plane e 0.9 | HeckerVerlet / on | 120 | 600 |

Invariants checked on every step of every scenario, and the only check on the steps past the golden window: all positions and velocities finite; no tunneling (y above plane − radius − 1 m); speed under a per-scenario budget (about twice the highest reachable speed). Multi-body contact order amplifies float noise, so the two chaotic goldens are short and the invariants carry the rest of the run.

Golden comparison tolerance is 1e-4 (toolchain variance between local and CI); metadata (solver, steps, dt, sampling) must match exactly. Only the first divergent (body, step) is reported.

## Exit criteria (all closed 2026-08-29)

1. - [x] Overlay works in-app, including swap, Cmd+R, and renderer switch while visible.
2. - [x] Spec numbers checked visually in both modes and accepted unchanged.
3. - [x] Fuselage capsule reads 18.9 m at scale 1.0; `MeshBoundsTests` and `ColliderOverlayMappingTests` green.
4. - [x] Six goldens committed; parity suite green on a clean re-run.
5. - [x] CI green on main at `0ec9a3e`; game plays the same with the overlay off.

---

# Phase A — colliders on `RigidBody`, one narrow phase, corrected response ✅ (closed 2026-08-31)

Implements combined doc §4.2. Landed as three commits: A-routing (plumbing, goldens byte-identical), A-response (behavior, goldens regenerated and reviewed), A-aircraft (the F-22 gets its compound body). The full reasoning, including the bit-exactness argument for A-routing and the regeneration review notes, is in the original plan.

## What landed

| Where | What |
|---|---|
| `Physics/Collision/Contact.swift` | `Contact`: unit normal from B toward A, depth, point, optional collider name/group for each side, `flipped` |
| `Physics/Collision/NarrowPhase.swift` | `generateContacts(_:_:into:)` (planes handled at body level, returns the deepest contact's index), `shapeVsPlane`, `shapeVsShape`, sphere/capsule/box primitives, `closestPointOnSegment(s)` |
| `Physics/Collision/ColliderShape.swift` | `WorldCollider` with `aabb`; `WorldColliderBuilder.build` (pure local-to-world transform) |
| `Physics/World/RigidBody.swift` | `colliders`, `categoryMask` / `collidesWithMask`, `onContact`, the world-collider cache, `shouldCollide(with:)`, compound `getAABB()`, `CollisionCategory` |
| `Physics/World/BasicRigidBodies.swift` | `SphereRigidBody` builds a one-sphere `WorldCollider` view; `collisionRadius.didSet` invalidates |
| `Physics/BroadPhase/BroadPhaseCollisionDetector.swift` | `shouldCollide` filter at pair emission |
| `Physics/World/PhysicsWorld.swift` | Per-instance contact scratch; every body invalidated at the start of each step |
| `Physics/CollisionResponse/HeckerCollisionResponse.swift` | `resolvePair` (one narrow phase per pair, events after the response) and the corrected `applyCollisionResponse` |
| `Physics/Solver/EulerSolver.swift` | Routed through the shared response; the legacy per-axis response is kept as unreferenced reference code |
| `Physics/World/PhysicsEntity.swift` | `CollisionShape` deleted; `shouldApplyGravity` is authoring state, never written by the solver |
| `Physics/Debug/ContactDebugLogger.swift` | Throttled named-contact printing on the player aircraft |
| `Scenes/FlightboxWithPhysics.swift` | Spec-driven body: a plain `RigidBody` with the spec for the F-22, the legacy 2 m `SphereRigidBody` for aircraft without a spec |
| Tests | `WorldColliderBuilderTests`, `NarrowPhaseTests`, `CollisionResponseTests`, `CompoundBodyTests`, `RigidBodyTests` additions, `PhysicsSolverTests` and `PhysicsWorldSmokeTests` additions, regenerated goldens, the flipped `restingKeepsGravityOn` |

## Contracts to keep in mind

- **Normals point from B toward A.** The legacy convention was shape-dependent; the new one is strict. `Contact.flipped` swaps sides.
- **Contact gates are inclusive** (`depth >= 0`), matching the legacy `<=` tests. Coincident sphere centers give a zero normal, as before. Both are covered by goldens; changing either needs a reviewed regeneration.
- **Deepest contact drives the response; every contact fires `onContact`.** Handlers run after the response, on the UpdateThread, and must not change physics state.
- **`SphereRigidBody.collisionRadius` is world meters.** Its world view does not apply node scale and carries no name or group. `LocalCollider` dimensions are local meters times `uniformScale`. That is why the sphere body keeps its own radius instead of a one-sphere collider list: scaled balls in `FlightboxWithPhysics` would otherwise be scaled twice.
- **Planes are body-level.** `PlaneRigidBody` has no colliders; the narrow phase tests every collider of the other body against the infinite plane through the plane's position with its normal. Tilted and translated planes work.
- **Response constants** (`HeckerCollisionResponse`): restitution velocity threshold 1 m/s, penetration slop 5 mm, position correction β 0.2. Steps: correct position by β × (depth − slop) split by inverse mass; skip separating contacts; e = 0 below the threshold; apply the impulse always. A resting body is re-supported every step with gravity on; its velocity at the frame boundary is about one gravity step (g·dt) and it sits about slop + sink/β below touching.
- **Cache invalidation.** `setPosition` covers mid-step moves (response corrections, integration). The world's start-of-step sweep covers node changes between steps (attitude rotation). Rotation cannot change mid-step today; if a later phase integrates rotation, that write must also invalidate.
- **Filtering** is inert: every body has the default category and the all mask. The same-GameObject exclusion in `shouldCollide` is the only active rule.

## Exit criteria (all closed 2026-08-31)

1. - [x] A-routing left the goldens byte-identical; game played the same.
2. - [x] A-response goldens regenerated and reviewed; `CollisionResponseTests` green; no solver writes to `shouldApplyGravity`.
3. - [x] Tilted and translated planes correct (`NarrowPhaseTests`).
4. - [x] The F-22 compound settles on the fuselage at y ≈ 1.05 and reports contacts by name in-app.
5. - [x] No process-wide state added; determinism test green.
6. - [x] CI green on all three commits.
7. - [x] Stress scene: about 1.4× the per-step cost at sub-millisecond scale, same broad-phase reduction; the scene's camera bug predated Phase A and is fixed.

---

# Phase A cleanup — changes to make before Phase B ✅ (closed 2026-09-03)

These are the simplifications from the 2026-09-02 review. None changes behavior. Land them as one or two plumbing commits under rule 2: full serial suite green, regeneration dry run byte-identical, `FlightboxWithPhysics` plays the same. C5 (`pose()`) must land before Phase B; the rest can land in any order. Line numbers refer to the tree at `58dbd67`.

## C1 — `HeckerCollisionResponse`: drop the unused `deltaTime`, share `resolvePair`

- [x] `resolveCollisions(deltaTime:collisionPairs:contactsScratch:)` becomes `resolveCollisions(collisionPairs:contactsScratch:)`. The body never reads `deltaTime` (HeckerCollisionResponse.swift:30).
- [x] Delete the `entities:` overload (line 42); C3 removes its only caller.
- [x] `resolvePair` (line 56) becomes internal so `EulerSolver` can call it.
- [x] `final class HeckerCollisionResponse` becomes `enum HeckerCollisionResponse`; nothing instantiates it, and `NarrowPhase` is already an enum.

Resulting shape of the file (bodies of `resolvePair` and `applyCollisionResponse` unchanged):

```swift
enum HeckerCollisionResponse {
    /// Below this approach speed restitution is 0: the impulse cancels the
    /// normal velocity instead of bouncing, so a resting body is re-supported
    /// every step and gravity stays on. Box2D and Jolt use about 1 m/s.
    private static let restitutionVelocityThreshold: Float = 1.0
    /// Penetration allowed before position correction starts (meters).
    private static let penetrationSlop: Float = 0.005
    /// Fraction of the penetration beyond the slop corrected per step.
    private static let positionCorrectionBeta: Float = 0.2

    /// Resolves every candidate pair. `contactsScratch` is cleared and
    /// refilled; it is reused scratch, not storage.
    static func resolveCollisions(collisionPairs: [(RigidBody, RigidBody)],
                                  contactsScratch: inout [Contact]) {
        contactsScratch.removeAll(keepingCapacity: true)
        for (entityA, entityB) in collisionPairs {
            resolvePair(entityA, entityB, contacts: &contactsScratch)
        }
    }

    /// One narrow phase per pair: filter, generate contacts, mark the pair as
    /// collided, respond to the deepest contact, then fire onContact for every
    /// contact (handlers see post-response state). Shared with EulerSolver.
    static func resolvePair(_ entityA: RigidBody, _ entityB: RigidBody, contacts: inout [Contact]) {
        // unchanged
    }

    /// Linear contact response for the deepest contact of a pair: position
    /// correction with slop and β, then an impulse with restitution above a
    /// speed threshold. Symmetric in inverse mass, so a static body (inverse
    /// mass 0) neither moves nor changes velocity. Shared by both solvers.
    static func applyCollisionResponse(_ entityA: RigidBody, _ entityB: RigidBody, contact: Contact) {
        // unchanged
    }
}
```

## C2 — `EulerSolver`: delete the duplicate pair routing

Since A-response, `EulerSolver.resolvePair` (EulerSolver.swift:76) is line for line the Hecker one, and `resolveCollisionsAllPairs` (line 62) duplicates the Hecker entities overload.

- [x] Delete `resolvePair` and `resolveCollisionsAllPairs`.
- [x] Delete `step(deltaTime:gravity:entities:contactsScratch:)` (line 26); C3 removes its only caller.
- [x] The protocol wrapper `step(deltaTime:gravity:entities:)` builds an all-pairs list with `PhysicsWorld.appendAllPairs` (C3). `PhysicsSolverTests` calls it three times with `TestRigidBody`s; those have no colliders, so they produce no contacts, as today.
- [ ] Optional O1 below: delete `applyLegacyEulerResponse` and `restSpeedThresholdSquared`. (Not taken; comments shortened per C9.)

Resulting file (without O1):

```swift
final class EulerSolver: PhysicsSolver {
    /// PhysicsSolver conformance and direct test entry: every pair is a
    /// candidate. PhysicsWorld uses the overload below with its own scratch.
    public static func step(deltaTime: Float, gravity: float3, entities: [RigidBody]) {
        var pairs: [(RigidBody, RigidBody)] = []
        PhysicsWorld.appendAllPairs(of: entities, into: &pairs)
        var contacts: [Contact] = []
        step(deltaTime: deltaTime, gravity: gravity, entities: entities,
             collisionPairs: pairs, contactsScratch: &contacts)
    }

    /// Semi-implicit Euler: forces, then contacts on the candidate pairs,
    /// then integration.
    public static func step(deltaTime: Float, gravity: float3, entities: [RigidBody],
                            collisionPairs: [(RigidBody, RigidBody)],
                            contactsScratch: inout [Contact]) {
        applyForces(deltaTime: deltaTime, gravity: gravity, entities: entities)
        contactsScratch.removeAll(keepingCapacity: true)
        for (a, b) in collisionPairs {
            HeckerCollisionResponse.resolvePair(a, b, contacts: &contactsScratch)
        }
        moveObjects(deltaTime: deltaTime, entities: entities)
        zeroForces(entities: entities)
    }

    public static func applyForces(deltaTime: Float, gravity: float3, entities: [RigidBody]) {
        // unchanged
    }

    static func moveObjects(deltaTime: Float, entities: [RigidBody]) {
        // unchanged
    }

    // applyLegacyEulerResponse and restSpeedThresholdSquared: unchanged unless O1 is taken.
}
```

## C3 — `PhysicsWorld`: one code path

The four private update methods (PhysicsWorld.swift:96–126) and the two switches collapse into one. With the broad phase off, the world builds every unordered pair in index order, which is the order the old O(n²) loops visited, so the goldens do not move.

- [x] Add `allPairsScratch` and `appendAllPairs(of:into:)`.
- [x] Rewrite `update(deltaTime:)` as below.
- [ ] Delete `naiveUpdate`, `heckerVerletUpdate`, `naiveUpdateOriginal`, `heckerVerletUpdateOriginal`. **Deferred by owner decision (2026-09-02):** kept as private, unused methods with a deprecation comment. The two `*Original` bodies now build their pair list with `appendAllPairs` (their old O(n²) callees are gone). Delete all four in a later plumbing commit.

```swift
final class PhysicsWorld {
    public static let gravity: float3 = [0, -9.81, 0]

    // Storage is the concrete class RigidBody for direct dispatch in the solver
    // loops. If a second PhysicsEntity type is ever added, give it a RigidBody
    // base or revisit the solver signatures.
    private var entities: [RigidBody]
    private var updateType: PhysicsUpdateType
    private var broadPhase = BroadPhaseCollisionDetector()

    /// Reused per-instance scratch (tests run several worlds concurrently in
    /// one process, so nothing here may be static).
    private var contactsScratch: [Contact] = []
    private var allPairsScratch: [(RigidBody, RigidBody)] = []

    /// When false, every pair is a candidate: the O(n²) comparison baseline for
    /// the broad phase's statistics. Four of the six parity goldens run this way.
    public var useBroadPhase: Bool = true
    public var collectBroadPhaseStatistics: Bool {
        get { broadPhase.collectStatistics }
        set { broadPhase.collectStatistics = newValue }
    }

    // init, setEntities, addEntity, addEntities: unchanged

    public func update(deltaTime: Float) {
        for entity in entities {
            entity.resetCollisions()
            // Node transforms can change between steps without going through
            // RigidBody.setPosition (attitude rotation), so every world-collider
            // cache is invalidated here. setPosition covers mid-step moves.
            entity.invalidateWorldColliders()
        }

        let pairs: [(RigidBody, RigidBody)]
        if useBroadPhase {
            broadPhase.update(entities: entities)
            pairs = broadPhase.getPotentialCollisionPairs()
        } else {
            Self.appendAllPairs(of: entities, into: &allPairsScratch)
            pairs = allPairsScratch
        }

        switch updateType {
            case .NaiveEuler:
                EulerSolver.step(deltaTime: deltaTime, gravity: Self.gravity, entities: entities,
                                 collisionPairs: pairs, contactsScratch: &contactsScratch)
            case .HeckerVerlet:
                HeckerCollisionResponse.resolveCollisions(collisionPairs: pairs,
                                                          contactsScratch: &contactsScratch)
                VerletSolver.step(deltaTime: deltaTime, gravity: Self.gravity, entities: entities)
        }
    }

    /// Every unordered pair (i < j) in index order: the same visiting order as
    /// the old O(n²) loops, so the goldens do not move.
    static func appendAllPairs(of entities: [RigidBody], into out: inout [(RigidBody, RigidBody)]) {
        out.removeAll(keepingCapacity: true)
        for i in 0..<entities.count {
            for j in (i + 1)..<entities.count {
                out.append((entities[i], entities[j]))
            }
        }
    }

    public func getBroadPhaseStats() -> (totalChecks: Int, checksSaved: Int) {
        return broadPhase.getStatistics()
    }
}
```

## C4 — `RigidBody`: one designated init

The two designated inits (RigidBody.swift:159 and :196) repeat a ten-line stored-property block, and a twelve-line comment explains why. Replacing `isStandalone: Bool` plus `standalonePosition: float3` with one optional removes the reason: nil means attached. The released-weak fallbacks that `RigidBodyTests.rigidBodyToleratesNilGameObject` asserts are unchanged (an attached body with a released GameObject has a nil `standalonePosition`, reads `.zero`, and ignores `setPosition`). `TestRigidBody` in `PhysicsSolverTests` still compiles: it calls `super.init(gameObject: nil, mass: ...)`, and the new parameters are defaulted.

- [x] Replace the storage, the two inits, `setPosition`, and `getPosition` with:

```swift
    // GameObject this is attached to:
    weak let gameObject: GameObject?

    /// Set only for detached bodies (tests): position lives here instead of
    /// on a node. nil for attached bodies, including one whose GameObject was
    /// released, which keeps reading .zero and ignoring setPosition.
    private var standalonePosition: float3?

    /// `gameObject` is optional so test doubles can exist without a GameObject
    /// (and therefore without Metal). Production code passes a GameObject;
    /// tests pass nil and, for a detached body, a `standalonePosition`.
    internal init(gameObject: GameObject?,
                  standalonePosition: float3? = nil,
                  collidedWith: Set<ObjectIdentifier> = [],
                  mass: Float = 1,
                  velocity: float3 = .zero,
                  acceleration: float3 = .zero,
                  force: float3 = .zero,
                  restitution: Float = 1,
                  isStatic: Bool = false,
                  shouldApplyGravity: Bool = true) {
        self.gameObject = gameObject
        self.standalonePosition = standalonePosition
        self.collidedWith = collidedWith
        self.mass = mass
        self.velocity = velocity
        self.acceleration = acceleration
        self.force = force
        self.restitution = restitution
        self.isStatic = isStatic
        self.shouldApplyGravity = shouldApplyGravity

        // Register with the object this is attached to:
        gameObject?.rigidBody = self
    }

    /// Detached body for Metal-free tests: the real class, no GameObject.
    internal convenience init(detachedAt position: float3) {
        self.init(gameObject: nil, standalonePosition: position)
    }

    func setPosition(_ position: float3) {
        invalidateWorldColliders()
        if standalonePosition != nil {
            standalonePosition = position
        } else {
            gameObject?.setPosition(position)
        }
    }

    func getPosition() -> float3 {
        standalonePosition ?? gameObject?.getPosition() ?? .zero
    }
```

- [x] `BasicRigidBodies.swift`: the two detached inits call the designated init directly (a subclass cannot chain to a superclass convenience init):

```swift
    // SphereRigidBody
    init(detachedAt position: float3, collisionRadius: Float = 1.0) {
        super.init(gameObject: nil, standalonePosition: position)
        self.collisionRadius = collisionRadius
    }
    // PlaneRigidBody
    init(detachedAt position: float3, collisionNormal: float3 = [0, 1, 0]) {
        super.init(gameObject: nil, standalonePosition: position)
        self.collisionNormal = collisionNormal.normalize()
    }
```

## C5 — `RigidBody.pose()` (required by Phase B)

`rebuildWorldColliders` (RigidBody.swift:109–132) gathers position, rotation, and scale twice, once per branch. Phase B's suspension needs the same three values. One accessor serves both.

- [x] Add `pose()` and rewrite `rebuildWorldColliders` to use it:

```swift
    /// The body's world pose for collider and strut math. Attached bodies read
    /// their node's LOCAL transform, which is valid only for scene-root
    /// children (asserted). Detached bodies, and attached bodies whose
    /// GameObject was released, get the identity rotation at getPosition().
    func pose() -> (position: float3, rotation: float3x3, uniformScale: Float) {
        guard let node = gameObject else {
            return (getPosition(), matrix_identity_float3x3, 1.0)
        }
        assert(node.parent == nil || node.parent is GameScene,
               "RigidBody on nested node '\(node.getName())': pose math assumes a scene-root child")
        return (node.getPosition(), node.getRotationMatrix().upperLeft3x3, node.uniformScale)
    }

    /// Override point; SphereRigidBody builds its one-sphere view here.
    internal func rebuildWorldColliders() {
        guard !colliders.isEmpty else {
            worldCollidersScratch.removeAll(keepingCapacity: true)
            return
        }
        let pose = pose()
        WorldColliderBuilder.build(colliders,
                                   bodyPosition: pose.position,
                                   bodyRotation: pose.rotation,
                                   uniformScale: pose.uniformScale,
                                   into: &worldCollidersScratch)
    }
```

The assert moves from `rebuildWorldColliders` into `pose()`. Its reach is the same today: `pose()` is called only from there (bodies with colliders) and, after B.5, from the suspension on the player aircraft.

## C6 — `Contact`: one initializer

`Contact` (Contact.swift:33–57) has a public init taking two `WorldCollider?` and a private memberwise-style init used only by `flipped`. Moving the convenience init into an extension keeps the synthesized memberwise init available, so the private one goes.

- [x] Delete the private init; move the `collider:against:` init into an extension:

```swift
struct Contact {
    /// Unit length, from B toward A.
    let normal: float3
    let depth: Float
    /// World-space contact point. Unused by the linear response; kept for
    /// angular dynamics later.
    let point: float3
    /// nil for a simple body: a SphereRigidBody's view or the infinite plane.
    let colliderNameA: String?
    let colliderGroupA: ColliderGroup?
    let colliderNameB: String?
    let colliderGroupB: ColliderGroup?

    /// The same contact with A and B swapped.
    var flipped: Contact {
        Contact(normal: -normal, depth: depth, point: point,
                colliderNameA: colliderNameB, colliderGroupA: colliderGroupB,
                colliderNameB: colliderNameA, colliderGroupB: colliderGroupA)
    }
}

extension Contact {
    /// Contact from the colliders that produced it. Either may be nil: the
    /// plane side, or a legacy sphere's view, which has no name or group.
    init(normal: float3, depth: Float, point: float3,
         collider a: WorldCollider? = nil, against b: WorldCollider? = nil) {
        self.init(normal: normal, depth: depth, point: point,
                  colliderNameA: a?.name, colliderGroupA: a?.group,
                  colliderNameB: b?.name, colliderGroupB: b?.group)
    }
}
```

## C7 — `NarrowPhase.generateContacts`: one append helper

The append-and-compare block with a force unwrap appears twice (NarrowPhase.swift:61–64 and :78–81).

- [x] Add the helper and use it in both loops:

```swift
    /// Appends `contact` and keeps `deepest` at the index of the deepest
    /// contact appended so far. Ties keep the earlier contact, as before.
    private static func append(_ contact: Contact, to contacts: inout [Contact], deepest: inout Int?) {
        contacts.append(contact)
        if let current = deepest, contacts[current].depth >= contact.depth { return }
        deepest = contacts.count - 1
    }
```

```swift
            for collider in a.worldColliders() {
                if let contact = shapeVsPlane(collider, planePoint: planePoint, planeNormal: planeNormal) {
                    append(contact, to: &contacts, deepest: &deepest)
                }
            }
```

```swift
        for colliderA in a.worldColliders() {
            for colliderB in b.worldColliders() {
                if let contact = shapeVsShape(colliderA, colliderB) {
                    append(contact, to: &contacts, deepest: &deepest)
                }
            }
        }
```

## C8 — delete reserved API nothing reads

- [x] `PhysicsMaterial` and `LocalCollider.material` with its init parameter (ColliderShape.swift:14–18, :83–85, :93, :102). No code reads them. The original reason, avoiding spec churn when Phase D adds materials, does not hold: a defaulted init parameter added later changes no spec. No test references them.
- [x] `PhysicsEntity.isDynamic` (PhysicsEntity.swift:49–52). Unused.

## C9 — shorten narrative doc comments

The rule: a comment says what the code does and why, in one to four lines. Research citations ("combined doc D3", "research §3.4", "P1", "correction 2") and plan history ("A-ROUTING TRANSCRIPTION", "dies in A.6") go; the plan holds them. Replacement text for the longest ones:

| Location | Replace with |
|---|---|
| `RigidBody.swift:44–50` (`colliders`) | Compound collision geometry: primitives at body-local offsets. Empty for planes (handled at body level in the narrow phase), ignored by SphereRigidBody (it uses collisionRadius); a plain RigidBody with no colliders makes no contacts. |
| `RigidBody.swift:55–57` (masks) | Collision filtering: a pair is tested only if each body's category intersects the other's mask. Defaults collide with everything. |
| `RigidBody.swift:61–67` (`onContact`) | Called once per contact this body is part of, on the UpdateThread, after the response for that pair. Every collider-pair contact fires, not only the deepest. The Contact has self as A. Keep it cheap; do not change physics state here. |
| `RigidBody.swift:69–83` (cache) | World-space collider cache behind a dirty flag. Invalidated by setPosition, by collider changes, and by the world at the start of every step (node rotation does not go through setPosition). Code that moves a body outside a stepped world must call invalidateWorldColliders(). `worldCollidersScratch` is internal only so subclass rebuilds can write it. |
| `RigidBody.swift:135–139` (`shouldCollide`) | Symmetric filter: category and mask both ways, and never two bodies on the same GameObject. |
| `BasicRigidBodies.swift:23–25`, `:30–35` | One-sphere world view so the narrow phase has a single collider-based path. collisionRadius is world meters, so node scale is not applied; name and group are nil. |
| `NarrowPhase.swift:10–18` (header) | Pure narrow phase: WorldCollider geometry in, Contacts out. No body mutation, no Metal. The sphere-sphere and sphere-plane paths reproduce the pre-Phase-A arithmetic operation for operation; changing them requires a reviewed golden regeneration. |
| `NarrowPhase.swift:22–28` (`generateContacts`) | Appends every contacting collider pair between the two bodies and returns the index into `contacts` of the deepest one, or nil. The linear response uses only the deepest; events use all. |
| `NarrowPhase.swift:39–47` (flip) | The recursive call built contacts with the volume body as A; flip them so the caller's order (A = plane, B = volume) holds. Flipping keeps each index and depth, so `deepest` stays valid. |
| `NarrowPhase.swift:91–97` (`shapeVsPlane`) | Sphere, capsule, or box against the infinite plane through planePoint. Gates are inclusive (depth >= 0). |
| `NarrowPhase.swift:222–238` (`sphereVsSphere`) | Squared compare: no sqrt on the reject path, and the same form as the legacy test, which the goldens cover. Coincident centers give a zero normal, as before. |
| `NarrowPhase.swift:297–300`, `:315–320`, `:325–333` | One or two lines each: capsule axis is the rotation's second column; clamped projection onto the segment; Ericson §5.1.9 with the book's variable names. |
| `HeckerCollisionResponse.swift:51–55`, `:73–83` | See the C1 listing. |
| `PhysicsWorld.swift:28–33`, `:64–67` | See the C3 listing. |
| `ColliderShape.swift:106–109` (`WorldCollider`) | A LocalCollider in world space for one narrow-phase query. Read it from RigidBody.worldColliders(); do not keep it across steps, the backing array is reused. |
| `ColliderShape.swift:114–116` (metadata) | nil for the view of a SphereRigidBody, which has no authored collider. |
| `ColliderShape.swift:153–158` (`WorldColliderBuilder`) | Pure LocalCollider × body pose → WorldCollider, kept free of RigidBody and Node so it is testable without Metal. The offset order, rotate(localPosition × scale), matches the overlay's scene-graph composition. |
| `Contact.swift:8–13`, `:17–19`, `:29–32` | See the C6 listing. |
| `ColliderDebugOverlay.swift:99–101` (colors) | Alpha < 1 makes isTransparent true, which routes the volumes into the transparent collection at registration, so setColor comes before Register. |
| `ColliderDebugOverlay.swift:119–126` (`hostWasReplaced`) | Aircraft swap: SceneManager.RemoveObject already detached and unregistered the old subtree, volumes included. Drop the stale references (removeFromScene on them would be redundant) and re-apply the mode to the new host. |
| `ColliderDebugOverlay.swift:193–203` (ghost) | The legacy sphere sits at the body origin. collisionRadius is world meters and the ghost is a child, so divide by the parent's scale. A compound aircraft has a plain RigidBody and gets no ghost; its red volumes are the live colliders. |
| `AircraftColliderSpec.swift:8–18` | Compound collider specs per aircraft in post-import meters (1 unit = 1 m after meterization; aircraft run at scale 1.0). Verified in-app with the overlay on 2026-08-29 and live physics geometry since Phase A. Re-check with the X-key overlay after any edit. Units contract: this plan, Phase 0. |
| `GameScene.swift:89–93` (teardown) | Bookkeeping reset only: the whole subtree is being dropped and SceneManager.TeardownScene clears the batched collections. The rebuilt scene starts with the overlay off. |
| `EulerSolver.swift:11–15`, `:94–103` | Gone with O1; otherwise: "Legacy per-axis response, unreferenced since A-response; kept as reference code." |

## C10 — pointers to the renamed plan

- [x] `AircraftColliderSpec.swift:14`, `PhysicsParityTests.swift:5`: point at this file (Phase 0, "Units contract" and "Parity harness").
- [x] `research/claude/meter_scale_units_research_2026-07-20.md:5`: point at `compound_rigid_bodies_implementation_plan_original.md`.

## Optional (low priority, not needed for Phase B)

- **O1** Delete `applyLegacyEulerResponse` and `restSpeedThresholdSquared` (EulerSolver.swift:11–15, :94–150). Kept by owner decision as reference code; git history keeps it readable, and no golden describes that response any more.
- **O2** Delete `SphereRigidBody.getAABB()` (BasicRigidBodies.swift:23–28). The base union over the one-sphere view gives the same box; the override is one extra path to reason about.
- **O3** Delete `WorldCollider.sourceIndex` (ColliderShape.swift:117). Only three test assertions read it (`WorldColliderBuilderTests`, `RigidBodyTests`). Keep it if Phase D will map contacts back to `LocalCollider`s.
- **O4** Delete the `PhysicsSolver` protocol. Two conformers, no generic consumer; its only content is `zeroForces`, which can be a free function.
- **O5** Fold `Contact`'s four metadata fields into two optional name-plus-group values. `flipped` swaps two fields instead of four; `CompoundBodyTests`, `NarrowPhaseTests`, and `ContactDebugLogger` change their accessors.

## Cleanup gate

- [x] `build-for-testing` green; full serial suite green against unchanged goldens (2026-09-02: 286 Swift Testing tests in 45 suites + 20 XCTest, all passed).
- [x] Regeneration dry run byte-identical (`git diff --exit-code` on `Baselines/` empty; discard the designed failure; clean re-run green). Done 2026-09-02.
- [x] `FlightboxWithPhysics` and `BallPhysicsScene` play the same. (Owner verified the game runs after C1–C7; C8–C10 and the dead-code removal were not re-checked in-app. Closed with the section, 2026-09-03.)
- [x] Commit message names the commit as Phase A cleanup (plumbing).

---

# Phase B — fixed timestep, forces inside the step, raycast landing gear, touchdown classification

*(Re-planned 2026-09-02 against the tree at `58dbd67`, assuming the Phase A cleanup above has landed.)*

Implements combined doc §4.3 (B1–B3). At the end of this phase:

- physics advances in fixed 1/120 s substeps behind an accumulator, so the menu's 30–120 Hz refresh selection no longer changes physics (today `update(deltaTime:)` consumes the raw frame delta);
- forces are computed inside the step by a per-body hook instead of one frame late in `Aircraft.doUpdate`;
- the F-22 stands, taxis, and lands on three raycast suspension struts (spring and damper on the one aircraft body; no gear bodies, no joints), gated by the existing gear animation;
- touchdown, gear overload, scrape, and crash are reported by name through a print-only reporter.

**What Phase B does not change:** the narrow phase, `applyCollisionResponse` and its constants (β, slop, restitution threshold), the collider specs, and the overlay machinery except for a strut layer. Rest jitter at 30 Hz is fixed by the timestep, not by retuning β.

## Commits

No step straddles a commit boundary; each commit is one kind of change (rule 2).

| Commit | Steps | Gate | Tests |
|---|---|---|---|
| **B-generators** | B.1–B.2 | Plumbing. Goldens byte-identical (no harness body has a force hook). In-app: flight feels the same; throttle response at most one frame crisper. | `ForceGeneratorTests` (new) |
| **B-timestep** | B.3 | Behavior. Regenerate all six goldens and review against the table in B.3. `CollisionResponseTests`, `CompoundBodyTests`, `restingKeepsGravityOn`, `PhysicsWorldSmokeTests` green unedited; the two flagged `ForceGeneratorTests` expectations flip to substep values. In-app: ball scenes settle the same at 30, 60, and 120 Hz. | `FixedTimestepTests` (new) |
| **B-suspension** | B.4–B.5 | Goldens untouched (no harness scenario has struts). In-app: the F-22 stands on its wheels at the logged ride height; gear up drops it to the belly rest; the cyan strut lines match the modeled gear. | `SuspensionSolverTests`, `AircraftGearSpecTests`, `GearSuspensionWorldTests` (new); additions to `NarrowPhaseTests` and `ColliderOverlayMappingTests` |
| **B-classification** | B.6 | Goldens untouched (observers only). In-app: touchdown, gear-overload, scrape, and crash lines print as described in B.6. | `AirframeContactClassifierTests` (new); one addition to `GearSuspensionWorldTests` |

## Decisions that differ from the research docs or the original Phase B plan

| Decision | Why |
|---|---|
| Force generation is a closure on `RigidBody` (`forceGenerator`), not a registry of protocol objects | Every planned generator belongs to one body. The closure leaves the world with its body on the entity swap, so there is no add/remove bookkeeping, no dedupe, and no retain cycle to audit. Same pattern as `onContact`. A generator spanning several bodies would need a registry; none is planned. |
| No `addForce(_:atWorldPoint:)` | An argument that does nothing until Phase D misleads readers into assuming torque is applied. The suspension adds to `force`; the point-taking API arrives with torque. |
| `RigidBody.pose()` feeds both colliders and struts | One place computes position, rotation, and scale for attached and detached bodies (Phase A cleanup C5). |
| The overlay takes an `AircraftType` | Both call sites hold the type. The overlay looks up collider and strut specs itself, so a new spec kind changes no signatures. |
| `stepStartVelocity` on `RigidBody`, written by the world | Pre-impact velocity for classification is available for every body with no `Aircraft` cache and no test-rig duplicate. |
| Substeps counted by division, not a `while` loop | `Int(accumulator / fixedDelta)` and one subtraction are exact in Float for 1/30, 1/60, 1/120, and 1/240 s frames (checked 2026-09-02: zero residue), so `FixedTimestepTests` compares partitions with `==`. |
| `raycastStaticPlanes` returns the nearest distance only | The strut needs the distance; nothing reads a hit point or normal yet. |
| B1 splits into B-generators and B-timestep | Plumbing and behavior in separate commits (rule 2). |
| `PhysicsWorld.update(deltaTime:)` keeps its name | Four scenes and about fifteen test call sites; the parameter is still the frame delta. |
| The gear gate is `Aircraft.isGearDown` | The animator's fully-deployed flag, already used by gameplay. Partial deployment is deferred (combined doc D8). |
| Strut lengths scale with `uniformScale`; spring and damper rates do not | Rates are sized against the aircraft's mass, which scaling a model does not change. Scaled rates would make a scaled aircraft sit too low or be pushed up. |
| Gear load split follows spring rates, not lever arms | Rotation is kinematic, so equal-reach struts share one compression and per-strut load is k·x (about 89/11 mains/nose here, not the geometric 85/15). Total force and ride height are exact; the split corrects itself when Phase D adds pitch. |
| Sink rate is −v.y; strut force acts along body up | Level-runway simplifications, noted at the code sites. |

## Step B.1 — the force hook on `RigidBody` and the world call — B-generators

Why: the physics step runs at the top of the scene's `doUpdate`, before children traverse, so the aircraft's subtree (attached camera included) sees post-physics transforms in the same frame. That placement stays. But it means forces written in a child's `doUpdate` (the flight model, in `Aircraft`) reach the step one frame late. The fix is a hook the world calls at the top of each step.

- [x] **Edit:** `Physics/World/RigidBody.swift`, next to `onContact`:

```swift
    /// Per-substep force source, called by PhysicsWorld at the top of every
    /// step before collision detection and integration, with this body as the
    /// first argument. Add to `force`; it is zeroed at the end of each step,
    /// so write it on every call. Do not move the body or change its velocity
    /// here. nil for bodies that only feel gravity and contacts.
    var forceGenerator: ((_ body: RigidBody, _ substepDelta: Float, _ world: PhysicsWorld) -> Void)?
```

- [x] **Edit:** `Physics/World/PhysicsWorld.swift`, the start-of-step loop:

```diff
         for entity in entities {
             entity.resetCollisions()
             entity.invalidateWorldColliders()
+            entity.forceGenerator?(entity, deltaTime, self)
         }
```

Goldens: no harness body sets `forceGenerator`, so the new line is a nil check. Byte-identical.

## Step B.2 — `Aircraft` computes its flight force inside the step — completes B-generators

`doUpdate` keeps what belongs to the frame (input sampling, the attitude filter, animator, gear toggle) and only caches the sampled input; the force is computed by `generateForces`, which the body's hook calls at the top of every step. The remaining one-frame input latency (stick sampled in frame N−1 feeds frame N's steps) is standard for engines that decouple input from fixed steps and is far below the attitude filter's time constants.

- [x] **Edit:** `GameObjects/Aircraft.swift`. The cached input, next to `flightModel`:

```swift
    /// Control input sampled once per frame in doUpdate and read by
    /// generateForces on every physics substep. nil while the aircraft is
    /// unfocused or not player-driven, so there is no flight force without
    /// focus, as before.
    private var latestControlInput: ControlInput?
```

The hook is installed whenever a body attaches, so aircraft swaps need no bookkeeping:

```diff
     override var rigidBody: RigidBody? {
         didSet {
             if let flightModel {
                 rigidBody?.mass = flightModel.mass
             }
+            // The world calls this from inside the physics step. Weak self:
+            // the aircraft owns the body, so a strong capture would be a cycle.
+            rigidBody?.forceGenerator = { [weak self] _, substepDelta, world in
+                self?.generateForces(substepDelta: substepDelta, world: world)
+            }
         }
     }
```

The generator, placed after `doUpdate` (B.5 extends it at the marked point):

```swift
    /// Called by the physics world at the top of each step (each substep after
    /// B.3), on the UpdateThread, from live body state. doUpdate runs later in
    /// the frame, after the step, and only refreshes the cached input.
    func generateForces(substepDelta: Float, world: PhysicsWorld) {
        guard let rigidBody else { return }

        if let input = latestControlInput,
           let flightModel,
           let state = rigidBody.getState() {
            rigidBody.force += flightModel.computeForce(state: state, input: input)
        }

        // B.5 adds the landing-gear suspension here, outside the input guard:
        // a parked, unfocused aircraft must still be held up.
    }
```

The `doUpdate` migration (the force block becomes the cache write; everything else stays):

```diff
         if shouldUpdateOnPlayerInput && hasFocus {
             let controlInput = getControlInput()
             let deltaMove = dt * _moveSpeed

-            if let rigidBody,
-               let flightModel,
-               let rigidBodyState = rigidBody.getState() {
-                let force = flightModel.computeForce(state: rigidBodyState, input: controlInput)
-                rigidBody.force += force
-            } else {
+            // Flight forces are computed in generateForces, inside the physics
+            // step. Here we only refresh the input it reads.
+            latestControlInput = controlInput
+            if rigidBody == nil || flightModel == nil {
+                // Kinematic fallback for aircraft without physics (the F-16
+                // wingman). Small change from before: a body whose getState()
+                // is nil now gets neither force nor kinematic motion.
                 moveAlongVector(getFwdVector(), distance: deltaMove * controlInput.throttle)
             }

             applyPlayerAttitudeInput(deltaTime: dt, controlInput: controlInput)
             applyPlayerSideMove(deltaMove: deltaMove)
             handleGearToggle()
         } else {
+            latestControlInput = nil
             decayAttitudeRates(deltaTime: dt)
```

No scene changes. On an aircraft swap the old body leaves the entity list through `swappedEntities`, so its hook is never called again, and the old aircraft still deallocates (weak capture). `FreeCamFlightboxScene`'s F-22 has a body but no flight model, so its hook does nothing, as before; the F-16 wingman has neither and keeps its kinematic fallback.

Goldens: no harness world contains an aircraft; nothing else on the step path changed. Byte-identical.

- [x] **File (new):** `ToyFlightSimulatorTests/Physics/ForceGeneratorTests.swift`

```swift
import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Force generators", .tags(.physics))
struct ForceGeneratorTests {
    private static let dt: Float = 1.0 / 60.0

    @Test("the hook runs once per update with the step delta")
    func hookRunsOncePerUpdate() {
        let body = RigidBody(detachedAt: .zero)
        body.shouldApplyGravity = false
        var calls = 0
        var lastDelta: Float = 0
        body.forceGenerator = { _, delta, _ in
            calls += 1
            lastDelta = delta
        }
        let world = PhysicsWorld(entities: [body], updateType: .HeckerVerlet)
        for _ in 0..<5 { world.update(deltaTime: Self.dt) }
        #expect(calls == 5)               // B.3: 10 (two substeps per update)
        #expect(lastDelta == Self.dt)     // B.3: PhysicsWorld.fixedDelta
    }

    @Test("a constant force accelerates the body through the Verlet half kick")
    func constantForceAccelerates() {
        let body = RigidBody(detachedAt: .zero)
        body.mass = 2
        body.shouldApplyGravity = false
        body.forceGenerator = { body, _, _ in body.force += [10, 0, 0] }
        let world = PhysicsWorld(entities: [body], updateType: .HeckerVerlet)
        world.update(deltaTime: Self.dt)
        // Velocity Verlet starts with a half kick: Δv = ½·(F/m)·dt.
        #expect(approxEqual(body.velocity.x, 0.5 * 5 * Self.dt))   // B.3: 1.5 · 5 · fixedDelta
        #expect(body.force == .zero, "forces are zeroed at the end of the step")
    }
}
```

## Step B.3 — fixed 1/120 s substeps — B-timestep

Implements combined doc D4: physics must not change with the refresh rate, stiff suspension springs (B.4) want a small fixed step, and the rest jitter bound g·dt² becomes a constant (0.68 mm at 120 Hz, versus 2.7 mm at 60 and 10.9 mm at 30). Every golden regenerates, because halving the integration step changes every trajectory.

- [x] **Edit:** `Physics/World/PhysicsWorld.swift`. The existing `update(deltaTime:)` body moves unchanged into a private `step(deltaTime:)`; the new `update` is the accumulator:

```swift
    /// Fixed simulation step. Physics must not change with the menu's
    /// 30–120 Hz refresh selection; before this commit it did, because
    /// update(deltaTime:) consumed the raw frame delta. 1/120 s divides every
    /// selectable frame period exactly (120 Hz: 1 substep per frame, 60 Hz: 2,
    /// 30 Hz: 4) and makes the rest jitter bound g·dt² a constant 0.68 mm.
    public static let fixedDelta: Float = 1.0 / 120.0

    /// At most this many substeps per update call (66.7 ms of simulated
    /// time). Time beyond it is dropped, not carried, like
    /// UpdateThread.maxDeltaTime one level down. Replaces the scenes'
    /// `GameTime.DeltaTime < 1.0` guards.
    public static let maxSubstepsPerUpdate = 8

    private var accumulator: Float = 0

    /// `deltaTime` is the frame delta. The world advances in fixed substeps
    /// and banks the remainder. Counting by division and subtracting once is
    /// exact in Float for 1/30, 1/60, 1/120 and 1/240 s frames (zero residue),
    /// which lets FixedTimestepTests compare partitions with ==.
    public func update(deltaTime: Float) {
        accumulator = min(accumulator + deltaTime, Float(Self.maxSubstepsPerUpdate) * Self.fixedDelta)
        let substeps = Int(accumulator / Self.fixedDelta)
        accumulator -= Float(substeps) * Self.fixedDelta
        for _ in 0..<substeps {
            step(deltaTime: Self.fixedDelta)
        }
    }

    /// One fixed substep: the previous update(deltaTime:) body, unchanged.
    private func step(deltaTime: Float) {
        for entity in entities {
            entity.resetCollisions()
            entity.invalidateWorldColliders()
            entity.forceGenerator?(entity, deltaTime, self)
        }
        // ... candidate pairs and the solver switch, unchanged ...
    }
```

- [x] **Edit (×4):** the scenes drop their hitch guards; the clamp lives in the world now, and `UpdateThread.maxDeltaTime` already caps the input at 100 ms.

`FlightboxWithPhysics.doUpdate` (lines 308–312):

```diff
-        let fdTime = Float(GameTime.DeltaTime)
-
-        if GameTime.DeltaTime < 1.0 {
-            physicsWorld.update(deltaTime: fdTime)
-        }
+        // Hitch clamping lives in the world's accumulator (at most 8 substeps
+        // per call); UpdateThread also caps DeltaTime at 100 ms.
+        physicsWorld.update(deltaTime: Float(GameTime.DeltaTime))
```

`BallPhysicsScene.doUpdate` (line 71), `PhysicsStressTestScene.doUpdate` (line 136): remove the `if GameTime.DeltaTime <= 1.0 {` wrapper, keep the `timeit` block. `FreeCamFlightboxScene.doUpdate` (line 78): same, and delete the commented-out block below it.

The stress scene's printed per-call time now covers two substeps at 60 Hz, so it roughly doubles. Compare per-substep cost, and expect about 1.3–1.9 ms per frame at 50 spheres.

### Regenerate the goldens and review the diff

| Scenario | Expected diff |
|---|---|
| `single_bounce_verlet` | Free fall matches within rounding: velocity Verlet integrates constant gravity exactly at any step size, so a pre-contact difference beyond rounding is a bug. First contact may land one substep earlier; bounces persist, apexes shift at cm scale and still decrease, gravity on. |
| `single_bounce_euler` | Free fall shifts: semi-implicit Euler's position bias is ½·g·t·dt, so halving dt halves it (about 4 cm at t = 1 s); first contact lands a few substeps later. Correct: the finer step is closer to the true parabola. |
| `rest_latch` | Final speed about g/120 ≈ 0.082 (was 0.164 = g/60); resting y ≈ 0.493 (was 0.488: slop 5 mm plus a sink term that quarters at 120 Hz). Gravity on throughout. |
| `head_on_pair` | Contact at the same time (0.3 s = 36 substeps). Mirror symmetry exact, velocities swap to ±5, the Y column differs by the finer step. |
| `ball_cluster_16`, `stress_grid_50` | Full regeneration. The invariants (finite, no tunneling, speed budgets) must pass unedited; a tripped budget is a timestep bug, not a budget to raise. |

**Observed at the 2026-09-03 regeneration** (review script over old vs new JSON; the runner's invariants held on every step of every scenario):

| Scenario | Observed |
|---|---|
| `single_bounce_verlet` | First contact at sample 58 in both. Apexes 4.1444 / 3.4517 / 2.8904 → 4.1445 / 3.4514 / 2.8895, decreasing; sampled bounce penetration shallower (min y 0.4247 → 0.4561); gravity on. **The pre-contact column moved by up to 3.9 cm, and that is not rounding:** `VerletSolver` bootstraps from `acceleration = .zero`, so free fall runs exactly h/2 late (y = y₀ − ½·g·(t² − t·h)); old − new matched ½·g·t·(1/60 − 1/120) to 5e-6 over all 58 samples. The row above assumed a warm start. Halving the step halves the lag; removing it (bootstrap a(t) from the forces before the first integrate) is a separate behavior commit that regenerates the goldens. |
| `single_bounce_euler` | Bias halves as predicted (old − new = −½·g·t/120 to 2e-6). First bounce at sample 57 in both; apexes 4.2795 / 3.6868 → 4.2121 / 3.5677, against the exact e = 0.9 values 4.145 / 3.4525, so the finer step is closer to the parabola. |
| `rest_latch` | Final \|v\| 0.1635 → 0.0818 (= g/120), resting y 0.4882 → 0.4933, gravity on, first contact at sample 44 in both. As predicted. |
| `head_on_pair` | Mirror symmetry exact; velocities swap to ±5; the Y column differs by the Verlet bootstrap lag (max 0.0818 = ½·g·2 s/120). **The contact landed at substep 37, not 36:** the scenario touches exactly at t = 0.3 s, and at 120 Hz the substep-36 gap rounds to just above 1.0, so the pair overlaps by one substep (0.0833 m) before responding; the 0.2·(0.0833 − 0.005)/2 = 7.8 mm position correction each is visible at sample 19 and carries through (final A.x −9.0000 → −8.9245). Exact tangency at a step boundary is a rounding coin flip; the scenario stays as designed. |
| `ball_cluster_16`, `stress_grid_50` | Every track differs from sample 1 (the bootstrap lag alone exceeds 1e-4 by t = 0.05 s). Deepest penetration 0.201 → 0.068 m and 0.230 → 0.119 m; samples below touching 10 → 4 and 19 → 10; final speeds within budget (max 8.65 and 15.7 m/s); gravity on everywhere. |

Suites that must stay green without edits, and why: `CollisionResponseTests` (every bound is a ceiling and the equilibrium tightens: |v| about 0.08 against a 0.25 ceiling, |y − 0.5| about 0.007 against 0.03; the 3:1 correction split holds per substep, so it holds per frame), `CompoundBodyTests` (settle at 1.05 ± 0.05 moves about 3 mm tighter; the banked test steps no world), `PhysicsParityTests.restingKeepsGravityOn` (same ceilings), `PhysicsWorldSmokeTests` (every call uses dt = 1/60, so exactly two substeps). **Observed 2026-09-03:** one edit was needed after all — `onContactFiresOnAttachedPath` counted one `onContact` per update, and two substeps of sustained contact fire it twice per side; it now steps one `fixedDelta`.

- [x] `ForceGeneratorTests`: the two flagged expectations flip (10 calls; `fixedDelta`; `1.5 · 5 · fixedDelta`).
- [x] `PhysicsParityTests`: doc note only. `ParityScenario.dt` is still the per-update frame delta; each update now runs two substeps. Sampling and JSON shape are unchanged.

- [x] **File (new):** `ToyFlightSimulatorTests/Physics/FixedTimestepTests.swift`

```swift
import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Fixed timestep", .tags(.physics))
struct FixedTimestepTests {
    private final class SubstepCounter {
        var calls = 0
        var lastDelta: Float = 0
    }

    /// A body whose force hook counts substeps.
    private func makeCountingWorld() -> (world: PhysicsWorld, counter: SubstepCounter) {
        let counter = SubstepCounter()
        let probe = RigidBody(detachedAt: .zero)
        probe.shouldApplyGravity = false
        probe.forceGenerator = { _, delta, _ in
            counter.calls += 1
            counter.lastDelta = delta
        }
        let world = PhysicsWorld(entities: [probe], updateType: .HeckerVerlet)
        return (world, counter)
    }

    @Test("a 60 Hz frame runs exactly two substeps of fixedDelta")
    func sixtyHzFrames() {
        let (world, counter) = makeCountingWorld()
        for _ in 0..<10 { world.update(deltaTime: 1.0 / 60.0) }
        #expect(counter.calls == 20)
        #expect(counter.lastDelta == PhysicsWorld.fixedDelta)
    }

    @Test("1/240 s frames accumulate: a substep every second call")
    func accumulationAcrossSmallFrames() {
        let (world, counter) = makeCountingWorld()
        for _ in 0..<8 { world.update(deltaTime: 1.0 / 240.0) }
        #expect(counter.calls == 4)
    }

    @Test("a huge frame runs maxSubstepsPerUpdate and drops the rest")
    func hitchClampDropsExcessTime() {
        let (world, counter) = makeCountingWorld()
        world.update(deltaTime: 10.0)
        #expect(counter.calls == PhysicsWorld.maxSubstepsPerUpdate)
        world.update(deltaTime: 1.0 / 60.0)   // the dropped time is gone, not banked
        #expect(counter.calls == PhysicsWorld.maxSubstepsPerUpdate + 2)
    }

    /// How frame time is sliced into update calls must not change the
    /// simulation. All three slicings run the same substep sequence, so
    /// positions compare exactly, contacts and pair order included.
    @Test("frame partitioning is exact: 1×(1/30) ≡ 2×(1/60) ≡ 4×(1/120)",
          arguments: [ParityScenario.singleBounceVerlet, ParityScenario.ballCluster16])
    func partitioningInvariance(_ scenario: ParityScenario) {
        let a = scenario.build()
        let b = scenario.build()
        let c = scenario.build()
        for _ in 0..<90 {   // 3 s, compared at every 1/30 s boundary
            a.world.update(deltaTime: 1.0 / 30.0)
            for _ in 0..<2 { b.world.update(deltaTime: 1.0 / 60.0) }
            for _ in 0..<4 { c.world.update(deltaTime: 1.0 / 120.0) }
            for i in a.spheres.indices {
                #expect(a.spheres[i].getPosition() == b.spheres[i].getPosition())
                #expect(b.spheres[i].getPosition() == c.spheres[i].getPosition())
            }
        }
    }
}
```

## Step B.4 — struts, solver, raycast, suspension state, gear specs — B-suspension

The gear model both research docs converged on (combined doc §1, §4.3 B2): the aircraft stays one rigid body; each gear leg is a raycast spring-damper. A ray from a body-local attach point along body −Y finds the ground; the compression (how far the uncompressed wheel would sit below the surface) drives F = k·x + c·ẋ; the force pushes the body up along the strut. Animation keeps owning deployment (the gear meshes); physics owns support. Everything in this step is Metal-free; nothing runs in the game until B.5 wires it into `Aircraft`.

- [ ] **File (new):** `ToyFlightSimulator Shared/Physics/Vehicle/SuspensionStrut.swift` (new `Vehicle/` folder; target membership is automatic)

```swift
//
//  SuspensionStrut.swift
//  ToyFlightSimulator
//

/// One landing-gear strut: a raycast spring-damper on the aircraft body. The
/// gear is not made of bodies; Bullet's raycast vehicle, Unity's
/// WheelCollider, Jolt's VehicleConstraint, and JSBSim's FGLGear all model it
/// this way.
///
/// Units: attachLocal, restLength, maxTravel, and wheelRadius are post-import
/// body-local meters, multiplied by the body's uniformScale when world
/// quantities are computed (the LocalCollider contract). springRate, the
/// dampings, and maxSupportForce are absolute SI values sized against the
/// aircraft's mass and do not scale: scaling a model does not change its mass.
struct SuspensionStrut {
    var name: String
    /// Strut attach point on the airframe, body-local meters (Y up, +Z nose).
    var attachLocal: float3
    /// Uncompressed strut length below the attach point, meters.
    var restLength: Float
    /// Compression at which the strut bottoms out, meters.
    var maxTravel: Float
    var wheelRadius: Float
    /// N/m. Sized as static load / target static compression.
    var springRate: Float
    /// N·s/m while compressing.
    var compressionDamping: Float
    /// N·s/m while extending. Oleo struts damp rebound harder than
    /// compression; this is also what lets a bounced aircraft leave the ground
    /// cleanly instead of oscillating.
    var reboundDamping: Float
    /// Clamp on the strut force, N, and the gear-overload threshold (B.6).
    var maxSupportForce: Float

    /// Attach point to the uncompressed wheel's contact patch, along body −Y.
    var reach: Float { restLength + wheelRadius }
    /// Body origin to the uncompressed wheel's contact patch for a level
    /// aircraft (attachLocal.y is negative below the origin).
    var reachBelowOrigin: Float { reach - attachLocal.y }
}

/// Pure per-strut math, testable without bodies or a world.
enum SuspensionSolver {
    struct StrutStep {
        let compression: Float        // meters, 0...maxTravel·scale
        let compressionRate: Float    // m/s, positive while compressing
        let force: Float              // N along body up, never negative
        let bottomedOut: Bool
        let overloaded: Bool          // unclamped force ≥ maxSupportForce, or bottomed out

        static let noContact = StrutStep(compression: 0, compressionRate: 0, force: 0,
                                         bottomedOut: false, overloaded: false)
    }

    /// `distanceToGround` is the raycast distance along −up from the attach
    /// point; nil or beyond reach means the wheel is in the air.
    static func solve(strut: SuspensionStrut,
                      uniformScale: Float,
                      distanceToGround: Float?,
                      previousCompression: Float,
                      substepDelta: Float) -> StrutStep {
        let reach = strut.reach * uniformScale
        guard let distance = distanceToGround, distance <= reach else { return .noContact }

        // How far the uncompressed wheel would sit below the surface is how
        // far the strut must compress to keep it on the surface.
        let maxTravel = strut.maxTravel * uniformScale
        let rawCompression = reach - distance
        let bottomedOut = rawCompression >= maxTravel
        let compression = min(rawCompression, maxTravel)

        // Finite-difference rate. At touchdown the previous compression is 0
        // and this substep's penetration is sink·dt, so the rate is the sink
        // speed with no special case. Stays correct when Phase D rotates the
        // strut.
        let rate = (compression - previousCompression) / substepDelta
        let damping = rate >= 0 ? strut.compressionDamping : strut.reboundDamping

        // A strut pushes, never pulls. Without the floor, a fast rebound's
        // damper term exceeds the spring term and pulls the aircraft back down.
        let unclamped = strut.springRate * compression + damping * rate
        let force = max(0, min(unclamped, strut.maxSupportForce))
        let overloaded = unclamped >= strut.maxSupportForce || bottomedOut

        return StrutStep(compression: compression, compressionRate: rate, force: force,
                         bottomedOut: bottomedOut, overloaded: overloaded)
    }
}
```

- [ ] **Edit:** `Physics/Collision/NarrowPhase.swift`, with the other primitive helpers:

```swift
    /// Ray vs infinite plane: distance t ≥ 0 along `direction` (unit length)
    /// to the plane through planePoint, or nil. Front face only: the ray must
    /// approach against the normal, so an inverted aircraft's struts hit
    /// nothing.
    static func rayVsPlane(origin: float3, direction: float3,
                           planePoint: float3, planeNormal n: float3) -> Float? {
        let denominator = dot(direction, n)
        guard denominator < -1e-6 else { return nil }   // parallel, or facing away
        let t = dot(planePoint - origin, n) / denominator
        return t >= 0 ? t : nil                          // plane behind the origin
    }
```

- [ ] **Edit:** `Physics/World/PhysicsWorld.swift`, the query the suspension uses (this is why the force hook passes the world):

```swift
    /// Distance to the nearest static plane along a ray, or nil. O(planes)
    /// per call; every current scene has one.
    public func raycastStaticPlanes(from origin: float3, direction: float3) -> Float? {
        var nearest: Float? = nil
        for case let plane as PlaneRigidBody in entities where plane.isStatic {
            if let t = NarrowPhase.rayVsPlane(origin: origin, direction: direction,
                                              planePoint: plane.getPosition(),
                                              planeNormal: plane.collisionNormal),
               t < (nearest ?? .infinity) {
                nearest = t
            }
        }
        return nearest
    }
```

- [ ] **File (new):** `ToyFlightSimulator Shared/Physics/Vehicle/LandingGearSuspension.swift`

```swift
//
//  LandingGearSuspension.swift
//  ToyFlightSimulator
//

/// Gear/ground events. Fired on the UpdateThread inside the physics step;
/// handlers must be cheap and must not change physics state (the onContact
/// rule). Nobody is registered until B.6.
enum GearEvent {
    /// Weight on wheels went false → true. sinkRate is the body's downward
    /// speed at that substep, before the strut forces act on it (level-runway
    /// vertical rate).
    case touchdown(sinkRate: Float, compressions: [Float])
    /// Weight on wheels went true → false (bounce, or takeoff).
    case liftoff
    /// A strut's unclamped force crossed maxSupportForce, or it bottomed out.
    /// Fires once per exceedance, per strut.
    case gearOverload(strutName: String, force: Float, bottomedOut: Bool)
}

/// Per-aircraft suspension state. Owned by Aircraft and driven from its
/// generateForces every substep, outside the input guard, because a parked
/// aircraft must be held up. Per-instance state only; UpdateThread only.
final class LandingGearSuspension {
    let struts: [SuspensionStrut]
    /// Current compression per strut, meters; index-aligned with `struts`.
    private(set) var compressions: [Float]
    private var wasOverloaded: [Bool]
    /// True while any strut carries compression.
    private(set) var isWeightOnWheels = false
    var onGearEvent: ((GearEvent) -> Void)?

    init(struts: [SuspensionStrut]) {
        self.struts = struts
        self.compressions = Array(repeating: 0, count: struts.count)
        self.wasOverloaded = Array(repeating: false, count: struts.count)
    }

    /// One substep. `gearDeployed` is the animation gate (Aircraft.isGearDown):
    /// retracted or moving gear produces no force and holds zero compression.
    func accumulateForces(body: RigidBody,
                          gearDeployed: Bool,
                          world: PhysicsWorld,
                          substepDelta: Float) {
        guard gearDeployed else {
            resetToAirborne()
            return
        }

        let pose = body.pose()
        let up = pose.rotation.columns.1   // strut axis: rays go down −up, force pushes +up

        for (i, strut) in struts.enumerated() {
            let attachWorld = pose.position + pose.rotation * (strut.attachLocal * pose.uniformScale)
            let distance = world.raycastStaticPlanes(from: attachWorld, direction: -up)
            let step = SuspensionSolver.solve(strut: strut,
                                              uniformScale: pose.uniformScale,
                                              distanceToGround: distance,
                                              previousCompression: compressions[i],
                                              substepDelta: substepDelta)
            compressions[i] = step.compression
            body.force += up * step.force

            if step.overloaded && !wasOverloaded[i] {
                onGearEvent?(.gearOverload(strutName: strut.name,
                                           force: step.force,
                                           bottomedOut: step.bottomedOut))
            }
            wasOverloaded[i] = step.overloaded
        }

        // Weight-on-wheels transitions after all struts updated, so a
        // touchdown event carries this substep's complete compressions. The
        // force phase runs before the collision response, so body.velocity is
        // still the incoming velocity here.
        let anyContact = compressions.contains { $0 > 0 }
        if anyContact != isWeightOnWheels {
            isWeightOnWheels = anyContact
            if anyContact {
                onGearEvent?(.touchdown(sinkRate: max(0, -body.velocity.y), compressions: compressions))
            } else {
                onGearEvent?(.liftoff)
            }
        }
    }

    /// Gear retracted or in transit: no force, compressions zeroed so the
    /// next deployment's finite differences start from rest. Known quirk,
    /// accepted: deploying the gear while resting on the fuselage reads a
    /// large compression on the first substep and lifts the aircraft onto its
    /// wheels. Bounded by maxSupportForce, and an aircraft on its fuselage is
    /// already a crash.
    private func resetToAirborne() {
        for i in compressions.indices {
            compressions[i] = 0
            wasOverloaded[i] = false
        }
        if isWeightOnWheels {
            isWeightOnWheels = false
            onGearEvent?(.liftoff)
        }
    }
}
```

- [ ] **File (new):** `ToyFlightSimulator Shared/Physics/Vehicle/AircraftGearSpec.swift`

```swift
//
//  AircraftGearSpec.swift
//  ToyFlightSimulator
//

/// Landing-gear strut specs per aircraft (the AircraftColliderSpec pattern).
/// Geometry in post-import body-local meters; rates in absolute SI.
enum AircraftGearSpec {
    /// Exhaustive over AircraftType with no `default`: adding an aircraft
    /// forces an authored-or-empty decision. [] means no suspension; the
    /// aircraft rests on its collision geometry as in Phase A.
    static func spec(for type: AircraftType) -> [SuspensionStrut] {
        switch type {
            case .f22_cgtrader:
                return f22CGTrader
            case .f16, .f18, .f22, .f35:
                return []
        }
    }

    /// PLACEHOLDERS until checked against the modeled gear with the X-key
    /// overlay's strut lines (B.5); tune, then update this comment.
    /// Geometry: wheel track 3.24 m (public F-22 data about 3.25), wheelbase
    /// 6.1 m (about 6.0). All three struts share one reachBelowOrigin, 2.05 m,
    /// so a level aircraft touches all wheels together. Rate sizing is derived
    /// in the plan (Phase B, step B.4); the resulting ride height, 1.93 m at
    /// 30 t, is asserted by AircraftGearSpecTests.
    private static let f22CGTrader: [SuspensionStrut] = [
        SuspensionStrut(name: "noseGear",
                        attachLocal: [0, -0.55, 5.2],
                        restLength: 1.20, maxTravel: 0.40, wheelRadius: 0.30,
                        springRate: 268_000,
                        compressionDamping: 34_000, reboundDamping: 51_000,
                        maxSupportForce: 100_000),
        SuspensionStrut(name: "mainGearLeft",
                        attachLocal: [-1.62, -0.55, -0.9],
                        restLength: 1.05, maxTravel: 0.45, wheelRadius: 0.45,
                        springRate: 1_100_000,
                        compressionDamping: 146_000, reboundDamping: 219_000,
                        maxSupportForce: 400_000),
        SuspensionStrut(name: "mainGearRight",
                        attachLocal: [1.62, -0.55, -0.9],
                        restLength: 1.05, maxTravel: 0.45, wheelRadius: 0.45,
                        springRate: 1_100_000,
                        compressionDamping: 146_000, reboundDamping: 219_000,
                        maxSupportForce: 400_000)
    ]

    /// Static stance for a level aircraft with equal-reach struts: every strut
    /// shares one compression x = m·g / Σk, and ride height = reach − x. nil
    /// for an empty spec.
    static func staticStance(struts: [SuspensionStrut], mass: Float, gravity: Float = 9.81)
        -> (compression: Float, rideHeight: Float)? {
        guard let first = struts.first else { return nil }
        let totalRate = struts.reduce(0) { $0 + $1.springRate }
        guard totalRate > 0 else { return nil }
        let x = mass * gravity / totalRate
        return (x, first.reachBelowOrigin - x)
    }
}
```

### Rate sizing (F-22 at 30 t, the in-game `F22SimpleFlightModel.mass`)

- Weight W = 30 000 · 9.81 ≈ 294 kN.
- Spring rates: mains 1.1 MN/m each, nose 268 kN/m; Σk = 2.468 MN/m.
- Static compression x = W / Σk ≈ 0.119 m; ride height = 2.05 − 0.119 ≈ 1.93 m. Close to the old 2 m sphere's stance, which was approximating the gear all along.
- Load split follows the rates: about 89 % mains, 11 % nose.
- Damping c = 2ζ√(k·m_share): mains ≈ 146 kN·s/m (ζ ≈ 0.6), nose ≈ 34 kN·s/m (ζ ≈ 0.5); rebound = 1.5 × compression.
- maxSupportForce ≈ 3 × static load per strut. A 3 m/s sink trips it on damping alone (146 · 3 ≈ 438 kN > 400 kN), which matches the real hard-landing boundary of about 10 ft/s.
- Stability at 1/120 s: ω = √(Σk/m) ≈ 9.1 rad/s (period 0.69 s ≈ 83 substeps); damping per substep (Σc/m)·dt ≈ 0.09, far below the explicit-integration limit. This is why B.3 precedes B.4.

### Details that are easy to get wrong

- The finite-difference damper needs no touchdown special case: previous compression 0, penetration this substep = sink·dt, so rate = sink.
- The push-only floor is required, not cosmetic: on a fast rebound the damper term is negative and larger than the spring term.
- `overloaded` uses the unclamped force; the clamp is what makes the event meaningful.
- Per-strut overload events fire inside the loop; the weight-on-wheels transition fires after it, so a touchdown event always reports its own substep's complete compressions. `compressions` is a value type, so the copy in the event cannot change later.

### Tests for this step (Metal-free, `.tags(.physics)`)

- [ ] `SuspensionSolverTests` (new, pure): nil distance and out-of-reach distance give `.noContact`; static compression gives k·x at zero rate; compressing uses the compression damping, extending the rebound damping; fast rebound gives force exactly 0, never negative; `maxSupportForce` clamps and `overloaded` comes from the unclamped value; bottom-out caps compression at `maxTravel` and sets the flag; `uniformScale` doubles reach and travel and leaves rates alone; touchdown rate recovery (previous 0, penetration v·dt gives rate v).
- [ ] `NarrowPhaseTests` additions: `rayVsPlane` for translated and tilted planes with hand-computed t; parallel gives nil; back-face approach gives nil; plane behind the origin gives nil.
- [ ] `AircraftGearSpecTests` (new): `.f22_cgtrader` returns `noseGear`, `mainGearLeft`, `mainGearRight` with unique names and finite positive dimensions; other types return `[]`; all three `reachBelowOrigin` equal 2.05 m; `staticStance` at mass 30 000 gives compression ≈ 0.119 m and ride height ≈ 1.93 m.

## Step B.5 — aircraft, scene, and overlay wiring — completes B-suspension

- [ ] **Edit:** `GameObjects/Aircraft.swift`. The property, next to `animator`:

```swift
    /// Raycast landing-gear suspension; nil for aircraft without a gear spec
    /// (they rest on their collision geometry, as in Phase A). Installed by
    /// the scene next to the rigid body.
    var gearSuspension: LandingGearSuspension?
```

and the call in `generateForces` at B.2's marked point:

```diff
-        // B.5 adds the landing-gear suspension here, outside the input guard:
-        // a parked, unfocused aircraft must still be held up.
+        // Outside the input guard: a parked, unfocused aircraft must still be
+        // held up. isGearDown is animator state written only in doUpdate, so
+        // it is stable across a frame's substeps.
+        gearSuspension?.accumulateForces(body: rigidBody,
+                                         gearDeployed: isGearDown,
+                                         world: world,
+                                         substepDelta: substepDelta)
```

- [ ] **Edit:** `Scenes/FlightboxWithPhysics.swift`, in `applyAircraftSwap` after the collider spec:

```diff
             acRigidBody.restitution = 0.2
+
+            // Gear suspension: authored struts or nothing. The old aircraft's
+            // suspension goes away with the old aircraft.
+            let gearStruts = AircraftGearSpec.spec(for: aircraft)
+            playerAircraft.gearSuspension = gearStruts.isEmpty ? nil : LandingGearSuspension(struts: gearStruts)
```

- [ ] **Edit:** `Physics/Debug/ColliderDebugOverlay.swift`. The overlay takes the aircraft type and looks up both specs itself; the two private helpers take the specs as data.

```diff
-    func cycle(on target: GameObject, spec: [LocalCollider]) {
+    func cycle(on target: GameObject, type: AircraftType) {
         assert(mode == .off || host === target,
                "[ColliderDebugOverlay] host changed without hostWasReplaced - swap wiring is missing")
-        apply(mode.next, on: target, spec: spec)
+        apply(mode.next, on: target, type: type)
     }

-    func hostWasReplaced(by newTarget: GameObject?, spec: [LocalCollider]) {
+    func hostWasReplaced(by newTarget: GameObject?, type: AircraftType) {
         let previousMode = mode
         reset()
         if previousMode != .off, let newTarget {
-            apply(previousMode, on: newTarget, spec: spec)
+            apply(previousMode, on: newTarget, type: type)
         }
     }

-    private func apply(_ newMode: Mode, on target: GameObject, spec: [LocalCollider]) {
+    private func apply(_ newMode: Mode, on target: GameObject, type: AircraftType) {
         ...
         if mode == .off {   // entering: build, attach, register, log
             host = target
-            buildVolumes(on: target, spec: spec)
-            logWorldDimensions(spec, on: target)
+            let spec = AircraftColliderSpec.spec(for: type)
+            let gearSpec = AircraftGearSpec.spec(for: type)
+            buildVolumes(on: target, spec: spec, gearSpec: gearSpec)
+            logWorldDimensions(spec, gearSpec: gearSpec, on: target)
         }
```

Call sites:

```diff
 // Scenes/GameScene.swift, the X handler
-            colliderOverlay.cycle(on: aircraft, spec: AircraftColliderSpec.spec(for: type))
+            colliderOverlay.cycle(on: aircraft, type: type)

 // Scenes/FlightboxWithPhysics.swift, end of applyAircraftSwap
-            colliderOverlay.hostWasReplaced(by: playerAircraft, spec: AircraftColliderSpec.spec(for: aircraft))
+            colliderOverlay.hostWasReplaced(by: playerAircraft, type: aircraft)
```

The pure half gets the endpoint helper (tested in `ColliderOverlayMappingTests`):

```swift
    /// Strut overlay line in the aircraft's local space (the Line is a child,
    /// so the parent's scale composes): attach point to the uncompressed
    /// wheel's contact patch along body −Y. With the gear down, the lower end
    /// should sit at the modeled wheel's contact patch.
    static func strutLineEndpoints(for strut: SuspensionStrut) -> (start: float3, end: float3) {
        (strut.attachLocal, strut.attachLocal - float3(0, strut.reach, 0))
    }
```

`buildVolumes` gains a strut loop after the collider loop, plus `static let strutColor: float4 = [0, 1, 1, 1]` next to the other colors (opaque cyan; `Line` renders through the `.lines` collection, so the alpha rule for volumes does not apply):

```swift
        // Cyan strut lines. Line is a GameObject in the .lines collection, so
        // attach, register, and removeFromScene work as for the volumes. Line
        // builds its vertex buffer at init, on the update thread, like the
        // capsule mesh above.
        for strut in gearSpec {
            let (start, end) = ColliderOverlayMapping.strutLineEndpoints(for: strut)
            attach(Line(startPoint: start, endPoint: end, color: Self.strutColor), to: target)
        }
```

`logWorldDimensions` gains the stance lines (the number the in-app settle must reproduce):

```swift
        if !gearSpec.isEmpty, let mass = target.rigidBody?.mass,
           let stance = AircraftGearSpec.staticStance(struts: gearSpec, mass: mass) {
            for strut in gearSpec {
                print("  \(strut.name): attach \(strut.attachLocal), reach below origin \(String(format: "%.2f m", strut.reachBelowOrigin))")
            }
            print("  gear stance: static compression \(String(format: "%.3f m", stance.compression)), "
                  + "ride height ≈ \(String(format: "%.2f m", stance.rideHeight))")
        }
```

### Expected behavior (check in-app; write into the commit message)

- **The jet stands on its wheels** at about 1.93 m (2.05 m reach minus 0.119 m static compression), between the belly rest (1.05) and the old sphere's 2.0. The fuselage capsule's lowest point sits about 0.88 m clear of the runway, so ground operations produce no airframe contacts: the A.7 contact log goes quiet with the gear down, which is the expected result.
- **The gear toggle now affects physics.** Gear up on the ground: the struts stop producing force, the jet drops about 0.88 m onto its fuselage, and the fuselage contact line returns. Gear down while on the fuselage: the jet rises onto its wheels (bounded by `maxSupportForce`; the quirk documented on `resetToAirborne`).
- **Wheels visually sink about 12 cm** (the static compression); the rendered gear is rigid. Two options at tuning time: accept it, or author `restLength` shorter by the static compression so the rendered wheels touch the ground at rest (touchdown then happens with the wheels visually buried for an instant). Compression-driven gear visuals are a Phase D item.
- **The jet slides on the ground.** No tangent friction, brakes, or steering until Phase D; only aero drag resists drift. Same as the Phase A sphere, but visible now that the jet sits still.

- [ ] **File (new):** `ToyFlightSimulatorTests/Physics/GearSuspensionWorldTests.swift`, the B-phase counterpart of `CompoundBodyTests`: the real suspension, compound colliders, and corrected response end to end, Metal-free.

```swift
import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Gear suspension (world)", .tags(.physics))
struct GearSuspensionWorldTests {
    private static let dt: Float = 1.0 / 60.0

    /// Metal-free stand-in for Aircraft: drives the real LandingGearSuspension
    /// from the body's force hook. A detached body's pose has the identity
    /// rotation, i.e. a level aircraft. Node rotation and the animator gate
    /// are B.5's in-app checks.
    private final class GearRig {
        let body: RigidBody
        let suspension: LandingGearSuspension
        var gearDeployed = true

        init(body: RigidBody, struts: [SuspensionStrut]) {
            self.body = body
            self.suspension = LandingGearSuspension(struts: struts)
            body.forceGenerator = { [weak self] body, substepDelta, world in
                guard let self else { return }
                self.suspension.accumulateForces(body: body,
                                                 gearDeployed: self.gearDeployed,
                                                 world: world,
                                                 substepDelta: substepDelta)
            }
        }
    }

    private func makeF22OnGear(startY: Float, velocityY: Float = 0)
        -> (world: PhysicsWorld, body: RigidBody, rig: GearRig) {
        let body = RigidBody(detachedAt: [0, startY, 0])
        body.mass = 30_000                                    // the flight model's mass
        body.restitution = 0.2
        body.velocity = [0, velocityY, 0]
        body.colliders = AircraftColliderSpec.spec(for: .f22_cgtrader)
        let rig = GearRig(body: body, struts: AircraftGearSpec.spec(for: .f22_cgtrader))
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true
        let world = PhysicsWorld(entities: [body, plane], updateType: .HeckerVerlet)
        world.useBroadPhase = false
        return (world, body, rig)
    }

    @Test("the F-22 settles on its struts at ride height, gravity on, fuselage clear")
    func settlesOnStruts() {
        let (world, body, rig) = makeF22OnGear(startY: 2.5)
        var airframeTouched = false
        body.onContact = { _, _ in airframeTouched = true }

        for _ in 0..<600 { world.update(deltaTime: Self.dt) }   // 10 s

        #expect(body.shouldApplyGravity)
        #expect(rig.suspension.isWeightOnWheels)
        #expect(abs(body.getPosition().y - 1.93) <= 0.02,
                "Σk·x = W gives x ≈ 0.119, ride height = 2.05 − x ≈ 1.93")
        #expect(abs(rig.suspension.compressions[0] - 0.119) <= 0.01,
                "equal-reach struts share the static compression")
        #expect(simd_length(body.velocity) <= 0.05)
        #expect(!airframeTouched,
                "on its wheels the fuselage capsule (bottom −1.05) stays about 0.88 m clear")
    }

    @Test("gear up: the same body falls through the struts to the Phase A belly rest")
    func gearUpFallsToBelly() {
        let (world, body, rig) = makeF22OnGear(startY: 2.5)
        rig.gearDeployed = false
        var contactNames: Set<String> = []
        body.onContact = { contact, _ in
            if let name = contact.colliderNameA { contactNames.insert(name) }
        }

        for _ in 0..<600 { world.update(deltaTime: Self.dt) }

        #expect(abs(body.getPosition().y - 1.05) <= 0.05,
                "CompoundBodyTests' settle, with the suspension present but retracted")
        #expect(contactNames == ["fuselage"])
        #expect(!rig.suspension.isWeightOnWheels)
    }

    @Test("touchdown reports the incoming sink; a firm arrival overloads, a gentle one does not")
    func touchdownAndOverloadEvents() {
        // 4 m/s sink: the mains' damper alone gives 146 kN·s/m · 4 ≈ 584 kN,
        // past the 400 kN clamp, so the overload event fires on the rising edge.
        let firm = makeF22OnGear(startY: 2.2, velocityY: -4)
        var firstSink: Float? = nil
        var overloadedStruts: Set<String> = []
        firm.rig.suspension.onGearEvent = { event in
            switch event {
                case .touchdown(let sinkRate, _):
                    if firstSink == nil { firstSink = sinkRate }
                case .gearOverload(let strutName, _, _):
                    overloadedStruts.insert(strutName)
                case .liftoff:
                    break
            }
        }
        for _ in 0..<300 { firm.world.update(deltaTime: Self.dt) }
        #expect(firstSink != nil && abs(firstSink! - 4.0) <= 0.4)
        #expect(overloadedStruts.contains("mainGearLeft") && overloadedStruts.contains("mainGearRight"))

        // 0.5 m/s: damper about 73 kN and the spring peaks well under the clamp.
        let gentle = makeF22OnGear(startY: 2.2, velocityY: -0.5)
        var gentleOverloads = 0
        gentle.rig.suspension.onGearEvent = { if case .gearOverload = $0 { gentleOverloads += 1 } }
        for _ in 0..<300 { gentle.world.update(deltaTime: Self.dt) }
        #expect(gentleOverloads == 0)
        #expect(gentle.rig.suspension.isWeightOnWheels)
    }

    @Test("a body pushed upward leaves cleanly: struts push, never pull")
    func strutsNeverPull() {
        let (world, body, rig) = makeF22OnGear(startY: 2.5)
        for _ in 0..<600 { world.update(deltaTime: Self.dt) }   // settle first
        var sawLiftoff = false
        rig.suspension.onGearEvent = { if case .liftoff = $0 { sawLiftoff = true } }

        body.velocity = [0, 4, 0]
        var maxY: Float = 0
        for _ in 0..<240 {
            world.update(deltaTime: Self.dt)
            maxY = max(maxY, body.getPosition().y)
        }

        #expect(sawLiftoff)
        // Ballistic apex from 4 m/s is about 0.82 m above launch; rebound
        // damping acts only across the first ~0.12 m of strut extension. A
        // strut that pulled would remove most of the apex.
        #expect(maxY - 1.93 >= 0.5)
    }
}
```

The settle test's initial drop arrives at about 3 m/s and fires an overload during settling; that is deliberately not asserted there. `touchdownAndOverloadEvents` owns the event expectations.

- [ ] `ColliderOverlayMappingTests` addition: `strutLineEndpoints` (start = attach, end = attach − [0, reach, 0]).
- [ ] `PhysicsParityTests`: untouched goldens stay green (no harness world has struts).

## Step B.6 — touchdown and crash classification — B-classification

Research §4.3 B3: gear support comes from strut compressions (no contact events involved); airframe contacts are classified scrape or impact by approach speed; the overload event is the hook crash scoring wants. Observers only: a pure classifier, one print-only reporter, and the wiring. No physics change; goldens untouched.

**Pre-impact velocity.** `onContact` fires after the response for that pair, so the body's velocity at event time is the post-impulse bounce, not the hit. The world records every body's velocity at the top of each step, before any response; classification reads that.

- [ ] **Edit:** `Physics/World/RigidBody.swift`, next to `forceGenerator`:

```swift
    /// Velocity at the top of the current step, before this step's contact
    /// impulses. Written by PhysicsWorld. onContact handlers run after the
    /// response, when `velocity` is already the post-impact value, so impact
    /// classification reads this instead.
    var stepStartVelocity: float3 = .zero
```

- [ ] **Edit:** `Physics/World/PhysicsWorld.swift`, the start-of-step loop in `step`:

```diff
         for entity in entities {
             entity.resetCollisions()
             entity.invalidateWorldColliders()
+            entity.stepStartVelocity = entity.velocity
             entity.forceGenerator?(entity, deltaTime, self)
         }
```

With the Euler solver the response sees one gravity kick more than this value (about 0.08 m/s at 120 Hz); irrelevant against a 2 m/s threshold.

- [ ] **File (new):** `ToyFlightSimulator Shared/Physics/Vehicle/AirframeContactClassifier.swift`

```swift
//
//  AirframeContactClassifier.swift
//  ToyFlightSimulator
//

/// Crash-vs-landing vocabulary for airframe ground contacts. Pure.
enum AirframeContactClass {
    /// Gentle airframe contact: a skid, a tail scrape, a soft belly slide.
    case scrape
    /// Hard airframe contact: a crash in gameplay terms.
    case impact
}

enum AirframeContactClassifier {
    /// Normal-speed boundary between scrape and impact. 2 m/s sits between
    /// gentle contact (under 1 m/s) and a hard landing (about 3 m/s sink, on
    /// the gear). Strictly greater; tunable.
    static let impactSpeedThreshold: Float = 2.0

    /// Approach speed along the contact normal. `contactNormal` is the
    /// Contact's B→A normal with the aircraft as A, so approach is −dot(v, n);
    /// a separating velocity clamps to 0.
    static func normalSpeed(contactNormal: float3, preImpactVelocity: float3) -> Float {
        max(0, -dot(preImpactVelocity, contactNormal))
    }

    static func classification(forNormalSpeed speed: Float) -> AirframeContactClass {
        speed > impactSpeedThreshold ? .impact : .scrape
    }
}
```

- [ ] **File (new):** `ToyFlightSimulator Shared/Physics/Debug/TouchdownReporter.swift`; **delete** `ContactDebugLogger.swift` (nothing uses it once the wiring below lands).

```swift
//
//  TouchdownReporter.swift
//  ToyFlightSimulator
//

import Foundation

/// Print-only flight-test telemetry: gear events as they come, airframe
/// contacts classified. Runs inside the physics step's callbacks on the
/// UpdateThread, so it must stay print-only.
final class TouchdownReporter {
    private let bodyLabel: String
    private let scrapeLogInterval: Double
    private var lastScrapeLog: [String: Double] = [:]

    init(bodyLabel: String, scrapeLogInterval: Double = 1.0) {
        self.bodyLabel = bodyLabel
        self.scrapeLogInterval = scrapeLogInterval
    }

    func report(_ event: GearEvent) {
        switch event {
            case .touchdown(let sinkRate, let compressions):
                let comps = compressions.map { String(format: "%.3f", $0) }.joined(separator: ", ")
                print("[Touchdown] \(bodyLabel) sink \(String(format: "%.2f", sinkRate)) m/s, compressions [\(comps)] m")
            case .liftoff:
                print("[Liftoff] \(bodyLabel)")
            case .gearOverload(let strutName, let force, let bottomedOut):
                print("[GearOverload] \(bodyLabel).\(strutName) at \(String(format: "%.0f", force)) N"
                      + (bottomedOut ? ", bottomed out" : ""))
        }
    }

    /// Scrapes are throttled per collider name (a sliding fuselage re-contacts
    /// every step); impacts always print.
    func reportAirframeContact(_ contact: Contact,
                               preImpactVelocity: float3,
                               isGearDown: Bool,
                               against other: RigidBody) {
        let speed = AirframeContactClassifier.normalSpeed(contactNormal: contact.normal,
                                                          preImpactVelocity: preImpactVelocity)
        let classification = AirframeContactClassifier.classification(forNormalSpeed: speed)
        let name = contact.colliderNameA ?? "body"

        if classification == .scrape {
            let now = GameTime.TotalGameTime
            if let last = lastScrapeLog[name], now - last < scrapeLogInterval { return }
            lastScrapeLog[name] = now
        }

        let otherLabel = other.gameObject?.getName() ?? "static geometry"
        let label = classification == .impact ? "CRASH" : "Scrape"
        print("[\(label)] \(bodyLabel).\(name) hit \(otherLabel) at "
              + String(format: "%.2f m/s", speed)
              + " (gear \(isGearDown ? "down" : "up"))")
    }
}
```

- [ ] **Edit:** `Scenes/FlightboxWithPhysics.swift`; replaces the `ContactDebugLogger` block in `applyAircraftSwap`. The closures capture the reporter strongly (nothing else owns it) and the aircraft weakly: a strong aircraft capture would cycle aircraft → rigidBody → onContact → aircraft.

```diff
-            // Debug scaffolding (A.7 exit criterion): named contact reporting,
-            // throttled so a resting aircraft doesn't spam 60 lines/s.
-            let contactLogger = ContactDebugLogger(bodyLabel: playerAircraft.getName())
-            acRigidBody.onContact = { contact, other in
-                contactLogger.log(contact, against: other)
-            }
+            // Flight-test telemetry: gear events and classified airframe
+            // contacts. Weak aircraft capture: the aircraft owns the body that
+            // owns this closure.
+            let reporter = TouchdownReporter(bodyLabel: playerAircraft.getName())
+            playerAircraft.gearSuspension?.onGearEvent = { event in
+                reporter.report(event)
+            }
+            acRigidBody.onContact = { [weak playerAircraft] contact, other in
+                guard let playerAircraft, let body = playerAircraft.rigidBody else { return }
+                reporter.reportAirframeContact(contact,
+                                               preImpactVelocity: body.stepStartVelocity,
+                                               isGearDown: playerAircraft.isGearDown,
+                                               against: other)
+            }
```

Spec-less aircraft get the same wiring: `gearSuspension` is nil, so only the contact leg is live, and their sphere bodies report `body` as the collider name, as before.

- [ ] **File (new):** `ToyFlightSimulatorTests/Physics/AirframeContactClassifierTests.swift`

```swift
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Airframe contact classification", .tags(.physics))
struct AirframeContactClassifierTests {
    private func classify(normal: float3, velocity: float3) -> (AirframeContactClass, Float) {
        let speed = AirframeContactClassifier.normalSpeed(contactNormal: normal, preImpactVelocity: velocity)
        return (AirframeContactClassifier.classification(forNormalSpeed: speed), speed)
    }

    @Test("normal speed is the pre-impact approach along the contact normal")
    func normalSpeedMath() {
        // Descending onto level ground: n = up (B→A with the aircraft as A).
        let (cls, speed) = classify(normal: [0, 1, 0], velocity: [30, -5, 0])
        #expect(approxEqual(speed, 5))
        #expect(cls == .impact)
    }

    @Test("fast tangential motion with a gentle sink is a scrape")
    func tangentialIsGentle() {
        let (cls, speed) = classify(normal: [0, 1, 0], velocity: [80, -0.5, 0])
        #expect(cls == .scrape)
        #expect(approxEqual(speed, 0.5))
    }

    @Test("a separating velocity clamps to zero speed: scrape")
    func separatingClampsToZero() {
        let (cls, speed) = classify(normal: [0, 1, 0], velocity: [0, 3, 0])
        #expect(speed == 0)
        #expect(cls == .scrape)
    }

    @Test("exactly the threshold speed is still a scrape")
    func thresholdBoundary() {
        let (cls, _) = classify(normal: [0, 1, 0],
                                velocity: [0, -AirframeContactClassifier.impactSpeedThreshold, 0])
        #expect(cls == .scrape)
    }
}
```

- [ ] **Addition to `GearSuspensionWorldTests`**, the end-to-end check that classification sees the arrival, not the bounce:

```swift
    @Test("a gear-up belly arrival classifies as a fuselage CRASH from pre-impact velocity")
    func bellyImpactClassifiesAsCrash() {
        let (world, body, rig) = makeF22OnGear(startY: 2.0, velocityY: -5)
        rig.gearDeployed = false
        var classified: [(name: String, cls: AirframeContactClass, speed: Float)] = []
        body.onContact = { [unowned body] contact, _ in
            let speed = AirframeContactClassifier.normalSpeed(contactNormal: contact.normal,
                                                              preImpactVelocity: body.stepStartVelocity)
            classified.append((contact.colliderNameA ?? "?",
                               AirframeContactClassifier.classification(forNormalSpeed: speed),
                               speed))
        }
        for _ in 0..<120 { world.update(deltaTime: Self.dt) }
        let firstImpact = classified.first { $0.cls == .impact }
        #expect(firstImpact?.name == "fuselage")
        #expect((firstImpact?.speed ?? 0) > 4.5,
                "classification must see the ≈5 m/s arrival, not the post-impulse bounce")
    }
```

## Phase B non-goals (deferred, with their homes)

- Torque from asymmetric gear contact (one wheel first, nose settling after the mains): Phase D, when forces at a point produce torque and the strut load split becomes geometric.
- Ground friction, brakes, and nosewheel steering: Phase D tangent friction; brakes ride on it.
- Compression-driven gear visuals (wheels sink about 12 cm at rest): Phase D-era visual polish; tuning options in B.5.
- Live strut-compression overlay: rest-pose lines are enough for geometry tuning.
- Sleeping: unchanged from Phase A's non-goals; the trigger is a target scene missing its frame budget after B.3's substep doubling, decided from measurements.
- Mid-transit gear collision (combined doc D8).
- Tilted-runway generalizations of the sink rate and the strut force direction: one-liners, noted at the code sites.
- Force hooks on non-aircraft bodies (balls need none); weight-on-wheels UI or scoring beyond prints; CCD, box-box, exact capsule-box; iOS overlay and menu parity.

## Phase B exit criteria

1. - [ ] **B-generators changes nothing measurable**: full serial suite green against unchanged goldens; the regeneration dry run byte-identical; in-app flight feel unchanged; an F-22 → F-16 → F-22 swap shows no double thrust and the old aircraft still deallocates.
2. - [ ] **Physics is refresh-rate independent**: `FixedTimestepTests` green with the partition case on exact equality; goldens regenerated, reviewed against the B.3 table, and committed; every semantic suite green without edits; in-app, ball scenes settle the same at 30, 60, and 120 Hz and `FlightboxWithPhysics` plays normally; stress-scene cost recorded before and after (about 2× per update call at 60 Hz is the substep count, not a regression).
3. - [ ] **The jet stands on its wheels**: `GearSuspensionWorldTests` green (settle at about 1.93 m with gravity on, weight on wheels, zero airframe contacts; gear up reproduces the 1.05 belly rest with a `fuselage` contact); in-app, the F-22 settles at the logged stance height, the gear toggle drops and raises it, and the cyan strut lines match the modeled gear (spec numbers tuned and the PLACEHOLDER comment updated, as for Phase 0 criterion 2).
4. - [ ] **Touchdown is reported**: in-app, a landing prints `[Touchdown]` with a plausible sink rate and compressions; a firm arrival prints `[GearOverload]`; a gear-up belly touch prints `[CRASH] …fuselage`, a gentle one `[Scrape]`, both from pre-impact velocity. `AirframeContactClassifierTests` and the belly-crash world test green.
5. - [ ] **No process-wide state**: parity determinism and partition tests green under Swift Testing's in-process concurrency; accumulator, hooks, and suspension state are per instance; review confirms no new static mutable state in the step path.
6. - [ ] **CI green** on all four commits (serial app-hosted run, as configured).

**Implementation order:** Phase A cleanup (C1–C10, one or two plumbing commits) → B.1–B.2 as one commit (B-generators, criterion 1) → B.3 (B-timestep, criterion 2) → B.4–B.5 as one commit (B-suspension, criterion 3) → B.6 (B-classification, criterion 4). Tests land inside their commits. The order matters twice: the force hook must exist before the accumulator moves its call into the substep loop, and the fixed step must precede the suspension, whose rates are sized against dt = 1/120.
