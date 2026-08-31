//
//  CollisionResponseTests.swift
//  ToyFlightSimulatorTests
//
//  A.8 (A-response track): the semantic pins research §4.7 asked for. Every
//  assertion here holds for the CORRECTED response and would have failed
//  under the legacy one (rest latch, minDeltaVelo discard, separating-contact
//  impulses, ×2 corrections, the Euler per-axis reflection). Metal-free —
//  detached bodies stepped through real PhysicsWorlds.
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Corrected contact response", .tags(.physics))
struct CollisionResponseTests {
    private static let dt: Float = 1.0 / 60.0

    private func makeRestingWorld(updateType: PhysicsUpdateType = .HeckerVerlet)
        -> (world: PhysicsWorld, ball: SphereRigidBody) {
        let ball = SphereRigidBody(detachedAt: [0, 0.499, 0], collisionRadius: 0.5)
        ball.restitution = 0.2
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true
        let world = PhysicsWorld(entities: [ball, plane], updateType: updateType)
        world.useBroadPhase = false
        return (world, ball)
    }

    @Test("resting body keeps gravity on forever (the latch regression)")
    func restingKeepsGravity() {
        let (world, ball) = makeRestingWorld()
        for _ in 0..<600 { world.update(deltaTime: Self.dt) }
        #expect(ball.shouldApplyGravity)
        // β-equilibrium ≈ slop + per-step-sink/β ≈ 1–2 cm at 60 Hz; loose
        // bound on purpose. Observed at the 2026-08-31 regolden (rest_latch
        // golden, same setup): y ≈ 0.488, |v| ≈ 0.1635 (exactly g·dt).
        #expect(abs(ball.getPosition().y - 0.5) <= 0.03)
        #expect(simd_length(ball.velocity) <= 0.25)             // ≤ ~one gravity step
    }

    @Test("a pushed resting body still falls afterward (old latch made it float away)")
    func pushedRestingBodyStillFalls() {
        let (world, ball) = makeRestingWorld()
        for _ in 0..<300 { world.update(deltaTime: Self.dt) }   // settle
        ball.velocity = [0, 3, 0]                               // pop it upward
        for _ in 0..<240 { world.update(deltaTime: Self.dt) }   // 4 s: up ≈ 0.46 m and back
        #expect(ball.shouldApplyGravity)
        #expect(ball.getPosition().y <= 0.6, "gravity must bring it back down")
    }

    @Test("no impulse on separating contacts (legacy applied one, adding energy)")
    func separatingContactGetsNoImpulse() {
        let a = SphereRigidBody(detachedAt: [0, 0, 0], collisionRadius: 0.5)
        a.velocity = [0, 5, 0]
        a.shouldApplyGravity = false
        let b = SphereRigidBody(detachedAt: [0, -0.9, 0], collisionRadius: 0.5)
        b.velocity = [0, -5, 0]
        b.shouldApplyGravity = false
        let world = PhysicsWorld(entities: [a, b], updateType: .HeckerVerlet)
        world.useBroadPhase = false
        world.update(deltaTime: Self.dt)
        // Overlapping (depth 0.1) but separating: position correction may act,
        // velocities must not change (gravity off ⇒ integration is exact too).
        #expect(approxEqual(a.velocity, [0, 5, 0]))
        #expect(approxEqual(b.velocity, [0, -5, 0]))
    }

    @Test("below the restitution threshold even e=1 does not bounce")
    func noBounceBelowThreshold() {
        // 3 cm drop ⇒ impact ≈ 0.77 m/s < 1 m/s ⇒ e forced to 0.
        let ball = SphereRigidBody(detachedAt: [0, 0.53, 0], collisionRadius: 0.5)
        ball.restitution = 1.0
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true
        let world = PhysicsWorld(entities: [ball, plane], updateType: .HeckerVerlet)
        world.useBroadPhase = false
        var maxYAfterContact: Float = 0
        var touched = false
        for _ in 0..<180 {
            world.update(deltaTime: Self.dt)
            let y = ball.getPosition().y
            if y < 0.5 { touched = true }
            if touched { maxYAfterContact = max(maxYAfterContact, y) }
        }
        #expect(touched)
        #expect(maxYAfterContact <= 0.52, "sub-threshold impact must settle, not bounce")
    }

    @Test("above the restitution threshold it bounces at ≈ e·impact")
    func bouncesAboveThreshold() {
        // 2 m drop ⇒ impact ≈ 6.3 m/s; e = 0.5 ⇒ apex ≈ e²·h = 0.5 m above rest.
        let ball = SphereRigidBody(detachedAt: [0, 2.5, 0], collisionRadius: 0.5)
        ball.restitution = 0.5
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true
        let world = PhysicsWorld(entities: [ball, plane], updateType: .HeckerVerlet)
        world.useBroadPhase = false
        var touched = false
        var apexAfterBounce: Float = 0
        for _ in 0..<240 {
            world.update(deltaTime: Self.dt)
            let y = ball.getPosition().y
            if y < 0.55 { touched = true }
            if touched { apexAfterBounce = max(apexAfterBounce, y) }
        }
        #expect(touched)
        #expect(apexAfterBounce >= 0.8 && apexAfterBounce <= 1.15,
                "first rebound apex ≈ 0.5 + e²·2.0 = 1.0 m (window absorbs correction losses)")
    }

    @Test("dynamic pair splits the position correction by inverse mass")
    func correctionSplitsByInverseMass() {
        // Pure-overlap pair at rest, gravity off: only the correction acts.
        // mass 1 vs mass 3 ⇒ displacement magnitudes 3 : 1, moving apart.
        let a = SphereRigidBody(detachedAt: [0, 0, 0], collisionRadius: 0.5)
        a.mass = 1
        a.shouldApplyGravity = false
        let b = SphereRigidBody(detachedAt: [0.9, 0, 0], collisionRadius: 0.5)
        b.mass = 3
        b.shouldApplyGravity = false
        let world = PhysicsWorld(entities: [a, b], updateType: .HeckerVerlet)
        world.useBroadPhase = false
        world.update(deltaTime: Self.dt)
        let movedA = -a.getPosition().x          // A pushed toward −x (n = B→A = −x̂)
        let movedB = b.getPosition().x - 0.9     // B pushed toward +x
        #expect(movedA > 0 && movedB > 0, "correction separates the pair")
        #expect(approxEqual(movedA / movedB, 3.0, tolerance: 1e-3))
    }

    @Test("the Euler path rests too (the reflection hack is gone)")
    func eulerPathRests() {
        let (world, ball) = makeRestingWorld(updateType: .NaiveEuler)
        for _ in 0..<300 { world.update(deltaTime: Self.dt) }
        #expect(ball.shouldApplyGravity)
        #expect(abs(ball.getPosition().y - 0.5) <= 0.03)
        #expect(simd_length(ball.velocity) <= 0.25)
    }
}
