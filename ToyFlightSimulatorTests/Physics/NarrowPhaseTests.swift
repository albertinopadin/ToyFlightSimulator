//
//  NarrowPhaseTests.swift
//  ToyFlightSimulatorTests
//
//  A.8 (A-routing track): the §4.7 geometry matrix for the pure narrow phase.
//  Every case is hand-computed and pinned — including the tests the deleted
//  y=0 plane hardcode made impossible (translated and tilted planes) and the
//  legacy-exact sphere-sphere boundary/degenerate pins the goldens rely on.
//  Metal-free: WorldColliders are built directly; the two body-level tests use
//  detached rigid bodies.
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("NarrowPhase geometry", .tags(.physics))
struct NarrowPhaseTests {

    // MARK: - Helpers

    private func rotation(_ angle: Float, about axis: float3) -> float3x3 {
        float3x3(simd_quatf(angle: angle, axis: axis))
    }

    /// Bare geometry probe (nil metadata unless a name is given).
    private func collider(_ shape: ColliderShape,
                          at position: float3,
                          rotation: float3x3 = matrix_identity_float3x3,
                          name: String? = nil) -> WorldCollider {
        WorldCollider(shape: shape,
                      position: position,
                      rotation: rotation,
                      sourceIndex: nil,
                      name: name,
                      group: name == nil ? nil : .airframe)
    }

    // MARK: - Shape vs plane: translated AND tilted (the y=0 hardcode's grave)

    @Test("sphere vs translated plane: depth and point measured from the plane, not y=0")
    func sphereVsTranslatedPlane() throws {
        // Plane at height 2; sphere r 1 centered 0.5 above it → depth 0.5.
        let s = collider(.sphere(radius: 1), at: [0, 2.5, 0])
        let contact = try #require(NarrowPhase.shapeVsPlane(s, planePoint: [0, 2, 0], planeNormal: [0, 1, 0]))
        #expect(approxEqual(contact.depth, 0.5))
        #expect(approxEqual(contact.normal, [0, 1, 0]))
        #expect(approxEqual(contact.point, [0, 2, 0]))   // foot of the center on the plane
    }

    @Test("sphere vs tilted plane: general dot(c − p, n) form")
    func sphereVsTiltedPlane() throws {
        // 45° plane through the origin; sphere r 1 centered 0.8 along the
        // normal → depth 0.2, contact point back at the origin.
        let n = normalize(float3(1, 1, 0))
        let s = collider(.sphere(radius: 1), at: n * 0.8)
        let contact = try #require(NarrowPhase.shapeVsPlane(s, planePoint: .zero, planeNormal: n))
        #expect(approxEqual(contact.depth, 0.2))
        #expect(approxEqual(contact.normal, n))
        #expect(approxEqual(contact.point, .zero))
    }

    @Test("capsule vs translated plane: the deeper end cap decides")
    func capsuleVsTranslatedPlane() throws {
        // Vertical capsule (r 0.5, hh 1) centered at y 1.4 over a plane at
        // y 1: lower end center [0, 0.4, 0] is 0.6 BELOW the plane → depth
        // 0.5 − (−0.6) = 1.1, and the contact point is the end center's foot.
        let c = collider(.capsule(radius: 0.5, halfHeight: 1), at: [0, 1.4, 0])
        let contact = try #require(NarrowPhase.shapeVsPlane(c, planePoint: [0, 1, 0], planeNormal: [0, 1, 0]))
        #expect(approxEqual(contact.depth, 1.1))
        #expect(approxEqual(contact.normal, [0, 1, 0]))
        #expect(approxEqual(contact.point, [0, 1, 0]))
    }

    @Test("capsule vs tilted plane")
    func capsuleVsTiltedPlane() throws {
        // 45° plane through the origin; vertical capsule (r 0.5, hh 1)
        // centered at [0.5, 0.5, 0]: lower end [0.5, −0.5, 0] lies ON the
        // plane (signed distance 0) → depth = r = 0.5.
        let n = normalize(float3(1, 1, 0))
        let c = collider(.capsule(radius: 0.5, halfHeight: 1), at: [0.5, 0.5, 0])
        let contact = try #require(NarrowPhase.shapeVsPlane(c, planePoint: .zero, planeNormal: n))
        #expect(approxEqual(contact.depth, 0.5))
        #expect(approxEqual(contact.normal, n))
        #expect(approxEqual(contact.point, [0.5, -0.5, 0]))
    }

    @Test("box vs translated plane: projection radius + deepest corner")
    func boxVsTranslatedPlane() throws {
        // Axis-aligned box he [1, 0.5, 2] centered 0.3 above a plane at y 2:
        // projection radius onto ŷ is 0.5 → depth 0.2. The support corner
        // steps −he along every axis (axisSign(0) = +1 for the two
        // perpendicular axes — deterministic, pinned).
        let b = collider(.box(halfExtents: [1, 0.5, 2]), at: [0, 2.3, 0])
        let contact = try #require(NarrowPhase.shapeVsPlane(b, planePoint: [0, 2, 0], planeNormal: [0, 1, 0]))
        #expect(approxEqual(contact.depth, 0.2))
        #expect(approxEqual(contact.normal, [0, 1, 0]))
        #expect(approxEqual(contact.point, [-1, 1.8, -2]))
    }

    @Test("box vs tilted plane: worst-corner projection over a 45° normal")
    func boxVsTiltedPlane() throws {
        // Unit cube (he [1,1,1]) at [0,1,0] against the 45° plane through the
        // origin: signed center distance = 1/√2, projection radius = 2/√2 →
        // depth = 1/√2. Deepest corner steps against n: [−1, 0, −1].
        let n = normalize(float3(1, 1, 0))
        let b = collider(.box(halfExtents: [1, 1, 1]), at: [0, 1, 0])
        let contact = try #require(NarrowPhase.shapeVsPlane(b, planePoint: .zero, planeNormal: n))
        #expect(approxEqual(contact.depth, 1 / sqrtf(2)))
        #expect(approxEqual(contact.normal, n))
        #expect(approxEqual(contact.point, [-1, 0, -1]))
    }

    // MARK: - Separated ⇒ nil, for every pair the dispatch reaches

    @Test("every separated pair returns nil")
    func separatedPairsAreNil() {
        let sphere  = collider(.sphere(radius: 1), at: .zero)
        let capsule = collider(.capsule(radius: 0.5, halfHeight: 1), at: .zero)
        let box     = collider(.box(halfExtents: [1, 1, 1]), at: .zero)
        let farSphere  = collider(.sphere(radius: 1), at: [5, 0, 0])
        let farCapsule = collider(.capsule(radius: 0.5, halfHeight: 1), at: [5, 0, 0])
        let farBox     = collider(.box(halfExtents: [1, 1, 1]), at: [5, 0, 0])

        #expect(NarrowPhase.shapeVsShape(sphere, farSphere) == nil)
        #expect(NarrowPhase.shapeVsShape(sphere, farCapsule) == nil)
        #expect(NarrowPhase.shapeVsShape(capsule, farSphere) == nil)
        #expect(NarrowPhase.shapeVsShape(capsule, farCapsule) == nil)
        #expect(NarrowPhase.shapeVsShape(sphere, farBox) == nil)
        #expect(NarrowPhase.shapeVsShape(box, farSphere) == nil)
        #expect(NarrowPhase.shapeVsShape(capsule, farBox) == nil)
        #expect(NarrowPhase.shapeVsShape(box, farCapsule) == nil)
        #expect(NarrowPhase.shapeVsPlane(collider(.sphere(radius: 1), at: [0, 5, 0]),
                                         planePoint: .zero, planeNormal: [0, 1, 0]) == nil)
    }

    @Test("box-box is pinned NOT IMPLEMENTED: nil even when overlapping")
    func boxBoxIsNilEvenOverlapping() {
        // Documented Phase C/D upgrade path (SAT/GJK). If this ever produces
        // a contact, that's a deliberate feature landing — retire this pin
        // with it.
        let a = collider(.box(halfExtents: [1, 1, 1]), at: .zero)
        let b = collider(.box(halfExtents: [1, 1, 1]), at: [0.5, 0, 0])
        #expect(NarrowPhase.shapeVsShape(a, b) == nil)
    }

    // MARK: - Sphere-in-box: least-penetration axis + tie determinism

    @Test("sphere center inside a box exits along the least-penetration axis")
    func sphereInsideBoxLeastAxis() throws {
        // he [2,1,3], center at [0.5, 0.2, 0]: face distances [1.5, 0.8, 3.0]
        // → Y wins; depth = face distance + radius; point = sphere center.
        let box = collider(.box(halfExtents: [2, 1, 3]), at: .zero)
        let sphere = collider(.sphere(radius: 0.3), at: [0.5, 0.2, 0])
        let contact = try #require(NarrowPhase.shapeVsShape(sphere, box))
        #expect(approxEqual(contact.normal, [0, 1, 0]))
        #expect(approxEqual(contact.depth, 1.1))
        #expect(approxEqual(contact.point, [0.5, 0.2, 0]))

        // Negative side of the winning axis flips the normal.
        let below = collider(.sphere(radius: 0.3), at: [0.5, -0.2, 0])
        let contactBelow = try #require(NarrowPhase.shapeVsShape(below, box))
        #expect(approxEqual(contactBelow.normal, [0, -1, 0]))
    }

    @Test("exact face-distance tie resolves x → y → z, deterministically")
    func sphereInsideBoxTieDeterminism() throws {
        // Unit cube, center [0.5, 0.5, 0]: distances [0.5, 0.5, 1.0]. The
        // strict `<` comparisons keep the FIRST axis on a tie → +X.
        let box = collider(.box(halfExtents: [1, 1, 1]), at: .zero)
        let sphere = collider(.sphere(radius: 0.1), at: [0.5, 0.5, 0])
        let contact = try #require(NarrowPhase.shapeVsShape(sphere, box))
        #expect(approxEqual(contact.normal, [1, 0, 0]))
        #expect(approxEqual(contact.depth, 0.6))
    }

    // MARK: - Capsule-capsule (Ericson closest-points cases)

    @Test("parallel capsules: closest points at the paired segment ends")
    func capsuleCapsuleParallel() throws {
        // Two vertical capsules (r 0.3, hh 1) 0.5 apart in X. The parallel
        // branch (denominator 0) picks s = 0 → both p0 ends; overlap
        // 0.6 − 0.5 = 0.1 along −X (B → A).
        let a = collider(.capsule(radius: 0.3, halfHeight: 1), at: .zero)
        let b = collider(.capsule(radius: 0.3, halfHeight: 1), at: [0.5, 0, 0])
        let contact = try #require(NarrowPhase.shapeVsShape(a, b))
        #expect(approxEqual(contact.depth, 0.1))
        #expect(approxEqual(contact.normal, [-1, 0, 0]))
        // Point = B-side surface at the closest pair: [0.5,−1,0] + n·0.3.
        #expect(approxEqual(contact.point, [0.2, -1, 0]))
    }

    @Test("crossing (perpendicular) capsules: closest points at the segment midpoints")
    func capsuleCapsuleCrossing() throws {
        // A vertical at the origin; B along X, offset 0.4 in Z. Closest
        // points are both segment midpoints → distance 0.4, sum 0.6 →
        // depth 0.2, normal −Z (B → A).
        let a = collider(.capsule(radius: 0.3, halfHeight: 1), at: .zero)
        let b = collider(.capsule(radius: 0.3, halfHeight: 1),
                         at: [0, 0, 0.4],
                         rotation: rotation(-.halfPi, about: Z_AXIS))   // ŷ → x̂
        let contact = try #require(NarrowPhase.shapeVsShape(a, b))
        #expect(approxEqual(contact.depth, 0.2))
        #expect(approxEqual(contact.normal, [0, 0, -1]))
    }

    @Test("degenerate point-segment capsule (hh 0) goes through the Ericson point branch")
    func capsuleCapsuleDegeneratePoint() throws {
        // A is a sphere-equivalent capsule (hh 0 — legal per ColliderShape);
        // B is vertical at x 0.8. B's closest parameter solves to its
        // midpoint; depth = 1.0 − 0.8 = 0.2, normal −X (B → A).
        let a = collider(.capsule(radius: 0.5, halfHeight: 0), at: .zero)
        let b = collider(.capsule(radius: 0.5, halfHeight: 1), at: [0.8, 0, 0])
        let contact = try #require(NarrowPhase.shapeVsShape(a, b))
        #expect(approxEqual(contact.depth, 0.2))
        #expect(approxEqual(contact.normal, [-1, 0, 0]))
    }

    // MARK: - Capsule-box approximation sanity

    @Test("capsule-box: contact where obviously overlapping, nil where obviously clear")
    func capsuleBoxApproximationSanity() throws {
        let capsule = collider(.capsule(radius: 0.5, halfHeight: 1), at: .zero)

        // Box face 0.2 from the capsule axis → overlap 0.3 against r 0.5.
        let touching = collider(.box(halfExtents: [1, 1, 1]), at: [1.2, 0, 0])
        let contact = try #require(NarrowPhase.shapeVsShape(capsule, touching))
        #expect(approxEqual(contact.depth, 0.3))
        #expect(approxEqual(contact.normal, [-1, 0, 0]))   // toward the capsule (A)

        // Same box hoisted 3 m up: nearest approach ≫ r.
        let clear = collider(.box(halfExtents: [1, 1, 1]), at: [1.2, 3, 0])
        #expect(NarrowPhase.shapeVsShape(capsule, clear) == nil)
    }

    // MARK: - Flipped-pair metadata

    @Test("A metadata stays on A in both argument orders; normals mirror")
    func flippedPairMetadataStaysWithBodies() throws {
        // Named capsule at the origin, named sphere 0.8 along +X (overlap 0.2).
        let cap = collider(.capsule(radius: 0.5, halfHeight: 1), at: .zero, name: "cap")
        let ball = collider(.sphere(radius: 0.5), at: [0.8, 0, 0], name: "ball")

        // Capsule as A goes through the flip path ((.capsule, .sphere) is
        // solved as (.sphere, .capsule).flipped) — metadata must still come
        // out caller-oriented.
        let capFirst = try #require(NarrowPhase.shapeVsShape(cap, ball))
        #expect(capFirst.colliderNameA == "cap")
        #expect(capFirst.colliderNameB == "ball")
        #expect(approxEqual(capFirst.normal, [-1, 0, 0]))   // B→A: toward the capsule
        #expect(approxEqual(capFirst.depth, 0.2))

        let ballFirst = try #require(NarrowPhase.shapeVsShape(ball, cap))
        #expect(ballFirst.colliderNameA == "ball")
        #expect(ballFirst.colliderNameB == "cap")
        #expect(approxEqual(ballFirst.normal, [1, 0, 0]))   // B→A: toward the sphere
        #expect(approxEqual(ballFirst.depth, 0.2))
    }

    // MARK: - Legacy-exact sphere-sphere pins

    @Test("surfaces exactly touching ⇒ contact with depth 0 (inclusive boundary)")
    func sphereSphereInclusiveBoundary() throws {
        // distance² == radiusSum² exactly (integers) — the legacy `<=` gate
        // admits it; a strict `>` rewrite would drop it and shift goldens.
        let a = collider(.sphere(radius: 1), at: .zero)
        let b = collider(.sphere(radius: 1), at: [2, 0, 0])
        let contact = try #require(NarrowPhase.shapeVsShape(a, b))
        #expect(contact.depth == 0)
        #expect(approxEqual(contact.normal, [-1, 0, 0]))
        #expect(approxEqual(contact.point, [1, 0, 0]))
    }

    @Test("coincident centers ⇒ ZERO normal (pinned legacy degenerate, not a [0,1,0] fallback)")
    func sphereSphereCoincidentCenters() throws {
        let a = collider(.sphere(radius: 1), at: [3, 3, 3])
        let b = collider(.sphere(radius: 1), at: [3, 3, 3])
        let contact = try #require(NarrowPhase.shapeVsShape(a, b))
        #expect(contact.normal == float3.zero)
        #expect(approxEqual(contact.depth, 2))
    }

    // MARK: - Body-level dispatch: plane-as-A flip, deepest index

    @Test("plane as entity A: contacts flip caller-oriented, deepest index survives")
    func planeAsAFlipsContacts() throws {
        // Compound body 0.5 m up with two named spheres: "low" reaches 0.2
        // into the floor, "high" exactly touches it (depth 0 — inclusive).
        let body = RigidBody(detachedAt: [0, 0.5, 0])
        body.colliders = [
            LocalCollider(name: "low", shape: .sphere(radius: 0.5), localPosition: [0, -0.2, 0]),
            LocalCollider(name: "high", shape: .sphere(radius: 0.5), localPosition: [0, 0, 0]),
        ]
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true

        // Volume-first order: normals point plane → body (+Y), names on A.
        var forward: [Contact] = []
        let deepestForward = try #require(NarrowPhase.generateContacts(body, plane, into: &forward))
        #expect(forward.count == 2)
        #expect(forward[deepestForward].colliderNameA == "low")
        #expect(approxEqual(forward[deepestForward].depth, 0.2))
        #expect(forward.allSatisfy { approxEqual($0.normal, [0, 1, 0]) })
        #expect(forward.allSatisfy { $0.colliderNameB == nil })   // plane has no identity

        // Plane-first order: every contact rewritten into the caller's
        // orientation — normal toward the plane (A side), names moved to B —
        // and the deepest index still lands on the deepest contact.
        var flipped: [Contact] = []
        let deepestFlipped = try #require(NarrowPhase.generateContacts(plane, body, into: &flipped))
        #expect(flipped.count == 2)
        #expect(flipped.indices.contains(deepestFlipped))
        #expect(flipped[deepestFlipped].colliderNameB == "low")
        #expect(approxEqual(flipped[deepestFlipped].depth, 0.2))
        #expect(flipped.allSatisfy { approxEqual($0.normal, [0, -1, 0]) })
        #expect(flipped.allSatisfy { $0.colliderNameA == nil })
    }

    @Test("plane vs plane generates nothing")
    func planeVsPlaneIsNil() {
        let a = PlaneRigidBody(detachedAt: .zero)
        let b = PlaneRigidBody(detachedAt: [0, 1, 0])
        var contacts: [Contact] = []
        #expect(NarrowPhase.generateContacts(a, b, into: &contacts) == nil)
        #expect(contacts.isEmpty)
    }

    // MARK: - Ray vs plane (B.4: the strut raycast)

    @Test("ray vs translated plane: t is the distance along the ray, wherever the plane point sits")
    func rayVsTranslatedPlane() throws {
        // Straight down from y 5 onto the y = 2 plane: t = 3. The plane point's
        // lateral offset is irrelevant (the plane is infinite), and so is the
        // ray origin's.
        let t = try #require(NarrowPhase.rayVsPlane(origin: [0, 5, 0], direction: [0, -1, 0],
                                                    planePoint: [7, 2, -3], planeNormal: [0, 1, 0]))
        #expect(approxEqual(t, 3))
        let shifted = try #require(NarrowPhase.rayVsPlane(origin: [4, 5, 9], direction: [0, -1, 0],
                                                          planePoint: [0, 2, 0], planeNormal: [0, 1, 0]))
        #expect(approxEqual(shifted, 3))
    }

    @Test("ray vs tilted plane, and an oblique ray: the general dot(p − o, n) / dot(d, n) form")
    func rayVsTiltedPlane() throws {
        // 45° plane through the origin, n = (1,1,0)/√2. Straight down from
        // [0, 2, 0]: dot(p − o, n) = −2/√2 over dot(d, n) = −1/√2 → t = 2, the
        // hit is the origin. From [1, 2, 0]: −3/√2 over −1/√2 → t = 3, hit
        // [1, −1, 0], which satisfies x + y = 0.
        let n = normalize(float3(1, 1, 0))
        let t0 = try #require(NarrowPhase.rayVsPlane(origin: [0, 2, 0], direction: [0, -1, 0],
                                                     planePoint: .zero, planeNormal: n))
        #expect(approxEqual(t0, 2))
        let t1 = try #require(NarrowPhase.rayVsPlane(origin: [1, 2, 0], direction: [0, -1, 0],
                                                     planePoint: .zero, planeNormal: n))
        #expect(approxEqual(t1, 3))
        // Oblique ray onto the flat plane: from [0, 1, 0] along (1, −1, 0)/√2,
        // t = √2 and the hit is [1, 0, 0]. The axis-aligned cases only pin the
        // sign of the divide by dot(d, n); this one pins its magnitude.
        let d = normalize(float3(1, -1, 0))
        let t2 = try #require(NarrowPhase.rayVsPlane(origin: [0, 1, 0], direction: d,
                                                     planePoint: .zero, planeNormal: [0, 1, 0]))
        #expect(approxEqual(t2, sqrtf(2)))
        #expect(approxEqual(float3(0, 1, 0) + d * t2, [1, 0, 0]))
    }

    @Test("parallel, facing-away, and back-face approaches are nil")
    func rayVsPlaneMisses() {
        let n: float3 = [0, 1, 0]
        #expect(NarrowPhase.rayVsPlane(origin: [0, 5, 0], direction: [1, 0, 0],
                                       planePoint: .zero, planeNormal: n) == nil)   // parallel
        #expect(NarrowPhase.rayVsPlane(origin: [0, 5, 0], direction: [0, 1, 0],
                                       planePoint: .zero, planeNormal: n) == nil)   // away from the plane
        // From below, moving up: the ray crosses the plane, but from the back —
        // an inverted aircraft's struts must hit nothing.
        #expect(NarrowPhase.rayVsPlane(origin: [0, -1, 0], direction: [0, 1, 0],
                                       planePoint: .zero, planeNormal: n) == nil)
    }

    @Test("a plane behind the origin is nil; an origin exactly on the plane hits at t = 0")
    func rayVsPlaneBehindAndOnPlane() {
        let n: float3 = [0, 1, 0]
        #expect(NarrowPhase.rayVsPlane(origin: [0, -1, 0], direction: [0, -1, 0],
                                       planePoint: .zero, planeNormal: n) == nil)
        // On the surface counts as a hit at 0: a wheel exactly at the ground
        // is a contact with zero compression, not airborne.
        #expect(NarrowPhase.rayVsPlane(origin: .zero, direction: [0, -1, 0],
                                       planePoint: .zero, planeNormal: n) == 0)
    }
}
