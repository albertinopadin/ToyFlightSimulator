//
//  PhysicsEntity.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/31/24.
//

import Foundation

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
    
    func setPosition(_ position: float3)
    func getPosition() -> float3
}

extension PhysicsEntity {
    var id: String { UUID().uuidString }
    
    static func ==(lhs: PhysicsEntity, rhs: PhysicsEntity) -> Bool {
        return lhs.id == rhs.id
    }
    
    mutating func reset() {
        collidedWith.removeAll()
    }
}

protocol SpherePhysicsEntity: PhysicsEntity {
    var collisionRadius: Float { get set }
}

//extension SpherePhysicsEntity {
//    var collisionShape: CollisionShape { .Sphere }
//}

protocol PlanePhysicsEntity: PhysicsEntity {
    var collisionNormal: float3 { get set }
}

//extension PlanePhysicsEntity {
//    var collisionShape: CollisionShape { .Plane }
//}

