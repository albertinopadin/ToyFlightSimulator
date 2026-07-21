//
//  AircraftColliderSpec.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/19/26.
//

/// Compound collider specs per player-selectable aircraft. Authored in MODEL
/// units; the node's uniform scale (3.0 for F22_CGTrader in FlightboxWithPhysics)
/// converts to world meters at runtime — see the units contract in
/// plans/claude/compound_rigid_bodies_implementation_plan.md (step 0.5).
/// Numbers are PLACEHOLDERS until tuned with the X-key debug overlay.
enum AircraftColliderSpec {
    static func spec(for type: AircraftType) -> [LocalCollider] {
        switch type {
            case .f22_cgtrader: return f22CGTrader
            default:            return []   // authored when each aircraft gets its Phase A body
        }
    }

    /// From research/claude/compound_rigid_bodies_research_2026-07-14.md §2.3
    /// (three primitives ≈ the whole airframe).
    private static let f22CGTrader: [LocalCollider] = [
        LocalCollider(name: "fuselage",
                      shape: .capsule(radius: 0.45, halfHeight: 2.4),
                      localPosition: [0, 0.10, 0.20],
                      // Capsule axis is local Y; rotate Y→Z so it runs nose–tail.
                      localRotation: simd_quatf(angle: .halfPi, axis: X_AXIS),
                      group: .airframe),
        LocalCollider(name: "wings",
                      shape: .box(halfExtents: [2.2, 0.06, 0.9]),
                      localPosition: [0, 0.05, -0.4],
                      group: .airframe),
        LocalCollider(name: "empennage",
                      shape: .box(halfExtents: [1.0, 0.45, 0.5]),
                      localPosition: [0, 0.35, -2.2],
                      group: .airframe)
    ]
}
