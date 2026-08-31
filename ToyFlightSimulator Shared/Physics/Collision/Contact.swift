//
//  Contact.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/30/26.
//

/// One collision contact produced by the narrow phase.
/// `normal` is unit length and points from B toward A — the direction that
/// separates A. NOTE: this is a STRICT convention; the legacy code's normal
/// was shape-dependent (sphere-plane pairs always carried the plane's normal,
/// whichever side the plane was on). The A-routing response transcription
/// accounts for the difference explicitly — see the sign-symmetry note there.
struct Contact {
    let normal: float3
    let depth: Float
    /// Representative world-space contact point. Unused by the linear-only
    /// response; populated from day one so it becomes the lever arm when
    /// angular dynamics land (combined doc D2 prep).
    let point: float3
    /// Sub-collider names/groups for compound bodies (nil for simple bodies —
    /// a legacy sphere's synthesized view and the infinite plane carry no
    /// collider identity).
    let colliderNameA: String?
    let colliderGroupA: ColliderGroup?
    let colliderNameB: String?
    let colliderGroupB: ColliderGroup?

    /// Geometry + metadata from the colliders that produced the contact
    /// (either may be nil: plane side, or a legacy body-level shape's view —
    /// whose own metadata fields are nil anyway, and optional chaining
    /// flattens them straight through).
    init(normal: float3, depth: Float, point: float3, collider a: WorldCollider? = nil, against b: WorldCollider? = nil) {
        self.normal = normal
        self.depth = depth
        self.point = point
        self.colliderNameA = a?.name
        self.colliderGroupA = a?.group
        self.colliderNameB = b?.name
        self.colliderGroupB = b?.group
    }
    
    private init (normal: float3,
                  depth: Float,
                  point: float3,
                  colliderNameA: String?,
                  colliderGroupA: ColliderGroup?,
                  colliderNameB: String?,
                  colliderGroupB: ColliderGroup?) {
        self.normal = normal
        self.depth = depth
        self.point = point
        self.colliderNameA = colliderNameA
        self.colliderGroupA = colliderGroupA
        self.colliderNameB = colliderNameB
        self.colliderGroupB = colliderGroupB
    }
    
    /// The same contact expressed with A and B swapped.
    var flipped: Contact {
        Contact(normal: -normal,
                depth: depth,
                point: point,
                colliderNameA: colliderNameB,
                colliderGroupA: colliderGroupB,
                colliderNameB: colliderNameA,
                colliderGroupB: colliderGroupA)
    }
}
