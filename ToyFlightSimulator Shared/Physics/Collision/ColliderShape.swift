//
//  ColliderShape.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/19/26.
//

import simd

/// Convex collision primitives, in the cost order every surveyed engine
/// documents (sphere < capsule < box). Dimensions are authored in the owning
/// model's local space and scaled by the GameObject's uniform scale when
/// world-space colliders are computed.
enum ColliderShape: Equatable {
    /// Ball of the given radius.
    case sphere(radius: Float)
    /// Segment along local Y from -halfHeight to +halfHeight, inflated by
    /// radius (total height = 2·(halfHeight + radius)). Orient with the
    /// collider's localRotation (e.g. Y→Z for a fuselage along +Z).
    case capsule(radius: Float, halfHeight: Float)
    /// Oriented box with the given half extents.
    case box(halfExtents: float3)
    
    func scaled(by s: Float) -> ColliderShape {
        switch self {
            case .sphere(radius: let r):
                return .sphere(radius: r * s)
            case .capsule(radius: let r, halfHeight: let hh):
                return .capsule(radius: r * s, halfHeight: hh * s)
            case .box(halfExtents: let he):
                return .box(halfExtents: he * s)
        }
    }
}

/// Which functional part of the object a collider represents, so contact
/// consumers (crash detection, landing logic) can tell a wheel strike from
/// a belly strike without geometry queries.
enum ColliderGroup {
    case airframe      // fuselage/wings/tail — contact here means structural impact
    case landingGear   // reserved for future wheel colliders (suspension covers ground contact)
    case structure     // buildings, towers, scenery
}

/// One primitive rigidly attached to a body at a local offset — the per-child
/// entry of a compound (Bullet btCompoundShape child, Unity child collider,
/// Jolt compound sub-shape).
struct LocalCollider {
    var name: String
    var shape: ColliderShape
    var localPosition: float3
    var localRotation: simd_quatf
    var group: ColliderGroup
    /// Cheap runtime on/off (Jolt MutableCompoundShape's role). Disabled
    /// colliders generate no contacts, don't contribute to the AABB, and the
    /// debug overlay skips them.
    var isEnabled: Bool
    
    init(name: String,
         shape: ColliderShape,
         localPosition: float3 = .zero,
         localRotation: simd_quatf = .identity,
         group: ColliderGroup = .airframe,
         isEnabled: Bool = true) {
        self.name = name
        self.shape = shape
        self.localPosition = localPosition
        self.localRotation = localRotation
        self.group = group
        self.isEnabled = isEnabled
    }
}
