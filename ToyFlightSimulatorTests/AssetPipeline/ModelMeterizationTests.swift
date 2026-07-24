//
//  ModelMeterizationTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

/// Pure meterization math in `Model` — no Metal, no Model construction. Fixtures are
/// DRAW-SPACE native extents (mesh-local bounds through scale-stripped node transforms —
/// the space `Model.DrawSpaceNativeExtent` measures and the renderer draws), measured in
/// debugging/claude/sketchfab_f22_f35_meterization_node_scale.md §2. Stage-space numbers
/// (`MDLAsset.boundingBox`, scripts/measure_models.swift §2.2) over-count USD node scale
/// and must NOT be used as fixtures here.
@Suite("Model meterization", .tags(.assetPipeline))
struct ModelMeterizationTests {

    static let rotate180AroundY = Transform.rotationMatrix(radians: Float(180).toRadians,
                                                           axis: [0, 1, 0])

    // MARK: - GetLengthAxisExtent per registered aircraft basis

    @Test("nil basis reads the native Z extent (F-35 registration shape)")
    func nilBasisReadsNativeZ() {
        let f35Extent = SIMD3<Float>(25.306, 6.175, 28.849)
        #expect(approxEqual(Model.GetLengthAxisExtent(nativeExtent: f35Extent), 28.849))
    }

    @Test("rotate180AroundY maps native Z onto engine −Z; abs recovers it (F-16/F-18)")
    func rotatedBasisReadsNativeZ() {
        let f16Extent = SIMD3<Float>(1.47, 0.69, 2.253)
        let length = Model.GetLengthAxisExtent(nativeExtent: f16Extent,
                                               basisTransform: Self.rotate180AroundY)
        #expect(approxEqual(length, 2.253))
    }

    @Test("CGTrader F-22 basis maps native Y (length axis) onto engine Z")
    func cgtraderBasisReadsNativeY() {
        let extent = SIMD3<Float>(6.220, 8.615, 2.456)
        let length = Model.GetLengthAxisExtent(nativeExtent: extent,
                                               basisTransform: Transform.transformXMinusZYToXYZ)
        #expect(approxEqual(length, 8.615))
    }

    @Test("Sketchfab F-22 basis maps native X (length axis) onto engine Z")
    func sketchfabBasisReadsNativeX() {
        // Mesh-local union — this asset's node transforms never apply at draw (empty time range).
        let extent = SIMD3<Float>(189.952, 135.606, 51.889)
        let length = Model.GetLengthAxisExtent(nativeExtent: extent,
                                               basisTransform: Transform.transformYMinusZXToXYZ)
        #expect(approxEqual(length, 189.952, tolerance: 1e-3))
    }

    @Test("a translation-bearing basis does not offset the measured extent")
    func translationDoesNotOffsetExtent() {
        // Row-vector convention puts a basis translation in the w components of
        // columns 0-2. It must move points (recentering) but never resize extents.
        var basis = Transform.transformXMinusZYToXYZ
        basis.columns.0.w = 100
        basis.columns.1.w = 200
        basis.columns.2.w = 300
        let extent = SIMD3<Float>(6.220, 8.615, 2.456)
        #expect(approxEqual(Model.GetLengthAxisExtent(nativeExtent: extent, basisTransform: basis),
                            8.615))
    }

    // MARK: - Meterization factor + composed basis properties

    @Test("calibration factors reproduce the research-doc table")
    func calibrationFactors() {
        // realWorldLength / nativeLength — the exact computation Model.init performs.
        let cgtrader = 18.92 / Model.GetLengthAxisExtent(nativeExtent: [6.220, 8.615, 2.456],
                                                         basisTransform: Transform.transformXMinusZYToXYZ)
        #expect(approxEqual(cgtrader, 2.1961696))

        let sketchfabF22 = 18.92 / Model.GetLengthAxisExtent(nativeExtent: [189.952, 135.606, 51.889],
                                                             basisTransform: Transform.transformYMinusZXToXYZ)
        #expect(approxEqual(sketchfabF22, 0.0996041, tolerance: 1e-6))

        let f16 = 15.06 / Model.GetLengthAxisExtent(nativeExtent: [1.47, 0.69, 2.253],
                                                    basisTransform: Self.rotate180AroundY)
        #expect(approxEqual(f16, 6.6844, tolerance: 1e-3))

        let f35 = 15.67 / Model.GetLengthAxisExtent(nativeExtent: [25.306, 6.175, 28.849])
        #expect(approxEqual(f35, 0.5431731, tolerance: 1e-5))
    }

    @Test("meterized basis (scale * basis) uniformly scales permuted points")
    func meterizedBasisScalesAndPermutes() {
        let s: Float = 2.1961696
        let basis = Transform.transformXMinusZYToXYZ
        // Same composition Model.init uses.
        let meterized = Transform.scaleMatrix(SIMD3<Float>(repeating: s)) * basis
        let native = simd_float4(1, 2, 3, 1)
        let expected = s * simd_mul(native, basis).xyz
        #expect(approxEqual(simd_mul(native, meterized).xyz, expected))
    }

    @Test("uniform scale preserves the winding-decision determinant sign")
    func meterizedBasisPreservesWindingSign() {
        // Sketchfab F-22's basis is orientation-reversing (det < 0) — the case where
        // Mesh.transformMeshBasis reverses triangle winding. det(s·B) = s³·det(B)
        // must keep that decision unchanged.
        let basis = Transform.transformYMinusZXToXYZ
        let meterized = Transform.scaleMatrix(SIMD3<Float>(repeating: 0.0996041)) * basis
        #expect(det3x3(basis) < 0)
        #expect((det3x3(meterized) < 0) == (det3x3(basis) < 0))
    }

    // MARK: - Draw-space measurement (scale-stripped node transforms)

    @Test("scaleStrippedTransform drops scale, keeps rotation, and unscales translation")
    func scaleStrippedTransformDropsScale() {
        let rotation = Transform.rotationMatrix(radians: Float(90).toRadians, axis: [1, 0, 0])
        let trs = Transform.matrixFromTR(translation: [10, -20, 30], rotation: rotation)
            * Transform.scaleMatrix(SIMD3<Float>(repeating: 5.7816))
        let stripped = Transform.scaleStrippedTransform(trs)
        let expected = Transform.matrixFromTR(translation: SIMD3<Float>(10, -20, 30) / 5.7816,
                                              rotation: rotation)
        #expect(approxEqual(stripped, expected, tolerance: 1e-5))
    }

    @Test("scaleStrippedTransform is the identity on scale-free transforms")
    func scaleStrippedTransformIdentityPassthrough() {
        let rotation = Transform.rotationMatrix(radians: Float(37).toRadians, axis: [0, 1, 0])
        let tr = Transform.matrixFromTR(translation: [1, 2, 3], rotation: rotation)
        #expect(approxEqual(Transform.scaleStrippedTransform(tr), tr, tolerance: 1e-5))
    }

    @Test("UnionTransformedExtent with identity transforms is the plain bbox union (CGTrader shape)")
    func unionExtentIdentityTransforms() {
        let extent = Model.UnionTransformedExtent(meshBounds: [
            (minBounds: [-3.11, -4.31, -1.23], maxBounds: [3.11, 4.31, 1.23], nodeTransform: .identity),
        ])
        #expect(approxEqual(extent, SIMD3<Float>(6.22, 8.62, 2.46), tolerance: 1e-2))
        #expect(Model.UnionTransformedExtent(meshBounds: []) == .zero)
    }

    @Test("node rotation reorients a mesh-local box (F-35 'Meshes' node shape)")
    func unionExtentAppliesNodeRotation() {
        // 90° about X maps local Y onto stage Z — the F-35's length lands on Z.
        let rotX90 = Transform.rotationMatrix(radians: Float(90).toRadians, axis: [1, 0, 0])
        let extent = Model.UnionTransformedExtent(meshBounds: [
            (minBounds: [0, 0, 0], maxBounds: [20, 29, 7], nodeTransform: rotX90),
        ])
        #expect(approxEqual(extent, SIMD3<Float>(20, 7, 29), tolerance: 1e-3))
    }

    @Test("per-mesh node translations spread the union (multi-part assemblies)")
    func unionExtentSpreadsTranslatedParts() {
        let forward = Transform.matrixFromTR(translation: [0, 0, 10], rotation: .identity)
        let aft = Transform.matrixFromTR(translation: [0, 0, -10], rotation: .identity)
        let cube: (SIMD3<Float>, SIMD3<Float>) = ([-1, -1, -1], [1, 1, 1])
        let extent = Model.UnionTransformedExtent(meshBounds: [
            (minBounds: cube.0, maxBounds: cube.1, nodeTransform: forward),
            (minBounds: cube.0, maxBounds: cube.1, nodeTransform: aft),
        ])
        #expect(approxEqual(extent, SIMD3<Float>(2, 2, 22)))
    }

    @Test("regression: a scale-bearing node transform, once stripped, cannot shrink the meterized aircraft")
    func strippedNodeScaleDoesNotShrinkExtent() {
        // The bug this file now guards against: MDLAsset.boundingBox counted the Sketchfab
        // F-22's ×5.7816 root node scale, which TransformComponent strips at draw time, so
        // s came out 5.78× too small and the jet rendered 3.27 m long.
        let scaleOnlyNode = Transform.scaleMatrix(SIMD3<Float>(repeating: 5.7816))
        let stripped = Transform.scaleStrippedTransform(scaleOnlyNode)
        let extent = Model.UnionTransformedExtent(meshBounds: [
            (minBounds: [0, 0, 0], maxBounds: [189.952, 135.606, 51.889], nodeTransform: stripped),
        ])
        #expect(approxEqual(extent, SIMD3<Float>(189.952, 135.606, 51.889), tolerance: 1e-3))
        let s = 18.92 / Model.GetLengthAxisExtent(nativeExtent: extent,
                                                  basisTransform: Transform.transformYMinusZXToXYZ)
        #expect(approxEqual(s, 0.0996041, tolerance: 1e-5))
    }

    private func det3x3(_ m: float4x4) -> Float {
        simd_determinant(simd_float3x3(m.columns.0.xyz, m.columns.1.xyz, m.columns.2.xyz))
    }
}
