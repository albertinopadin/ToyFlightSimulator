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
    
    /// Velocity at the top of the current step, before this step's contact
    /// impulses. Written by PhysicsWorld. onContact handlers run after the
    /// response, when `velocity` is already the post-impact value, so impact
    /// classification reads this instead.
    var stepStartVelocity: float3 = .zero
    
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
    
    /// World-space collider cache behind a dirty flag. Invalidated by
    /// setPosition, by rotate(by:) and setRotation, by collider changes, and
    /// by the world at the start of every step (the kinematic attitude path
    /// rotates the node without going through the body). Code that
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
    /// GameObject was released, use their own rotation (identity until
    /// rotated) at getPosition().
    func pose() -> (position: float3, rotation: float3x3, uniformScale: Float) {
        guard let node = gameObject else {
            return (getPosition(), standaloneRotation, 1.0)
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
