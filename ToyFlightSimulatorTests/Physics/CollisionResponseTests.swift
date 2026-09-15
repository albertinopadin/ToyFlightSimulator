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

    // MARK: - Lever-arm impulse (D.1, D-angular-plumbing)

    /// A hand-built contact straight into applyImpulse, no narrow phase: A at
    /// the origin, mass 2, falling at 1 m/s onto a static plane, the contact
    /// 1 m off-axis at [1, 0, 0] with the normal up. The lever arm
    /// r = [1, 0, 0] is perpendicular to n, so with I⁻¹ = diag(0.5) the
    /// angular term equals the linear one.
    private func makeOffAxisContact() -> (a: RigidBody, plane: PlaneRigidBody, contact: Contact) {
        let a = RigidBody(detachedAt: .zero)
        a.mass = 2
        a.velocity = [0, -1, 0]
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true
        let contact = Contact(normal: [0, 1, 0], depth: 0, point: [1, 0, 0])
        return (a, plane, contact)
    }

    @Test("finite inertia: the impulse splits between the origin and the spin — j = 1, v = [0, −0.5, 0], ω = [0, 0, 0.5], exact")
    func leverArmImpulseSplitsLinearAndAngular() {
        let (a, plane, contact) = makeOffAxisContact()
        a.inverseInertiaLocal = float3x3(diagonal: [0.5, 0.5, 0.5])
        let stats = HeckerCollisionResponse.getInverseMassStats(a, plane)
        #expect(stats.inverseMassA == 0.5)
        #expect(stats.inverseMassB == 0, "a static body has inverse mass 0")
        #expect(stats.inverseMassSum == 0.5)

        HeckerCollisionResponse.applyImpulse(a, plane, contact: contact, inverseMassStats: stats)

        // approach = −1 m/s, at exactly the 1 m/s threshold ⇒ e = 0. Angular
        // term ((I⁻¹ (r × n)) × r) · n = 0.5, denominator 0.5 + 0.5 = 1, so
        // j = 1. Linear: j/m = 0.5 up. Angular: I⁻¹ (r × j n) = 0.5 · [0, 0, 1].
        #expect(a.velocity == [0, -0.5, 0])
        #expect(a.angularVelocity == [0, 0, 0.5])
        #expect(plane.velocity == .zero)
        #expect(plane.angularVelocity == .zero, "statics never change")
        // The contact point itself is at rest along n: −0.5 from the origin,
        // +0.5 from ω × r.
        #expect(dot(a.velocity(atWorldPoint: contact.point), contact.normal) == 0)
    }

    @Test("infinite inertia: the same contact gives the point-mass result — the origin stops, nothing spins, exact")
    func infiniteInertiaTakesThePointMassPath() {
        let (a, plane, contact) = makeOffAxisContact()
        let stats = HeckerCollisionResponse.getInverseMassStats(a, plane)

        HeckerCollisionResponse.applyImpulse(a, plane, contact: contact, inverseMassStats: stats)

        // Linear fast path: j = −(1 + 0)(−1) / 0.5 = 2; v += n · (2 · 0.5).
        // The off-axis point is irrelevant: a point mass has no lever arm.
        #expect(a.velocity == .zero)
        #expect(a.angularVelocity == .zero)
    }

    // MARK: - Pair solve (D.3, D-attitude)

    @Test("two caps converge: eight passes bring both cap points to rest where one pass leaves the first approaching again, and no accumulated impulse is negative")
    func twoCapsConverge() {
        // The F-22 belly rest as two hand-built contacts: 30 t with its
        // tensor at [0, 1.05, 0] sinking at 0.5 m/s, the fuselage capsule's
        // cap feet at z −7.5 and 8.7. The lever arms dominate the effective
        // mass (r²/I ≈ 1.4e-4 against 1/m ≈ 3.3e-5 per unit impulse), so the
        // first cap's impulse pitches the second into the ground and the
        // second's pitches the first back out: after one pass the first cap
        // approaches at 0.517 m/s (replay of the shipped algorithm); after
        // eight both are within 0.01. The accumulated impulses are private
        // scratch, so they are recovered from what they did to the body:
        // j₁ + j₂ = m·Δv_y and 7.5 j₁ − 8.7 j₂ = I_x·Δω_x (r × n = [−r_z, 0, r_x]).
        let a = RigidBody(detachedAt: [0, 1.05, 0])
        a.mass = 30_000
        a.inverseInertiaLocal = float3x3(diagonal: 1 / float3(390_000, 440_000, 80_000))
        a.velocity = [0, -0.5, 0]
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true
        let contacts = [Contact(normal: [0, 1, 0], depth: 0, point: [0, 0, -7.5]),
                        Contact(normal: [0, 1, 0], depth: 0, point: [0, 0, 8.7])]
        let stats = HeckerCollisionResponse.getInverseMassStats(a, plane)

        HeckerCollisionResponse.solveManifold(a, plane, contacts: contacts[...], inverseMassStats: stats)

        for contact in contacts {
            #expect(abs(dot(a.velocity(atWorldPoint: contact.point), contact.normal)) <= 0.01,
                    "one pass leaves the first cap at −0.52 m/s; eight leave both within 0.01")
        }
        let impulseSum = 30_000 * (a.velocity.y + 0.5)          // j₁ + j₂, N·s
        let impulseMoment = 390_000 * a.angularVelocity.x       // 7.5 j₁ − 8.7 j₂
        let j2 = (7.5 * impulseSum - impulseMoment) / (7.5 + 8.7)
        let j1 = impulseSum - j2
        #expect(j1 >= 0 && j2 >= 0, "accumulated impulses are clamped non-negative")
        #expect(abs(j1 - 8038) <= 100 && abs(j2 - 6934) <= 100, "the replay's split: 8038 and 6934 N·s")
        #expect(plane.velocity == .zero && plane.angularVelocity == .zero, "statics never change")
    }

    @Test("a single-contact pair through resolvePair is exactly correctPosition + applyImpulse: the one pass every sphere golden took")
    func singleContactPairKeepsTheOnePass() throws {
        // A finite-inertia body with one off-center sphere collider 1 cm into
        // a static plane, approaching: position correction and the general
        // (lever-arm) impulse both act. Two identical set-ups, one through
        // resolvePair and one through the two halves by hand, must agree
        // bit-for-bit — a second impulse pass on a single contact would not.
        func makePair() -> (body: RigidBody, plane: PlaneRigidBody) {
            let body = RigidBody(detachedAt: [0, 0.49, 0])
            body.mass = 2
            body.inverseInertiaLocal = float3x3(diagonal: [0.5, 0.5, 0.5])
            body.velocity = [0, -1.5, 0]
            body.colliders = [LocalCollider(name: "ball", shape: .sphere(radius: 0.5), localPosition: [0.3, 0, 0])]
            let plane = PlaneRigidBody(detachedAt: .zero)
            plane.isStatic = true
            return (body, plane)
        }

        let paired = makePair()
        var contacts: [Contact] = []
        HeckerCollisionResponse.resolvePair(paired.body, paired.plane, contacts: &contacts)
        #expect(contacts.count == 1)

        let manual = makePair()
        var manualContacts: [Contact] = []
        let deepest = try #require(NarrowPhase.generateContacts(manual.body, manual.plane, into: &manualContacts))
        let stats = HeckerCollisionResponse.getInverseMassStats(manual.body, manual.plane)
        HeckerCollisionResponse.correctPosition(manual.body, manual.plane, contact: manualContacts[deepest], inverseMassStats: stats)
        HeckerCollisionResponse.applyImpulse(manual.body, manual.plane, contact: manualContacts[deepest], inverseMassStats: stats)

        #expect(paired.body.getPosition() == manual.body.getPosition())
        #expect(paired.body.velocity == manual.body.velocity)
        #expect(paired.body.angularVelocity == manual.body.angularVelocity)
        #expect(paired.body.velocity != [0, -1.5, 0], "the impulse acted")
        #expect(paired.body.angularVelocity != .zero, "through the lever arm")
    }
}
