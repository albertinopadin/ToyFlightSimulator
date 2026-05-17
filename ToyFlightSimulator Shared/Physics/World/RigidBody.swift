//
//  RigidBody.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/14/26.
//

import Foundation

public class RigidBody: PhysicsEntity {
    public struct State {
        let mass: Float
        let velocity: float3
        let acceleration: float3
        
        let worldForward: float3
        let worldRight: float3
        let rotationMatrix: matrix_float4x4
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
    
    func getState() -> RigidBody.State {
        return RigidBody.State(mass: self.mass,
                               velocity: self.velocity,
                               acceleration: self.acceleration,
                               worldForward: self.gameObject!.getFwdVector(),
                               worldRight: self.gameObject!.getRightVector(),
                               rotationMatrix: self.gameObject!.getRotationMatrix())
    }
}
