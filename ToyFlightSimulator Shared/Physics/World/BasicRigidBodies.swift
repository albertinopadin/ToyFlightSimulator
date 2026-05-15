//
//  BasicRigidBodies.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/14/26.
//

public final class SphereRigidBody: RigidBody {
    var collisionRadius: Float = 1.0
    
    init(gameObject: GameObject, collisionRadius: Float = 1.0) {
        super.init(gameObject: gameObject)
        self.collisionRadius = collisionRadius
        self.collisionShape = .Sphere
    }
    
    // Default AABB implementation for spheres
    override func getAABB() -> AABB {
        return AABB(center: getPosition(), radius: collisionRadius)
    }
}

public final class PlaneRigidBody: RigidBody {
    var collisionNormal: float3 = [0, 1, 0]
    
    init(gameObject: GameObject, collisionNormal: float3 = [0, 1, 0]) {
        super.init(gameObject: gameObject)
        self.collisionNormal = collisionNormal
        self.collisionShape = .Plane
    }
    
    // Default AABB implementation for planes
    // Using a large box to represent an "infinite" plane
    override func getAABB() -> AABB {
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
