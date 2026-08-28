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
        self.gameObject?.getAABB() ?? AABB(center: .zero, radius: .zero)
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
