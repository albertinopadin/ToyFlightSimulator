# Compound Rigid Bodies — Implementation Plan (simplified), continuation: Phases C and D

**Started:** 2026-09-06 · **Planned against:** the tree at `82f852b` (Phase B closed; CI green on the push head)
**Parent plan:** `plans/claude/compound_rigid_bodies_implementation_plan_simplified.md` holds Phases 0, A, and B, the rules every phase follows, the verification commands, and the golden regeneration procedure. This document continues it; nothing here restates a landed step.
**Design source:** `research/claude/compound_rigid_bodies_research_combined.md` §4.4 (Phase C), §4.5 (Phase D), §4.6 (the Jolt gate), and §3.1 (inertia tensors); `research/claude/compound_rigid_bodies_research_2026-07-14.md` §2.5–§2.6 for the code sketches.

## How this document works

Same as the parent: steps are edited in place to match the code, history goes in the Changelog one line per entry, checkboxes are ticked as steps land, and the code listings are the contract for hand transcription (their comments are the comments to ship). Line numbers are as of `82f852b`; each step says what earlier steps shift.

## Changelog

- **2026-09-06** — Phases C and D planned against `82f852b`. Phase C is two commits (narrow phase, then structures). Phase D is three (angular plumbing, tires and brakes, the aircraft rotates) plus a gated list (D.4) that is not planned in code. Neither phase regenerates a golden: every commit's gate is the byte-identical dry run.
- **2026-09-08** — Revised after Codex's review of this document; every quantitative claim was reproduced before adoption, and no code has landed yet. Phase C: capsule-box becomes exact (a slab test, both end caps, the twelve box edges — the three sphere probes missed about one true hit in ten in a random sweep of overlapping pairs); the box-box contact point moves from the incident face's center to the overlap centroid (for C.2's own wing-over-wall case the face center was 8.5 m from the wing and on the wrong side of the origin, which flips D.3's yaw); the one-body-per-part rationale is corrected (the broad phase does test every dynamic body against every static one). Phase D: the §4.6 Jolt gate is recorded as held (native); angular velocity integrates with the forces and orientation with the positions; `rotate(by:)` composes through a normalised quaternion, with a 72 000-substep soak; D.1 keeps the deepest-contact impulse behind a linear fast path, and the per-pair manifold solve (accumulated impulses, eight iterations, gated to pairs with more than one contact) lands in D.3 — one pass left a two-cap belly rest rocking at 0.029 rad/s against the test's own 0.02 band, and a second pass on a single contact is not byte-identical in float32, so the gate is what keeps the goldens fixed; tires become holding friction with the strut load applied along the ground normal (the regularised form crept at 0.2 m/s from the −0.45° stance and under any thrust with the brakes on); crash classification reads the relative velocity at the contact point; `applyPlayerSideMove` is gated to the kinematic path; a nil flight model restores infinite inertia; the gear-visual note's sign is corrected (lengthen `restLength`, not shorten; the parent plan's B.5 note is corrected too). Test counts and the CLAUDE.md wording follow.
- **2026-09-08, second review** — Codex reviewed the revision above; its four corrections and three wording fixes are adopted, each reproduced first. Phase C: the capsule-box inside branch becomes an exact separating-axis test over a segment's twelve candidate directions — the midpoint probe reported the probe sphere's depth, not the capsule's (a core through a unit box answered +x at 1.5 where 3.5 separates along x and 1.5 across the core does); the plan's own crossing case moves from `[1, 0, 0]` at 0.75 to `[0.894, −0.447, 0]` at 0.947 and the end-inside case from 0.75 to 1.0, and the tests gain a translation check. The box-box point becomes the centroid of the incident face clipped to the reference face, Box2D's construction reduced to one point: the projected-overlap midpoint sat 0.46 m outside a unit cube at 45° shifted 0.5 m along the face, and 5.3 m from the tip of a wing yawed 20° into a wall, on the wing's centerline — a yaw lever arm of zero; the D.4 clipping row is gone. Phase D: angular velocity integrates before the contact response in the Verlet path too (`PhysicsWorld.step`), orientation after; the tires are solved together as sequential impulses over the wheels against one predicted velocity, linear and angular — the fixed per-wheel share left the unbraked nose wheel's unmet demand to nobody once its rolling-resistance limit bound, so 89.8 kN opposed 100 kN of thrust with the brakes on and the jet crept 1.6 cm in 5 s against the test's own 1 cm, under either solver; the joint solve opposes all 100 and moves nothing — with the strut loads applied in the first pass so their torque is in the prediction, and `effectiveMass(atWorldPoint:along:)` leaves D.1 with nothing to call it. Wording: one body per part costs its AABB tests, not nothing (`StaticStructure`'s doc comment); "no dynamic box" becomes "no aircraft box rests flat on a face"; impact deduplication is described as what it is, once per frame per other body, with the reason a substep counter is not worth its plumbing.
- **2026-09-08, third review** — Codex found two test expectations and one sentence to fix; all three reproduced. D.3's rig gives the brake-hold test a tensor, and the 100 kN step then pitches the nose from −0.48° to −1.80° and swings the origin 4.4 cm forward in about a second before it holds (a planar replay of the struts, the controller, and the joint tire solve: 0.2 mm of drift over the next 4 s), so D.2 keeps its strict bound for a body that cannot pitch and D.3 allows the transient, then asserts the hold. Case 3c's cube at exactly 45° tied its two lower faces to one ulp, and the two faces clip to different points; it is a 40° cube now. The dedupe comment calls once-per-frame a policy, not an impossibility.
- **2026-09-09** — C.1's listings renamed for explicit identifiers ahead of transcription; no behavior change. In `capsuleVsBox` the capsule's world-space core ends and radius are `capsuleCoreStart`/`capsuleCoreEnd`/`capsuleRadius`, their box-local images `localCapsuleCoreStart`/`localCapsuleCoreEnd`, and the start-to-end vector `localCapsuleCoreDelta` — "core" stays in the names because the capsule's surface reaches a radius beyond each end, which is the distinction the inside and outside branches turn on; the signed candidate normal in `considerAxis` is `signedAxis`, the nearer end's projection in the depth formula gets its own line as `nearerEndProjection`, and the edge loop's closest point is `onCapsuleCore`. `segmentSpanInsideBox` stays generic: `segmentStart`/`segmentEnd`, `segmentDelta` (unnormalised, so `enter`/`exit` are fractions along the segment, which the contact point's reconstruction from the world-space ends relies on), `inverseDelta`, and `slabEnter`/`slabExit` for one axis's two crossings. `boxVsBox`'s center-to-center vector is `centerOffset`. The single letter `d` had meant three different things across the three functions.
- **2026-09-09, tolerances** — C.1's six threshold literals become named `static let`s on `NarrowPhase` (`grazingRayCosine`, `parallelAxisSineSquared`, `perpendicularAxisCosine`, `coreAcrossNormalCosine`, `parallelSlabExtent`), each documented with what it compares and its unit; `rayVsPlane` gains an edit for its guard, value unchanged. One behavior change, reproduced first: `capsuleVsBox` normalises the core direction once, so its cross-product guard is the same squared sine as `overlaps` and the contact-point rule compares a cosine — the absolute 1e-6 m band it replaces was within 5% of the float32 rounding at the F-22's 16.2 m core (0.95e-6 m over 300 000 random pose-axis samples; 0.06e-6 at 1 m, 0.24e-6 at 5 m), and a core a metre longer would have reported a span end instead of the midpoint for a crossing on some frames. The five capsule-box cases are unaffected: their inside-branch cosines are zero up to rounding or far outside any band, and the depths do not involve the direction.
- **2026-09-09, point names** — `capsuleVsBox`'s contact-point fraction `t` is `contactPointParameter` (0 at `capsuleCoreStart`, 1 at `capsuleCoreEnd`), and the edge loop's half-edge vector `along` is `halfEdge`; the projection `along` had already become `coreAlongNormal` with the tolerances. `overlaps(along:)` keeps its argument label; `clippedPoint`'s side-axis loop index `t` is `sideAxis`.
- **2026-09-10** — C-narrowphase landed (C.1, `c6b4fba`): box-box and exact capsule-box per the listings. Found at review, before the tests ran: the edge-edge loop had been transcribed as `cross(a.rotation[i], b.rotation[i])`, so six of the nine edge axes were never tested (test 4 fails on it); fixed to `b.rotation[j]`. `boxVsBox` shipped without its listed comments; added. All fourteen listed cases green with the listed numbers, each reproduced first in a standalone harness; the suite also carries a pose self-check for the capsule test helper and a box-vs-far-box line. Dry run byte-identical; 346 tests in 52 suites. Exit criterion 1 closed.
- **2026-09-11** — C-structures landed (C.2, `3aabb82`): `StaticStructure` and the airfield per the listings. The owner's transcription had no defects; the listings' comments had not been carried over and were added at review, with three small extensions folded back into the listings (the halfHeight-0 clamp in `Shape.collider`'s comment, `makeMesh`'s thread sentence, the airfield's centers-and-spans note plus a doc comment on `addStructure`). Tests as listed plus a fourth shape test (ModelIO bounds equal the collider's reach) and two deviations in `StructureContactTests`: the broad phase stays ON (the app's dynamic-vs-static path), and case 4's tree is centered at y 4.5 so its core spans a resting ball's center (at the scene's y 5 the normal tilts 0.4°, outside the 1e-3 band). Full serial suite 354 tests in 54 suites plus 20 XCTest; dry run byte-identical; a keyboard-free smoke run lists the thirteen structures and leaves the drop sequence unchanged. Exit criterion 2's test half and criterion 4 closed; the four keyboard checks (criteria 2 and 3) stay the owner's; 5 waits on the push.
- **2026-09-11** — D-angular-plumbing landed (D.1, `14c0bda`): angular state on `RigidBody`, forces at points, `AngularIntegration`'s two halves in both solvers, and the lever-arm impulse behind the linear fast path, per the listings. Found at review, before the tests ran: `EulerSolver.step` had been transcribed with the orientation half only, so under `.NaiveEuler` a torque never reached ω (inert with infinite inertia; the plan's one-substep and response-sees-the-torque tests fail on it for that solver) — fixed; `PhysicsEntity.zeroForce()` had not been deleted and the Euler solver's legacy comment still named `applyCollisionResponse` — both fixed; the listings' comments had not been carried over and were added. One deviation, the owner's, kept and folded into the listings: `getInverseMassStats` computes a pair's inverse masses once in `resolvePair` and passes them to `correctPosition` and `applyImpulse` (the `InverseMassStats` tuple typealias), which D.3's iterations reuse; D.3.5's `resolvePair` listing is synced to the signatures. Tests as listed (14: seven, five, two, and the torque assertion), every number reproduced first, all green first run; the 72 000-substep soak's discriminating claim reproduced too (the bare matrix product drifts to 4.7e-5 in column length and 9.1e-5 in determinant where the quaternion path holds 1.2e-7 and 4.8e-7). Full serial suite 368 tests in 55 suites plus 20 XCTest; dry run byte-identical. CLAUDE.md's Physics paragraph carries the D.1 entry. `PhysicsWorld.swift` grew by seven lines, not the one D.2 accounted for (comments), so D.2's `raycastStaticPlanes` note moves to 146–161. Exit criterion 1 closed; 4 and 5 hold for D.1 and stay open for D.2 and D.3; 6 waits on the push.

## Where Phase B left the engine

Facts the steps below build on, so they are not re-derived in each step:

- One `RigidBody` per object, colliders on the body, a pure narrow phase that appends every collider-pair contact and returns the deepest, a linear response (position correction with slop and β, one impulse at the deepest contact), events per contact.
- Box-box returns nil (`NarrowPhase.swift:184–187`), and capsule-box reduces the capsule to the one sphere nearest the box center (`:174–179`). The F-22's wings and empennage are boxes; no box has ever met another box, because every debris object uses a `SphereRigidBody`.
- Physics runs in fixed 1/120 s substeps; forces come from a per-body hook at the top of each substep (`forceGenerator`); the aircraft's flight force and its three raycast struts are computed there.
- Rotation is kinematic: `Aircraft.doUpdate` rotates the node through a per-axis first-order lag filter (`AttitudeDynamics`). Nothing in physics rotates anything. `RigidBody.pose()` reads the node's rotation; `Contact.point` is produced and unread.
- The jet stands on its struts and slides: no tangent force exists anywhere. The three struts share one compression because the body cannot pitch, so the load split is 89/11 by spring rate instead of the geometric 85/15.
- Goldens: six sphere-only scenarios. No golden contains a box, a capsule, a strut, or an aircraft.

## Rules carried over

The parent plan's six rules apply unchanged: per-instance state only in the step path; plumbing and behavior commits never mix; Metal-free logic tests on detached bodies; the world-collider cache is invalidated by `setPosition`, by collider changes, and by the world at the start of each step; attached bodies read local transforms (scene-root children only, asserted in `pose()`); debug objects follow the register/`removeFromScene` rule.

One consequence is specific to these phases: **no commit in Phase C or D regenerates a golden.** Every behavior change lands on a code path no golden exercises (box and capsule pairs, struts, finite inertia), so the gate for every commit is the same: full serial suite green, then the regeneration dry run with `git diff --exit-code` on `Baselines/` empty. A diff is a bug, never a golden to update. If a later step finds it needs a golden to move, that is a design signal to stop and re-plan, not a regeneration to review.

---

# Phase C — static structures

Implements combined doc §4.4. At the end of this phase the airfield has things to hit: an open-front hangar, a control tower, and a tree line, each a static body with a `.structure` collider. Flying into a wall prints `[CRASH] F-22_CGTrader.fuselage hit Hangar_wallLeft at 41.20 m/s (gear down)` and the jet stops at the wall; clipping a tree with a wing names the wing; debris balls rest on the roof and against walls. The narrow phase gains the two pairs the F-22's boxes need against structure boxes.

**What Phase C does not change:** the response, the solvers, the strut model, the collider specs, the overlay, and the goldens.

## Commits

| Commit | Steps | Gate | Tests |
|---|---|---|---|
| **C-narrowphase** ✅ `c6b4fba` | C.1 | Behavior on paths no golden covers: dry run byte-identical. Every existing suite green; the one test that pins box-box as not implemented is replaced. | `NarrowPhaseTests` additions (box-box ×9, capsule-box ×5) |
| **C-structures** ✅ `3aabb82` | C.2 | Dry run byte-identical. In-app: the structures render at their collider size, the wall stops the jet, contact lines name the part, the jet flies through the hangar opening clean. | `StaticStructureShapeTests` (new, pure), `StructureContactTests` (new, Metal-free world) |

## Decisions

| Decision | Why |
|---|---|
| One body per structure part, not one compound per structure | Contacts name the part (`Hangar_roof`), and it avoids a root node with no mesh of its own: every `GameObject` needs a model, and a compound's root would either render nothing (an empty model is an untested path) or carry a non-uniform scale, which `uniformScale` rejects on a body's node. The cost is real but small: the broad phase tests every dynamic body against every static body (`BroadPhaseCollisionDetector.getPotentialCollisionPairs`, the dynamic-vs-static loop), so thirteen parts are thirteen AABB tests per dynamic body per substep where one compound would be one, plus thirteen one-collider rebuilds. Static bodies never pair with each other. Noise at this scale; a forest revisits it. |
| The mesh is the collider: a bespoke mesh at exact size, node scale 1 | The X-key overlay exists to compare a collider against a hull. When the hull is the collider there is nothing to compare, and nothing to keep in sync. Boxes get `CubeMesh(extent:)`; capsules already have `CapsuleMesh(radius:length:)`. |
| `StaticStructure.Shape` has two cases, box and vertical capsule, in full sizes | Authoring reads as building dimensions (a 40 × 12 × 3 m wall). Reusing `ColliderShape` directly would drag in a sphere case that has no exact-size mesh (`SphereMesh` builds twice the size; the OBJ sphere needs a scale). The mapping to `ColliderShape` is one pure function, tested. |
| Box-box by separating axes with one contact point from the clipped incident face | Fifteen axes give the least-overlap normal and depth exactly. One point is enough for a strike, but it must lie where the boxes actually meet. The first draft used the incident box's face center, which for a wing (the reference box: its axes are tested first) against a 40 m wall (the incident box) is the wall face's center — 8.5 m from the wing in C.2's own wing-over-wall case, and 10 m ahead of an origin the wing sits behind, so its Phase D yaw torque had the wrong sign. The second used the midpoint of the two boxes' projected overlap on the face's tangent axes, which is inside both projections but not both boxes: a unit cube at 45° shifted 0.5 m along the face got a point 0.46 m outside the cube, and the F-22 wing yawed 20° with its tip 0.3 m into a wall got one 5.3 m from the tip on the wing's centerline — a yaw lever arm of zero for a wingtip strike. Now Box2D's construction, reduced to one point: the incident face (the other box's face most opposed to the reference face) is clipped by the reference face's four side planes, and the clipped vertices at or below the face are averaged. Inside both boxes for every strike (285 random ones checked; the only exceptions are a box swallowed whole, where the incident face lies past the reference box's far face), and the same points as before for the aligned and the edge-on cases. Edge-edge axes take the two edges' closest points. Persistent manifolds stay in D.4: a one-point manifold would make a box resting flat on another box's face rock, and no aircraft box does that — the fuselage capsule sits below the wings and empennage. |
| Capsule-box exact: separating axes for a core that touches the box, else the least of the two end caps' distances and the core's distance to the twelve box edges | The single center-nearest probe misses a capsule end that enters a face away from the box center (the fuselage nose into a wall corner). Three probes (both caps and the center-nearest point) were the first draft; they still miss a core that crosses a box between the probes (a rod from `[8, −4, 0]` to `[12, 4, 0]` through a `[10, 1, 10]` slab: every probe is 3 m clear) and a core passing an edge at an angle — about one true hit in ten in a random sweep of overlapping pairs. The exact distance from a segment to a box is the least of its endpoints' distances (a face, an edge, or a corner: `sphereVsBox`) and its distances to the twelve edges (`closestPointsOnSegments`, which exists): a core interior point closest to a face interior means the core runs parallel to that face, and then either it lies within the face's extent (an endpoint is as close) or it crosses the face's boundary (an edge is as close). Checked against sampled truth: zero misses. A core that touches or enters the box (Ericson §5.3.3, the slab test) needs a penetration depth, not a distance. The second draft probed a sphere at the midpoint of the clipped span, which reports that sphere's depth, not the capsule's: a core through a unit box answered +x at 1.5, where 3.5 separates along x and 1.5 across the core does. The least translation of a segment out of a box is a separating-axis test over twelve directions — the box's three face normals and the core's cross product with each, both senses (the Minkowski difference's face normals) — with depth = the box's reach along the direction + r − the nearer end's projection; the face normal wins a shallow nose-first strike at any yaw, and a deep crossing slides out past the nearest edge, as box-box would. Checked against 200 000 sampled directions on 3 000 random penetrating cores: never beaten, and translating by the depth leaves exactly r every time. About fourteen segment tests or twelve axis tests per capsule-box pair; the F-22 has one capsule. |
| Structures set `categoryMask = .structure`; every mask stays `.all` | Filtering stays inert, as Phase A left it. The category is free information for whoever writes the first mask. |
| Structure restitution 0.3 | `min()` with the aircraft's 0.2 keeps the aircraft's value. Debris balls in `FlightboxWithPhysics` carry the default 1.0, so without this they would bounce off walls forever. |
| Struts see planes only | Landing on a roof is not a case. The airframe still collides with the roof (a crash). Ray-vs-box for a deck is a D.4 item. |
| Static bodies keep the per-step world-collider invalidation | Correctness first: the world's start-of-step sweep is what keeps node rotation visible. Thirteen structures × one collider rebuilt per substep is noise. Skipping statics is a one-line optimization with a stated trigger (a scene with hundreds of trees) and a new rule (a static body's node must not move after its first step). Not taken. |
| No overlay work | See "the mesh is the collider". The aircraft overlay is unchanged. |
| Tolerances are named `static let`s on `NarrowPhase`, by what they compare and its unit | Six literals in the step compared three kinds of quantity: cosines and squared sines of unit vectors, and lengths in meters and square meters. One shared epsilon would be wrong, and two of the `1e-6`s meant different angles. The capsule-box point rule's band was absolute meters, and the rounding it must absorb scales with the core: at the F-22's 16.2 m the float32 noise reached 0.95e-6 against a 1e-6 band, so the core direction is normalised once and the band is a cosine (`coreAcrossNormalCosine` = 1e-5, 170× the measured noise). `considerAxis` then shares `parallelAxisSineSquared` with `overlaps`, the same angle for "parallel" in both. |

## Step C.1 — box-box and capsule-box in the narrow phase — C-narrowphase ✅ (landed 2026-09-10, `c6b4fba`)

Why first: the structures are boxes and the F-22's wings and empennage are boxes. Without box-box, a wing through a wall makes no contact at all; with the old capsule-box probe, the fuselage nose into a wall corner can miss.

**Landed 2026-09-10** (`c6b4fba`), goldens untouched (regeneration dry run byte-identical; no golden has a box or a capsule). Found at review: the edge-edge loop had been transcribed as `cross(a.rotation[i], b.rotation[i])`, so only the three i = j axes were tested and the six i ≠ j axes never — on the crossed-rods case (test 4) it reported A's own face axis at 0.78 with the point at the end of B's ridge, 1 m from the crossing, and a pair separated only along an i ≠ j axis would have reported a contact; fixed to the listed `b.rotation[j]`, and the edge-edge test fails on the transcribed form. `boxVsBox` had also shipped without its listed comments (added; the other listings were transcribed with theirs). Expectations: every listed number reproduced, first in a standalone harness (the file's pure functions under `swiftc` with type stubs) and then in the suite; no tolerance was widened. Shipped tests: 36 in `NarrowPhaseTests` (was 23) — the nine box-box cases as eight `@Test`s plus the metadata pair inside `A metadata stays on A in both argument orders` (which now checks groups too: the probe helper gained a `group:` parameter), the five capsule-box cases (case 1 includes the 90°-about-Y turn; case 5 iterates cases 1, 3, and 4), a sixth capsule-box test pinning the `capsuleAlong(from:to:radius:)` helper's pose against case 1's stated center, half height, axis, and core start, and one line in `every separated pair returns nil` for box vs far box. The capsule cases build their `WorldCollider` from the core endpoints through that helper (angle = atan2(−dir.x, dir.y) about Z) rather than from the center/half-height/angle literals; the pose test shows the two agree. Full serial suite: 346 Swift Testing tests in 52 suites (was 333) plus 20 XCTest cases. In the file the helpers are ordered `capsuleVsBox`, `boxVsBox`, `segmentSpanInsideBox` (the listing puts the slab test before the box pair); otherwise the listings below are the shipped code up to line breaks.

- [x] **Edit:** `Physics/Collision/NarrowPhase.swift`, the `(.capsule, .box)` case (lines 174–179):

```swift
            case (.capsule, .box(halfExtents: let he)):
                return capsuleVsBox(a, b, halfExtents: he)
```

- [x] **Edit:** the `(.box, .box)` case (lines 184–187):

```swift
            case (.box(halfExtents: let ha), .box(halfExtents: let hb)):
                return boxVsBox(a, halfExtentsA: ha, b, halfExtentsB: hb)
```

- [x] **Edit:** the tolerances, a new section at the top of `// MARK: - Primitive helpers` (line 191), before `rayVsPlane`. Named by what they compare, with the unit in the doc comment; none is a generic epsilon, and one shared value would be wrong because the units differ (cosines and squared sines of unit vectors, and one length). Internal, like `segmentSpanInsideBox`, so tests can name them:

```swift
    // MARK: - Tolerances
    //
    // Angles are compared as cosines or squared sines of unit vectors, so
    // they do not scale with the scene; the one length is a division guard.

    /// Ray vs plane: the cosine between the unit ray and the plane normal
    /// must lie at least this far below zero. Grazing and receding rays
    /// (an inverted aircraft's struts) hit nothing.
    static let grazingRayCosine: Float = 1e-6

    /// Separating axes from cross products: two unit directions whose cross
    /// product is shorter than this (|sin θ| < 1e-3, 0.057°) are parallel
    /// and give no new axis. Box edges against box edges in boxVsBox, the
    /// core direction against box axes in capsuleVsBox.
    static let parallelAxisSineSquared: Float = 1e-6

    /// Support point: a box axis whose cosine against the direction is
    /// within this of zero (0.006°) has no single farthest point and
    /// contributes its center.
    static let perpendicularAxisCosine: Float = 1e-4

    /// Capsule-box contact point: a core whose cosine against the contact
    /// normal is within this of zero runs across the normal, and the
    /// clipped span's midpoint is the point rather than an end. The
    /// cross-product normals are perpendicular to the core exactly; in
    /// float32 their cosine carries up to 6e-8 of rounding (300 000 random
    /// pose-axis samples of the F-22's 16.2 m core), so this is a 170×
    /// margin. The absolute 1e-6 m band it replaces was within 5% of that
    /// rounding at 16.2 m.
    static let coreAcrossNormalCosine: Float = 1e-5

    /// Segment vs slab: a segment whose extent along a box axis is under
    /// this (meters) is parallel to the slab, which keeps 1 / extent
    /// finite and the 0 × inf NaN out of the crossing parameters.
    static let parallelSlabExtent: Float = 1e-8
```

- [x] **Edit:** `rayVsPlane` (line 200): the guard reads `guard denominator < -grazingRayCosine else { return nil }   // parallel, or facing away` — the same value, named.

- [x] **Edit:** the new primitives, after `sphereVsBox` (its closing brace is line 261), before `capsuleSegment`. First the capsule pair:

```swift
    /// Capsule vs oriented box, exact. A core that touches or enters the box
    /// (the slab test) gets the least translation that frees the capsule, by
    /// separating axes over the twelve directions a segment and a box can
    /// separate along. Otherwise the core's distance to the box is the least
    /// of its two ends' distances (sphereVsBox: a face, an edge, or a corner)
    /// and its distance to each of the twelve box edges
    /// (closestPointsOnSegments): a core interior point nearest a face
    /// interior means the core runs parallel to the face, and then an end or
    /// a boundary edge is as close. The three sphere probes this replaces
    /// (both caps and the point nearest the box center) missed a core
    /// crossing a box between them, about one true hit in ten; a sphere
    /// probed at the clipped span's midpoint (the second draft) reported that
    /// sphere's depth, not the capsule's.
    private static func capsuleVsBox(_ a: WorldCollider, _ b: WorldCollider, halfExtents he: float3) -> Contact? {
        let (capsuleCoreStart, capsuleCoreEnd, capsuleRadius) = capsuleSegment(a)

        // Capsule core in box-local space (R orthonormal: inverse = transpose).
        let localCapsuleCoreStart = b.rotation.transpose * (capsuleCoreStart - b.position)
        let localCapsuleCoreEnd = b.rotation.transpose * (capsuleCoreEnd - b.position)
        if let span = segmentSpanInsideBox(localCapsuleCoreStart, localCapsuleCoreEnd, halfExtents: he) {
            // Penetration depth of a segment in a box: the least, over the
            // Minkowski difference's face normals — the three face normals
            // and the core's cross product with each, in both senses — of
            // the box's reach along the direction, plus the radius, minus the
            // nearer end's projection: how far the capsule must move along it
            // to be clear. Face axes first, strict compares: ties go to the
            // face and to the earlier sense. A shallow nose-first strike
            // comes out through the face at any yaw; a deep crossing slides
            // out past the nearest edge, as box-box would.
            // The core's unit direction: its cross products with the box
            // axes are then sines and its run along the normal a cosine, so
            // both tolerances are angles and neither scales with the core.
            // A zero-length core (a sphere) has no direction: no
            // cross-product axes, and the point is the span's midpoint.
            let localCapsuleCoreDelta = localCapsuleCoreEnd - localCapsuleCoreStart
            let coreLength = simd_length(localCapsuleCoreDelta)
            let localCapsuleCoreDirection = coreLength > 0 ? localCapsuleCoreDelta / coreLength : .zero
            var leastDepth = Float.infinity
            var localNormal = float3.zero
            func considerAxis(_ candidate: float3) {
                let lengthSquared = simd_length_squared(candidate)
                guard lengthSquared > parallelAxisSineSquared else { return }   // core parallel to the axis: no new direction
                let axis = candidate / lengthSquared.squareRoot()
                let reach = he.x * abs(axis.x) + he.y * abs(axis.y) + he.z * abs(axis.z)
                for sense in 0..<2 {
                    let signedAxis = sense == 0 ? axis : -axis
                    let nearerEndProjection = min(dot(localCapsuleCoreStart, signedAxis),
                                                  dot(localCapsuleCoreEnd, signedAxis))
                    let depth = reach + capsuleRadius - nearerEndProjection
                    if depth < leastDepth {
                        leastDepth = depth
                        localNormal = signedAxis
                    }
                }
            }
            for i in 0..<3 {
                var axis = float3.zero
                axis[i] = 1
                considerAxis(axis)
            }
            for i in 0..<3 {
                var axis = float3.zero
                axis[i] = 1
                considerAxis(cross(localCapsuleCoreDirection, axis))
            }

            // The point: the clipped span's deepest point against the normal
            // (an end inside the box), or the span's midpoint when the core
            // runs across the normal (a core through the box, or past an
            // edge). Inside both shapes, as sphereVsBox's inside branch
            // reports the center.
            let coreAlongNormal = dot(localCapsuleCoreDirection, localNormal)   // a cosine
            let contactPointParameter: Float   // along the core: 0 at capsuleCoreStart, 1 at capsuleCoreEnd
            if coreAlongNormal > coreAcrossNormalCosine {
                contactPointParameter = span.enter
            } else if coreAlongNormal < -coreAcrossNormalCosine {
                contactPointParameter = span.exit
            } else {
                contactPointParameter = 0.5 * (span.enter + span.exit)
            }
            return Contact(normal: b.rotation * localNormal,
                           depth: leastDepth,
                           point: capsuleCoreStart + (capsuleCoreEnd - capsuleCoreStart) * contactPointParameter,
                           collider: a,
                           against: b)
        }

        // Outside the box: the nearer end cap, then the twelve edges. Ties
        // keep the earlier candidate, as everywhere else.
        var best: Contact? = nil
        func consider(_ candidate: Contact?) {
            guard let candidate else { return }
            if let current = best, current.depth >= candidate.depth { return }
            best = candidate
        }
        consider(sphereVsBox(center: capsuleCoreStart, radius: capsuleRadius, box: b, halfExtents: he, a: a, b: b))
        consider(sphereVsBox(center: capsuleCoreEnd, radius: capsuleRadius, box: b, halfExtents: he, a: a, b: b))

        for axis in 0..<3 {
            // The four edges parallel to this axis, one per corner of the
            // face it is normal to.
            let u = (axis + 1) % 3
            let v = (axis + 2) % 3
            let halfEdge = b.rotation[axis] * he[axis]
            for cornerU in 0..<2 {
                for cornerV in 0..<2 {
                    let signU: Float = cornerU == 0 ? -1 : 1
                    let signV: Float = cornerV == 0 ? -1 : 1
                    let middle = b.position + b.rotation[u] * (signU * he[u]) + b.rotation[v] * (signV * he[v])
                    let (onCapsuleCore, onEdge) = closestPointsOnSegments(capsuleCoreStart, capsuleCoreEnd,
                                                                          middle - halfEdge, middle + halfEdge)
                    let delta = onCapsuleCore - onEdge
                    let distance = simd_length(delta)
                    guard distance <= capsuleRadius, distance > 0 else { continue }   // 0 cannot happen: the slab test took it
                    consider(Contact(normal: delta / distance,
                                     depth: capsuleRadius - distance,
                                     point: onEdge,
                                     collider: a,
                                     against: b))
                }
            }
        }

        return best
    }

    /// The parameter span of the segment segmentStart→segmentEnd (t = 0 at
    /// the start, 1 at the end; both ends box-local) inside the axis-aligned
    /// box of the given half extents, or nil where it passes by. Ericson
    /// §5.3.3 (segment vs AABB by slabs); inclusive at the boundary like
    /// every other gate, so a segment touching a face is inside.
    static func segmentSpanInsideBox(_ segmentStart: float3, _ segmentEnd: float3,
                                     halfExtents he: float3) -> (enter: Float, exit: Float)? {
        let segmentDelta = segmentEnd - segmentStart
        var enter: Float = 0
        var exit: Float = 1
        for i in 0..<3 {
            if abs(segmentDelta[i]) < parallelSlabExtent {
                // Parallel to this slab: inside it or not at all.
                guard abs(segmentStart[i]) <= he[i] else { return nil }
            } else {
                let inverseDelta = 1 / segmentDelta[i]
                var slabEnter = (-he[i] - segmentStart[i]) * inverseDelta
                var slabExit = (he[i] - segmentStart[i]) * inverseDelta
                if slabEnter > slabExit { swap(&slabEnter, &slabExit) }
                enter = max(enter, slabEnter)
                exit = min(exit, slabExit)
                guard enter <= exit else { return nil }
            }
        }
        return (enter, exit)
    }
```

Then the box pair:

```swift
    /// Oriented box vs oriented box by separating axes: the six face normals
    /// and the nine edge-edge cross products (Ericson §4.4.1 gives the test;
    /// this keeps each axis's overlap). The contact normal is the axis of
    /// least overlap, pointed from B toward A, and the depth is that overlap.
    /// One contact point where the boxes meet: for a face axis, the centroid
    /// of the incident face clipped to the reference face (Box2D's manifold,
    /// reduced to one point); for an edge-edge axis the midpoint of the two
    /// edges' closest points. Right for a strike; a box resting flat on
    /// another box's face would rock on one point, and no aircraft box does
    /// (the fuselage capsule sits below the wings and empennage).
    private static func boxVsBox(_ a: WorldCollider, halfExtentsA ha: float3,
                                 _ b: WorldCollider, halfExtentsB hb: float3) -> Contact? {
        enum Feature { case faceOfA(Int), faceOfB(Int), edges(Int, Int) }
        let centerOffset = a.position - b.position
        var leastOverlap = Float.infinity
        var normal = float3.zero
        var feature = Feature.faceOfA(0)

        /// False when `candidate` separates the boxes. Near-parallel edges
        /// give a near-zero cross product and no new axis.
        func overlaps(along candidate: float3, _ candidateFeature: Feature) -> Bool {
            let lengthSquared = simd_length_squared(candidate)
            guard lengthSquared > parallelAxisSineSquared else { return true }
            let axis = candidate / lengthSquared.squareRoot()
            let reachA = ha.x * abs(dot(a.rotation[0], axis)) + ha.y * abs(dot(a.rotation[1], axis)) + ha.z * abs(dot(a.rotation[2], axis))
            let reachB = hb.x * abs(dot(b.rotation[0], axis)) + hb.y * abs(dot(b.rotation[1], axis)) + hb.z * abs(dot(b.rotation[2], axis))
            let distance = dot(centerOffset, axis)
            let overlap = reachA + reachB - abs(distance)
            guard overlap >= 0 else { return false }              // inclusive, like every other gate
            if overlap < leastOverlap {                           // strict: face axes win ties over edge axes
                leastOverlap = overlap
                normal = distance >= 0 ? axis : -axis             // from B toward A
                feature = candidateFeature
            }
            return true
        }

        for i in 0..<3 {
            guard overlaps(along: a.rotation[i], .faceOfA(i)), overlaps(along: b.rotation[i], .faceOfB(i)) else { return nil }
        }
        for i in 0..<3 {
            for j in 0..<3 {
                guard overlaps(along: cross(a.rotation[i], b.rotation[j]), .edges(i, j)) else { return nil }
            }
        }

        /// The box's farthest point in `direction`. An axis at right angles to
        /// the direction has no single farthest point (a face or an edge), so
        /// that axis contributes its center: a face gives its center, an edge
        /// its midpoint, a corner itself.
        func support(_ box: WorldCollider, _ h: float3, _ direction: float3) -> float3 {
            var point = box.position
            for i in 0..<3 {
                let alignment = dot(box.rotation[i], direction)
                if abs(alignment) > perpendicularAxisCosine {
                    point += box.rotation[i] * (h[i] * (alignment > 0 ? 1 : -1))
                }
            }
            return point
        }

        /// One point where the boxes meet, for a face axis of `reference`
        /// (Box2D's contact points, Catto GDC 2006, reduced to one): the
        /// incident face — the other box's face most opposed to the
        /// reference face — is clipped by the reference face's four side
        /// planes (Sutherland–Hodgman), and the clipped vertices at or below
        /// the face are averaged. Inside both boxes for any strike. The
        /// second draft's projected-overlap midpoint was inside both
        /// projections but not both boxes: a unit cube at 45° shifted 0.5 m
        /// along the face got a point 0.46 m outside the cube, and a wing
        /// yawed 20° with its tip 0.3 m into a wall got one 5.3 m from the
        /// tip on the wing's centerline, a yaw lever arm of zero. A quad
        /// clipped by four planes has at most eight vertices; the buffer is
        /// on the stack. `fallback` (the support point) covers a clip that
        /// keeps nothing, which no overlapping pair has produced.
        func clippedPoint(reference: WorldCollider, _ hRef: float3, referenceAxis: Int, faceNormal: float3,
                          incident: WorldCollider, _ hInc: float3, fallback: float3) -> float3 {
            // The incident face: the incident axis most opposed to the
            // reference face's outward normal, on that side.
            var incidentAxis = 0
            var incidentSign: Float = 1
            var mostOpposed = Float.infinity
            for j in 0..<3 {
                let alignment = dot(incident.rotation[j], faceNormal)
                let sign: Float = alignment > 0 ? -1 : 1
                if sign * alignment < mostOpposed {
                    mostOpposed = sign * alignment
                    incidentAxis = j
                    incidentSign = sign
                }
            }
            let u = (incidentAxis + 1) % 3
            let v = (incidentAxis + 2) % 3
            let faceCenter = incident.position + incident.rotation[incidentAxis] * (incidentSign * hInc[incidentAxis])
            let du = incident.rotation[u] * hInc[u]
            let dv = incident.rotation[v] * hInc[v]

            return withUnsafeTemporaryAllocation(of: float3.self, capacity: 16) { buffer -> float3 in
                // Two eight-slot halves, swapped after each clip plane.
                var input = UnsafeMutableBufferPointer(rebasing: buffer[0..<8])
                var output = UnsafeMutableBufferPointer(rebasing: buffer[8..<16])
                input[0] = faceCenter + du + dv
                input[1] = faceCenter + du - dv
                input[2] = faceCenter - du - dv
                input[3] = faceCenter - du + dv
                var count = 4

                for sideAxis in 0..<3 where sideAxis != referenceAxis {
                    for side in 0..<2 {
                        // Keep what lies within this side plane of the
                        // reference face: dot(p, n) ≤ dot(center, n) + h.
                        let planeNormal = reference.rotation[sideAxis] * (side == 0 ? -1 : 1)
                        let planeOffset = dot(reference.position, planeNormal) + hRef[sideAxis]
                        var kept = 0
                        for k in 0..<count {
                            let p = input[k]
                            let q = input[(k + 1) % count]
                            let dp = dot(p, planeNormal) - planeOffset
                            let dq = dot(q, planeNormal) - planeOffset
                            if dp <= 0 {
                                output[kept] = p
                                kept += 1
                            }
                            if (dp < 0 && dq > 0) || (dp > 0 && dq < 0) {
                                output[kept] = p + (q - p) * (dp / (dp - dq))
                                kept += 1
                            }
                        }
                        count = kept
                        guard count > 0 else { return fallback }
                        swap(&input, &output)
                    }
                }

                // The clipped vertices at or below the reference face.
                let facePlane = dot(reference.position, faceNormal) + hRef[referenceAxis]
                var sum = float3.zero
                var below = 0
                for k in 0..<count where dot(input[k], faceNormal) - facePlane <= 0 {
                    sum += input[k]
                    below += 1
                }
                return below > 0 ? sum / Float(below) : fallback
            }
        }

        let point: float3
        switch feature {
            case .faceOfA(let i):
                // The reference face is A's face toward B: its outward normal
                // is −normal (the normal points from B toward A).
                point = clippedPoint(reference: a, ha, referenceAxis: i, faceNormal: -normal,
                                     incident: b, hb, fallback: support(b, hb, normal))
            case .faceOfB(let i):
                point = clippedPoint(reference: b, hb, referenceAxis: i, faceNormal: normal,
                                     incident: a, ha, fallback: support(a, ha, -normal))
            case .edges(let i, let j):
                let midA = support(a, ha, -normal)
                let midB = support(b, hb, normal)
                let (pA, pB) = closestPointsOnSegments(midA - a.rotation[i] * ha[i], midA + a.rotation[i] * ha[i],
                                                       midB - b.rotation[j] * hb[j], midB + b.rotation[j] * hb[j])
                point = 0.5 * (pA + pB)
        }

        return Contact(normal: normal, depth: leastOverlap, point: point, collider: a, against: b)
    }
```

Details that are easy to get wrong:

- The normal must point from B toward A (the `Contact` contract). `distance = dot(a.position − b.position, axis)`; A is on the positive side when `distance >= 0`, so the axis is kept, else negated.
- Face axes are tested before edge axes and ties keep the first, so a face-face contact never reports an edge axis (the two coincide in overlap for aligned boxes).
- `support` with the parallel-axis rule is what makes the edge-edge midpoints lie on the edges; it is also `clippedPoint`'s fallback. Without it two aligned unit cubes' edge midpoints would sit at a shared corner.
- `clippedPoint` needs the reference face's outward normal: −`normal` when the reference is A (the normal points from B toward A), +`normal` when it is B. A wrong sign picks the far face of the reference box and the incident face on the wrong side, and every kept vertex lands beyond the face.
- Sutherland–Hodgman keeps a vertex on the plane (`dp <= 0`) and adds the crossing point only for a strict crossing; a convex quad clipped by four planes has at most eight vertices, so the two eight-slot halves never overflow. The stack buffer is `withUnsafeTemporaryAllocation` (Swift 5.6): no allocation, and nothing static.
- The slab test and the axis test run in box-local space; `capsuleVsBox` transforms only the two core endpoints and rotates the winning local normal back. The edge loop works in world space with the box's world axes.
- `matrix_float3x3[i]` is column i, the box's i-th axis in world space. No arrays are built: the step path stays allocation-free.
- Ericson's test skips a cross-product axis when the edges are parallel; so does `overlaps` (`lengthSquared > parallelAxisSineSquared`), returning "not separated" for that axis.

### Tests for this step (`NarrowPhaseTests`, Metal-free)

- [x] Replace `box-box is pinned NOT IMPLEMENTED: nil even when overlapping` (line 138) with nine cases:
  1. **Aligned face overlap.** A: half extents 1 at `[1.5, 0, 0]`; B: half extents 1 at the origin. Normal `[1, 0, 0]`, depth 0.5, point `[1, 0, 0]` (A's x axis is tested first, ties keep it, so the feature is `faceOfA(0)`; B's support gives x = 1 and the overlap midpoints give y = z = 0). Also `boxVsBox` through `shapeVsShape(b, a)`: normal `[-1, 0, 0]`, same depth (the point may differ: it lies on the other box's face, which is also correct).
  1b. **Offset face overlap** (the first review's case). A at `[1.5, 1.5, 0]`, B at the origin: x and y overlap 0.5 each and the strict compare keeps x. Normal `[1, 0, 0]`, depth 0.5, point `[1, 0.75, 0]`: B's +x face clipped to A's y range is the strip y = 0.5…1 at x = 1, all of it 0.5 deep, and its centroid is inside the overlap (x 0.5…1, y 0.5…1). B's support alone gave `[1, 0, 0]`, outside A entirely.
  2. **Separated and touching.** A at `[2.5, 0, 0]` → nil; A at `[2, 0, 0]` → a contact with depth 0 (inclusive gate).
  3. **Rotated box on a face.** A: half extents 1, rotated 45° about Z, center `[0, 1 + √2 − 0.1, 0]`; B: half extents 1 at the origin. Least axis is B's +y face (overlap 0.1; A's own axes overlap by about 0.78 and the y edge-cross ties but loses to the face). Normal `[0, 1, 0]`, depth 0.1 ± 1e-4, point `[0, 0.9, 0]` ± 1e-4: the incident face is one of A's two lower faces (a tie to one ulp in float; either face keeps the same bottom edge, so the point does not depend on which wins), its two low vertices are the bottom edge at y = 0.9, z = ±1, its two high ones sit 1.3 above the face and are dropped, and the centroid is the edge's midpoint.
  3b. **Rotated box shifted along the face** (the second review's case). Case 3 with A at `[0.5, 1 + √2 − 0.1, 0]`: same normal and depth, point `[0.5, 0.9, 0]` ± 1e-4, the bottom edge's midpoint. The projected-overlap midpoint gave `[0.043, 0.9, 0]`, which in A's frame is 1.32 half extents out along one axis: outside A.
  3c. **Rotated box over the side of the face.** A: half extents 1, rotated 40° about Z (0.6981 rad), placed so its bottom corner sits at x = 0.93, y = 0.9: center `[0.93 + cos 40° − sin 40°, 0.9 + cos 40° + sin 40°, 0]` = `[1.0533, 2.3088, 0]`. At 40° the incident face is unambiguous — A's −y face, opposed to the reference normal by 0.766 against 0.643 for the other lower face (at 45° the two tie to one ulp, and they clip to different points) — and it rises toward +x, crossing B's x = 1 side plane 0.041 below the top face. Least axis B's +y at 0.1; A's own x axis is next at 0.118. Normal `[0, 1, 0]`, depth 0.1 ± 1e-4, point `[0.965, 0.929, 0]` ± 1e-3: the clip keeps four vertices, the bottom edge's two at `[0.93, 0.9, ±1]` and two new ones on the side plane at `[1, 0.959, ±1]`. The same in float32.
  4. **Edge-edge.** A: half extents `[0.2, 0.2, 2]` (a rod along z) rotated 45° about Z, center `[1, 0.466, 0]`; B: half extents `[2, 0.2, 0.2]` (a rod along x) rotated 45° about X at the origin. The ridges cross at x = 1 with 0.1 m of overlap: normal `[0, 1, 0]` ± 1e-4, depth 0.1 ± 1e-3, point `[1, 0.233, 0]` ± 1e-3. The x = 1 pins the closest-points step: the edge midpoints alone would give x = 0.5.
  5. **Metadata.** Names and groups land on the right sides in both argument orders (extend `A metadata stays on A in both argument orders; normals mirror` at line 239 with a box-box pair).
  6. **Yawed wing tip into a wall.** A: the F-22 wing box, half extents `[6.6, 0.18, 2.7]`, rotated 0.3491 rad (20°) about Y, center `[5.279, 6, −4.495]`, which puts its leading tip edge (local x = −6.6, z = 2.7) at z = 0.3; B: a wall, half extents `[20, 6, 1.5]` at `[0, 6, 1.5]`, near face at z = 0. Normal `[0, 0, −1]` ± 1e-4, depth 0.3 ± 1e-3, point `[0, 6, 0.3]` ± 2e-3 — the tip edge's midpoint: the incident face is the wing's front face, and its trailing tip sits about 4 m in front of the wall and is dropped. The projected-overlap midpoint put the point at `[5.28, 6, 0.3]`, on the wing's centerline: with D.3's lever arms a wingtip strike would not have yawed the jet.
- [x] **Capsule-box, five cases**, the first three against slab B: half extents `[10, 1, 10]` at the origin. Each capsule is a `WorldCollider` whose axis (local +Y) is rotated about Z to run along the stated core; `capsuleCoreStart = center − axis·halfHeight`.
  1. **Core crossing the slab between the old probes** (the first review's counterexample). Core `[8, −4, 0]` → `[12, 4, 0]`, radius 0.5: center `[10, 0, 0]`, half height 4.4721, rotation −0.4636 rad about Z (axis `[0.4472, 0.8944, 0]`). Both ends are 3 m clear and the point nearest the slab's center is the first end, but the core is inside the slab for t = 0.375…0.5, passing 0.447 m inside the corner edge at `[10, −1, z]`. Expected: normal `[0.8944, −0.4472, 0]` ± 1e-3 (the core's cross product with the z axis: the capsule slides out past that edge), depth 0.9472 ± 1e-3 (0.447 + the radius), point `[9.75, −0.5, 0]` ± 1e-3 (the clipped span's midpoint: the core runs across the normal). The face axes lose: +x needs 2.5, ±y 5.5. The second draft's midpoint probe answered `[1, 0, 0]` at 0.75, and a capsule moved 0.75 along x is still crossing the slab. Then the same pair with both colliders' positions and rotations turned 90° about Y (`simd_quatf(angle: .halfPi, axis: Y_AXIS)`, the slab's rotation included): normal `[0, −0.4472, −0.8944]` ± 1e-3, same depth — the box-local transform.
  2. **Core passing a corner at an angle.** Core `[12, 1.2, 0]` → `[8, 3, 0]`, radius 1.1: center `[10, 2.1, 0]`, half height 2.1932, rotation 1.1487 rad about Z (axis `[−0.9119, 0.4104, 0]`). Both ends are 2.0 m from the slab, and so is the center-nearest point (an end), but the core passes 1.0032 m from the corner `[10, 1, 0]`. Expected: normal `[0.4104, 0.9119, 0]` ± 1e-3, depth 0.0968 ± 1e-3, point `[10, 1, 0]` ± 1e-3 (the edge branch: the +x, +y edge along z). Three probes returned nil here.
  3. **End inside the slab** (the first draft's case). Core `[9.8, 0.5, 0]` → `[1.8, 6.5, 0]`, radius 0.5: center `[5.8, 3.5, 0]`, half height 5, rotation 0.9273 rad about Z (axis `[−0.8, 0.6, 0]`). The end sits 0.5 m below the top face: normal `[0, 1, 0]`, depth 1.0 ± 1e-3 (0.5 + the radius; the nearest cross axis, `[0.6, 0.8, 0]`, needs 1.02), point `[9.8, 0.5, 0]` ± 1e-3 (the span's end deepest against the normal). The first draft expected `[1, 0, 0]` at 0.7 and the second `[0, 1, 0]` at 0.75; neither depth frees the capsule.
  4. **Core through the box** (the second review's case). B: a unit box (half extents 1) at the origin; core `[−2, 0, 0]` → `[2, 0, 0]`, radius 0.5: center at the origin, half height 2, rotation −π/2 about Z (axis `[1, 0, 0]`). Every direction across the core needs 1.5 and the first tested wins: normal `[0, 1, 0]`, depth 1.5 ± 1e-4, point `[0, 0, 0]` ± 1e-4 (the span's midpoint). The midpoint probe answered `[1, 0, 0]` at 1.5, where 3.5 separates along x.
  5. **The depth frees the capsule** (the second review's response check), over cases 1, 3, and 4: with the capsule's `position` moved by `depth × normal` the pair reports nil or a depth ≤ 1e-4; moved by `(depth − 0.01) × normal` it reports depth 0.01 ± 1e-4 with the same normal within 1e-3 — through the outside branch each time (the corner edge for 1, an end cap for 3, a top-face edge for 4), so the two constructions agree at the boundary.
- [x] `capsule-box: contact where obviously overlapping, nil where obviously clear` (line 222) stays green unedited.
- [x] Gate: full serial suite green; dry run byte-identical (no golden has a box or a capsule).

## Step C.2 — `StaticStructure` and the airfield — C-structures ✅ (landed 2026-09-11, `3aabb82`)

Line numbers in this step are as of `82f852b`; C.1 touched only `NarrowPhase.swift`.

**Landed 2026-09-11** (`3aabb82`), goldens untouched (regeneration dry run byte-identical; no golden has a structure). The owner transcribed the three listings and review found no defects: every name resolves with the listed signature, and the collider mapping, static-body setup, mask, restitution, positions, and call placement agree. The listings' comments had not been carried over, so they were added at review — both `CubeMesh` doc comments, `StaticStructure`'s class, case, init, and `makeMesh` comments, the airfield's doc comment and hangar note — with three small extensions, now in the listings below: `Shape.collider`'s comment states the halfHeight-0 clamp; `makeMesh`'s thread sentence reads "wherever `buildScene` runs (the update thread on a scene reset)", because at launch the view wrapper calls `SetScene` on the main thread and the point is that `MTKMesh` creation needs neither; the airfield's doc comment carries the centers-and-spans prose, a tower/trees note, and `addStructure` gets a doc comment. Shipped tests: 8 (4 + 4). `StaticStructureShapeTests` has the three listed mappings and a fourth, the mesh-is-the-collider check: ModelIO's box and capsule bounds with a nil allocator (`makeMesh`'s constructor arguments) equal the collider's reach, ±halfExtents and ±[r, halfHeight + r, r]. `StructureContactTests` runs with the broad phase ON, unlike the sibling world suites, so structures reach the narrow phase through the dynamic-vs-static loop the app uses and two statics (a tree and the ground) never pair. Two deviations from the cases as listed: the wall strike also pins exactly one impact — e = 0.2 on 30 m/s rebounds at 6 m/s, 5 cm per substep, so the nose clears the face on the next step (the first contact is at depth 0.05 m after 40 substeps) — and case 4's tree stands with its center at y 4.5 (core y 0…9) on a ground plane rather than at the scene's y 5, because a ball resting 7 mm into the ground meets a y-5 tree's core end 7 mm above its own center, a 0.4° tilt that is invisible in play but outside the 1e-3 band; the plan's "rolling" is a frictionless slide. Every expected value was reproduced by hand from the response and narrow-phase code before the tests ran, and all eight passed first run. Full serial suite: 354 Swift Testing tests in 54 suites (was 346 in 52) plus 20 XCTest cases. In-app: a 40 s keyboard-free smoke run of the Debug build lists the thirteen structures among the scene children and prints the B.6 drop sequence line for line (the structures are ahead of the drop point); the four keyboard checks under "Expected behavior" stay the owner's under exit criterion 2. The listings below are the shipped code.

- [x] **Edit:** `AssetPipeline/Libraries/Meshes/BasicMeshes.swift`, `CubeMesh` (lines 38–60). The unit-cube init becomes a convenience over a full-extent init; the body is unchanged apart from the extent argument:

```diff
 class CubeMesh: Mesh {
     private var _color: float4
     
-    init(size: Float = 1.0, color: float4 = GRABBER_BLUE_COLOR) {
+    /// Unit cube (the library's .Cube). Structures use init(extent:).
+    convenience init(size: Float = 1.0, color: float4 = GRABBER_BLUE_COLOR) {
+        self.init(extent: float3(repeating: size), color: color)
+    }
+
+    /// Box of the given full extents: MDLMesh(boxWithExtent:) takes full
+    /// extents (measured by MeshBoundsTests).
+    init(extent: float3, color: float4 = GRABBER_BLUE_COLOR) {
         _color = color
         
-        let mdlCube = MDLMesh(boxWithExtent: [size, size, size],
+        let mdlCube = MDLMesh(boxWithExtent: extent,
                               segments: [1, 1, 1],
```

- [x] **File (new):** `ToyFlightSimulator Shared/GameObjects/StaticStructure.swift`

```swift
//
//  StaticStructure.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/11/26.
//

/// Static scenery with collision: one box or one vertical capsule, rendered
/// at exactly its collider's size (the mesh is the collider, so there is
/// nothing to overlay) and carried by a static RigidBody it creates itself.
/// Build a hangar from several. Static bodies never pair with each other in
/// the broad phase; each part costs one AABB test per dynamic body per
/// substep over a compound, and contacts name the part ("Hangar_roof").
final class StaticStructure: GameObject {
    enum Shape {
        /// Full extents in meters: a 40 × 12 × 3 m wall is [40, 12, 3].
        case box(size: float3)
        /// Vertical (axis +Y), `height` cap to cap.
        case capsule(radius: Float, height: Float)

        /// The same solid as a collider. Pure, tested. A capsule no taller
        /// than its diameter has no core: halfHeight clamps to 0, the
        /// sphere-equivalent LocalCollider accepts, never negative.
        var collider: ColliderShape {
            switch self {
                case .box(let size):
                    return .box(halfExtents: size / 2)
                case .capsule(let radius, let height):
                    return .capsule(radius: radius, halfHeight: max(0, height / 2 - radius))
            }
        }
    }

    init(name: String, shape: Shape, color: float4) {
        super.init(name: name, model: Model(name: name, mesh: Self.makeMesh(shape)))
        setColor(color)

        // RigidBody.init registers itself as this object's rigidBody. Scenes
        // still add it to their PhysicsWorld (GameScene.addChild registers
        // renderables, not bodies).
        let body = RigidBody(gameObject: self)
        body.colliders = [LocalCollider(name: name, shape: shape.collider, group: .structure)]
        body.isStatic = true
        body.shouldApplyGravity = false
        body.restitution = 0.3            // min() with the aircraft's 0.2 keeps 0.2; debris (1.0) stops bouncing
        body.categoryMask = CollisionCategory.structure
    }

    /// Bespoke mesh at the shape's size, so the node stays at scale 1 (the
    /// units contract for a body's node). Built wherever buildScene runs (the
    /// update thread on a scene reset), like the overlay's capsule volumes:
    /// MTKMesh creation does not need the main thread.
    private static func makeMesh(_ shape: Shape) -> Mesh {
        switch shape {
            case .box(size: let size):
                return CubeMesh(extent: size)
            case .capsule(radius: let radius, height: let height):
                return CapsuleMesh(radius: radius, length: height)
        }
    }
}
```

- [x] **Edit:** `Scenes/FlightboxWithPhysics.swift`. The call goes after the ground-level cube (line 168), before the commented-out `makeRandomDispersedObjects` line at 170:

```swift
        addAirfieldStructures()
```

and the two helpers go after `makeRandomDispersedObjects` (its closing brace is line 101), before `buildScene`:

```swift
    /// Phase C scenery, all ahead of the drop point (+Z is forward) and off
    /// the landing line: an open-front hangar facing the runway, a control
    /// tower, and a tree line either side of a 90 m wide taxi lane.
    /// Positions are centers: a 12 m wall centered at y 6 stands on the
    /// ground, the 2 m roof at y 13 sits on the walls (bottom at 12), and
    /// the back wall at z 321.5 (320…323) closes the walls' 280…320 span.
    private func addAirfieldStructures() {
        let concrete: float4 = [0.6, 0.6, 0.6, 1]
        let bark: float4 = [0.35, 0.25, 0.15, 1]

        // Hangar: 37 m wide opening toward −Z, 40 m deep, 12 m under the roof.
        // Walls are 3 m thick so a 300 m/s arrival (2.5 m per substep) cannot
        // pass through between two substeps; there is no continuous collision.
        addStructure(StaticStructure(name: "Hangar_wallLeft", shape: .box(size: [3, 12, 40]), color: concrete),
                     at: [70, 6, 300])
        addStructure(StaticStructure(name: "Hangar_wallRight", shape: .box(size: [3, 12, 40]), color: concrete),
                     at: [110, 6, 300])
        addStructure(StaticStructure(name: "Hangar_wallBack", shape: .box(size: [43, 12, 3]), color: concrete),
                     at: [90, 6, 321.5])
        addStructure(StaticStructure(name: "Hangar_roof", shape: .box(size: [43, 2, 40]), color: concrete),
                     at: [90, 13, 300])

        // Control tower, left of the lane; the trees are 10 m capsules with a
        // 1 m trunk, four a side at 50 m spacing, ±45 m off the centerline.
        addStructure(StaticStructure(name: "Tower", shape: .box(size: [8, 30, 8]), color: concrete),
                     at: [-90, 15, 250])

        for k in 0..<4 {
            let z: Float = 150 + 50 * Float(k)
            addStructure(StaticStructure(name: "Tree_L\(k)", shape: .capsule(radius: 0.5, height: 10), color: bark),
                         at: [-45, 5, z])
            addStructure(StaticStructure(name: "Tree_R\(k)", shape: .capsule(radius: 0.5, height: 10), color: bark),
                         at: [45, 5, z])
        }
    }

    /// Places one structure: the node into the scene graph (addChild registers
    /// the renderable) and its static body into `entities`, which buildScene
    /// installs once at the end.
    private func addStructure(_ structure: StaticStructure, at position: float3) {
        structure.setPosition(position)
        addChild(structure)
        if let body = structure.rigidBody {
            entities.append(body)
        }
    }
```

The positions are centers: a wall 12 m tall centered at y = 6 stands on the ground; the roof's bottom at y = 12 sits on the walls; the back wall at z = 321.5 spans 320–323, the walls and roof span 280–320.

No other wiring. `buildScene` installs `entities` once at the end (line 181), so the bodies join the world with everything else. `TouchdownReporter` already prints `other.gameObject?.getName()`, which is the structure's name, and classifies the hit from `stepStartVelocity` like any airframe contact. Debris balls get sphere-vs-box and sphere-vs-capsule contacts through the same path with no handler. Balls that spawn overlapping a structure are pushed out by the position correction over the first frames; accepted.

### Expected behavior (checked in-app; written into the commit message)

*(2026-09-11: the keyboard-free smoke run — the thirteen structures listed, the drop untouched — is in `3aabb82`'s message; the four checks below need the keyboard and stay the owner's under exit criterion 2.)*

- The structures render at their collider size and cast shadows like any opaque object. A ball rests on the roof at roof top + its radius.
- Taxi into a wall at 10–15 m/s: `[CRASH] F-22_CGTrader.fuselage hit Hangar_wallLeft at 12.30 m/s (gear down)`, then throttled `[Scrape]` lines while the nose stays pressed against it. The jet does not pass through and rebounds slightly (0.2).
- A wingtip into a tree while taxiing: `wings hit Tree_L2`. A wing over a wall with the fuselage clear: `wings hit Hangar_wallLeft`, the box-box path.
- Through the hangar opening at walking pace with the wings level: no line.

### Tests for this step

- [x] **File (new):** `ToyFlightSimulatorTests/GameObjects/StaticStructureShapeTests.swift` (pure, `.tags(.physics, .gameObjects)`): box maps to half extents; capsule maps to `halfHeight = height/2 − radius` (and back: 2·(halfHeight + radius) = height); a capsule with `height ≤ 2·radius` maps to `halfHeight 0` (a sphere-equivalent, which `LocalCollider` accepts); and, beyond the three, the mesh is the collider: `MDLMesh(boxWithExtent:)` and `MDLMesh(capsuleWithExtent:)` with a nil allocator (`makeMesh`'s constructor arguments) have bounds ±halfExtents and ±[r, halfHeight + r, r].
- [x] **File (new):** `ToyFlightSimulatorTests/Physics/StructureContactTests.swift` (Metal-free: a static box is `RigidBody(detachedAt:)` with one `.structure` box collider, `isStatic = true`, `shouldApplyGravity = false`, restitution 0.3; the aircraft is the detached F-22 compound from `CompoundBodyTests`; the broad phase stays ON, so the pairs come from its dynamic-vs-static loop as in the app):
  1. **Wall strike.** The F-22 at `[0, 5, -20]` flying +Z at 30 m/s into a 40 × 12 × 3 m wall centered at `[0, 6, 1.5]` (x from −20 to 20, its near face at z = 0), gravity off for a clean read. Within 60 updates: the first contact names `fuselage` against `wall`; `AirframeContactClassifier` on `stepStartVelocity` says `.impact` at 30 ± 0.5 m/s; the wall's position is `==` its start (statics never move); the aircraft ends on the near side (its origin's z below the fuselage's reach into the face) with `velocity.z ≤ 0` (stopped or rebounding at up to 0.2 × 30). Also pinned: exactly one impact — the 6 m/s rebound moves 5 cm per substep, so the nose (first contact at depth 0.05 m, 40 substeps in) clears the face on the next step.
  2. **Wing over a wall.** A 3 × 12 × 40 m wall centered at `[13.5, 6, 0]` (x from 12 to 15, along z); the F-22 at 5 m/s with its origin at `[8.5, 5, -10]`, so the right wing (to x = 15.1) is inside the wall's slab and the fuselage (to x = 9.85) is clear: the first contact names `wings` (box-box), not `fuselage`, and its point is `[12, 5.15, −11.2]` ± 0.05 — the wall's inner face clipped to the wing's outline, centered on the wing box, inside both boxes. The first draft's face-center rule put it at `[12, 6, 0]`, 8.5 m from the wing and 10 m ahead of an origin the wing sits behind; with D.3's lever arms that flips the yaw.
  3. **Ball on a roof.** A `SphereRigidBody` radius 0.5, restitution 0.2, dropped from 3 m onto a box top at y = 1: rests at 1.5 ± 0.02 after 5 s with gravity on.
  4. **Ball against a tree.** A sphere (radius 0.5, restitution 0.2) sliding along a ground plane at 3 m/s — no tangent force exists, so it keeps its speed — into a vertical capsule (radius 0.5, half height 4.5) centered at y 4.5, so its core (y 0…9) spans the resting ball's center and the closest core point is level with it: the first tree contact's normal is horizontal (|n.y| < 1e-3, ≈ `[−1, 0, 0]`), its B name is the tree's, and its A name is nil (a `SphereRigidBody`'s view). At the scene's y 5 the resting ball (7 mm into the ground) meets the core's lower end 7 mm above its own center, a 0.4° tilt outside the band.
- [x] Gate: full serial suite green; dry run byte-identical; the four in-app checks above. *(2026-09-11: build green; full serial suite 354 Swift Testing tests in 54 suites plus 20 XCTest cases; the regeneration dry run rewrote all six goldens byte-identical and the clean parity re-run is green; the keyboard checks are the owner's under criterion 2.)*

## Phase C non-goals (deferred, with their homes)

- Structures in other scenes, and a structure editor or spec file: `FlightboxWithPhysics` gets the airfield; a scene that wants more calls `addStructure`.
- Struts against structures (landing on a roof or a deck): D.4, `raycastStatics` with ray-vs-box.
- Continuous collision for thin walls at high speed: D.4; the walls are 3 m thick and the note at the call site says why.
- Sharing one mesh between identical parts: thirteen bespoke meshes are fine; revisit with a forest.
- Skipping the per-step collider rebuild for static bodies: the optimization row in Decisions.
- Terrain collision (`FlightboxWithTerrain`): a different problem (height field), not a box.

## Phase C exit criteria

1. - [x] **Narrow phase:** the nine box-box cases and the five capsule-box cases green; every other `NarrowPhaseTests` case green unedited; dry run byte-identical. *(`c6b4fba`, 2026-09-10: all green in the full serial run; the two pre-existing tests the listing extends — the metadata pair and the separated sweep — gained their box-box lines and nothing else changed; the dry run rewrote the six goldens byte-identical.)*
2. - [ ] **Structures:** `StaticStructureShapeTests` and `StructureContactTests` green; in-app, the four expected behaviors above hold, including "through the opening: no line". *(`3aabb82`, 2026-09-11: both suites green in the full serial run; the keyboard-free smoke run lists the thirteen structures and leaves the drop sequence unchanged. The four keyboard checks stay open for the owner's pass.)*
3. - [ ] **Statics never move:** asserted by the wall-strike test with `==`, and visible in-app after repeated impacts. *(`3aabb82`: the wall-strike test asserts it with `==`, and the roof and tree cases pin their bodies' positions too; the in-app half stays open for the owner's pass.)*
4. - [x] **No process-wide state**; the stress scene's per-call cost is unchanged (structures exist only in `FlightboxWithPhysics`). *(`3aabb82`, by inspection: `StaticStructure` holds no static state and each instance owns its mesh and body; `addAirfieldStructures` is private to `FlightboxWithPhysics`, so `PhysicsStressTestScene` is untouched.)*
5. - [ ] **CI green** on both commits (serial app-hosted run, as configured).

---

# Phase D — ground handling and angular dynamics

Implements combined doc §4.5 items 1–3 and the Phase B non-goals that were handed to Phase D (tangent friction, brakes, steering, torque from asymmetric gear contact). Item 4 of §4.5 lands in its smallest form in D.3 (accumulated impulses over one pair's contacts, no persistence and no warm start); friction cones on contacts and item 5 (joints) are not planned in code here; D.4 lists them with the trigger that would start each. The §4.6 Jolt gate is held before D.1 (first row of Decisions).

At the end of this phase:

- the jet stops: wheel brakes on the mains (B key), lateral tire grip that kills a crab and lets the nose lead the velocity, rolling resistance, all as forces at the wheel contact patches;
- the jet rotates under physics: `RigidBody` carries angular velocity, torque, and an inverse inertia tensor; strut and tire forces act at their points and pitch and roll the body; contact impulses have lever arms; the nose settles onto the nose gear after the mains, a one-wheel touchdown rolls level, braking dips the nose, nosewheel steering turns the jet at taxi speed;
- in the air the jet feels the same: the kinematic lag filter becomes a rate controller that produces the torque the filter's ODE implies, with the same maximum rates and time constants;
- every body that is not an aircraft with a flight model is unchanged, bit for bit: infinite inertia is the default, and a pair of such bodies takes the response's linear fast path, the Phase A code verbatim.

**What Phase D does not change:** the flight model's aerodynamics (no aerodynamic moments: pitch stability, roll damping, and yaw stability are still the controller's job), the narrow phase except one capsule-plane manifold, the collider and strut specs' geometry, the overlay, and the goldens.

## Commits

| Commit | Steps | Gate | Tests |
|---|---|---|---|
| **D-angular-plumbing** ✅ `14c0bda` | D.1 | Plumbing. Every body keeps infinite inertia, so the impulse takes its linear fast path (the Phase A arithmetic verbatim) and the response still acts at the deepest contact only: dry run byte-identical, every existing suite green unedited (the `zeroForces` test gains one assertion). No in-app change. | `AngularIntegrationTests` (new, with the long-run orthonormality soak); additions to `RigidBodyTests`, `CollisionResponseTests`, `PhysicsSolverTests` |
| **D-tires** | D.2 | Behavior on the struts only: dry run byte-identical. In-app: brakes stop the jet from 40 m/s in about 200 m; it holds still on the runway, at idle and against thrust under the brake limit; a crab settles; Q/E turn it at taxi speed (the kinematic yaw filter is still in charge); gear-up belly slides as before (contacts have no friction). | `TireModelTests` (new, pure); six additions to `GearSuspensionWorldTests`; `LandingGearSuspensionTests` signature and force-direction edits |
| **D-attitude** | D.3 | Behavior on the aircraft and on pairs with more than one contact: dry run byte-identical (a single-contact pair, so every sphere pair, keeps the one-pass path). In-app: flight feels the same; the parked jet does not creep; touchdown settles nose-last; a one-wheel arrival rolls level; braking dips the nose; steering works; a belly slap rests without rocking; a rotation-only wing strike prints `[CRASH]`. | `AttitudeRateControllerTests` (new); `GearSuspensionWorldTests` (seven additions, three edits, the controller in the rig); `CollisionResponseTests` (the pair solve); `StructureContactTests` (point-velocity classification); `NarrowPhaseTests` (capsule manifold); `CompoundBodyTests` and `NarrowPhaseTests` call-site edits for the appending `shapeVsPlane` |

## Decisions

| Decision | Why |
|---|---|
| The §4.6 Jolt gate is held here, before D.1: build natively | The research doc puts the go/no-go before Phase D; the first draft of this document had it inside D.4. Held now: the goal of this plan is owning the solver at the fidelity each step asks for (three raycast struts, one aircraft, one pair solve), not shipping a fleet of vehicles, so Phase D is native. The Jolt spike stays the D.4 fallback if a D.4 trigger fires; everything below the authoring layer (specs, gear, events, classification, overlay, tests) survives either way. |
| Angular state lives on `RigidBody`, infinite inertia by default | One class, no subclass (the D1 verdict again). The zero inverse inertia makes every new term in the impulse exactly zero, so existing bodies are bit-identical through the response, and an aircraft opts in by receiving a tensor. |
| Orientation stays on the node; physics rotates it through `RigidBody.rotate(by:)`; detached bodies keep a matrix of their own | Mirrors position: `pose()` reads the node, the integrator writes it. The attached camera is a child, so it follows within the frame with no publish step, and there is no quaternion on the body to keep in sync with the node. Codex's `setPhysicsPose` publish (research §4.5 item 1) was for a design where the body owned the pose; here the node does. |
| `rotate(by:)` composes through a normalised quaternion | `Node.rotate` left-multiplies float matrices and never renormalises; the kinematic path gets away with it because a settled aircraft snaps its rates to zero and stops writing. The physics path writes every substep, and D.3 uses `R.transpose` as the inverse and `R.up` as a unit ray direction. Composing as quaternions, normalising, and rebuilding the matrix keeps R orthonormal for the life of the process; a 72 000-substep soak pins it. Pose ownership does not move. |
| Semi-implicit Euler for rotation in both solvers, no gyroscopic term; angular velocity integrates with the forces and before the contact response, orientation with the positions — in both paths | Box2D and Jolt order it this way: velocities from forces, then constraints, then poses. The first draft put both angular updates after the contact response, so a strut or controller torque applied this substep would rotate a just-resolved contact back into the ground and the response would only see it next substep; the second draft fixed `EulerSolver` and kept Verlet's two halves after its position update for symmetry with the linear lag of B.2, which reintroduced the same defect in the production solver. Split in two in both: `EulerSolver` integrates ω right after `applyForces` and the orientation right after `moveObjects`; in the `.HeckerVerlet` path `PhysicsWorld.step` integrates ω after the force hooks and before `resolveCollisions`, and `VerletSolver.step` rotates after its position update. The linear Verlet arithmetic is untouched and infinite-inertia bodies skip both halves, so the goldens cannot move. Velocity Verlet's split buys nothing for rotation, and the gyroscopic term ω × (Iω) is negligible at aircraft rates while making an explicit step conditionally stable. |
| The body origin is the center of mass; no offset field | The F-22 strut spec already balances about the origin: the nose carries 0.9/6.1 = 14.8% of the weight, the real jet's split. A `centerOfMass` field would be unread until an aircraft with an off-origin model appears; adding it later is additive. |
| Inertia is authored on the `FlightModel`, synced to the body like mass | Mass lives there today. One `syncMassProperties()` replaces the two mass mirrors in `Aircraft` and adds the tensor. Aircraft without a flight model keep infinite inertia and the kinematic path (the F-16 wingman, `FreeCamFlightboxScene`'s jet). |
| Attitude becomes a rate controller that produces torque; the kinematic filter stays for aircraft without flight physics | The filter's law, dω/dt = (ω_cmd − ω)/τ, multiplied by I is a torque. With no other torque one semi-implicit substep reproduces the filter's exact-exponential update, so the in-air response is unchanged (tested). Gear and contact torques add on top and are damped with the same time constants. |
| No airspeed scaling of control authority | Considered. At zero airspeed the controller acts as rate damping, which is what makes a one-wheel touchdown roll level at a plausible 20°/s instead of snapping. The pilot can pitch the parked jet against its springs (about 10° at full stick); the kinematic model lets the pilot pitch it without limit today. One multiplier if the quirk ever matters. |
| Contact response in two commits: D.1 adds lever arms behind a linear fast path and keeps the deepest-contact impulse; D.3 solves each pair's contacts together | Hecker's full formula (research §3.1 item 2). D.1 is plumbing, so its response acts where Phase A's did, at the deepest contact, and a pair of infinite-inertia bodies runs the Phase A block verbatim instead of the general form with zero angular terms (the zeros are exact for finite inputs, but the fast path is cheaper for the stress scene and makes the byte-identity argument trivial). Switching to every contact is behavior even with infinite inertia whenever a pair's normals differ (a ball wedged between fuselage and wing), so it lands in D.3 with the capsule manifold that needs it. One Gauss-Seidel pass is not enough there: with the F-22's pitch inertia the lever arms dominate the effective mass, and after one pass over the two caps the first is approaching again at about the speed it arrived (0.52 m/s from 0.5); a 5 s simulation of the exact algorithm rocked at a steady 0.029 rad/s, over the test's own 0.02 band. D.3 iterates a pair's contacts eight times with accumulated, non-negative impulses and a restitution target captured before the solve (Catto, GDC 2006): four passes bring the rate to 0.008, eight to rest. Pairs with one contact keep the single pass — a second pass on a single contact is not byte-identical (float32 leaves the residual approach negative in about four contacts in ten), so that gate is what keeps every sphere golden fixed. Persistence and warm starting stay in D.4. |
| Capsule-plane emits both end caps | A body with pitch freedom resting on its belly needs two points or it rocks between the ends. Box-plane keeps its one corner: the aircraft's boxes (wings, empennage) sit above the fuselage capsule's underside, so they meet the ground at a corner when rolled or pitched far enough, never flat on a face. |
| Tires: holding Coulomb friction at the wheel patch with a friction circle, no wheel spin state; the strut load acts along the ground normal | The first draft regularised friction (force proportional to slip below 0.5 m/s). That is zero at rest, so nothing holds: any tangent force creeps at the speed where μN·v/0.5 balances it — 0.2 m/s at idle from the −0.45° stance alone (a strut force along body up has a 2.3 kN runway component there), and with the brakes on 0.19 m/s per 50 kN of thrust where the text promised no motion below 130 kN. Now the loaded wheels are solved together as sequential impulses (Catto, GDC 2006) against one predicted end-of-substep velocity, linear and angular, with this substep's other forces and torques included: each wheel in turn applies the impulse that brings its patch's tangent velocity to rest, clamped to the friction circle, and the prediction is updated as each lands. At rest that is exactly the force needed and no more, so the parked jet holds at idle on rolling resistance and holds against thrust until it exceeds the brake limit, then slides; a wheel at its limit leaves the rest of the demand to the wheels after it. The second draft gave each wheel a fixed share of the demand, so the unbraked nose wheel's unmet share went to nobody once its rolling-resistance limit bound: 89.8 kN opposed 100 kN of thrust with the brakes on and the jet crept 1.6 cm in 5 s against the test's own 1 cm, under either solver. The joint solve opposes all 100 (nose 0.6, mains 68.1 and 31.2 kN in strut order — any split that sums to the demand stops the jet, and the mains' asymmetry lives in the redundant part of the split) and moves nothing. Rolling resistance is the unbraked longitudinal limit; brakes raise it. The strut's load is applied along the ground-hit normal, as Bullet's raycast vehicle applies its suspension impulse, so a pitched or rolled stance pushes nothing along the runway; the compression is still measured along the strut. Lift unloads the brakes for free. |
| Brakes on the mains only, B key held = full | Real aircraft brake the mains. The keyboard is binary anyway; a controller axis can map to the same 0…1 command later. |
| Nosewheel steering is a steer angle on the nose strut following the yaw input; the yaw controller stays | The turn is torque from the nose tire's lateral force at 5.2 m ahead of the origin: physical, and it exists whether or not the controller has authority. Releasing the key leaves the controller commanding zero yaw rate, which stops the turn. Both use the yaw command's sign. |
| D.2 (tires) before D.3 (rotation) | Ground handling is the visible gap after Phase B and works without torque. Because D.2 already applies its forces at the contact patch through `addForce(_:atWorldPoint:)`, D.3 makes them torque-correct with no rewrite. |
| No aircraft golden; expectations live in `GearSuspensionWorldTests` as physics numbers | Keeps the harness sphere-only and every commit's golden gate a pure dry run. Pitch −0.45°, loads 15/85, and stopping distances read as physics in a test; in JSON they would not. |
| Balls keep infinite inertia | Nothing torques a frictionless sphere: its contact points lie on the line through its center. Giving spheres a tensor changes nothing visible and would not be byte-identical on principle. Revisit with contact friction (D.4). |
| `raycastStaticPlanes` returns a `RayHit` (distance and normal) | The tire needs the ground normal. Phase B's "distance only" decision said nothing read a normal yet; now something does. |
| `SuspensionStrut` gains defaulted `hasBrakes` and `maxSteerAngle` | Per-strut facts, not shared constants. Defaulted trailing properties keep the memberwise init source-compatible for the spec and the tests. |
| `TireModel`'s constants are `static let`s in one enum | Like `HeckerCollisionResponse`'s: one place to tune. |
| Crash classification reads the relative velocity at the contact point | `stepStartVelocity` is the origin's velocity. Once the body rotates, a wing can strike a wall at 3.3 m/s while the origin is still (a 0.5 rad/s yaw at 6.6 m), and the classifier would print `[Scrape]`. D.3 evaluates v + ω × r at the contact point from both bodies' step-start state, so a moving ball into a parked jet also classifies by the closing speed. |
| `applyPlayerSideMove` runs only on the kinematic path | It teleports the node sideways (A/D), bypassing the body's velocity; on the physics path it would slide the jet through its own tire model. Gated with the throttle move under `hasFlightPhysics`. One line to revert if the strafe is wanted as a debug control. |
| A nil `flightModel` restores infinite inertia | `syncMassProperties` guarded on both being present, which left a finite tensor behind when a model was removed while `hasFlightPhysics` fell back to the kinematic filter: two writers to the rotation. Nothing sets it to nil today; the else branch costs three lines. |

## Step D.1 — angular state, forces at points, lever-arm impulses — D-angular-plumbing ✅ (landed 2026-09-11, `14c0bda`)

Everything here is inert until a body gets a finite inertia tensor, which nothing does until D.3. The commit is plumbing: the argument for byte-identity is written into each listing, and the dry run checks it.

Line numbers are as of `82f852b`; Phase C touches none of these files. D.1 touches `PhysicsWorld.swift` once (one line at 99), which D.2's line numbers account for.

**Landed 2026-09-11** (`14c0bda`), goldens untouched (regeneration dry run byte-identical: no body has finite inertia, so every pair took the fast path). The owner transcribed the listings and added one helper; review found one transcription defect and two loose ends, fixed before the tests ran: `EulerSolver.step` had the orientation half after `moveObjects` but not the angular-velocity half after `applyForces`, so under `.NaiveEuler` a torque never reached ω — inert today, but the one-substep and response-sees-the-torque tests below fail on it for that solver; `PhysicsEntity.zeroForce()` was still present with its only caller gone; and the Euler solver's legacy-code comment still named `applyCollisionResponse`. The listings' comments had not been carried over and were added throughout; beyond the listings, `Contact.point`'s doc comment no longer calls the point unused, `EulerSolver.step`'s doc comment names the angular halves, and the two Verlet-path call sites carry marker comments. The owner's deviation, kept and folded into the listings: `getInverseMassStats` computes the pair's inverse masses and their sum once in `resolvePair` and passes them to `correctPosition` and `applyImpulse` as the `InverseMassStats` tuple typealias — a per-pair fact that D.3's eight iterations would otherwise recompute (D.3.5's `resolvePair` listing is synced; its `solveManifold` still computes its own and can take the tuple at transcription). Tests as listed, every expected value reproduced in a scratch script first, all green first run: `AngularIntegrationTests` (7, the six world-stepping ones on both solvers), `RigidBodyTests` (5), `CollisionResponseTests` (2), and the `torque` assertion in `zeroForcesClearsAllForces`. The soak's discriminating claim was reproduced too: over 72 000 substeps the bare matrix product drifts to 4.7e-5 in column length, 3.4e-5 in the column dot products, and 9.1e-5 in determinant; the quaternion path to 1.2e-7, 7.7e-10, and 4.8e-7. Full serial suite 368 Swift Testing tests in 55 suites plus 20 XCTest cases; dry run byte-identical; clean parity re-run green. CLAUDE.md's Physics paragraph carries the D.1 entry from the list at the end of this document. Line shifts for later steps: `PhysicsWorld.swift` grew by seven lines (the snapshot line and the ω half, with their comments), not the one D.2 accounted for, so `raycastStaticPlanes` sits at 146–161 (D.2's note is corrected below); `RigidBody.swift` grew by 95 lines and `HeckerCollisionResponse.swift` by 79 — D.2 and D.3 locate their edits in those files by the text quoted. No in-app change: plumbing, and the owner ran the game before the review. The listings below are the shipped code.

- [x] **Edit:** `Physics/World/RigidBody.swift`, inserted after line 81 (`var stepStartVelocity`), before the world-collider cache comment at 83:

```swift
    /// Angular state, world frame: angular velocity in rad/s and the torque
    /// accumulated this substep in N·m about the body origin, zeroed with
    /// `force`. The body origin is the center of mass: every lever arm is
    /// measured from it (the F-22 strut spec was authored that way;
    /// AircraftLandingGearSpecTests pins its 15/85 static load split).
    var angularVelocity: float3 = .zero
    var torque: float3 = .zero
    
    /// Inverse inertia tensor in body axes. The default, the zero matrix, is
    /// infinite inertia: physics never rotates the body. That is every body
    /// before D.3 and every body not given a tensor after it (balls, debris,
    /// spec-less aircraft); with it the lever-arm terms of the response are
    /// exactly zero, so those bodies' arithmetic is unchanged.
    static let infiniteInertia = float3x3(diagonal: .zero)
    var inverseInertiaLocal: float3x3 = RigidBody.infiniteInertia
    var hasFiniteInertia: Bool { inverseInertiaLocal != Self.infiniteInertia }
    
    /// I⁻¹ in world axes, R · I⁻¹ · Rᵀ. The zero matrix for an
    /// infinite-inertia body, without reading the pose.
    func inverseInertiaWorld() -> float3x3 {
        guard hasFiniteInertia else { return Self.infiniteInertia }
        let rotation = pose().rotation
        return rotation * inverseInertiaLocal * rotation.transpose
    }
    
    /// A force acting at a world point: the force itself plus its torque
    /// about the origin. Strut and tire forces use this (D.2), so they pitch
    /// and roll the body as soon as it has finite inertia (D.3).
    func addForce(_ force: float3, atWorldPoint point: float3) {
        self.force += force
        torque += cross(point - getPosition(), force)
    }

    /// Velocity of a world point on the body: v + ω × r.
    func velocity(atWorldPoint point: float3) -> float3 {
        velocity + cross(angularVelocity, point - getPosition())
    }
    
    /// Angular velocity at the top of the current step, next to
    /// stepStartVelocity and written with it by PhysicsWorld. Zero for every
    /// body until D.3.
    var stepStartAngularVelocity: float3 = .zero
    
    /// Pre-response velocity of a world point: the step-start pair combined.
    /// Crash classification reads this at the contact point (D.3), where the
    /// origin's velocity alone misses a rotating wing.
    func stepStartVelocity(atWorldPoint point: float3) -> float3 {
        stepStartVelocity + cross(stepStartAngularVelocity, point - getPosition())
    }
```

- [x] **Edit:** the same file, rotation storage and writes, inserted after `getPosition()` (line 186), before `getAABB()` at 188:

```swift
    /// Rotation of a detached body. Attached bodies keep theirs on the node,
    /// as with position.
    private var standaloneRotation: float3x3 = matrix_identity_float3x3
    
    /// Rotates the body by the world-frame angular displacement ω·h (its
    /// direction is the axis, its length the angle). Attached bodies rotate
    /// their node, which dirties the subtree so the attached camera follows
    /// within the frame; detached bodies rotate their own matrix. Invalidates
    /// the world colliders like setPosition (the Phase A note: a rotation
    /// written mid-step must invalidate). The composition goes through a
    /// normalised quaternion and the matrix is rebuilt from it: a matrix
    /// product per substep for the life of the process drifts from
    /// orthonormal, and D.3 uses R.transpose as the inverse and R.up as a
    /// unit ray. Node.rotate's bare product stays for the kinematic path,
    /// which stops writing once settled. The world-axis step multiplies on
    /// the left, as Node.rotate(deltaAngle:axis:) composes its matrices. A
    /// TestRigidBody (nil GameObject, nil standalonePosition) falls into the
    /// node branch and does nothing, which is right: it never has finite
    /// inertia.
    func rotate(by delta: float3) {
        let angle = simd_length(delta)
        guard angle > 0 else { return }
        invalidateWorldColliders()
        let step = simd_quatf(angle: angle, axis: delta / angle)
        let composed = float3x3(simd_normalize(step * simd_quatf(pose().rotation)))
        if standalonePosition != nil {
            standaloneRotation = composed
        } else {
            gameObject?.setRotation(simd_quatf(composed))
        }
    }
    
    /// Absolute rotation, for authoring and tests. Node.setRotation(_:) goes
    /// through the rotationMatrix setter, which dirty-flags like rotate.
    func setRotation(_ rotation: float3x3) {
        invalidateWorldColliders()
        if standalonePosition != nil {
            standaloneRotation = rotation
        } else {
            gameObject?.setRotation(simd_quatf(rotation))
        }
    }
```

Both branches compose the same quaternion product (the world-axis step on the left, as `Node.rotate(deltaAngle:axis:)` composes its matrices) and write the matrix rebuilt from its normalised form; `Node.setRotation(_:)` goes through the `rotationMatrix` setter, which dirty-flags like `rotate`. `TestRigidBody` (nil GameObject, nil `standalonePosition`) falls into the node branch and does nothing, which is right: it never has finite inertia.

- [x] **Edit:** `pose()` (lines 218–231): the detached branch returns the body's own rotation, and the doc comment's last sentence becomes "Detached bodies, and attached bodies whose GameObject was released, use their own rotation (identity until rotated) at getPosition()."

```diff
         guard let node = gameObject else {
-            return (getPosition(), matrix_identity_float3x3, 1.0)
+            return (getPosition(), standaloneRotation, 1.0)
         }
```

- [x] **Edit:** `Physics/Solver/PhysicsSolver.swift`, `zeroForces` (lines 15–21) clears torque too, and `PhysicsEntity.zeroForce()` (`PhysicsEntity.swift:43–45`), its only caller gone, is deleted:

```swift
extension PhysicsSolver {
    /// End of step: forces and torques are per-substep accumulators.
    public static func zeroForces(entities: [RigidBody]) {
        for entity in entities {
            entity.force = .zero
            entity.torque = .zero
        }
    }
}
```

- [x] **File (new):** `ToyFlightSimulator Shared/Physics/Solver/AngularIntegration.swift`

```swift
//
//  AngularIntegration.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/11/26.
//

/// Rotation step shared by both solvers: semi-implicit Euler in two halves,
/// ω += I⁻¹_world · τ · h with the forces and a rotation by ω · h with the
/// positions, so the contact response between them sees this substep's
/// torques (Box2D and Jolt order it this way: velocities, constraints,
/// poses). Bodies with infinite inertia (the default) are skipped, so their
/// step is unchanged. No gyroscopic term (ω × Iω): small at aircraft rates,
/// and without it the explicit update has no stability condition of its own.
enum AngularIntegration {
    static func integrateAngularVelocity(entities: [RigidBody], deltaTime: Float) {
        for entity in entities where !entity.isStatic && entity.hasFiniteInertia {
            entity.angularVelocity += entity.inverseInertiaWorld() * entity.torque * deltaTime
        }
    }
    
    static func integrateOrientation(entities: [RigidBody], deltaTime: Float) {
        for entity in entities where !entity.isStatic && entity.hasFiniteInertia {
            entity.rotate(by: entity.angularVelocity * deltaTime)
        }
    }
}
```

- [x] **Edit:** `Physics/Solver/EulerSolver.swift`, the pair-consuming `step` (lines 23–33): the angular-velocity half goes right after `applyForces` (line 26), before the contact loop, and the orientation half right after `moveObjects` (line 31), before `zeroForces`:

```swift
        applyForces(deltaTime: deltaTime, gravity: gravity, entities: entities)
        AngularIntegration.integrateAngularVelocity(entities: entities, deltaTime: deltaTime)
        contactsScratch.removeAll(keepingCapacity: true)
        for (a, b) in collisionPairs {
            HeckerCollisionResponse.resolvePair(a, b, contacts: &contactsScratch)
        }
        moveObjects(deltaTime: deltaTime, entities: entities)
        AngularIntegration.integrateOrientation(entities: entities, deltaTime: deltaTime)
        zeroForces(entities: entities)
```

and the Verlet path, whose response runs in `PhysicsWorld.step` before `VerletSolver.step`: the angular-velocity half goes into `Physics/World/PhysicsWorld.swift`, the `.HeckerVerlet` case of `step` (lines 122–125 once the snapshot line below is in), between the force hooks and the response, so the response sees this substep's torques as it does under Euler; the orientation half goes into `Physics/Solver/VerletSolver.swift` before `zeroForces(entities: entities)` (line 55). The linear Verlet arithmetic is not touched (its one-substep lag stays as B.2 accepted it) and both halves skip infinite-inertia bodies, so every golden holds:

```swift
            case .HeckerVerlet:
                // ω from this substep's torques before the response, as
                // EulerSolver orders it; VerletSolver.step rotates after its
                // position update. Infinite-inertia bodies skip both halves.
                AngularIntegration.integrateAngularVelocity(entities: entities, deltaTime: deltaTime)
                HeckerCollisionResponse.resolveCollisions(collisionPairs: pairs,
                                                          contactsScratch: &contactsScratch)
                VerletSolver.step(deltaTime: deltaTime, gravity: Self.gravity, entities: entities)
```

```swift
        // Orientation with the positions. The other half, ω from this
        // substep's torques, ran in PhysicsWorld.step before the contact
        // response, as EulerSolver orders it.
        AngularIntegration.integrateOrientation(entities: entities, deltaTime: deltaTime)
        zeroForces(entities: entities)
```

- [x] **Edit:** `Physics/World/PhysicsWorld.swift`, `step` (line 99), next to the linear snapshot:

```swift
            // Step-start snapshot, linear and angular together: what the
            // crash classifier reads (RigidBody.stepStartVelocity(atWorldPoint:)).
            entity.stepStartVelocity = entity.velocity
            entity.stepStartAngularVelocity = entity.angularVelocity
```

- [x] **Edit:** `Physics/CollisionResponse/HeckerCollisionResponse.swift`, `resolvePair` (lines 33–51) and `applyCollisionResponse` (lines 53–95). The response splits into a position half and an impulse half; the impulse gains lever arms behind a linear fast path and still runs once, at the deepest contact (D.3 iterates it over a pair's contacts). The pair's inverse masses and their sum are computed once by `getInverseMassStats` and passed to both halves as the `InverseMassStats` tuple — the owner's addition, kept:

```swift
    /// One narrow phase per pair: filter, generate contacts, mark the pair as
    /// collided, respond at the deepest contact, then fire onContact for every
    /// contact (handlers see post-response state). Shared with EulerSolver.
    /// D.3 replaces the single impulse with a solve over the pair's contacts.
    static func resolvePair(_ entityA: RigidBody, _ entityB: RigidBody, contacts: inout [Contact]) {
        guard entityA.shouldCollide(with: entityB), !entityA.collidedWith.contains(ObjectIdentifier(entityB)) else { return }
        
        let firstNew = contacts.count
        guard let deepest = NarrowPhase.generateContacts(entityA, entityB, into: &contacts) else { return }
        
        entityA.collidedWith.insert(ObjectIdentifier(entityB))
        entityB.collidedWith.insert(ObjectIdentifier(entityA))
        
        // Position, then impulse, at the deepest contact: the Phase A
        // sequence, now in two functions so D.3 can iterate the impulse. The
        // inverse masses are a property of the pair, computed once for both.
        let invMassStats = getInverseMassStats(entityA, entityB)
        correctPosition(entityA, entityB, contact: contacts[deepest], inverseMassStats: invMassStats)
        applyImpulse(entityA, entityB, contact: contacts[deepest], inverseMassStats: invMassStats)
        
        for contact in contacts[firstNew...] {
            entityA.onContact?(contact, entityB)
            entityB.onContact?(contact.flipped, entityA)
        }
    }
    
    /// A pair's inverse masses and their sum: the split both halves of the
    /// response use. A static body has inverse mass 0, so it neither moves
    /// nor changes velocity; a zero sum (two statics) means nothing to do.
    typealias InverseMassStats = (inverseMassA: Float, inverseMassB: Float, inverseMassSum: Float)
    
    /// Computed once per pair in resolvePair rather than in each half: D.3
    /// iterates applyImpulse over a pair's contacts, and the masses do not
    /// change between iterations.
    static func getInverseMassStats(_ entityA: RigidBody, _ entityB: RigidBody) -> InverseMassStats {
        let invMassA: Float = entityA.isStatic ? 0 : 1 / entityA.mass
        let invMassB: Float = entityB.isStatic ? 0 : 1 / entityB.mass
        let invMassSum = invMassA + invMassB
        return (invMassA, invMassB, invMassSum)
    }
    
    /// Moves the bodies apart along the normal by β × (depth − slop), split by
    /// inverse mass: only the penetration beyond the slop, and only a
    /// β-fraction of it per step. Linear only: the angular share of position
    /// correction belongs to a manifold solver (D.4), if one is ever built.
    static func correctPosition(_ entityA: RigidBody,
                                _ entityB: RigidBody,
                                contact: Contact,
                                inverseMassStats: InverseMassStats) {
        let n = contact.normal                       // unit, from B toward A
        guard inverseMassStats.inverseMassSum > 0 else { return }         // two statics: nothing to move

        let correction = positionCorrectionBeta * max(0, contact.depth - penetrationSlop) / inverseMassStats.inverseMassSum
        guard correction > 0 else { return }
        if !entityA.isStatic {
            entityA.setPosition(entityA.getPosition() + n * (correction * inverseMassStats.inverseMassA))
        }
        if !entityB.isStatic {
            entityB.setPosition(entityB.getPosition() - n * (correction * inverseMassStats.inverseMassB))
        }
    }
    
    /// Normal impulse at the contact point, Hecker's full form: the relative
    /// velocity and the effective mass include the lever arms r = point −
    /// origin through each body's world inverse inertia. A pair with no
    /// finite inertia on either side takes the linear path first: the Phase A
    /// block verbatim, so its arithmetic is unchanged by construction. (The
    /// general form's angular terms are exactly zero for such a pair too, but
    /// the fast path skips two position reads, eight cross products, and four
    /// matrix products per sphere contact, and makes the golden argument a
    /// reading exercise.) Symmetric in inverse mass: a static body neither
    /// moves nor changes velocity. In the general path the lever arms are
    /// measured from the post-correction origins; the difference is the
    /// β-fraction of a penetration, millimeters.
    static func applyImpulse(_ entityA: RigidBody,
                             _ entityB: RigidBody,
                             contact: Contact,
                             inverseMassStats: InverseMassStats) {
        let n = contact.normal                       // unit, from B toward A
        guard inverseMassStats.inverseMassSum > 0 else { return }
        
        guard entityA.hasFiniteInertia || entityB.hasFiniteInertia else {
            // Linear fast path: every body before D.3, every ball after it.
            // Impulse only when approaching (n points toward A, so approaching
            // means relative velocity along −n); separating contacts are skipped.
            let relativeVelocity = entityA.velocity - entityB.velocity
            let approach = dot(relativeVelocity, n)
            guard approach < 0 else { return }

            // Restitution only above the threshold; below it e = 0, so the
            // normal velocity is cancelled exactly (the support impulse).
            let e = -approach > restitutionVelocityThreshold ? min(entityA.restitution, entityB.restitution) : 0

            // Always applied: at rest this is the per-step support impulse
            // (about m·g·dt), the normal force integrated over the step.
            let j = -(1 + e) * approach / inverseMassStats.inverseMassSum
            if !entityA.isStatic {
                entityA.velocity += n * (j * inverseMassStats.inverseMassA)
            }
            if !entityB.isStatic {
                entityB.velocity -= n * (j * inverseMassStats.inverseMassB)
            }
            
            return
        }
        
        // Lever arms from each origin to the contact point. Impulse only when
        // approaching AT THE POINT: each body's velocity there is v + ω × r,
        // so a body spinning into the contact counts even if its origin is
        // still (n points toward A, so approaching means along −n).
        let rA = contact.point - entityA.getPosition()
        let rB = contact.point - entityB.getPosition()
        let approach = dot(entityA.velocity(atWorldPoint: contact.point) - entityB.velocity(atWorldPoint: contact.point), n)
        guard approach < 0 else { return }
        
        // Restitution only above the threshold; below it e = 0 and the normal
        // velocity at the point is cancelled exactly (the support impulse).
        let e = -approach > restitutionVelocityThreshold ? min(entityA.restitution, entityB.restitution) : 0
        
        // Effective mass along n at the point: the inverse-mass sum plus each
        // body's angular term ((I⁻¹ (r × n)) × r) · n — how much of a unit
        // impulse at the point goes into spinning the body rather than
        // pushing it. A static body contributes nothing on either count.
        let invInertiaA = entityA.isStatic ? RigidBody.infiniteInertia : entityA.inverseInertiaWorld()
        let invInertiaB = entityB.isStatic ? RigidBody.infiniteInertia : entityB.inverseInertiaWorld()
        
        let angularA = dot(cross(invInertiaA * cross(rA, n), rA), n)
        let angularB = dot(cross(invInertiaB * cross(rB, n), rB), n)
        let j = -(1 + e) * approach / (inverseMassStats.inverseMassSum + angularA + angularB)
        
        // Linear change j/m along n; angular change I⁻¹ (r × j n). B takes
        // the opposite signs because n points toward A.
        if !entityA.isStatic {
            entityA.velocity += n * (j * inverseMassStats.inverseMassA)
            entityA.angularVelocity += invInertiaA * cross(rA, n * j)
        }
        
        if !entityB.isStatic {
            entityB.velocity -= n * (j * inverseMassStats.inverseMassB)
            entityB.angularVelocity -= invInertiaB * cross(rB, n * j)
        }
    }
```

Why this is byte-identical for every current body: no body has finite inertia, so every pair takes the fast path, which is steps 2–4 of the old `applyCollisionResponse` with the same operands in the same order; `correctPosition` is its step 1 verbatim; and `resolvePair` still responds once, at the deepest contact, before the events. (The general path would also be exact for these bodies — x + 0 and 0 · x are exact for finite x, and a −0 where a +0 was cannot change a compare or a product — but the fast path makes that a reading exercise and saves the work.) In the general path the lever arms are measured from the post-correction origin; the difference is the β-fraction of a penetration, millimeters.

The `applyCollisionResponse` name goes; nothing outside this file called it. Hoisting the inverse masses into `getInverseMassStats` computes the same three values once instead of twice, in the same order for each use; the dry run confirmed byte-identity with the helper in place.

### Tests for this step (Metal-free, `.tags(.physics)`)

- [x] `RigidBodyTests` additions (5), shipped as listed with extra pins per case — the default `inverseInertiaWorld()` is the zero matrix; a force through the origin adds no torque and the lever arm is measured from the body's position; the collider authored 1 m ahead lands 1 m right after the yaw, a zero displacement neither writes nor invalidates, and a second quarter turn about world Y brings forward to −Z (left composition); `velocity(atWorldPoint:)` is checked alongside the step-start form —: the default tensor is infinite and `hasFiniteInertia` is false; `addForce(_:atWorldPoint:)` on a detached body at the origin with force `[0, 10, 0]` at `[2, 0, 0]` gives torque `[0, 0, 20]` and the same force; `rotate(by: [0, .halfPi, 0])` on a detached body turns `pose().rotation.forward` to `[1, 0, 0]` within 1e-5 and marks the world colliders dirty (the rebuild-count discipline of `worldColliderCacheRebuildDiscipline`); `inverseInertiaWorld()` for `inverseInertiaLocal = diag(1, 2, 3)` after `setRotation` by 90° about Y is `diag(3, 2, 1)` within 1e-5; `stepStartVelocity(atWorldPoint:)` with `stepStartVelocity = [1, 0, 0]` and `stepStartAngularVelocity = [0, 1, 0]` at `[0, 0, 2]` from the origin is `[3, 0, 0]`.
- [x] **File (new):** `ToyFlightSimulatorTests/Physics/AngularIntegrationTests.swift` (7, parameterized over `.NaiveEuler` and `.HeckerVerlet` where a world is stepped): an infinite-inertia body with a constant torque hook never rotates and keeps `angularVelocity == .zero`; a detached body with `inverseInertiaLocal = diag(0.5)`, gravity off, and a hook adding torque `[2, 0, 0]` has `angularVelocity.x == fixedDelta` after one substep (`0.5 · 2 · h`) and has rotated about X by `h·h` rad; a static body with finite inertia and torque does not rotate; `torque` is zero after every step (`zeroForces`); the halves are separable — `integrateAngularVelocity` alone changes ω and not the pose, `integrateOrientation` alone the pose and not ω (the order the solvers rely on); **the response sees this substep's torque** (both solvers): a detached body with one sphere collider resting on a static plane body, `inverseInertiaLocal = diag(0.5)`, gravity off, a hook adding torque `[2, 0, 0]`, and an `onContact` handler that records `angularVelocity` as it fires — the record is `[fixedDelta, 0, 0]` (0.5 · 2 · h): a sphere's contact impulse has no lever arm, so the handler sees the torque's own half-step, which the second draft's Verlet order recorded as zero; **the orthonormality soak**: a detached body with `inverseInertiaLocal = diag(1)`, gravity off, `angularVelocity = [0.3, 0.5, 0.7]` and no torque, stepped for 72 000 substeps (ten minutes at 120 Hz, a few milliseconds of test time): every column of `pose().rotation` has unit length within 1e-5, the columns are pairwise orthogonal within 1e-5, and the determinant is 1 within 1e-5. The bare matrix product drifts past that; the quaternion path does not. *(Shipped as listed. The rotation about X is checked against a hand-written R_x(h·h) with tolerance 1e-6; the torque-zeroed case also pins ω = n·h after n substeps; the response case uses a plain `RigidBody` with one sphere `LocalCollider` at y 0.499, broad phase off, and pins exactly one contact and no position change; the soak also asserts ω unchanged. The suite runs in 0.8 s, the soak included.)*
- [x] `PhysicsSolverTests.zeroForcesClearsAllForces` also sets and asserts `torque`.
- [x] `CollisionResponseTests` additions (2), through `getInverseMassStats` and `applyImpulse(_:_:contact:inverseMassStats:)` with a hand-built `Contact` (the finite-inertia case also pins the stats tuple and that the contact point is at rest along n afterward): A is a detached body, mass 2, velocity `[0, −1, 0]`, against a static plane body, contact normal `[0, 1, 0]` at point `[1, 0, 0]` with A's origin at `[0, 0, 0]`. With `inverseInertiaLocal = diag(0.5)`: the angular term is 0.5, the denominator 1.0, j = 1 (e = 0 at exactly the threshold), so `velocity == [0, −0.5, 0]` and `angularVelocity == [0, 0, 0.5]` exactly. With infinite inertia the same call gives `velocity == .zero` and `angularVelocity == .zero`: the point-mass result, exact.
- [x] Gate: full serial suite green with no other edit; dry run byte-identical. Commit as D-angular-plumbing (plumbing, rule 2). *(2026-09-11: build green; full serial suite 368 Swift Testing tests in 55 suites plus 20 XCTest cases; the regeneration dry run rewrote all six goldens byte-identical and the clean parity re-run is green. Committed as `14c0bda`.)*

## Step D.2 — tires, brakes, and the ground normal — D-tires

Why: since B.5 the jet stands on its wheels and slides on them. Every ground-handling gap (stopping, holding position, a crab, a turn that the velocity follows) is one tangent force at each loaded wheel. The forces need the normal loads (the struts have them), the body's predicted velocity at each patch (`velocity(atWorldPoint:)` and `inverseInertiaWorld()` from D.1), the ground normal (the raycast has the plane, not yet its normal), and a brake command. The wheels are solved together, because a wheel at its friction limit must hand the rest of the demand to the others. No angular state is involved yet: with infinite inertia every patch moves with the center, and the kinematic yaw filter still turns the nose. D.3 makes the same forces torque-correct without touching this step's code.

Line numbers are as of `82f852b` for files D.1 did not touch (`ControlInput.swift`, `InputManager.swift`, `Aircraft.swift`, `SuspensionStrut.swift`, `AircraftLandingGearSpec.swift`, `LandingGearSuspension.swift`); `PhysicsWorld.swift` has D.1's seven inserted lines (the snapshot and the ω half, with their comments; `14c0bda`), so `raycastStaticPlanes` sits at 146–161.

- [ ] **Edit:** `Physics/World/PhysicsWorld.swift`, `raycastStaticPlanes` (lines 140–155 after D.1) returns the hit's normal with its distance. The struct goes above `final class PhysicsWorld`, after the `PhysicsUpdateType` enum (line 13):

```swift
/// A static-plane raycast hit: distance along the ray, and the surface
/// normal there (the plane's), which the tire model needs.
struct RayHit {
    let distance: Float
    let normal: float3
}
```

```swift
    /// Nearest static plane along a ray, or nil. O(planes) per call; every
    /// current scene has one.
    public func raycastStaticPlanes(from origin: float3, direction: float3) -> RayHit? {
        var nearest: RayHit? = nil
        for case let plane as PlaneRigidBody in entities where plane.isStatic {
            if let t = NarrowPhase.rayVsPlane(origin: origin,
                                              direction: direction,
                                              planePoint: plane.getPosition(),
                                              planeNormal: plane.collisionNormal),
               t < (nearest?.distance ?? .infinity) {
                nearest = RayHit(distance: t, normal: plane.collisionNormal)
            }
        }
        
        return nearest
    }
```

`LandingGearSuspensionTests.raycastStaticPlanes` (lines 249–253) compares `?.distance`; the nil cases are unchanged.

- [ ] **Edit:** `Physics/FlightModel/ControlInput.swift`, the brake channel, defaulted so `ControlInput` stays constructible without it:

```swift
public struct ControlInput {
    public let throttle: Float  //  0...1
    public let pitch: Float     // -1...1
    public let roll: Float      // -1...1
    public let yaw: Float       // -1...1
    public let brake: Float     //  0...1, wheel brakes on the braked struts

    public init(throttle: Float, pitch: Float, roll: Float, yaw: Float, brake: Float = 0) {
        self.throttle = throttle
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
        self.brake = brake
    }
}
```

- [ ] **Edit:** `Managers/InputManager.swift`: `case Brake` after `case Yaw` in `ContinuousCommand` (line 35), and the key after the `.Yaw` entry of `keyboardMappingsContinuous` (line 109). B is unbound today. Controller and HOTAS mappings are not added: the dictionaries return 0 for a command they do not list.

```swift
        .Brake: [KeycodeValue(keyCode: .b, value: 1.0)]
```

- [ ] **Edit:** `GameObjects/Aircraft.swift`, `getControlInput()` (lines 201–206) adds `brake: InputManager.ContinuousCommand(.Brake)`; and the suspension call in `generateForces` (lines 195–198) passes it. `latestControlInput` is nil without focus, so an unfocused aircraft never brakes; the parked jet holds on rolling resistance.

```diff
         gearSuspension?.accumulateForces(body: rigidBody,
                                          gearDeployed: isGearDown,
+                                         brake: latestControlInput?.brake ?? 0,
                                          world: world,
                                          substepDelta: substepDelta)
```

- [ ] **Edit:** `Physics/Vehicle/SuspensionStrut.swift`, after `var maxSupportForce: Float` (line 36). A trailing defaulted property keeps the memberwise init source-compatible:

```swift
    /// Wheel brakes act on this strut (the mains; braking the nose wheel
    /// would flat-spot it). Default off.
    var hasBrakes: Bool = false
```

and `Physics/Vehicle/AircraftLandingGearSpec.swift`: both mains (lines 41–58) get `hasBrakes: true` after `maxSupportForce: 400_000`; the nose keeps the default.

- [ ] **File (new):** `ToyFlightSimulator Shared/Physics/Vehicle/TireModel.swift`

```swift
//
//  TireModel.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/6/26.
//

/// Tangent forces of the loaded wheels for one substep, solved together,
/// pure. Holding Coulomb friction as sequential impulses (Catto, GDC 2006):
/// each wheel in turn applies the impulse that brings its patch's tangent
/// velocity — predicted to the end of the substep from the body's other
/// forces and torques — to rest, clamped to what the tire can carry, and
/// the prediction is updated as each impulse lands; a few sweeps converge.
/// At rest that is exactly the force needed to stay at rest, so a parked
/// aircraft holds at idle on rolling resistance and holds against thrust up
/// to the brake limit, then slides; a wheel at its limit leaves the rest of
/// the demand to the wheels after it. (A force proportional to slip speed,
/// the first draft, is zero at rest and creeps under any push: 0.2 m/s from
/// the parked stance alone. A fixed per-wheel share of the demand, the
/// second, left the unbraked nose wheel's unmet share to nobody: 1.6 cm of
/// creep in 5 s under 100 kN with the brakes on.) There is no wheel spin
/// state: a free wheel rolls, resisting along its rolling direction only
/// with rolling resistance; braking raises that limit. Lateral and
/// longitudinal parts together are clamped to the friction circle.
enum TireModel {
    static let lateralFriction: Float = 0.8       // cornering grip, dry runway
    static let brakeFriction: Float = 0.5         // fully braked wheel, dry
    static let rollingResistance: Float = 0.02
    /// Sweeps over the wheels. With infinite inertia the first sweep is
    /// exact (every patch shares the body's velocity). With the F-22's
    /// tensor the patches couple through pitch, roll, and yaw, and a sweep
    /// removes about three quarters of what is left: eight leave under 0.1%
    /// of a 1 mm/s or 1 mrad/s disturbance at any patch (four leave 3%),
    /// and the next substep sees the rest as velocity.
    static let sweeps = 8
    /// The per-solve scratch is fixed-size; no aircraft has more struts.
    static let maxWheels = 8

    /// One wheel on the ground.
    struct Wheel {
        /// Contact patch on the ground, world space.
        var patch: float3
        /// Unit ground normal at the patch.
        var groundNormal: float3
        /// The wheel's forward axis (body forward, steered or not); any
        /// length, projected onto the ground plane here.
        var rollingDirection: float3
        /// Normal load, N. Zero for a strut off the ground: the wheel is
        /// skipped and its force is zero.
        var normalLoad: Float
        /// Brake command 0…1 on this wheel (0 for struts without brakes).
        var brake: Float
    }

    /// The body as the solve sees it: the point its velocities refer to, and
    /// what an impulse does to them.
    struct Body {
        var origin: float3
        var inverseMass: Float
        /// Zero for infinite inertia (RigidBody.infiniteInertia).
        var inverseInertiaWorld: float3x3
    }

    /// Solves `wheels` together. `velocity` and `angularVelocity` are the
    /// body's predicted end-of-substep velocities if no wheel acted; on
    /// return they carry the wheels' impulses (the solve's bookkeeping, not
    /// applied to any body here). `forces[i]` receives wheel i's force — its
    /// impulse over the substep — and zero for an unloaded wheel or one
    /// whose rolling axis is normal to the ground.
    static func solve(wheels: [Wheel],
                      body: Body,
                      velocity: inout float3,
                      angularVelocity: inout float3,
                      substepDelta h: Float,
                      forces: inout [float3]) {
        assert(wheels.count <= maxWheels && forces.count == wheels.count)
        // Accumulated impulses per wheel, N·s, along the wheel's forward and
        // side directions (Catto's accumulated clamping, in two dimensions).
        var longitudinal = SIMD8<Float>(repeating: 0)
        var lateral = SIMD8<Float>(repeating: 0)

        for _ in 0..<sweeps {
            for (i, wheel) in wheels.enumerated() {
                guard let frame = groundFrame(of: wheel) else { continue }
                let lever = wheel.patch - body.origin
                let patchVelocity = velocity + cross(angularVelocity, lever)

                // The impulse that stops the patch along each direction, on
                // top of what this wheel has already applied; then the
                // Coulomb limits as impulses — rolling resistance raised by
                // the brake along, cornering grip across, the circle over
                // both.
                let alongLimit = (rollingResistance + wheel.brake * brakeFriction) * wheel.normalLoad * h
                let acrossLimit = lateralFriction * wheel.normalLoad * h
                var along = longitudinal[i] - effectiveMass(body, lever: lever, along: frame.forward) * dot(patchVelocity, frame.forward)
                var across = lateral[i] - effectiveMass(body, lever: lever, along: frame.side) * dot(patchVelocity, frame.side)
                along = max(-alongLimit, min(alongLimit, along))
                let magnitude = (along * along + across * across).squareRoot()
                if magnitude > acrossLimit {
                    let scale = acrossLimit / magnitude
                    along *= scale
                    across *= scale
                }

                let impulse = frame.forward * (along - longitudinal[i]) + frame.side * (across - lateral[i])
                longitudinal[i] = along
                lateral[i] = across
                velocity += impulse * body.inverseMass
                angularVelocity += body.inverseInertiaWorld * cross(lever, impulse)
            }
        }

        for (i, wheel) in wheels.enumerated() {
            if let frame = groundFrame(of: wheel) {
                forces[i] = (frame.forward * longitudinal[i] + frame.side * lateral[i]) / h
            } else {
                forces[i] = .zero
            }
        }
    }

    /// The wheel's rolling direction projected onto the ground and the side
    /// direction across it, or nil for an unloaded wheel or a rolling axis
    /// normal to the ground.
    private static func groundFrame(of wheel: Wheel) -> (forward: float3, side: float3)? {
        guard wheel.normalLoad > 0 else { return nil }
        let n = wheel.groundNormal
        let inPlane = wheel.rollingDirection - n * dot(wheel.rollingDirection, n)
        guard simd_length_squared(inPlane) > 1e-4 else { return nil }
        let forward = simd_normalize(inPlane)
        return (forward, cross(n, forward))
    }

    /// Effective mass at a lever arm along a unit direction,
    /// 1 / (1/m + (r × d) · I⁻¹ (r × d)): the mass an impulse there along d
    /// sees. The mass itself for infinite inertia.
    private static func effectiveMass(_ body: Body, lever r: float3, along d: float3) -> Float {
        let arm = cross(r, d)
        return 1 / (body.inverseMass + dot(body.inverseInertiaWorld * arm, arm))
    }
}
```

- [ ] **Edit:** `Physics/Vehicle/LandingGearSuspension.swift`, `accumulateForces` (lines 42–90). The signature gains `brake:`; the ray returns a hit; the step becomes two passes (every strut's spring-damper and its load first, then the tires solved together), and both the strut's load and the tire's tangent force are applied at the contact patch through `addForce(_:atWorldPoint:)`:

```swift
    /// One substep. `gearDeployed` is the animation gate (Aircraft.isGearDown):
    /// retracted or moving gear produces no force and holds zero compression.
    /// `brake` is 0…1 and acts on the struts that have brakes.
    func accumulateForces(body: RigidBody, gearDeployed: Bool, brake: Float, world: PhysicsWorld, substepDelta: Float) {
        guard gearDeployed else {
            resetToAirborne()
            return
        }

        let pose = body.pose()
        // Body up, the strut axis: rays go down −up. Not float3.up, which is
        // world up — a rolled aircraft's struts roll with it.
        let up = pose.rotation.up
        // Wheels roll along body forward; TireModel projects it onto the ground.
        let forward = pose.rotation.forward

        // Pass 1: every strut's spring-damper step, its overload edge, and
        // its load — applied now, along the ground normal at the contact
        // patch (Bullet's raycast vehicle applies its suspension impulse the
        // same way), so a pitched or rolled stance pushes nothing along the
        // runway and the load's torque is in the tire solve's prediction.
        // The compression is still measured along the strut. A braking
        // force at ground level pitches the nose down once the body can
        // pitch (D.3).
        for (i, strut) in struts.enumerated() {
            let attachWorld = pose.position + pose.rotation * (strut.attachLocal * pose.uniformScale)
            let hit = world.raycastStaticPlanes(from: attachWorld, direction: -up)
            let step = SuspensionSolver.solve(strut: strut,
                                              uniformScale: pose.uniformScale,
                                              distanceToGround: hit?.distance,
                                              previousCompression: compressions[i],
                                              substepDelta: substepDelta)
            compressions[i] = step.compression

            // Rising edge only: one event per exceedance, per strut.
            if step.overloaded && !wasOverloaded[i] {
                onLandingGearEvent?(.gearOverload(strutName: strut.name,
                                                  force: step.force,
                                                  bottomedOut: step.bottomedOut))
            }
            wasOverloaded[i] = step.overloaded

            if let hit, step.force > 0 {
                let patch = attachWorld - up * hit.distance
                body.addForce(hit.normal * step.force, atWorldPoint: patch)
                wheels[i] = TireModel.Wheel(patch: patch,
                                            groundNormal: hit.normal,
                                            rollingDirection: forward,
                                            normalLoad: step.force,
                                            brake: strut.hasBrakes ? brake : 0)
            } else {
                wheels[i].normalLoad = 0
            }
        }

        // Pass 2: the tires, solved together against the body's velocities
        // as this substep's other forces and torques would leave them — the
        // flight model's force (Aircraft.generateForces adds it first), the
        // strut loads above, and the solver's gravity. Their impulses come
        // back as forces at the patches.
        let gravity: float3 = body.shouldApplyGravity ? PhysicsWorld.gravity : .zero
        var velocity = body.velocity + (body.force / body.mass + gravity) * substepDelta
        var angularVelocity = body.angularVelocity + body.inverseInertiaWorld() * body.torque * substepDelta
        TireModel.solve(wheels: wheels,
                        body: TireModel.Body(origin: pose.position,
                                             inverseMass: 1 / body.mass,
                                             inverseInertiaWorld: body.inverseInertiaWorld()),
                        velocity: &velocity,
                        angularVelocity: &angularVelocity,
                        substepDelta: substepDelta,
                        forces: &tireForces)
        for i in struts.indices where wheels[i].normalLoad > 0 {
            body.addForce(tireForces[i], atWorldPoint: wheels[i].patch)
        }

        // (weight-on-wheels block unchanged)
    }
```

`body.force += up * step.force` is gone: `addForce(_:atWorldPoint:)` applies the load along `hit.normal` at the patch and accumulates a torque that nothing integrates until D.3. For a level body on a level runway the direction is the one it was; for a pitched or rolled body it no longer has a runway component. The class gains two index-aligned scratch arrays, `wheels: [TireModel.Wheel]` (an unloaded entry carries `normalLoad` 0 and is skipped) and `tireForces: [float3]`, sized in `init(struts:)` like `compressions`, so the two passes allocate nothing. Until D.3 `inverseInertiaWorld()` is the zero matrix, so the angular prediction is zero and every patch moves with the origin: the first sweep is exact and the rest are no-ops. The sink rate stays `−velocity.y` (level runway; `hit.normal` is at hand when the tilted-runway one-liner is wanted).

### Numbers (F-22 at 30 t, the same rig as B.4)

- Static loads with the 89/11 split of a body that cannot pitch: mains 131 kN each, nose 32 kN.
- Braking from 40 m/s: the longitudinal limit is μ = 0.02 + 0.5 = 0.52 on the mains, deceleration ≈ 0.52 × 0.89 × g ≈ 4.5 m/s², stop in about 9 s and 180 m. After D.3 the geometric split and the braking pitch move this by a few percent; the test band covers both.
- Lateral grip: 0.8 × 294 kN ≈ 235 kN, up to 7.8 m/s² against a crab; a 5 m/s sideways drift is gone in about 0.65 s, the last centimetres per second within one substep (the holding force is unsaturated there).
- Holding: at rest the demand is the tangent force the body would otherwise pick up this substep, and the capacity is 5.9 kN unbraked (0.02 × W) and 137 kN with the brakes on (0.52 × 262 kN on the mains plus the nose's 0.6; 131 kN after D.3's split). No push under the capacity moves the jet: the wheels are solved in strut order and each takes what the ones before it left, so 100 kN of thrust is opposed by 0.6 kN at the nose and 68.1 and 31.2 kN at the mains. The regularised draft crept at 0.2 m/s from the −0.45° stance alone and 0.19 m/s per 50 kN of thrust with the brakes on; the fixed-share draft opposed only 89.8 of the 100 kN (the nose's share stopped at its 0.6 kN limit and nobody took the rest) and crept 1.6 cm in 5 s.
- Stability: under Euler the holding force is dead-beat (the patch velocity is gone in one substep). Under Verlet, the production solver, this substep's force is averaged with last substep's, so a disturbance rings with a factor of 1/√2 per substep and alternating sign, gone in about ten substeps (a 0.1 m/s kick travels 0.9 mm and stops); at rest under a steady push the demand is the same every substep, the average is exact, and nothing rings — 0.000 mm in 5 s under 100 kN with the brakes on, under either solver.
- Rolling resistance alone: 0.02 g ≈ 0.2 m/s²; a taxiing jet coasts a long way, as real ones do.

### Expected behavior (checked in-app; written into the commit message)

- **The jet stops.** Land, hold B: from 40 m/s the roll-out is about 200 m. Release: it coasts. Hold B at rest: it stays put, at idle and with throttle up, until thrust exceeds 0.52 × the main-gear load; then it slides. Release the brakes at idle: it still stays put (rolling resistance holds up to 0.02 × W).
- **A crab settles.** Touch down with a few degrees of yaw: the velocity swings to the nose within a second (the mains skid a little); no drift across the runway.
- **Q/E turn the jet at taxi speed** through the kinematic yaw filter, and the velocity follows the nose. The turn is not yet physical; D.3 adds nosewheel steering.
- **Gear up:** the belly slide is unchanged (contacts have no friction; D.4).

### Tests for this step (Metal-free, `.tags(.physics)`)

- [ ] **File (new):** `ToyFlightSimulatorTests/Physics/TireModelTests.swift` (14, pure, through `TireModel.solve`; unless stated, one wheel with N = 1000 on level ground, a body of mass 100 with infinite inertia (`inverseMass` 0.01, `inverseInertiaWorld` zero), h = 1/120 for exact numbers, and the predicted velocity given as the body's): unloaded → zero force and the velocities untouched; lateral 2 m/s (a 24 kN demand) → `−800 · side`, saturated; lateral 0.001 m/s → `−12 · side` exactly (100 · 0.001 · 120, the holding region) and the returned velocity zero; **two wheels, one demand** (both at 0.001 m/s lateral): the first takes `−12 · side`, the second zero — a sequence, not a share; rolling at 20 m/s with no brake → `−20 · forward` (rolling resistance), with brake 1 → `−520 · forward`; a predicted forward drift of 0.001 m/s with no brake → `−12 · forward` exactly (held), of 0.005 m/s → `−20 · forward` (over the 20 N rolling limit, so it creeps); saturated lateral plus saturated brake → magnitude 800, not 940 (the circle); the force has no component along the ground normal; a rolling direction along the normal → zero; **the limit hands the demand on** (the D.2 rig's numbers: mass 30 000, three wheels at 32, 131, 131 kN, brakes on the mains only, predicted forward velocity 100 000 / 30 000 / 120): the forces sum to `−100 000 · forward` ± 1 N — nose 640, mains 68 120 and 31 240 in order — and the returned velocity is zero within 1e-6; the same with the brakes off: the sum is 5 880 (0.02 × the load) and the velocity is not zero; **finite inertia** (mass 2, `inverseInertiaWorld = diag(0.5)`, one wheel 2 m below the origin with brake 1, predicted `[0, 0, 1]` along its forward): the force is `−48 · forward` (effective mass 1 / (0.5 + 2) = 0.4, an impulse of 0.4 N·s over h), the returned velocity `[0, 0, 0.8]`, the angular velocity `[0.4, 0, 0]`, and the patch velocity (velocity + ω × r) zero within 1e-6.
- [ ] `GearSuspensionWorldTests` additions (6; the rig's hook passes a `brake` field, default 0, and adds an `extraForce`, default zero, to `body.force` before the suspension runs, as the flight model's force would): **braking stop** (settle 10 s, then `velocity = [0, 0, 40]`, brake 1: `|velocity| < 0.5` within 12 s, distance travelled in 150…260 m); **crab settles** (settle, `velocity = [5, 0, 0]`: `|velocity.x| < 0.1` after 2 s, less than 3 m moved); **coasting** (settle, `velocity = [0, 0, 20]`, no brake: speed after 5 s is 20 − 0.98 ± 0.2); **gear up slides** (from the belly rest with `velocity = [0, 0, 5]`: speed after 2 s is at least 4.5, pinning that contacts carry no friction); **parked hold** (settle, then `extraForce = [0, 0, 4_000]`, under the 5.9 kN rolling-resistance limit, for 5 s: the origin moves less than 1 cm and `|velocity| < 1e-3` at the end — the regularised draft would drift 1.7 m); **brake hold and release** (settle, brake 1, `extraForce = [0, 0, 100_000]`: less than 1 cm in 5 s; then `[0, 0, 200_000]`, over the 137 kN capacity: more than 1 m in 5 s, the wheels slide — 26 m, with the limit taken).
- [ ] `LandingGearSuspensionTests`: every `accumulateForces` call gains `brake: 0`; the raycast test reads `.distance`; the rolled-body case (line 99) keeps its ray and compression (the slant distance) but its force direction flips: the load acts along the plane normal, so it expects `[0, 50, 0]` and asserts the force is NOT along `up` — the inverse of before — and its title becomes "the strut ray follows the body's up axis; the load acts along the ground normal". Every other force expectation holds unedited: every existing case has a vertical velocity only and no accumulated force, so the tire's demand is zero and its force exactly zero.
- [ ] Gate: full serial suite green; dry run byte-identical; the four in-app behaviors above. Commit as D-tires (behavior on the struts; goldens untouched).

## Step D.3 — the aircraft rotates — D-attitude

Why: everything Phase B deferred to "when the body can pitch" lands here: the nose settling after the mains, a one-wheel touchdown rolling level, the geometric gear load split, braking dive, steering that turns the jet through its tires. The prerequisite is a rotation that physics owns, and the constraint is that flight must feel as it does today.

The attitude filter is already an ordinary differential equation, dω/dt = (ω_cmd − ω)/τ per axis. Multiplied by the inertia it is a torque. So the filter does not go away; it moves inside the step as a rate controller, and its output becomes one torque among others. With no other torque a semi-implicit substep reproduces the filter's exact-exponential update, so the in-air trajectory is the one the kinematic path produced. Gear and contact torques add, and the controller damps them with the same time constants: on the ground it behaves like a stability-augmentation system that opposes rates, not angles, so the gear's spring torques still turn the aircraft to its equilibrium at a plausible rate.

Aircraft without a body or without a flight model keep the kinematic path unchanged: the F-16 wingman has no body, `FreeCamFlightboxScene`'s jet has no flight model. The rule is "an aircraft with flight physics flies by forces and torques; the rest move as before".

Line numbers: `FlightModel.swift`, `F22SimpleFlightModel.swift`, and the `Aircraft.swift` property block are as of `82f852b`; `Aircraft.doUpdate`/`generateForces` and `LandingGearSuspension.accumulateForces` are after D.2 (locate by the text quoted); `NarrowPhase.shapeVsPlane` is after C.1 (locate by the `// MARK: - Shape vs plane` section); `HeckerCollisionResponse.resolvePair` and `applyImpulse` are after D.1; `TouchdownReporter` and the `applyAircraftSwap` wiring are as of `82f852b`.

### D.3.1 — inertia on the flight model, synced like mass

- [ ] **Edit:** `Physics/FlightModel/FlightModel.swift`, after `var mass: Float { get }` (line 9):

```swift
    /// Principal moments of inertia about the body axes, kg·m²: x (pitch),
    /// y (yaw), z (roll). Authored per aircraft like mass, never derived
    /// from the collider spec: fuel, engines, and stores set the real
    /// distribution, not collision boxes (research §3.1).
    var inertia: float3 { get }
```

and its doc comment's "Note" (lines 29–39) is replaced by: "Torque is not returned here. Attitude is a rate controller on the aircraft (`AttitudeRateController`) whose torque is added to the body inside the step; aerodynamic moments would be the next thing a flight model returns."

- [ ] **Edit:** `Physics/FlightModel/Models/F22SimpleFlightModel.swift`, after `public let mass` (line 9):

```swift
    /// Estimate scaled from the public F-16 model (NASA TP-1538: 12 875 /
    /// 75 674 / 85 552 kg·m² roll / pitch / yaw at 9 300 kg) by mass and by
    /// span² for roll and length² for pitch and yaw, rounded. Order of
    /// magnitude is what matters: it sets how hard gear and tire torques
    /// turn the aircraft against the controller.
    public let inertia: float3 = [390_000, 440_000, 80_000]   // pitch, yaw, roll
```

- [ ] **Edit:** `GameObjects/Aircraft.swift`. The two mass mirrors (`flightModel.didSet`, lines 86–92, and the first half of `rigidBody.didSet`, lines 102–107) become one call; the long "Fix 3" comment above `flightModel` shrinks to its first paragraph plus a pointer to the debugging note:

```swift
    var flightModel: FlightModel? {
        didSet { syncMassProperties() }
    }

    override var rigidBody: RigidBody? {
        didSet {
            syncMassProperties()
            // The world calls this from inside the physics step. Weak self:
            // the aircraft owns the body, so a strong capture would be a cycle.
            rigidBody?.forceGenerator = { [weak self] _, substepDelta, world in
                self?.generateForces(substepDelta: substepDelta, world: world)
            }
        }
    }

    /// Mass and inertia come from the flight model. Both didSets call this,
    /// so either assignment order converges. An aircraft without a flight
    /// model has infinite inertia and the kinematic attitude path; removing
    /// the model restores that (the tensor, and the angular state the
    /// integrator would otherwise keep applying next to the kinematic
    /// rotation). Mass is left where it was: nothing else authors it.
    private func syncMassProperties() {
        guard let rigidBody else { return }
        guard let flightModel else {
            rigidBody.inverseInertiaLocal = RigidBody.infiniteInertia
            rigidBody.angularVelocity = .zero
            rigidBody.torque = .zero
            return
        }
        rigidBody.mass = flightModel.mass
        rigidBody.inverseInertiaLocal = float3x3(diagonal: 1 / flightModel.inertia)
    }
```

`F22.rigidBody.didSet` (restitution 0.1) is untouched; its observer runs after the base class's.

### D.3.2 — the rate controller

- [ ] **File (new):** `ToyFlightSimulator Shared/Physics/FlightModel/AttitudeRateController.swift`. `AttitudeDynamics` stays in `Aircraft.swift`; both paths read it.

```swift
//
//  AttitudeRateController.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/6/26.
//

/// Pilot rate command → torque, so the body's angular velocity follows the
/// command with the first-order lag AttitudeDynamics describes. With no
/// other torque, one semi-implicit substep reproduces the kinematic filter's
/// update exactly: Δω = (ω_cmd − ω)·(1 − e^(−h/τ)). Gear and contact torques
/// add on top and are damped with the same time constants. Pure.
enum AttitudeRateController {
    /// Body-axis rate command: pitch about X (right), yaw about Y (up), roll
    /// about Z (forward). The negations are the pilot convention the
    /// kinematic path used (rotateX(−pitchRate·dt) and so on). nil input
    /// (no focus) commands zero rates, which is the old decay path.
    static func commandedRates(_ input: ControlInput?, _ dynamics: AttitudeDynamics) -> float3 {
        guard let input else { return .zero }
        return [-input.pitch * dynamics.maxPitchRate,
                -input.yaw * dynamics.maxYawRate,
                -input.roll * dynamics.maxRollRate]
    }

    /// Body-frame torque for one substep of length h. τ = I·Δω/h per axis,
    /// with Δω the filter's exact discrete update.
    static func torque(commandedRates: float3,
                       bodyRates: float3,
                       inertia: float3,
                       dynamics: AttitudeDynamics,
                       substepDelta h: Float) -> float3 {
        let alpha = float3(1 - exp(-h / dynamics.pitchTimeConstant),
                           1 - exp(-h / dynamics.yawTimeConstant),
                           1 - exp(-h / dynamics.rollTimeConstant))
        let deltaRates = (commandedRates - bodyRates) * alpha
        return inertia * deltaRates / h
    }
}
```

- [ ] **Edit:** `GameObjects/Aircraft.swift`, `doUpdate` and `generateForces`. The kinematic rotation runs only without flight physics; the controller runs inside the step, outside the input guard:

```swift
    /// Aircraft with a body and a flight model fly by forces and torques in
    /// generateForces. The rest move kinematically, as before: the F-16
    /// wingman has no body, FreeCamFlightboxScene's jet has no flight model.
    private var hasFlightPhysics: Bool { rigidBody != nil && flightModel != nil }

    override func doUpdate() {
        super.doUpdate()

        let dt = Float(GameTime.DeltaTime)

        if shouldUpdateOnPlayerInput && hasFocus {
            let controlInput = getControlInput()
            let deltaMove = dt * _moveSpeed

            // Flight forces and the attitude torque are computed in
            // generateForces, inside the physics step. Here we only refresh
            // the input it reads.
            latestControlInput = controlInput
            if !hasFlightPhysics {
                moveAlongVector(getFwdVector(), distance: deltaMove * controlInput.throttle)
                applyPlayerAttitudeInput(deltaTime: dt, controlInput: controlInput)
                // The A/D strafe teleports the node; on the physics path it
                // would slide the jet through its own tire model.
                applyPlayerSideMove(deltaMove: deltaMove)
            }

            handleGearToggle()
        } else {
            latestControlInput = nil
            if !hasFlightPhysics {
                // Kinematic path: bleed off the carried rates so resuming
                // control does not snap into a stale tumble.
                decayAttitudeRates(deltaTime: dt)
            }
        }

        animator?.update(deltaTime: dt)
    }

    /// Called by the physics world at the top of each substep, on the
    /// UpdateThread, from live body state. doUpdate runs later in the frame,
    /// after the step, and only refreshes the cached input.
    func generateForces(substepDelta: Float, world: PhysicsWorld) {
        guard let rigidBody else { return }

        if let flightModel {
            if let input = latestControlInput, let state = rigidBody.getState() {
                rigidBody.force += flightModel.computeForce(state: state, input: input)
            }

            // Attitude by torque, outside the input guard: without focus the
            // command is zero and the controller damps the body's rates, as
            // the kinematic filter's decay did.
            let rotation = rigidBody.pose().rotation
            let torqueBody = AttitudeRateController.torque(
                commandedRates: AttitudeRateController.commandedRates(latestControlInput, attitudeDynamics),
                bodyRates: rotation.transpose * rigidBody.angularVelocity,
                inertia: flightModel.inertia,
                dynamics: attitudeDynamics,
                substepDelta: substepDelta)
            rigidBody.torque += rotation * torqueBody
        }

        // Outside the input guard: a parked, unfocused aircraft must still be
        // held up. isGearDown is animator state written only in doUpdate, so
        // it is stable across a frame's substeps.
        gearSuspension?.accumulateForces(body: rigidBody,
                                         gearDeployed: isGearDown,
                                         brake: latestControlInput?.brake ?? 0,
                                         steer: latestControlInput?.yaw ?? 0,
                                         world: world,
                                         substepDelta: substepDelta)
    }
```

The `currentPitchRate/RollRate/YawRate` fields and the two filter functions stay for the kinematic path. The `rateEpsilon` snap that kept a settled kinematic aircraft from writing its transform every frame does not carry over to the physics path, and need not: a body on its struts already writes its position every substep.

### D.3.3 — nosewheel steering

- [ ] **Edit:** `Physics/Vehicle/SuspensionStrut.swift`, after `var hasBrakes` (D.2):

```swift
    /// Steering range of this strut's wheel, radians, driven by the yaw
    /// command. 0 (default) for the mains.
    var maxSteerAngle: Float = 0
```

`AircraftLandingGearSpec`: the nose strut gets `maxSteerAngle: 0.35` (20°). Kinematic steering geometry gives ω = v·tan δ / wheelbase ≈ 0.48 rad/s at 8 m/s, about 27°/s, before the mains' side grip and the controller's rate damping slow it. Tune in-app.

- [ ] **Edit:** `Physics/Vehicle/LandingGearSuspension.swift`, `accumulateForces` gains `steer: Float` (−1…1, the yaw command) after `brake:`, and the wheel's rolling direction per strut becomes:

```swift
            // A steered wheel rolls along body forward turned about body up by
            // −steer × range: the same sign as the yaw rate command
            // (−yaw × maxYawRate), so Q and E turn the nose the same way on
            // the ground as in the air. The nose tire's side grip at 5.2 m
            // ahead of the origin is the yaw torque.
            let rolling = strut.maxSteerAngle == 0
                ? forward
                : simd_quatf(angle: -steer * strut.maxSteerAngle, axis: up).act(forward)
```

and `rollingDirection: rolling` where pass 1 builds the wheel.

### D.3.4 — the capsule rests on both ends

- [ ] **Edit:** `Physics/Collision/NarrowPhase.swift`, `shapeVsPlane`. It appends into the caller's array (none, one, or two contacts) instead of returning one, and the plane branch of `generateContacts` notes the deepest index per appended contact. Sphere and box bodies are unchanged apart from the `contacts.append`; the capsule case becomes:

```swift
    /// Appends the contacts of one collider against the infinite plane
    /// through planePoint: none, one, or two (a capsule's end caps). Gates are
    /// inclusive (depth >= 0).
    static func shapeVsPlane(_ collider: WorldCollider, planePoint: float3, planeNormal n: float3,
                             into contacts: inout [Contact]) {
        switch collider.shape {
            case .sphere(radius: let r):
                // (unchanged, then contacts.append(...))

            case .capsule(radius: let r, halfHeight: let hh):
                // Both end caps, deeper first. A capsule lying along the
                // ground gets two points, so a body with pitch freedom rests
                // on both ends instead of rocking between them (D.3). The
                // first contact is the one the single-contact form produced.
                let axis = collider.rotation.columns.1
                let p0 = collider.position - axis * hh
                let p1 = collider.position + axis * hh
                let d0 = dot(p0 - planePoint, n)
                let d1 = dot(p1 - planePoint, n)
                let (near, nearDistance, far, farDistance) = d0 < d1 ? (p0, d0, p1, d1) : (p1, d1, p0, d0)
                guard r - nearDistance >= 0 else { return }
                contacts.append(Contact(normal: n, depth: r - nearDistance,
                                        point: near - n * nearDistance, collider: collider))
                if r - farDistance >= 0 {
                    contacts.append(Contact(normal: n, depth: r - farDistance,
                                            point: far - n * farDistance, collider: collider))
                }

            case .box(halfExtents: let he):
                // (unchanged, then contacts.append(...))
        }
    }
```

In `generateContacts`, the plane branch becomes:

```swift
            for collider in a.worldColliders() {
                let before = contacts.count
                shapeVsPlane(collider, planePoint: planePoint, planeNormal: planeNormal, into: &contacts)
                for index in before..<contacts.count {
                    noteDeepest(index, in: contacts, deepest: &deepest)
                }
            }
```

with `append(_:to:deepest:)` split into the append and a `noteDeepest(_:in:deepest:)` that keeps the tie rule ("ties keep the earlier"). The volume-volume loop keeps using `append`.

Call sites: `generateContacts`; `CompoundBodyTests.bankedPoseContactsWingsOnly`; seven cases in `NarrowPhaseTests`. A three-line helper in each test file, `planeContacts(_:planePoint:planeNormal:) -> [Contact]`, keeps each edit to one line. A level belly slap now fires two `onContact`s per substep (both caps); `TouchdownReporter` prints one `[CRASH]` for them (D.3.6 dedupes impacts per frame per other body). With two contacts, the pair needs D.3.5's solve: one impulse pass leaves the first cap approaching again.

### D.3.5 — one solve per pair

- [ ] **Edit:** `Physics/CollisionResponse/HeckerCollisionResponse.swift` (after D.1). `resolvePair` sends a pair with more than one contact to `solveManifold`; a single-contact pair keeps D.1's path, which is what keeps every sphere golden fixed. D.1 as shipped computes the pair's inverse masses once (`getInverseMassStats`) and passes them to both halves; `solveManifold` below computes its own and can take the same tuple at transcription:

```swift
    /// Iterations of the pair solve for a pair with more than one contact.
    /// Eight brings the F-22's two-cap belly rest to rest (four leaves 0.008
    /// rad/s of rocking, one 0.029). A single-contact pair keeps the one
    /// pass: a second pass there is not byte-identical (float32 leaves the
    /// residual approach negative in about four contacts in ten).
    static let manifoldIterations = 8

    /// One narrow phase per pair: filter, generate contacts, mark the pair as
    /// collided, correct position at the deepest contact, solve the pair's
    /// contacts for impulses, then fire onContact for every contact (handlers
    /// see post-response state). Shared with EulerSolver.
    static func resolvePair(_ entityA: RigidBody, _ entityB: RigidBody, contacts: inout [Contact]) {
        guard entityA.shouldCollide(with: entityB), !entityA.collidedWith.contains(ObjectIdentifier(entityB)) else { return }
        
        let firstNew = contacts.count
        guard let deepest = NarrowPhase.generateContacts(entityA, entityB, into: &contacts) else { return }
        
        entityA.collidedWith.insert(ObjectIdentifier(entityB))
        entityB.collidedWith.insert(ObjectIdentifier(entityA))
        
        let invMassStats = getInverseMassStats(entityA, entityB)
        correctPosition(entityA, entityB, contact: contacts[deepest], inverseMassStats: invMassStats)
        if contacts.count - firstNew == 1 {
            // One contact — every sphere pair, so every golden: the Phase A
            // sequence exactly.
            applyImpulse(entityA, entityB, contact: contacts[deepest], inverseMassStats: invMassStats)
        } else {
            solveManifold(entityA, entityB, contacts: contacts[firstNew...])
        }
        
        for contact in contacts[firstNew...] {
            entityA.onContact?(contact, entityB)
            entityB.onContact?(contact.flipped, entityA)
        }
    }

    /// Sequential impulses over one pair's contacts (Catto, GDC 2006): each
    /// contact's accumulated impulse is clamped non-negative, so an early
    /// contact can give back what a later one made unnecessary, and the
    /// restitution target is captured from the pre-solve velocities. With
    /// the F-22's pitch inertia the lever arms dominate the effective mass,
    /// so one pass over two caps leaves the first approaching again at about
    /// the speed it arrived; eight passes converge. Position correction
    /// stays linear at the deepest contact (D.4 for the angular share).
    static func solveManifold(_ entityA: RigidBody, _ entityB: RigidBody, contacts: ArraySlice<Contact>) {
        assert(contacts.count <= ManifoldState.capacity, "more contacts in one pair than the specs can produce")
        let invMassA: Float = entityA.isStatic ? 0 : 1 / entityA.mass
        let invMassB: Float = entityB.isStatic ? 0 : 1 / entityB.mass
        guard invMassA + invMassB > 0 else { return }
        let invInertiaA = entityA.isStatic ? RigidBody.infiniteInertia : entityA.inverseInertiaWorld()
        let invInertiaB = entityB.isStatic ? RigidBody.infiniteInertia : entityB.inverseInertiaWorld()
        let positionA = entityA.getPosition()
        let positionB = entityB.getPosition()

        var state = ManifoldState()
        for (slot, contact) in contacts.enumerated() {
            let n = contact.normal
            let rA = contact.point - positionA
            let rB = contact.point - positionB
            let approach = dot(entityA.velocity(atWorldPoint: contact.point) - entityB.velocity(atWorldPoint: contact.point), n)
            let e = -approach > restitutionVelocityThreshold ? min(entityA.restitution, entityB.restitution) : 0
            let angularA = dot(cross(invInertiaA * cross(rA, n), rA), n)
            let angularB = dot(cross(invInertiaB * cross(rB, n), rB), n)
            state.effectiveMass[slot] = 1 / (invMassA + invMassB + angularA + angularB)
            // Target normal velocity: −e × the incoming approach (0 below the
            // threshold), the same bounce the single impulse produces.
            state.target[slot] = approach < 0 ? -e * approach : 0
        }

        for _ in 0..<manifoldIterations {
            for (slot, contact) in contacts.enumerated() {
                let n = contact.normal
                let rA = contact.point - positionA
                let rB = contact.point - positionB
                let relative = dot(entityA.velocity(atWorldPoint: contact.point) - entityB.velocity(atWorldPoint: contact.point), n)
                let wanted = (state.target[slot] - relative) * state.effectiveMass[slot]
                let previous = state.accumulated[slot]
                state.accumulated[slot] = max(0, previous + wanted)
                let j = state.accumulated[slot] - previous
                guard j != 0 else { continue }
                if !entityA.isStatic {
                    entityA.velocity += n * (j * invMassA)
                    entityA.angularVelocity += invInertiaA * cross(rA, n * j)
                }
                if !entityB.isStatic {
                    entityB.velocity -= n * (j * invMassB)
                    entityB.angularVelocity -= invInertiaB * cross(rB, n * j)
                }
            }
        }
    }

    /// Fixed-capacity per-contact scratch for solveManifold: no allocation
    /// on the step path. Sixteen slots cover any pair the specs produce
    /// (fuselage, wings, empennage against a plane or a structure's one
    /// collider, the capsule contributing two; two compounds give nine).
    private struct ManifoldState {
        static let capacity = 16
        var effectiveMass = SIMD16<Float>(repeating: 0)
        var target = SIMD16<Float>(repeating: 0)
        var accumulated = SIMD16<Float>(repeating: 0)
    }
```

Why the goldens hold: every sphere pair has one contact and takes the first branch, D.1's code. Pairs with several contacts and infinite inertia (the detached F-22 of `CompoundBodyTests`, before the rig gives it a tensor) change by at most float rounding — the first iteration cancels the approach, later ones see a residual of a few ulp — and those tests assert bands, not bytes.

### D.3.6 — crash classification at the contact point

- [ ] **Edit:** `Physics/Debug/TouchdownReporter.swift`, `reportAirframeContact` (lines 37–55). The velocity it classifies is the relative velocity at the contact point, and impacts are printed once per frame per other body:

```swift
    /// Scrapes are throttled per collider name (a sliding fuselage re-contacts
    /// every step); impacts print once per frame per other body, keyed on
    /// GameTime.TotalGameTime, which a frame's substeps share. That is a
    /// policy, not a proof: a level belly slap is two cap contacts in one
    /// substep and one crash, and a tumbling airframe that strikes the same
    /// body with a second collider inside the same frame also prints once —
    /// one line for one event, which is the right amount of console.
    /// `preImpactRelativeVelocity` is the aircraft's step-start velocity at
    /// the contact point minus the other body's there: a rotating wing
    /// strikes at ω × r while the origin is still, and a ball thrown at a
    /// parked jet closes at its own speed.
    func reportAirframeContact(_ contact: Contact, preImpactRelativeVelocity: float3, isGearDown: Bool, against other: RigidBody) {
        let speed = AirframeContactClassifier.normalSpeed(contactNormal: contact.normal, preImpactVelocity: preImpactRelativeVelocity)
        let classification = AirframeContactClassifier.classification(forNormalSpeed: speed)
        let name = contact.colliderNameA ?? "aircraft body"
        let now = GameTime.TotalGameTime
        
        if classification == .scrape {
            if let last = lastScrapeLog[name], now - last < scrapeLogInterval { return }
            lastScrapeLog[name] = now
        } else {
            let key = ObjectIdentifier(other)
            if lastImpactLog[key] == now { return }
            lastImpactLog[key] = now
        }
        
        // (the print is unchanged)
    }
```

with `private var lastImpactLog: [ObjectIdentifier: Double] = [:]` next to `lastScrapeLog`. `AirframeContactClassifier` is unchanged: it already takes a velocity and a normal; its doc comment says the velocity is now the relative point velocity.

- [ ] **Edit:** `Scenes/FlightboxWithPhysics.swift`, the `onContact` wiring in `applyAircraftSwap` (lines 244–250):

```swift
            acRigidBody.onContact = { [weak playerAircraft] contact, other in
                guard let playerAircraft, let body = playerAircraft.rigidBody else { return }
                let closing = body.stepStartVelocity(atWorldPoint: contact.point)
                            - other.stepStartVelocity(atWorldPoint: contact.point)
                reporter.reportAirframeContact(contact,
                                               preImpactRelativeVelocity: closing,
                                               isGearDown: playerAircraft.isGearDown,
                                               against: other)
            }
```

### Numbers (F-22 at 30 t)

- **Static split with pitch freedom:** nose 0.9/6.1 = 14.75% of 294.3 kN = 43.4 kN → compression 0.162 m; mains 125.4 kN each → 0.114 m. Pitch −0.45° (nose down, 48 mm over 6.1 m). Origin height 1.929 m: `staticStance`'s 1.931 is still the number the overlay logs; its doc comment gains "ignores the pitch equilibrium, a 2 mm difference at the origin".
- **Gear stiffness about the origin:** pitch Σk·z² = 268 k × 5.2² + 2 × 1.1 M × 0.9² ≈ 9.0 MN·m/rad; roll 2 × 1.1 M × 1.62² ≈ 5.8 MN·m/rad. With I_pitch 390 k and I_roll 80 k: ω_n ≈ 4.8 rad/s (1.3 s) and 8.5 rad/s (0.74 s); damping ratios from Σc·z² ≈ 0.31 (pitch) and 0.56 (roll) before the controller's own damping. Per-substep factors (Σc·z²/I)·h ≈ 0.025 and 0.08: stable with margin.
- **Controller authority:** full pitch command asks for 390 k × 1 / 0.25 ≈ 1.6 MN·m against 9.0 MN·m/rad of gear stiffness: a parked jet pitches about 10° at full stick (the kinematic model had no limit). At ω = 0 the roll controller's opposing torque per unit rate is I/τ = 530 kN·m per rad/s; a one-wheel touchdown's spring torque (one main at 1.62 m carrying half the weight, 238 kN·m) rolls the jet level at a steady 0.45 rad/s, 26°/s, then the second main takes up the load.
- **Braking dive:** 0.52 × 250 kN at the patch, 1.93 m below the origin: 250 kN·m nose-down, 41 kN more on the nose gear, +0.15 m nose compression (travel 0.40). Visible, and what real jets do.
- **Parked:** with the load along the ground normal the −0.45° stance pushes nothing along the runway; a strut force along body up would have, 2.3 kN, and the first draft's tire would have crept at 0.2 m/s for as long as the jet stood there.
- **Brake hold:** 100 kN of thrust against the brakes at rest is a couple of 193 kN·m (the tire force acts 1.93 m below the origin, the thrust at it). The nose dives from −0.48° to −1.80°, the nose gear takes about 34 kN more, and the origin, pivoting on the held patches, moves 4.4 cm forward within a second — then nothing moves (0.2 mm over the next 4 s in a planar replay of the struts, the controller, and the joint tire solve). That is the transient the D.3 test allows before asserting the hold; the 4 kN parked case moves 1.8 mm.
- **Belly rest:** two caps 16.2 m apart on 390 000 kg·m² of pitch inertia. One impulse pass per substep left a 5 s simulation of the exact algorithm rocking at a steady 0.029 rad/s with a 0.25 m/s residual sink at every frame boundary; four passes give 0.008 rad/s, eight rest (the residual back at g·h).

### Expected behavior (checked in-app; written into the commit message)

- **In the air the jet feels the same.** Full roll still spools to 270°/s over about 0.15 s; releasing the stick damps out as before. The single-axis response is exact; a combined pitch-and-roll input differs at second order, because the kinematic path composed three body-axis rotations per frame and the physics path applies one world-frame rotation per substep. The owner flies a circuit and says so.
- **Parked, it stays put:** gear down at idle, for as long as it is left there, and with the brakes held against throttle up to the limit.
- **Touchdown:** the mains take the weight first when the nose is up; the nose drops onto the nose gear within a second or two and stays there. `[Touchdown]` prints once, with the mains' compressions ahead of the nose's.
- **One-wheel arrival** (a few degrees of bank): the jet rolls level and both mains load; no `[Scrape]` from a wingtip.
- **Braking dips the nose** and the jet stops in about the same distance as in D.2.
- **Q/E turn the jet on the ground** at taxi speed; releasing the key ends the turn; the direction matches the airborne yaw direction. If it is reversed, the sign in D.3.3 is wrong, not the tire model.
- **Gear-up belly arrival:** the jet slaps down, slides, and rests without rocking; one `[CRASH]` line for a level slap (two caps, one substep), `[Scrape]` at 1/s after.
- **A wingtip swung into a wall** while turning on the ground prints `[CRASH]` at the tip's speed, not `[Scrape]` at the origin's.
- **The X-key overlay** is unchanged: strut lines are the rest geometry.

### Tests for this step (Metal-free, `.tags(.physics)`)

- [ ] **File (new):** `ToyFlightSimulatorTests/Physics/AttitudeRateControllerTests.swift` (3): `commandedRates` maps pitch/yaw/roll with the negations and nil to zero; `torque` equals `I·(ω_cmd − ω)·(1 − e^(−h/τ))/h` per axis for hand values; and the integration check, on a detached body with `inverseInertiaLocal = diag(1/I)`, gravity off, a hook adding the controller torque for a constant roll command of 1 rad/s with τ = 0.15 s: after 18 substeps (0.15 s) `angularVelocity.z` is 0.632 ± 0.01, after 120 (1 s) 0.999 ± 1e-3, and the accumulated roll angle `atan2(right.y, right.x)` is t − τ(1 − e^(−t/τ)) = 0.850 ± 0.01 rad. This is the "flight feels the same" test for one axis at a time; combined inputs are the owner's circuit.
- [ ] `GearSuspensionWorldTests`: the rig sets `body.inverseInertiaLocal` from `F22SimpleFlightModel().inertia` and runs the controller from its hook (`AttitudeRateController.torque` with `AttitudeDynamics()` and the F-22's inertia, commanded rates zero unless a test sets them) — production has the controller on the ground too, and a rig without it tests a different system (the one-wheel arrival's 26°/s above assumes its damping). **Edits (3):** `settlesOnStruts` asserts the geometric split (nose 0.162 ± 0.01, mains 0.114 ± 0.01), pitch −0.45° ± 0.15° (from `pose().rotation.forward.y`), roll within 0.05°, origin height 1.93 ± 0.02 as before; `bellyImpactClassifiesAsCrash` counts substeps with an impact (1) instead of impact contacts (a level slap has two); the D.2 **brake hold and release** case allows the nose dive that pitch freedom adds — within 2 s of the 100 kN step the origin has moved 2…8 cm forward and the pitch is −1.3°…−2.3° (the replay in Numbers: 4.4 cm and −1.80°), then over the following 5 s `|velocity| < 1e-3` and less than 1 cm more, the hold; the 200 kN release still slides more than 1 m (D.2's strict 1 cm bound stays for the body that cannot pitch; the 4 kN parked case moves 1.8 mm under this rig and needs no change). **Additions (7):** **nose settles last** (start with 4° nose-up — the rotation about X whose sign lifts `pose().rotation.forward.y` — at strut-contact height + 1 cm, sink 1 m/s: the mains compress before the nose does, and after 4 s the pitch is −0.45° ± 0.2°); **one-wheel arrival rolls level** (3° of roll, sink 1 m/s: after 3 s |roll| < 0.3° and both mains carry load within 10% of each other); **steering** (settle, `velocity = [0, 0, 8]`, `steer = 1`: after 2 s `pose().rotation.forward.x < −0.05`, and the mirror for `steer = −1`; the yaw controller damps rates, not angles, so the turn holds against it); **braking dive** (settle, `velocity = [0, 0, 40]`, brake 1: within 1 s the nose compression exceeds its static value by at least 0.05 m, and the jet still stops within 12 s); **belly rest without rocking** (gear up from 2.0 m at −1 m/s: after 5 s |pitch rate| < 0.02 rad/s and |pitch| < 1° — the band one impulse pass fails at 0.029 and eight passes meet); **the parked jet holds** (settle 10 s at its −0.45° stance, then 10 s more: the origin moves less than 1 cm along the runway and `|velocity| < 1e-3` — the first draft's tire would have drifted 2 m); **partition invariance** (the settle from 2.5 m run as 1/30 s frames and as 1/120 s frames: `pose().position` and `pose().rotation` `==` at 5 s, the `FixedTimestepTests.partitioningInvariance` pattern, parameterized over both solvers — the aircraft's force hook and the pair solve are per substep, so nothing may depend on the frame).
- [ ] `CollisionResponseTests` additions (2): **two caps converge** (a detached body of mass 30 000 with `inverseInertiaLocal = diag(1/390_000, 1/440_000, 1/80_000)` at `[0, 1.05, 0]`, velocity `[0, −0.5, 0]`, against a static plane body, two hand-built contacts with normal `[0, 1, 0]` at `[0, 0, −7.5]` and `[0, 0, 8.7]`, through `solveManifold`: afterwards both points' normal velocity is within 0.01 m/s of zero, where one pass leaves the first at −0.52, and no accumulated impulse is negative); **single-contact pairs are untouched** (a one-contact pair through `resolvePair` leaves the velocities `==` those of `correctPosition` + `applyImpulse` alone).
- [ ] `StructureContactTests` additions (2, the classifier at the point): **rotation-only wing strike** (the F-22 with its tensor, `velocity = .zero`, `angularVelocity = [0, 0.5, 0]`, a wall 1 cm from the right wingtip: the first contact's relative point velocity classifies `.impact` at 3.3 ± 0.3 m/s, and `stepStartVelocity` alone would say scrape); **moving object into a parked jet** (a `SphereRigidBody` at 5 m/s into the resting F-22's fuselage: `.impact` at 5 ± 0.5 m/s from the relative velocity, where the aircraft's own is zero).
- [ ] `NarrowPhaseTests` addition (1): a capsule lying along X at height r − 0.1 emits two contacts of depth 0.1 at its two end points, deeper-or-equal first; tilted so one end is clear, it emits one.
- [ ] `CompoundBodyTests.f22CompoundSettlesOnFuselage` stays green unedited (its assertions are a settle band and a set of names); `PhysicsWorldSmokeTests` unedited (spheres).
- [ ] Gate: full serial suite green; dry run byte-identical; the in-app list above, the owner's circuit included. Commit as D-attitude (behavior on the aircraft; goldens untouched).

## D.4 — gated: the manifold solver and beyond

Research §4.5 items 4–5 and §4.6. Not planned in code. Each row names what would start it; without a trigger it is not built. Before any row starts, hold the Jolt go/no-go from §4.6: if the goal is more vehicle and structure gameplay, spike Jolt behind the authoring layer (specs, gear, events, classification, overlay, and tests survive either way); if the goal is owning the solver, build the row natively and stop at the fidelity the trigger asked for.

| Item | Trigger |
|---|---|
| Persistent contact manifolds with warm starting across substeps, angular position correction (D.3's pair solve is per substep: accumulated impulses, no persistence) | A dynamic box or capsule that must rest on a face or stack; creep or rocking that eight iterations do not remove. |
| Tangent (friction) impulses on contacts with a friction cone | A belly slide that should stop; balls that should roll instead of slide; debris that should not glide across the runway. |
| Sleeping (island-based, reversible) | A target scene misses its frame budget; measured, per the Phase A and B non-goals. |
| Continuous collision | Thin structures, or impacts above about 300 m/s, tunnel through a 3 m wall in one substep. |
| `raycastStatics` (ray vs box) for the struts | A deck or roof to land on. |
| Joints and motors (hinge, prismatic with drives) | A mechanism: a towed target, an articulated ground vehicle, a physically swinging door. The gear never needs them. |
| Gyroscopic term ω × (Iω) | Tumbling debris whose wobble matters. |
| A `centerOfMass` offset on `RigidBody` | An aircraft whose model origin is not its center of mass. |
| Aerodynamic moments in the flight model (stability and damping), replacing the controller's damping in the air | A flight-model project of its own; the controller is the stand-in until then. |
| Airspeed-scaled control authority | The parked-jet pitch quirk bothers someone. |

## Phase D non-goals (deferred, with their homes)

- Compression-driven gear visuals: at rest the rendered wheels sit 11–16 cm in the ground (the static compressions). Two options: accept, or **lengthen** `restLength` by each strut's static compression so the origin rests where the rendered wheels touch. The B.5 note said shorten; that lowers the origin by the same amount and buries the wheels twice as deep, because the static compression m·g/Σk does not depend on the reach (checked: −0.12 m as authored, −0.24 m shortened, 0.00 m lengthened). Lengthening is not free either: the stance rises by the compression and the struts touch down that much earlier. Not physics.
- A live strut-compression overlay; the rest-pose lines are enough.
- Brake bindings for controller, HOTAS toe brakes, and iOS touch: the command exists (`ContinuousCommand.Brake`); mapping it is input work.
- Differential braking and a parking brake: rolling resistance holds a parked jet at idle.
- Wind, tire temperature, wet runways: `TireModel`'s constants are where a surface coefficient would enter.
- Angular velocity in `RigidBody.State`: nothing in the flight model reads it yet.

## Phase D exit criteria

1. - [x] **Plumbing changes nothing measurable:** D-angular-plumbing leaves the goldens byte-identical and every suite green unedited; the exact-value tests pin the point-mass result for infinite inertia. *(`14c0bda`, 2026-09-11: dry run byte-identical; every existing suite green with only the listed `zeroForces` edit; the two `applyImpulse` cases pin the point-mass result exactly.)*
2. - [ ] **The jet stops and steers:** `TireModelTests` and the six D.2 world tests green; in-app, brakes stop the jet from 40 m/s in about 200 m, it holds still at idle and against thrust under the brake limit, a crab settles, Q/E turn it at taxi speed.
3. - [ ] **The jet rotates under physics, and flight feels the same:** `AttitudeRateControllerTests` green (the exponential response reproduced per axis); the seven D.3 world tests, the pair-solve cases, and the point-velocity classification cases green; in-app, the owner's circuit, the parked jet that does not creep, the nose-last touchdown, the one-wheel arrival, the braking dive, ground steering in the airborne yaw direction, the rock-free belly rest, and a wingtip swung into a wall printing `[CRASH]`.
4. - [ ] **Goldens byte-identical after every commit** (Phase D regenerates nothing). *(D.1 `14c0bda`: byte-identical.)*
5. - [ ] **No process-wide state:** `AttitudeRateController` and `TireModel` are pure; every new field is per body; determinism and partition tests green. *(D.1 `14c0bda`: `AngularIntegration` is two pure static functions over the entity list; every new field — `angularVelocity`, `torque`, `inverseInertiaLocal`, `stepStartAngularVelocity`, `standaloneRotation` — is per body; `FixedTimestepTests` and the parity suite green in the full run.)*
6. - [ ] **CI green** on all three commits.

**Implementation order:** C.1 → C.2 → D.1 → D.2 → D.3. C.2 needs C.1 (a wing over a wall is box-box). D.2 needs D.1's `addForce(_:atWorldPoint:)` and `velocity(atWorldPoint:)`. D.3 needs both. Phase C and D.1 are independent of each other; C goes first because it is smaller and stands alone.

## CLAUDE.md and skill updates

Land each with its commit, as the Phase B steps did.

- **C.2:** the Physics paragraph gains "**Static structures (Phase C):** `StaticStructure` (GameObjects/) is one box or vertical capsule rendered at its collider's size with a static `.structure` `RigidBody` it creates in its init; scenes add the body to their world (`FlightboxWithPhysics.addStructure`). Box-box is a 15-axis separating-axis test with one contact point, the centroid of the incident face clipped to the reference face (`clippedPoint`: Box2D's manifold reduced to one point); capsule-box is exact (twelve separating axes for a core inside the box, else the end caps and the twelve edges)." The `extending-the-engine` skill's game-object recipe gains a line: "Static scenery with collision: `StaticStructure(name:shape:color:)`, then `entities.append(structure.rigidBody!)` or the scene's helper."
- **D.1** *(done in `14c0bda`)*: the Physics paragraph's composition sentence lists `angularVelocity`, `torque`, `inverseInertiaLocal` (infinite by default), `stepStartAngularVelocity`, `addForce(_:atWorldPoint:)`, `rotate(by:)` (quaternion-normalised); the response description becomes "position correction at the deepest contact, then an impulse with lever arms at the deepest contact — a linear fast path for pairs without finite inertia"; `AngularIntegration`'s two halves are named next to the solvers with their order (ω with the forces and before the contact response in both solvers, orientation with the positions).
- **D.2:** the Landing gear paragraph replaces "No tangent friction, brakes, or steering yet (Phase D): the jet slides." with the tire model (holding friction solved over the wheels as sequential impulses, load along the ground normal), `RayHit`, and the B key; Debugging gains "**'B' key**: wheel brakes (mains)".
- **D.3:** the Attitude paragraph is rewritten: "rotation is torque-driven for aircraft with flight physics: `AttitudeRateController` turns the stick's rate command into a body torque with the `AttitudeDynamics` time constants, gear and contact torques add, and `AngularIntegration` rotates the node from inside the step; aircraft without a body or flight model keep the kinematic lag filter." The Flight Model paragraph adds `inertia`; the Landing gear paragraph adds nosewheel steering and the geometric load split; the Physics paragraph notes the capsule two-cap manifold and the pair solve ("a pair with more than one contact is solved by `solveManifold`: eight sequential-impulse iterations with accumulated, non-negative impulses; single-contact pairs keep the one pass"); the Classification sentence says the reporter classifies the relative velocity at the contact point (`stepStartVelocity(atWorldPoint:)`), impacts deduped per frame per body.
