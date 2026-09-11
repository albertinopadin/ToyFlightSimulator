//
//  StaticStructureShapeTests.swift
//  ToyFlightSimulatorTests
//
//  C.2 (C-structures): StaticStructure.Shape is authored in full building
//  dimensions (a 40 × 12 × 3 m wall) and maps to the ColliderShape its body
//  carries. The mapping is a pure computed property on a nested enum, so no
//  GameObject is built and no Metal is needed. The mesh side of "the mesh is
//  the collider" is checked through ModelIO's extent semantics with a nil
//  allocator, the way MeshBoundsTests does.
//

import Testing
import ModelIO
import simd
@testable import ToyFlightSimulator

@Suite("StaticStructure shape mapping", .tags(.physics, .gameObjects))
struct StaticStructureShapeTests {

    @Test("box: full extents map to half extents")
    func boxMapsToHalfExtents() {
        // The hangar's left wall (3 m thick, 12 m tall, 40 m deep) and roof.
        #expect(StaticStructure.Shape.box(size: [3, 12, 40]).collider == .box(halfExtents: [1.5, 6, 20]))
        #expect(StaticStructure.Shape.box(size: [43, 2, 40]).collider == .box(halfExtents: [21.5, 1, 20]))
    }

    @Test("capsule: halfHeight is height/2 − radius, so cap to cap is the authored height")
    func capsuleMapsToCoreHalfHeight() throws {
        // A tree: 10 m cap to cap on a 0.5 m radius is a 9 m core, half 4.5.
        let collider = StaticStructure.Shape.capsule(radius: 0.5, height: 10).collider
        #expect(collider == .capsule(radius: 0.5, halfHeight: 4.5))

        // ColliderShape's own contract: total height = 2·(halfHeight + radius).
        guard case .capsule(let radius, let halfHeight) = collider else {
            Issue.record("expected a capsule, got \(collider)")
            return
        }
        #expect(approxEqual(2 * (halfHeight + radius), 10))
    }

    @Test("capsule no taller than its diameter: halfHeight 0, which LocalCollider accepts as a sphere-equivalent")
    func stubbyCapsuleClampsToSphereEquivalent() {
        // Exactly two radii: the core has zero length.
        #expect(StaticStructure.Shape.capsule(radius: 1, height: 2).collider == .capsule(radius: 1, halfHeight: 0))

        // Shorter than two radii: clamped at 0 rather than going negative,
        // which LocalCollider's dimension assert would reject.
        let squashed = StaticStructure.Shape.capsule(radius: 1, height: 1.5).collider
        #expect(squashed == .capsule(radius: 1, halfHeight: 0))
        #expect(squashed.hasFinitePositiveDimensions)
        let local = LocalCollider(name: "stub", shape: squashed, group: .structure)
        #expect(local.shape == squashed)
        #expect(local.group == .structure)
    }

    @Test("the mesh is the collider: ModelIO's box and capsule bounds equal the collider's reach")
    func meshBoundsMatchCollider() {
        // Mirrors StaticStructure.makeMesh's constructor arguments —
        // CubeMesh(extent: size) builds MDLMesh(boxWithExtent: size), and
        // CapsuleMesh(radius:length:) builds MDLMesh(capsuleWithExtent:
        // [r, h, r]) — with a nil allocator, so no Metal device is needed.
        let wallSize: float3 = [3, 12, 40]
        let boxMesh = MDLMesh(boxWithExtent: wallSize,
                              segments: [1, 1, 1],
                              inwardNormals: false,
                              geometryType: .triangles,
                              allocator: nil)
        guard case .box(let halfExtents) = StaticStructure.Shape.box(size: wallSize).collider else {
            Issue.record("expected a box")
            return
        }
        #expect(approxEqual(boxMesh.boundingBox.maxBounds, halfExtents, tolerance: 1e-4))
        #expect(approxEqual(boxMesh.boundingBox.minBounds, -halfExtents, tolerance: 1e-4))

        let treeRadius: Float = 0.5
        let treeHeight: Float = 10
        let capsuleMesh = MDLMesh(capsuleWithExtent: [treeRadius, treeHeight, treeRadius],
                                  cylinderSegments: vector_uint2(32, 32),
                                  hemisphereSegments: 32,
                                  inwardNormals: false,
                                  geometryType: .triangles,
                                  allocator: nil)
        guard case .capsule(let radius, let halfHeight) =
                StaticStructure.Shape.capsule(radius: treeRadius, height: treeHeight).collider else {
            Issue.record("expected a capsule")
            return
        }
        // The collider reaches radius sideways and halfHeight + radius along
        // its axis; the mesh's y extent is the cap-to-cap length.
        let reach: float3 = [radius, halfHeight + radius, radius]
        #expect(approxEqual(capsuleMesh.boundingBox.maxBounds, reach, tolerance: 1e-3))
        #expect(approxEqual(capsuleMesh.boundingBox.minBounds, -reach, tolerance: 1e-3))
    }
}
