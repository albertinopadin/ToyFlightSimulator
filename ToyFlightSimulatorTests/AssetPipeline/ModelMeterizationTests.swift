//
//  ModelMeterizationTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

/// Pure meterization math in `Model` — no Metal, no Model construction. Native
/// (pre-basis) bounding-box extents measured by `scripts/measure_models.swift`
/// (research/claude/meter_scale_units_research_2026-07-20.md §2.2) serve as fixtures.
@Suite("Model meterization", .tags(.assetPipeline))
struct ModelMeterizationTests {

    static let rotate180AroundY = Transform.rotationMatrix(radians: Float(180).toRadians,
                                                           axis: [0, 1, 0])

    // MARK: - GetLengthAxisExtent per registered aircraft basis

    @Test("nil basis reads the native Z extent (F-35 registration shape)")
    func nilBasisReadsNativeZ() {
        let f35Extent = SIMD3<Float>(302.5, 111.9, 433.6)
        #expect(approxEqual(Model.GetLengthAxisExtent(nativeExtent: f35Extent), 433.6))
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
        let extent = SIMD3<Float>(1098.2236, 300.0, 784.0)
        let length = Model.GetLengthAxisExtent(nativeExtent: extent,
                                               basisTransform: Transform.transformYMinusZXToXYZ)
        #expect(approxEqual(length, 1098.2236, tolerance: 1e-3))
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

        let sketchfabF22 = 18.92 / Model.GetLengthAxisExtent(nativeExtent: [1098.2236, 300.0, 784.0],
                                                             basisTransform: Transform.transformYMinusZXToXYZ)
        #expect(approxEqual(sketchfabF22, 0.017227821, tolerance: 1e-6))

        let f16 = 15.06 / Model.GetLengthAxisExtent(nativeExtent: [1.47, 0.69, 2.253],
                                                    basisTransform: Self.rotate180AroundY)
        #expect(approxEqual(f16, 6.6844, tolerance: 1e-3))

        let f35 = 15.67 / Model.GetLengthAxisExtent(nativeExtent: [302.5, 111.9, 433.6])
        #expect(approxEqual(f35, 0.0361393, tolerance: 1e-5))
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
        let meterized = Transform.scaleMatrix(SIMD3<Float>(repeating: 0.017227821)) * basis
        #expect(det3x3(basis) < 0)
        #expect((det3x3(meterized) < 0) == (det3x3(basis) < 0))
    }

    private func det3x3(_ m: float4x4) -> Float {
        simd_determinant(simd_float3x3(m.columns.0.xyz, m.columns.1.xyz, m.columns.2.xyz))
    }
}
