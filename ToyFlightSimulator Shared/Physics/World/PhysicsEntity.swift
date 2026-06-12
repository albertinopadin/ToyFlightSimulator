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

/// Contract for anything that participates in the physics simulation.
/// AnyObject-constrained: entities are reference types, so solvers mutate
/// them through the reference (no inout/existential writeback needed).
protocol PhysicsEntity: AnyObject {
    var collisionShape: CollisionShape { get set }
    /// Identities of entities already collided with this step.
    /// ObjectIdentifier == the entity's address: free to obtain, hashes as a
    /// single word, valid for the entity's lifetime (reset every step anyway).
    var collidedWith: Set<ObjectIdentifier> { get set }

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
    func resetCollisions() {
        collidedWith.removeAll(keepingCapacity: true)
    }

    func zeroForce() {
        force = .zero
    }

    // Computed property for dynamic check (inverse of static)
    var isDynamic: Bool {
        return !isStatic
    }
}
