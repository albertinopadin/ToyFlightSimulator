# Compound rigid bodies, articulated parts, and aircraft landing gear

Research and implementation proposal for ToyFlightSimulator
Date: 2026-07-14

## Executive answer

The proposed direction is correct, with one important terminology and architecture change:

- A complex but rigid object is normally **one rigid body with multiple colliders (shapes)**. The colliders may be spheres, oriented boxes, capsules, convex hulls, and so on, each with a transform relative to the body. This is a *compound collider* or *compound shape*. It has one mass, center of mass, inertia tensor, pose, linear velocity, and angular velocity.
- A part that truly moves relative to another massive part is a **second rigid body connected by a joint/constraint**, or a link in an **articulation**. The joint removes unwanted degrees of freedom and may add limits, springs, damping, motors/drives, and break forces.
- A scripted part whose mass and reaction forces are unimportant can remain an **animated child collider** on the main body. Landing-gear deployment doors and most flight-control surfaces fit here. They do not need separate rigid bodies merely because they animate.
- Landing-gear ground support is commonly modeled as a **contact query plus a spring/damper and tire-force model**, with its force applied to the aircraft at the wheel contact point. Applying the force away from the center of mass creates the correct pitch/roll/yaw moment. This can produce precise three-point ground contact without simulating every strut link as a rigid body.

For ToyFlightSimulator, the recommended first target is therefore:

1. Separate `Collider` from `RigidBody` and allow many colliders per body.
2. Add box and capsule geometry, body orientation, angular velocity, torque, center of mass, and inertia.
3. Generate contact manifolds between *colliders*, but resolve them against their owning *bodies*.
4. Give each aircraft a fixed compound structural collider plus three animated landing-gear contact units.
5. Use the existing skeleton/gear animation to position each wheel unit, but calculate compression, normal force, tire friction, and crash state in physics.
6. Add generic joints only after the angular/contact solver is stable. Full landing-gear articulations are an optional later tier, not the foundation.

This yields the behavior the project needs: gear-down landings are supported at the actual wheel positions; gear-up aircraft fall onto their belly/wing/tail colliders; a wingtip, nose, tail, or fuselage strike is distinguishable; and one aircraft does not accidentally become a collection of independent masses.

## 1. Research: how rigid-body engines represent complex objects

### 1.1 Body, collider, contact, constraint, and joint are different things

A **rigid body** is the simulated mass state. In 3D it has six unconstrained degrees of freedom: three translation and three rotation. A production body normally owns or references:

- position and orientation;
- linear and angular velocity;
- accumulated force and torque;
- mass and inverse mass;
- a center-of-mass frame and inertia tensor;
- motion type (static, kinematic, or dynamic);
- one or more collision shapes.

PhysX explicitly separates linear and angular velocity and requires mass, moment of inertia, and a center-of-mass frame for a dynamic actor. Unity exposes the same concepts through `Rigidbody`, including center of mass, inertia tensor, angular velocity, force-at-position, torque, and solver iteration settings. [PhysX rigid-body dynamics](https://nvidia-omniverse.github.io/PhysX/physx/5.4.0/docs/RigidBodyDynamics.html) and [Unity `Rigidbody`](https://docs.unity3d.com/ScriptReference/Rigidbody.html) are useful references.

A **collider/shape** is geometry attached to a body. It defines where contacts can occur and usually carries material and filtering data. It does not own an independent velocity or mass state merely because it has a local offset. Box2D states this distinction compactly: a shape binds collision geometry and material properties to a body. Its contact constraints are created automatically; joint constraints are explicit connections between bodies. Although Box2D is 2D, this vocabulary and solver organization are also used by 3D engines. See the [Box2D overview](https://box2d.org/documentation/).

A **contact** is generated when two shapes touch. It normally contains a normal, one or more contact points, separation/penetration, shape identifiers, and material data. Multiple nearby contact points form a **contact manifold**. Resolving the manifold produces impulses that affect both linear and angular velocity.

A **constraint** is a mathematical restriction on body motion. A non-penetration contact is itself a constraint. A **joint** is an application-authored constraint between bodies. A hinge/revolute joint removes five of the six relative degrees of freedom and leaves one rotation. A prismatic joint leaves one translation. Limits restrict the remaining coordinate; a motor or drive targets a speed or position; a spring and damper make the restriction compliant.

The word **articulation** generally means a tree of rigid links solved as one mechanism in reduced coordinates. Rather than storing every link as an unconstrained six-degree-of-freedom body and repeatedly correcting joint errors, the solver stores the root pose and only the permitted joint coordinates. PhysX describes this as having no unwanted separation on locked axes and a cost often proportional to degrees of freedom rather than link count. See [PhysX articulations](https://nvidia-omniverse.github.io/PhysX/physx/5.6.0/docs/Articulations.html).

### 1.2 Collision geometry used by engines

Common 3D collision geometry falls into four groups.

#### Analytic convex primitives

- **Sphere**: cheapest and rotation-invariant. Good for balls, rounded masses, joints, canopies, and coarse broad approximations.
- **Box / oriented bounding box (OBB)**: good for buildings, crates, wings, slabs, doors, vehicles, and equipment. Its world AABB changes with rotation.
- **Capsule**: a line segment swept by a sphere. Good for fuselages, limbs, trunks, pipes, missiles, rotor blades, and elongated rounded parts. It avoids the sharp-edge instability of cylinders.
- **Plane**: an infinite half-space, useful for mathematical test grounds but not a finite runway or general terrain.
- **Cylinder, tapered capsule/cylinder, cone**: available in some engines. Jolt warns that cylinders are among its least stable shapes and recommends another shape when practical.

Unity's built-in primitive colliders are box, sphere, and capsule. Unreal's “simple collision” adds convex hulls, and its Physics Assets support spheres, boxes, capsules, tapered capsules, and convex elements. Jolt exposes spheres, boxes, capsules, tapered capsules, cylinders, convex hulls, planes, and decorators. Sources: [Unity primitive colliders](https://docs.unity3d.com/Manual/primitive-colliders.html), [Unreal Physics Bodies reference](https://dev.epicgames.com/documentation/unreal-engine/physics-bodies-reference-for-unreal-engine?lang=en-US), and [Jolt architecture](https://jrouwe.github.io/JoltPhysics/).

#### General convex shapes

A **convex hull** tightly wraps an arbitrary convex point set. A dynamic concave object is usually decomposed into several convex hulls. Convex shapes are attractive because support-mapping algorithms such as GJK can test separation, EPA can find penetration depth, and feature clipping can build stable contact manifolds across many convex shape pairs.

Convex hulls are more faithful than primitives but more expensive and more sensitive to authoring quality. A small number of authored hulls is usually preferable to using the render mesh or generating hundreds of tiny hulls.

#### Concave/static geometry

- **Triangle mesh**: accurate for runways, hangars, control towers, and other static world geometry. Dynamic triangle meshes are expensive and often unstable; Unity recommends primitives for moving bodies and Unreal does not allow “complex as simple” geometry to be simulated as a dynamic object.
- **Height field**: optimized terrain grid; normally static.
- **Signed-distance/custom geometry**: supported by some high-end engines, but not a sensible first implementation here.

See [Unity Mesh colliders](https://docs.unity3d.com/Manual/class-MeshCollider.html), [Unreal simple versus complex collision](https://dev.epicgames.com/documentation/unreal-engine/simple-versus-complex-collision-in-unreal-engine?lang=en-US), and [PhysX geometry queries](https://nvidia-omniverse.github.io/PhysX/physx/5.4.1/docs/GeometryQueries.html).

#### Compound and decorator shapes

A compound is a hierarchy or list of child shapes with local translations and rotations. Unity describes it as child collider GameObjects under one parent `Rigidbody`; the physics system treats the collection as one body. PhysX attaches several `PxShape`s to one actor and gives each shape a local pose. Jolt has static and mutable compound shapes and uses sub-shape IDs to identify the exact leaf that was hit.

Important behavior follows from this design:

- child shapes on the same body do not collide with one another;
- overlapping child shapes are acceptable for ordinary collision response, although they can duplicate events or contacts if not filtered/merged;
- one union AABB can represent the body in the broad phase, followed by leaf-shape checks in the narrow phase;
- a hit still reports which child shape was involved, enabling `leftWing`, `noseGear`, or `fuselage` damage logic;
- moving a child shape changes collision geometry but should not silently create another body.

Unity explicitly recommends one parent `Rigidbody` and the simplest child shapes that adequately cover the object. It also warns that continuously moving child colliders can affect automatically calculated center of mass. PhysX's `PxShape.setLocalPose` similarly does not automatically update the actor's inertia. For aircraft, that is a reason to author/freeze mass, center of mass, and inertia rather than recompute them on every gear-animation frame. Sources: [Unity compound collider creation](https://docs.unity3d.com/Manual/create-compound-collider.html), [Unity compound collider introduction](https://docs.unity3d.com/Manual/compound-colliders-introduction.html), and [PhysX `PxShape`](https://nvidia-omniverse.github.io/PhysX/physx/5.4.0/_api_build/class_px_shape.html).

### 1.3 When a joint is appropriate

Use multiple shapes on one body when the distance between the shapes is meant to remain exactly fixed. PhysX specifically notes that a single actor with multiple shapes is cheaper than fixed-jointing several actors, has no joint drift, and should be preferred unless the connection must break or report joint force.

Use separate bodies and a joint when at least one of the following is true:

- the child has meaningful mass/inertia and should react dynamically;
- relative motion must be solved from forces rather than authored animation;
- the connection has compliance, limits, a motor, break force, or load reporting;
- the part can detach;
- collision should transfer momentum through the mechanism rather than directly to one body.

Common joints are:

| Joint | Free relative motion | Example |
| --- | --- | --- |
| Fixed/weld | none | breakable aircraft panel, bolted assembly |
| Revolute/hinge | one rotation | door, flap hinge, folding gear link |
| Prismatic/slider | one translation | oleo strut compression, piston |
| Spherical/ball | two or three rotations | shoulder, rod end |
| Distance | constrained distance | cable or linkage |
| D6/configurable | selected linear/angular axes | complex suspension or steering knuckle |

Joint frames are defined in the local coordinates of both connected bodies. The solver tries to make the permitted coordinates obey their limits and the locked coordinates coincide. PhysX's D6 drive is a proportional-derivative controller:

```text
driveForce = stiffness * (targetPosition - position)
           + damping   * (targetVelocity - velocity)
```

This is what “a joint motor/spring drive” means in code: it does not set a transform directly; it asks the constraint solver to apply bounded force/torque toward a target. See [PhysX joints](https://nvidia-omniverse.github.io/PhysX/physx/5.4.0/docs/Joints.html).

An articulation is appropriate for a real multi-link landing gear, excavator, robotic arm, or ragdoll. It is overkill for a gear leg that is visually animated between two states and needs only suspension compression at touchdown. Full articulation also introduces link mass ratios, constraint iteration requirements, self-collision filtering, and a two-way animation/physics ownership problem.

### 1.4 The collision pipeline used by real-time engines

#### Broad phase

The broad phase cheaply returns potentially overlapping *bodies* or *shapes* using conservative bounding volumes. Common structures are sweep-and-prune, dynamic AABB trees/BVH, grids, and static/dynamic query trees. ToyFlightSimulator's cached-AABB single-axis sweep-and-prune is already a valid broad phase for its intended counts.

For a compound body, compute a world AABB for every enabled child shape, union them into the body AABB, and submit one body proxy to the existing sweep. If a body pair overlaps, optionally AABB-test its child shapes before exact narrow-phase tests. This prevents an aircraft with 20 colliders from appearing as 20 independent dynamic entities in the global sweep.

#### Narrow phase

The narrow phase finds exact contacts. A practical implementation grows in tiers:

1. Analytic sphere-sphere, sphere-plane, sphere-box, capsule-plane, and box-plane.
2. OBB-vs-OBB separating-axis test (SAT), with face/edge clipping for contacts.
3. Capsule-sphere, capsule-capsule, and capsule-box using closest points on segments/features.
4. General convex GJK distance/intersection, EPA penetration depth, and a persistent manifold builder.
5. Convex-vs-triangle-mesh/heightfield for static environments.

A boolean overlap is not enough for a stable aircraft-on-ground solver. The result needs a consistent normal, penetration/separation, point on the surfaces, and collider IDs. Box2D's documentation explains why a manifold approximates a continuous contact region with a small number of points and why contacts must be available to the constraint solver before movement. See [Box2D collision](https://box2d.org/documentation/md_collision.html) and [Box2D simulation](https://box2d.org/documentation/md_simulation.html).

#### Response and constraint solve

At contact point `p`, the velocity is not just the body's center-of-mass velocity:

```text
v(p) = linearVelocity + angularVelocity × (p - centerOfMass)
```

The normal impulse denominator includes inverse mass *and* inverse inertia. In abbreviated form for contact normal `n`, offsets `rA`/`rB`, and inverse world inertia `I⁻¹`:

```text
j = -(1 + restitution) * dot(vB(p) - vA(p), n)
    / (invMassA + invMassB
       + dot(n, cross(I⁻¹A * cross(rA, n), rA)
              + cross(I⁻¹B * cross(rB, n), rB)))
```

Apply `±j*n` to linear velocities and `r × impulse` through inverse inertia to angular velocities. Then solve one or two tangent directions for friction, clamped by Coulomb friction (`|jt| <= μ * jn`). Iterate the contact and joint rows several times, warm-starting from the prior frame when feature IDs persist. Use a small penetration slop and split/position correction; do not turn gravity off to fake resting contact.

This sequential-impulse style is standard because contacts and joints become the same general class of velocity constraint. The Box2D overview calls its solver a sequential solver; PhysX describes contacts and joints as constraints and exposes position/velocity iteration counts. [PhysX's 1D constraint formulation](https://nvidia-omniverse.github.io/PhysX/physx/5.4.0/_downloads/f27bad5e4b631dc274a41ecf77568a49/constraintFormulation.pdf) contains the fuller derivation.

#### Discrete time, fixed steps, and CCD

Collision can be missed when a fast or thin body crosses another between samples (“tunneling”). Engines address it with:

- a fixed simulation step independent of display refresh;
- multiple substeps for stiff contacts and suspension;
- swept shape casts/time of impact for fast objects;
- speculative contacts before shapes actually overlap.

Unity documents sweep and speculative CCD for box, sphere, and capsule colliders, while warning that CCD is a safety net and a smaller timestep may still be required. For ToyFlightSimulator, a fixed `1/120 s` physics step with a bounded accumulator is a reasonable aircraft/gear starting point; retain `1/60 s` as a performance option and use more substeps during touchdown tests. See [Unity CCD](https://docs.unity3d.com/Manual/ContinuousCollisionDetection.html).

### 1.5 How engines model vehicles and landing gear

There are three useful fidelity levels.

#### Level A: one body plus contact/suspension queries

Unity's Wheel Collider is not a rolling cylinder collider. It casts one ray along the suspension axis, computes suspension and slip-based tire forces, and drives the separate visual wheel transform. This is efficient, but Unity documents that a center ray can clip/pop at curbs and steps. A sphere/capsule sweep instead of a ray improves the contact volume where rough terrain matters. See [Wheel Collider introduction](https://docs.unity3d.com/Manual/wheel-colliders-introduction.html), [suspension](https://docs.unity3d.com/Manual/wheel-colliders-suspension.html), and [friction](https://docs.unity3d.com/Manual/wheel-colliders-friction.html).

JSBSim uses an especially relevant aircraft model. It maintains landing-gear and structural contact points, computes compression and compression velocity, evaluates a spring/damper normal force, calculates runway-plane friction, and applies the resulting force and moment to the aircraft. Its documented moment is `r × F`, exactly the mechanism needed for asymmetric touchdowns and nose/main-gear loading. See [JSBSim `FGLGear`](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGLGear.html) and [`FGGroundReactions`](https://jsbsim-team.github.io/jsbsim/python/FGGroundReactions.html).

This level is the best first implementation for ToyFlightSimulator.

#### Level B: animated collision shapes plus suspension queries

The deployment linkage and doors are animation-driven. The animation supplies a body-local wheel hub, suspension axis, and steering frame each physics step. Only a downlocked gear unit supports the aircraft. A wheel sphere/capsule may also participate in ordinary impact detection. The strut compression returned by physics offsets the visual wheel/strut pose after the deployment animation, so animation controls *deployment* while physics controls *compression*.

The provided aircraft-rigging article describes the visual side well: a parent-child hierarchy, directional/position constraints, up vectors, and IK/deformation for linkages and brake lines. Those are animation constraints, not collision-response constraints. The key integration lesson is to expose stable gear attachment frames from the rig rather than infer them from rendered vertices. See [Alex Jamerson's landing-gear rigging article](https://www.alexjamerson.com/blog-1/2021/9/11/how-i-rigged-aircraft-landing-gear-in-3d-software).

#### Level C: fully articulated gear

The aircraft, strut links, bogies, and wheels are separate bodies. Revolute/prismatic/D6 joints enforce geometry, drives deploy the gear, a spring/damper acts through the strut, and collision impulses flow through the joint tree. This can model shimmy, link loads, breakage, detached wheels, and detailed rough-surface response. It is also substantially harder to make stable.

For a flight game, use this only when the extra behavior is visible or affects gameplay. A full mechanism is not required merely to tell gear-down touchdown from a belly strike.

### 1.6 Patterns across engines

| Engine/library | Complex rigid object | Articulated object | Vehicle/gear pattern | Notable lesson |
| --- | --- | --- | --- | --- |
| Unity / PhysX | One `Rigidbody`, child colliders | Joints or `ArticulationBody` tree | Ray-based Wheel Colliders with spring/damper and slip | Moving child colliders is supported; manage COM/inertia deliberately |
| Unreal / Chaos | Multiple simple primitives/convexes per body | Physics Asset bodies and constraints aligned to bones | Chaos Vehicle wheels plus skeletal animation | Simple collision for dynamic objects; trimesh mainly for static/query geometry |
| Godot / Jolt | A body can own multiple shapes | Joint nodes / physical bones | `VehicleBody3D`/wheel system | Shape index is retained in contact events, which is useful for damage roles |
| Jolt library | Static or mutable compound shape | Constraints and vehicle constraint | Pluggable wheel collision tester and suspension | Child/sub-shape IDs and explicit center-of-mass decorator are first-class |
| Box2D | Multiple shapes on one body | Revolute, prismatic, wheel, weld, etc. | Wheel joint | Contacts and joints are both iterative constraints; same-body shapes do not collide |
| JSBSim | Aircraft mass state plus structural contact points | Not a general game collision engine | Aircraft-specific spring/damper gear contacts | Ground forces at gear points naturally generate aircraft moments |

Unreal's [Physics Asset Editor](https://dev.epicgames.com/documentation/unreal-engine/physics-asset-editor-interface-in-unreal-engine?lang=en-US) is also a useful authoring model for this project: bodies/shapes and constraints are associated with named skeleton bones, visualized, tested, and selectively collision-filtered rather than hard-coded ad hoc in the runtime.

## 2. Potential implementation in ToyFlightSimulator

### 2.1 Current-state audit

The current engine has several good foundations:

- physics entities are concrete reference-type `RigidBody` objects;
- the update thread owns scene/physics mutation;
- broad phase caches each body AABB once and reuses scratch storage;
- the renderer/update semaphore handshake publishes one coherent transform snapshot;
- skeleton channels resolve joint paths outside the hot path;
- landing-gear state/progress and named gear joints already exist;
- `Node` has a cached transform hierarchy suitable for rendering animated descendants.

The blockers are structural rather than a lack of more `RigidBody` subclasses:

1. `CollisionShape` has only `.Sphere` and `.Plane`, and shape state is stored on the body itself.
2. `SphereRigidBody` and `PlaneRigidBody` combine body state with one geometry type.
3. `PhysicsWorld` switches on the body type and force-casts subclasses, which cannot express many leaf shapes owned by one body.
4. Cubes and capsules in `FlightboxWithPhysics` are currently simulated as spheres; every player aircraft is a radius-2 sphere.
5. Only translation is integrated. Aircraft attitude is written directly to `Node`; contacts cannot produce roll, pitch, or yaw.
6. `HeckerCollisionResponse` uses center velocity only, resolves at most one response per body pair, has no friction manifold, and disables gravity as a resting-contact workaround.
7. Sphere-plane penetration assumes the plane is at world `y = 0`, even though the collision test itself reads the plane pose/normal.
8. Physics uses render-frame delta time. At 30/60/120 Hz, contact/suspension behavior will differ and a long frame can create deep penetration.
9. In the current traversal, `FlightboxWithPhysics.doUpdate()` steps physics before child `Aircraft.doUpdate()` accumulates this frame's aerodynamic force and updates gear animation. Forces therefore take effect one update later, and animated colliders would also lag without explicit phases.
10. `Skeleton.currentPose` becomes a skinning palette (`jointWorld * inverseBind`, basis-conjugated). It is not a raw model-space joint transform that a physics collider should consume.
11. Render scales such as `3.0`, `0.25`, and `12.0` are asset normalization choices, not a reliable meter scale. Physics geometry needs an explicit asset-to-meter contract.

### 2.2 Target object model

The central refactor is:

```text
GameObject / Node (render hierarchy)
        │ publishes/receives one body pose
        ▼
RigidBody (one mass state)
  ├─ Collider[0] fuselage capsule, fixed body-local pose
  ├─ Collider[1] left-wing box/hull, fixed body-local pose
  ├─ Collider[2] right-wing box/hull, fixed body-local pose
  ├─ Collider[3] tail, fixed body-local pose
  └─ LandingGearUnit[0...2]
       ├─ animation-resolved body-local hub/strut pose
       ├─ wheel sweep/contact shape
       └─ suspension + tire-force state
```

Separate *geometry*, *instance*, and *body*:

```swift
import simd

enum CapsuleAxis: Sendable {
    case x, y, z
}

enum ColliderGeometry: Sendable {
    case sphere(radius: Float)
    case box(halfExtents: float3)
    case capsule(radius: Float, halfHeight: Float, axis: CapsuleAxis)
    case plane(normal: float3, offset: Float)
    // Later: case convexHull(ConvexHullHandle)
    // Static-only later: case triangleMesh(TriangleMeshHandle)
}

struct PhysicsMaterial: Sendable {
    var staticFriction: Float = 0.8
    var dynamicFriction: Float = 0.6
    var restitution: Float = 0.05
}

enum AircraftColliderPart: String, Sendable {
    case fuselage, nose, leftWing, rightWing, leftTail, rightTail
    case noseGear, leftMainGear, rightMainGear
}

enum ColliderRole: Sendable {
    case structure(AircraftColliderPart)
    case landingGear(AircraftColliderPart)
    case sensor
}

struct PhysicsPose: Sendable {
    var position: float3 = .zero
    var orientation = simd_quatf(angle: 0, axis: float3(0, 1, 0))

    var matrix: float4x4 {
        var result = float4x4(orientation)
        result.columns.3 = float4(position, 1)
        return result
    }

    func transformed(point: float3) -> float3 {
        orientation.act(point) + position
    }

    static func * (lhs: PhysicsPose, rhs: PhysicsPose) -> PhysicsPose {
        PhysicsPose(position: lhs.transformed(point: rhs.position),
                    orientation: lhs.orientation * rhs.orientation)
    }
}

struct Collider: Sendable {
    let id: UInt32
    var geometry: ColliderGeometry
    var bodyFromCollider: PhysicsPose
    var material: PhysicsMaterial
    var role: ColliderRole
    var isEnabled: Bool = true
    var categoryBits: UInt32 = 1
    var maskBits: UInt32 = .max
}
```

`RigidBody` then owns `ContiguousArray<Collider>`. `SphereRigidBody` and `PlaneRigidBody` can remain temporarily as compatibility factories, but collision dispatch must move from body subclass casts to `ColliderGeometry` values.

### 2.3 Body state, force at a point, and angular integration

Add these to `RigidBody`:

```swift
var pose = PhysicsPose()
var centerOfMassLocal: float3 = .zero
var linearVelocity: float3 = .zero
var angularVelocity: float3 = .zero
var accumulatedForce: float3 = .zero
var accumulatedTorque: float3 = .zero
var inverseMass: Float = 1
var inverseInertiaLocal = matrix_identity_float3x3
var colliders = ContiguousArray<Collider>()

func addForce(_ force: float3, atWorldPoint point: float3) {
    accumulatedForce += force
    let centerWorld = pose.transformed(point: centerOfMassLocal)
    accumulatedTorque += cross(point - centerWorld, force)
}

func pointVelocity(atWorldPoint point: float3) -> float3 {
    let centerWorld = pose.transformed(point: centerOfMassLocal)
    return linearVelocity + cross(angularVelocity, point - centerWorld)
}
```

For a body-space inertia tensor `Ibody`, form `Iworld⁻¹ = R * Ibody⁻¹ * Rᵀ`. A semi-implicit angular update is:

```swift
let rotation = float3x3(body.pose.orientation)
let inverseInertiaWorld = rotation * body.inverseInertiaLocal * rotation.transpose

// The gyroscopic term is optional in the first milestone; include it once
// Ibody and the integrator have dedicated tests.
body.angularVelocity += inverseInertiaWorld * body.accumulatedTorque * dt

let omega = body.angularVelocity
let speed = length(omega)
if speed > 1e-7 {
    let dq = simd_quatf(angle: speed * dt, axis: omega / speed)
    body.pose.orientation = simd_normalize(dq * body.pose.orientation)
}
```

For aircraft, author mass, COM, and inertia in an `AircraftPhysicsConfig`; do not infer the aircraft's mass distribution from collision approximations every frame. Primitive-volume mass computation is useful for crates and debris. Compound inertia can be built from per-shape mass and the parallel-axis theorem, but an aircraft's fuel, engines, stores, and landing gear make an authored tensor more meaningful than uniformly dense wing boxes.

The physics pose should become authoritative for dynamic objects. Publish it back to `Node` once after all fixed substeps, using one `setPhysicsPose(position:orientation:)` operation that dirties the subtree once. Do not call three `rotateX/Y/Z` operations per substep.

### 2.4 Compound AABBs and narrow-phase dispatch

Preserve the existing global broad phase. Change `RigidBody.getAABB()` to union child bounds:

```swift
func getAABB() -> AABB {
    var result: AABB?
    for collider in colliders where collider.isEnabled {
        let worldFromCollider = pose * collider.bodyFromCollider
        let child = collider.geometry.worldAABB(pose: worldFromCollider)
        result = result.map { $0.merged(with: child) } ?? child
    }
    return result ?? AABB(center: pose.position, radius: .zero)
}
```

For an oriented box with rotation matrix `R` and half extents `e`, the world AABB half extents are `abs(R) * e`. A capsule AABB encloses its two world endpoints expanded by radius. These calculations are cheap and allocation-free.

After a body pair passes broad phase:

```swift
for colliderAIndex in bodyA.colliders.indices {
    let a = bodyA.worldCollider(at: colliderAIndex)
    guard a.isEnabled else { continue }

    for colliderBIndex in bodyB.colliders.indices {
        let b = bodyB.worldCollider(at: colliderBIndex)
        guard b.isEnabled,
              CollisionFilter.shouldCollide(a, b),
              a.aabb.overlaps(b.aabb)
        else { continue }

        NarrowPhase.generateContacts(a, b, into: &manifoldsScratch)
    }
}
```

The contact representation should retain the leaf identities:

```swift
struct ContactPoint {
    var position: float3
    var normalFromAToB: float3
    var penetration: Float
    var featureID: UInt64
    var normalImpulse: Float = 0
    var tangentImpulse: float2 = .zero
}

struct ContactManifold {
    unowned let bodyA: RigidBody
    unowned let bodyB: RigidBody
    let colliderA: UInt32
    let colliderB: UInt32
    var points: ContiguousArray<ContactPoint>
}
```

Do not carry forward `collidedWith` as “one response per body pair.” A fuselage and both wheels may legitimately contact the runway in one step; each manifold matters. De-duplicate by collider pair and feature ID, not by body identity.

### 2.5 Landing gear: recommended hybrid model

Each gear unit should have data independent of its render mesh:

```swift
enum GearID: Sendable { case nose, leftMain, rightMain }

struct LandingGearConfig: Sendable {
    let id: GearID
    let wheelRadius: Float
    let restLength: Float               // hub clearance at zero compression
    let maxTravel: Float
    let springRate: Float               // N/m
    let compressionDamping: Float       // N*s/m
    let reboundDamping: Float
    let rollingFriction: Float
    let lateralFriction: Float
    let maxSupportForce: Float
    let downLockProgress: Float          // for example 0.98
    let jointPath: String
    let jointFromWheelHub: PhysicsPose
}

struct LandingGearRuntime {
    let config: LandingGearConfig
    let skeletonIndex: Int
    let jointIndex: Int                  // resolved once
    var compression: Float = 0
    var compressionVelocity: Float = 0
    var isWeightOnWheel: Bool = false
    var wheelAngularSpeed: Float = 0
}
```

At `preparePhysics` time, update gear deployment animation first, read the raw joint model pose, convert it through the aircraft's explicit `assetToBodyMeters` transform, and store the hub pose. At each fixed substep:

1. If deployment progress is below `downLockProgress`, disable support. Optionally leave a collision-only shape enabled so partially deployed gear can be damaged.
2. Sweep a wheel sphere along the suspension axis from full compression to full extension. Against the current plane this is an analytic signed-distance test; later it can use a general world sphere cast.
3. Compute compression `x` and compression rate `xDot` from the contact distance and body point velocity.
4. Calculate a one-sided normal force:

```text
normalForce = max(0, springRate * x + damping * xDot)
```

Use compression or rebound damping according to the sign of `xDot`, and clamp to `maxSupportForce` for damage/solver safety.

5. Compute longitudinal and lateral velocity in the runway tangent plane. Add rolling/braking and side forces, clamped by available normal load.
6. Apply the total force at the world contact point through `RigidBody.addForce(_:atWorldPoint:)`.
7. Record weight-on-wheels, overload, sink rate, and which unit contacted for gameplay and animation.

A compact first implementation against a flat plane can look like:

```swift
mutating func solveFlatGround(body: RigidBody,
                              hubWorld: float3,
                              groundPoint: float3,
                              groundNormal: float3,
                              dt: Float) {
    let normal = normalize(groundNormal)
    let hubHeight = dot(hubWorld - groundPoint, normal) - config.wheelRadius
    let newCompression = clamp(config.restLength - hubHeight,
                               min: 0,
                               max: config.maxTravel)

    guard newCompression > 0 else {
        compression = 0
        compressionVelocity = 0
        isWeightOnWheel = false
        return
    }

    compressionVelocity = (newCompression - compression) / dt
    compression = newCompression
    isWeightOnWheel = true

    let damping = compressionVelocity >= 0
        ? config.compressionDamping
        : config.reboundDamping
    let support = min(config.maxSupportForce,
                      max(0, config.springRate * compression
                             + damping * compressionVelocity))

    let contact = hubWorld - normal * config.wheelRadius
    let pointVelocity = body.pointVelocity(atWorldPoint: contact)
    let tangentVelocity = pointVelocity - dot(pointVelocity, normal) * normal

    // First milestone: viscous tangent force with a Coulomb cap. Replace with
    // separate longitudinal/lateral slip curves when braking/steering lands.
    let desiredTangentForce = -tangentVelocity * config.lateralFriction
    let maxTangentForce = support * config.rollingFriction
    let tangentLength = length(desiredTangentForce)
    let tangentForce = tangentLength > maxTangentForce && tangentLength > 0
        ? desiredTangentForce * (maxTangentForce / tangentLength)
        : desiredTangentForce

    body.addForce(normal * support + tangentForce,
                  atWorldPoint: contact)
}
```

The example focuses on data flow for a horizontal plane. A general suspension query should cast along a standardized local strut axis and derive compression from the hit distance rather than assume the runway normal aligns with the strut.

For initial tuning, choose desired static compression `x0` and supported mass fraction `fi` per gear:

```text
k_i = fi * mass * g / x0
mEffective_i = fi * mass
c_i = 2 * dampingRatio * sqrt(k_i * mEffective_i)
```

Start with damping ratio `0.7...1.0`, then validate at representative landing weights and sink rates. Main gear usually carries most static load; do not split the load equally unless the configured CG/gear geometry actually does so.

### 2.6 Structural collision and crash classification

Do not define “crash” as any aircraft/ground contact. Define it from collider roles, gear state, load, and impact conditions:

```swift
enum AircraftContactOutcome {
    case supportedByGear(GearID, normalLoad: Float)
    case scrape(part: AircraftColliderPart, impulse: Float)
    case overload(part: AircraftColliderPart, impulse: Float)
    case gearOverload(GearID, force: Float)
}
```

Suggested policy:

- gear contact while downlocked and within force/sink-rate limits: normal landing/rolling;
- tire/strut contact while extending or retracting: damage candidate, no normal support unless intentionally permitted;
- fuselage, wing, nose, tail, weapon, or door contact with runway: structural strike;
- structural contact above impulse/relative-speed threshold: crash;
- gear support above `maxSupportForce` or compression at the hard stop: gear damage/collapse;
- static scenery contacts use the same child-part roles, so a wingtip can hit a hangar without the fuselage sphere falsely declaring contact.

The solver should publish contact events after the fixed-step batch. Gameplay consumes those events on the update thread; it should not mutate the world from within narrow-phase/solver loops.

### 2.7 Connecting physics colliders to the F-22 skeleton

`F22AnimationConfig` already knows the landing-gear joint names and `AircraftAnimator` exposes progress/state. Reuse that information but resolve a dedicated collider binding once, similarly to the existing animation channel mappings.

`Skeleton.currentPose` cannot be used directly because pass 2 multiplies by inverse bind transforms for skinning. Preserve an engine-basis raw joint pose:

```diff
--- a/ToyFlightSimulator Shared/Animation/Skeleton.swift
+++ b/ToyFlightSimulator Shared/Animation/Skeleton.swift
@@
     var currentPose: [float4x4] = []
+    /// Joint model-space transforms in engine basis, before inverse bind.
+    /// Physics/attachments consume this; Skin continues to consume currentPose.
+    private(set) var jointModelPoses: [float4x4] = []
@@
     func evaluateWorldPoses() {
         let count = parentIndices.count
         if currentPose.count != count {
             currentPose = [float4x4](repeating: .identity, count: count)
+            jointModelPoses = [float4x4](repeating: .identity, count: count)
         }
@@
         if let basisTransform, let inverseBasisTransform {
             for index in 0..<count {
+                jointModelPoses[index] = inverseBasisTransform
+                    * currentPose[index]
+                    * basisTransform
                 currentPose[index] = inverseBasisTransform
                     * (currentPose[index] * inverseBindTransforms[index])
                     * basisTransform
             }
         } else {
             for index in 0..<count {
+                jointModelPoses[index] = currentPose[index]
                 currentPose[index] *= inverseBindTransforms[index]
             }
         }
     }
```

This illustrative diff preserves current skinning output. Add tests proving:

- rest-pose joint transforms match expected hierarchy composition;
- `currentPose` remains unchanged for existing skinning tests;
- basis conversion matches the project's `B⁻¹ * J * B` convention;
- collider world pose equals `worldFromBody * assetToBodyMeters * jointModelPose * jointFromCollider`;
- no render `Node` scale is accidentally applied twice.

For rigid pieces driven procedurally without skinning, a named `Node` attachment can be another pose provider. Resolve all strings to indices/weak references during aircraft construction; do not scan joint names during physics steps.

### 2.8 Control surfaces

Movable control surfaces normally should **not** be separate simulated bodies:

- Their hinge motion is commanded by flight controls.
- Their mass is small relative to the aircraft.
- The important flight effect is aerodynamic force and moment, not momentum exchanged through a collision joint.
- A fully physical hinge could flutter or be knocked away from the commanded angle unless a strong drive is solved, adding cost without improving ordinary flight.

Recommended treatment:

1. Keep visual aileron/flaperon/stabilator/rudder animation as it is.
2. If accurate ground/scenery strikes require it, attach small box/convex colliders to their animated joint poses. They remain part of the main aircraft body.
3. Upgrade `FlightModel` from only `computeForce` to force-and-torque contributions at aerodynamic centers. For each lifting surface, use local airflow and deflection, then call `addForce(force, atWorldPoint: centerOfPressure)`. This naturally creates pitch/roll/yaw torque.
4. Create a separate body plus hinge only for damage modes such as a surface partially detached, jammed, or broken off.

### 2.9 Suggested collider sets for future object types

| Object | Recommended dynamic representation | Articulation only if… |
| --- | --- | --- |
| Aircraft | One body; fuselage capsules/hulls, wing/tail boxes or convex hulls, gear units | gear/link loads, collapse, detachment, or shimmy are gameplay |
| Helicopter | One body; cabin hulls, tail-boom capsule, skids/gear contacts; rotor sweep/strike capsules | rotor blades must flap/lead-lag and exchange collision impulses individually |
| Car/truck | One chassis body with compound shapes; four wheel suspension queries | axle/independent suspension geometry and breakage must be solved |
| Control tower/hangar | Static compound boxes/convexes or static triangle mesh | door/elevator/crane parts move |
| Tree | Static trunk capsule + canopy sphere/hull | trunk must bend, break, or fall dynamically |
| Debris | One small body with sphere/box/capsule/convex hull | connected wreckage must remain breakable |
| Runway/terrain | Finite static box/mesh and later heightfield | never a dynamic concave mesh |

### 2.10 Fixed simulation phases and thread integration

Keep all physics on the existing update thread. Introduce explicit phases so input, animation, collision geometry, solver state, and render transforms have one unambiguous order:

```text
drain UI mailboxes
  -> sample controls / update commanded animation
  -> update raw joint poses
  -> sync animated collider local poses
  -> accumulate aerodynamic, engine, gear, and gravity forces
  -> run 0...N fixed physics substeps
  -> publish body poses to Nodes once
  -> traverse remaining scene updates
  -> write the existing frame-ring snapshot
```

A bounded fixed-step accumulator can live inside `PhysicsWorld`:

```swift
final class PhysicsWorld {
    private let fixedDelta: Float = 1.0 / 120.0
    private let maxSubsteps = 8
    private var accumulator: Float = 0

    func update(frameDelta: Float) {
        accumulator += min(frameDelta, 0.1)
        var steps = 0

        while accumulator >= fixedDelta && steps < maxSubsteps {
            step(deltaTime: fixedDelta)
            accumulator -= fixedDelta
            steps += 1
        }

        if steps == maxSubsteps {
            // Prevent a permanent spiral of death after a breakpoint/stall.
            accumulator = min(accumulator, fixedDelta)
        }

        publishBodyPosesToGameObjects()
    }
}
```

For continuous forces, either recompute at each substep from immutable sampled control input or hold a force value for all substeps in the rendered frame. Recomputing aerodynamic force from the current substep state is more accurate. Clear force/torque after each fixed step, not once after an arbitrary display frame.

The existing update/render semaphores and triple-buffered `ModelConstants` are already the right publication boundary. Physics does not require a Metal compute kernel. At the current scale, a CPU solver avoids GPU readback, divergent kernels, and complicated synchronization. Metal should consume the resulting transforms, just as it does now.

Metal is useful for **debug visualization**:

- create a ring-buffered `ColliderDebugInstance` with `modelMatrix`, shape type, dimensions, and color;
- color fixed structural colliders cyan, gear green/yellow, disabled red/transparent, and active contacts magenta;
- render wireframe spheres/boxes/capsules using instancing or lines;
- render contact normals and force vectors;
- toggle it with an existing debug shortcut/HUD path.

If debug instance data is written by the update thread and read by the renderer, use the same frame index and ring discipline already used for model constants. Apple's [CPU/GPU synchronization sample](https://developer.apple.com/documentation/metal/synchronizing-cpu-and-gpu-work) describes this multi-buffer pattern.

### 2.11 Illustrative first patches

These are design diffs, not a single ready-to-apply patch. The work should be split into tested commits.

#### A. Separate shape from body

```diff
--- a/ToyFlightSimulator Shared/Physics/World/PhysicsEntity.swift
+++ b/ToyFlightSimulator Shared/Physics/World/PhysicsEntity.swift
@@
-enum CollisionShape {
-    case Sphere
-    case Plane
-}
+enum ColliderGeometry: Sendable {
+    case sphere(radius: Float)
+    case box(halfExtents: float3)
+    case capsule(radius: Float, halfHeight: Float, axis: CapsuleAxis)
+    case plane(normal: float3, offset: Float)
+}
@@
-    var collisionShape: CollisionShape { get set }
-    var collidedWith: Set<ObjectIdentifier> { get set }
+    var colliders: ContiguousArray<Collider> { get set }
```

```diff
--- a/ToyFlightSimulator Shared/Physics/World/RigidBody.swift
+++ b/ToyFlightSimulator Shared/Physics/World/RigidBody.swift
@@
-    var collisionShape: CollisionShape
-    var collidedWith: Set<ObjectIdentifier>
+    var colliders = ContiguousArray<Collider>()
+    var orientation = simd_quatf(angle: 0, axis: float3(0, 1, 0))
+    var angularVelocity: float3 = .zero
+    var torque: float3 = .zero
+    var centerOfMassLocal: float3 = .zero
+    var inverseInertiaLocal = matrix_identity_float3x3
```

Compatibility factory:

```swift
extension RigidBody {
    static func sphere(gameObject: GameObject, radius: Float) -> RigidBody {
        let body = RigidBody(gameObject: gameObject)
        body.colliders.append(Collider(
            id: 0,
            geometry: .sphere(radius: radius),
            bodyFromCollider: PhysicsPose(),
            material: PhysicsMaterial(),
            role: .structure(.fuselage)
        ))
        return body
    }
}
```

For non-aircraft objects, replace the aircraft-specific role with a generic `ColliderTag`/`UInt32 userData`; the example shows why stable leaf metadata matters.

#### B. Generate contacts per collider pair

```diff
--- a/ToyFlightSimulator Shared/Physics/World/PhysicsWorld.swift
+++ b/ToyFlightSimulator Shared/Physics/World/PhysicsWorld.swift
@@
-    static func collided(entityA: RigidBody, entityB: RigidBody) -> Bool
-    static func getCollisionData(_ entityA: RigidBody,
-                                 _ entityB: RigidBody) -> CollisionData
+    private var manifoldsScratch = ContiguousArray<ContactManifold>()
+
+    private func generateContacts(for bodyPairs: [(RigidBody, RigidBody)]) {
+        manifoldsScratch.removeAll(keepingCapacity: true)
+        for (bodyA, bodyB) in bodyPairs {
+            NarrowPhase.generateContacts(bodyA: bodyA,
+                                         bodyB: bodyB,
+                                         into: &manifoldsScratch)
+        }
+    }
@@
-    HeckerCollisionResponse.resolveCollisions(...)
+    generateContacts(for: potentialPairs)
+    SequentialImpulseSolver.solve(manifolds: &manifoldsScratch,
+                                  deltaTime: deltaTime,
+                                  velocityIterations: 8,
+                                  positionIterations: 3)
```

Keep the current solver behind a comparison flag until the new sphere/plane tests match existing behavior.

#### C. Build one compound F-22 body

Illustrative dimensions must be calibrated in the collider debug view against the actual asset; they are intentionally not asserted as final F-22 measurements:

```swift
func makeF22PhysicsBody(for aircraft: F22_CGTrader) -> RigidBody {
    let body = RigidBody(gameObject: aircraft)
    body.mass = aircraft.flightModel?.mass ?? 30_000
    body.restitution = 0.05
    body.shouldApplyGravity = true

    body.colliders.append(Collider(
        id: 0,
        geometry: .capsule(radius: 1.05, halfHeight: 6.5, axis: .z),
        bodyFromCollider: PhysicsPose(position: [0, 0.1, 0.4]),
        material: PhysicsMaterial(),
        role: .structure(.fuselage)
    ))
    body.colliders.append(Collider(
        id: 1,
        geometry: .box(halfExtents: [3.3, 0.18, 2.1]),
        bodyFromCollider: PhysicsPose(position: [-3.2, 0, 0.2]),
        material: PhysicsMaterial(),
        role: .structure(.leftWing)
    ))
    body.colliders.append(Collider(
        id: 2,
        geometry: .box(halfExtents: [3.3, 0.18, 2.1]),
        bodyFromCollider: PhysicsPose(position: [3.2, 0, 0.2]),
        material: PhysicsMaterial(),
        role: .structure(.rightWing)
    ))

    // Add nose/tail/vertical-tail shapes after calibration. Gear support is
    // represented by LandingGearRuntime entries, not additional RigidBodies.
    return body
}
```

```diff
--- a/ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift
+++ b/ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift
@@
-    let acRigidBody = SphereRigidBody(gameObject: playerAircraft)
-    acRigidBody.collisionRadius = 2.0
-    acRigidBody.restitution = 0.2
+    let acRigidBody: RigidBody
+    if let f22 = playerAircraft as? F22_CGTrader {
+        acRigidBody = makeF22PhysicsBody(for: f22)
+    } else {
+        acRigidBody = RigidBody.sphere(gameObject: playerAircraft,
+                                       radius: 2.0)
+    }
```

#### D. Introduce update phases

```swift
protocol PhysicsParticipant: AnyObject {
    func preparePhysics(frameDelta: Float)
    func accumulateForces(substepDelta: Float)
    func didSimulatePhysics()
}
```

`Aircraft.preparePhysics` samples controls, advances commanded animation, and syncs gear/collider bindings. `accumulateForces` calculates the flight model and gear forces from current body state. `didSimulatePhysics` publishes derived animation state such as strut compression. This avoids relying on parent/child traversal order.

### 2.12 Recommended implementation roadmap

#### Phase 0 — measurements, debug view, and contracts

- Establish meters/kilograms/seconds/radians as physics units.
- Add per-aircraft `assetToBodyMeters`, mass, COM, and inertia configuration.
- Add collider/contact debug rendering before collision behavior changes.
- Add deterministic physics-only test bodies that do not load Metal assets.

Exit criterion: authored shapes visibly align with the F-22 at rest, gear up, gear down, and midway through deployment.

#### Phase 1 — compound translation-only compatibility

- Introduce `ColliderGeometry`, `Collider`, filtering, roles, and compound AABB.
- Port sphere and plane behavior without angular response.
- Add analytic box/capsule AABBs and plane contacts.
- Replace body subclass dispatch with geometry dispatch.
- Keep old solver behind a test/comparison switch.

Exit criterion: existing falling-sphere tests pass; cube/capsule scene objects use their real primitive; an aircraft body/wing collider reports the correct part against the plane.

#### Phase 2 — 6-DOF rigid bodies and contact manifolds

- Make quaternion pose, angular velocity, torque, COM, and inertia canonical.
- Add force at point and point velocity.
- Implement iterative normal/friction impulses and position correction.
- Remove gravity-disable and minimum-delta-velocity hacks.
- Add fixed timestep/substeps and sleep only after contacts are stable.

Exit criterion: an off-center sphere/box impact spins a body; a box rests on multiple points without turning gravity off; 30/60/120 Hz rendering produces nearly identical physics trajectories.

#### Phase 3 — F-22 ground model

- Preserve raw joint model poses and resolve gear joint bindings.
- Add three gear suspension units, flat-plane sphere casts, friction, and weight-on-wheels.
- Feed compression back to visual strut/wheel transforms.
- Add structural strike/crash events and gear overload.
- Tune at several landing weights, vertical speeds, bank angles, and yaw/slip values.

Exit criterion: downlocked wheels support the aircraft at their actual locations; retracted gear does not; nose/main gear load distribution pitches the body correctly; wing/belly/tail strikes are separately detected.

#### Phase 4 — general world collision

- Add finite runway/static box and convex/triangle-mesh queries.
- Add OBB-vs-OBB and capsule pairs.
- Add static BVH or retain separate static broad-phase data.
- Add sphere/capsule casts against terrain and scenery.
- Add CCD for missiles and high-speed small debris.

#### Phase 5 — joints/articulations only where justified

- Implement a common constraint-row solver shared by contacts and joints.
- Start with fixed, revolute, and prismatic joints with limits.
- Add PD drives, break thresholds, and connected-body collision filtering.
- Prototype one gear leg before converting the whole aircraft.

### 2.13 Tests and validation matrix

#### Geometry tests

- world AABB for rotated/translated box and capsule;
- compound AABB union, disabled child omission, and empty body fallback;
- sphere/plane at a translated and tilted plane;
- box/plane with one, two, and four contact points;
- collider filtering and same-body non-collision;
- exact child IDs/roles in contacts.

#### Dynamics tests

- force at COM creates no torque;
- equal force away from COM creates expected angular acceleration;
- equal/opposite impulses conserve linear and angular momentum within tolerance;
- friction never exceeds `μ * normalImpulse`;
- resting body retains gravity and is supported by contact impulses;
- fixed-step result is invariant to render delta partitioning;
- high-speed sphere sweep prevents tunneling through a thin runway.

#### Landing-gear tests

- gear up: no support contact;
- gear transitioning: damage collision optional, support disabled;
- gear downlocked: correct static compression and weight-on-wheels;
- asymmetric main-gear contact creates roll moment;
- nose-gear-only contact creates pitch moment;
- hard-stop compression and overload event;
- longitudinal braking and lateral friction caps;
- skeleton pose binding at gear-up/down/mid-animation;
- visual compression does not feed back twice into physics pose.

#### Scenario tests

- level three-point landing;
- one-main-wheel-first crosswind landing;
- nose-first landing;
- gear-up belly landing;
- wingtip and tail strike;
- runway edge/curb once finite geometry exists;
- runtime aircraft swap and scene reset leave no bodies/colliders registered;
- renderer switching does not affect physics results.

### 2.14 Build it in Swift or integrate a physics library?

There are two defensible choices.

#### Continue the custom Swift engine

This is appropriate if physics-engine construction is part of the project's purpose and the scope is deliberately staged. Compound spheres/boxes/capsules, 6-DOF integration, iterative contacts, and a JSBSim-style gear model are achievable without immediately implementing a general articulation engine.

The risk is scope. Robust convex contacts, persistent manifolds, friction, stacking, CCD, sleeping, joints, vehicles, and triangle meshes form a mature physics engine, not a small extension to `BasicRigidBodies.swift`.

#### Integrate Jolt behind a Swift-facing adapter

Jolt already provides the relevant primitives, mutable/static compounds, convex hulls, meshes/heightfields, sub-shape IDs, constraints, vehicle suspension, CCD, multithreading, and mass/COM handling. Its official repository lists macOS x64/ARM64 and iOS x64/ARM64 support. Swift can call C++ directly with C++ interoperability, though a narrow C or Objective-C++ facade often gives a more stable boundary for handles and arrays. Sources: [Jolt repository](https://github.com/jrouwe/JoltPhysics) and [Swift/C++ interoperability](https://www.swift.org/documentation/cxx-interop/).

A backend boundary could be small:

```swift
protocol PhysicsBackend: AnyObject {
    func createBody(_ definition: BodyDefinition) -> PhysicsBodyHandle
    func destroyBody(_ handle: PhysicsBodyHandle)
    func setAnimatedColliderPose(body: PhysicsBodyHandle,
                                 collider: ColliderHandle,
                                 bodyFromCollider: PhysicsPose)
    func addForce(body: PhysicsBodyHandle,
                  force: float3,
                  atWorldPoint: float3)
    func step(deltaTime: Float)
    func pose(of body: PhysicsBodyHandle) -> PhysicsPose
    func drainContactEvents(into events: inout [PhysicsContactEvent])
}
```

The rest of the proposal—aircraft collider authoring, bone bindings, landing-gear state, update-thread ownership, contact roles, crash policy, and Metal debug rendering—still applies with Jolt. Only the collision/dynamics implementation changes.

**Recommendation:** implement Phase 0 and the aircraft/gear authoring layer independently of the backend. In parallel, make a small Jolt spike with one compound body and three suspension queries before committing to building Phase 2–5 from scratch. If the goal is shipping sophisticated aircraft, helicopters, cars, and structures sooner, Jolt is the lower-risk core. If the goal includes learning and owning the solver, keep the Swift path but stop at the fidelity actually needed before adding general articulations.

## 3. References

All sources opened or substantively consulted for this research are listed below. Accessed 2026-07-14.

### User-provided starting points

1. Unity, `Rigidbody` scripting API: https://docs.unity3d.com/ScriptReference/Rigidbody.html
2. Unity, Wheel Collider component reference: https://docs.unity3d.com/Manual/class-WheelCollider.html
3. Alex Jamerson, “How I Rigged Aircraft Landing Gear in 3D Software”: https://www.alexjamerson.com/blog-1/2021/9/11/how-i-rigged-aircraft-landing-gear-in-3d-software

### Unity / PhysX

4. Unity, Introduction to collision: https://docs.unity3d.com/Manual/CollidersOverview.html
5. Unity, Introduction to collider types: https://docs.unity3d.com/Manual/collider-types-introduction.html
6. Unity, Primitive collider shapes: https://docs.unity3d.com/Manual/primitive-colliders.html
7. Unity, Mesh colliders: https://docs.unity3d.com/Manual/mesh-colliders.html
8. Unity, Mesh Collider component reference: https://docs.unity3d.com/Manual/class-MeshCollider.html
9. Unity, Create a compound collider: https://docs.unity3d.com/Manual/create-compound-collider.html
10. Unity, Introduction to compound colliders: https://docs.unity3d.com/Manual/compound-colliders-introduction.html
11. Unity, Wheel colliders: https://docs.unity3d.com/Manual/wheel-colliders.html
12. Unity, Introduction to Wheel colliders: https://docs.unity3d.com/Manual/wheel-colliders-introduction.html
13. Unity, Wheel collider suspension: https://docs.unity3d.com/Manual/wheel-colliders-suspension.html
14. Unity, Wheel collider friction: https://docs.unity3d.com/Manual/wheel-colliders-friction.html
15. Unity, Continuous collision detection: https://docs.unity3d.com/Manual/ContinuousCollisionDetection.html
16. Unity, `ArticulationBody` scripting API: https://docs.unity3d.com/ScriptReference/ArticulationBody.html
17. NVIDIA PhysX, API basics: https://nvidia-omniverse.github.io/PhysX/physx/5.4.1/docs/API.html
18. NVIDIA PhysX, Geometry: https://nvidia-omniverse.github.io/PhysX/physx/5.1.3/docs/Geometry.html
19. NVIDIA PhysX, Geometry queries: https://nvidia-omniverse.github.io/PhysX/physx/5.4.1/docs/GeometryQueries.html
20. NVIDIA PhysX, Scene queries: https://nvidia-omniverse.github.io/PhysX/physx/5.4.1/docs/SceneQueries.html
21. NVIDIA PhysX, `PxShape`: https://nvidia-omniverse.github.io/PhysX/physx/5.4.0/_api_build/class_px_shape.html
22. NVIDIA PhysX, Rigid Body Dynamics: https://nvidia-omniverse.github.io/PhysX/physx/5.4.0/docs/RigidBodyDynamics.html
23. NVIDIA PhysX, Joints: https://nvidia-omniverse.github.io/PhysX/physx/5.4.0/docs/Joints.html
24. NVIDIA PhysX, Articulations: https://nvidia-omniverse.github.io/PhysX/physx/5.6.0/docs/Articulations.html
25. NVIDIA PhysX, Simulation/island management: https://nvidia-omniverse.github.io/PhysX/physx/5.4.1/docs/Simulation.html
26. NVIDIA PhysX, Best Practices: https://nvidia-omniverse.github.io/PhysX/physx/5.4.1/docs/BestPractices.html
27. NVIDIA PhysX, 1D Constraint Formulation: https://nvidia-omniverse.github.io/PhysX/physx/5.4.0/_downloads/f27bad5e4b631dc274a41ecf77568a49/constraintFormulation.pdf

### Other engines and physics libraries

28. Unreal Engine, Simple versus Complex Collision: https://dev.epicgames.com/documentation/unreal-engine/simple-versus-complex-collision-in-unreal-engine?lang=en-US
29. Unreal Engine, Physics Bodies Reference: https://dev.epicgames.com/documentation/unreal-engine/physics-bodies-reference-for-unreal-engine?lang=en-US
30. Unreal Engine, Physics Asset Editor Interface: https://dev.epicgames.com/documentation/unreal-engine/physics-asset-editor-interface-in-unreal-engine?lang=en-US
31. Unreal Engine, Physics Constraints: https://dev.epicgames.com/documentation/en-us/unreal-engine/physics-constraints-in-unreal-engine
32. Unreal Engine, Physics Constraint Reference: https://dev.epicgames.com/documentation/en-us/unreal-engine/physics-constraint-reference-in-unreal-engine
33. Unreal Engine, Add Simple Collision to a Static Mesh: https://dev.epicgames.com/documentation/en-us/unreal-engine/add-simple-collision-to-a-static-mesh-in-unreal-engine
34. Unreal Engine, Set up vehicles: https://dev.epicgames.com/documentation/en-us/unreal-engine/how-to-set-up-vehicles-in-unreal-engine
35. Godot, Physics introduction: https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html
36. Godot, `RigidBody3D`: https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html
37. Jolt Physics, architecture/API overview: https://jrouwe.github.io/JoltPhysics/
38. Jolt Physics, `VehicleConstraint`: https://jrouwe.github.io/JoltPhysics/class_vehicle_constraint.html
39. Jolt Physics repository: https://github.com/jrouwe/JoltPhysics
40. Box2D overview: https://box2d.org/documentation/
41. Box2D collision: https://box2d.org/documentation/md_collision.html
42. Box2D simulation: https://box2d.org/documentation/md_simulation.html
43. Box2D joints: https://box2d.org/documentation/group__joint.html
44. Erin Catto, “Iterative Dynamics with Temporal Coherence”: https://box2d.org/files/ErinCatto_IterativeDynamicsSlides_GDC2005.pdf
45. Erin Catto, “Contact Manifolds”: https://box2d.org/files/ErinCatto_ContactManifolds_GDC2007.pdf
46. Bullet Physics Quickstart: https://raw.githubusercontent.com/bulletphysics/bullet3/master/docs/BulletQuickstart.pdf

### Aircraft ground reaction and Apple integration

47. JSBSim, `FGLGear` landing gear model: https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGLGear.html
48. JSBSim, `FGGroundReactions`: https://jsbsim-team.github.io/jsbsim/python/FGGroundReactions.html
49. JSBSim source repository: https://github.com/JSBSim-Team/jsbsim
50. JSBSim `FGLGear.h` source: https://jsbsim-team.github.io/jsbsim/FGLGear_8h_source.html
51. Apple, Synchronizing CPU and GPU work: https://developer.apple.com/documentation/metal/synchronizing-cpu-and-gpu-work
52. Swift.org, Mixing Swift and C++: https://www.swift.org/documentation/cxx-interop/
