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
    /// Reach of the plane's broad-phase box along its two in-plane axes, in
    /// meters: the box runs from −unboundedExtent to +unboundedExtent in world
    /// coordinates there, wherever the plane's node is.
    ///
    /// Not centred on the node: the ground is a direct child of the scene, so
    /// the floating origin moves its node on every shift, and after a long
    /// flight the node can be any distance from the aircraft. A box centred on
    /// the node (it used to reach 10 km either side) then stops pairing the
    /// airframe with the ground. Only the offset along the normal locates the
    /// plane, and that one stays on the node (the 1 m slab in getAABB).
    ///
    /// Not .infinity: AABB.center is (min + max) / 2, and −∞ + ∞ is NaN.
    /// The value is Bullet's BT_LARGE_FLOAT for single precision
    /// (src/LinearMath/btScalar.h), chosen there so its square, 1e36, stays
    /// below Float.greatestFiniteMagnitude (3.4e38). Bullet's
    /// btStaticPlaneShape::getAabb returns ±BT_LARGE_FLOAT on all three axes;
    /// getAABB here keeps a thin slab along the normal instead, so a body far
    /// above the ground is not paired with it.
    static let unboundedExtent: Float = 1e18
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
    
    /// Broad-phase box of the infinite plane: ±unboundedExtent along the two
    /// in-plane axes, and a 2 m slab (the node's coordinate ± 1 m) along the
    /// axis the normal is closest to.
    ///
    /// Known limitation: the slab is exact only for an axis-aligned normal.
    /// A tilted plane leaves its slab away from the node, and a normal with no
    /// component above 0.9 lands in the last (±Z) branch. Every scene's ground
    /// uses (0, 1, 0).
    override func getAABB() -> AABB {
        let position = getPosition()
        
        // Create a thin but wide AABB based on the plane's normal
        if abs(collisionNormal.y) > 0.9 {
            // Horizontal plane (normal points up/down)
            return AABB(
                min: float3(-Self.unboundedExtent, position.y - 1.0, -Self.unboundedExtent),
                max: float3(Self.unboundedExtent, position.y + 1.0, Self.unboundedExtent)
            )
        } else if abs(collisionNormal.x) > 0.9 {
            // Vertical plane (normal points left/right)
            return AABB(
                min: float3(position.x - 1.0, -Self.unboundedExtent, -Self.unboundedExtent),
                max: float3(position.x + 1.0, Self.unboundedExtent, Self.unboundedExtent)
            )
        } else {
            // Vertical plane (normal points forward/back)
            return AABB(
                min: float3(-Self.unboundedExtent, -Self.unboundedExtent, position.z - 1.0),
                max: float3(Self.unboundedExtent, Self.unboundedExtent, position.z + 1.0)
            )
        }
    }
}
