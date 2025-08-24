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
    
    mutating func reset() {
        collidedWith.removeAll()
    }
    
    // Computed property for dynamic check (inverse of static)
    var isDynamic: Bool {
        return !isStatic
    }
}

protocol SpherePhysicsEntity: PhysicsEntity {
    var collisionRadius: Float { get set }
}

extension SpherePhysicsEntity {
    // Default AABB implementation for spheres
    func getAABB() -> AABB {
        return AABB(center: getPosition(), radius: collisionRadius)
    }
}

protocol PlanePhysicsEntity: PhysicsEntity {
    var collisionNormal: float3 { get set }
}

extension PlanePhysicsEntity {
    // Default AABB implementation for planes
    // Using a large box to represent an "infinite" plane
    func getAABB() -> AABB {
        let position = getPosition()
        let largeExtent: Float = 10000.0  // Large enough to cover the game world
        
        // Create a thin but wide AABB based on the plane's normal
        if abs(collisionNormal.y) > 0.9 {
            // Horizontal plane (normal points up/down)
            return AABB(
                min: float3(position.x - largeExtent, position.y - 1.0, position.z - largeExtent),
                max: float3(position.x + largeExtent, position.y + 1.0, position.z + largeExtent)
            )
        } else if abs(collisionNormal.x) > 0.9 {
            // Vertical plane (normal points left/right)
            return AABB(
                min: float3(position.x - 1.0, position.y - largeExtent, position.z - largeExtent),
                max: float3(position.x + 1.0, position.y + largeExtent, position.z + largeExtent)
            )
        } else {
            // Vertical plane (normal points forward/back)
            return AABB(
                min: float3(position.x - largeExtent, position.y - largeExtent, position.z - 1.0),
                max: float3(position.x + largeExtent, position.y + largeExtent, position.z + 1.0)
            )
        }
    }
}

final class CollidableSphere: Sphere, SpherePhysicsEntity {
    var collisionRadius: Float = 1.0
}

final class CollidablePlane: Quad, PlanePhysicsEntity {
    var collisionNormal: float3 = [0, 1, 0]
//    var collisionShape: CollisionShape = .Plane
}

final class CollidableF22: F22, SpherePhysicsEntity {
    var collisionRadius: Float = 1.0
}
