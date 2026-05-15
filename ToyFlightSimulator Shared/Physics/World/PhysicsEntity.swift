//
//  PhysicsEntity.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/31/24.
//

import Foundation
import simd

enum CollisionShape {
    case Sphere
    case Plane
}

protocol PhysicsEntity {
    var id: String { get }
    var collisionShape: CollisionShape { get set }
    var collidedWith: [String : Bool] { get set }
    
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

extension PhysicsEntity {    
    static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id
    }
    
    mutating func resetCollisions() {
        collidedWith.removeAll(keepingCapacity: true)
    }
    
    mutating func zeroForce() {
        force = .zero
    }
    
    // Computed property for dynamic check (inverse of static)
    var isDynamic: Bool {
        return !isStatic
    }
}
