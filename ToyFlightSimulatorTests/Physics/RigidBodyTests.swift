//
//  RigidBodyTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("RigidBody / GameObject composition", .tags(.physics))
struct RigidBodyTests {

    // MARK: - Back-reference registration

    @Test("SphereRigidBody init writes self into gameObject.rigidBody")
    func sphereRigidBodyRegistersBackReference() {
        let sphere = Sphere()
        #expect(sphere.rigidBody == nil)

        let rb = SphereRigidBody(gameObject: sphere, collisionRadius: 1.5)
        #expect(sphere.rigidBody === rb)
        #expect(rb.collisionShape == .Sphere)
        #expect(rb.collisionRadius == 1.5)
    }

    @Test("PlaneRigidBody init writes self into gameObject.rigidBody and stores normal")
    func planeRigidBodyRegistersBackReference() {
        let quad = Quad()
        #expect(quad.rigidBody == nil)

        let rb = PlaneRigidBody(gameObject: quad, collisionNormal: [0, 1, 0])
        #expect(quad.rigidBody === rb)
        #expect(rb.collisionShape == .Plane)
        #expect(approxEqual(rb.collisionNormal, [0, 1, 0]))
    }

    // MARK: - Position pass-through

    @Test("setPosition / getPosition pass through to the attached GameObject")
    func positionPassThrough() {
        let sphere = Sphere()
        let rb = SphereRigidBody(gameObject: sphere, collisionRadius: 1.0)

        rb.setPosition([3, 4, 5])
        #expect(approxEqual(sphere.getPosition(), [3, 4, 5]))
        #expect(approxEqual(rb.getPosition(), [3, 4, 5]))

        sphere.setPosition([-1, -2, -3])
        #expect(approxEqual(rb.getPosition(), [-1, -2, -3]))
    }

    // MARK: - AABB delegation

    @Test("SphereRigidBody.getAABB matches center+radius of the GameObject")
    func sphereAABBMatchesPositionAndRadius() {
        let sphere = Sphere()
        sphere.setPosition([10, 20, 30])
        let rb = SphereRigidBody(gameObject: sphere, collisionRadius: 2.0)

        let aabb = rb.getAABB()
        #expect(approxEqual(aabb.min, [8, 18, 28]))
        #expect(approxEqual(aabb.max, [12, 22, 32]))
    }

    // MARK: - Retain-cycle / weak back-reference

    @Test("Releasing the GameObject also releases the RigidBody (no retain cycle)")
    func noRetainCycleBetweenGameObjectAndRigidBody() {
        weak var weakSphere: Sphere?
        weak var weakRigidBody: SphereRigidBody?

        // Scope so both strong refs go away at end of block.
        do {
            let sphere = Sphere()
            let rb = SphereRigidBody(gameObject: sphere, collisionRadius: 1.0)
            weakSphere = sphere
            weakRigidBody = rb
            #expect(weakSphere != nil)
            #expect(weakRigidBody != nil)
        }

        // If the back-reference inside RigidBody were strong, the cycle
        // GameObject → RigidBody → GameObject would keep both alive even
        // though all named strong refs are gone.
        #expect(weakSphere == nil, "GameObject leaked — likely a strong back-reference in RigidBody")
        #expect(weakRigidBody == nil, "RigidBody leaked — held by a stale strong ref")
    }

    @Test("RigidBody handles a deallocated GameObject without crashing")
    func rigidBodyToleratesNilGameObject() {
        // Use an explicit optional so we can drop the strong ref deterministically;
        // in debug builds Swift can extend a `let` past its scope, which would
        // keep the weak gameObject backref non-nil and defeat the test.
        var sphere: Sphere? = Sphere()
        sphere!.setPosition([7, 8, 9])
        let rb = SphereRigidBody(gameObject: sphere!, collisionRadius: 1.0)
        #expect(approxEqual(rb.getPosition(), [7, 8, 9]))

        sphere = nil  // drop the only strong ref; rb.gameObject (weak) → nil

        // Methods must not crash and must return the optional-chain fallbacks.
        #expect(approxEqual(rb.getPosition(), .zero),
                "getPosition should fall back to .zero when gameObject is nil")
        rb.setPosition([1, 2, 3])  // no-op write — must not crash
        #expect(approxEqual(rb.getPosition(), .zero),
                "setPosition is a no-op when gameObject is nil")
    }

    // MARK: - F22 didSet overrides

    @Test("F22.rigidBody didSet stamps F22.mass and restitution=0.1")
    func f22RigidBodyDidSetAppliesAircraftDefaults() {
        let jet = F22(scale: 0.25, shouldUpdateOnPlayerInput: false)
        let rb = SphereRigidBody(gameObject: jet)
        jet.flightModel = F22SimpleFlightModel()
        // The RigidBody initializer registers itself with the F22, which
        // triggers F22.rigidBody.didSet — we expect the F22-specific
        // defaults to win over the RigidBody init defaults. F22.mass is
        // 30_000 kg (real F-22 loaded weight ~30 tonnes) since b094014.
        #expect(rb.mass == jet.flightModel!.mass)
        #expect(rb.mass == 30_000)
        #expect(approxEqual(rb.restitution, 0.1))
    }
}
