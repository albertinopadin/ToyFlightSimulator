//
//  RigidBody.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/14/26.
//

import Foundation

public class RigidBody: PhysicsEntity {
    public struct State {
        public let mass: Float
        public let velocity: float3
        public let acceleration: float3

        public let worldForward: float3
        public let worldRight: float3
        public let rotationMatrix: matrix_float4x4

        public init(mass: Float,
                    velocity: float3,
                    acceleration: float3,
                    worldForward: float3,
                    worldRight: float3,
                    rotationMatrix: matrix_float4x4) {
            self.mass = mass
            self.velocity = velocity
            self.acceleration = acceleration
            self.worldForward = worldForward
            self.worldRight = worldRight
            self.rotationMatrix = rotationMatrix
        }
    }
    
    var collisionShape: CollisionShape
    var collidedWith: Set<ObjectIdentifier>
    var mass: Float
    var velocity: float3
    var acceleration: float3
    var force: float3
    var restitution: Float
    var isStatic: Bool
    var shouldApplyGravity: Bool
    
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
        if let mine = gameObject, let theirs = other.gameObject, mine === theirs { return false }
        return true
    }
    
    // GameObject this is attached to:
    weak let gameObject: GameObject?
    
    /// Standalone-mode storage (parity-harness bodies built with init(detachedAt:)).
    /// Attached bodies never touch this: a released weak gameObject keeps the
    /// tested .zero / no-op fallbacks — that state is a bug signal, not a mode.
    private let isStandalone: Bool
    private var standalonePosition: float3 = .zero
    
    /// `gameObject` is optional so test doubles can exist without a GameObject
    /// (and therefore without Metal/asset loading); all production rigid bodies
    /// pass a non-nil GameObject.
    internal init(gameObject: GameObject?,
                  collisionShape: CollisionShape = .Sphere,
                  collidedWith: Set<ObjectIdentifier> = [],
                  mass: Float = 1,
                  velocity: float3 = .zero,
                  acceleration: float3 = .zero,
                  force: float3 = .zero,
                  restitution: Float = 1,
                  isStatic: Bool = false,
                  shouldApplyGravity: Bool = true) {
        self.gameObject = gameObject
        self.collisionShape = collisionShape
        self.collidedWith = collidedWith
        self.mass = mass
        self.velocity = velocity
        self.acceleration = acceleration
        self.force = force
        self.restitution = restitution
        self.isStatic = isStatic
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
        invalidateWorldColliders()
        
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
    
    func getAABB() -> AABB {
        // Compound bodies: union of the world colliders' bounds.
        let worlds = worldColliders()
        guard var merged = worlds.first?.aabb else {
            // No colliders: the legacy node-AABB delegate, unchanged.
            return self.gameObject?.getAABB() ?? AABB(center: .zero, radius: .zero)
        }

        for collider in worlds.dropFirst() {
            merged = merged.merged(with: collider.aabb)
        }
        
        return merged
    }
    
    func getState() -> RigidBody.State? {
        if let fwd = self.gameObject?.getFwdVector(),
           let right = self.gameObject?.getRightVector(),
           let rotationMatrix = self.gameObject?.getRotationMatrix() {
            return RigidBody.State(mass: self.mass,
                                   velocity: self.velocity,
                                   acceleration: self.acceleration,
                                   worldForward: fwd,
                                   worldRight: right,
                                   rotationMatrix: rotationMatrix)
        } else {
            return nil
        }
    }
}

/// Bitmask vocabulary for collision filtering. Extend as needed; assign
/// categories when a scene actually needs to filter (Phase B/C) — the
/// defaults (default category, all-mask) keep every pair live.
enum CollisionCategory {
    static let `default`: UInt32    = 1 << 0
    static let world: UInt32        = 1 << 1    // ground plane, terrain
    static let vehicle: UInt32      = 1 << 2    // player + AI aircraft
    static let structure: UInt32    = 1 << 3    // buildings, towers
    static let debris: UInt32       = 1 << 4    // random physics objects
    static let all: UInt32          = .max
}
