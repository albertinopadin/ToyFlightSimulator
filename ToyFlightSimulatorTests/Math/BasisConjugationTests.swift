//
//  BasisConjugationTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

/// `Transform.basisConjugationMatrices` maps native-space animation deltas into engine
/// space (P = Bᵀ · M · (Bᵀ)⁻¹). Two properties matter: exact agreement with the legacy
/// B⁻¹ · M · B form for orthonormal permutation bases, and correct s-scaling of
/// translations for a meterized basis B = S·B₀ (the legacy form divided translations
/// by s — an s² error).
@Suite("Basis conjugation", .tags(.math))
struct BasisConjugationTests {

    /// A representative native-space delta: rotate about X, then translate.
    private var nativeDelta: float4x4 {
        Transform.translationMatrix([0.5, -1.25, 2.0])
            * Transform.rotationMatrix(radians: 0.7, axis: [1, 0, 0])
    }

    @Test("orthonormal bases: matches the legacy inverse conjugation")
    func orthonormalMatchesLegacy() {
        let bases = [Transform.transformXMinusZYToXYZ,
                     Transform.transformYMinusZXToXYZ,
                     Transform.rotationMatrix(radians: Float(180).toRadians, axis: [0, 1, 0])]
        for basis in bases {
            let (left, right) = Transform.basisConjugationMatrices(for: basis)
            let modern = left * nativeDelta * right
            let legacy = basis.inverse * nativeDelta * basis
            #expect(approxEqual(modern, legacy, tolerance: 1e-5))
        }
    }

    @Test("meterized basis: conjugated translations scale by s (not 1/s)")
    func meterizedScalesTranslationByS() {
        let s: Float = 2.1961696   // CGTrader F-22 meterization factor
        let b0 = Transform.transformXMinusZYToXYZ
        let meterized = Transform.scaleMatrix(SIMD3<Float>(repeating: s)) * b0

        let t = SIMD3<Float>(1, -2, 3)
        var delta = matrix_identity_float4x4
        delta.columns.3 = simd_float4(t, 1)   // column-convention translation, as ModelIO joint deltas are

        let (left, right) = Transform.basisConjugationMatrices(for: meterized)
        let conjugated = left * delta * right

        // Engine-space translation = s · (B₀ᵀ · t); column action of B₀ᵀ = row action of B₀.
        let expected = s * simd_mul(simd_float4(t, 0), b0).xyz
        #expect(approxEqual(conjugated.columns.3.xyz, expected, tolerance: 1e-3))

        // Linear block of a conjugated pure translation stays identity.
        #expect(approxEqual(conjugated.columns.0.xyz, [1, 0, 0], tolerance: 1e-4))
        #expect(approxEqual(conjugated.columns.1.xyz, [0, 1, 0], tolerance: 1e-4))
        #expect(approxEqual(conjugated.columns.2.xyz, [0, 0, 1], tolerance: 1e-4))

        // The legacy inverse form is exactly the s² regression this API fixes.
        let legacy = meterized.inverse * delta * meterized
        #expect(approxEqual(legacy.columns.3.xyz, expected / (s * s), tolerance: 1e-3))
    }

    @Test("meterized basis: rotation deltas conjugate identically to the unscaled basis")
    func meterizedPreservesRotationConjugation() {
        let s: Float = 0.017227821   // Sketchfab F-22 meterization factor
        let b0 = Transform.transformYMinusZXToXYZ
        let meterized = Transform.scaleMatrix(SIMD3<Float>(repeating: s)) * b0
        let rotation = Transform.rotationMatrix(radians: 1.1, axis: [0, 0, 1])

        let (left, right) = Transform.basisConjugationMatrices(for: meterized)
        let (left0, right0) = Transform.basisConjugationMatrices(for: b0)
        #expect(approxEqual(left * rotation * right, left0 * rotation * right0, tolerance: 1e-4))
    }

    // MARK: - Translation-bearing import transforms (center-of-mass recentering)

    /// Bake a native point into the body frame the way `Mesh.transformMeshBasis` does (row vector).
    private func bake(_ nativePoint: SIMD3<Float>, _ importTransform: float4x4) -> SIMD3<Float> {
        simd_mul(simd_float4(nativePoint, 1), importTransform).xyz
    }

    private func randomUnitAxis(_ random: inout SplitMix64) -> SIMD3<Float> {
        while true {
            let candidate = SIMD3<Float>(random.float(in: -1...1), random.float(in: -1...1), random.float(in: -1...1))
            if simd_length(candidate) > 0.1 { return simd_normalize(candidate) }
        }
    }

    @Test("recentered import transforms: moving then baking equals baking then moving by the conjugated delta")
    func translationBearingBasisConjugatesExactly() {
        // P = Bᵀ·J·(Bᵀ)⁻¹ assumes nothing about B having no translation, so skinning and node
        // animation stay exact after recentering, as long as they get the FULL import transform.
        let rotate180AroundY = Transform.rotationMatrix(radians: Float(180).toRadians, axis: [0, 1, 0])
        let importTransforms: [(name: String, transform: float4x4)] = [
            ("F-18", Model.ComposeImportTransform(basisTransform: rotate180AroundY,
                                                  scaleCorrectionFactor: nil,
                                                  centerOfMassInImportFrame: F18.centerOfMassInImportFrame)),
            ("F-35", Model.ComposeImportTransform(basisTransform: nil,
                                                  scaleCorrectionFactor: 0.5431731,
                                                  centerOfMassInImportFrame: F35.centerOfMassInImportFrame)),
            ("CGTrader-like, off-axis c", Model.ComposeImportTransform(basisTransform: Transform.transformXMinusZYToXYZ,
                                                                       scaleCorrectionFactor: 2.1961696,
                                                                       centerOfMassInImportFrame: [0.1, -0.7, 0.4])),
        ]
        var random = SplitMix64(seed: 0x00C0_FFEE)
        for (name, importTransform) in importTransforms {
            let (left, right) = Transform.basisConjugationMatrices(for: importTransform)
            var worstErrorMeters: Float = 0
            for _ in 0..<200 {
                let jointDelta = Transform.translationMatrix([random.float(in: -3...3),
                                                              random.float(in: -3...3),
                                                              random.float(in: -3...3)])
                    * Transform.rotationMatrix(radians: random.float(in: -Float.pi...Float.pi),
                                               axis: randomUnitAxis(&random))
                let nativePoint = SIMD3<Float>(random.float(in: -10...10),
                                               random.float(in: -10...10),
                                               random.float(in: -10...10))
                let movedThenBaked = bake(simd_mul(jointDelta, simd_float4(nativePoint, 1)).xyz, importTransform)
                let bakedThenMoved = simd_mul(left * jointDelta * right, simd_float4(bake(nativePoint, importTransform), 1)).xyz
                worstErrorMeters = max(worstErrorMeters, simd_length(movedThenBaked - bakedThenMoved))
            }
            #expect(worstErrorMeters < 1e-4, "\(name): worst \(worstErrorMeters) m")
        }
    }

    @Test("a skeleton given the basis WITHOUT the translation misplaces skinned vertices by |(I − R)·c|")
    func basisWithoutTheTranslationMisplacesSkinnedVertices() {
        // The failure mode if recentering were a separate vertex pass: the vertices move by −c,
        // the joint conjugation does not. For a 90° rotation about X and c = (0, 1.845, 0) the
        // error is 1.845·√2 = 2.609 m for every vertex.
        let rotate180AroundY = Transform.rotationMatrix(radians: Float(180).toRadians, axis: [0, 1, 0])
        let fullImportTransform = Model.ComposeImportTransform(basisTransform: rotate180AroundY,
                                                               scaleCorrectionFactor: nil,
                                                               centerOfMassInImportFrame: [0, 1.845, 0])
        let (staleLeft, staleRight) = Transform.basisConjugationMatrices(for: rotate180AroundY)
        let jointRotation = Transform.rotationMatrix(radians: Float(90).toRadians, axis: [1, 0, 0])
        for nativePoint: SIMD3<Float> in [[0, 0, 0], [1, 2, 3], [-4, 0.5, 7]] {
            let correct = bake(simd_mul(jointRotation, simd_float4(nativePoint, 1)).xyz, fullImportTransform)
            let stale = simd_mul(staleLeft * jointRotation * staleRight,
                                 simd_float4(bake(nativePoint, fullImportTransform), 1)).xyz
            #expect(approxEqual(simd_length(correct - stale), 2.609, tolerance: 1e-3))
        }
    }
}
