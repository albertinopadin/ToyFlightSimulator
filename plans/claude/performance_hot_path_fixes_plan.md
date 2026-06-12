# Plan: Hot-Path Performance Fixes (from 2026-06-12 audit)

**Status:** AWAITING REVIEW — no code has been changed yet.
**Source:** `debugging/claude/performance_audit_unnecessary_copies.md`
**Baseline commit:** `b4a1d6e`

Scope decisions from review of the audit:

| Finding | Decision |
|---------|----------|
| P1 | Euler solver consumes broad-phase collision pairs |
| P2 | `ObjectIdentifier` identity (chosen over Int — see rationale) |
| P3 | Full broad-phase fix (all sub-items) |
| P4 | Remove unnecessary `pow()`/`sqrt()` |
| P5 | Covered by P3/P4 (no separate work) |
| P6 | Concrete `[RigidBody]` storage + future-proofing comment |
| P7 | Covered by P3/P6 (index map deleted) |
| P8 | Merge VerletSolver's zero-acceleration pass |
| R1 | `ContiguousArray` type change (least-change option) |
| R2 | Per-frame caching of transformed uniforms (suggestion 2, which subsumes suggestion 1) |
| R3, R4 | Ignored for now |
| R5 | `PointLightCount` accessor only |
| N1 | Cached world matrix + generation counter |
| N2 | Lazy local-matrix rebuild |
| N3 | **Proposal only** — diff included, flagged for explicit approval |
| N4 | Add `getRotationEulers()` |
| A1 | Fix all (cached inverses + in-place world poses) |
| A2, A3 | Joint indices resolved at channel registration (plus a per-frame allocation found in `Animation.swift` during planning — see A3+) |

The work is organized into 4 phases, each independently buildable and testable.

---

## Design decisions made up front

**P2 — why `ObjectIdentifier` over `Int`:** both hash a single 64-bit word (equivalent lookup cost), but `ObjectIdentifier(self)` needs **no stored property, no init-time work, and no atomic global counter** — it's just the object's address, valid for the entity's lifetime, which is exactly the lifetime the physics structures need (`collidedWith` is reset every frame; the broad-phase no longer tracks identity across frames after P3). This also lets us delete `RigidBody.id` (a `UUID().uuidString` per init) entirely. Verified: nothing outside the physics module reads `.id` on rigid bodies (only debug prints, updated below), and no test references it.

**P3 — the incremental-sort machinery is deleted, not optimized.** `shouldPerformFullSort` already pays O(n) `getPosition()` + dictionary lookups *just to decide* whether to sort; `performInsertionSort` builds two `Set<String>`s and worst-cases O(n²) `getAABB()` calls. After P3, AABBs are computed **once per entity per frame** into a flat array and we sort an index array by a cached `Float` key — for the 100–1000-entity range this engine targets, that sort is microseconds and strictly cheaper than the bookkeeping that tried to avoid it. `lastFramePositions`, `resortThreshold`, `isFirstFrame`, and both sort paths are removed.

**P6 — protocol kept, storage concrete.** `PhysicsEntity` remains as the documented contract (now `AnyObject`-constrained, so the helpers stop being `mutating`), but every hot-path signature and the world's storage becomes `[RigidBody]`. A comment at the storage site records the decision and what to do if a non-RigidBody entity type ever appears.

**R2 cache-key safety:** the cache key is `ObjectIdentifier(mesh)` **plus the source region offset and absolute frame number**. The offset guard makes the cache correct even if a `Mesh` instance were ever shared between two models (it isn't today — `SingleSubmeshMesh` creates fresh instances — but the guard is one `Int` compare). The absolute frame number (not the ring slot index) prevents false hits when a slot index recycles 3 frames later. Note the render/update handshake (`updateDoneSemaphore`) means the update thread is *not* mutating `currentTransform` while we encode, so reading it once per frame is safe — and more self-consistent than today's per-pass reads.

**N1/N2 — camera coupling is the real risk, handled by restructuring `Camera`.** Today `Camera`/`AttachedCamera`/`DebugCamera` override `updateModelMatrix()` to eagerly derive `viewMatrix`. With a lazy local rebuild those overrides would either go stale or recurse (they read `modelMatrix` inside the rebuild hook). The fix: Node gets a monotonically increasing `worldMatrixGeneration`; `Camera.viewMatrix` becomes a lazy getter that re-derives from the world matrix only when the generation changed, with a single `computeViewMatrix(from:)` override point (plain inverse for base/Debug, `scaleStrippedInverse` for Attached). All three `updateModelMatrix()` overrides and `AttachedCamera`'s `worldMatrixDirty` hook are deleted. `AttachedCameraTests` only exercises the static `scaleStrippedInverse` — unaffected.

**Threading note for N1/N2 lazy getters:** `modelMatrix`/`viewMatrix` getters now mutate caches. All current callers run on the update thread (scene update, physics, cascade fitting, click handling); the render thread only reads `modelConstants` (stored) and ring-buffer data. This matches the existing threading contract. Called out so it's a conscious invariant: **don't call `modelMatrix` from the render thread.**

**Latent bug noted, intentionally NOT fixed here (behavior parity):** `VerletSolver` zeroes acceleration *before* reading it, so the `0.5·a·dt²` / `0.5·a·dt` history terms are always zero — it's not true velocity Verlet. P8 merges the pass while **preserving** that behavior (trajectories must not change in a perf PR). A follow-up comment marks it.

---

## Phase 1 — Physics (P1, P2, P3, P4, P6, P7, P8)

Files touched:
- `Physics/World/PhysicsEntity.swift`
- `Physics/World/RigidBody.swift`
- `Physics/World/PhysicsWorld.swift`
- `Physics/Solver/PhysicsSolver.swift`
- `Physics/Solver/EulerSolver.swift`
- `Physics/Solver/VerletSolver.swift`
- `Physics/CollisionResponse/HeckerCollisionResponse.swift`
- `Physics/BroadPhase/BroadPhaseCollisionDetector.swift`
- `Scenes/FlightboxWithPhysics.swift`, `Scenes/FreeCamFlightboxScene.swift`, `Scenes/BallPhysicsScene.swift`, `Scenes/PhysicsStressTestScene.swift`
- `ToyFlightSimulatorTests/Physics/PhysicsSolverTests.swift`

### 1.1 `PhysicsEntity.swift` — ObjectIdentifier identity, AnyObject constraint (P2, P6)

```diff
-protocol PhysicsEntity {
-    var id: String { get }
+/// Contract for anything that participates in the physics simulation.
+/// AnyObject-constrained: entities are reference types, so solvers mutate
+/// them through the reference (no inout/existential writeback needed).
+protocol PhysicsEntity: AnyObject {
     var collisionShape: CollisionShape { get set }
-    var collidedWith: [String : Bool] { get set }
+    /// Identities of entities already collided with this step.
+    /// ObjectIdentifier == the entity's address: free to obtain, hashes as a
+    /// single word, valid for the entity's lifetime (reset every step anyway).
+    var collidedWith: Set<ObjectIdentifier> { get set }
 
     var mass: Float { get set }
     var velocity: float3 { get set }
     var acceleration: float3 { get set }
     var force: float3 { get set }
     var restitution: Float { get set }
     var isStatic: Bool { get set }
     var shouldApplyGravity: Bool { get set }  // Hack...
 
     func setPosition(_ position: float3)
     func getPosition() -> float3
 
     // Broad-phase collision detection support
     func getAABB() -> AABB
 }
 
-extension PhysicsEntity {    
-    static func ==(lhs: Self, rhs: Self) -> Bool {
-        return lhs.id == rhs.id
-    }
-    
-    mutating func resetCollisions() {
+extension PhysicsEntity {
+    func resetCollisions() {
         collidedWith.removeAll(keepingCapacity: true)
     }
-    
-    mutating func zeroForce() {
+
+    func zeroForce() {
         force = .zero
     }
-    
+
     // Computed property for dynamic check (inverse of static)
     var isDynamic: Bool {
         return !isStatic
     }
 }
```

(The `==` extension is deleted — it was never usable on heterogeneous existentials; identity is now object identity.)

### 1.2 `RigidBody.swift` — drop String id, Set-based collidedWith, optional gameObject (P2, P6)

The `gameObject` parameter becomes optional so the test target can build a lightweight `RigidBody` double without dragging in Metal/model loading (see §1.10). Behavior for all existing callers is unchanged (they all pass a non-nil GameObject).

```diff
-    let id: String
     var collisionShape: CollisionShape
-    var collidedWith: [String : Bool]
+    var collidedWith: Set<ObjectIdentifier>
     var mass: Float
     var velocity: float3
     var acceleration: float3
     var force: float3
     var restitution: Float
     var isStatic: Bool
     var shouldApplyGravity: Bool
     
     // GameObject this is attached to:
     weak let gameObject: GameObject?
     
-    internal init(gameObject: GameObject,
+    internal init(gameObject: GameObject?,
                   collisionShape: CollisionShape = .Sphere,
-                  collidedWith: [String : Bool] = [:],
+                  collidedWith: Set<ObjectIdentifier> = [],
                   mass: Float = 1,
                   velocity: float3 = .zero,
                   acceleration: float3 = .zero,
                   force: float3 = .zero,
                   restitution: Float = 1,
                   isStatic: Bool = false,
                   shouldApplyGravity: Bool = true) {
-        self.id = UUID().uuidString
         self.gameObject = gameObject
         self.collisionShape = collisionShape
         self.collidedWith = collidedWith
         ...
-        // Register with object this is attached to:
-        gameObject.rigidBody = self
+        // Register with object this is attached to:
+        gameObject?.rigidBody = self
     }
```

`import Foundation` can stay (Foundation no longer needed for UUID, but `weak let` etc. are fine either way — drop the import only if nothing else needs it; will verify at implementation time).

### 1.3 `PhysicsWorld.swift` — concrete storage, pairs into Euler, sqrt/pow fixes (P1, P4, P6)

```diff
 final class PhysicsWorld {
     public static let gravity: float3 = [0, -9.81, 0]
     
-    private var entities: [PhysicsEntity]
+    // NOTE(P6): storage is the concrete class `RigidBody`, not `any PhysicsEntity`.
+    // RigidBody is currently the only conformer; concrete storage gives direct
+    // class dispatch in the solver loops instead of protocol-witness dispatch.
+    // If a second, non-RigidBody PhysicsEntity type is ever added, either give
+    // it a RigidBody base or revisit these signatures (PhysicsWorld, the
+    // solvers, HeckerCollisionResponse, BroadPhaseCollisionDetector).
+    private var entities: [RigidBody]
     private var updateType: PhysicsUpdateType
     private var broadPhase = BroadPhaseCollisionDetector()
     
     // Performance testing flags
     public var useBroadPhase: Bool = true
+    /// Forwarded to the broad phase; when false (default) the per-frame
+    /// CFAbsoluteTimeGetCurrent() calls and stat bookkeeping are skipped.
+    public var collectBroadPhaseStatistics: Bool {
+        get { broadPhase.collectStatistics }
+        set { broadPhase.collectStatistics = newValue }
+    }
     
-    init(entities: [PhysicsEntity] = [], updateType: PhysicsUpdateType = .NaiveEuler) {
+    init(entities: [RigidBody] = [], updateType: PhysicsUpdateType = .NaiveEuler) {
         self.entities = entities
         self.updateType = updateType
     }
     
-    public func setEntities(_ entities: [PhysicsEntity]) {
+    public func setEntities(_ entities: [RigidBody]) {
         self.entities = entities
     }
     
-    public func addEntity(_ entity: PhysicsEntity) {
+    public func addEntity(_ entity: RigidBody) {
         entities.append(entity)
     }
     
-    public func addEntities(_ entities: [PhysicsEntity]) {
+    public func addEntities(_ entities: [RigidBody]) {
         self.entities += entities
     }
     
     public func update(deltaTime: Float) {
-        for i in entities.indices {
-            entities[i].resetCollisions()
+        for entity in entities {
+            entity.resetCollisions()
         }
         
         if useBroadPhase {
             // Use optimized broad-phase collision detection
             broadPhase.update(entities: entities)
             let potentialPairs = broadPhase.getPotentialCollisionPairs()
             
             switch self.updateType {
                 case .NaiveEuler:
                     naiveUpdate(deltaTime: deltaTime, collisionPairs: potentialPairs)
                     
                 case .HeckerVerlet:
                     heckerVerletUpdate(deltaTime: deltaTime, collisionPairs: potentialPairs)
             }
         } else {
             ...unchanged...
         }
     }
     
-    // Optimized update methods using broad-phase pairs
-    private func naiveUpdate(deltaTime: Float, collisionPairs: [(PhysicsEntity, PhysicsEntity)]) {
-        // For now, naive update doesn't handle collisions, but we pass pairs for future use
-        EulerSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: &self.entities)
-    }
+    // Optimized update methods using broad-phase pairs
+    private func naiveUpdate(deltaTime: Float, collisionPairs: [(RigidBody, RigidBody)]) {
+        // P1: the Euler path now resolves collisions against the broad-phase
+        // pairs instead of its own O(n²) sweep.
+        EulerSolver.step(deltaTime: deltaTime,
+                         gravity: PhysicsWorld.gravity,
+                         entities: entities,
+                         collisionPairs: collisionPairs)
+    }
     
-    private func heckerVerletUpdate(deltaTime: Float, collisionPairs: [(PhysicsEntity, PhysicsEntity)]) {
-        HeckerCollisionResponse.resolveCollisions(deltaTime: deltaTime, entities: &entities, collisionPairs: collisionPairs)
-        VerletSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: &entities)
+    private func heckerVerletUpdate(deltaTime: Float, collisionPairs: [(RigidBody, RigidBody)]) {
+        HeckerCollisionResponse.resolveCollisions(deltaTime: deltaTime, collisionPairs: collisionPairs)
+        VerletSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: entities)
     }
     
     // Original O(n²) update methods for comparison
     private func naiveUpdateOriginal(deltaTime: Float) {
-        EulerSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: &self.entities)
+        EulerSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: entities)
     }
     
     private func heckerVerletUpdateOriginal(deltaTime: Float) {
-        HeckerCollisionResponse.resolveCollisions(deltaTime: deltaTime, entities: &entities)
-        VerletSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: &entities)
+        HeckerCollisionResponse.resolveCollisions(deltaTime: deltaTime, entities: entities)
+        VerletSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: entities)
     }
```

Distance / collision math (P4):

```diff
     static func getDistance(_ pointA: float3, _ pointB: float3) -> Float {
-        let dx = pointA.x - pointB.x
-        let dy = pointA.y - pointB.y
-        let dz = pointA.z - pointB.z
-        return sqrt((pow(dx, 2) + pow(dy, 2) + pow(dz, 2)))
+        return simd_distance(pointA, pointB)
     }
     
-    static func getCollisionData(_ entityA: PhysicsEntity, _ entityB: PhysicsEntity) -> CollisionData {
+    static func getCollisionData(_ entityA: RigidBody, _ entityB: RigidBody) -> CollisionData {
         switch (entityA.collisionShape, entityB.collisionShape) {
             case (.Sphere, .Sphere):
-                let unormCV = Self.getUnnormalizedCollisionVector(entityA.getPosition(), entityB.getPosition())
-                let penetrationDepth = Self.getPenetrationDepth(ballA: entityA as! SphereRigidBody,
-                                                                ballB: entityB as! SphereRigidBody,
-                                                                unnormalizedCollisionVector: unormCV)
-                return CollisionData(collisionVector: unormCV.normalize(), penetrationDepth: penetrationDepth)
+                // One sqrt total (was: sqrt in normalize() + sqrt in magnitude + 3 pow()s).
+                let ballA = entityA as! SphereRigidBody
+                let ballB = entityB as! SphereRigidBody
+                let delta = ballA.getPosition() - ballB.getPosition()
+                let distance = simd_length(delta)
+                let normal: float3 = distance > 0 ? delta / distance : .zero
+                return CollisionData(collisionVector: normal,
+                                     penetrationDepth: ballA.collisionRadius + ballB.collisionRadius - distance)
             ...other cases unchanged except parameter types...
     }
     
-    static private func getUnnormalizedCollisionVector(_ pointA: float3, _ pointB: float3) -> float3 {
-        let dx = pointA.x - pointB.x
-        ...
-    }
+    // getUnnormalizedCollisionVector deleted — folded into getCollisionData above.
     
     static public func getPenetrationDepth(ballA: SphereRigidBody,
                                            ballB: SphereRigidBody,
                                            unnormalizedCollisionVector: float3) -> Float {
         return ballA.collisionRadius + ballB.collisionRadius - unnormalizedCollisionVector.magnitude
     }
     // ^ kept for API compatibility, but no longer called on the hot path.
     
-    static func collided(entityA: PhysicsEntity, entityB: PhysicsEntity) -> Bool {
+    static func collided(entityA: RigidBody, entityB: RigidBody) -> Bool {
         ...body unchanged (the as! casts now downcast from RigidBody)...
     }
     
     static func collided(sphereA: SphereRigidBody, sphereB: SphereRigidBody) -> Bool {
-        return Self.getDistance(sphereA.getPosition(), sphereB.getPosition()) <=
-                                (sphereA.collisionRadius + sphereB.collisionRadius)
+        // Squared-distance compare: no sqrt at all on the narrow-phase reject path.
+        let radiusSum = sphereA.collisionRadius + sphereB.collisionRadius
+        return simd_distance_squared(sphereA.getPosition(), sphereB.getPosition()) <= radiusSum * radiusSum
     }
```

`collided(sphere:plane:)` and `collided(planeA:planeB:)` keep their logic, parameter types only.

### 1.4 `PhysicsSolver.swift` — concrete types, no inout (P6)

With class semantics, `inout` was never doing anything for element mutation; dropping it removes the `&` noise:

```diff
 protocol PhysicsSolver {
-    static func step(deltaTime: Float, gravity: float3, entities: inout [PhysicsEntity])
+    static func step(deltaTime: Float, gravity: float3, entities: [RigidBody])
 }
 
 extension PhysicsSolver {
-    public static func zeroForces(entities: inout [PhysicsEntity]) {
-        for i in 0..<entities.count {
-            entities[i].zeroForce()
+    public static func zeroForces(entities: [RigidBody]) {
+        for entity in entities {
+            entity.zeroForce()
         }
     }
 }
```

### 1.5 `EulerSolver.swift` — pair-consuming step, factored response, squared compares (P1, P4, P6)

Full replacement (this file changes shape substantially). Behavior parity notes inline:

```swift
final class EulerSolver: PhysicsSolver {
    /// Below this relative speed, colliding bodies are parked (anti-jitter hack).
    /// Stored squared so the hot path compares length_squared with no sqrt.
    private static let restSpeedThresholdSquared: Float = 0.55 * 0.55

    /// Legacy O(n²) step — kept as the `useBroadPhase == false` comparison baseline.
    public static func step(deltaTime: Float, gravity: float3, entities: [RigidBody]) {
        applyForces(deltaTime: deltaTime, gravity: gravity, entities: entities)
        resolveCollisionsAllPairs(entities: entities)
        moveObjects(deltaTime: deltaTime, entities: entities)
        zeroForces(entities: entities)
    }

    /// P1: broad-phase-driven step. Same force/move/zero phases; collision
    /// resolution only inspects the candidate pairs.
    public static func step(deltaTime: Float,
                            gravity: float3,
                            entities: [RigidBody],
                            collisionPairs: [(RigidBody, RigidBody)]) {
        applyForces(deltaTime: deltaTime, gravity: gravity, entities: entities)
        for (ei, ej) in collisionPairs {
            resolvePair(ei, ej)
        }
        moveObjects(deltaTime: deltaTime, entities: entities)
        zeroForces(entities: entities)
    }

    public static func applyForces(deltaTime: Float, gravity: float3, entities: [RigidBody]) {
        for entity in entities where !entity.isStatic {
            let appliedGravity: float3 = entity.shouldApplyGravity ? gravity : .zero
            let acceleration: float3 = entity.force / entity.mass + appliedGravity
            entity.acceleration = acceleration
            entity.velocity += acceleration * deltaTime
        }
    }

    /// O(n²) all-pairs resolve for the no-broad-phase path. Visits each
    /// unordered pair once (the old i≠j double visit's second leg was already
    /// a no-op thanks to the collidedWith guard — this just skips it outright).
    static func resolveCollisionsAllPairs(entities: [RigidBody]) {
        for i in 0..<entities.count {
            for j in (i + 1)..<entities.count {
                resolvePair(entities[i], entities[j])
            }
        }
    }

    /// Narrow phase + response for one candidate pair. Logic is the existing
    /// resolveCollisions body, operating on the class references directly.
    private static func resolvePair(_ ei: RigidBody, _ ej: RigidBody) {
        guard !ei.collidedWith.contains(ObjectIdentifier(ej)),
              PhysicsWorld.collided(entityA: ei, entityB: ej) else { return }

        ei.collidedWith.insert(ObjectIdentifier(ej))
        ej.collidedWith.insert(ObjectIdentifier(ei))

        let collisionData = PhysicsWorld.getCollisionData(ei, ej)
        let collisionVector = collisionData.collisionVector
        let restitution = min(ei.restitution, ej.restitution)
        let unormCollisionVector = collisionData.collisionVector * collisionData.penetrationDepth

        // Hack to prevent infinite bouncing (squared compare, was .magnitude < 0.55):
        if simd_length_squared(ei.velocity - ej.velocity) < restSpeedThresholdSquared {
            ei.velocity = .zero
            ej.velocity = .zero
            return
        }

        if !ei.isStatic && !ej.isStatic {
            ei.setPosition(ei.getPosition() + unormCollisionVector)
            ei.velocity = (ei.velocity + collisionVector) * restitution

            ej.setPosition(ej.getPosition() - unormCollisionVector)
            ej.velocity = (ej.velocity - collisionVector) * restitution
            return
        }

        if !ei.isStatic && ej.isStatic {
            ei.setPosition(ei.getPosition() + unormCollisionVector * 2)
            let vX = collisionVector.x != 0 ? ei.velocity.x * -collisionVector.x * restitution : ei.velocity.x
            let vY = collisionVector.y != 0 ? ei.velocity.y * -collisionVector.y * restitution : ei.velocity.y
            let vZ = collisionVector.z != 0 ? ei.velocity.z * -collisionVector.z * restitution : ei.velocity.z
            ei.velocity = [vX, vY, vZ]
            return
        }

        if ei.isStatic && !ej.isStatic {
            ej.setPosition(ej.getPosition() + unormCollisionVector * 2)
            let vX = collisionVector.x != 0 ? ej.velocity.x * -collisionVector.x * restitution : ej.velocity.x
            let vY = collisionVector.y != 0 ? ej.velocity.y * -collisionVector.y * restitution : ej.velocity.y
            let vZ = collisionVector.z != 0 ? ej.velocity.z * -collisionVector.z * restitution : ej.velocity.z
            ej.velocity = [vX, vY, vZ]
            return
        }
    }

    static func moveObjects(deltaTime: Float, entities: [RigidBody]) {
        for entity in entities where !entity.isStatic {
            entity.setPosition(entity.getPosition() + entity.velocity * deltaTime)
        }
    }
}
```

**Parity caveats (intentional, called out for review):**
1. Pair processing order changes (broad-phase x-sorted order vs. index order; unordered pairs vs. both directions). The old second-direction visit never produced a response (guarded by `collidedWith`), so response *count* is identical, but floating-point outcomes in multi-contact frames can differ in the last bits.
2. In the old code the "park slow collisions" velocity-zeroing read `entities[i/j].velocity` *after* the pair was already marked collided; identical here.

### 1.6 `VerletSolver.swift` — merged zero-acceleration pass (P8)

```swift
final class VerletSolver: PhysicsSolver {
    static func step(deltaTime: Float, gravity: float3, entities: [RigidBody]) {
        for entity in entities {
            // P8: zeroAcceleration() was a separate full pass; merged here.
            // Static entities still get their acceleration cleared, exactly
            // as the old pre-pass did.
            entity.acceleration = .zero
            guard !entity.isStatic else { continue }

            let pos = entity.getPosition()
            let velo = entity.velocity
            // NOTE: acceleration was just zeroed above, so the 0.5·a·dt²/0.5·a·dt
            // history terms below are always zero. That matches the pre-existing
            // behavior (the old code zeroed all accelerations before reading them);
            // true velocity-Verlet would carry last frame's acceleration. Kept
            // bit-identical on purpose — flagged as a separate physics follow-up.
            let acc: float3 = .zero

            let nPosEuler: float3 = pos + velo * deltaTime
            let nPos: float3 = nPosEuler + 0.5 * acc * (deltaTime * deltaTime)

            let veloDtHalf = velo + 0.5 * acc * deltaTime

            var newAcc = acc
            if entity.shouldApplyGravity {
                newAcc += Self.applyForces(gravity: gravity, force: entity.force)
            } else {
                newAcc += Self.applyForces(gravity: .zero, force: entity.force)
            }

            let nVelo = veloDtHalf + 0.5 * newAcc * deltaTime

            entity.setPosition(nPos)
            entity.velocity = nVelo
            entity.acceleration = newAcc
        }

        zeroForces(entities: entities)
    }

    static func applyForces(gravity: float3, force: float3 = .zero) -> float3 {
        return gravity + force
    }
}
```

(`zeroAcceleration` deleted; no other callers — verified by grep.)

### 1.7 `HeckerCollisionResponse.swift` — no index map, direct refs, squared compares (P4, P6, P7)

```swift
final class HeckerCollisionResponse {
    /// Below this relative speed a contact is treated as resting (squared — no sqrt).
    private static let restSpeedThresholdSquared: Float = 0.55 * 0.55
    /// Impulse delta-v below this magnitude is discarded (1.0² == 1.0).
    private static let minDeltaVeloSquared: Float = 1.0

    /// Broad-phase pair path. P7: the per-call [String: Int] index map is gone —
    /// entities are classes, so the response mutates them through the references.
    static func resolveCollisions(deltaTime: Float, collisionPairs: [(RigidBody, RigidBody)]) {
        for (entityA, entityB) in collisionPairs {
            let alreadyCollided = entityA.collidedWith.contains(ObjectIdentifier(entityB))
            if !alreadyCollided && PhysicsWorld.collided(entityA: entityA, entityB: entityB) {
                entityA.collidedWith.insert(ObjectIdentifier(entityB))
                entityB.collidedWith.insert(ObjectIdentifier(entityA))
                applyCollisionResponse(entityA, entityB)
            }
        }
    }

    /// Legacy O(n²) path for useBroadPhase == false (unordered pairs — the old
    /// (j,i) revisit was already suppressed by the collidedWith guard).
    static func resolveCollisions(deltaTime: Float, entities: [RigidBody]) {
        for a in 0..<entities.count {
            for b in (a + 1)..<entities.count {
                let entityA = entities[a]
                let entityB = entities[b]
                let alreadyCollided = entityA.collidedWith.contains(ObjectIdentifier(entityB))
                if !alreadyCollided && PhysicsWorld.collided(entityA: entityA, entityB: entityB) {
                    entityA.collidedWith.insert(ObjectIdentifier(entityB))
                    entityB.collidedWith.insert(ObjectIdentifier(entityA))
                    applyCollisionResponse(entityA, entityB)
                }
            }
        }
    }

    private static func applyCollisionResponse(_ entityA: RigidBody, _ entityB: RigidBody) {
        // Hack:
        // TODO: This will fail if the static entity is not directly below the non-static
        //       entity. Need to figure out a better way...
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

        let collisionData = PhysicsWorld.getCollisionData(entityA, entityB)
        let penetrationDepth = collisionData.penetrationDepth
        // collisionVector is already unit-length (getCollisionData normalizes
        // every branch) — the old second normalize() was a redundant sqrt.
        let collisionNormal = collisionData.collisionVector

        if !entityA.isStatic && !entityB.isStatic {
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
            entityB.setPosition(entityB.getPosition() + collisionNormal * (penetrationDepth * 2))

            let relativeVelo = entityB.velocity
            let e = min(entityA.restitution, entityB.restitution)
            var j = -(1 + e) * dot(relativeVelo, collisionNormal)
            j /= 1.0 / entityB.mass

            let entityBDeltaVelo = j / entityB.mass * collisionNormal
            entityB.velocity += simd_length_squared(entityBDeltaVelo) > minDeltaVeloSquared ? entityBDeltaVelo : .zero
            return
        }
    }
}
```

**Parity caveat:** dropping the redundant `normalize()` assumes `PlaneRigidBody.collisionNormal` is unit-length. All current constructors pass `[0, 1, 0]`. A `precondition`-free safety would be to normalize once in `PlaneRigidBody.init` — included in the diff for `BasicRigidBodies.swift`:

```diff
     init(gameObject: GameObject, collisionNormal: float3 = [0, 1, 0]) {
         super.init(gameObject: gameObject)
-        self.collisionNormal = collisionNormal
+        // Normalize once at init so collision response can use the normal
+        // without re-normalizing per contact.
+        self.collisionNormal = collisionNormal.normalize()
         self.collisionShape = .Plane
     }
```

### 1.8 `BroadPhaseCollisionDetector.swift` — full rewrite (P3)

Replaces the filter/Set/dict/insertion-sort machinery with: one partition pass, AABBs computed once per entity per frame, an index sort on a cached Float key, reusable scratch arrays, and stats gated behind a flag.

```swift
import Foundation
import simd

/// Broad-phase collision detector using single-axis sweep and prune.
///
/// Per-frame flow (all scratch storage reused across frames — zero steady-state
/// allocation):
///   1. Partition entities into static/dynamic and compute every AABB exactly
///      once (one weak-ref dereference per entity per frame).
///   2. Sort an index array by cached `aabb.min.x` — for the entity counts this
///      engine targets (~10²–10³), a full sort of cached Float keys is cheaper
///      than the old "decide whether to sort" machinery, which itself cost O(n)
///      getPosition() + String-keyed dictionary work per frame.
///   3. Sweep the sorted order, emitting candidate pairs.
final class BroadPhaseCollisionDetector {
    // MARK: - Reused per-frame scratch (P3: no per-frame allocations)
    private var staticEntities: [RigidBody] = []
    private var staticAABBs: [AABB] = []
    private var dynamicEntities: [RigidBody] = []
    private var dynamicAABBs: [AABB] = []
    private var sortedDynamicIndices: [Int] = []
    private var pairsScratch: [(RigidBody, RigidBody)] = []

    /// When false (default), skips CFAbsoluteTimeGetCurrent() and stat updates.
    /// PhysicsStressTestScene turns this on.
    var collectStatistics: Bool = false
    private(set) var lastFrameStats = BroadPhaseStats()

    // MARK: - Public Methods

    func update(entities: [RigidBody]) {
        let startTime = collectStatistics ? CFAbsoluteTimeGetCurrent() : 0

        staticEntities.removeAll(keepingCapacity: true)
        staticAABBs.removeAll(keepingCapacity: true)
        dynamicEntities.removeAll(keepingCapacity: true)
        dynamicAABBs.removeAll(keepingCapacity: true)

        // Single partition pass; getAABB() called exactly once per entity.
        for entity in entities {
            if entity.isStatic {
                staticEntities.append(entity)
                staticAABBs.append(entity.getAABB())
            } else {
                dynamicEntities.append(entity)
                dynamicAABBs.append(entity.getAABB())
            }
        }

        // Sort indices by cached min.x — no getAABB() calls inside the comparator.
        sortedDynamicIndices.removeAll(keepingCapacity: true)
        sortedDynamicIndices.append(contentsOf: 0..<dynamicEntities.count)
        sortedDynamicIndices.sort { dynamicAABBs[$0].min.x < dynamicAABBs[$1].min.x }

        if collectStatistics {
            lastFrameStats.updateTime = CFAbsoluteTimeGetCurrent() - startTime
            lastFrameStats.dynamicEntityCount = dynamicEntities.count
            lastFrameStats.staticEntityCount = staticEntities.count
            lastFrameStats.didFullSort = true
        }
    }

    /// Candidate pairs after sweep-and-prune.
    ///
    /// IMPORTANT: the returned array is internal scratch, reused next frame.
    /// Consume it within the current physics step; do not store it. (CoW would
    /// silently copy it on the next removeAll if a stale reference survived,
    /// which is a perf bug, not a correctness one.)
    func getPotentialCollisionPairs() -> [(RigidBody, RigidBody)] {
        let startTime = collectStatistics ? CFAbsoluteTimeGetCurrent() : 0
        var checksPerformed = 0
        var checksSaved = 0

        pairsScratch.removeAll(keepingCapacity: true)

        // Dynamic vs dynamic: sweep along sorted X.
        let sortedCount = sortedDynamicIndices.count
        for si in 0..<sortedCount {
            let i = sortedDynamicIndices[si]
            let aabbA = dynamicAABBs[i]

            for sj in (si + 1)..<sortedCount {
                let j = sortedDynamicIndices[sj]
                let aabbB = dynamicAABBs[j]
                checksPerformed += 1

                // Early exit when X ranges no longer overlap (key optimization).
                if aabbB.min.x > aabbA.max.x {
                    checksSaved += (sortedCount - sj - 1)
                    break
                }

                if aabbA.overlaps(aabbB) {
                    pairsScratch.append((dynamicEntities[i], dynamicEntities[j]))
                }
            }
        }

        // Dynamic vs static.
        for di in 0..<dynamicEntities.count {
            let dynamicAABB = dynamicAABBs[di]
            for si in 0..<staticEntities.count {
                checksPerformed += 1
                if dynamicAABB.overlaps(staticAABBs[si]) {
                    pairsScratch.append((dynamicEntities[di], staticEntities[si]))
                }
            }
        }

        if collectStatistics {
            let dynamicCount = dynamicEntities.count
            let staticCount = staticEntities.count
            let totalPossibleChecks = (dynamicCount * (dynamicCount - 1)) / 2 + (dynamicCount * staticCount)
            lastFrameStats.pairGenerationTime = CFAbsoluteTimeGetCurrent() - startTime
            lastFrameStats.checksPerformed = checksPerformed
            lastFrameStats.checksSaved = checksSaved + (totalPossibleChecks - checksPerformed)
            lastFrameStats.potentialPairs = pairsScratch.count
        }

        return pairsScratch
    }

    func reset() {
        staticEntities.removeAll()
        staticAABBs.removeAll()
        dynamicEntities.removeAll()
        dynamicAABBs.removeAll()
        sortedDynamicIndices.removeAll()
        pairsScratch.removeAll()
        lastFrameStats = BroadPhaseStats()
    }

    func getStatistics() -> (totalChecks: Int, checksSaved: Int) {
        return (lastFrameStats.checksPerformed, lastFrameStats.checksSaved)
    }
}
```

`BroadPhaseStats` struct stays as-is (all fields still meaningful). The `CustomDebugStringConvertible` extension stays, with the entity-count lines reading from `lastFrameStats` instead of the removed arrays' live counts.

Deleted: `lastFramePositions`, `resortThreshold`, `isFirstFrame`, `shouldPerformFullSort`, `performFullSort`, `performInsertionSort`, `updateLastFramePositions`.

### 1.9 Scene type tweaks (P6)

```diff
 // FlightboxWithPhysics.swift:23
-    var entities: [PhysicsEntity] = []
+    var entities: [RigidBody] = []

 // FreeCamFlightboxScene.swift:19
-    var entities: [PhysicsEntity] = []
+    var entities: [RigidBody] = []

 // BallPhysicsScene.swift:57
-        let entities: [PhysicsEntity] = spheres.map { $0.rigidBody! } + [groundRigidBody]
+        let entities: [RigidBody] = spheres.map { $0.rigidBody! } + [groundRigidBody]

 // PhysicsStressTestScene.swift:116-118
-        let entities: [PhysicsEntity] = spheres.map { $0.rigidBody! } + [groundRigidBody]
         physicsWorld = PhysicsWorld(entities: entities, updateType: .HeckerVerlet)
         physicsWorld.useBroadPhase = useBroadPhase
+        physicsWorld.collectBroadPhaseStatistics = true  // stress scene prints these stats
```
(with the stress-test `entities` line also retyped to `[RigidBody]`)

### 1.10 Test updates — `PhysicsSolverTests.swift`

`PhysicsEntityStub` conformed to the protocol directly; with `[RigidBody]` signatures it must become a `RigidBody` subclass. `@testable import` makes internal classes/members overridable in the test target, and the now-optional `gameObject` init parameter (§1.2) means the double needs no GameObject (and therefore no Metal/Engine dependency — the suite stays a logic suite):

```swift
/// Minimal RigidBody test double. Position lives in a local var so solver
/// position writes don't require a GameObject (and the test stays Metal-free).
final class TestRigidBody: RigidBody {
    private var position: float3

    init(position: float3 = .zero,
         mass: Float = 1.0,
         velocity: float3 = .zero,
         force: float3 = .zero,
         isStatic: Bool = false,
         shouldApplyGravity: Bool = true,
         collisionShape: CollisionShape = .Sphere) {
        self.position = position
        super.init(gameObject: nil,
                   collisionShape: collisionShape,
                   mass: mass,
                   velocity: velocity,
                   force: force,
                   isStatic: isStatic,
                   shouldApplyGravity: shouldApplyGravity)
    }

    override func setPosition(_ position: float3) { self.position = position }
    override func getPosition() -> float3 { position }
    override func getAABB() -> AABB { AABB(center: position, radius: 0.5) }
}
```

Mechanical call-site updates throughout the file:
- `PhysicsEntityStub(...)` → `TestRigidBody(...)` (same argument labels).
- `var entities: [PhysicsEntity] = [body]` → `let entities: [RigidBody] = [body]`.
- `EulerSolver.applyForces(deltaTime:gravity:entities: &entities)` → drop the `&` (no longer `inout`); same for `zeroForces`, `EulerSolver.step`, `VerletSolver.step`.

`PhysicsWorldSmokeTests` and `RigidBodyTests` need **no changes**: array literals like `[sphereRB, groundRB]` infer `[RigidBody]`, and neither suite touches `id`/`collidedWith`. The smoke tests' `useBroadPhase = false` paths exercise the kept legacy solvers.

---

## Phase 2 — SceneManager / DrawManager / LightManager (R1, R2, R5)

### 2.1 R1 — `SceneManager.swift`: transparent objects use `ContiguousArray` (least-change option)

```diff
 struct TransparentObjectData {
-    var gameObjects: [GameObject] = []
+    var gameObjects = ContiguousArray<GameObject>()
     var models: [Model] = []
     var meshDatas: [MeshData] = []
```

```diff
         for (model, objData) in transparentObjectDatas {
             guard !objData.gameObjects.isEmpty else { continue }
-            // Transparent objects use ContiguousArray via a temporary:
-            let gameObjects = ContiguousArray(objData.gameObjects)
             if let offset = DrawManager.writeModelConstants(
-                gameObjects: gameObjects,
+                gameObjects: objData.gameObjects,
                 frameIndex: frameIndex
             ) {
                 transparent[model] = RingBufferRegion(
                     offset: offset,
-                    count: gameObjects.count,
+                    count: objData.gameObjects.count,
                     meshDatas: objData.meshDatas
                 )
             }
         }
```

(`addGameObject` keeps working — `ContiguousArray` has `append`.)

### 2.2 R2 — `DrawManager.swift`: once-per-frame transformed-uniforms cache (suggestion 2)

Adds an absolute frame counter, a render-thread-only cache, and a ring-to-ring transform writer that replaces the temp-array path (so suggestion 1's "no intermediate allocation" comes along for free on the cache-miss path).

```diff
     nonisolated(unsafe) private static var currentFrameIndex: Int = 0
     public static var currentRenderFrameIndex: Int { currentFrameIndex }
     nonisolated(unsafe) private static var currentBufferOffset: Int = 0
+    /// Absolute (non-wrapped) frame number, set in BeginFrame. Used by the
+    /// animated-uniforms cache: ring SLOT indices recycle every 3 frames, so
+    /// slot index alone can't tell "this frame" from "3 frames ago".
+    nonisolated(unsafe) private static var currentAbsoluteFrame: Int = -1
+
+    /// R2: per-frame cache of mesh-local-transform-multiplied ModelConstants.
+    /// A mesh with a non-identity animation transform is drawn by up to 6
+    /// passes per frame (4 shadow cascades + GBuffer + transparency); the
+    /// transform multiply is identical in each, so compute once and re-bind.
+    /// Key: mesh identity. Value also records the SOURCE region offset (guards
+    /// against a mesh ever being shared across models) and the absolute frame.
+    /// Render-thread only.
+    private struct AnimatedUniformsEntry {
+        let frame: Int
+        let srcOffset: Int
+        let dstOffset: Int
+    }
+    nonisolated(unsafe) private static var _animatedUniformsCache: [ObjectIdentifier: AnimatedUniformsEntry] = [:]
+
+    /// Called from SceneManager.TeardownScene so stale Mesh keys don't linger
+    /// across scene loads.
+    public static func ClearFrameCaches() {
+        _animatedUniformsCache.removeAll()
+    }
```

```diff
     static func BeginFrame(frameIndex: Int) {
+        currentAbsoluteFrame = frameIndex
         currentFrameIndex = frameIndex % Renderer.maxFramesInFlight
         currentBufferOffset = updateEndOffsets[currentFrameIndex]
     }
```

`DrawFromRingBuffer` animated branch:

```diff
             let ringBuffer = uniformsRingBuffers[currentFrameIndex]
             let localTransform = mesh.transform?.currentTransform ?? .identity
 
             if localTransform != .identity {
-                // Mesh has an animation transform — copy and multiply, write to new ring buffer region:
-                var tempUniforms = [ModelConstants](
-                    UnsafeBufferPointer(
-                        start: ringBuffer.contents().advanced(by: region.offset)
-                            .assumingMemoryBound(to: ModelConstants.self),
-                        count: region.count
-                    )
-                )
-                for i in 0..<tempUniforms.count {
-                    tempUniforms[i].modelMatrix *= localTransform
-                }
-                guard let (animBuffer, animOffset) = writeUniformsToRingBuffer(&tempUniforms) else { return }
-                renderEncoder.setVertexBuffer(animBuffer, offset: animOffset, index: TFSBufferModelConstants.index)
+                // Mesh has an animation transform. Compute the transformed
+                // constants ONCE per frame (first pass that draws this mesh)
+                // and re-bind the same region in subsequent passes.
+                let key = ObjectIdentifier(mesh)
+                if let hit = _animatedUniformsCache[key],
+                   hit.frame == currentAbsoluteFrame,
+                   hit.srcOffset == region.offset {
+                    renderEncoder.setVertexBuffer(uniformsRingBuffers[currentFrameIndex],
+                                                  offset: hit.dstOffset,
+                                                  index: TFSBufferModelConstants.index)
+                } else {
+                    guard let dstOffset = writeTransformedUniforms(region: region,
+                                                                   localTransform: localTransform) else { return }
+                    _animatedUniformsCache[key] = AnimatedUniformsEntry(frame: currentAbsoluteFrame,
+                                                                        srcOffset: region.offset,
+                                                                        dstOffset: dstOffset)
+                    renderEncoder.setVertexBuffer(uniformsRingBuffers[currentFrameIndex],
+                                                  offset: dstOffset,
+                                                  index: TFSBufferModelConstants.index)
+                }
             } else {
                 // No animation — bind ring buffer region directly (ZERO COPY):
                 renderEncoder.setVertexBuffer(ringBuffer, offset: region.offset, index: TFSBufferModelConstants.index)
             }
```

New writer (single pass, ring → ring, no Swift array; same grow logic as the existing writers):

```swift
    /// Reserve a new ring-buffer region and fill it with the source region's
    /// ModelConstants, each modelMatrix post-multiplied by `localTransform`.
    /// Returns the destination byte offset, or nil if the buffer can't grow.
    /// Source and destination regions never overlap: dst starts at/after the
    /// current end-of-writes offset, which is past every update-thread region.
    private static func writeTransformedUniforms(region: RingBufferRegion,
                                                 localTransform: float4x4) -> Int? {
        let count = region.count
        guard count > 0 else { return nil }

        let size = ModelConstants.stride(count)
        let alignment = 256
        let alignedOffset = (currentBufferOffset + alignment - 1) & ~(alignment - 1)

        var ringBuffer = uniformsRingBuffers[currentFrameIndex]

        // Grow buffer if needed (grow-then-read: the memcpy preserves every
        // byte below alignedOffset, which includes the source region):
        if alignedOffset + size > ringBuffer.length {
            let newSize = max(ringBuffer.length * 2, alignedOffset + size)
            guard let grown = Engine.Device.makeBuffer(length: newSize, options: .storageModeShared) else {
                return nil
            }
            grown.label = "Uniforms Ring Buffer \(currentFrameIndex)"
            memcpy(grown.contents(), ringBuffer.contents(), alignedOffset)
            uniformsRingBuffers[currentFrameIndex] = grown
            ringBuffer = grown
        }

        let base = ringBuffer.contents()
        let src = base.advanced(by: region.offset).assumingMemoryBound(to: ModelConstants.self)
        let dst = base.advanced(by: alignedOffset).assumingMemoryBound(to: ModelConstants.self)
        for i in 0..<count {
            var constants = src[i]
            constants.modelMatrix *= localTransform
            dst[i] = constants
        }

        currentBufferOffset = alignedOffset + size
        return alignedOffset
    }
```

And the teardown hook in `SceneManager.TeardownScene()`:

```diff
         // Clear ring buffer snapshots:
         opaqueSnapshots = [[:], [:], [:]]
         transparentSnapshots = [[:], [:], [:]]
         skySnapshots = [nil, nil, nil]
+        DrawManager.ClearFrameCaches()
```

Note: `writeUniformsToRingBuffer` stays — the legacy `Draw` path (point lights / icosahedrons) still uses it. Its animated-transform copy at `DrawManager.swift:444-449` is left alone (R2 scope is the ring-buffer path; the legacy path's arrays are small reusable scratch).

### 2.3 R5 — `LightManager.swift` + `TiledDeferredRenderer.swift`

```diff
 // LightManager.swift
+    /// Cheap count accessor — lets render code branch on "any point lights?"
+    /// without materializing a [LightData] array (each LightData is ~0.5 KB).
+    public static var PointLightCount: Int {
+        withLock(lightLock) { Self._pointLights.count }
+    }
```

```diff
 // TiledDeferredRenderer.swift, encodePointLightStage
-        let pointLights = LightManager.GetPointLightData()
-        if !pointLights.isEmpty {
+        let pointLightCount = LightManager.PointLightCount
+        if pointLightCount > 0 {
             encodeRenderStage(using: renderEncoder, label: "Point Light Stage") {
                 ...
                 renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                     indexCount: submesh.indexCount,
                                                     indexType: submesh.indexType,
                                                     indexBuffer: submesh.indexBuffer,
                                                     indexBufferOffset: submesh.indexBufferOffset,
-                                                    instanceCount: pointLights.count)
+                                                    instanceCount: pointLightCount)
             }
         }
```

(The actual `LightData` upload happens in `SceneManager.SetPointLightData` → scratch-buffer path, unchanged.)

---

## Phase 3 — Scene graph (N1, N2, N4; N3 proposal)

Files: `GameObjects/Node.swift`, `GameObjects/GameObject.swift`, `GameObjects/Cameras/Camera.swift`, `GameObjects/Cameras/AttachedCamera.swift`, `GameObjects/Cameras/DebugCamera.swift`, `GameObjects/Aircraft.swift`.

### 3.1 N1 + N2 — `Node.swift`: cached world matrix, lazy local rebuild

```diff
     var parentModelMatrix = matrix_identity_float4x4
+        { didSet { _worldMatrixValid = false } }
     
     private var _modelMatrix = matrix_identity_float4x4
     private var _rotationMatrix = matrix_identity_float4x4
     
+    /// N2: local T·R·S needs rebuilding (setters no longer rebuild eagerly).
+    private var _localMatrixDirty: Bool = true
+    /// N1: composed parent×local cache.
+    private var _worldMatrix = matrix_identity_float4x4
+    private var _worldMatrixValid: Bool = false
+    /// Bumped whenever the cached world matrix is recomputed. Consumers that
+    /// derive from the world matrix (Camera.viewMatrix) compare generations
+    /// instead of recomputing per read.
+    private(set) var worldMatrixGeneration: UInt64 = 0
+
     /// True when position, rotation, or scale has changed since last update.
     /// Starts true so the first frame computes the initial matrix.
     private var _transformDirty: Bool = true
```

```diff
     var modelMatrix: matrix_float4x4 {
         set {
             _modelMatrix = newValue
+            _localMatrixDirty = false   // caller supplied the local matrix directly
+            _worldMatrixValid = false
         }
         
         get {
-            return matrix_multiply(parentModelMatrix, _modelMatrix)
+            if _localMatrixDirty {
+                // Clear the flag BEFORE rebuilding so derived getters invoked
+                // during the rebuild don't recurse.
+                _localMatrixDirty = false
+                updateModelMatrix()
+                _worldMatrixValid = false
+            }
+            if !_worldMatrixValid {
+                _worldMatrix = matrix_multiply(parentModelMatrix, _modelMatrix)
+                _worldMatrixValid = true
+                worldMatrixGeneration &+= 1
+            }
+            return _worldMatrix
         }
     }
```

```diff
     func updateModelMatrix() {
         _modelMatrix = Transform.translationMatrix(_position) * _rotationMatrix * Transform.scaleMatrix(_scale)
     }
+    // ^ now invoked lazily from the modelMatrix getter (N2). The Camera
+    //   subclasses no longer override it — see Camera.computeViewMatrix(from:).
```

```diff
     @inline(__always)
     func updateModelMatrixAndMarkTransformDirty(_ body: () -> Void) {
         body()
-        updateModelMatrix()
+        // N2: defer the T·R·S rebuild to the first modelMatrix read. Setters
+        // called several times per frame (physics position + collision
+        // corrections) now cost two flag writes instead of two matrix
+        // multiplies each.
+        _localMatrixDirty = true
+        _worldMatrixValid = false
         markTransformDirty()
     }
```

`update()` — hoist the per-child world-matrix recomputation (the getter is now cached, but hoisting also skips N getter calls):

```diff
         worldMatrixDirty = needsUpdate
 
-        for child in children {
-            if needsUpdate {
-                child.parentModelMatrix = self.modelMatrix
-                child._transformDirty = true
-            }
-            
-            child.update()
-        }
+        if needsUpdate && !children.isEmpty {
+            let world = self.modelMatrix   // computed once for all children
+            for child in children {
+                child.parentModelMatrix = world
+                child._transformDirty = true
+                child.update()
+            }
+        } else {
+            for child in children {
+                child.update()
+            }
+        }
```

### 3.2 N1 — `GameObject.swift`: single world-matrix read

```diff
     override func update() {
         super.update()
         
         if worldMatrixDirty {
-            modelConstants.modelMatrix = self.modelMatrix
-            modelConstants.normalMatrix = Transform.normalMatrix(from: self.modelMatrix)
+            let world = self.modelMatrix   // one cached read, not two multiplies
+            modelConstants.modelMatrix = world
+            modelConstants.normalMatrix = Transform.normalMatrix(from: world)
         }
```

### 3.3 N1/N2 — Camera family: generation-based lazy viewMatrix

`Camera.swift`:

```diff
     var cameraType: CameraType!
     var projectionMatrix: matrix_float4x4 = matrix_identity_float4x4
     
     private var _viewMatrix = matrix_identity_float4x4
+    /// worldMatrixGeneration value the cached _viewMatrix was derived from.
+    /// .max == "never computed".
+    private var _viewMatrixGeneration: UInt64 = .max
     var viewMatrix: matrix_float4x4 {
         get {
-            return _viewMatrix
+            // Reading modelMatrix first ensures the world cache (and its
+            // generation) is current; recompute the inverse only when the
+            // world matrix actually changed.
+            let world = modelMatrix
+            if _viewMatrixGeneration != worldMatrixGeneration {
+                _viewMatrix = computeViewMatrix(from: world)
+                _viewMatrixGeneration = worldMatrixGeneration
+            }
+            return _viewMatrix
         }
         
         set {
             _viewMatrix = newValue
+            _viewMatrixGeneration = worldMatrixGeneration
         }
     }
+
+    /// How this camera derives its view matrix from its world matrix.
+    /// Base: plain inverse. AttachedCamera: scale-stripped inverse.
+    func computeViewMatrix(from world: float4x4) -> float4x4 {
+        world.inverse
+    }
```

```diff
-    override func updateModelMatrix() {
-        super.updateModelMatrix()
-        _viewMatrix = modelMatrix.inverse
-    }
+    // updateModelMatrix() override removed: viewMatrix is now derived lazily
+    // (and correctly picks up PARENT moves, which this override never did).
```

`AttachedCamera.swift`:

```diff
-    // To make a camera follow a node, invert the camera's model matrix.
-    // ... (comment retained, moved onto computeViewMatrix)
-    override func updateModelMatrix() {
-        super.updateModelMatrix()
-        viewMatrix = AttachedCamera.scaleStrippedInverse(of: modelMatrix)
-    }
+    // To make a camera follow a node, invert the camera's model matrix.
+    // A camera has no mesh, so a scaled parent (e.g. a setScale(3) jet) should
+    // not warp its view. Strip the inherited scale ... (full comment retained)
+    override func computeViewMatrix(from world: float4x4) -> float4x4 {
+        AttachedCamera.scaleStrippedInverse(of: world)
+    }
 
     ...
 
-    override func update() {
-        super.update()
-        // Recompute viewMatrix when world matrix changed (e.g. parent aircraft moved).
-        // updateModelMatrix() only fires when the camera's OWN transform changes;
-        // this catches the parent-propagation case.
-        if worldMatrixDirty {
-//            viewMatrix = modelMatrix.inverse
-            self.updateModelMatrix()
-        }
-    }
+    // update() override removed: the lazy viewMatrix getter (generation check
+    // in Camera) covers both own-transform and parent-propagation changes.
```

`DebugCamera.swift`:

```diff
-    override func updateModelMatrix() {
-        super.updateModelMatrix()
-        viewMatrix = modelMatrix.inverse
-    }
+    // updateModelMatrix() override removed — base Camera.computeViewMatrix
+    // already returns modelMatrix.inverse, derived lazily.
```

**Parity notes for review:**
- Old behavior recomputed `_viewMatrix` *eagerly on every setter call* (Debug camera: ~10 setter calls per frame while flying = ~10 inverses); new behavior computes at most one inverse per frame per camera, at first `viewMatrix` read. Values identical.
- `viewMatrix` consumers (`GameScene.update`, cascade fitting, click handling) all run on the update thread after `CameraManager.Update()`/scene traversal — ordering unchanged.
- `worldMatrixDirty` keeps its exact semantics for `GameObject`.

### 3.4 N4 — `Node.swift`: `getRotationEulers()`

```diff
-    func getRotationX() -> Float { return Transform.decomposeToEulers(_rotationMatrix).x }
-    func getRotationY() -> Float { return Transform.decomposeToEulers(_rotationMatrix).y }
-    func getRotationZ() -> Float { return Transform.decomposeToEulers(_rotationMatrix).z }
+    /// All three Euler angles from a single decomposition. Prefer this over
+    /// consecutive getRotationX/Y/Z calls (each runs the full decompose).
+    func getRotationEulers() -> float3 { return Transform.decomposeToEulers(_rotationMatrix) }
+    func getRotationX() -> Float { return getRotationEulers().x }
+    func getRotationY() -> Float { return getRotationEulers().y }
+    func getRotationZ() -> Float { return getRotationEulers().z }
```

### 3.5 N3 — `Aircraft.swift` (**PROPOSAL — implement only if approved**)

Skips transform writes when input/rates are effectively zero, so an idle (or non-physics) aircraft stops dirtying its subtree every frame. Once a rate decays below threshold it snaps to exactly 0 so the guard latches.

```diff
 class Aircraft: GameObject {
+    /// Below these, stick input / residual rotation rates are treated as zero
+    /// (skips per-frame transform writes that would dirty the whole subtree).
+    private static let inputEpsilon: Float = 1e-5
+    private static let rateEpsilon: Float = 1e-4   // rad/s; ~0.006°/s
```

```diff
     internal func applyPlayerAttitudeInput(deltaTime: Float, controlInput: ControlInput) {
         let dyn = attitudeDynamics
 
         let cmdPitchRate = controlInput.pitch * dyn.maxPitchRate
         let cmdRollRate  = controlInput.roll  * dyn.maxRollRate
         let cmdYawRate   = controlInput.yaw   * dyn.maxYawRate
 
         let pitchAlpha = 1 - exp(-deltaTime / dyn.pitchTimeConstant)
         let rollAlpha  = 1 - exp(-deltaTime / dyn.rollTimeConstant)
         let yawAlpha   = 1 - exp(-deltaTime / dyn.yawTimeConstant)
 
         currentPitchRate += (cmdPitchRate - currentPitchRate) * pitchAlpha
         currentRollRate  += (cmdRollRate  - currentRollRate)  * rollAlpha
         currentYawRate   += (cmdYawRate   - currentYawRate)   * yawAlpha
 
-        rotateX(-currentPitchRate * deltaTime)
-        rotateZ(-currentRollRate  * deltaTime)
-        rotateY(-currentYawRate   * deltaTime)
+        applyAttitudeRates(deltaTime: deltaTime)
     }
 
     private func decayAttitudeRates(deltaTime: Float) {
         let dyn = attitudeDynamics
         let pitchAlpha = 1 - exp(-deltaTime / dyn.pitchTimeConstant)
         let rollAlpha  = 1 - exp(-deltaTime / dyn.rollTimeConstant)
         let yawAlpha   = 1 - exp(-deltaTime / dyn.yawTimeConstant)
 
         currentPitchRate += (0 - currentPitchRate) * pitchAlpha
         currentRollRate  += (0 - currentRollRate)  * rollAlpha
         currentYawRate   += (0 - currentYawRate)   * yawAlpha
 
-        rotateX(-currentPitchRate * deltaTime)
-        rotateZ(-currentRollRate  * deltaTime)
-        rotateY(-currentYawRate   * deltaTime)
+        applyAttitudeRates(deltaTime: deltaTime)
     }
+
+    /// Applies accumulated rates, snapping sub-epsilon residuals to exactly 0
+    /// so a settled aircraft performs zero rotate() calls (and never dirties
+    /// its subtree) until the next real input.
+    private func applyAttitudeRates(deltaTime: Float) {
+        if abs(currentPitchRate) < Self.rateEpsilon { currentPitchRate = 0 } else { rotateX(-currentPitchRate * deltaTime) }
+        if abs(currentRollRate)  < Self.rateEpsilon { currentRollRate  = 0 } else { rotateZ(-currentRollRate  * deltaTime) }
+        if abs(currentYawRate)   < Self.rateEpsilon { currentYawRate   = 0 } else { rotateY(-currentYawRate   * deltaTime) }
+    }
 
     internal func applyPlayerSideMove(deltaMove: Float) {
-        moveAlongVector(getRightVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveSide))
+        let side = InputManager.ContinuousCommand(.MoveSide)
+        guard abs(side) > Self.inputEpsilon else { return }
+        moveAlongVector(getRightVector(), distance: deltaMove * side)
     }
```

**Behavior delta (why this is a proposal):** residual rotation below ~0.006°/s is dropped instead of applied forever, and a zero side-stick no longer issues a `setPosition` per frame. Imperceptible in flight, but it *is* a change to control feel in principle. The physics-driven F-22 still updates every frame via the rigid body, so the visible win is for non-physics aircraft and at-rest states.

---

## Phase 4 — Animation (A1, A2, A3, A3+)

Files: `Animation/Skeleton.swift`, `Animation/Animation.swift`, `Animation/AnimationClip.swift`, `Animation/Layers/ProceduralAnimationChannel.swift`, `Animation/Layers/AnimationLayerSystem.swift`.

### 4.1 A1 — `Skeleton.swift`: cached inverses, in-place world poses, path→index map

```diff
 class Skeleton {
     let parentIndices: [Int?]
     let jointPaths: [String]
     let bindTransforms: [float4x4]
     let restTransforms: [float4x4]
+    /// A1: bind matrices never change — invert once at load, not per joint per frame.
+    let inverseBindTransforms: [float4x4]
+    /// A2: O(1) jointPath → index lookups at registration time (replaces
+    /// firstIndex(of:) linear String scans). First index wins on duplicates,
+    /// matching firstIndex semantics.
+    let jointIndexByPath: [String: Int]
     var currentPose: [float4x4] = []
 
     private(set) var localPoses: [float4x4]
 
     /// Optional basis transform for coordinate system conversion (e.g., USDZ to game coords)
     let basisTransform: float4x4?
+    /// A1: constant per skeleton — computed once instead of per evaluateWorldPoses call.
+    private let inverseBasisTransform: float4x4?
 
     init?(mdlSkeleton: MDLSkeleton?, basisTransform: float4x4? = nil) {
         guard let mdlSkeleton, !mdlSkeleton.jointPaths.isEmpty else { return nil }
         self.basisTransform = basisTransform
+        self.inverseBasisTransform = basisTransform?.inverse
         jointPaths = mdlSkeleton.jointPaths
         parentIndices = Skeleton.getParentIndices(jointPaths: jointPaths)
         bindTransforms = mdlSkeleton.jointBindTransforms.float4x4Array
+        inverseBindTransforms = bindTransforms.map { $0.inverse }
         restTransforms = mdlSkeleton.jointRestTransforms.float4x4Array
         localPoses = restTransforms
+        jointIndexByPath = Dictionary(jointPaths.enumerated().map { ($1, $0) },
+                                      uniquingKeysWith: { first, _ in first })
     }
```

```diff
     func mapJoints(from jointPaths: [String]) -> [Int] {
         jointPaths.compactMap { jointPath in
-            self.jointPaths.firstIndex(of: jointPath)
+            self.jointIndexByPath[jointPath]
         }
     }
```

`evaluateWorldPoses` — zero allocation, fused bind-inverse + basis passes:

```swift
    /// Computes world-space currentPose from the accumulated localPoses.
    /// Call this once per frame after all clip and procedural channels have written to localPoses.
    /// Allocation-free: currentPose is written in place (parents precede
    /// children in joint order, so pass 1 can safely read freshly written
    /// parent poses from the same array).
    func evaluateWorldPoses() {
        let count = parentIndices.count
        if currentPose.count != count {
            currentPose = [float4x4](repeating: .identity, count: count)
        }

        // Pass 1: pure world poses.
        for index in 0..<count {
            let localMatrix = localPoses[index]
            if let parentIndex = parentIndices[index] {
                currentPose[index] = currentPose[parentIndex] * localMatrix
            } else {
                currentPose[index] = localMatrix
            }
        }

        // Pass 2: bind-inverse, with the basis conjugation fused in when present.
        // (Same math as before: basisInverse * (world * bindInverse) * basis.)
        if let basisTransform, let inverseBasisTransform {
            for index in 0..<count {
                currentPose[index] = inverseBasisTransform * (currentPose[index] * inverseBindTransforms[index]) * basisTransform
            }
        } else {
            for index in 0..<count {
                currentPose[index] *= inverseBindTransforms[index]
            }
        }
    }
```

### 4.2 A2/A3 — index-resolved channel application

**`Skeleton.swift`** — the per-frame application methods become index-based; the String-keyed versions they replace are deleted (their only caller was `AnimationLayerSystem.applyChannelToLocalPoses`; the fallback path uses `updatePose`, which stays):

```swift
    /// A3: clip application over registration-resolved (jointIndex, animation)
    /// pairs — no mask Set lookups, no per-joint dictionary lookups.
    /// `animation == nil` means the clip has no track for that joint → rest pose,
    /// matching the old `getPose(...) ?? restTransforms[index]` fallback.
    func applyClip(at currentTime: Float,
                   animationClip: AnimationClip,
                   resolvedJoints: [(jointIndex: Int, animation: Animation?)]) {
        let time = min(currentTime, animationClip.duration) * animationClip.speed
        for (jointIndex, animation) in resolvedJoints {
            if let animation {
                localPoses[jointIndex] = animation.getPose(at: time)
            } else {
                localPoses[jointIndex] = restTransforms[jointIndex]
            }
        }
    }

    /// A2: procedural overrides by pre-resolved joint index. `jointIndices[i]`
    /// pairs with `rotations[i]`; -1 marks a config whose joint path wasn't
    /// found in this skeleton (resolved & warned at registration time).
    func applyProceduralOverrides(jointIndices: [Int], rotations: [float4x4]) {
        for i in 0..<jointIndices.count {
            let index = jointIndices[i]
            guard index >= 0 else { continue }
            localPoses[index] = restTransforms[index] * rotations[i]
        }
    }
```

(Deleted: `applyClip(at:animationClip:mask:)` and `applyProceduralOverrides(_ overrides: [String: float4x4])`.)

**`Animation.swift`** — pose composition moves onto `Animation` (shared by old and new paths):

```swift
    /// T·R·S pose at `time`, with per-track identity fallbacks.
    /// (Extracted from AnimationClip.getPose so index-resolved callers can
    /// sample without the jointPath dictionary lookup.)
    func getPose(at time: Float) -> float4x4 {
        let rotation = getRotation(at: time) ?? simd_quatf(matrix_identity_float4x4)
        let translation = getTranslation(at: time) ?? float3.zero
        let scale = getScale(at: time) ?? float3.one
        return Transform.translationMatrix(translation) * float4x4(rotation) * Transform.scaleMatrix(scale)
    }
```

**`AnimationClip.swift`** — delegates (legacy `updatePose` fallback keeps working):

```diff
     func getPose(at time: Float, jointPath: String) -> float4x4? {
         guard let jointAnimation = jointAnimation[jointPath],
               let jointAnimation = jointAnimation else { return nil }
-        
-        let rotation = jointAnimation.getRotation(at: time) ?? simd_quatf(matrix_identity_float4x4)
-        let translation = jointAnimation.getTranslation(at: time) ?? float3.zero
-        let scale = jointAnimation.getScale(at: time) ?? float3.one
-        let pose = Transform.translationMatrix(translation) * float4x4(rotation) * Transform.scaleMatrix(scale)
-        return pose
+        return jointAnimation.getPose(at: time)
     }
```

**`ProceduralAnimationChannel.swift`** — scratch-array rotations, axis pre-normalized:

```diff
     init(jointPath: String, axis: float3, maxDeflection: Float, inverted: Bool = false) {
         self.jointPath = jointPath
-        self.axis = axis
+        // Normalized once here so per-frame rotation construction skips it.
+        self.axis = normalize(axis)
         self.maxDeflection = maxDeflection
         self.inverted = inverted
     }
```

```diff
-    /// Computes joint rotation overrides based on the current channel value.
-    /// Returns a dictionary of jointPath -> local rotation matrix.
-    /// These rotations are applied on top of (multiplied with) the joint's rest transform.
-    func getJointOverrides() -> [String: float4x4] {
-        var overrides: [String: float4x4] = [:]
-
-        for config in jointConfigs {
-            let deflection = config.inverted ? -value : value
-            let angle = deflection * config.maxDeflection
-            let rotation = float4x4(rotateAbout: normalize(config.axis), byAngle: angle)
-            overrides[config.jointPath] = rotation
-        }
-
-        return overrides
-    }
+    /// Reused output buffer for computeJointRotations — one slot per jointConfig.
+    private var rotationScratch: [float4x4] = []
+
+    /// Computes per-config local rotations into a reused buffer (A2: indices
+    /// are resolved at registration; element i pairs with jointConfigs[i]).
+    /// The returned array is internal scratch — consume immediately.
+    func computeJointRotations() -> [float4x4] {
+        if rotationScratch.count != jointConfigs.count {
+            rotationScratch = [float4x4](repeating: .identity, count: jointConfigs.count)
+        }
+        for (i, config) in jointConfigs.enumerated() {
+            let deflection = config.inverted ? -value : value
+            let angle = deflection * config.maxDeflection
+            rotationScratch[i] = float4x4(rotateAbout: config.axis, byAngle: angle)
+        }
+        return rotationScratch
+    }
```

**`AnimationLayerSystem.swift`** — `ChannelMapping` carries the resolved data; the hot path uses it:

```diff
-/// Pre-computed mapping from a channel to the skeletons and meshes it affects.
-/// Built once at registration time so the per-frame update path does zero discovery work.
 struct ChannelMapping {
-    /// Skeleton paths affected by this channel, paired with the clip to use.
-    /// Clip is nil for procedural channels that don't sample from clips.
-    let skeletonEntries: [(path: String, clip: AnimationClip?)]
+    struct SkeletonEntry {
+        let path: String
+        /// Resolved once — avoids the model.skeletons dictionary lookup per frame.
+        let skeleton: Skeleton
+        /// Clip is nil for procedural channels that don't sample from clips.
+        let clip: AnimationClip?
+        /// A3 (clip channels): masked joints pre-resolved to (index, animation).
+        let resolvedClipJoints: [(jointIndex: Int, animation: Animation?)]
+        /// A2 (procedural channels): jointConfigs[i] → joint index (-1 = missing).
+        let proceduralJointIndices: [Int]
+    }
+    let skeletonEntries: [SkeletonEntry]
 
     /// Mesh indices that need transform and/or skin updates
     let affectedMeshIndices: [Int]
 
     /// For each affected mesh index, the skeleton (if any) that drives its skin
     let meshSkeletonLookup: [Int: Skeleton]
 }
```

```diff
         if let proceduralChannel = channel as? ProceduralAnimationChannel {
             // Procedural path: apply direct joint overrides to localPoses
-            let overrides = proceduralChannel.getJointOverrides()
+            let rotations = proceduralChannel.computeJointRotations()
             for entry in mapping.skeletonEntries {
-                model.skeletons[entry.path]?.applyProceduralOverrides(overrides)
+                entry.skeleton.applyProceduralOverrides(jointIndices: entry.proceduralJointIndices,
+                                                        rotations: rotations)
                 dirtySkeletonPaths.insert(entry.path)
             }
         } else {
             // Clip-based path: sample animation clip and write to localPoses
             let animTime = channel.getAnimationTime()
             ...
             for entry in mapping.skeletonEntries {
                 guard let clip = entry.clip else { continue }
-                model.skeletons[entry.path]?.applyClip(at: animTime, animationClip: clip, mask: channel.mask)
+                entry.skeleton.applyClip(at: animTime,
+                                         animationClip: clip,
+                                         resolvedJoints: entry.resolvedClipJoints)
                 dirtySkeletonPaths.insert(entry.path)
             }
```

`buildMapping` gains the resolution work (registration time only):

```diff
         for (skeletonPath, skeleton) in model.skeletons {
             let hasAffectedJoints = skeleton.jointPaths.contains { mask.contains(jointPath: $0) }
 
             if hasAffectedJoints || mask.jointPaths.isEmpty {
                 affectedSkeletonPaths.insert(skeletonPath)
 
                 if isProcedural {
-                    // Procedural channels don't need a clip
-                    skeletonEntries.append((path: skeletonPath, clip: nil))
+                    // Procedural channels don't need a clip. Resolve each
+                    // jointConfig's path to its index in THIS skeleton (A2).
+                    let configs = (channel as? ProceduralAnimationChannel)?.jointConfigs ?? []
+                    let indices: [Int] = configs.map { config in
+                        if let idx = skeleton.jointIndexByPath[config.jointPath] { return idx }
+                        print("[AnimationLayerSystem] Warning: channel '\(channel.id)' targets joint '\(config.jointPath)' not present in skeleton '\(skeletonPath)'")
+                        return -1
+                    }
+                    skeletonEntries.append(.init(path: skeletonPath,
+                                                 skeleton: skeleton,
+                                                 clip: nil,
+                                                 resolvedClipJoints: [],
+                                                 proceduralJointIndices: indices))
                 } else {
                     let clip = channel.animationClip
                         ?? model.animationClips[model.skeletonAnimationMap[skeletonPath] ?? ""]
                         ?? model.animationClips.values.first
 
-                    skeletonEntries.append((path: skeletonPath, clip: clip))
+                    // A3: resolve masked joints to (index, animation) once.
+                    // Semantics match the old per-frame loop: empty mask = all
+                    // joints; missing clip track (nil animation) = rest pose.
+                    var resolved: [(jointIndex: Int, animation: Animation?)] = []
+                    if let clip {
+                        for (index, path) in skeleton.jointPaths.enumerated() {
+                            guard mask.jointPaths.isEmpty || mask.contains(jointPath: path) else { continue }
+                            resolved.append((jointIndex: index, animation: clip.jointAnimation[path] ?? nil))
+                        }
+                    }
+                    skeletonEntries.append(.init(path: skeletonPath,
+                                                 skeleton: skeleton,
+                                                 clip: clip,
+                                                 resolvedClipJoints: resolved,
+                                                 proceduralJointIndices: []))
                 }
             }
         }
```

(`var skeletonEntries: [(path: String, clip: AnimationClip?)] = []` becomes `var skeletonEntries: [ChannelMapping.SkeletonEntry] = []`.)

**Note on mapping staleness:** `ChannelMapping` now holds `Skeleton` references and resolved indices. These are derived from the model's skeletons at registration time; the model's skeletons never change post-load, and channels are re-registered per animator construction. No new invalidation cases.

### 4.3 A3+ — `Animation.swift`: kill the per-sample `keyFramePairs` allocation (found while planning)

`getTranslation/getRotation/getScale` each build an **array of all keyframe pairs** (`indices.dropFirst().map { ... }`) per joint per sample — the single biggest allocation in the clip-sampling path and squarely inside A3's scope. Replace with a direct scan (identical first-match semantics, zero allocation). Shown for `getTranslation`; `getRotation` (with `simd_slerp`) and `getScale` get the same shape:

```diff
         currentTime = fmod(currentTime, lastKeyframe.time)
-        let keyFramePairs = translations.indices.dropFirst().map {
-            (previous: translations[$0 - 1], next: translations[$0])
-        }
-        guard
-            let (previousKey, nextKey) =
-                (keyFramePairs.first {
-                    currentTime < $0.next.time
-                })
-        else { return nil }
-        let interpolant =
-            (currentTime - previousKey.time) / (nextKey.time - previousKey.time)
-        return simd_mix(
-            previousKey.value,
-            nextKey.value,
-            float3(repeating: interpolant)
-        )
+        // Scan for the bracketing pair directly — the old code materialized an
+        // array of ALL (prev, next) pairs per sample just to call first(where:).
+        for i in 1..<translations.count where currentTime < translations[i].time {
+            let previousKey = translations[i - 1]
+            let nextKey = translations[i]
+            let interpolant = (currentTime - previousKey.time) / (nextKey.time - previousKey.time)
+            return simd_mix(previousKey.value, nextKey.value, float3(repeating: interpolant))
+        }
+        return nil
```

---

## What is intentionally NOT in this plan

- R3 (snapshot dict reuse), R4 (debug-label caching) — deferred per review.
- R5's `GetDirectionalLightData`/`cascadeViewProjections` allocations — deferred per review.
- The Verlet integration's zeroed-acceleration history term — flagged in a comment, behavior preserved (physics change, not a perf change).
- `view.sampleCount` per-frame set, `GameStatsManager`, `ComputeManager` traversal (G1/F-items) — not in the requested fix list.

## Implementation order & verification

Each phase lands as its own commit, built and smoke-tested before the next:

1. **Phase 1 (physics)** → 2. **Phase 2 (render managers)** → 3. **Phase 3 (scene graph)** → 4. **Phase 4 (animation)**

Per phase:

```bash
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" \
  -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

Tests: per the known test-host constraint (unscoped local `xcodebuild test` hangs at app-host launch), run scoped suites locally after building —
`-only-testing:ToyFlightSimulatorTests/EulerSolverTests`, `.../VerletSolverTests` (Phase 1), `.../AttachedCameraTests` + `NodeTests` (Phase 3), Math/Utils suites as regression canaries — and let CI run the full app-hosted suite (PhysicsWorldSmokeTests, RigidBodyTests) on push.

Manual smoke checks (default `FlightboxWithPhysics` scene):
- **Phase 1:** balls fall, collide, settle without jitter; aircraft thrust/lift works; `PhysicsStressTestScene` still prints broad-phase stats and shows improved timings at 100/500/1000 spheres.
- **Phase 2:** transparent spheres + F-22 canopy render as before; renderer switch to TiledDeferred shows point lights; gear animation renders identically in shadow + main passes (R2 cache correctness).
- **Phase 3:** attached camera follows the jet with no lag/jitter (lazy viewMatrix), 'C' toggles to debug camera and WASD/mouselook works, scaled-parent camera still produces correct shadows (scale-strip path).
- **Phase 4:** gear toggle (G) animates smoothly; F-22 control surfaces deflect with stick input; F-35 animations unaffected.

Perf validation: Instruments *Allocations* (transient) while idling 30 s in the default scene — expect physics/broad-phase/String allocation churn to drop to near zero; *Time Profiler* on `PhysicsWorld.update` before/after.

## Open questions for review

1. **P1/P4 parity:** pair iteration order changes (sorted-by-X vs index order) can shift float outcomes in multi-contact frames by ULPs. Acceptable? (The smoke tests assert qualitative behavior, not exact trajectories — they should pass.)
2. **Legacy O(n²) baselines** (`useBroadPhase == false`) get the `j in (i+1)...` upgrade too, which roughly halves the "without broad-phase" baseline cost in `PhysicsStressTestScene` comparisons. Keep the upgrade (my recommendation — the old second visit was dead work), or preserve the old loop exactly for benchmark continuity?
3. **N3** is included as a proposal — approve, modify thresholds, or drop?
4. **`PlaneRigidBody` normal normalization at init** (§1.7) — tiny behavior guard, included by default; object if you'd rather assert instead.
