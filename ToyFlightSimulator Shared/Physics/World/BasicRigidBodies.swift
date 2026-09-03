//
//  BasicRigidBodies.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/14/26.
//

public final class SphereRigidBody: RigidBody {
    var collisionRadius: Float = 1.0 {
        didSet { invalidateWorldColliders() }
    }
    
    init(gameObject: GameObject, collisionRadius: Float = 1.0) {
        super.init(gameObject: gameObject)
        self.collisionRadius = collisionRadius
    }

    init(detachedAt position: float3, collisionRadius: Float = 1.0) {
        super.init(gameObject: nil, standalonePosition: position)
        self.collisionRadius = collisionRadius
    }
    
    // Same box as the base union over the one-sphere view, without the
    // rebuild.
    override func getAABB() -> AABB {
        return AABB(center: getPosition(), radius: collisionRadius)
    }

    /// One-sphere world view so the narrow phase has a single collider-based
    /// path. collisionRadius is world meters, so node scale is not applied;
    /// name and group are nil. `colliders` is ignored on this class: a
    /// compound body is a plain RigidBody.
    override internal func rebuildWorldColliders() {
        assert(colliders.isEmpty, "SphereRigidBody ignores `colliders` — use a plain RigidBody for compounds")
        
        worldCollidersScratch.removeAll(keepingCapacity: true)
        worldCollidersScratch.append(WorldCollider(shape: .sphere(radius: collisionRadius),
                                                   position: getPosition(),
                                                   rotation: matrix_identity_float3x3,
                                                   sourceIndex: nil,
                                                   name: nil,
                                                   group: nil))
    }
}

public final class PlaneRigidBody: RigidBody {
    var collisionNormal: float3 = [0, 1, 0]
    
    init(gameObject: GameObject, collisionNormal: float3 = [0, 1, 0]) {
        super.init(gameObject: gameObject)
        // Normalize once at init so collision response can use the normal
        // directly without re-normalizing per contact.
        self.collisionNormal = collisionNormal.normalize()
    }

    init(detachedAt position: float3, collisionNormal: float3 = [0, 1, 0]) {
        super.init(gameObject: nil, standalonePosition: position)
        self.collisionNormal = collisionNormal.normalize()
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
