//
//  CenterOfMassImportTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
import ModelIO
@testable import ToyFlightSimulator

/// The import transform `B = S · B₀ · T_row(−c)` that recenters an aircraft on its center of
/// mass (`Model.ComposeImportTransform`, `Transform.rowVectorTranslationMatrix`). Pure simd, no
/// Metal: the aircraft constants are static lets, so reading them constructs nothing.
///
/// Expected values come from `swift scripts/verify_center_of_mass_math.swift` (sections A–D, H);
/// native nose-tip and nozzle inputs from `swift scripts/measure_center_of_mass.swift`. See
/// plans/claude/aircraft_center_of_mass_recentering_2026-09-25.md.
@Suite("Center-of-mass import transform", .tags(.assetPipeline))
struct CenterOfMassImportTests {

    static let rotate180AroundY = Transform.rotationMatrix(radians: Float(180).toRadians, axis: Y_AXIS)

    /// The bake, exactly as `Mesh.transformMeshBasis` does it: row vector, w = 1 for points.
    private func bakePoint(_ nativePoint: float3, _ importTransform: float4x4) -> float3 {
        simd_mul(float4(nativePoint, 1), importTransform).xyz
    }

    /// w = 0 for normals, tangents and extents: a translation must not move them.
    private func bakeDirection(_ nativeDirection: float3, _ importTransform: float4x4) -> float3 {
        simd_mul(float4(nativeDirection, 0), importTransform).xyz
    }

    /// Height of the straight nose→nozzle line at body z = 0, the station of the pivot. The
    /// roll axis is body +Z through the origin, so 0 means it runs along the fuselage line.
    private func lineHeightAtPivotStation(noseTipInBodyFrame: float3, nozzleCenterInBodyFrame: float3) -> Float {
        let fractionFromNose = noseTipInBodyFrame.z / (noseTipInBodyFrame.z - nozzleCenterInBodyFrame.z)
        return noseTipInBodyFrame.y + fractionFromNose * (nozzleCenterInBodyFrame.y - noseTipInBodyFrame.y)
    }

    private func det3x3(_ m: float4x4) -> Float {
        simd_determinant(simd_float3x3(m.columns.0.xyz, m.columns.1.xyz, m.columns.2.xyz))
    }

    // MARK: - Row-vector translation

    @Test("row-vector translation moves points")
    func rowVectorTranslationMovesPoints() {
        let translation = Transform.rowVectorTranslationMatrix(offset: [0, -1.845, 0])
        #expect(approxEqual(bakePoint([1, 2, 3], translation), [1, 0.155, 3]))
    }

    @Test("row-vector translation leaves directions (w = 0) unchanged")
    func rowVectorTranslationLeavesDirections() {
        let translation = Transform.rowVectorTranslationMatrix(offset: [0, -1.845, 0])
        #expect(bakeDirection([0, 1, 0], translation) == [0, 1, 0])
    }

    @Test("row-vector translation is the transpose of the column-vector form")
    func rowVectorTranslationIsTransposedColumnForm() {
        let offset = float3(0.1, -0.7, 0.4)
        #expect(Transform.rowVectorTranslationMatrix(offset: offset) == Transform.translationMatrix(offset).transpose)
    }

    @Test("trap: a column-vector translation inside the basis is dropped by the bake")
    func columnTranslationIsDroppedByTheBake() {
        // The offset lands in the output's w, which .xyz discards: same result as no translation.
        let withColumnTranslation = Self.rotate180AroundY * Transform.translationMatrix([0, -1.845, 0])
        #expect(approxEqual(bakePoint([1, 2, 3], withColumnTranslation), [-1, 2, -3]))
        #expect(approxEqual(bakePoint([1, 2, 3], withColumnTranslation),
                            bakePoint([1, 2, 3], Self.rotate180AroundY)))
    }

    // MARK: - Composition order and edge cases

    @Test("composing the translation last reads c in engine meters and engine axes")
    func composeOrderPutsCenterOfMassInEngineMeters() {
        let scale: Float = 2.1961696   // CGTrader F-22 meterization factor
        let basis = Transform.transformXMinusZYToXYZ
        let centerOfMass = float3(0, 1, 0)
        let composed = Model.ComposeImportTransform(basisTransform: basis,
                                                    scaleCorrectionFactor: scale,
                                                    centerOfMassInImportFrame: centerOfMass)
        #expect(approxEqual(bakePoint([1, 2, 3], composed), [2.1961696, 5.5885086, -4.392339]))

        // The wrong order subtracts c from NATIVE z (this basis maps native z to engine y).
        let wrongOrder = Transform.rowVectorTranslationMatrix(offset: -centerOfMass)
            * Transform.scaleMatrix(float3(repeating: scale)) * basis
        #expect(approxEqual(bakePoint([1, 2, 3], wrongOrder), [2.1961696, 6.5885086, -2.1961696]))
    }

    @Test("no inputs compose to identity; c = 0 changes nothing")
    func noInputsAndZeroCenterOfMass() {
        #expect(Model.ComposeImportTransform(basisTransform: nil,
                                             scaleCorrectionFactor: nil,
                                             centerOfMassInImportFrame: nil) == .identity)
        let withoutCenterOfMass = Model.ComposeImportTransform(basisTransform: Transform.transformYMinusZXToXYZ,
                                                               scaleCorrectionFactor: 0.0996041,
                                                               centerOfMassInImportFrame: nil)
        let withZeroCenterOfMass = Model.ComposeImportTransform(basisTransform: Transform.transformYMinusZXToXYZ,
                                                                scaleCorrectionFactor: 0.0996041,
                                                                centerOfMassInImportFrame: .zero)
        #expect(withZeroCenterOfMass == withoutCenterOfMass)
    }

    @Test("a center of mass alone still bakes (no basis, no scale)")
    func centerOfMassAloneStillBakes() {
        let composed = Model.ComposeImportTransform(basisTransform: nil,
                                                    scaleCorrectionFactor: nil,
                                                    centerOfMassInImportFrame: [0, 1, 0])
        #expect(approxEqual(bakePoint([1, 2, 3], composed), [1, 1, 3]))
    }

    // MARK: - The Model.init overload

    @Test("Model.init path returns nil with nothing to apply, so Mesh.init skips the vertex pass")
    func modelPathReturnsNilWithNothingToApply() {
        // realWorldLength is nil, so the asset is never measured: an empty MDLAsset is enough.
        let importTransform = Model.ComposeImportTransform(modelName: "plain",
                                                           asset: MDLAsset(),
                                                           mdlMeshes: [],
                                                           basisTransform: nil,
                                                           realWorldLength: nil,
                                                           centerOfMassInImportFrame: nil)
        #expect(importTransform == nil)
    }

    @Test("Model.init path still composes a center of mass given without a basis")
    func modelPathComposesCenterOfMassWithoutBasis() {
        let importTransform = Model.ComposeImportTransform(modelName: "centered",
                                                           asset: MDLAsset(),
                                                           mdlMeshes: [],
                                                           basisTransform: nil,
                                                           realWorldLength: nil,
                                                           centerOfMassInImportFrame: [0, 1, 0])
        #expect(importTransform.map { approxEqual(bakePoint([1, 2, 3], $0), [1, 1, 3]) } == true)
    }

    @Test("both F-18 import paths compose the identical matrix")
    func f18ImportPathsAreCongruent() {
        // ModelLibrary's .F18 (Model.init) and SingleSubmeshMeshLibrary (bypasses it). A
        // mismatch floats every control surface and store off its slot.
        let fuselageTransform = Model.ComposeImportTransform(modelName: "FA-18F",
                                                             asset: MDLAsset(),
                                                             mdlMeshes: [],
                                                             basisTransform: Self.rotate180AroundY,
                                                             realWorldLength: nil,
                                                             centerOfMassInImportFrame: F18.centerOfMassInImportFrame)
        let submeshTransform = Model.ComposeImportTransform(basisTransform: Self.rotate180AroundY,
                                                            scaleCorrectionFactor: nil,
                                                            centerOfMassInImportFrame: F18.centerOfMassInImportFrame)
        #expect(fuselageTransform == submeshTransform)
    }

    // MARK: - Per-aircraft transforms (registered constants)

    @Test("F-18 worked example at the original station: c = (0, 1.845, 0)")
    func f18WorkedExample() {
        let composed = Model.ComposeImportTransform(basisTransform: Self.rotate180AroundY,
                                                    scaleCorrectionFactor: nil,
                                                    centerOfMassInImportFrame: [0, 1.845, 0])
        #expect(approxEqual(bakePoint([0, 1.418, -9.085], composed), [0, -0.427, 9.085], tolerance: 1e-3))
        #expect(approxEqual(bakePoint([0, 2.205, 7.648], composed), [0, 0.360, -7.648], tolerance: 1e-3))
    }

    @Test("F-18: nose tip and nozzle land on either side of the pivot, on the line through it")
    func f18FinalImportTransform() {
        let composed = Model.ComposeImportTransform(basisTransform: Self.rotate180AroundY,
                                                    scaleCorrectionFactor: nil,
                                                    centerOfMassInImportFrame: F18.centerOfMassInImportFrame)
        let noseTip = bakePoint([0, 1.418, -9.085], composed)
        let nozzleCenter = bakePoint([0, 2.205, 7.648], composed)
        #expect(approxEqual(noseTip, [0, -0.510, 10.846], tolerance: 1e-3))
        #expect(approxEqual(nozzleCenter, [0, 0.277, -5.887], tolerance: 1e-3))
        #expect(approxEqual(lineHeightAtPivotStation(noseTipInBodyFrame: noseTip,
                                                     nozzleCenterInBodyFrame: nozzleCenter), 0, tolerance: 1e-3))
    }

    @Test("F-35: scale and center of mass without a basis")
    func f35ImportTransform() {
        let composed = Model.ComposeImportTransform(basisTransform: nil,
                                                    scaleCorrectionFactor: 0.5431731,
                                                    centerOfMassInImportFrame: F35.centerOfMassInImportFrame)
        let noseTip = bakePoint([0, 1.690069, 14.4245], composed)
        let nozzleCenter = bakePoint([-0.0073641, 1.9570189, -10.169871], composed)
        #expect(approxEqual(noseTip, [0, -0.085, 7.835], tolerance: 1e-3))
        #expect(approxEqual(nozzleCenter, [-0.004, 0.060, -5.524], tolerance: 1e-3))
        #expect(approxEqual(lineHeightAtPivotStation(noseTipInBodyFrame: noseTip,
                                                     nozzleCenterInBodyFrame: nozzleCenter), 0, tolerance: 1e-3))
    }

    @Test("Sketchfab F-22: recentered, and the winding flip still happens")
    func sketchfabF22ImportTransform() {
        let composed = Model.ComposeImportTransform(basisTransform: Transform.transformYMinusZXToXYZ,
                                                    scaleCorrectionFactor: 0.0996041,
                                                    centerOfMassInImportFrame: F22.centerOfMassInImportFrame)
        let noseTip = bakePoint([135.4261, 0, 0.5221], composed)
        let nozzlePairCenter = bakePoint([-31.8561, 0, 0], composed)
        #expect(approxEqual(noseTip, [0, -0.034, 10.977], tolerance: 1e-3))
        #expect(approxEqual(nozzlePairCenter, [0, 0.018, -5.685], tolerance: 1e-3))
        #expect(approxEqual(lineHeightAtPivotStation(noseTipInBodyFrame: noseTip,
                                                     nozzleCenterInBodyFrame: nozzlePairCenter), 0, tolerance: 1e-3))
        #expect(det3x3(composed) < 0)
    }

    // MARK: - What the translation must not change

    @Test("recentering keeps the winding determinant: det(s·B₀·T) = s³·det(B₀)")
    func recenteringKeepsWindingSign() {
        let scale: Float = 2.1961696
        let composed = Model.ComposeImportTransform(basisTransform: Transform.transformXMinusZYToXYZ,
                                                    scaleCorrectionFactor: scale,
                                                    centerOfMassInImportFrame: [0, 1, 0])
        #expect(approxEqual(det3x3(composed), scale * scale * scale * det3x3(Transform.transformXMinusZYToXYZ),
                            tolerance: 1e-3))
        #expect(approxEqual(det3x3(composed), 10.59248, tolerance: 1e-3))
    }

    @Test("recentering keeps the meterized length extent (w = 0)")
    func recenteringKeepsLengthExtent() {
        let composed = Model.ComposeImportTransform(basisTransform: Self.rotate180AroundY,
                                                    scaleCorrectionFactor: nil,
                                                    centerOfMassInImportFrame: F18.centerOfMassInImportFrame)
        #expect(approxEqual(Model.GetLengthAxisExtent(nativeExtent: [13.654, 5.149, 18.267], basisTransform: composed),
                            18.267, tolerance: 1e-3))
    }
}
