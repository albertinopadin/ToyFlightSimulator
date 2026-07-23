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
}
