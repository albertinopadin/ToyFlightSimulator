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
    
    let id: String
    var collisionShape: CollisionShape
    var collidedWith: [String : Bool]
    var mass: Float
    var velocity: float3
    var acceleration: float3
    var force: float3
    var restitution: Float
    var isStatic: Bool
    var shouldApplyGravity: Bool
    
    // GameObject this is attached to:
    weak let gameObject: GameObject?
    
    internal init(gameObject: GameObject,
                  collisionShape: CollisionShape = .Sphere,
                  collidedWith: [String : Bool] = [:],
                  mass: Float = 1,
                  velocity: float3 = .zero,
                  acceleration: float3 = .zero,
                  force: float3 = .zero,
                  restitution: Float = 1,
                  isStatic: Bool = false,
                  shouldApplyGravity: Bool = true) {
        self.id = UUID().uuidString
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

        // Register with object this is attached to:
        gameObject.rigidBody = self
    }
    
    func setPosition(_ position: float3) {
        self.gameObject?.setPosition(position)
    }
    
    func getPosition() -> float3 {
        self.gameObject?.getPosition() ?? .zero
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
