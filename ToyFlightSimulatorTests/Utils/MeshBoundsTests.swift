//
//  MeshBoundsTests.swift
//  ToyFlightSimulatorTests
//
//  Step 0.8: pins the MEASURED ModelIO extent semantics (2026-08-27, macOS 26)
//  that ColliderOverlayMapping depends on. nil allocator = MDLMeshBufferData,
//  no Metal. If a future ModelIO changes these, the collider overlay's
//  capsule/box math is what breaks — this suite is the early alarm.
//

import Testing
import ModelIO
import simd
@testable import ToyFlightSimulator

@Suite("MDLMesh extent semantics", .tags(.utils))
struct MeshBoundsTests {

    private func bounds(of mesh: MDLMesh) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        let box = mesh.boundingBox
        return (box.minBounds, box.maxBounds)
    }

    @Test("capsuleWithExtent [1,5,1] → bounds ±[1, 2.5, 1] (x/z = RADIUS, y = total length)")
    func capsuleExtentIsRadiusAndTotalLength() {
        // Mirrors CapsuleMesh's constructor call (BasicMeshes.swift) with a
        // nil allocator. CapsuleMesh(radius: 1, length: 5) builds exactly this.
        let capsule = MDLMesh(capsuleWithExtent: [1, 5, 1],
                              cylinderSegments: vector_uint2(16, 16),
                              hemisphereSegments: 8,
                              inwardNormals: false,
                              geometryType: .triangles,
                              allocator: nil)
        let b = bounds(of: capsule)
        #expect(approxEqual(b.min, [-1, -2.5, -1], tolerance: 1e-3))
        #expect(approxEqual(b.max, [1, 2.5, 1], tolerance: 1e-3))
    }

    @Test("boxWithExtent [1,2,3] → bounds ±[0.5, 1, 1.5] (extent IS full extent)")
    func boxExtentIsFullExtent() {
        let box = MDLMesh(boxWithExtent: [1, 2, 3],
                          segments: [1, 1, 1],
                          inwardNormals: false,
                          geometryType: .triangles,
                          allocator: nil)
        let b = bounds(of: box)
        #expect(approxEqual(b.min, [-0.5, -1, -1.5], tolerance: 1e-4))
        #expect(approxEqual(b.max, [0.5, 1, 1.5], tolerance: 1e-4))
    }

    @Test("sphereWithExtent [2,2,2] → bounds ±2 (RADIUS semantics — the latent SphereMesh 2× quirk)")
    func sphereExtentIsRadius() {
        // SphereMesh(radius:) passes the DIAMETER as extent, so it builds a
        // mesh twice the requested size. Latent today: the overlay's sphere
        // path uses the OBJ unit sphere (ModelType.Sphere), never SphereMesh.
        let sphere = MDLMesh(sphereWithExtent: [2, 2, 2],
                             segments: SIMD2<UInt32>(16, 16),
                             inwardNormals: false,
                             geometryType: .triangles,
                             allocator: nil)
        let b = bounds(of: sphere)
        #expect(approxEqual(b.min, [-2, -2, -2], tolerance: 1e-3))
        #expect(approxEqual(b.max, [2, 2, 2], tolerance: 1e-3))
    }
}
