//
//  ColliderShape.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/19/26.
//

import simd

/// Reserved per-collider surface override (combined doc, minor-differences
/// table): friction / restitution per collider arrive with tangent friction in
/// Phase D. Until then body-level restitution applies and NOTHING reads this —
/// it exists so authored specs don't churn when Phase D lands.
struct PhysicsMaterial: Equatable {
    var friction: Float = 0.5
    /// nil ⇒ inherit the body's restitution.
    var restitution: Float? = nil
}

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
    /// Reserved: per-collider friction/restitution override (Phase D).
    /// Body-level restitution applies until then.
    var material: PhysicsMaterial?

    init(name: String,
         shape: ColliderShape,
         localPosition: float3 = .zero,
         localRotation: simd_quatf = .identity,
         group: ColliderGroup = .airframe,
         isEnabled: Bool = true,
         material: PhysicsMaterial? = nil) {
        assert(shape.hasFinitePositiveDimensions,
               "Collider '\(name)' has non-finite or non-positive dimensions: \(shape)")
        self.name = name
        self.shape = shape
        self.localPosition = localPosition
        self.localRotation = localRotation
        self.group = group
        self.isEnabled = isEnabled
        self.material = material
    }
}

/// A LocalCollider transformed into world space for one narrow-phase query.
/// Derived and read-only (research §3.4: LocalCollider = authored spec,
/// WorldCollider = per-step snapshot). Obtain via RigidBody.worldColliders();
/// never store across steps — the backing array is reused scratch.
struct WorldCollider {
    let shape: ColliderShape        // dimensions already × uniformScale
    let position: float3            // world center
    let rotation: float3x3          // world orientation (orthonormal)
    /// Identity of the authored LocalCollider. All three are nil for the
    /// synthesized view of a legacy body-level shape (SphereRigidBody), which
    /// is what keeps Contact's "nil for simple bodies" contract truthful.
    let sourceIndex: Int?
    let name: String?
    let group: ColliderGroup?

    /// World-axis-aligned bounds (broad-phase input; compound AABB = union).
    var aabb: AABB {
        switch shape {
            case .sphere(radius: let r):
                return AABB(center: position, radius: r)
            case .capsule(radius: let r, halfHeight: let hh):
                // A capsule is a segment with ball ends: endpoints sit at
                // position ± axis·hh, where axis = rotation.columns.1 (the
                // world direction of the local Y the capsule is defined
                // along). The segment's reach from the center along each
                // WORLD axis is the endpoint offset's per-component
                // magnitude, |axis·hh| — e.g. its reach along world X is
                // |axis.x|·hh. Then inflate by r on all three axes, because
                // every surface point lies within r of the segment.
                let axisExtent = abs(rotation.columns.1 * hh)
                return AABB(center: position, halfExtents: axisExtent + float3(repeating: r))
            case .box(halfExtents: let he):
                // World-axis extents of an oriented box: |R|·he. Each column
                // of R is one box axis in world space, and the box reaches
                // ±he[i] along its axis i — so its reach along, say, world X
                // is the sum of what the three half-axis vectors contribute
                // there: |c0.x|·he.x + |c1.x|·he.y + |c2.x|·he.z. The three
                // abs(column)·he terms compute that for all world axes at
                // once, component-wise.
                let extents = abs(rotation.columns.0) * he.x
                            + abs(rotation.columns.1) * he.y
                            + abs(rotation.columns.2) * he.z
                return AABB(center: position, halfExtents: extents)
        }
    }
}

/// Pure LocalCollider × body-pose → WorldCollider transform. Kept free of
/// RigidBody/Node so the math is unit-testable Metal-free (the attached-body
/// wrapper in RigidBody.rebuildWorldColliders is three lines of state
/// gathering around this). The offset transform order — rotate(localPosition
/// × scale) — matches the debug overlay's scene-graph composition, so physics
/// and the rendered volumes agree by construction.
enum WorldColliderBuilder {
    /// Appends the world snapshot of every ENABLED collider into `out`
    /// (cleared first, capacity kept — reused-scratch discipline).
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
