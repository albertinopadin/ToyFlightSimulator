//
//  CompoundBodyTests.swift
//  ToyFlightSimulatorTests
//
//  A.8 (A-aircraft track): the LIVE F-22 spec driving the full pipeline —
//  broad-phase AABB union → collider narrow phase → corrected response —
//  Metal-free via the 0.6 detached machinery (a plain detached RigidBody
//  carrying the real spec IS the aircraft's collision body, minus the node).
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Compound body integration", .tags(.physics))
struct CompoundBodyTests {
    private static let dt: Float = 1.0 / 60.0

    /// The live F-22 spec on a detached body settles on its fuselage capsule:
    /// lowest surface = localPosition.y − radius = 0.3 − 1.35 = −1.05, so the
    /// body origin rests at ≈ +1.05 (minus the β-equilibrium residual). The
    /// legacy sphere rested at 2.0 — this pins the compound actually driving
    /// the response, end to end (broad phase AABB union → narrow phase →
    /// corrected response), and pins WHICH collider carries the contact.
    @Test("F-22 compound settles on the fuselage capsule, reported by name")
    func f22CompoundSettlesOnFuselage() {
        let body = RigidBody(detachedAt: [0, 5, 0])
        body.colliders = AircraftColliderSpec.spec(for: .f22_cgtrader)
        body.restitution = 0.2
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true
        let world = PhysicsWorld(entities: [body, plane], updateType: .HeckerVerlet)
        world.useBroadPhase = false

        var contactNames: Set<String> = []
        body.onContact = { contact, _ in
            if let name = contact.colliderNameA { contactNames.insert(name) }
        }

        for _ in 0..<600 { world.update(deltaTime: Self.dt) }

        #expect(body.shouldApplyGravity)
        #expect(simd_length(body.velocity) <= 0.25)
        let restY = body.getPosition().y
        #expect(abs(restY - 1.05) <= 0.05,
                "origin should rest ≈ 1.05 (fuselage capsule bottom), not the sphere's 2.0")
        #expect(contactNames == ["fuselage"],
                "level settle touches the fuselage only — wings/empennage sit higher")
    }

    /// A 90°-banked pose contacts the plane with the WINGS alone — the
    /// wingtip-strike identity the 2 m sphere could never report. Pure
    /// geometry (WorldColliderBuilder + shapeVsPlane), no stepping: detached
    /// bodies can't rotate, and this needs no world — which also makes it the
    /// direct unit pin for rotated compound poses.
    @Test("banked 90°, only the wings box reaches the ground, by name")
    func bankedPoseContactsWingsOnly() {
        let spec = AircraftColliderSpec.spec(for: .f22_cgtrader)
        let roll90 = float3x3(simd_quatf(angle: .halfPi, axis: Z_AXIS))
        var worlds: [WorldCollider] = []
        WorldColliderBuilder.build(spec,
                                   bodyPosition: [0, 5, 0],
                                   bodyRotation: roll90,
                                   uniformScale: 1.0,
                                   into: &worlds)

        var touching: [String] = []
        for collider in worlds {
            if let contact = NarrowPhase.shapeVsPlane(collider,
                                                      planePoint: .zero,
                                                      planeNormal: [0, 1, 0]) {
                touching.append(contact.colliderNameA ?? "?")
                // Rolled wings: half-span 6.6 projects fully onto the plane
                // normal → depth = 6.6 − (5 + rotated local offset) ≈ 1.6.
                #expect(contact.depth > 1.0 && contact.depth < 2.5)
            }
        }
        #expect(touching == ["wings"],
                "at 5 m banked 90°, fuselage (r 1.35) and empennage (3.0 span) stay clear")
    }
}
