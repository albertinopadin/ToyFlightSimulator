//
//  AttachedCameraTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("AttachedCamera scale strip", .tags(.math))
struct AttachedCameraTests {

    /// A translation * rotation * uniform-scale world matrix, like an attached
    /// camera inherits from a scaled parent jet.
    private func world(scale: Float) -> float4x4 {
        let t = Transform.translationMatrix(SIMD3<Float>(100, 50, -30))
        let r = Transform.rotationMatrix(radians: 0.7, axis: SIMD3<Float>(0, 1, 0))
              * Transform.rotationMatrix(radians: -0.3, axis: SIMD3<Float>(1, 0, 0))
        let s = Transform.scaleMatrix(SIMD3<Float>(scale, scale, scale))
        return t * r * s
    }

    @Test("scaleStrippedInverse is independent of uniform parent scale")
    func independentOfScale() {
        let s1 = AttachedCamera.scaleStrippedInverse(of: world(scale: 1))
        let s3 = AttachedCamera.scaleStrippedInverse(of: world(scale: 3))
        let s10 = AttachedCamera.scaleStrippedInverse(of: world(scale: 10))
        #expect(approxEqual(s1, s3, tolerance: 1e-3))
        #expect(approxEqual(s1, s10, tolerance: 1e-3))
    }

    @Test("scaleStrippedInverse equals the inverse of the unscaled rigid transform")
    func equalsRigidInverse() {
        let stripped = AttachedCamera.scaleStrippedInverse(of: world(scale: 3))
        let rigidInverse = world(scale: 1).inverse  // T*R with no scale
        #expect(approxEqual(stripped, rigidInverse, tolerance: 1e-3))
    }

    @Test("recovered world basis is orthonormal (scale removed)")
    func basisOrthonormal() {
        // Invert back to the rigid world transform and inspect its basis.
        let rigid = AttachedCamera.scaleStrippedInverse(of: world(scale: 3)).inverse
        let x = rigid.columns.0.xyz
        let y = rigid.columns.1.xyz
        let z = rigid.columns.2.xyz
        #expect(approxEqual(simd_length(x), 1, tolerance: 1e-3))
        #expect(approxEqual(simd_length(y), 1, tolerance: 1e-3))
        #expect(approxEqual(simd_length(z), 1, tolerance: 1e-3))
        // Mutually perpendicular.
        #expect(approxEqual(simd_dot(x, y), 0, tolerance: 1e-3))
        #expect(approxEqual(simd_dot(x, z), 0, tolerance: 1e-3))
        #expect(approxEqual(simd_dot(y, z), 0, tolerance: 1e-3))
    }

    @Test("world translation is preserved")
    func translationPreserved() {
        let rigid = AttachedCamera.scaleStrippedInverse(of: world(scale: 3)).inverse
        #expect(approxEqual(rigid.columns.3.xyz, SIMD3<Float>(100, 50, -30), tolerance: 1e-2))
    }
}
