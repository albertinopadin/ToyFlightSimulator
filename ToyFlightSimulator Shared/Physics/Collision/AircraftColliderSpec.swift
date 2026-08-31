//
//  AircraftColliderSpec.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 7/19/26.
//

/// Compound collider specs per player-selectable aircraft. Authored in
/// post-import engine-local units, which meterization makes METERS (import
/// folds `realWorldLength / nativeLength` into the basis transform — see
/// ModelLibrary.makeLibrary()). Aircraft run at scale 1.0, so world meters
/// = spec meters × uniformScale = spec meters; `uniformScale` stays in the
/// world-collider math only as an optional gameplay multiplier — see the
/// units contract in plans/claude/compound_rigid_bodies_implementation_plan.md
/// (step 0.5). Numbers overlay-verified in-app 2026-08-29 (Phase 0 exit
/// criterion 2); now LIVE physics geometry (FlightboxWithPhysics installs the
/// spec on the player aircraft's RigidBody) — re-run the X-key overlay after
/// any edit.
enum AircraftColliderSpec {
    /// Exhaustive over AircraftType with no `default` (same convention as
    /// SceneManager's registration switches): adding an aircraft forces a
    /// conscious authored-or-empty decision here at compile time.
    static func spec(for type: AircraftType) -> [LocalCollider] {
        switch type {
            case .f22_cgtrader:
                return f22CGTrader
            case .f16, .f18, .f22, .f35:
                return []   // authored when each aircraft gets its Phase A body
        }
    }

    /// From research/claude/compound_rigid_bodies_research_2026-07-14.md §2.3
    /// (three primitives ≈ the whole airframe). Real F-22: length 18.92 m,
    /// wingspan 13.56 m.
    private static let f22CGTrader: [LocalCollider] = [
        LocalCollider(name: "fuselage",
                      // Total 2·(8.1 + 1.35) = 18.9 m — spans nose→tail (real 18.92 m).
                      shape: .capsule(radius: 1.35, halfHeight: 8.1),
                      localPosition: [0, 0.3, 0.6],
                      // Capsule axis is local Y; rotate Y→Z so it runs nose–tail.
                      localRotation: simd_quatf(angle: .halfPi, axis: X_AXIS),
                      group: .airframe),
        LocalCollider(name: "wings",
                      // 13.2 m span vs 13.56 m real wingspan.
                      shape: .box(halfExtents: [6.6, 0.18, 2.7]),
                      localPosition: [0, 0.15, -1.2],
                      group: .airframe),
        LocalCollider(name: "empennage",
                      shape: .box(halfExtents: [3.0, 1.35, 1.5]),
                      localPosition: [0, 1.05, -6.6],
                      group: .airframe)
    ]
}
