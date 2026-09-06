# Compound Rigid Bodies — Implementation Plan (simplified), continuation: Phases C and D

**Started:** 2026-09-06 · **Planned against:** the tree at `82f852b` (Phase B closed; CI green on the push head)
**Parent plan:** `plans/claude/compound_rigid_bodies_implementation_plan_simplified.md` holds Phases 0, A, and B, the rules every phase follows, the verification commands, and the golden regeneration procedure. This document continues it; nothing here restates a landed step.
**Design source:** `research/claude/compound_rigid_bodies_research_combined.md` §4.4 (Phase C), §4.5 (Phase D), §4.6 (the Jolt gate), and §3.1 (inertia tensors); `research/claude/compound_rigid_bodies_research_2026-07-14.md` §2.5–§2.6 for the code sketches.

## How this document works

Same as the parent: steps are edited in place to match the code, history goes in the Changelog one line per entry, checkboxes are ticked as steps land, and the code listings are the contract for hand transcription (their comments are the comments to ship). Line numbers are as of `82f852b`; each step says what earlier steps shift.

## Changelog

- **2026-09-06** — Phases C and D planned against `82f852b`. Phase C is two commits (narrow phase, then structures). Phase D is three (angular plumbing, tires and brakes, the aircraft rotates) plus a gated list (D.4) that is not planned in code. Neither phase regenerates a golden: every commit's gate is the byte-identical dry run.

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
| **C-narrowphase** | C.1 | Behavior on paths no golden covers: dry run byte-identical. Every existing suite green; the one test that pins box-box as not implemented is replaced. | `NarrowPhaseTests` additions (box-box ×5, capsule-box ×1) |
| **C-structures** | C.2 | Dry run byte-identical. In-app: the structures render at their collider size, the wall stops the jet, contact lines name the part, the jet flies through the hangar opening clean. | `StaticStructureShapeTests` (new, pure), `StructureContactTests` (new, Metal-free world) |

## Decisions

| Decision | Why |
|---|---|
| One body per structure part, not one compound per structure | The broad phase never pairs two static bodies, so a hangar made of four bodies costs the same as one compound and reports contacts per part (`Hangar_roof`). It also avoids a root node with no mesh of its own: every `GameObject` needs a model, and a compound's root would either render nothing (an empty model is an untested path) or carry a non-uniform scale, which `uniformScale` rejects on a body's node. |
| The mesh is the collider: a bespoke mesh at exact size, node scale 1 | The X-key overlay exists to compare a collider against a hull. When the hull is the collider there is nothing to compare, and nothing to keep in sync. Boxes get `CubeMesh(extent:)`; capsules already have `CapsuleMesh(radius:length:)`. |
| `StaticStructure.Shape` has two cases, box and vertical capsule, in full sizes | Authoring reads as building dimensions (a 40 × 12 × 3 m wall). Reusing `ColliderShape` directly would drag in a sphere case that has no exact-size mesh (`SphereMesh` builds twice the size; the OBJ sphere needs a scale). The mapping to `ColliderShape` is one pure function, tested. |
| Box-box by separating axes with one contact point, placed on the incident feature | Fifteen axes give the least-overlap normal and depth exactly. One point is enough for a strike. The point is taken from the box that pushes into the other's face (corner, edge midpoint, or face center), and for an edge-edge axis from the two edges' closest points, so a wingtip strike in Phase D produces its yaw about the right place. A one-point manifold would make a dynamic box resting on a face rock; no dynamic box exists. |
| Capsule-box by three sphere probes: both end caps and the point nearest the box center, deepest wins | The single center-nearest probe misses a capsule end that enters a face away from the box center (the fuselage nose into a wall corner). Three calls to a routine that exists; exact segment-vs-box distance stays the upgrade if a case is ever missed. |
| Structures set `categoryMask = .structure`; every mask stays `.all` | Filtering stays inert, as Phase A left it. The category is free information for whoever writes the first mask. |
| Structure restitution 0.3 | `min()` with the aircraft's 0.2 keeps the aircraft's value. Debris balls in `FlightboxWithPhysics` carry the default 1.0, so without this they would bounce off walls forever. |
| Struts see planes only | Landing on a roof is not a case. The airframe still collides with the roof (a crash). Ray-vs-box for a deck is a D.4 item. |
| Static bodies keep the per-step world-collider invalidation | Correctness first: the world's start-of-step sweep is what keeps node rotation visible. Thirteen structures × one collider rebuilt per substep is noise. Skipping statics is a one-line optimization with a stated trigger (a scene with hundreds of trees) and a new rule (a static body's node must not move after its first step). Not taken. |
| No overlay work | See "the mesh is the collider". The aircraft overlay is unchanged. |

## Step C.1 — box-box and capsule-box in the narrow phase — C-narrowphase

Why first: the structures are boxes and the F-22's wings and empennage are boxes. Without box-box, a wing through a wall makes no contact at all; with the old capsule-box probe, the fuselage nose into a wall corner can miss.

- [ ] **Edit:** `Physics/Collision/NarrowPhase.swift`, the `(.capsule, .box)` case (lines 174–179):

```swift
            case (.capsule, .box(halfExtents: let he)):
                // Three sphere probes along the core segment: both end caps and
                // the point nearest the box center; the deepest wins. An end
                // entering a face away from the box center, which the single
                // center-nearest probe missed, is found by its cap. Exact
                // segment-vs-box distance is the upgrade if a case is missed.
                let (p0, p1, r) = capsuleSegment(a)
                func deeper(_ best: Contact?, _ center: float3) -> Contact? {
                    guard let candidate = sphereVsBox(center: center, radius: r, box: b,
                                                      halfExtents: he, a: a, b: b) else { return best }
                    guard let best, best.depth >= candidate.depth else { return candidate }
                    return best   // ties keep the earlier probe
                }
                var best: Contact? = nil
                best = deeper(best, p0)
                best = deeper(best, p1)
                best = deeper(best, closestPointOnSegment(p0, p1, to: b.position))
                return best
```

- [ ] **Edit:** the `(.box, .box)` case (lines 184–187):

```swift
            case (.box(halfExtents: let ha), .box(halfExtents: let hb)):
                return boxVsBox(a, halfExtentsA: ha, b, halfExtentsB: hb)
```

- [ ] **Edit:** the new primitive, after `sphereVsBox` (its closing brace is line 261), before `capsuleSegment`:

```swift
    /// Oriented box vs oriented box by separating axes: the six face normals
    /// and the nine edge-edge cross products (Ericson §4.4.1 gives the test;
    /// this keeps each axis's overlap). The contact normal is the axis of
    /// least overlap, pointed from B toward A, and the depth is that overlap.
    /// One contact point, on the incident feature: the corner, edge midpoint,
    /// or face center of the box that pushes into the other's face; for an
    /// edge-edge axis the midpoint of the two edges' closest points. Right for
    /// a strike; a dynamic box resting on a face would rock on one point, and
    /// none exists.
    private static func boxVsBox(_ a: WorldCollider, halfExtentsA ha: float3,
                                 _ b: WorldCollider, halfExtentsB hb: float3) -> Contact? {
        enum Feature { case faceOfA, faceOfB, edges(Int, Int) }
        let d = a.position - b.position
        var leastOverlap = Float.infinity
        var normal = float3.zero
        var feature = Feature.faceOfA

        /// False when `candidate` separates the boxes. Near-parallel edges
        /// give a near-zero cross product and no new axis.
        func overlaps(along candidate: float3, _ candidateFeature: Feature) -> Bool {
            let lengthSquared = simd_length_squared(candidate)
            guard lengthSquared > 1e-6 else { return true }
            let axis = candidate / lengthSquared.squareRoot()
            let reachA = ha.x * abs(dot(a.rotation[0], axis)) + ha.y * abs(dot(a.rotation[1], axis)) + ha.z * abs(dot(a.rotation[2], axis))
            let reachB = hb.x * abs(dot(b.rotation[0], axis)) + hb.y * abs(dot(b.rotation[1], axis)) + hb.z * abs(dot(b.rotation[2], axis))
            let distance = dot(d, axis)
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
            guard overlaps(along: a.rotation[i], .faceOfA), overlaps(along: b.rotation[i], .faceOfB) else { return nil }
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
                if abs(alignment) > 1e-4 {
                    point += box.rotation[i] * (h[i] * (alignment > 0 ? 1 : -1))
                }
            }
            return point
        }

        let point: float3
        switch feature {
            case .faceOfA:
                point = support(b, hb, normal)
            case .faceOfB:
                point = support(a, ha, -normal)
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
- `support` with the parallel-axis rule is what makes the face-face point the face center rather than a corner, and what makes the edge-edge midpoints lie on the edges. Without it two aligned unit cubes would report their contact at a shared corner.
- `matrix_float3x3[i]` is column i, the box's i-th axis in world space. No arrays are built: the step path stays allocation-free.
- Ericson's test skips a cross-product axis when the edges are parallel; so does `overlaps` (`lengthSquared > 1e-6`), returning "not separated" for that axis.

### Tests for this step (`NarrowPhaseTests`, Metal-free)

- [ ] Replace `box-box is pinned NOT IMPLEMENTED: nil even when overlapping` (line 138) with five cases:
  1. **Aligned face overlap.** A: half extents 1 at `[1.5, 0, 0]`; B: half extents 1 at the origin. Normal `[1, 0, 0]`, depth 0.5, point `[1, 0, 0]` (B's +x face center: A's x axis is tested first, ties keep it, so the feature is `faceOfA` and the point is B's support). Also `boxVsBox` through `shapeVsShape(b, a)`: normal `[-1, 0, 0]`, same depth (the point may differ: it lies on the other box's face, which is also correct).
  2. **Separated and touching.** A at `[2.5, 0, 0]` → nil; A at `[2, 0, 0]` → a contact with depth 0 (inclusive gate).
  3. **Rotated box on a face.** A: half extents 1, rotated 45° about Z, center `[0, 1 + √2 − 0.1, 0]`; B: half extents 1 at the origin. Least axis is B's +y face (overlap 0.1; A's own axes overlap by about 0.78 and the y edge-cross ties but loses to the face). Normal `[0, 1, 0]`, depth 0.1 ± 1e-4, point `[0, 0.9, 0]` ± 1e-4 (A's lowest corner: its z axis is at right angles to −y and contributes nothing).
  4. **Edge-edge.** A: half extents `[0.2, 0.2, 2]` (a rod along z) rotated 45° about Z, center `[1, 0.466, 0]`; B: half extents `[2, 0.2, 0.2]` (a rod along x) rotated 45° about X at the origin. The ridges cross at x = 1 with 0.1 m of overlap: normal `[0, 1, 0]` ± 1e-4, depth 0.1 ± 1e-3, point `[1, 0.233, 0]` ± 1e-3. The x = 1 pins the closest-points step: the edge midpoints alone would give x = 0.5.
  5. **Metadata.** Names and groups land on the right sides in both argument orders (extend `A metadata stays on A in both argument orders; normals mirror` at line 239 with a box-box pair).
- [ ] **Capsule-box probe.** Slab B: half extents `[10, 1, 10]` at the origin. Capsule A: radius 0.5, half height 5, rotated 0.9273 rad (53.13°) about Z so its axis is `[-0.8, 0.6, 0]`, center `[5.8, 3.5, 0]`; its end p0 = `[9.8, 0.5, 0]` is inside the slab, its other end `[1.8, 6.5, 0]` and the point nearest the slab's center (`[3.77, 5.02, 0]`) are clear. Expected: a contact with normal `[1, 0, 0]` and depth 0.7 ± 1e-4 (inside-the-box branch: least face distance 0.2 plus the radius). Before this step the same input returned nil.
- [ ] `capsule-box: contact where obviously overlapping, nil where obviously clear` (line 222) stays green unedited.
- [ ] Gate: full serial suite green; dry run byte-identical (no golden has a box or a capsule).

## Step C.2 — `StaticStructure` and the airfield — C-structures

Line numbers in this step are as of `82f852b`; C.1 touched only `NarrowPhase.swift`.

- [ ] **Edit:** `AssetPipeline/Libraries/Meshes/BasicMeshes.swift`, `CubeMesh` (lines 38–60). The unit-cube init becomes a convenience over a full-extent init; the body is unchanged apart from the extent argument:

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

- [ ] **File (new):** `ToyFlightSimulator Shared/GameObjects/StaticStructure.swift`

```swift
//
//  StaticStructure.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/6/26.
//

/// Static scenery with collision: one box or one vertical capsule, rendered
/// at exactly its collider's size (the mesh is the collider, so there is
/// nothing to overlay) and carried by a static RigidBody it creates itself.
/// Build a hangar from several. Static bodies never pair with each other in
/// the broad phase, so one body per part costs nothing over a compound and
/// contacts name the part ("Hangar_roof").
final class StaticStructure: GameObject {
    enum Shape {
        /// Full extents in meters: a 40 × 12 × 3 m wall is [40, 12, 3].
        case box(size: float3)
        /// Vertical, `height` cap to cap.
        case capsule(radius: Float, height: Float)

        /// The same solid as a collider. Pure, tested.
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
    /// units contract for a body's node). Built on the update thread like the
    /// overlay's capsule volumes.
    private static func makeMesh(_ shape: Shape) -> Mesh {
        switch shape {
            case .box(let size):
                return CubeMesh(extent: size)
            case .capsule(let radius, let height):
                return CapsuleMesh(radius: radius, length: height)
        }
    }
}
```

- [ ] **Edit:** `Scenes/FlightboxWithPhysics.swift`. The call goes after the ground-level cube (line 168), before the commented-out `makeRandomDispersedObjects` line at 170:

```swift
        addAirfieldStructures()
```

and the two helpers go after `makeRandomDispersedObjects` (its closing brace is line 101), before `buildScene`:

```swift
    /// Phase C scenery, all ahead of the drop point (+Z is forward) and off
    /// the landing line: an open-front hangar facing the runway, a control
    /// tower, and a tree line either side of a 90 m wide taxi lane.
    private func addAirfieldStructures() {
        let concrete: float4 = [0.6, 0.6, 0.6, 1]
        let bark: float4 = [0.35, 0.25, 0.15, 1]

        // Hangar: 37 m wide opening toward −Z, 40 m deep, 12 m under the roof.
        // Walls are 3 m thick so a 300 m/s arrival (2.5 m per substep) cannot
        // pass through between two substeps; there is no continuous collision.
        addStructure(StaticStructure(name: "Hangar_wallLeft",  shape: .box(size: [3, 12, 40]), color: concrete), at: [70, 6, 300])
        addStructure(StaticStructure(name: "Hangar_wallRight", shape: .box(size: [3, 12, 40]), color: concrete), at: [110, 6, 300])
        addStructure(StaticStructure(name: "Hangar_wallBack",  shape: .box(size: [43, 12, 3]), color: concrete), at: [90, 6, 321.5])
        addStructure(StaticStructure(name: "Hangar_roof",      shape: .box(size: [43, 2, 40]), color: concrete), at: [90, 13, 300])

        addStructure(StaticStructure(name: "Tower", shape: .box(size: [8, 30, 8]), color: concrete), at: [-90, 15, 250])

        for k in 0..<4 {
            let z: Float = 150 + 50 * Float(k)
            addStructure(StaticStructure(name: "Tree_L\(k)", shape: .capsule(radius: 0.5, height: 10), color: bark), at: [-45, 5, z])
            addStructure(StaticStructure(name: "Tree_R\(k)", shape: .capsule(radius: 0.5, height: 10), color: bark), at: [45, 5, z])
        }
    }

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

- The structures render at their collider size and cast shadows like any opaque object. A ball rests on the roof at roof top + its radius.
- Taxi into a wall at 10–15 m/s: `[CRASH] F-22_CGTrader.fuselage hit Hangar_wallLeft at 12.30 m/s (gear down)`, then throttled `[Scrape]` lines while the nose stays pressed against it. The jet does not pass through and rebounds slightly (0.2).
- A wingtip into a tree while taxiing: `wings hit Tree_L2`. A wing over a wall with the fuselage clear: `wings hit Hangar_wallLeft`, the box-box path.
- Through the hangar opening at walking pace with the wings level: no line.

### Tests for this step

- [ ] **File (new):** `ToyFlightSimulatorTests/GameObjects/StaticStructureShapeTests.swift` (pure, `.tags(.physics)`): box maps to half extents; capsule maps to `halfHeight = height/2 − radius`; a capsule with `height ≤ 2·radius` maps to `halfHeight 0` (a sphere-equivalent, which `LocalCollider` accepts).
- [ ] **File (new):** `ToyFlightSimulatorTests/Physics/StructureContactTests.swift` (Metal-free: a static box is `RigidBody(detachedAt:)` with one `.structure` box collider, `isStatic = true`, `shouldApplyGravity = false`; the aircraft is the detached F-22 compound from `CompoundBodyTests`):
  1. **Wall strike.** The F-22 at `[0, 5, -20]` flying +Z at 30 m/s into a 40 × 12 × 3 m wall centered at `[0, 6, 1.5]` (x from −20 to 20, its near face at z = 0), gravity off for a clean read. Within 60 updates: the first contact names `fuselage` against `wall`; `AirframeContactClassifier` on `stepStartVelocity` says `.impact` at 30 ± 0.5 m/s; the wall's position is `==` its start (statics never move); the aircraft ends on the near side (its origin's z below the fuselage's reach into the face) with `velocity.z ≤ 0` (stopped or rebounding at up to 0.2 × 30).
  2. **Wing over a wall.** A 3 × 12 × 40 m wall centered at `[13.5, 6, 0]` (x from 12 to 15, along z); the F-22 at 5 m/s with its origin at `[8.5, 5, -10]`, so the right wing (to x = 15.1) is inside the wall's slab and the fuselage (to x = 9.85) is clear: the first contact names `wings` (box-box), not `fuselage`.
  3. **Ball on a roof.** A `SphereRigidBody` radius 0.5, restitution 0.2, dropped from 3 m onto a box top at y = 1: rests at 1.5 ± 0.02 after 5 s with gravity on.
  4. **Ball against a tree.** A sphere rolling at 3 m/s into a vertical capsule (radius 0.5, half height 4.5): a contact whose normal is horizontal (|n.y| < 1e-3) and whose B name is the tree's.
- [ ] Gate: full serial suite green; dry run byte-identical; the four in-app checks above.

## Phase C non-goals (deferred, with their homes)

- Structures in other scenes, and a structure editor or spec file: `FlightboxWithPhysics` gets the airfield; a scene that wants more calls `addStructure`.
- Struts against structures (landing on a roof or a deck): D.4, `raycastStatics` with ray-vs-box.
- Continuous collision for thin walls at high speed: D.4; the walls are 3 m thick and the note at the call site says why.
- Sharing one mesh between identical parts: thirteen bespoke meshes are fine; revisit with a forest.
- Skipping the per-step collider rebuild for static bodies: the optimization row in Decisions.
- Terrain collision (`FlightboxWithTerrain`): a different problem (height field), not a box.

## Phase C exit criteria

1. - [ ] **Narrow phase:** the five box-box cases and the capsule-box probe case green; every other `NarrowPhaseTests` case green unedited; dry run byte-identical.
2. - [ ] **Structures:** `StaticStructureShapeTests` and `StructureContactTests` green; in-app, the four expected behaviors above hold, including "through the opening: no line".
3. - [ ] **Statics never move:** asserted by the wall-strike test with `==`, and visible in-app after repeated impacts.
4. - [ ] **No process-wide state**; the stress scene's per-call cost is unchanged (structures exist only in `FlightboxWithPhysics`).
5. - [ ] **CI green** on both commits (serial app-hosted run, as configured).

---

# Phase D — ground handling and angular dynamics

Implements combined doc §4.5 items 1–3 and the Phase B non-goals that were handed to Phase D (tangent friction, brakes, steering, torque from asymmetric gear contact). Items 4–5 of §4.5 (sequential impulses with warm starting, friction cones on contacts, joints) are not planned in code here; D.4 lists them with the trigger that would start each and the Jolt gate that comes first.

At the end of this phase:

- the jet stops: wheel brakes on the mains (B key), lateral tire grip that kills a crab and lets the nose lead the velocity, rolling resistance, all as forces at the wheel contact patches;
- the jet rotates under physics: `RigidBody` carries angular velocity, torque, and an inverse inertia tensor; strut and tire forces act at their points and pitch and roll the body; contact impulses have lever arms; the nose settles onto the nose gear after the mains, a one-wheel touchdown rolls level, braking dips the nose, nosewheel steering turns the jet at taxi speed;
- in the air the jet feels the same: the kinematic lag filter becomes a rate controller that produces the torque the filter's ODE implies, with the same maximum rates and time constants;
- every body that is not an aircraft with a flight model is unchanged, bit for bit: infinite inertia is the default, and with it every new term in the response is exactly zero.

**What Phase D does not change:** the flight model's aerodynamics (no aerodynamic moments: pitch stability, roll damping, and yaw stability are still the controller's job), the narrow phase except one capsule-plane manifold, the collider and strut specs' geometry, the overlay, and the goldens.

## Commits

| Commit | Steps | Gate | Tests |
|---|---|---|---|
| **D-angular-plumbing** | D.1 | Plumbing. Every body keeps infinite inertia, so the lever-arm terms are exactly zero and the all-contacts impulse pass sees one contact per sphere pair: dry run byte-identical, every existing suite green unedited (the `zeroForces` test gains one assertion). No in-app change. | `AngularIntegrationTests` (new); additions to `RigidBodyTests`, `CollisionResponseTests`, `PhysicsSolverTests` |
| **D-tires** | D.2 | Behavior on the struts only: dry run byte-identical. In-app: brakes stop the jet from 40 m/s in about 200 m; it holds still on the runway; a crab settles; Q/E turn it at taxi speed (the kinematic yaw filter is still in charge); gear-up belly slides as before (contacts have no friction). | `TireModelTests` (new, pure); four additions to `GearSuspensionWorldTests`; `LandingGearSuspensionTests` signature edits |
| **D-attitude** | D.3 | Behavior on the aircraft only: dry run byte-identical. In-app: flight feels the same; touchdown settles nose-last; a one-wheel arrival rolls level; braking dips the nose; steering works; a belly slap rests without rocking. | `AttitudeRateControllerTests` (new); `GearSuspensionWorldTests` (five additions, two edits); `NarrowPhaseTests` (capsule manifold); `CompoundBodyTests` and `NarrowPhaseTests` call-site edits for the appending `shapeVsPlane` |

## Decisions

| Decision | Why |
|---|---|
| Angular state lives on `RigidBody`, infinite inertia by default | One class, no subclass (the D1 verdict again). The zero inverse inertia makes every new term in the impulse exactly zero, so existing bodies are bit-identical through the response, and an aircraft opts in by receiving a tensor. |
| Orientation stays on the node; physics rotates it through `RigidBody.rotate(by:)`; detached bodies keep a matrix of their own | Mirrors position: `pose()` reads the node, the integrator writes it. The attached camera is a child, so it follows within the frame with no publish step, and there is no quaternion on the body to keep in sync with the node. Codex's `setPhysicsPose` publish (research §4.5 item 1) was for a design where the body owned the pose; here the node does. |
| Semi-implicit Euler for rotation in both solvers, no gyroscopic term | Box2D and Jolt integrate rotation this way. Velocity Verlet's split buys nothing for rotation, and the gyroscopic term ω × (Iω) is negligible at aircraft rates while making an explicit step conditionally stable. |
| The body origin is the center of mass; no offset field | The F-22 strut spec already balances about the origin: the nose carries 0.9/6.1 = 14.8% of the weight, the real jet's split. A `centerOfMass` field would be unread until an aircraft with an off-origin model appears; adding it later is additive. |
| Inertia is authored on the `FlightModel`, synced to the body like mass | Mass lives there today. One `syncMassProperties()` replaces the two mass mirrors in `Aircraft` and adds the tensor. Aircraft without a flight model keep infinite inertia and the kinematic path (the F-16 wingman, `FreeCamFlightboxScene`'s jet). |
| Attitude becomes a rate controller that produces torque; the kinematic filter stays for aircraft without flight physics | The filter's law, dω/dt = (ω_cmd − ω)/τ, multiplied by I is a torque. With no other torque one semi-implicit substep reproduces the filter's exact-exponential update, so the in-air response is unchanged (tested). Gear and contact torques add on top and are damped with the same time constants. |
| No airspeed scaling of control authority | Considered. At zero airspeed the controller acts as rate damping, which is what makes a one-wheel touchdown roll level at a plausible 20°/s instead of snapping. The pilot can pitch the parked jet against its springs (about 10° at full stick); the kinematic model lets the pilot pitch it without limit today. One multiplier if the quirk ever matters. |
| Contact response: lever arms in the impulse, one impulse per contact in order, position correction linear at the deepest | Hecker's full formula (research §3.1 item 2). Applying the impulse at every contact of a pair in sequence is the smallest step toward a manifold solver and what stops a two-point belly rest from rocking. Sphere pairs have one contact, so the goldens do not move. |
| Capsule-plane emits both end caps | A body with pitch freedom resting on its belly needs two points or it rocks between the ends. Box-plane keeps its one corner: no dynamic box rests on a face. |
| Tires: regularized Coulomb friction at the wheel patch with a friction circle, no wheel spin state | JSBSim's `FGLGear` and vehicle games use this shape. The linear region below 0.5 m/s prevents chatter at 120 Hz and settles a crab exponentially. Rolling is the zero of longitudinal slip; brakes scale the longitudinal coefficient. The normal load comes from the strut, so lift unloads the brakes for free. |
| Brakes on the mains only, B key held = full | Real aircraft brake the mains. The keyboard is binary anyway; a controller axis can map to the same 0…1 command later. |
| Nosewheel steering is a steer angle on the nose strut following the yaw input; the yaw controller stays | The turn is torque from the nose tire's lateral force at 5.2 m ahead of the origin: physical, and it exists whether or not the controller has authority. Releasing the key leaves the controller commanding zero yaw rate, which stops the turn. Both use the yaw command's sign. |
| D.2 (tires) before D.3 (rotation) | Ground handling is the visible gap after Phase B and works without torque. Because D.2 already applies its forces at the contact patch through `addForce(_:atWorldPoint:)`, D.3 makes them torque-correct with no rewrite. |
| No aircraft golden; expectations live in `GearSuspensionWorldTests` as physics numbers | Keeps the harness sphere-only and every commit's golden gate a pure dry run. Pitch −0.45°, loads 15/85, and stopping distances read as physics in a test; in JSON they would not. |
| Balls keep infinite inertia | Nothing torques a frictionless sphere: its contact points lie on the line through its center. Giving spheres a tensor changes nothing visible and would not be byte-identical on principle. Revisit with contact friction (D.4). |
| `raycastStaticPlanes` returns a `RayHit` (distance and normal) | The tire needs the ground normal. Phase B's "distance only" decision said nothing read a normal yet; now something does. |
| `SuspensionStrut` gains defaulted `hasBrakes` and `maxSteerAngle` | Per-strut facts, not shared constants. Defaulted trailing properties keep the memberwise init source-compatible for the spec and the tests. |
| `TireModel`'s constants are `static let`s in one enum | Like `HeckerCollisionResponse`'s: one place to tune. |

## Step D.1 — angular state, forces at points, lever-arm impulses — D-angular-plumbing

Everything here is inert until a body gets a finite inertia tensor, which nothing does until D.3. The commit is plumbing: the argument for byte-identity is written into each listing, and the dry run checks it.

Line numbers are as of `82f852b`; Phase C touches none of these files.

- [ ] **Edit:** `Physics/World/RigidBody.swift`, inserted after line 81 (`var stepStartVelocity`), before the world-collider cache comment at 83:

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
    var inverseInertiaLocal: float3x3 = RigidBody.infiniteInertia
    static let infiniteInertia = float3x3(diagonal: .zero)
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
```

- [ ] **Edit:** the same file, rotation storage and writes, inserted after `getPosition()` (line 186), before `getAABB()` at 188:

```swift
    /// Rotation of a detached body. Attached bodies keep theirs on the node,
    /// as with position.
    private var standaloneRotation: float3x3 = matrix_identity_float3x3

    /// Rotates the body by the world-frame angular displacement ω·h (its
    /// direction is the axis, its length the angle). Attached bodies rotate
    /// their node, which dirties the subtree so the attached camera follows
    /// within the frame; detached bodies rotate their own matrix. Invalidates
    /// the world colliders like setPosition (the Phase A note: a rotation
    /// written mid-step must invalidate).
    func rotate(by delta: float3) {
        let angle = simd_length(delta)
        guard angle > 0 else { return }
        invalidateWorldColliders()
        let axis = delta / angle
        if standalonePosition != nil {
            standaloneRotation = float3x3(simd_quatf(angle: angle, axis: axis)) * standaloneRotation
        } else {
            gameObject?.rotate(deltaAngle: angle, axis: axis)
        }
    }

    /// Absolute rotation, for authoring and tests.
    func setRotation(_ rotation: float3x3) {
        invalidateWorldColliders()
        if standalonePosition != nil {
            standaloneRotation = rotation
        } else {
            gameObject?.setRotation(simd_quatf(rotation))
        }
    }
```

`Node.rotate(deltaAngle:axis:)` left-multiplies by the world-axis rotation; the detached branch does the same, so the two agree. `TestRigidBody` (nil GameObject, nil `standalonePosition`) falls into the node branch and does nothing, which is right: it never has finite inertia.

- [ ] **Edit:** `pose()` (lines 218–231): the detached branch returns the body's own rotation, and the doc comment's last sentence becomes "Detached bodies, and attached bodies whose GameObject was released, use their own rotation (identity until rotated) at getPosition()."

```diff
         guard let node = gameObject else {
-            return (getPosition(), matrix_identity_float3x3, 1.0)
+            return (getPosition(), standaloneRotation, 1.0)
         }
```

- [ ] **Edit:** `Physics/Solver/PhysicsSolver.swift`, `zeroForces` (lines 15–21) clears torque too, and `PhysicsEntity.zeroForce()` (`PhysicsEntity.swift:43–45`), its only caller gone, is deleted:

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

- [ ] **File (new):** `ToyFlightSimulator Shared/Physics/Solver/AngularIntegration.swift`

```swift
//
//  AngularIntegration.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/6/26.
//

/// Rotation step shared by both solvers: semi-implicit Euler,
/// ω += I⁻¹_world · τ · h, then rotate by ω · h. Bodies with infinite inertia
/// (the default) are skipped, so their step is unchanged. No gyroscopic term
/// (ω × Iω): small at aircraft rates, and without it the explicit update has
/// no stability condition of its own. Box2D and Jolt integrate rotation the
/// same way; Verlet's split is a linear-only refinement.
enum AngularIntegration {
    static func step(entities: [RigidBody], deltaTime: Float) {
        for entity in entities where !entity.isStatic && entity.hasFiniteInertia {
            entity.angularVelocity += entity.inverseInertiaWorld() * entity.torque * deltaTime
            entity.rotate(by: entity.angularVelocity * deltaTime)
        }
    }
}
```

- [ ] **Edit:** `Physics/Solver/VerletSolver.swift`, inserted before `zeroForces(entities: entities)` (line 55); and `Physics/Solver/EulerSolver.swift`, inserted after `moveObjects(...)` (line 31), before `zeroForces` at 32. The same line in both:

```swift
        AngularIntegration.step(entities: entities, deltaTime: deltaTime)
```

- [ ] **Edit:** `Physics/CollisionResponse/HeckerCollisionResponse.swift`, `resolvePair` (lines 33–51) and `applyCollisionResponse` (lines 53–95). The response splits into a position half and an impulse half; the impulse gains lever arms and runs once per contact:

```swift
    /// One narrow phase per pair: filter, generate contacts, mark the pair as
    /// collided, correct position at the deepest contact, apply an impulse at
    /// every contact, then fire onContact for every contact (handlers see
    /// post-response state). Shared with EulerSolver.
    static func resolvePair(_ entityA: RigidBody, _ entityB: RigidBody, contacts: inout [Contact]) {
        guard entityA.shouldCollide(with: entityB), !entityA.collidedWith.contains(ObjectIdentifier(entityB)) else { return }
        
        let firstNew = contacts.count
        guard let deepest = NarrowPhase.generateContacts(entityA, entityB, into: &contacts) else { return }
        
        entityA.collidedWith.insert(ObjectIdentifier(entityB))
        entityB.collidedWith.insert(ObjectIdentifier(entityA))
        
        // Position once, at the deepest contact; an impulse at every contact
        // in order, each seeing the velocities the one before left (one
        // Gauss-Seidel pass). A pair with one contact — every sphere pair, so
        // every golden — runs the previous sequence exactly.
        correctPosition(entityA, entityB, contact: contacts[deepest])
        for contact in contacts[firstNew...] {
            applyImpulse(entityA, entityB, contact: contact)
        }
        
        for contact in contacts[firstNew...] {
            entityA.onContact?(contact, entityB)
            entityB.onContact?(contact.flipped, entityA)
        }
    }

    /// Moves the bodies apart along the normal by β × (depth − slop), split by
    /// inverse mass. Linear only: the angular share of position correction
    /// belongs to a manifold solver (D.4), if one is ever built.
    static func correctPosition(_ entityA: RigidBody, _ entityB: RigidBody, contact: Contact) {
        let n = contact.normal                       // unit, from B toward A
        let invMassA: Float = entityA.isStatic ? 0 : 1 / entityA.mass
        let invMassB: Float = entityB.isStatic ? 0 : 1 / entityB.mass
        let invMassSum = invMassA + invMassB
        guard invMassSum > 0 else { return }         // two statics: nothing to move

        let correction = positionCorrectionBeta * max(0, contact.depth - penetrationSlop) / invMassSum
        guard correction > 0 else { return }
        if !entityA.isStatic {
            entityA.setPosition(entityA.getPosition() + n * (correction * invMassA))
        }
        if !entityB.isStatic {
            entityB.setPosition(entityB.getPosition() - n * (correction * invMassB))
        }
    }

    /// Normal impulse at the contact point, Hecker's full form: the relative
    /// velocity and the effective mass include the lever arms r = point −
    /// origin through each body's world inverse inertia. For a body with
    /// infinite inertia both angular terms are exactly zero, so the
    /// point-mass arithmetic of Phase A is unchanged bit for bit. Symmetric in
    /// inverse mass: a static body neither moves nor changes velocity.
    static func applyImpulse(_ entityA: RigidBody, _ entityB: RigidBody, contact: Contact) {
        let n = contact.normal
        let invMassA: Float = entityA.isStatic ? 0 : 1 / entityA.mass
        let invMassB: Float = entityB.isStatic ? 0 : 1 / entityB.mass
        guard invMassA + invMassB > 0 else { return }

        // Impulse only when approaching at the point (n points toward A, so
        // approaching means relative velocity along −n).
        let rA = contact.point - entityA.getPosition()
        let rB = contact.point - entityB.getPosition()
        let approach = dot(entityA.velocity(atWorldPoint: contact.point) - entityB.velocity(atWorldPoint: contact.point), n)
        guard approach < 0 else { return }

        // Restitution only above the threshold; below it e = 0 and the normal
        // velocity is cancelled exactly (the support impulse).
        let e = -approach > restitutionVelocityThreshold ? min(entityA.restitution, entityB.restitution) : 0

        // Effective mass along n at the point.
        let invInertiaA = entityA.isStatic ? RigidBody.infiniteInertia : entityA.inverseInertiaWorld()
        let invInertiaB = entityB.isStatic ? RigidBody.infiniteInertia : entityB.inverseInertiaWorld()
        let angularA = dot(cross(invInertiaA * cross(rA, n), rA), n)
        let angularB = dot(cross(invInertiaB * cross(rB, n), rB), n)
        let j = -(1 + e) * approach / (invMassA + invMassB + angularA + angularB)

        if !entityA.isStatic {
            entityA.velocity += n * (j * invMassA)
            entityA.angularVelocity += invInertiaA * cross(rA, n * j)
        }
        if !entityB.isStatic {
            entityB.velocity -= n * (j * invMassB)
            entityB.angularVelocity -= invInertiaB * cross(rB, n * j)
        }
    }
```

Why this is byte-identical for every current body: `angularVelocity` is zero, so `velocity(atWorldPoint:)` adds a zero vector to `velocity` and the dot product is unchanged; the zero inverse inertia makes `angularA` and `angularB` exactly 0, and adding 0 to the inverse-mass sum leaves it unchanged; the angular velocity update adds a zero vector. The only sign-of-zero differences (a −0 where a +0 was) cannot change a compare or a product. `correctPosition` is the old block verbatim. With one contact per pair the sequence is position, impulse, events, as before. Lever arms are measured from the post-correction origin; the difference is the β-fraction of a penetration, millimeters.

The `applyCollisionResponse` name goes; nothing outside this file called it.

### Tests for this step (Metal-free, `.tags(.physics)`)

- [ ] `RigidBodyTests` additions (4): the default tensor is infinite and `hasFiniteInertia` is false; `addForce(_:atWorldPoint:)` on a detached body at the origin with force `[0, 10, 0]` at `[2, 0, 0]` gives torque `[0, 0, 20]` and the same force; `rotate(by: [0, .halfPi, 0])` on a detached body turns `pose().rotation.forward` to `[1, 0, 0]` within 1e-5 and marks the world colliders dirty (the rebuild-count discipline of `worldColliderCacheRebuildDiscipline`); `inverseInertiaWorld()` for `inverseInertiaLocal = diag(1, 2, 3)` after `setRotation` by 90° about Y is `diag(3, 2, 1)` within 1e-5.
- [ ] **File (new):** `ToyFlightSimulatorTests/Physics/AngularIntegrationTests.swift` (4, parameterized over `.NaiveEuler` and `.HeckerVerlet` where a world is stepped): an infinite-inertia body with a constant torque hook never rotates and keeps `angularVelocity == .zero`; a detached body with `inverseInertiaLocal = diag(0.5)`, gravity off, and a hook adding torque `[2, 0, 0]` has `angularVelocity.x == fixedDelta` after one substep (`0.5 · 2 · h`) and has rotated about X by `h·h` rad; a static body with finite inertia and torque does not rotate; `torque` is zero after every step (`zeroForces`).
- [ ] `PhysicsSolverTests.zeroForcesClearsAllForces` also sets and asserts `torque`.
- [ ] `CollisionResponseTests` additions (2), through `HeckerCollisionResponse.applyImpulse` with a hand-built `Contact`: A is a detached body, mass 2, velocity `[0, −1, 0]`, against a static plane body, contact normal `[0, 1, 0]` at point `[1, 0, 0]` with A's origin at `[0, 0, 0]`. With `inverseInertiaLocal = diag(0.5)`: the angular term is 0.5, the denominator 1.0, j = 1 (e = 0 at exactly the threshold), so `velocity == [0, −0.5, 0]` and `angularVelocity == [0, 0, 0.5]` exactly. With infinite inertia the same call gives `velocity == .zero` and `angularVelocity == .zero`: the point-mass result, exact.
- [ ] Gate: full serial suite green with no other edit; dry run byte-identical. Commit as D-angular-plumbing (plumbing, rule 2).

## Step D.2 — tires, brakes, and the ground normal — D-tires

Why: since B.5 the jet stands on its wheels and slides on them. Every ground-handling gap (stopping, holding position, a crab, a turn that the velocity follows) is one tangent force at each loaded wheel. The force needs the normal load (the strut has it), the patch velocity (`velocity(atWorldPoint:)` from D.1), the ground normal (the raycast has the plane, not yet its normal), and a brake command. No angular state is involved: with infinite inertia the forces at the patch act on the center, and the kinematic yaw filter still turns the nose. D.3 makes the same forces torque-correct without touching this step's code.

Line numbers are as of `82f852b` for files D.1 did not touch (`PhysicsWorld.swift`, `ControlInput.swift`, `InputManager.swift`, `Aircraft.swift`, `SuspensionStrut.swift`, `AircraftLandingGearSpec.swift`, `LandingGearSuspension.swift`).

- [ ] **Edit:** `Physics/World/PhysicsWorld.swift`, `raycastStaticPlanes` (lines 139–154) returns the hit's normal with its distance. The struct goes above `final class PhysicsWorld`, after the `PhysicsUpdateType` enum (line 13):

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

/// Tangent force of one loaded wheel, pure. Regularized Coulomb friction:
/// the force grows in proportion to slip speed up to μ·N at `slipSpeed`, so
/// a rolling wheel does not chatter at 120 Hz and a crab settles smoothly,
/// and the lateral and longitudinal parts together are clamped to the
/// friction circle. There is no wheel spin state: rolling is the zero of
/// longitudinal slip, and braking scales the longitudinal coefficient.
/// JSBSim's FGLGear and most vehicle games use this shape.
enum TireModel {
    static let lateralFriction: Float = 0.8       // cornering grip, dry runway
    static let brakeFriction: Float = 0.5         // fully braked wheel, dry
    static let rollingResistance: Float = 0.02
    /// Slip speed at which the force reaches its full Coulomb value, m/s.
    static let slipSpeed: Float = 0.5

    /// `rollingDirection` is the wheel's forward axis (body forward, steered
    /// or not); it is projected onto the ground plane here. Zero when the
    /// wheel is unloaded or its axis is normal to the ground.
    static func force(normalLoad: Float,
                      patchVelocity: float3,
                      groundNormal n: float3,
                      rollingDirection: float3,
                      brake: Float) -> float3 {
        guard normalLoad > 0 else { return .zero }
        let inPlane = rollingDirection - n * dot(rollingDirection, n)
        guard simd_length_squared(inPlane) > 1e-4 else { return .zero }
        let forward = simd_normalize(inPlane)
        let side = cross(n, forward)

        let longitudinalCoefficient = rollingResistance + brake * brakeFriction
        let longitudinal = -longitudinalCoefficient * normalLoad * slipFraction(dot(patchVelocity, forward))
        let lateral = -lateralFriction * normalLoad * slipFraction(dot(patchVelocity, side))

        var force = forward * longitudinal + side * lateral
        let limit = lateralFriction * normalLoad
        let magnitude = simd_length(force)
        if magnitude > limit {
            force *= limit / magnitude
        }
        
        return force
    }

    /// −1…1: proportional below slipSpeed, saturated above.
    private static func slipFraction(_ speed: Float) -> Float {
        max(-1, min(1, speed / slipSpeed))
    }
}
```

- [ ] **Edit:** `Physics/Vehicle/LandingGearSuspension.swift`, `accumulateForces` (lines 42–90). The signature gains `brake:`; the ray returns a hit; the strut force and the tire force are applied together at the contact patch through `addForce(_:atWorldPoint:)`:

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
        // Body up, the strut axis: rays go down −up, force pushes +up. Not
        // float3.up, which is world up — a rolled aircraft's struts roll with it.
        let up = pose.rotation.up
        // Wheels roll along body forward; TireModel projects it onto the ground.
        let forward = pose.rotation.forward

        for (i, strut) in struts.enumerated() {
            let attachWorld = pose.position + pose.rotation * (strut.attachLocal * pose.uniformScale)
            let hit = world.raycastStaticPlanes(from: attachWorld, direction: -up)
            let step = SuspensionSolver.solve(strut: strut,
                                              uniformScale: pose.uniformScale,
                                              distanceToGround: hit?.distance,
                                              previousCompression: compressions[i],
                                              substepDelta: substepDelta)
            compressions[i] = step.compression

            if let hit, step.force > 0 {
                // Strut force along body up plus the tire's tangent force, at
                // the contact patch on the ground. The strut's own force is
                // colinear with its attach point, so its moment does not
                // depend on the point; the tire's does, and a braking force at
                // ground level pitches the nose down once the body can pitch.
                let patch = attachWorld - up * hit.distance
                let tire = TireModel.force(normalLoad: step.force,
                                           patchVelocity: body.velocity(atWorldPoint: patch),
                                           groundNormal: hit.normal,
                                           rollingDirection: forward,
                                           brake: strut.hasBrakes ? brake : 0)
                body.addForce(up * step.force + tire, atWorldPoint: patch)
            }

            // Rising edge only: one event per exceedance, per strut.
            if step.overloaded && !wasOverloaded[i] {
                onLandingGearEvent?(.gearOverload(strutName: strut.name,
                                                  force: step.force,
                                                  bottomedOut: step.bottomedOut))
            }

            wasOverloaded[i] = step.overloaded
        }

        // (weight-on-wheels block unchanged)
    }
```

`body.force += up * step.force` is gone: `addForce(_:atWorldPoint:)` adds the same force and accumulates a torque that nothing integrates until D.3. The sink rate stays `−velocity.y` (level runway; `hit.normal` is at hand when the tilted-runway one-liner is wanted).

### Numbers (F-22 at 30 t, the same rig as B.4)

- Static loads with the 89/11 split of a body that cannot pitch: mains 131 kN each, nose 32 kN.
- Braking from 40 m/s: μ = 0.02 + 0.5 = 0.52 on the mains, deceleration ≈ 0.52 × 0.89 × g ≈ 4.5 m/s², stop in about 9 s and 180 m. After D.3 the geometric split and the braking pitch move this by a few percent; the test band covers both.
- Lateral grip: 0.8 × 294 kN ≈ 235 kN, up to 7.8 m/s² against a crab; a 5 m/s sideways drift is gone in about a second. Below 0.5 m/s the force is proportional, so the crab decays exponentially with time constant m / Σ(μN / slipSpeed) ≈ 30 000 / 470 000 ≈ 0.06 s.
- Stability of the linear region at 1/120 s: per-substep gain (Σc / m) · h ≈ 0.13, well under 1.
- Rolling resistance alone: 0.02 g ≈ 0.2 m/s²; a taxiing jet coasts a long way, as real ones do.

### Expected behavior (checked in-app; written into the commit message)

- **The jet stops.** Land, hold B: from 40 m/s the roll-out is about 200 m. Release: it coasts. Hold B at rest: it stays put with throttle at idle; with throttle up it creeps once thrust exceeds 0.52 × the main-gear load.
- **A crab settles.** Touch down with a few degrees of yaw: the velocity swings to the nose within a second (the mains skid a little); no drift across the runway.
- **Q/E turn the jet at taxi speed** through the kinematic yaw filter, and the velocity follows the nose. The turn is not yet physical; D.3 adds nosewheel steering.
- **Gear up:** the belly slide is unchanged (contacts have no friction; D.4).

### Tests for this step (Metal-free, `.tags(.physics)`)

- [ ] **File (new):** `ToyFlightSimulatorTests/Physics/TireModelTests.swift` (7, pure, N = 1000 for exact numbers): unloaded → zero; lateral slip 2 m/s (saturated) → `−800 · side`; lateral slip 0.25 m/s → `−400 · side` (linear region); rolling at 20 m/s with no brake → `−20 · forward`, with brake 1 → `−520 · forward`; saturated lateral plus saturated brake → magnitude 800, not 940 (the circle); the force has no component along the ground normal; a rolling direction along the normal → zero.
- [ ] `GearSuspensionWorldTests` additions (4; the rig's hook passes a `brake` field, default 0): **braking stop** (settle 10 s, then `velocity = [0, 0, 40]`, brake 1: `|velocity| < 0.5` within 12 s, distance travelled in 150…260 m); **crab settles** (settle, `velocity = [5, 0, 0]`: `|velocity.x| < 0.1` after 2 s, less than 3 m moved); **coasting** (settle, `velocity = [0, 0, 20]`, no brake: speed after 5 s is 20 − 0.98 ± 0.2); **gear up slides** (from the belly rest with `velocity = [0, 0, 5]`: speed after 2 s is at least 4.5, pinning that contacts carry no friction).
- [ ] `LandingGearSuspensionTests`: every `accumulateForces` call gains `brake: 0`; the raycast test reads `.distance`. The force expectations hold unedited: every existing case has a vertical velocity only, so the tire's slip is zero and its force exactly zero.
- [ ] Gate: full serial suite green; dry run byte-identical; the four in-app behaviors above. Commit as D-tires (behavior on the struts; goldens untouched).

## Step D.3 — the aircraft rotates — D-attitude

Why: everything Phase B deferred to "when the body can pitch" lands here: the nose settling after the mains, a one-wheel touchdown rolling level, the geometric gear load split, braking dive, steering that turns the jet through its tires. The prerequisite is a rotation that physics owns, and the constraint is that flight must feel as it does today.

The attitude filter is already an ordinary differential equation, dω/dt = (ω_cmd − ω)/τ per axis. Multiplied by the inertia it is a torque. So the filter does not go away; it moves inside the step as a rate controller, and its output becomes one torque among others. With no other torque a semi-implicit substep reproduces the filter's exact-exponential update, so the in-air trajectory is the one the kinematic path produced. Gear and contact torques add, and the controller damps them with the same time constants: on the ground it behaves like a stability-augmentation system that opposes rates, not angles, so the gear's spring torques still turn the aircraft to its equilibrium at a plausible rate.

Aircraft without a body or without a flight model keep the kinematic path unchanged: the F-16 wingman has no body, `FreeCamFlightboxScene`'s jet has no flight model. The rule is "an aircraft with flight physics flies by forces and torques; the rest move as before".

Line numbers: `FlightModel.swift`, `F22SimpleFlightModel.swift`, and the `Aircraft.swift` property block are as of `82f852b`; `Aircraft.doUpdate`/`generateForces` and `LandingGearSuspension.accumulateForces` are after D.2 (locate by the text quoted); `NarrowPhase.shapeVsPlane` is after C.1 (locate by the `// MARK: - Shape vs plane` section).

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
    /// model keeps the body's defaults: mass 1 and infinite inertia.
    private func syncMassProperties() {
        guard let flightModel, let rigidBody else { return }
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
            }

            applyPlayerSideMove(deltaMove: deltaMove)
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

and `rollingDirection: rolling` in the `TireModel.force` call.

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

Call sites: `generateContacts`; `CompoundBodyTests.bankedPoseContactsWingsOnly`; seven cases in `NarrowPhaseTests`. A three-line helper in each test file, `planeContacts(_:planePoint:planeNormal:) -> [Contact]`, keeps each edit to one line. A level belly slap now fires two `onContact`s per substep (both caps), so `TouchdownReporter` prints two `[CRASH]` lines for it; accepted and noted in its doc comment.

### Numbers (F-22 at 30 t)

- **Static split with pitch freedom:** nose 0.9/6.1 = 14.75% of 294.3 kN = 43.4 kN → compression 0.162 m; mains 125.4 kN each → 0.114 m. Pitch −0.45° (nose down, 48 mm over 6.1 m). Origin height 1.929 m: `staticStance`'s 1.931 is still the number the overlay logs; its doc comment gains "ignores the pitch equilibrium, a 2 mm difference at the origin".
- **Gear stiffness about the origin:** pitch Σk·z² = 268 k × 5.2² + 2 × 1.1 M × 0.9² ≈ 9.0 MN·m/rad; roll 2 × 1.1 M × 1.62² ≈ 5.8 MN·m/rad. With I_pitch 390 k and I_roll 80 k: ω_n ≈ 4.8 rad/s (1.3 s) and 8.5 rad/s (0.74 s); damping ratios from Σc·z² ≈ 0.31 (pitch) and 0.56 (roll) before the controller's own damping. Per-substep factors (Σc·z²/I)·h ≈ 0.025 and 0.08: stable with margin.
- **Controller authority:** full pitch command asks for 390 k × 1 / 0.25 ≈ 1.6 MN·m against 9.0 MN·m/rad of gear stiffness: a parked jet pitches about 10° at full stick (the kinematic model had no limit). At ω = 0 the roll controller's opposing torque per unit rate is I/τ = 530 kN·m per rad/s; a one-wheel touchdown's spring torque (one main at 1.62 m carrying half the weight, 238 kN·m) rolls the jet level at a steady 0.45 rad/s, 26°/s, then the second main takes up the load.
- **Braking dive:** 0.52 × 250 kN at the patch, 1.93 m below the origin: 250 kN·m nose-down, 41 kN more on the nose gear, +0.15 m nose compression (travel 0.40). Visible, and what real jets do.

### Expected behavior (checked in-app; written into the commit message)

- **In the air the jet feels the same.** Full roll still spools to 270°/s over about 0.15 s; releasing the stick damps out as before. The owner flies a circuit and says so.
- **Touchdown:** the mains take the weight first when the nose is up; the nose drops onto the nose gear within a second or two and stays there. `[Touchdown]` prints once, with the mains' compressions ahead of the nose's.
- **One-wheel arrival** (a few degrees of bank): the jet rolls level and both mains load; no `[Scrape]` from a wingtip.
- **Braking dips the nose** and the jet stops in about the same distance as in D.2.
- **Q/E turn the jet on the ground** at taxi speed; releasing the key ends the turn; the direction matches the airborne yaw direction. If it is reversed, the sign in D.3.3 is wrong, not the tire model.
- **Gear-up belly arrival:** the jet slaps down, slides, and rests without rocking; two `[CRASH]` lines for a level slap, `[Scrape]` at 1/s after.
- **The X-key overlay** is unchanged: strut lines are the rest geometry.

### Tests for this step (Metal-free, `.tags(.physics)`)

- [ ] **File (new):** `ToyFlightSimulatorTests/Physics/AttitudeRateControllerTests.swift` (3): `commandedRates` maps pitch/yaw/roll with the negations and nil to zero; `torque` equals `I·(ω_cmd − ω)·(1 − e^(−h/τ))/h` per axis for hand values; and the integration check, on a detached body with `inverseInertiaLocal = diag(1/I)`, gravity off, a hook adding the controller torque for a constant roll command of 1 rad/s with τ = 0.15 s: after 18 substeps (0.15 s) `angularVelocity.z` is 0.632 ± 0.01, after 120 (1 s) 0.999 ± 1e-3, and the accumulated roll angle `atan2(right.y, right.x)` is t − τ(1 − e^(−t/τ)) = 0.850 ± 0.01 rad. This is the "flight feels the same" test.
- [ ] `GearSuspensionWorldTests`: the rig sets `body.inverseInertiaLocal` from `F22SimpleFlightModel().inertia`. **Edits (2):** `settlesOnStruts` asserts the geometric split (nose 0.162 ± 0.01, mains 0.114 ± 0.01), pitch −0.45° ± 0.15° (from `pose().rotation.forward.y`), roll within 0.05°, origin height 1.93 ± 0.02 as before; `bellyImpactClassifiesAsCrash` counts substeps with an impact (1) instead of impact contacts (a level slap has two). **Additions (5):** **nose settles last** (start with 4° nose-up — the rotation about X whose sign lifts `pose().rotation.forward.y` — at strut-contact height + 1 cm, sink 1 m/s: the mains compress before the nose does, and after 4 s the pitch is −0.45° ± 0.2°); **one-wheel arrival rolls level** (3° of roll, sink 1 m/s: after 3 s |roll| < 0.3° and both mains carry load within 10% of each other); **steering** (settle, `velocity = [0, 0, 8]`, `steer = 1`: after 2 s `pose().rotation.forward.x < −0.05`, and the mirror for `steer = −1`; no controller in the rig, so this is the tire torque alone); **braking dive** (settle, `velocity = [0, 0, 40]`, brake 1: within 1 s the nose compression exceeds its static value by at least 0.05 m, and the jet still stops within 12 s); **belly rest without rocking** (gear up from 2.0 m at −1 m/s: after 5 s |pitch rate| < 0.02 rad/s and |pitch| < 1°).
- [ ] `NarrowPhaseTests` addition (1): a capsule lying along X at height r − 0.1 emits two contacts of depth 0.1 at its two end points, deeper-or-equal first; tilted so one end is clear, it emits one.
- [ ] `CompoundBodyTests.f22CompoundSettlesOnFuselage` stays green unedited (its assertions are a settle band and a set of names); `PhysicsWorldSmokeTests` unedited (spheres).
- [ ] Gate: full serial suite green; dry run byte-identical; the in-app list above, the owner's circuit included. Commit as D-attitude (behavior on the aircraft; goldens untouched).

## D.4 — gated: the manifold solver and beyond

Research §4.5 items 4–5 and §4.6. Not planned in code. Each row names what would start it; without a trigger it is not built. Before any row starts, hold the Jolt go/no-go from §4.6: if the goal is more vehicle and structure gameplay, spike Jolt behind the authoring layer (specs, gear, events, classification, overlay, and tests survive either way); if the goal is owning the solver, build the row natively and stop at the fidelity the trigger asked for.

| Item | Trigger |
|---|---|
| Persistent contact manifolds, sequential impulses with accumulated-impulse clamping and warm starting, angular position correction | A dynamic box or capsule that must rest on a face or stack; visible rocking or creep after D.3's two-point belly rest. |
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

- Compression-driven gear visuals: at rest the rendered wheels sit 11–16 cm in the ground (the static compressions). The two options from B.5 stand: accept, or shorten `restLength` by the static compression per strut. Not physics.
- A live strut-compression overlay; the rest-pose lines are enough.
- Brake bindings for controller, HOTAS toe brakes, and iOS touch: the command exists (`ContinuousCommand.Brake`); mapping it is input work.
- Differential braking and a parking brake: rolling resistance holds a parked jet at idle.
- Wind, tire temperature, wet runways: `TireModel`'s constants are where a surface coefficient would enter.
- Angular velocity in `RigidBody.State`: nothing in the flight model reads it yet.

## Phase D exit criteria

1. - [ ] **Plumbing changes nothing measurable:** D-angular-plumbing leaves the goldens byte-identical and every suite green unedited; the exact-value tests pin the point-mass result for infinite inertia.
2. - [ ] **The jet stops and steers:** `TireModelTests` and the four D.2 world tests green; in-app, brakes stop the jet from 40 m/s in about 200 m, it holds still at idle, a crab settles, Q/E turn it at taxi speed.
3. - [ ] **The jet rotates under physics, and flight feels the same:** `AttitudeRateControllerTests` green (the exponential response reproduced); the five D.3 world tests green; in-app, the owner's circuit, the nose-last touchdown, the one-wheel arrival, the braking dive, ground steering in the airborne yaw direction, and the rock-free belly rest.
4. - [ ] **Goldens byte-identical after every commit** (Phase D regenerates nothing).
5. - [ ] **No process-wide state:** `AttitudeRateController` and `TireModel` are pure; every new field is per body; determinism and partition tests green.
6. - [ ] **CI green** on all three commits.

**Implementation order:** C.1 → C.2 → D.1 → D.2 → D.3. C.2 needs C.1 (a wing over a wall is box-box). D.2 needs D.1's `addForce(_:atWorldPoint:)` and `velocity(atWorldPoint:)`. D.3 needs both. Phase C and D.1 are independent of each other; C goes first because it is smaller and stands alone.

## CLAUDE.md and skill updates

Land each with its commit, as the Phase B steps did.

- **C.2:** the Physics paragraph gains "**Static structures (Phase C):** `StaticStructure` (GameObjects/) is one box or vertical capsule rendered at its collider's size with a static `.structure` `RigidBody` it creates in its init; scenes add the body to their world (`FlightboxWithPhysics.addStructure`). Box-box is a 15-axis separating-axis test with one contact point on the incident feature; capsule-box probes both end caps and the center-nearest point." The `extending-the-engine` skill's game-object recipe gains a line: "Static scenery with collision: `StaticStructure(name:shape:color:)`, then `entities.append(structure.rigidBody!)` or the scene's helper."
- **D.1:** the Physics paragraph's composition sentence lists `angularVelocity`, `torque`, `inverseInertiaLocal` (infinite by default), `addForce(_:atWorldPoint:)`, `rotate(by:)`; the response description becomes "position correction at the deepest contact, an impulse with lever arms at every contact in order"; `AngularIntegration` is named next to the solvers.
- **D.2:** the Landing gear paragraph replaces "No tangent friction, brakes, or steering yet (Phase D): the jet slides." with the tire model, `RayHit`, and the B key; Debugging gains "**'B' key**: wheel brakes (mains)".
- **D.3:** the Attitude paragraph is rewritten: "rotation is torque-driven for aircraft with flight physics: `AttitudeRateController` turns the stick's rate command into a body torque with the `AttitudeDynamics` time constants, gear and contact torques add, and `AngularIntegration` rotates the node from inside the step; aircraft without a body or flight model keep the kinematic lag filter." The Flight Model paragraph adds `inertia`; the Landing gear paragraph adds nosewheel steering and the geometric load split; the Physics paragraph notes the capsule two-cap manifold.
