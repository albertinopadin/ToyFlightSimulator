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
//  C.1 (C-narrowphase): box-box by separating axes with one clipped contact
//  point, and exact capsule-box (the slab test and twelve axes for a core
//  inside the box; end caps and twelve edges outside). Every case is
//  hand-computed against the plan's listing.
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
                          name: String? = nil,
                          group: ColliderGroup = .airframe) -> WorldCollider {
        WorldCollider(shape: shape,
                      position: position,
                      rotation: rotation,
                      sourceIndex: nil,
                      name: name,
                      group: name == nil ? nil : group)
    }

    /// A capsule whose core runs from `start` to `end` (both in the XY
    /// plane): the collider's axis (local +Y) is rotated about Z to the
    /// core's direction, so position ∓ axis·halfHeight are `start` and
    /// `end` — the (center, half height, angle) pose each capsule-box case
    /// is stated in.
    private func capsuleAlong(from start: float3, to end: float3, radius: Float) -> WorldCollider {
        let delta = end - start
        let direction = normalize(delta)
        // Rotating ŷ about Z by θ gives (−sin θ, cos θ, 0).
        let angle = atan2f(-direction.x, direction.y)
        return collider(.capsule(radius: radius, halfHeight: 0.5 * length(delta)),
                        at: 0.5 * (start + end),
                        rotation: rotation(angle, about: Z_AXIS))
    }

    /// The same collider translated by `delta`.
    private func moved(_ c: WorldCollider, by delta: float3) -> WorldCollider {
        WorldCollider(shape: c.shape, position: c.position + delta, rotation: c.rotation,
                      sourceIndex: c.sourceIndex, name: c.name, group: c.group)
    }

    /// The same collider with its pose turned by `turn` about the origin.
    private func turned(_ c: WorldCollider, by turn: float3x3) -> WorldCollider {
        WorldCollider(shape: c.shape, position: turn * c.position, rotation: turn * c.rotation,
                      sourceIndex: c.sourceIndex, name: c.name, group: c.group)
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
        #expect(NarrowPhase.shapeVsShape(box, farBox) == nil)
        #expect(NarrowPhase.shapeVsPlane(collider(.sphere(radius: 1), at: [0, 5, 0]),
                                         planePoint: .zero, planeNormal: [0, 1, 0]) == nil)
    }

    // MARK: - Box-box (C.1): separating axes, one clipped contact point

    @Test("aligned face overlap: A's x axis wins the tie; the point is the clipped incident face's centroid")
    func boxBoxAlignedFaceOverlap() throws {
        // Unit cubes, A 1.5 along +X of B: x overlaps by 0.5 on A's axis and
        // on B's alike; A's is tested first and the strict compare keeps it
        // (faceOfA(0)). The reference face is A's −x face at x 0.5, the
        // incident face B's +x face at x 1: all four of its vertices lie
        // within A's y and z ranges and 0.5 below the face, so the centroid
        // is that face's center.
        let b = collider(.box(halfExtents: [1, 1, 1]), at: .zero)
        let a = collider(.box(halfExtents: [1, 1, 1]), at: [1.5, 0, 0])
        let contact = try #require(NarrowPhase.shapeVsShape(a, b))
        #expect(approxEqual(contact.normal, [1, 0, 0]))
        #expect(approxEqual(contact.depth, 0.5))
        #expect(approxEqual(contact.point, [1, 0, 0]))

        // The other argument order mirrors the normal at the same depth; the
        // point lies on the other box's face (A's −x face at x 0.5), which is
        // also where the boxes meet.
        let reversed = try #require(NarrowPhase.shapeVsShape(b, a))
        #expect(approxEqual(reversed.normal, [-1, 0, 0]))
        #expect(approxEqual(reversed.depth, 0.5))
        #expect(approxEqual(reversed.point, [0.5, 0, 0]))
    }

    @Test("offset face overlap: the point is the clipped strip's centroid, inside the overlap")
    func boxBoxOffsetFaceOverlap() throws {
        // A at [1.5, 1.5, 0]: x and y overlap 0.5 each and the strict compare
        // keeps x. B's +x face clipped to A's y range is the strip y 0.5…1
        // at x 1, all of it 0.5 deep, and its centroid is inside the overlap
        // (x 0.5…1, y 0.5…1). B's support point alone gave [1, 0, 0],
        // outside A entirely.
        let b = collider(.box(halfExtents: [1, 1, 1]), at: .zero)
        let a = collider(.box(halfExtents: [1, 1, 1]), at: [1.5, 1.5, 0])
        let contact = try #require(NarrowPhase.shapeVsShape(a, b))
        #expect(approxEqual(contact.normal, [1, 0, 0]))
        #expect(approxEqual(contact.depth, 0.5))
        #expect(approxEqual(contact.point, [1, 0.75, 0]))
    }

    @Test("separated boxes are nil; faces exactly touching are a depth-0 contact (inclusive gate)")
    func boxBoxSeparatedAndTouching() throws {
        let b = collider(.box(halfExtents: [1, 1, 1]), at: .zero)
        let separated = collider(.box(halfExtents: [1, 1, 1]), at: [2.5, 0, 0])
        #expect(NarrowPhase.shapeVsShape(separated, b) == nil)

        // reach 1 + 1 against a center distance of 2: overlap exactly 0.
        let touching = collider(.box(halfExtents: [1, 1, 1]), at: [2, 0, 0])
        let contact = try #require(NarrowPhase.shapeVsShape(touching, b))
        #expect(contact.depth == 0)
        #expect(approxEqual(contact.normal, [1, 0, 0]))
    }

    @Test("rotated box on a face: the face beats its tying edge axis; the point is the bottom edge's midpoint")
    func boxBoxRotatedOnFace() throws {
        // A: a unit cube rotated 45° about Z with its bottom edge 0.1 into
        // B's +y face (center y = 1 + √2 − 0.1). B's +y face overlaps by 0.1;
        // A's own axes overlap by about 0.78, and the y edge-cross ties the
        // face but loses to it (face axes first, strict compare). The
        // incident face is one of A's two lower faces — a tie to one ulp,
        // and either keeps the same bottom edge: its two low vertices are
        // that edge at y 0.9, z ±1, its two high ones sit above the face and
        // are dropped, and the centroid is the edge's midpoint.
        let b = collider(.box(halfExtents: [1, 1, 1]), at: .zero)
        let a = collider(.box(halfExtents: [1, 1, 1]),
                         at: [0, 1 + sqrtf(2) - 0.1, 0],
                         rotation: rotation(.pi / 4, about: Z_AXIS))
        let contact = try #require(NarrowPhase.shapeVsShape(a, b))
        #expect(approxEqual(contact.normal, [0, 1, 0]))
        #expect(approxEqual(contact.depth, 0.1))
        #expect(approxEqual(contact.point, [0, 0.9, 0]))
    }

    @Test("rotated box shifted along the face: the point follows the bottom edge")
    func boxBoxRotatedShiftedAlongFace() throws {
        // The case above with A moved 0.5 along the face: same normal and
        // depth, and the point is the shifted bottom edge's midpoint. The
        // projected-overlap midpoint (the second draft) gave [0.043, 0.9, 0],
        // which in A's frame is 1.32 half extents out along one axis:
        // outside A.
        let b = collider(.box(halfExtents: [1, 1, 1]), at: .zero)
        let a = collider(.box(halfExtents: [1, 1, 1]),
                         at: [0.5, 1 + sqrtf(2) - 0.1, 0],
                         rotation: rotation(.pi / 4, about: Z_AXIS))
        let contact = try #require(NarrowPhase.shapeVsShape(a, b))
        #expect(approxEqual(contact.normal, [0, 1, 0]))
        #expect(approxEqual(contact.depth, 0.1))
        #expect(approxEqual(contact.point, [0.5, 0.9, 0]))
    }

    @Test("rotated box over the side of the face: the clip adds vertices on the side plane")
    func boxBoxRotatedOverFaceSide() throws {
        // A: a unit cube rotated 40° about Z, placed so its bottom corner
        // sits at x 0.93, y 0.9. At 40° the incident face is unambiguous —
        // A's −y face, opposed to the reference normal by 0.766 against
        // 0.643 for the other lower face (at 45° the two tie to one ulp and
        // clip to different points) — and it rises toward +x, crossing B's
        // x = 1 side plane 0.041 below the top face. Least axis B's +y at
        // 0.1; A's own x axis is next at 0.118. The clip keeps four
        // vertices, the bottom edge's two at [0.93, 0.9, ±1] and two new
        // ones on the side plane at [1, 0.959, ±1], all below the face; the
        // point is their mean.
        let angle: Float = 40 * .pi / 180
        let b = collider(.box(halfExtents: [1, 1, 1]), at: .zero)
        let a = collider(.box(halfExtents: [1, 1, 1]),
                         at: [0.93 + cosf(angle) - sinf(angle), 0.9 + cosf(angle) + sinf(angle), 0],
                         rotation: rotation(angle, about: Z_AXIS))
        let contact = try #require(NarrowPhase.shapeVsShape(a, b))
        #expect(approxEqual(contact.normal, [0, 1, 0]))
        #expect(approxEqual(contact.depth, 0.1))
        #expect(approxEqual(contact.point, [0.965, 0.929, 0], tolerance: 1e-3))
    }

    @Test("edge-edge: crossed rods meet at their edges' closest points, not the edge midpoints")
    func boxBoxEdgeEdge() throws {
        // A: a rod along z (he [0.2, 0.2, 2]) rotated 45° about Z, its bottom
        // ridge along z at x 1, y 0.466 − 0.2√2 = 0.183. B: a rod along x
        // (he [2, 0.2, 0.2]) rotated 45° about X, its top ridge along x at
        // z 0, y 0.2√2 = 0.283. The ridges cross at x 1 with 0.1 m of
        // overlap along y = cross(A's z edge, B's x edge). The point is the
        // midpoint of the two edges' closest points, [1, 0.183, 0] and
        // [1, 0.283, 0]; the edge midpoints alone would give x 0.5.
        let a = collider(.box(halfExtents: [0.2, 0.2, 2]),
                         at: [1, 0.466, 0],
                         rotation: rotation(.pi / 4, about: Z_AXIS))
        let b = collider(.box(halfExtents: [2, 0.2, 0.2]),
                         at: .zero,
                         rotation: rotation(.pi / 4, about: X_AXIS))
        let contact = try #require(NarrowPhase.shapeVsShape(a, b))
        #expect(approxEqual(contact.normal, [0, 1, 0]))
        #expect(approxEqual(contact.depth, 0.1, tolerance: 1e-3))
        #expect(approxEqual(contact.point, [1, 0.233, 0], tolerance: 1e-3))
    }

    @Test("yawed wing tip into a wall: the point is the tip edge's midpoint, not the wing's centerline")
    func boxBoxYawedWingTipIntoWall() throws {
        // A: the F-22 wing box (he [6.6, 0.18, 2.7]) yawed 20° about Y and
        // placed so its leading tip edge (local x −6.6, z 2.7) sits 0.3 m
        // into the wall's near face at z 0, at x 0; its trailing tip is
        // about 4 m in front of the wall. B: a 40 × 12 × 3 m wall. The least
        // axis is the wall's z face at 0.3 (the y edge-cross ties it and
        // loses); the incident face is the wing's front face, and the clip
        // drops its two vertices in front of the wall, leaving the tip
        // edge's ends at y 6 ± 0.18. The projected-overlap midpoint put the
        // point at [5.28, 6, 0.3], on the wing's centerline: with D.3's
        // lever arms a wingtip strike would not have yawed the jet.
        let wall = collider(.box(halfExtents: [20, 6, 1.5]), at: [0, 6, 1.5])
        let wing = collider(.box(halfExtents: [6.6, 0.18, 2.7]),
                            at: [5.279, 6, -4.495],
                            rotation: rotation(0.3491, about: Y_AXIS))
        let contact = try #require(NarrowPhase.shapeVsShape(wing, wall))
        #expect(approxEqual(contact.normal, [0, 0, -1]))
        #expect(approxEqual(contact.depth, 0.3, tolerance: 1e-3))
        #expect(approxEqual(contact.point, [0, 6, 0.3], tolerance: 2e-3))
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

    // MARK: - Capsule-box, exact (C.1): slab test and twelve axes inside; end caps and twelve edges outside

    /// The slab the first three cases run against: half extents [10, 1, 10]
    /// at the origin.
    private var slab: WorldCollider { collider(.box(halfExtents: [10, 1, 10]), at: .zero) }

    @Test("capsuleAlong reproduces the stated pose: center, half height, axis, and core start")
    func capsulePoseHelperReproducesCore() throws {
        // The crossing case's core, [8, −4, 0] → [12, 4, 0]: center
        // [10, 0, 0], half height √20 = 4.4721, axis [1, 2, 0]/√5 (−0.4636 rad
        // about Z), and center − axis·halfHeight is the start again — the
        // world core capsuleSegment reads.
        let cap = capsuleAlong(from: [8, -4, 0], to: [12, 4, 0], radius: 0.5)
        guard case .capsule(radius: let radius, halfHeight: let halfHeight) = cap.shape else {
            Issue.record("capsuleAlong built a non-capsule")
            return
        }
        let axis = cap.rotation.columns.1
        #expect(radius == 0.5)
        #expect(approxEqual(cap.position, [10, 0, 0]))
        #expect(approxEqual(halfHeight, sqrtf(20)))
        #expect(approxEqual(axis, normalize(float3(1, 2, 0))))
        #expect(approxEqual(cap.position - axis * halfHeight, [8, -4, 0]))
        #expect(approxEqual(cap.position + axis * halfHeight, [12, 4, 0]))
    }

    @Test("capsule-box: a core crossing the slab between the old probes slides out past the corner edge")
    func capsuleBoxCoreCrossingBetweenProbes() throws {
        // Core [8, −4, 0] → [12, 4, 0], r 0.5 (center [10, 0, 0], half height
        // 4.4721, −0.4636 rad about Z). Both ends are 3 m clear of the slab
        // and the point nearest its center is the first end — the three
        // sphere probes saw nothing — but the core is inside for
        // t 0.375…0.5, passing 0.447 m inside the corner edge at [10, −1, z].
        // The least of the twelve axes is the core's cross product with z,
        // the capsule sliding out past that edge: the face axes need 2.5
        // (+x) and 5.5 (±y). Depth 0.447 + r; the point is the clipped
        // span's midpoint, since the core runs across the normal. The
        // second draft's midpoint probe answered [1, 0, 0] at 0.75, and a
        // capsule moved 0.75 along x is still crossing the slab.
        let cap = capsuleAlong(from: [8, -4, 0], to: [12, 4, 0], radius: 0.5)
        let contact = try #require(NarrowPhase.shapeVsShape(cap, slab))
        #expect(approxEqual(contact.normal, [0.8944, -0.4472, 0], tolerance: 1e-3))
        #expect(approxEqual(contact.depth, 0.9472, tolerance: 1e-3))
        #expect(approxEqual(contact.point, [9.75, -0.5, 0], tolerance: 1e-3))

        // The same pair turned 90° about Y, the slab's rotation included:
        // the box-local transform. Same depth; the normal turns with it.
        let turn = rotation(.halfPi, about: Y_AXIS)
        let turnedContact = try #require(NarrowPhase.shapeVsShape(turned(cap, by: turn), turned(slab, by: turn)))
        #expect(approxEqual(turnedContact.normal, [0, -0.4472, -0.8944], tolerance: 1e-3))
        #expect(approxEqual(turnedContact.depth, 0.9472, tolerance: 1e-3))
    }

    @Test("capsule-box: a core passing a corner at an angle is found by the edge branch")
    func capsuleBoxCorePassingCorner() throws {
        // Core [12, 1.2, 0] → [8, 3, 0], r 1.1 (center [10, 2.1, 0], half
        // height 2.1932, 1.1487 rad about Z). Both ends are 2.0 m from the
        // slab, and so is the center-nearest point (an end), but the core
        // passes 1.0032 m from the corner [10, 1, 0]: the +x, +y edge along
        // z, whose closest point is the contact point. Three probes
        // returned nil here.
        let cap = capsuleAlong(from: [12, 1.2, 0], to: [8, 3, 0], radius: 1.1)
        let contact = try #require(NarrowPhase.shapeVsShape(cap, slab))
        #expect(approxEqual(contact.normal, [0.4104, 0.9119, 0], tolerance: 1e-3))
        #expect(approxEqual(contact.depth, 0.0968, tolerance: 1e-3))
        #expect(approxEqual(contact.point, [10, 1, 0], tolerance: 1e-3))
    }

    @Test("capsule-box: an end inside the slab comes out through the face, at the span's end")
    func capsuleBoxEndInsideSlab() throws {
        // Core [9.8, 0.5, 0] → [1.8, 6.5, 0], r 0.5 (center [5.8, 3.5, 0],
        // half height 5, 0.9273 rad about Z). The first end sits 0.5 m below
        // the top face: +y needs 0.5 + r = 1.0, and the nearest cross axis,
        // [0.6, 0.8, 0], needs 1.02. The point is the span's end deepest
        // against the normal — the end inside. The first draft expected
        // [1, 0, 0] at 0.7 and the second [0, 1, 0] at 0.75; neither depth
        // frees the capsule.
        let cap = capsuleAlong(from: [9.8, 0.5, 0], to: [1.8, 6.5, 0], radius: 0.5)
        let contact = try #require(NarrowPhase.shapeVsShape(cap, slab))
        #expect(approxEqual(contact.normal, [0, 1, 0]))
        #expect(approxEqual(contact.depth, 1.0, tolerance: 1e-3))
        #expect(approxEqual(contact.point, [9.8, 0.5, 0], tolerance: 1e-3))
    }

    @Test("capsule-box: a core through a unit box exits across the core, not along it")
    func capsuleBoxCoreThroughBox() throws {
        // Unit box at the origin; core [−2, 0, 0] → [2, 0, 0], r 0.5 (half
        // height 2, −π/2 about Z). Every direction across the core needs
        // 1 + r = 1.5 and the first tested, +y, wins; along the core 3.5
        // separates. The point is the span's midpoint, the origin. The
        // midpoint probe answered [1, 0, 0] at 1.5.
        let box = collider(.box(halfExtents: [1, 1, 1]), at: .zero)
        let cap = capsuleAlong(from: [-2, 0, 0], to: [2, 0, 0], radius: 0.5)
        let contact = try #require(NarrowPhase.shapeVsShape(cap, box))
        #expect(approxEqual(contact.normal, [0, 1, 0]))
        #expect(approxEqual(contact.depth, 1.5))
        #expect(approxEqual(contact.point, .zero))
    }

    @Test("capsule-box: translating by depth × normal frees the capsule; 0.01 less leaves 0.01 through the outside branch")
    func capsuleBoxDepthFreesTheCapsule() throws {
        // Over the crossing, end-inside, and through-the-box cases: moved by
        // the reported depth along the normal, the pair is nil or touching
        // (depth ≤ 1e-4); moved 0.01 less, it reports 0.01 with the same
        // normal — through the outside branch each time (the corner edge,
        // an end cap, a top-face edge), so the inside and outside
        // constructions agree at the boundary.
        let unitBox = collider(.box(halfExtents: [1, 1, 1]), at: .zero)
        let pairs: [(capsule: WorldCollider, box: WorldCollider)] = [
            (capsuleAlong(from: [8, -4, 0], to: [12, 4, 0], radius: 0.5), slab),
            (capsuleAlong(from: [9.8, 0.5, 0], to: [1.8, 6.5, 0], radius: 0.5), slab),
            (capsuleAlong(from: [-2, 0, 0], to: [2, 0, 0], radius: 0.5), unitBox),
        ]
        for pair in pairs {
            let contact = try #require(NarrowPhase.shapeVsShape(pair.capsule, pair.box))
            let freed = NarrowPhase.shapeVsShape(moved(pair.capsule, by: contact.normal * contact.depth), pair.box)
            #expect((freed?.depth ?? 0) <= 1e-4)

            let almostFreed = try #require(NarrowPhase.shapeVsShape(
                moved(pair.capsule, by: contact.normal * (contact.depth - 0.01)), pair.box))
            #expect(approxEqual(almostFreed.depth, 0.01))
            #expect(approxEqual(almostFreed.normal, contact.normal, tolerance: 1e-3))
        }
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

        // Box-box (C.1) solves both orders directly, no flip path: names AND
        // groups must still land on the caller's sides.
        let wing = collider(.box(halfExtents: [1, 1, 1]), at: [1.5, 0, 0], name: "wing")
        let wall = collider(.box(halfExtents: [1, 1, 1]), at: .zero, name: "wall", group: .structure)
        let wingFirst = try #require(NarrowPhase.shapeVsShape(wing, wall))
        #expect(wingFirst.colliderNameA == "wing")
        #expect(wingFirst.colliderGroupA == .airframe)
        #expect(wingFirst.colliderNameB == "wall")
        #expect(wingFirst.colliderGroupB == .structure)
        #expect(approxEqual(wingFirst.normal, [1, 0, 0]))   // B→A: toward the wing
        #expect(approxEqual(wingFirst.depth, 0.5))

        let wallFirst = try #require(NarrowPhase.shapeVsShape(wall, wing))
        #expect(wallFirst.colliderNameA == "wall")
        #expect(wallFirst.colliderGroupA == .structure)
        #expect(wallFirst.colliderNameB == "wing")
        #expect(wallFirst.colliderGroupB == .airframe)
        #expect(approxEqual(wallFirst.normal, [-1, 0, 0]))  // B→A: toward the wall
        #expect(approxEqual(wallFirst.depth, 0.5))
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
