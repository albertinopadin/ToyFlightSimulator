//
//  ColliderShape.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/19/26.
//

import simd

/// Convex collision primitives, cheapest first. Dimensions are authored in
/// the model's local space and scaled by the GameObject's uniform scale when
/// world colliders are built.
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

    /// Debug validation: every dimension finite and > 0. A capsule halfHeight
    /// of 0 is allowed — that's a legal sphere-equivalent.
    var hasFinitePositiveDimensions: Bool {
        switch self {
            case .sphere(radius: let r):
                return r.isFinite && r > 0
            case .capsule(radius: let r, halfHeight: let hh):
                return r.isFinite && r > 0 && hh.isFinite && hh >= 0
            case .box(halfExtents: let he):
                return he.x.isFinite && he.x > 0
                    && he.y.isFinite && he.y > 0
                    && he.z.isFinite && he.z > 0
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

/// One primitive rigidly attached to a body at a local offset: the per-child
/// entry of a compound.
struct LocalCollider {
    var name: String
    var shape: ColliderShape
    var localPosition: float3
    var localRotation: simd_quatf
    var group: ColliderGroup
    /// Runtime on/off. Disabled colliders generate no contacts, do not
    /// contribute to the AABB, and the debug overlay skips them.
    var isEnabled: Bool

    init(name: String,
         shape: ColliderShape,
         localPosition: float3 = .zero,
         localRotation: simd_quatf = .identity,
         group: ColliderGroup = .airframe,
         isEnabled: Bool = true) {
        assert(shape.hasFinitePositiveDimensions,
               "Collider '\(name)' has non-finite or non-positive dimensions: \(shape)")
        self.name = name
        self.shape = shape
        self.localPosition = localPosition
        self.localRotation = localRotation
        self.group = group
        self.isEnabled = isEnabled
    }
}

/// A LocalCollider in world space for one narrow-phase query. Read it from
/// RigidBody.worldColliders(); do not keep it across steps, the backing array
/// is reused.
struct WorldCollider {
    let shape: ColliderShape        // dimensions already × uniformScale
    let position: float3            // world center
    let rotation: float3x3          // world orientation (orthonormal)
    /// Identity of the authored LocalCollider. nil for the view of a
    /// SphereRigidBody, which has no authored collider.
    let sourceIndex: Int?
    let name: String?
    let group: ColliderGroup?

    /// World-axis-aligned bounds (broad-phase input; compound AABB = union).
    var aabb: AABB {
        switch shape {
            case .sphere(radius: let r):
                return AABB(center: position, radius: r)
            case .capsule(radius: let r, halfHeight: let hh):
                // Endpoints sit at position ± axis·hh (axis = columns.1, the
                // world direction of local Y); the segment's reach along each
                // world axis is |axis·hh|, then inflate by r on every axis.
                let axisExtent = abs(rotation.columns.1 * hh)
                return AABB(center: position, halfExtents: axisExtent + float3(repeating: r))
            case .box(halfExtents: let he):
                // World-axis extents of an oriented box: |R|·he, each column
                // of R being one box axis in world space.
                let extents = abs(rotation.columns.0) * he.x
                            + abs(rotation.columns.1) * he.y
                            + abs(rotation.columns.2) * he.z
                return AABB(center: position, halfExtents: extents)
        }
    }
}

/// Pure LocalCollider × body pose → WorldCollider, kept free of RigidBody and
/// Node so it is testable without Metal. The offset order,
/// rotate(localPosition × scale), matches the overlay's scene-graph
/// composition.
enum WorldColliderBuilder {
    /// Appends the world snapshot of every enabled collider into `out`
    /// (cleared first, capacity kept).
    static func build(_ colliders: [LocalCollider],
                      bodyPosition: float3,
                      bodyRotation: float3x3,
                      uniformScale: Float,
                      into out: inout [WorldCollider]) {
        out.removeAll(keepingCapacity: true)
        for (index, collider) in colliders.enumerated() where collider.isEnabled {
            out.append(WorldCollider(shape: collider.shape.scaled(by: uniformScale),
                                     position: bodyPosition + bodyRotation * (collider.localPosition * uniformScale),
                                     rotation: bodyRotation * float3x3(collider.localRotation),
                                     sourceIndex: index,
                                     name: collider.name,
                                     group: collider.group))
        }
    }
}
