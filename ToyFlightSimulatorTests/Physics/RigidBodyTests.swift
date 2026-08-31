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
        #expect(rb.collisionRadius == 1.5)
    }

    @Test("PlaneRigidBody init writes self into gameObject.rigidBody and stores normal")
    func planeRigidBodyRegistersBackReference() {
        let quad = Quad()
        #expect(quad.rigidBody == nil)

        let rb = PlaneRigidBody(gameObject: quad, collisionNormal: [0, 1, 0])
        #expect(quad.rigidBody === rb)
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

    // MARK: - Detached (standalone) bodies — step 0.6

    @Test("init(detachedAt:) round-trips position with no GameObject")
    func detachedPositionRoundTrip() {
        let body = SphereRigidBody(detachedAt: [1, 2, 3], collisionRadius: 0.5)
        #expect(body.gameObject == nil)
        #expect(approxEqual(body.getPosition(), [1, 2, 3]))

        // Standalone storage, not the released-weak no-op fallback.
        body.setPosition([-4, 5, -6])
        #expect(approxEqual(body.getPosition(), [-4, 5, -6]))
    }

    @Test("detached bodies get the same stored-property defaults as attached ones")
    func detachedDefaultsMatchAttached() {
        let body = SphereRigidBody(detachedAt: .zero)
        #expect(body.mass == 1)
        #expect(body.restitution == 1)
        #expect(!body.isStatic)
        #expect(body.shouldApplyGravity)
        #expect(approxEqual(body.velocity, .zero))
        #expect(approxEqual(body.acceleration, .zero))
    }

    @Test("detached SphereRigidBody AABB = position ± radius")
    func detachedSphereAABB() {
        let body = SphereRigidBody(detachedAt: [10, 20, 30], collisionRadius: 2.0)
        let aabb = body.getAABB()
        #expect(approxEqual(aabb.min, [8, 18, 28]))
        #expect(approxEqual(aabb.max, [12, 22, 32]))
    }

    @Test("detached PlaneRigidBody normalizes its normal and brackets its position")
    func detachedPlaneAABB() {
        let plane = PlaneRigidBody(detachedAt: .zero, collisionNormal: [0, 2, 0])
        #expect(approxEqual(plane.collisionNormal, [0, 1, 0]))

        // The "infinite" horizontal-plane AABB: thin in Y, huge in X/Z —
        // enough for the broad phase to pair it with anything near the floor.
        let aabb = plane.getAABB()
        #expect(aabb.min.y <= 0 && aabb.max.y >= 0)
        #expect(aabb.min.x <= -9999 && aabb.max.x >= 9999)
        #expect(aabb.min.z <= -9999 && aabb.max.z >= 9999)
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

    // MARK: - World-collider snapshot cache (A.8, A-routing track)

    @Test("worldColliders() rebuilds only on invalidation (dirty-flag cache discipline)")
    func worldColliderCacheRebuildDiscipline() {
        let body = RebuildCountingBody(detachedAt: .zero)
        body.colliders = [LocalCollider(name: "c", shape: .sphere(radius: 1))]

        _ = body.worldColliders()
        #expect(body.rebuilds == 1)
        _ = body.worldColliders()
        _ = body.worldColliders()
        #expect(body.rebuilds == 1, "clean reads must hit the cache, not rebuild")

        body.setPosition([1, 0, 0])                 // mid-step funnel invalidates
        _ = body.worldColliders()
        #expect(body.rebuilds == 2)
        #expect(approxEqual(body.worldColliders()[0].position, [1, 0, 0]))

        body.invalidateWorldColliders()             // the world's start-of-step sweep
        _ = body.worldColliders()
        #expect(body.rebuilds == 3)

        body.colliders[0].isEnabled = false         // colliders.didSet invalidates
        _ = body.worldColliders()
        #expect(body.rebuilds == 4)
        #expect(body.worldColliders().isEmpty)
    }

    @Test("SphereRigidBody synthesizes a world-meter view at the live position, nil metadata")
    func sphereSynthesizedView() throws {
        // Phase A deviation 2: collisionRadius is WORLD meters, node scale
        // deliberately not applied, and the nil identity keeps Contact's
        // "nil for simple bodies" contract truthful.
        let sphere = SphereRigidBody(detachedAt: [3, 4, 5], collisionRadius: 2.0)
        let views = sphere.worldColliders()
        try #require(views.count == 1)
        #expect(views[0].shape == .sphere(radius: 2.0))
        #expect(approxEqual(views[0].position, [3, 4, 5]))
        #expect(views[0].name == nil)
        #expect(views[0].sourceIndex == nil)
        #expect(views[0].group == nil)
    }

    @Test("collisionRadius.didSet invalidates the synthesized view")
    func collisionRadiusInvalidates() throws {
        let sphere = SphereRigidBody(detachedAt: .zero, collisionRadius: 1.0)
        _ = sphere.worldColliders()                  // prime the cache
        sphere.collisionRadius = 2.5
        let views = sphere.worldColliders()
        try #require(views.count == 1)
        #expect(views[0].shape == .sphere(radius: 2.5))
    }

    @Test("compound getAABB is the union of the world colliders' bounds")
    func compoundAABBUnion() {
        let body = RigidBody(detachedAt: [0, 10, 0])
        body.colliders = [
            LocalCollider(name: "left", shape: .sphere(radius: 1), localPosition: [-2, 0, 0]),
            LocalCollider(name: "right", shape: .sphere(radius: 1), localPosition: [2, 0, 0]),
        ]
        let aabb = body.getAABB()
        #expect(approxEqual(aabb.min, [-3, 9, -1]))
        #expect(approxEqual(aabb.max, [3, 11, 1]))
    }

    @Test("collider-less plain RigidBody keeps the legacy AABB delegate (zero AABB when detached)")
    func emptyColliderAABBFallback() {
        // No colliders and no gameObject → the pre-Phase-A fallback shape:
        // AABB(center: .zero, radius: .zero), regardless of standalone position.
        let body = RigidBody(detachedAt: [5, 5, 5])
        let aabb = body.getAABB()
        #expect(approxEqual(aabb.min, .zero))
        #expect(approxEqual(aabb.max, .zero))
    }
}

/// Counts rebuilds so the dirty-flag cache is observable — the returned
/// snapshot is a value-type array, so cache hits can't be detected from
/// outside without hooking the (internal, @testable-visible) rebuild point.
private final class RebuildCountingBody: RigidBody {
    var rebuilds = 0
    override func rebuildWorldColliders() {
        rebuilds += 1
        super.rebuildWorldColliders()
    }
}

// MARK: - Filtering truth table (A.8, A-routing track; pure predicate)

@Suite("Collision filtering", .tags(.physics))
struct CollisionFilteringTests {

    @Test("default masks: everything collides with everything")
    func defaultsCollide() {
        let a = SphereRigidBody(detachedAt: .zero)
        let b = SphereRigidBody(detachedAt: [1, 0, 0])
        #expect(a.shouldCollide(with: b))
        #expect(b.shouldCollide(with: a))
    }

    @Test("mask truth table: the pair is live only when BOTH directions pass")
    func maskCombinations() {
        let a = SphereRigidBody(detachedAt: .zero)
        let b = SphereRigidBody(detachedAt: [1, 0, 0])
        a.categoryMask = CollisionCategory.vehicle
        b.categoryMask = CollisionCategory.world

        // Both directions open.
        a.collidesWithMask = CollisionCategory.world
        b.collidesWithMask = CollisionCategory.vehicle
        #expect(a.shouldCollide(with: b))
        #expect(b.shouldCollide(with: a))

        // b stops accepting vehicles → dead BOTH ways (symmetric predicate).
        b.collidesWithMask = CollisionCategory.debris
        #expect(!a.shouldCollide(with: b))
        #expect(!b.shouldCollide(with: a))

        // b accepts again but a stops accepting world → still dead both ways.
        b.collidesWithMask = CollisionCategory.vehicle
        a.collidesWithMask = CollisionCategory.debris
        #expect(!a.shouldCollide(with: b))
        #expect(!b.shouldCollide(with: a))
    }

    @Test("detached bodies (nil gameObjects) are never same-object excluded")
    func detachedBodiesNeverSameObjectExcluded() {
        // The same-GameObject exclusion needs BOTH gameObjects non-nil; the
        // attached-path exclusion itself is pinned in PhysicsWorldSmokeTests
        // (app-hosted — GameObjects are legal there).
        let a = SphereRigidBody(detachedAt: .zero)
        let b = SphereRigidBody(detachedAt: .zero)
        #expect(a.shouldCollide(with: b))
    }
}
