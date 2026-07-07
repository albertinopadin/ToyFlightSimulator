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
}
