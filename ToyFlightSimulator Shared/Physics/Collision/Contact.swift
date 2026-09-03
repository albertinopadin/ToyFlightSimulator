//
//  Contact.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/30/26.
//

/// One contact produced by the narrow phase.
struct Contact {
    /// Unit length, from B toward A.
    let normal: float3
    let depth: Float
    /// World-space contact point. Unused by the linear response; kept for
    /// angular dynamics later.
    let point: float3
    /// nil for a simple body: a SphereRigidBody's view or the infinite plane.
    let colliderNameA: String?
    let colliderGroupA: ColliderGroup?
    let colliderNameB: String?
    let colliderGroupB: ColliderGroup?

    /// The same contact with A and B swapped.
    var flipped: Contact {
        Contact(normal: -normal, depth: depth, point: point,
                colliderNameA: colliderNameB, colliderGroupA: colliderGroupB,
                colliderNameB: colliderNameA, colliderGroupB: colliderGroupA)
    }
}

extension Contact {
    /// Contact from the colliders that produced it. Either may be nil: the
    /// plane side, or a legacy sphere's view, which has no name or group.
    init(normal: float3, depth: Float, point: float3,
         collider a: WorldCollider? = nil, against b: WorldCollider? = nil) {
        self.init(normal: normal, depth: depth, point: point,
                  colliderNameA: a?.name, colliderGroupA: a?.group,
                  colliderNameB: b?.name, colliderGroupB: b?.group)
    }
}
