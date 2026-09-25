//
//  SingleMeshVertexMetadataTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("SingleMeshVertexMetadata basis transform", .tags(.assetPipeline))
struct SingleMeshVertexMetadataTests {

    private func makeMetadata(centroid: float3 = float3(1.5, -2.0, 7.25)) -> SingleMeshVertexMetadata {
        SingleMeshVertexMetadata(initialPositionInParentMesh: centroid,
                                 uniqueVertices: 42,
                                 minX: -1,
                                 maxX: 2,
                                 minY: -3,
                                 maxY: 4,
                                 minZ: -5,
                                 maxZ: 6)
    }

    @Test("Identity basis leaves all fields unchanged")
    func identityBasisIsNoOp() {
        let m = makeMetadata()
        let t = m.transformingCentroid(by: .identity)

        #expect(approxEqual(t.initialPositionInParentMesh, m.initialPositionInParentMesh))
        #expect(t.uniqueVertices == m.uniqueVertices)
        #expect(t.minX == m.minX)
        #expect(t.maxX == m.maxX)
        #expect(t.minY == m.minY)
        #expect(t.maxY == m.maxY)
        #expect(t.minZ == m.minZ)
        #expect(t.maxZ == m.maxZ)
    }

    @Test("rotate180AroundY (the F-18 submesh basis) negates centroid X and Z")
    func rotate180AroundYNegatesXZ() {
        // Same construction as SingleSubmeshMeshLibrary.makeLibrary:
        let basis = Transform.rotationMatrix(radians: Float(180).toRadians, axis: Y_AXIS)
        let m = makeMetadata(centroid: float3(1.5, -2.0, 7.25))
        let t = m.transformingCentroid(by: basis)

        #expect(approxEqual(t.initialPositionInParentMesh, float3(-1.5, -2.0, -7.25)))

        // Min/max bounds are intentionally left in pre-basis space (see the
        // transformingCentroid doc comment):
        #expect(t.uniqueVertices == m.uniqueVertices)
        #expect(t.minX == m.minX)
        #expect(t.maxX == m.maxX)
        #expect(t.minY == m.minY)
        #expect(t.maxY == m.maxY)
        #expect(t.minZ == m.minZ)
        #expect(t.maxZ == m.maxZ)
    }

    @Test("Centroid transforms with Mesh's row-vector (v * B) convention")
    func matchesMeshRowVectorConvention() {
        // Put a translation in the row-vector slot (w component of column 0).
        // Under v * B — the convention Mesh.transformMeshBasis applies to the
        // geometry — this adds +5 to x; a column-vector (B * v) implementation
        // would leave the centroid unchanged.
        var basis = matrix_identity_float4x4
        basis.columns.0.w = 5
        let m = makeMetadata(centroid: float3(1, 2, 3))
        let t = m.transformingCentroid(by: basis)

        #expect(approxEqual(t.initialPositionInParentMesh, float3(6, 2, 3)))
    }

    // MARK: - Center-of-mass recentering (the F-18 submesh import transform)

    /// Same construction as SingleSubmeshMeshLibrary.makeLibrary.
    private func f18SubmeshImportTransform(centerOfMass: float3) -> float4x4 {
        Model.ComposeImportTransform(basisTransform: Transform.rotationMatrix(radians: Float(180).toRadians, axis: Y_AXIS),
                                     scaleCorrectionFactor: nil,
                                     centerOfMassInImportFrame: centerOfMass)
    }

    @Test("centroid carries the recentering (c at the original station)")
    func centroidCarriesRecentering() {
        let m = makeMetadata(centroid: float3(-5.462, 2.084, 3.773))
        let t = m.transformingCentroid(by: f18SubmeshImportTransform(centerOfMass: [0, 1.845, 0]))
        #expect(approxEqual(t.initialPositionInParentMesh, float3(5.462, 0.239, -3.773), tolerance: 1e-3))
    }

    @Test("centroid carries the registered F-18 center of mass")
    func centroidCarriesFinalF18Recentering() {
        let m = makeMetadata(centroid: float3(-5.462, 2.084, 3.773))
        let t = m.transformingCentroid(by: f18SubmeshImportTransform(centerOfMass: F18.centerOfMassInImportFrame))
        #expect(approxEqual(t.initialPositionInParentMesh, float3(5.462, 0.156, -2.012), tolerance: 1e-3))
    }

    @Test("recentering cancels in submesh-local vertices; only the centroid moves, by −c")
    func recenteringCancelsInSubmeshLocalVertices() {
        // SingleSubmeshMesh.init subtracts the baked centroid from its baked vertices, so a
        // vertex relative to its centroid is the same with or without c. That is why
        // F18.setupControlSurfaces (hinge offsets from each centroid) needs no change.
        let bareBasis = Transform.rotationMatrix(radians: Float(180).toRadians, axis: Y_AXIS)
        let recentered = f18SubmeshImportTransform(centerOfMass: F18.centerOfMassInImportFrame)
        let nativeVertex = float3(-5.0, 2.3, 4.1)
        let nativeCentroid = float3(-5.462, 2.084, 3.773)
        func bake(_ point: float3, _ transform: float4x4) -> float3 { simd_mul(float4(point, 1), transform).xyz }

        #expect(approxEqual(bake(nativeVertex, recentered) - bake(nativeCentroid, recentered),
                            bake(nativeVertex, bareBasis) - bake(nativeCentroid, bareBasis), tolerance: 1e-5))
        #expect(approxEqual(bake(nativeCentroid, recentered) - bake(nativeCentroid, bareBasis),
                            -F18.centerOfMassInImportFrame, tolerance: 1e-5))
    }
}
