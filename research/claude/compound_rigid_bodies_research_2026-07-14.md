# Compound Rigid Bodies, Joints, and Landing-Gear Physics

**Date:** 2026-07-14
**Goal:** ToyFlightSimulator currently has exactly two rigid-body types — `SphereRigidBody` and `PlaneRigidBody` — and the player aircraft is, physically, a 2 m sphere. The objects we want to simulate are much richer: aircraft with wings, retractable landing gear that should contact the runway precisely, movable control surfaces, and (in the future) helicopters, ground vehicles, and structures like towers, hangars, and trees. This doc researches how games and game engines build complex physical objects out of simple primitive bodies — compound shapes, joints, constraints, and force models — and then proposes a concrete, phased implementation for this engine (Swift + Metal), with code samples and diffs.

**Method:** The research section was produced by a deep-research pipeline (107 agents: 5 search angles → 15 source fetches → claim extraction → 3-voter adversarial verification per claim → synthesis). Every claim below marked **[verified]** survived a unanimous 3-0 adversarial vote against primary sources (vendor docs / SDK manuals / source code). Two claims were refuted during verification and are *excluded*; §1.6 lists them plus the coverage gaps. Four sources (the three starter links from the request plus Unity's WheelCollider tutorial) were fetched and read directly, and are cited as **[fetched]**. The TFS analysis in Part 2 is grounded in the current code at `ToyFlightSimulator Shared/Physics/` and `GameObjects/`.

---

## Executive Summary

1. **Complex dynamic objects are one rigid body carrying many primitive shapes, not many bodies.** Every surveyed engine (Unity/PhysX, Bullet, Jolt, Defold) models a vehicle as a *single* rigid body whose collision geometry is a **compound** of cheap convex primitives. Joints connecting separate bodies are the tool for *mechanisms* (ragdolls, trailers, cranes), not for assembling a hull out of parts. **[verified]**

2. **The primitive vocabulary converges everywhere: sphere < capsule < box < convex hull, in documented cost order.** Concave triangle meshes are effectively banned on dynamic bodies (Unity errors at runtime; PhysX requires a precomputed SDF; Bullet routes them to static geometry), and PhysX caps convex hulls at 255 vertices/faces — which is *why* engines push you toward a handful of primitives per object. **[verified]**

3. **Wheels and landing gear are not bodies at all in the industry pattern.** Bullet's manual recommends `btRaycastVehicle` — "the entire vehicle is represented as a single rigidbody, the chassis; the collision detection of the wheels is approximated by ray casts" — and calls this model "widely used in commercial driving games." Jolt's `VehicleConstraint` likewise "adds virtual wheels or tracks to a body." Unity's WheelCollider is the same idea productized: a spring (default 35,000 N/m) + damper (4,500 N·s/m) suspension along a travel distance, with no wheel rigid body. **[verified / fetched]**

4. **Gear/strut articulation is kinematic animation of collision geometry, not physical joints.** The engine-level mechanism for "collision children that move" is Jolt's `MutableCompoundShape` (flat list, cheap to reposition) vs. `StaticCompoundShape` (immutable, BVH-accelerated); Unity documents the same pattern via animated child colliders — with a caveat that moving children re-shifts the auto-computed center of mass unless you pin it manually. The PBY-5A gear-rigging article shows the animation side: an entire multi-piston mechanism driven by *one* control parameter — exactly what TFS's `gearAnimationProgress` already is. **[verified / fetched]**

5. **Joints exist for the day two bodies must move relative to each other under physics.** All joints, contacts, and collisions are solved uniformly as *constraints* (Catto GDC 2009), production-solved by Sequential Impulses with warm starting; Jolt ships 13 constraint types and drives motors with `stiffness·(targetPos − pos) + damping·(targetVel − vel)`. This machinery *requires angular dynamics* (orientation, angular velocity, inertia tensors) — which TFS's physics does not have yet (rotation is kinematic). Joints are therefore Phase D here, after compound colliders and raycast gear, and the research says you may never need them for the gear at all. **[verified]**

6. **For TFS specifically:** add a shape vocabulary (`sphere`/`capsule`/`box`), a `CompoundRigidBody` holding `LocalCollider`s, a small pair-dispatch narrow phase producing `Contact`s (normal + depth + point + which sub-collider), collision filtering masks, and contact callbacks — then model landing gear as raycast spring-damper struts on the aircraft body, gated by the existing `gearAnimationProgress`. Crash-vs-landing becomes trivial: any *airframe*-collider contact is a crash; wheels never generate contacts because suspension catches the aircraft first. Part 2 has the code.

---

## Part 1 — Research: how engines model complex physical objects

### 1.1 The primitive shape vocabulary

Engines agree on a small catalog of *convex* primitives, and they publish the cost ordering. **[verified]**

| Shape | Unity/PhysX | Bullet | Jolt | Notes |
|---|---|---|---|---|
| Sphere | ✓ | `btSphereShape` | `SphereShape` | Cheapest everywhere |
| Capsule | ✓ | `btCapsuleShape` (Y-axis; X/Z variants) | `CapsuleShape`, `TaperedCapsuleShape` | Barely costlier than sphere |
| Box | ✓ | `btBoxShape` (half extents) | `BoxShape` | "Slightly more resource-intensive than Sphere or Capsule" (Unity) |
| Cylinder / cone | via mesh | `btCylinderShape`, `btConeShape` | `CylinderShape`, `TaperedCylinderShape` | Jolt: "cylinders are the least stable of all shapes, so use another shape if possible" |
| Multi-sphere | — | `btMultiSphereShape` | — | Convex hull of spheres |
| Convex hull | convex MeshCollider | `btConvexHullShape` | `ConvexHullShape` | PhysX: hard cap of **255 vertices and 255 faces** per cooked hull (64 for GPU-compatible hulls) |
| Triangle mesh | MeshCollider | `btBvhTriangleMeshShape` | `MeshShape` ("mostly for static geometry") | Static-only in practice — see below |
| Heightfield | TerrainCollider | `btHeightfieldTerrainShape` | `HeightFieldShape` | Static terrain |
| Infinite plane | ✓ | `btStaticPlaneShape` | `PlaneShape` | Static |

Jolt's `Architecture.md` lists its shapes explicitly "in order of computational complexity": Sphere, Box, Capsule, TaperedCapsule, Cylinder, TaperedCylinder, ConvexHull, Triangle, Plane, Static/MutableCompound, Mesh, HeightField, Empty. Unity's optimization manual ranks colliders "in order from most to least performant": sphere ("the simplest and most efficient"), capsule ("slightly more complex than a Sphere Collider, but still efficient"), then box. **[verified]**

**Why not just use the render mesh?** Concave triangle-mesh collision on *dynamic* bodies is effectively prohibited across engines: **[verified]**

- Unity: the non-convex MeshCollider is "the most resource-intensive collider type... Use only for static, non-moving geometry" and "cannot be attached to non-kinematic Rigidbodies" (runtime error since Unity 5).
- PhysX 5.5: "TriangleMesh, HeightField and Plane geometries are not supported for simulation shapes that are attached to dynamic actors, unless the dynamic actors are configured to be kinematic" — the only escape hatch is cooking a Signed Distance Field per mesh (a GPU pipeline feature).
- Bullet's manual: "Ideally, concave meshes should only be used for static artwork. Otherwise its convex hull should be used... multiple convex parts can be combined into a composite object called btCompoundShape"; the Doxygen for `btBvhTriangleMeshShape` says it "can only be used for fixed/non-moving objects."

So the industry answer to "my object is complicated" is exactly the intuition in this project's prompt: **approximate it with a handful of convex primitives, welded into a compound.** Even convex hulls are complexity-capped (PhysX's 255/255 limit) specifically to force decomposition into several simple pieces rather than one detailed shape. **[verified]**

### 1.2 Compound shapes: many colliders, one body

Every surveyed engine has a first-class "compound" mechanism, and they all share the same structure: **child shapes with local offset transforms, rigidly attached to a single rigid body.** **[verified]**

- **Unity**: "Compound colliders are formed by parenting multiple primitive colliders... to a single GameObject with a Rigidbody component." "Each collider is attached to a child GameObject, with the Rigidbody GameObject as its parent... A compound collider should only have one Rigidbody, which should be on the root GameObject." The physics system then "treats the whole collection as a single Rigidbody collider." Unity's guidance on when to use them cuts both ways: compounds are for "an accurate collider for a concave shape, or if you have a model that would be too computationally demanding to simulate with a Mesh collider" — but "very complex shapes which require a high number of colliders to approximate" can end up costlier than one mesh collider. **[verified]**
- **Bullet**: `btCompoundShape` "allows to store multiple other btCollisionShapes. This allows for moving concave collision objects." "Each child shape has its own local offset transform, relative to the btCompoundShape." It's also the prescribed tool when collision geometry isn't aligned with the center-of-mass frame: "you can use a btCompoundShape, and use the child transform to shift the child collision shape." **[verified]**
- **Jolt** exposes the static-vs-animated tradeoff as *two* shape types: `StaticCompoundShape` "is constructed once and cannot be changed afterwards. Child shapes are organized in a tree to speed up collision detection" (a 4-ary quantized-AABB BVH in the source); `MutableCompoundShape` "can be constructed/changed at runtime... Child shapes are organized in a list to make modification easy" — the source calls it "optimized for adding / removing and changing the rotation / translation of sub shapes but... less efficient in querying." That is the engine-level answer to *retractable landing gear*: collision children that move want a flat, mutable compound. **[verified]**
- **Defold** (Box2D/Bullet wrapper): several primitive shapes may share one collision component, but a complex shape must be the component's *only* shape — primitives and complex shapes can't mix on one body. **[verified]**

**Mass properties of a compound.** Engines compose compound mass/inertia the textbook way — sum child masses, rotate each child's inertia tensor into the compound frame, and add parallel-axis translation terms — and expose APIs for the COM bookkeeping: **[verified]**

- Bullet: "The world transform of a rigid body is in Bullet always equal to its center of mass, and its basis also defines its local frame for inertia." `btCompoundShape::calculatePrincipalAxisTransform(masses[], principal, inertia)` "computes the exact moment of inertia and the transform from the coordinate system defined by the principal axes... and the center of mass" — which the caller must then apply *inversely* to every child transform (Bullet's shipped example: `addChildShape(principal.inverse() * childTransform, child)`).
- Jolt: "By default, the mass and inertia of a body are automatically calculated from its shape and density" (compounds accumulate sub-shape masses and rotate/translate each child inertia — confirmed in `CompoundShape::GetMassProperties()` source), with three override modes on `BodyCreationSettings::mOverrideMassProperties` and wrapper shapes like `OffsetCenterOfMassShape` ("shift the center of mass of a vehicle down to improve its handling").

§2.6 gives the parallel-axis composition as Swift code — TFS doesn't need it until angular dynamics land, but it directly answers "how do engines combine the primitives."

**Animating collider children has a documented side effect.** Unity, verbatim: "Changes to collider position and scale can change the Rigidbody's center of mass, which can result in some unexpected behavior if continuous change is made over several frames at runtime. If this happens, you can use rigidbody.centerOfMass to manually set the center of mass" (after which COM is no longer auto-recomputed). For a flight sim this matters exactly once: gear swinging out shouldn't lurch the aircraft. Freeze/author the mass properties; move only the collision geometry. **[verified]**

**A property you get for free:** a compound never collides with itself — one body cannot contact itself, so gear-vs-fuselage self-collision simply cannot happen. Jointed multi-body assemblies have to *work* for this (see §1.5); compounds sidestep it entirely. **[verified]**

### 1.3 Joints and constraints: connecting separate bodies

A **joint** (constraint) connects two rigid bodies and removes degrees of freedom between them. Jolt's verified catalog is representative of a mature engine: **Fixed** (weld), **Distance**, **Point** (ball-socket — "removing 3 degrees of freedom"), **Hinge** (revolute), **Cone**, **Slider** ("also known as prismatic"), **SwingTwist**, **SixDOF**, **Path**, **Gear**, **RackAndPinion**, **Pulley**, and **Vehicle**. Constraints can have **motors** that drive toward a target: the applied force is `stiffness · (target_position − current_position) + damping · (target_velocity − current_velocity)`, with an alternative frequency/damping-ratio parameterization per Catto's GDC 2011 soft-constraints talk. **[verified]**

(A note on Bullet: it does ship the analogous joints — `btHingeConstraint`, `btSliderConstraint`, etc. — but the detailed Bullet joint-catalog claim as originally worded *failed* adversarial verification on two specifics, so this report leans on Jolt's verified catalog. See §1.6.)

**How constraints are solved.** The unifying idea (Catto, *Modeling and Solving Constraints*, GDC 2009 — verified against the PDF): "Constraints are used to simulate joints, contact, and collision. We need to solve the constraints to stack boxes and to keep ragdoll limbs attached. Constraint solvers do this by calculating impulse or forces, and applying them to the constrained bodies." Contacts and joints are the *same machinery* — a contact is just an inequality constraint with a friction cone. The production-standard solver is **Sequential Impulses (SI)**: "an iterative solver... SI applies impulses at each constraint to correct the velocity error. SI is fast and stable. Converges to a global solution." Per step: **[verified]**

1. Integrate applied forces (gravity, thrust) to get tentative velocities.
2. For `N` iterations: visit each constraint in sequence and apply a corrective impulse that cancels that constraint's velocity error (clamping accumulated impulses — e.g. contacts can only push).
3. Integrate positions from the corrected velocities ("This is the symplectic Euler integrator" — Catto).

SI with **warm starting** (re-applying last frame's converged impulses as the starting guess) is what Jolt implements, citing Catto's formulation directly; verifiers corroborated the same lineage in Bullet (`btSequentialImpulseConstraintSolver`) and PhysX (PGS ≡ sequential impulses, per Coumans). Position drift is handled by Baumgarte-style stabilization or dedicated position-correction iterations on top of the velocity solve (Jolt does the latter). **[verified]** XPBD (extended position-based dynamics) is the newer position-space alternative — the paper was collected during research but no claim about it survived verification, so it's referenced as background reading only.

The math that makes "a joint in code" concrete (standard formulation, from Catto's slides): a constraint is a scalar function of positions `C(x) = 0`; differentiate to get `Ċ = J·v`, where `J` is the **Jacobian**. The solver finds an impulse `λ` along `J` such that the post-impulse velocity satisfies `J·v = 0`:

```
λ = −(J·v + bias) / (J · M⁻¹ · Jᵀ)        // effective-mass form
v ← v + M⁻¹ · Jᵀ · λ                       // apply to both bodies
bias = (β/h) · C(x)                        // Baumgarte position feedback
```

For a **distance joint** between anchor points `pA`, `pB`: `C = |pB − pA| − L`, and `J·v` reduces to `dot(n, vB + ωB×rB − vA − ωA×rA)` with `n` the unit anchor-to-anchor direction and `r` the body-space anchor arms. A **hinge** is a point constraint (3 DOF removed) plus two angular rows keeping the hinge axes aligned; a **prismatic/slider** removes the two translations perpendicular to the slide axis plus all three relative rotations. Every term with `ω` and `r×n` in it needs angular state and inverse inertia tensors — which is why §2.6 sequences joints *after* angular dynamics for TFS.

**Joints vs. kinematically animated compound children — the decision rule that falls out of the research:**

| Use a compound child (animated kinematically) | Use separate bodies + joint |
|---|---|
| The part's *motion is prescribed* (gear extends because the animation says so) | The part's motion must *react to physics* (a wrecking ball swings because of gravity) |
| Landing gear, gear doors, control surfaces, turrets, canopies | Ragdolls, trailers, tow cables, articulated cranes, debris |
| One body: no self-collision, no solver cost, no drift | Needs solver iterations, collision filtering within the assembly, motors to drive poses |
| Caveat: pin the COM if children move continuously (Unity caveat above) | Caveat: joints can stretch under load (iterative solvers converge, not enforce) |

Flight-sim gear sits squarely in the left column: the strut's *pose* comes from the animation system; physics only needs to know *where the wheel is* and *how hard the ground pushes back*. That's the next section.

### 1.4 Wheels and landing gear: the raycast-suspension pattern

The strongest single finding of the research: **for wheels, the industry pattern is NOT separate wheel bodies connected by joints.** Bullet's manual, verbatim (typo preserved): "For arcade style vehicle simulations, it is recommended to use the simplified Bullet vehicle model as provided in btRaycastVehicle. Instead of simulation each wheel and chassis as separate rigid bodies, connected by constraints, it uses a simplified model... widely used in commercial driving games. The entire vehicle is represented as a single rigidbody, the chassis. The collision detection of the wheels is approximated by ray casts, and the tire friction is a basic anisotropic friction model." Jolt's `VehicleConstraint` is the same shape: it "adds virtual wheels or tracks to a body." **[verified]**

**Unity's WheelCollider** is the productized version of that pattern; its documented parameters give the suspension model and concrete default magnitudes: **[fetched]**

- "A special collider for grounded vehicles. It has built-in collision detection, wheel physics, and a slip-based tire friction model" — and it is positioned/configured independently of any visual wheel mesh (the tutorial's pattern is to read the simulated pose back via `GetWorldPose()` and *copy it onto* the render mesh, never the reverse).
- **Spring**: "the stiffness of the simulated spring (in newtons per meter). The default value is 35000 N/m, which simulates a normal vehicle."
- **Damper**: "the strength of the simulated damper or shock absorber (in newton-seconds per square meter [sic — N·s/m]). The default value is 4500."
- **Suspension Distance**: "the maximum distance along the vertical Y axis that the Wheel collider can move from its target position." Default 0.3 m.
- **Target Position**: normalized 0–1 along the suspension travel; "0 indicates the point of fully extended suspension... 1 indicates the point of fully compressed suspension." Default 0.5.
- Wheel **mass** (20 kg), **radius** (0.5 m), **wheel damping rate** (rotational spin-down), **force application point** (where along the strut the suspension force enters the rigidbody), and forward/sideways **friction curves** parameterized by (extremum slip/value, asymptote slip/value, stiffness) — "setting [stiffness] to zero completely disables all friction from the wheel."

The suspension force model this implies is the classic damped spring along the strut:

```
compression x  = restLength − currentLength          (≥ 0, clamped to travel)
compressionVel ẋ = d(compression)/dt                 (+ while compressing)
F_suspension   = k·x + c·ẋ                           (clamped ≥ 0 — a strut can push, never pull)
```

applied upward along the strut at the attach point. Spring rate `k` is sized from the static load (choose the fraction of travel you want consumed at rest: `k = W_axle / x_static`), and the damper from the damping ratio: `c = 2ζ√(k·m_axle)` with `ζ ≈ 0.3–0.7` for vehicles (aircraft oleos are heavily damped; start near 0.6). §2.4 does this arithmetic for the F-22's 30,000 kg.

**Retraction/articulation.** Microsoft Flight Simulator's SDK documents gear animation as a keyframed animation asset (gear positions driven by simvars), not as jointed physics; and the PBY-5A landing-gear rigging article **[fetched]** shows what the *animation side* of a faithful gear looks like: a hierarchy of parented parts, direction constraints for the pistons and wishbone suspension, lattice/skeletal deformers for tires and brake lines — "all working off of a single control parameter," with the author's core lesson being that "considerations for animation need to be made upstream from the very start when you begin modeling" (the linkage geometry dictates what the rig can do). Two takeaways for TFS:

1. The "single control parameter" *is* `AircraftAnimator.gearAnimationProgress` (0 = up, 1 = down). Physics should consume that scalar — it's the entire interface between the animation system and the gear force model.
2. The mechanical realism (scissor links, drag braces, pistons) lives in the *animation rig*, not in the physics. Physics needs only: where is the wheel contact point, and is the gear down.

Combined with §1.2's `MutableCompoundShape` finding and §1.3's decision rule, the retractable-gear recipe used in practice is:

- **Chassis/airframe**: one rigid body with a static compound of primitives.
- **Wheels**: no bodies; raycast suspension struts, *enabled only when gear is down* (weight-on-wheels = strut compressed).
- **Gear geometry during transit**: either ignored (contact during the retract cycle falls through to the airframe colliders — a belly scrape), or a mutable compound child lerped between stowed/deployed poses if mid-transit contact must be detected.

### 1.5 Collision filtering

Filtering is a staged pipeline, and the guidance is to reject pairs as early as possible. Jolt's verified stages: **BroadPhaseLayer → ObjectLayer → GroupFilter (simulation) / BodyFilter (queries) → shape filter → ContactListener**. "To avoid work, try to filter out collisions as early as possible." The `GroupFilter` stage "runs after bounding boxes have [been] found to be overlapping. Allows you [to] fine tune collision e.g. by discarding collisions between bodies connected by a constraint" — `GroupFilterTable` is the stock implementation, and `RagdollSettings` auto-creates one to disable parent/child joint collisions in ragdolls. **[verified]**

The practical shape of this in most engines is a pair of bitmasks per body (category + "collides with"), checked right after (or during) broad phase — Unity exposes it as the Layer Collision Matrix, Box2D as category/mask/group bits. TFS has *no* filtering today: every pair that overlaps on AABBs goes to narrow phase. Masks are cheap to add and immediately useful (weapons shouldn't collide with the aircraft that fired them; debris shouldn't collide with each other if perf demands).

Contact **events** (Jolt's `ContactListener` stage) are the other half: gameplay (crash detection, landing scoring) subscribes to contacts rather than polling. TFS's `collidedWith` set is close but carries no information about *where/what* — Part 2 adds a `Contact` payload and an `onContact` callback.

### 1.6 What did NOT survive verification (and gaps filled manually)

Adversarial verification killed two claims outright (0-3 votes), worth recording so future work doesn't re-import them as facts:

1. **A "PhysX has seven geometry types in two classes" taxonomy** — wrong as stated.
2. **The detailed Bullet joint catalog** ("btPoint2PointConstraint/btHingeConstraint/btSliderConstraint/btConeTwistConstraint/btGeneric6DofConstraint all derive from btTypedConstraint, solved by btSequentialImpulseConstraintSolver") — Bullet *does* ship these joints, but the compound claim failed on two specifics: `btRaycastVehicle` does **not** derive from `btTypedConstraint` (it's a `btActionInterface` — confirmed in bullet3 master source), and other wording details didn't hold. Re-verify Bullet joint specifics against current docs before depending on them.

Coverage gaps in the verified set, and how this doc handles them: nothing survived on **Unreal/Chaos, Havok, Box2D, or Rapier** specifics (they're simply not covered here); nothing on **XPBD/Baumgarte specifics** (presented above as standard background with the Catto/XPBD sources in References, not as verified claims); nothing on **sensor/trigger shapes** (omitted); and the workflow never fetched the **WheelCollider math** or the **gear-rigging blog** — both were fetched directly afterward and are marked **[fetched]** in §1.4. Time-sensitivity: Bullet evidence cites the 2.80 manual (2012) — verifiers confirmed the cited APIs still exist in bullet3 master, but newer Bullet features (`btMultiBody`/Featherstone articulations) are not covered. Unity docs verified at 2022.3 and 6000.x, PhysX at 5.5.1/5.6.0, Jolt at master (5.x), all current as of 2026-07-14.

---

## Part 2 — Applying this to ToyFlightSimulator

### 2.1 Where the engine is today

Grounding the design in the actual code (all paths under `ToyFlightSimulator Shared/`):

- **Shapes**: `enum CollisionShape { case Sphere, Plane }` (`Physics/World/PhysicsEntity.swift:11`). `SphereRigidBody` carries `collisionRadius`; `PlaneRigidBody` carries a normalized `collisionNormal` — but plane penetration is hardcoded to a plane through the origin: `getPenetrationDepth(ball:plane:)` returns `ball.collisionRadius - ball.getPosition().y` (`PhysicsWorld.swift:162`).
- **Narrow phase**: a double-dispatch `switch` over `(collisionShape, collisionShape)` with force-casts, duplicated across `PhysicsWorld.collided(...)` and `PhysicsWorld.getCollisionData(...)`. Adding shapes to this switch is quadratic case growth — with 5 shapes that's 25 cases × 2 functions.
- **Dynamics are linear-only.** `RigidBody` has mass, velocity, acceleration, force — **no orientation state, no angular velocity, no inertia tensor, no torque**. Aircraft attitude is kinematic (`AttitudeDynamics` first-order lag in `Aircraft.swift`), and `HeckerCollisionResponse` computes `j = −(1+e)·(v_rel·n) / (1/mA + 1/mB)` — the point-mass impulse, applied at the center, no contact point anywhere.
- **The player aircraft is a 2 m sphere**: `applyAircraftSwap` builds `SphereRigidBody(gameObject: playerAircraft); acRigidBody.collisionRadius = 2.0` (`Scenes/FlightboxWithPhysics.swift:207-209`) for a jet that renders ~19 m long. Gear state exists only in animation: `Aircraft.isGearDown` → `animator?.isGearDown`, progress via `gearAnimationProgress` (0 = up, 1 = down).
- **Broad phase**: single-axis sweep-and-prune over `getAABB()` (`BroadPhase/BroadPhaseCollisionDetector.swift`), dynamic-vs-dynamic + dynamic-vs-static, no filtering of any kind. `AABB` already has `merged(with:)` — handy for compound bounds.
- **Response quirks that will interact with gear physics**: the "rest hack" in `HeckerCollisionResponse.applyCollisionResponse` zeroes velocity and sets `shouldApplyGravity = false` when relative speed < 0.55 m/s against a static body. A suspended aircraft sitting on its wheels would trip this constantly (and then float, gravityless). Phase B must opt the aircraft out.
- **Update order**: `Node.update()` runs `doUpdate()` *before* traversing children, so `FlightboxWithPhysics.doUpdate` steps `physicsWorld` before `Aircraft.doUpdate` accumulates this frame's forces — i.e. forces are consumed on the *next* step. Suspension forces added in `Aircraft.doUpdate` inherit exactly the flight model's existing (one-frame-latency) semantics. Position access: `RigidBody.getPosition()` is the node's *local* position, which equals world only because physics bodies are direct children of the scene root — the compound code below follows the same convention deliberately.

### 2.2 Design principles (what the research says to build)

1. **One body per vehicle; compound colliders; no jointed parts.** Matches finding §1.2/§1.3 and keeps TFS's linear-only solver viable — a compound needs no new solver machinery at all, because all its shapes share one velocity.
2. **Landing gear = raycast suspension struts, not wheel bodies, not even wheel colliders.** Matches §1.4 (`btRaycastVehicle`, Jolt "virtual wheels", WheelCollider). Gear-down state and strut poses come from the existing animation layer through one scalar, `gearAnimationProgress`.
3. **Control surfaces stay out of collision entirely.** They're animation + aerodynamics (`F22SimpleFlightModel` is where deflection *forces* would enter, as moments once angular dynamics exist). No engine surveyed gives control surfaces colliders.
4. **Crash-vs-landing is a *filtering + events* problem, not a geometry problem.** Tag each collider (`airframe` vs. future `landingGear`), emit `Contact`s with the tag, and let `Aircraft` classify. Gear-up belly contact → airframe collider → crash. Gear-down → suspension catches the aircraft before any airframe collider reaches the ground → no contact at all.
5. **Static structures are static compound bodies** — buildings/towers/hangars are boxes (the cheap, adequate primitive for architecture), trees a capsule trunk; the existing static path in the broad phase already handles them.
6. **Joints and angular dynamics are a separate, later investment** (§2.6): real inertia, torque, contact points with lever arms, then sequential impulses — *then* hinges. Nothing in phases A–C blocks on it, and gear never needs it.

The phases below are ordered so each ships something visible: **A** — the aircraft stops being a sphere (collision shape hugs the airframe); **B** — the aircraft rests and lands on its wheels at correct ride height; **C** — buildings and scenery collide; **D** — (future) torque-true touchdowns and optional joints.

### 2.3 Phase A — shape vocabulary, compound bodies, contact-based narrow phase

Design-level code, written to compile against this codebase's idioms (`float3`, zero-safe `.normalize()`, 4-space indent) but **not yet compiled** — treat as the implementation blueprint.

#### New file: `Physics/Collision/ColliderShape.swift`

```swift
import simd

/// Convex collision primitives, in the cost order every surveyed engine
/// documents (sphere < capsule < box). Dimensions are authored in the owning
/// model's local space and scaled by the GameObject's uniform scale when
/// world-space colliders are computed.
enum ColliderShape {
    /// Ball of the given radius.
    case sphere(radius: Float)
    /// Segment along local Y from -halfHeight to +halfHeight, inflated by
    /// radius (total height = 2·(halfHeight + radius)). Orient with the
    /// collider's localRotation (e.g. Y→Z for a fuselage along +Z).
    case capsule(radius: Float, halfHeight: Float)
    /// Oriented box with the given half extents.
    case box(halfExtents: float3)

    func scaled(by s: Float) -> ColliderShape {
        switch self {
            case .sphere(let r):
                return .sphere(radius: r * s)
            case .capsule(let r, let hh):
                return .capsule(radius: r * s, halfHeight: hh * s)
            case .box(let he):
                return .box(halfExtents: he * s)
        }
    }
}

/// Which functional part of the object a collider represents, so contact
/// consumers (crash detection, landing logic) can tell a wheel strike from
/// a belly strike without geometry queries.
enum ColliderGroup {
    case airframe      // fuselage/wings/tail — contact here means structural impact
    case landingGear   // reserved for future wheel colliders (suspension covers ground contact)
    case structure     // buildings, towers, scenery
}

/// One primitive rigidly attached to a body at a local offset — the per-child
/// entry of a compound (Bullet btCompoundShape child, Unity child collider,
/// Jolt compound sub-shape).
struct LocalCollider {
    var name: String
    var shape: ColliderShape
    var localPosition: float3
    var localRotation: simd_quatf
    var group: ColliderGroup
    /// Cheap runtime on/off (Jolt MutableCompoundShape's role). Disabled
    /// colliders generate no contacts and don't contribute to the AABB.
    var isEnabled: Bool

    init(name: String,
         shape: ColliderShape,
         localPosition: float3 = .zero,
         localRotation: simd_quatf = simd_quatf(real: 1, imag: .zero),
         group: ColliderGroup = .airframe,
         isEnabled: Bool = true) {
        self.name = name
        self.shape = shape
        self.localPosition = localPosition
        self.localRotation = localRotation
        self.group = group
        self.isEnabled = isEnabled
    }
}

/// A LocalCollider transformed into world space for one narrow-phase query.
struct WorldCollider {
    let shape: ColliderShape        // dimensions already scaled
    let position: float3            // world center
    let rotation: float3x3          // world orientation
    let sourceIndex: Int            // index into the owning body's colliders
    let name: String
    let group: ColliderGroup

    var aabb: AABB {
        switch shape {
            case .sphere(let r):
                return AABB(center: position, radius: r)
            case .capsule(let r, let hh):
                let axisExtent = abs(rotation.columns.1 * hh)
                return AABB(center: position,
                            halfExtents: axisExtent + float3(repeating: r))
            case .box(let he):
                // World-axis extents of an oriented box: |R| · he
                let ex = abs(rotation.columns.0) * he.x
                     + abs(rotation.columns.1) * he.y
                     + abs(rotation.columns.2) * he.z
                return AABB(center: position, halfExtents: ex)
        }
    }
}
```

#### New file: `Physics/World/CompoundRigidBody.swift`

```swift
/// A rigid body whose collision geometry is a set of primitive colliders at
/// local offsets — the engine-standard way to give a complex object (aircraft,
/// building) faithful collision without a mesh shape (§1.2 of the research
/// doc). All children share the body's single linear state; there is no
/// self-collision within a compound by construction.
public final class CompoundRigidBody: RigidBody {
    var colliders: [LocalCollider] {
        didSet { worldCollidersFrame = -1 }   // invalidate cache
    }

    /// Per-step cache: worldColliders() is called by getAABB() (broad phase)
    /// and again per candidate pair (narrow phase); rebuild only when the
    /// frame advances.
    private var worldScratch: [WorldCollider] = []
    private var worldCollidersFrame: Int = -1

    init(gameObject: GameObject, colliders: [LocalCollider]) {
        self.colliders = colliders
        super.init(gameObject: gameObject)
        self.collisionShape = .Compound
    }

    /// World-space poses of the enabled colliders. Follows RigidBody's
    /// existing space convention: node-local position/rotation (== world for
    /// the direct scene-root children physics uses). Uniform scale assumed —
    /// radii scale by scale.x, matching how the aircraft are scaled today.
    func worldColliders(frame: Int) -> [WorldCollider] {
        if frame == worldCollidersFrame { return worldScratch }
        worldCollidersFrame = frame
        worldScratch.removeAll(keepingCapacity: true)
        guard let node = gameObject else { return worldScratch }

        let bodyPosition = node.getPosition()
        let bodyRotation = node.getRotationMatrix().upperLeft3x3
        let scale = node.getScale().x

        for (index, collider) in colliders.enumerated() where collider.isEnabled {
            let worldRotation = bodyRotation * float3x3(collider.localRotation)
            let worldPosition = bodyPosition + bodyRotation * (collider.localPosition * scale)
            worldScratch.append(WorldCollider(shape: collider.shape.scaled(by: scale),
                                              position: worldPosition,
                                              rotation: worldRotation,
                                              sourceIndex: index,
                                              name: collider.name,
                                              group: collider.group))
        }
        return worldScratch
    }

    override func getAABB() -> AABB {
        let worlds = worldColliders(frame: PhysicsWorld.currentStepIndex)
        guard var merged = worlds.first?.aabb else {
            return AABB(center: getPosition(), radius: 0.5)
        }
        for collider in worlds.dropFirst() {
            merged = merged.merged(with: collider.aabb)
        }
        return merged
    }
}
```

(`PhysicsWorld.currentStepIndex` is a monotonically increasing `Int` bumped at the top of `PhysicsWorld.update` — three lines, shown in the diff below. If the cache feels premature, drop it and rebuild unconditionally; at ≤10 colliders per body it's a handful of matrix multiplies either way. Jolt's precedent for "flat list, just iterate" is `MutableCompoundShape`.)

#### New file: `Physics/Collision/Contact.swift`

```swift
/// One collision contact produced by the narrow phase.
/// `normal` is unit length and points from B toward A — the direction that
/// separates A — matching HeckerCollisionResponse's existing convention
/// (it pushes entityA along +normal).
struct Contact {
    let normal: float3
    let depth: Float
    /// Representative world-space contact point. Unused by the current
    /// linear-only response; becomes the lever arm when angular dynamics land.
    let point: float3
    /// Sub-collider names/groups for compound bodies (nil for simple bodies).
    let colliderNameA: String?
    let colliderGroupA: ColliderGroup?
    let colliderNameB: String?
    let colliderGroupB: ColliderGroup?

    /// The same contact expressed with A and B swapped.
    var flipped: Contact {
        Contact(normal: -normal, depth: depth, point: point,
                colliderNameA: colliderNameB, colliderGroupA: colliderGroupB,
                colliderNameB: colliderNameA, colliderGroupB: colliderGroupA)
    }
}
```

#### New file: `Physics/Collision/NarrowPhase.swift`

One dispatch entry point replaces the shape-pair switches in `PhysicsWorld`. Compounds expand to their children; the deepest contact wins. (Deepest-only is *correct* for the current linear-only response: with no torque, one impulse along the shared normal resolves the whole body, and on flat ground every gear/airframe contact shares that normal. When angular dynamics land, return all contacts instead — noted in §2.6.)

```swift
import simd

enum NarrowPhase {
    // MARK: - Body-level dispatch

    /// Single entry point: nil ⇒ no intersection. Replaces the
    /// (CollisionShape, CollisionShape) switches in PhysicsWorld.
    static func generateContact(_ a: RigidBody, _ b: RigidBody, frame: Int) -> Contact? {
        // Planes are always presented to the shape tests as the B side.
        if a is PlaneRigidBody {
            guard !(b is PlaneRigidBody) else { return nil }   // plane/plane: nothing to do
            return generateContact(b, a, frame: frame)?.flipped
        }
        if let plane = b as? PlaneRigidBody {
            let planePoint = plane.getPosition()
            let planeNormal = plane.collisionNormal
            var deepest: Contact? = nil
            for collider in worldColliders(of: a, frame: frame) {
                if let c = shapeVsPlane(collider, planePoint: planePoint, planeNormal: planeNormal),
                   c.depth > (deepest?.depth ?? 0) {
                    deepest = c
                }
            }
            return deepest
        }
        // Volume vs volume: children × children, keep the deepest.
        var deepest: Contact? = nil
        for ca in worldColliders(of: a, frame: frame) {
            for cb in worldColliders(of: b, frame: frame) {
                if let c = shapeVsShape(ca, cb), c.depth > (deepest?.depth ?? 0) {
                    deepest = c
                }
            }
        }
        return deepest
    }

    /// Uniform collider view over the body zoo: compounds expose their
    /// children; a legacy SphereRigidBody is a one-sphere compound.
    private static func worldColliders(of body: RigidBody, frame: Int) -> [WorldCollider] {
        if let compound = body as? CompoundRigidBody {
            return compound.worldColliders(frame: frame)
        }
        if let sphere = body as? SphereRigidBody {
            return [WorldCollider(shape: .sphere(radius: sphere.collisionRadius),
                                  position: sphere.getPosition(),
                                  rotation: matrix_identity_float3x3,
                                  sourceIndex: 0, name: "sphere", group: .airframe)]
        }
        return []
    }

    // MARK: - Shape vs plane (the tests the flight sim needs first)

    static func shapeVsPlane(_ collider: WorldCollider,
                             planePoint: float3,
                             planeNormal n: float3) -> Contact? {
        switch collider.shape {
            case .sphere(let r):
                let signedDistance = dot(collider.position - planePoint, n)
                let depth = r - signedDistance
                guard depth > 0 else { return nil }
                return contact(normal: n, depth: depth,
                               point: collider.position - n * signedDistance,
                               a: collider)

            case .capsule(let r, let hh):
                let axis = collider.rotation.columns.1
                let p0 = collider.position - axis * hh
                let p1 = collider.position + axis * hh
                let d0 = dot(p0 - planePoint, n)
                let d1 = dot(p1 - planePoint, n)
                let (endPoint, signedDistance) = d0 < d1 ? (p0, d0) : (p1, d1)
                let depth = r - signedDistance
                guard depth > 0 else { return nil }
                return contact(normal: n, depth: depth,
                               point: endPoint - n * signedDistance, a: collider)

            case .box(let he):
                let c0 = collider.rotation.columns.0
                let c1 = collider.rotation.columns.1
                let c2 = collider.rotation.columns.2
                // Projection radius of the OBB onto the plane normal.
                let projectionRadius = he.x * abs(dot(c0, n))
                                     + he.y * abs(dot(c1, n))
                                     + he.z * abs(dot(c2, n))
                let signedDistance = dot(collider.position - planePoint, n)
                let depth = projectionRadius - signedDistance
                guard depth > 0 else { return nil }
                // Deepest corner: step against the normal on each box axis.
                func axisSign(_ x: Float) -> Float { x >= 0 ? 1 : -1 }
                let corner = collider.position
                    - c0 * (he.x * axisSign(dot(c0, n)))
                    - c1 * (he.y * axisSign(dot(c1, n)))
                    - c2 * (he.z * axisSign(dot(c2, n)))
                return contact(normal: n, depth: depth, point: corner, a: collider)
        }
    }

    // MARK: - Shape vs shape

    static func shapeVsShape(_ a: WorldCollider, _ b: WorldCollider) -> Contact? {
        switch (a.shape, b.shape) {
            case (.sphere(let ra), .sphere(let rb)):
                return sphereVsSphere(centerA: a.position, radiusA: ra,
                                      centerB: b.position, radiusB: rb, a: a, b: b)

            case (.sphere(let r), .capsule):
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

            case (.sphere(let r), .box(let he)):
                return sphereVsBox(center: a.position, radius: r,
                                   box: b, halfExtents: he, a: a, b: b)
            case (.box, .sphere):
                return shapeVsShape(b, a)?.flipped

            case (.capsule, .box(let he)):
                // Approximation: nearest point of the capsule segment to the
                // box center, then sphere-vs-box. Adequate for crash detection;
                // exact segment-OBB (or GJK) is the upgrade path.
                let (p, r) = capsuleAsSphere(a, towards: b.position)
                return sphereVsBox(center: p, radius: r, box: b, halfExtents: he, a: a, b: b)
            case (.box, .capsule):
                return shapeVsShape(b, a)?.flipped

            case (.box, .box):
                // Not needed while structures are static and vehicles are
                // sphere/capsule-dominant. Upgrade path: SAT (15 axes) or GJK/EPA.
                return nil
        }
    }

    // MARK: - Primitive helpers (pure — unit-testable without Metal)

    private static func sphereVsSphere(centerA: float3, radiusA: Float,
                                       centerB: float3, radiusB: Float,
                                       a: WorldCollider, b: WorldCollider) -> Contact? {
        let delta = centerA - centerB
        let distanceSquared = simd_length_squared(delta)
        let radiusSum = radiusA + radiusB
        guard distanceSquared < radiusSum * radiusSum else { return nil }
        let distance = sqrt(distanceSquared)
        let normal: float3 = distance > 1e-6 ? delta / distance : [0, 1, 0]
        return contact(normal: normal, depth: radiusSum - distance,
                       point: centerB + normal * radiusB, a: a, b: b)
    }

    private static func sphereVsBox(center: float3, radius: Float,
                                    box: WorldCollider, halfExtents he: float3,
                                    a: WorldCollider, b: WorldCollider) -> Contact? {
        // Sphere center in box-local space (R is orthonormal: inverse = transpose).
        let local = box.rotation.transpose * (center - box.position)
        let clamped = simd_clamp(local, -he, he)

        if local.x == clamped.x && local.y == clamped.y && local.z == clamped.z {
            // Center inside the box: push out along the axis of least penetration.
            let distances = he - abs(local)
            var axis = 0
            if distances.y < distances.x { axis = 1 }
            if distances.z < distances[axis] { axis = 2 }
            var localNormal = float3.zero
            localNormal[axis] = local[axis] >= 0 ? 1 : -1
            let worldNormal = box.rotation * localNormal
            return contact(normal: worldNormal,
                           depth: distances[axis] + radius,
                           point: center, a: a, b: b)
        }

        let closest = box.position + box.rotation * clamped
        let delta = center - closest
        let distance = simd_length(delta)
        guard distance < radius else { return nil }
        let normal = distance > 1e-6 ? delta / distance : [0, 1, 0]
        return contact(normal: normal, depth: radius - distance, point: closest, a: a, b: b)
    }

    private static func capsuleSegment(_ c: WorldCollider) -> (float3, float3, Float) {
        guard case .capsule(let r, let hh) = c.shape else { fatalError("not a capsule") }
        let axis = c.rotation.columns.1
        return (c.position - axis * hh, c.position + axis * hh, r)
    }

    private static func capsuleAsSphere(_ c: WorldCollider, towards target: float3) -> (float3, Float) {
        let (p0, p1, r) = capsuleSegment(c)
        return (closestPointOnSegment(p0, p1, to: target), r)
    }

    static func closestPointOnSegment(_ p0: float3, _ p1: float3, to point: float3) -> float3 {
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

    private static func contact(normal: float3, depth: Float, point: float3,
                                a: WorldCollider, b: WorldCollider? = nil) -> Contact {
        Contact(normal: normal, depth: depth, point: point,
                colliderNameA: a.name, colliderGroupA: a.group,
                colliderNameB: b?.name, colliderGroupB: b?.group)
    }
}
```

#### Diffs to existing files

`Physics/World/PhysicsEntity.swift` — one new shape case, filtering masks, and the contact callback:

```diff
 enum CollisionShape {
     case Sphere
     case Plane
+    case Compound
 }

 protocol PhysicsEntity: AnyObject {
     var collisionShape: CollisionShape { get set }
     ...
     var isStatic: Bool { get set }
     var shouldApplyGravity: Bool { get set }  // Hack...
+
+    /// Collision filtering (§1.5): a pair is tested only if each body's
+    /// category intersects the other's collidesWith mask. Defaults keep
+    /// current behavior (everything collides with everything).
+    var categoryMask: UInt32 { get set }
+    var collidesWithMask: UInt32 { get set }
```

`Physics/World/RigidBody.swift` — the stored fields plus events and the rest-hack opt-out:

```diff
     var isStatic: Bool
     var shouldApplyGravity: Bool
+    var categoryMask: UInt32 = CollisionCategory.default
+    var collidesWithMask: UInt32 = CollisionCategory.all
+    /// When false, the low-relative-speed "rest" branch in
+    /// HeckerCollisionResponse leaves this body alone (it would otherwise
+    /// zero velocity and disable gravity — fatal for a body held up by
+    /// suspension forces, which needs gravity every frame).
+    var freezeOnRestingContact: Bool = true
+    /// Invoked (on the UpdateThread, during collision resolution) once per
+    /// new contact this step. The Contact is expressed with self as A.
+    var onContact: ((Contact, RigidBody) -> Void)?
```

```swift
/// Bitmask vocabulary for collision filtering. Extend as needed.
enum CollisionCategory {
    static let `default`: UInt32 = 1 << 0
    static let world: UInt32     = 1 << 1   // ground plane, terrain
    static let vehicle: UInt32   = 1 << 2   // player + AI aircraft
    static let structure: UInt32 = 1 << 3   // buildings, towers
    static let debris: UInt32    = 1 << 4   // random physics objects
    static let all: UInt32       = .max
}
```

`Physics/BroadPhase/BroadPhaseCollisionDetector.swift` — filter pairs at emission (both loops):

```diff
                 // Check full AABB overlap (Y and Z axes)
-                if aabbA.overlaps(aabbB) {
+                if aabbA.overlaps(aabbB) && Self.shouldCollide(dynamicEntities[i], dynamicEntities[j]) {
                     pairsScratch.append((dynamicEntities[i], dynamicEntities[j]))
                 }
```

```swift
    /// §1.5 filtering: symmetric category/mask test, plus never pair two
    /// bodies attached to the same GameObject.
    static func shouldCollide(_ a: RigidBody, _ b: RigidBody) -> Bool {
        guard (a.categoryMask & b.collidesWithMask) != 0,
              (b.categoryMask & a.collidesWithMask) != 0 else { return false }
        if let ga = a.gameObject, let gb = b.gameObject, ga === gb { return false }
        return true
    }
```

`Physics/CollisionResponse/HeckerCollisionResponse.swift` — narrow phase runs **once**, produces a `Contact`, response consumes it, events fire. (The old flow ran `PhysicsWorld.collided` and then re-derived geometry in `getCollisionData` — two narrow phases per pair.)

```diff
     static func resolveCollisions(deltaTime: Float, collisionPairs: [(RigidBody, RigidBody)]) {
         for (entityA, entityB) in collisionPairs {
             let alreadyCollided = entityA.collidedWith.contains(ObjectIdentifier(entityB))
+            guard !alreadyCollided,
+                  let contact = NarrowPhase.generateContact(entityA, entityB,
+                                                            frame: PhysicsWorld.currentStepIndex)
+            else { continue }

-            // Perform narrow-phase collision detection
-            if !alreadyCollided && PhysicsWorld.collided(entityA: entityA, entityB: entityB) {
-                entityA.collidedWith.insert(ObjectIdentifier(entityB))
-                entityB.collidedWith.insert(ObjectIdentifier(entityA))
-
-                applyCollisionResponse(entityA, entityB)
-            }
+            entityA.collidedWith.insert(ObjectIdentifier(entityB))
+            entityB.collidedWith.insert(ObjectIdentifier(entityA))
+
+            applyCollisionResponse(entityA, entityB, contact: contact)
+            entityA.onContact?(contact, entityB)
+            entityB.onContact?(contact.flipped, entityA)
         }
     }

-    private static func applyCollisionResponse(_ entityA: RigidBody, _ entityB: RigidBody) {
+    private static func applyCollisionResponse(_ entityA: RigidBody, _ entityB: RigidBody,
+                                               contact: Contact) {
         if simd_length_squared(entityA.velocity - entityB.velocity) < restSpeedThresholdSquared {
-            if entityB.isStatic {
+            if entityB.isStatic && entityA.freezeOnRestingContact {
                 entityA.velocity = .zero
                 ...
             }
-            if entityA.isStatic {
+            if entityA.isStatic && entityB.freezeOnRestingContact {
                 ...
             }
             return
         }

-        let collisionData = PhysicsWorld.getCollisionData(entityA, entityB)
-        let penetrationDepth = collisionData.penetrationDepth
-        let collisionNormal = collisionData.collisionVector
+        let penetrationDepth = contact.depth
+        let collisionNormal = contact.normal
         ...unchanged impulse math...
```

`EulerSolver.resolvePair` gets the identical treatment (contact in, `getCollisionData` out). `PhysicsWorld.collided`/`getCollisionData` shrink to thin wrappers over `NarrowPhase.generateContact` for any remaining callers, and the sphere-plane y=0 hardcode dies with them — the plane's actual `getPosition()` and `collisionNormal` flow through `shapeVsPlane`. Add the step counter at the top of `PhysicsWorld.update`:

```diff
 final class PhysicsWorld {
     public static let gravity: float3 = [0, -9.81, 0]
+    /// Monotonic step counter — cache key for per-step world-collider poses.
+    public private(set) static var currentStepIndex: Int = 0

     public func update(deltaTime: Float) {
+        Self.currentStepIndex &+= 1
         for entity in entities {
```

#### The F-22's compound (example spec)

Numbers are model-space placeholders for the CGTrader F-22 (rendered at `setScale(3.0)`) — **tune with the debug overlay** (§2.7). Pattern mirrors `AircraftThumbnailSpec`: one spec per `AircraftType`, kept next to the aircraft.

```swift
/// Collision + gear spec for F22_CGTrader. Authored in model space; the
/// body's uniform scale (3.0 in FlightboxWithPhysics) is applied at runtime.
enum F22ColliderSpec {
    static let colliders: [LocalCollider] = [
        LocalCollider(name: "fuselage",
                      shape: .capsule(radius: 0.45, halfHeight: 2.4),
                      localPosition: [0, 0.10, 0.20],
                      // Capsule axis is local Y; rotate Y→Z so it runs nose–tail.
                      localRotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]),
                      group: .airframe),
        LocalCollider(name: "wings",
                      shape: .box(halfExtents: [2.2, 0.06, 0.9]),
                      localPosition: [0, 0.05, -0.4],
                      group: .airframe),
        LocalCollider(name: "empennage",
                      shape: .box(halfExtents: [1.0, 0.45, 0.5]),
                      localPosition: [0, 0.35, -2.2],
                      group: .airframe),
    ]
}
```

Three primitives ≈ the whole airframe. That's the density the research recommends: Unity's both-ways guidance (§1.2) says a *few* primitives beat a mesh collider, and PhysX's 255-vertex hull cap exists to keep counts like this. Wingtip strikes, belly scrapes, and tail strikes all become detectable — none were with the 2 m sphere.

### 2.4 Phase B — landing gear as raycast suspension

Per §1.4: **no wheel bodies, no wheel colliders.** Struts are raycast spring-dampers on the aircraft body, active only when the gear is down, fed by the one scalar the animation system already publishes.

#### New file: `Physics/Vehicle/LandingGearSuspension.swift`

```swift
import simd

/// One oleo strut, WheelCollider-style (§1.4): geometry in model units
/// (scaled by the aircraft's uniform scale at runtime), forces in world units.
struct SuspensionStrut {
    var name: String
    /// Strut attach point on the airframe, model space.
    var attachLocal: float3
    /// Attach point → wheel center at full extension, model units.
    var restLength: Float
    /// Max upward wheel travel from full extension, model units.
    var maxTravel: Float
    var wheelRadius: Float
    /// N/m (world). Size from static load: k = W_strut / x_static.
    var springRate: Float
    /// N·s/m (world). c = 2ζ√(k·m_strut); aircraft oleos ζ ≈ 0.5–0.7.
    var dampingRate: Float
}

/// Raycast landing-gear model: the industry-standard alternative to wheel
/// rigid bodies (Bullet btRaycastVehicle, Jolt VehicleConstraint "virtual
/// wheels", Unity WheelCollider). Casts each strut ray against the ground
/// and accumulates spring-damper forces into the aircraft's RigidBody.
final class LandingGearSuspension {
    var struts: [SuspensionStrut]
    /// Phase B ground model: the analytic plane the scene's ground uses.
    /// (Upgrade path: raycast the PhysicsWorld when terrain arrives.)
    var groundHeight: Float = 0

    /// Last-step compression per strut, world meters. > 0 ⇒ that wheel is
    /// carrying load — the weight-on-wheels signal.
    private(set) var compressions: [Float]

    init(struts: [SuspensionStrut]) {
        self.struts = struts
        self.compressions = Array(repeating: 0, count: struts.count)
    }

    var isWeightOnWheels: Bool { compressions.contains { $0 > 1e-3 } }

    /// Accumulate suspension forces. Call from Aircraft.doUpdate (UpdateThread),
    /// alongside the flight-model force accumulation.
    /// gearExtension: AircraftAnimator.gearAnimationProgress (0 up … 1 down).
    func update(rigidBody: RigidBody, node: Node, gearExtension: Float) {
        guard gearExtension > 0.99 else {
            for i in compressions.indices { compressions[i] = 0 }
            return
        }

        let bodyPosition = node.getPosition()
        let bodyRotation = node.getRotationMatrix().upperLeft3x3
        let scale = node.getScale().x
        // Struts point down the aircraft's -Y (they retract with the airframe's
        // attitude — that's what makes nose-high touchdowns settle correctly
        // once angular dynamics land; for now it tilts the ray with the body).
        let strutDirection = -(bodyRotation * float3(0, 1, 0)).normalize()

        for (i, strut) in struts.enumerated() {
            compressions[i] = 0
            // Ray pointing away from the ground can't contact it.
            guard strutDirection.y < -1e-4 else { continue }

            let attachWorld = bodyPosition + bodyRotation * (strut.attachLocal * scale)
            let rayLength = (strut.restLength + strut.wheelRadius) * scale
            // Ray vs plane y = groundHeight.
            let hitDistance = (groundHeight - attachWorld.y) / strutDirection.y
            guard hitDistance >= 0, hitDistance < rayLength else { continue }

            let maxCompression = strut.maxTravel * scale
            let compression = min(rayLength - hitDistance, maxCompression)
            // + while the body moves toward the ground (compressing).
            let compressionVelocity = dot(rigidBody.velocity, strutDirection)

            let force = Self.suspensionForce(compression: compression,
                                             compressionVelocity: compressionVelocity,
                                             springRate: strut.springRate,
                                             dampingRate: strut.dampingRate)
            rigidBody.force += -strutDirection * force
            compressions[i] = compression
        }
    }

    /// F = k·x + c·ẋ, clamped ≥ 0 (a strut pushes, never pulls). Pure —
    /// unit-testable without Metal.
    static func suspensionForce(compression: Float,
                                compressionVelocity: Float,
                                springRate: Float,
                                dampingRate: Float) -> Float {
        max(0, springRate * compression + dampingRate * compressionVelocity)
    }
}
```

#### Sizing the springs (worked example, F-22, 30,000 kg)

Weight `W = 30,000 · 9.81 ≈ 294 kN`. Typical tricycle-gear load split: ~10% nose, ~45% each main. Choose world-space travel budget: with `maxTravel = 0.15` model units × scale 3 = **0.45 m**, target static compression ≈ 0.12 m (~27% of travel — the WheelCollider `targetPosition = 0.5` idea: sit mid-travel-ish at rest):

- **Mains**: `k = 0.45 · 294,300 / 0.12 ≈ 1.10 MN/m`. Damping at ζ = 0.6 with `m_eff = 13,500 kg`: `c = 2 · 0.6 · √(1.1e6 · 13,500) ≈ 146,000 N·s/m`.
- **Nose**: `k = 0.10 · 294,300 / 0.11 ≈ 268 kN/m`; `c = 2 · 0.6 · √(2.68e5 · 3,000) ≈ 34,000 N·s/m`.

```swift
extension F22ColliderSpec {
    static let gearStruts: [SuspensionStrut] = [
        SuspensionStrut(name: "nose",
                        attachLocal: [0, -0.15, 1.6],
                        restLength: 0.55, maxTravel: 0.15, wheelRadius: 0.12,
                        springRate: 268_000, dampingRate: 34_000),
        SuspensionStrut(name: "mainLeft",
                        attachLocal: [-0.55, -0.15, -0.35],
                        restLength: 0.55, maxTravel: 0.15, wheelRadius: 0.16,
                        springRate: 1_100_000, dampingRate: 146_000),
        SuspensionStrut(name: "mainRight",
                        attachLocal: [0.55, -0.15, -0.35],
                        restLength: 0.55, maxTravel: 0.15, wheelRadius: 0.16,
                        springRate: 1_100_000, dampingRate: 146_000),
    ]
}
```

Sanity check at rest: total spring force at static compression = `2·(1.1e6·0.12) + 2.68e5·0.11 ≈ 293.5 kN ≈ W`. The aircraft settles with wheels exactly on the runway and the belly `fuselage` capsule ~a strut-length above it — "landing gear precisely contacts the ground," which was the original ask. **Important caveat:** these forces are consumed by the *next* physics step (§2.1 update order), and with `k ~ 1e6` the spring is stiff relative to a 60 Hz step — if touchdown oscillates, the standard fixes are (in order) more damping, clamping `k·x·dt` impulses, or sub-stepping the suspension; tune before reaching for solver machinery.

#### Diffs: `Aircraft` + scene wiring

`GameObjects/Aircraft.swift`:

```diff
     /// Optional flight model.
     var flightModel: FlightModel? { ... }
+
+    /// Optional raycast landing-gear model (Phase B). Gated by the animator's
+    /// gear progress; aircraft without an animator report gear-down (1.0),
+    /// matching isGearDown's default.
+    var gearSuspension: LandingGearSuspension?

     override func doUpdate() {
         ...
             if let rigidBody,
                let flightModel,
                let rigidBodyState = rigidBody.getState() {
                 let force = flightModel.computeForce(state: rigidBodyState, input: controlInput)
                 rigidBody.force += force
             } else {
                 moveAlongVector(getFwdVector(), distance: deltaMove * controlInput.throttle)
             }
             ...
         } else {
             decayAttitudeRates(deltaTime: dt)
         }
+
+        // OUTSIDE the focus guard: a parked/unfocused aircraft must still be
+        // held up by its gear (flight forces are input-driven; ground
+        // reaction is not).
+        if let rigidBody, let gearSuspension {
+            gearSuspension.update(rigidBody: rigidBody,
+                                  node: self,
+                                  gearExtension: animator?.gearAnimationProgress ?? 1.0)
+        }

         animator?.update(deltaTime: dt)
```

`Scenes/FlightboxWithPhysics.swift` — the aircraft stops being a sphere:

```diff
         if let playerAircraft {
-            let acRigidBody = SphereRigidBody(gameObject: playerAircraft)
-            acRigidBody.collisionRadius = 2.0
-            acRigidBody.restitution = 0.2
+            let acRigidBody = CompoundRigidBody(gameObject: playerAircraft,
+                                                colliders: F22ColliderSpec.colliders)
+            acRigidBody.restitution = 0.2
+            acRigidBody.categoryMask = CollisionCategory.vehicle
+            // Suspension holds the aircraft up; the rest hack must not
+            // zero its velocity / disable its gravity at taxi speeds.
+            acRigidBody.freezeOnRestingContact = false
+
+            playerAircraft.gearSuspension = LandingGearSuspension(struts: F22ColliderSpec.gearStruts)
+
+            acRigidBody.onContact = { [weak playerAircraft] contact, other in
+                playerAircraft?.handleContact(contact, with: other)
+            }
```

(Per-aircraft specs slot into the existing `applyAircraftSwap` switch the same way thumbnails and camera offsets do; aircraft without a spec keep the sphere fallback.)

#### Crash vs. landing classification

With gear as suspension and airframe as colliders, classification needs no geometry at contact time — the collider *group* already says what got hit:

```swift
extension Aircraft {
    /// Physics contact classifier. Suspension handles the wheels silently, so
    /// ANY contact on this body is structure touching something.
    func handleContact(_ contact: Contact, with other: RigidBody) {
        guard contact.colliderGroupA == .airframe else { return }
        let impactSpeed = abs(dot(rigidBody?.velocity ?? .zero, contact.normal))
        // Threshold in m/s; below it, treat as a scrape (sparks, damage later).
        if impactSpeed > 3.0 || !isGearDown {
            print("[\(getName())] CRASH: \(contact.colliderNameA ?? "?") hit "
                  + "\(other.gameObject?.getName() ?? "static body") at \(impactSpeed) m/s")
            // TODO: damage model / scene reset hook (SceneManager.RequestResetScene()).
        }
    }
}
```

Touchdown quality scoring (greased vs. firm) reads `gearSuspension.compressions` and sink rate at the frame `isWeightOnWheels` flips true — no contact event involved.

### 2.5 Phase C — static structures (towers, hangars, trees)

Static compound bodies reuse everything above; the broad phase's dynamic-vs-static loop already exists. A control tower:

```swift
let tower = Cube()                       // or a dedicated model later
tower.setPosition([120, 15, 300])
tower.setScale(30)
let towerBody = CompoundRigidBody(gameObject: tower, colliders: [
    LocalCollider(name: "towerShaft", shape: .box(halfExtents: [0.5, 0.5, 0.5]),
                  group: .structure),    // Cube mesh spans ±0.5 — verify against mesh bounds
])
towerBody.isStatic = true
towerBody.shouldApplyGravity = false
towerBody.categoryMask = CollisionCategory.structure
entities.append(towerBody)
addChild(tower)
```

A hangar is 2–3 boxes (walls + roof); a tree is a capsule trunk (`.structure`) — aircraft-vs-tree resolves through capsule-vs-capsule/sphere paths already in `NarrowPhase`. The aircraft's fuselage *capsule* vs. these *boxes* uses the approximate capsule-box test (§2.3); if wing-clips-hangar-corner fidelity ever matters, that's the box-box/SAT upgrade trigger.

### 2.6 Phase D (future) — angular dynamics, contact torque, then joints

Everything above ships without touching the solvers. The *next* fidelity jump — the nose settling onto the nosewheel after main-gear touchdown, wingtip strikes yawing the aircraft, and eventually hinged/prismatic mechanisms — requires angular state. What that takes, in dependency order:

1. **Angular state on `RigidBody`**: `orientation: simd_quatf` (or reuse the node's rotation, as position does today), `angularVelocity: float3`, `torque: float3`, `inverseInertiaLocal: float3x3` (world-space inverse conjugated by the rotation each step).

2. **Mass properties for compounds** — the composition every engine implements (§1.2), directly portable:

```swift
/// Parallel-axis composition of child inertias (Bullet
/// calculatePrincipalAxisTransform / Jolt CompoundShape::GetMassProperties).
static func composeMassProperties(
    children: [(mass: Float, inertiaLocal: float3x3, rotation: float3x3, offset: float3)]
) -> (mass: Float, centerOfMass: float3, inertia: float3x3) {
    let totalMass = children.reduce(0) { $0 + $1.mass }
    let com = children.reduce(float3.zero) { $0 + $1.offset * $1.mass } / totalMass
    var inertia = float3x3()   // zero matrix
    for child in children {
        // Rotate child inertia into the body frame: R·I·Rᵀ
        let rotated = child.rotation * child.inertiaLocal * child.rotation.transpose
        // Parallel-axis term for the offset from the compound COM:
        // m·(dᵀd·𝟙 − d·dᵀ), with the outer product spelled out column-wise.
        let d = child.offset - com
        let outer = float3x3(columns: (d * d.x, d * d.y, d * d.z))
        let parallelAxis = float3x3(diagonal: float3(repeating: dot(d, d))) - outer
        inertia += rotated + child.mass * parallelAxis
    }
    return (totalMass, com, inertia)
}
```

with the primitive inertias: solid sphere `I = (2/5)mr²·𝟙`; solid box `Ixx = m(h_y² + h_z²)/3` (half-extent form) etc.; capsule = cylinder + two half-spheres composed by the same parallel-axis rule. Freeze the result at spec time (don't recompute as gear animates — §1.2's Unity COM caveat; the open question on per-frame inertia recomputation stayed open in research, and freezing is the conservative answer).

3. **Contact impulses with lever arms** (Hecker's full formulation — the current response is its point-mass reduction): impulse at contact point `p`, `r = p − centerOfMass`,

```
j = −(1+e)·(v_rel·n) / (1/mA + 1/mB + n·((I_A⁻¹(r_A×n))×r_A) + n·((I_B⁻¹(r_B×n))×r_B))
v ± = j·n/m ;  ω ± = I⁻¹(r × j·n)
```

This is the point where `Contact.point` (already produced by `NarrowPhase`) starts mattering, and where `generateContact` should return *all* contacts rather than the deepest (a two-wheel touchdown needs both lever arms).

4. **Sequential impulses** (§1.3): iterate contacts/joints a few times per step with accumulated-impulse clamping and warm starting; add Baumgarte bias `β/h · C` for position drift. Only *then* do **joints** become expressible — hinge for a physically-swinging gear door, prismatic + motor for an oleo as a *real* sliding constraint (`stiffness·(target − pos) + damping·(targetVel − vel)`, the verified Jolt motor form). The research's bottom line stands: for the gear itself, the raycast model is what shipping games use even when they *have* a full joint solver; joints earn their cost for towed gliders, wrecking balls, articulated ground vehicles, and ragdolls.

An alternative worth knowing exists — XPBD solves constraints in position space with compliance parameters and is the basis of several modern engines — but it replaces the integrator wholesale; for TFS, sequential impulses bolt onto the existing Euler/Verlet structure far more gently.

### 2.7 Testing, debugging, performance

**Tests** (Swift Testing, `.physics` tag; everything below is Metal-free — the narrow phase and suspension math are pure functions by design, matching the project's established pattern):

```swift
@Suite("NarrowPhase", .tags(.physics))
struct NarrowPhaseTests {
    @Test func sphereRestingDepthOnPlane() {
        let collider = WorldCollider(shape: .sphere(radius: 0.5), position: [0, 0.4, 0],
                                     rotation: matrix_identity_float3x3,
                                     sourceIndex: 0, name: "s", group: .airframe)
        let contact = NarrowPhase.shapeVsPlane(collider, planePoint: .zero, planeNormal: [0, 1, 0])
        #expect(contact != nil)
        #expect(approxEqual(contact!.depth, 0.1))
        #expect(approxEqual(contact!.normal, [0, 1, 0]))
    }

    @Test func tiltedBoxDeepestCornerContactsPlane() { /* rotation ⇒ projectionRadius grows */ }
    @Test func capsuleEndpointBeatsCenterOnPlane() { /* pitched capsule: deepest endpoint wins */ }
    @Test func separatedShapesProduceNoContact() { /* nil cases for every pair */ }
}

@Suite("Suspension", .tags(.physics))
struct SuspensionTests {
    @Test func springForceBalancesStaticLoad() {
        let f = LandingGearSuspension.suspensionForce(compression: 0.12, compressionVelocity: 0,
                                                      springRate: 1_100_000, dampingRate: 146_000)
        #expect(approxEqual(f, 132_000, tolerance: 1_000))
    }
    @Test func strutNeverPulls() {
        let f = LandingGearSuspension.suspensionForce(compression: 0.01, compressionVelocity: -5,
                                                      springRate: 1_100_000, dampingRate: 146_000)
        #expect(f == 0)   // rebound faster than spring push ⇒ clamped
    }
}
```

`CompoundRigidBody`/`LandingGearSuspension.update` touch `Node` transforms — testable with plain `Node`s per the Metal-free-test-design rule (no `GameObject` construction; if a `RigidBody` is needed, the `TestRigidBody(gameObject: nil)` double pattern from `PhysicsSolverTests` applies).

**Debug visualization** — the single highest-leverage tool for tuning collider specs: a `showColliders` flag that parents translucent `Sphere`/`CapsuleObject`/`Cube` children (the meshes already exist) at each `LocalCollider`'s pose with `setColor([1, 0, 0, 0.3])`. They auto-register as transparent renderables; remember `removeFromScene()` when toggling off. Struts: `Line` from attach point to wheel contact, green when compressed.

**Performance** notes, in this engine's terms:

- Broad phase is untouched (same SAP, same one-AABB-per-body); a compound's `getAABB()` is a few merges. Filtering *reduces* narrow-phase work.
- Narrow phase per candidate pair goes from O(1) to O(children_A × children_B) — with 3-collider aircraft and 1–3-collider structures that's ≤ 9 primitive tests per pair, each a handful of dot products. The per-step `worldColliders` cache keeps matrix work at one build per body per step. Jolt's `MutableCompoundShape` precedent says flat lists are the right call at these counts; a per-child AABB pre-test (or BVH) is the documented upgrade if anything ever carries dozens of children.
- Zero steady-state allocation is preserved: `worldScratch` reuses capacity like the broad phase's scratch arrays; `Contact` is a value type on the stack.
- All new work runs on the UpdateThread inside `physicsWorld.update` / `Aircraft.doUpdate` — no render-thread contact, no new locks.

### 2.8 Suggested implementation order

| Step | Deliverable | Touches | Visible result |
|---|---|---|---|
| A1 | `ColliderShape` + `LocalCollider` + `WorldCollider` + tests | new files | — |
| A2 | `NarrowPhase` + `Contact` + tests | new files | — |
| A3 | Route `HeckerCollisionResponse`/`EulerSolver`/`PhysicsWorld` through `NarrowPhase`; delete y=0 plane hack | 3 diffs | behavior parity for existing scenes (regression-test BallPhysicsScene) |
| A4 | `CompoundRigidBody` + F-22 spec + debug overlay | new files + scene diff | wingtip/belly/tail strikes register; sphere gone |
| A5 | Masks + `onContact` + `freezeOnRestingContact` | 3 small diffs | crash classification prints |
| B1 | `LandingGearSuspension` + strut spec + `Aircraft` wiring | new file + 2 diffs | aircraft rests/lands on its wheels at ride height; gear-up = belly crash |
| C1 | Static structure bodies in a scene | scene diff | fly into a tower, it objects |
| D | Angular dynamics → contact torque → sequential impulses → joints | solver rewrite | torque-true touchdowns; hinged mechanisms possible |

Each of A3, A4, B1 is independently shippable and testable; nothing blocks on D.

---

## References

All URLs visited during this research. **Bold** = user-provided starter links. *(workflow)* = fetched and verified by the research pipeline's agents; *(direct)* = fetched directly while writing this doc.

### Unity (PhysX-based)

- **https://docs.unity3d.com/ScriptReference/Rigidbody.html** — Rigidbody API: mass, COM, inertiaTensor, AddForce/AddForceAtPosition, forces in FixedUpdate *(direct)*
- **https://docs.unity3d.com/Manual/class-WheelCollider.html** — WheelCollider suspension parameters: spring N/m (35,000 default), damper (4,500), suspension distance, targetPosition 0–1, friction curves *(workflow + direct)*
- https://docs.unity3d.com/Manual/WheelColliderTutorial.html — WheelCollider setup; visual wheels driven from `GetWorldPose()` *(direct)*
- https://docs.unity3d.com/Manual/compound-colliders.html — compound collider definition, one-Rigidbody rule, when to prefer compounds vs mesh colliders *(workflow)*
- https://docs.unity3d.com/Manual/compound-colliders-introduction.html — child-collider structure; the moving-children → COM caveat *(workflow)*
- https://docs.unity3d.com/6000.0/Documentation/Manual/compound-colliders-introduction.html *(workflow)*
- https://docs.unity3d.com/6000.2/Documentation/Manual/compound-colliders-introduction.html *(workflow)*
- https://docs.unity3d.com/6000.3/Documentation/Manual/compound-colliders-introduction.html *(workflow)*
- https://docs.unity3d.com/2022.3/Documentation/Manual/physics-optimization-cpu-collider-types.html — collider cost ranking (sphere/capsule/box/mesh); MeshCollider restrictions *(workflow)*
- https://docs.unity3d.com/6000.2/Documentation/Manual/physics-optimization-cpu-collider-types.html *(workflow)*
- https://docs.unity3d.com/Manual/mesh-colliders-introduction.html — concave mesh colliders static/kinematic-only *(workflow)*
- https://docs.unity3d.com/6000.2/Documentation/Manual/mesh-colliders-introduction.html *(workflow)*
- https://docs.unity3d.com/Manual/CollidersOverview.html — collider taxonomy overview *(workflow)*
- https://docs.unity3d.com/Manual/LayerBasedCollision.html — layer collision matrix (filtering) *(workflow)*
- https://docs.unity3d.com/ScriptReference/Rigidbody-centerOfMass.html — manual COM set disables auto-recompute *(workflow)*
- https://discussions.unity.com/t/is-this-still-the-case-sphere-collider-are-more-effecient-than-cube-collider/535773 *(workflow)*
- https://discussions.unity.com/t/trying-different-ways-to-solve-this-error-non-convex-meshcollider-with-non-kinematic-rigidbody/928132 — the Unity 5+ runtime error *(workflow)*
- https://forum.unity.com/threads/capsule-vs-box-colliders.34254/ *(workflow)*
- https://www.quora.com/Is-it-true-that-a-sphere-collider-is-less-performance-heavy-than-a-box-collider *(workflow)*

### PhysX SDK

- https://nvidia-omniverse.github.io/PhysX/physx/5.5.1/docs/Geometry.html — geometry types; convex 255-vertex/face cap; SDF requirement for dynamic trimeshes *(workflow)*
- https://nvidia-omniverse.github.io/PhysX/physx/5.5.1/docs/RigidBodyCollision.html — trimesh/heightfield/plane not simulable on dynamic actors *(workflow)*
- https://nvidia-omniverse.github.io/PhysX/physx/5.4.1/docs/RigidBodyCollision.html *(workflow)*
- https://nvidia-omniverse.github.io/PhysX/physx/5.6.0/docs/RigidBodyCollision.html *(workflow)*
- https://nvidia-omniverse.github.io/PhysX/physx/5.3.0/docs/Geometry.html *(workflow)*
- https://nvidia-omniverse.github.io/PhysX/physx/5.5.1/docs/CustomGeometry.html *(workflow)*
- https://nvidia-omniverse.github.io/PhysX/physx/5.5.1/_api_build/structPxGeometryType.html *(workflow)*
- https://nvidia-omniverse.github.io/PhysX/physx/5.1.3/_build/physx/latest/class_px_convex_mesh_desc.html — vertexLimit/polygonLimit ∈ [4, 255] *(workflow)*
- https://nvidia-omniverse.github.io/PhysX/physx/5.6.0/docs/Articulations.html — reduced-coordinate articulations (the beyond-joints tier) *(workflow)*
- https://archive.docs.nvidia.com/gameworks/content/gameworkslibrary/physx/guide/Manual/RigidBodyCollision.html *(workflow)*
- https://github.com/NVIDIA-Omniverse/PhysX/blob/main/physx/CHANGELOG.md *(workflow)*

### Bullet

- https://www.cs.kent.edu/~ruttan/GameEngines/lectures/Bullet_User_Manual — Bullet 2.80 SDK manual (Coumans, 2012): convex primitives p.18, compound shapes p.19, COM-shift pattern, btRaycastVehicle recommendation p.31 *(workflow)*
- https://pybullet.org/Bullet/BulletFull/classbtCompoundShape.html — child shapes with local offset transforms; calculatePrincipalAxisTransform *(workflow)*
- https://raw.githubusercontent.com/bulletphysics/bullet3/master/src/BulletCollision/CollisionShapes/btCompoundShape.h *(workflow)*
- https://raw.githubusercontent.com/bulletphysics/bullet3/master/src/BulletCollision/CollisionShapes/btCompoundShape.cpp *(workflow)*
- https://github.com/bulletphysics/bullet3/blob/master/src/BulletCollision/CollisionShapes/btCompoundShape.h *(workflow)*
- https://pybullet.org/Bullet/BulletFull/classbtBvhTriangleMeshShape.html — "can only be used for fixed/non-moving objects" *(workflow)*
- https://github.com/bulletphysics/bullet3/blob/master/src/BulletCollision/CollisionShapes/btBvhTriangleMeshShape.h *(workflow)*
- https://pybullet.org/Bullet/BulletFull/classbtRaycastVehicle.html *(workflow)*
- https://github.com/bulletphysics/bullet3/blob/master/src/BulletDynamics/Vehicle/btRaycastVehicle.h — btActionInterface, not btTypedConstraint (refutation evidence) *(workflow)*
- https://github.com/bulletphysics/bullet3/blob/master/src/BulletDynamics/Vehicle/btRaycastVehicle.cpp *(workflow)*
- https://github.com/bulletphysics/bullet3/blob/master/src/BulletDynamics/ConstraintSolver/btGeneric6DofConstraint.h *(workflow)*
- https://www.staff.city.ac.uk/~andrey/INM377/bullet-2.82-html/html/btRaycastVehicle_8h_source.html *(workflow)*
- https://docs.panda3d.org/1.11/cpp/programming/physics/bullet/collision-shapes — Bullet shape catalog via Panda3D *(workflow)*
- https://docplayer.net/58650489-Vehicle-simulation-with-bullet.html *(workflow)*
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=11004 *(workflow)*
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=2130 *(workflow)*
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=2562 *(workflow)*
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=3702 *(workflow)*
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=5766 *(workflow)*
- https://pybullet.org/Bullet/phpBB3/viewtopic.php?t=7095 *(workflow)*

### Jolt

- https://github.com/jrouwe/JoltPhysics/blob/master/Docs/Architecture.md — shape catalog in complexity order; Static/MutableCompoundShape; mass override modes; OffsetCenterOfMassShape; 13-constraint catalog; motor formula; sequential impulses + warm starting; filtering pipeline; GroupFilterTable *(workflow)*
- https://raw.githubusercontent.com/jrouwe/JoltPhysics/master/Docs/Architecture.md *(workflow)*
- https://raw.githubusercontent.com/jrouwe/JoltPhysics/master/Jolt/Physics/Collision/Shape/CompoundShape.cpp — GetMassProperties composition *(workflow)*
- https://jrouwe.github.io/JoltPhysics/ *(workflow)*
- https://jrouwe.github.io/JoltPhysics/class_cylinder_shape.html *(workflow)*
- https://jrouwe.github.io/JoltPhysics/class_ragdoll_settings.html — auto GroupFilterTable for ragdolls *(workflow)*
- https://jrouwe.github.io/JoltPhysicsDocs/5.0.0/class_vehicle_constraint.html — "adds virtual wheels or tracks to a body" *(workflow)*
- https://jrouwe.github.io/JoltPhysics/md__docs_2_release_notes.html *(workflow)*

### Constraint solving / physics theory

- https://box2d.org/files/ErinCatto_ModelingAndSolvingConstraints_GDC2009.pdf — constraints unify joints/contacts; sequential impulses; symplectic Euler *(workflow)*
- https://box2d.org/files/ErinCatto_IterativeDynamics_GDC2005.pdf — PGS formulation *(workflow)*
- https://box2d.org/doc_version_2_4/md__e_1_2github_2box2d__24_2docs_2dynamics.html — Box2D dynamics/joints reference *(workflow)*
- https://box2d.org/posts/2024/02/solver2d/ — Catto's modern solver comparison (relaxation, soft constraints, TGS) *(workflow)*
- https://matthias-research.github.io/pages/publications/XPBD.pdf — XPBD: position-based dynamics with compliance *(workflow)*
- https://allenchou.net/2013/12/game-physics-constraints-sequential-impulse/ — sequential impulse tutorial *(workflow)*
- http://www.mft-spirit.nl/files/MTamis_Constraints.pdf — constraint Jacobian derivations *(workflow)*
- http://www.mft-spirit.nl/files/MTamis_PGS_SI_Comparison.pdf — PGS vs SI equivalence *(workflow)*
- https://gamedev.net/forums/topic/361031-adding-inertia-tensors-together/3372851/ — parallel-axis compound inertia discussion *(workflow)*
- https://www.iforce2d.net/b2dtut/collision-filtering — Box2D category/mask/group filtering *(workflow)*

### Vehicles, landing gear, other engines

- **https://www.alexjamerson.com/blog-1/2021/9/11/how-i-rigged-aircraft-landing-gear-in-3d-software** — PBY-5A gear rig: hierarchy + constraints + deformers, one control parameter drives the whole mechanism *(direct)*
- https://docs.flightsimulator.com/html/mergedProjects/How_To_Make_An_Aircraft/Contents/Modelling/Airframe/Animations/Animating_Landing_Gear.htm — MSFS SDK: gear as keyframed animation *(workflow)*
- https://medium.com/@remvoorhuis/how-to-program-realistic-vehicle-physics-for-realtime-environments-games-part-i-simple-b4c2375dc7fa — raycast vehicle suspension walkthrough *(workflow)*
- https://defold.com/manuals/physics-shapes/ — multiple primitives per collision component; complex shapes must be sole shape *(workflow)*
- https://forum.defold.com/t/can-i-use-multiple-convex-hull-shapes/74715 *(workflow)*

### Non-URL references

- Christer Ericson, *Real-Time Collision Detection* — closest-point primitives used in §2.3 (segment-segment §5.1.9, point-OBB §5.1.4).
- Chris Hecker, *Physics, Part 3: Collision Response* (Game Developer Magazine, 1997) — already the basis of `HeckerCollisionResponse`; its full angular form is the §2.6 step 3 formula. https://www.chrishecker.com/images/e/e7/Gdmphys3.pdf (cited in the existing code).
