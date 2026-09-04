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
    
    var collidedWith: Set<ObjectIdentifier>
    var mass: Float
    var velocity: float3
    var acceleration: float3
    var force: float3
    var restitution: Float
    var isStatic: Bool
    var shouldApplyGravity: Bool
    
    /// True once VerletSolver has stored a(t) for this body. Until then the
    /// solver seeds a(t) from the current forces instead of integrating from
    /// .zero, which ran every Verlet trajectory h/2 late (found at the B.3
    /// regeneration). Written by VerletSolver only; cleared while the body is
    /// static. EulerSolver does not carry acceleration and ignores it.
    var accelerationIsWarm: Bool = false
    
    /// Compound collision geometry: primitives at body-local offsets. Empty
    /// for planes (handled at body level in the narrow phase), ignored by
    /// SphereRigidBody (it uses collisionRadius); a plain RigidBody with no
    /// colliders makes no contacts.
    var colliders: [LocalCollider] = [] {
        didSet { invalidateWorldColliders() }
    }

    /// Collision filtering: a pair is tested only if each body's category
    /// intersects the other's mask. Defaults collide with everything.
    var categoryMask: UInt32 = CollisionCategory.default
    var collidesWithMask: UInt32 = CollisionCategory.all

    /// Called once per contact this body is part of, on the UpdateThread,
    /// after the response for that pair. Every collider-pair contact fires,
    /// not only the deepest. The Contact has self as A. Keep it cheap; do not
    /// change physics state here.
    var onContact: ((Contact, RigidBody) -> Void)?
    
    /// Per-substep force source, called by PhysicsWorld at the top of every
    /// step before collision detection and integration, with this body as the
    /// first argument. Add to `force`; it is zeroed at the end of each step,
    /// so write it on every call. Do not move the body or change its velocity
    /// here. nil for bodies that only feel gravity and contacts.
    var forceGenerator: ((_ body: RigidBody, _ substepDelta: Float, _ world: PhysicsWorld) -> Void)?

    /// World-space collider cache behind a dirty flag. Invalidated by
    /// setPosition, by collider changes, and by the world at the start of
    /// every step (node rotation does not go through setPosition). Code that
    /// moves a body outside a stepped world must call
    /// invalidateWorldColliders(). `worldCollidersScratch` is internal only so
    /// subclass rebuilds can write it.
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

    /// Symmetric filter: category and mask both ways, and never two bodies on
    /// the same GameObject. Detached bodies (nil gameObject) never match each
    /// other on that rule.
    func shouldCollide(with other: RigidBody) -> Bool {
        guard (categoryMask & other.collidesWithMask) != 0,
              (other.categoryMask & collidesWithMask) != 0 else { return false }
        if let mine = gameObject, let theirs = other.gameObject, mine === theirs { return false }
        return true
    }
    
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

        // Register with object this is attached to:
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
        }
        else {
            gameObject?.setPosition(position)
        }
    }
    
    func getPosition() -> float3 {
        standalonePosition ?? gameObject?.getPosition() ?? .zero
    }
    
    func getAABB() -> AABB {
        // Compound bodies: union of the world colliders' bounds.
        let worlds = worldColliders()
        guard var merged = worlds.first?.aabb else {
            // No colliders: the node's own AABB.
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
}

/// Bitmask vocabulary for collision filtering. Nothing assigns categories
/// yet; the defaults (default category, all mask) keep every pair live.
enum CollisionCategory {
    static let `default`: UInt32    = 1 << 0
    static let world: UInt32        = 1 << 1    // ground plane, terrain
    static let vehicle: UInt32      = 1 << 2    // player + AI aircraft
    static let structure: UInt32    = 1 << 3    // buildings, towers
    static let debris: UInt32       = 1 << 4    // random physics objects
    static let all: UInt32          = .max
}
