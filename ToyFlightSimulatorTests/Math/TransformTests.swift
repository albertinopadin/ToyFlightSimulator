//
//  TransformTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Transform", .tags(.math))
struct TransformTests {

    // MARK: - translation / scale / normal

    @Test("translationMatrix places translation in column 3")
    func translationMatrixBasics() {
        let t = SIMD3<Float>(5, -3, 2)
        let m = Transform.translationMatrix(t)
        #expect(m.columns.3 == SIMD4<Float>(5, -3, 2, 1))
        #expect(m.columns.0 == SIMD4<Float>(1, 0, 0, 0))
    }

    @Test("scaleMatrix places scale on the diagonal")
    func scaleMatrixBasics() {
        let m = Transform.scaleMatrix(SIMD3<Float>(2, 3, 4))
        #expect(m.columns.0.x == 2)
        #expect(m.columns.1.y == 3)
        #expect(m.columns.2.z == 4)
        #expect(m.columns.3.w == 1)
    }

    @Test("normalMatrix extracts the upper-left 3x3")
    func normalMatrixBasics() {
        let model = Transform.rotationMatrix(radians: 1.2, axis: SIMD3<Float>(0, 1, 0))
            * Transform.scaleMatrix(SIMD3<Float>(2, 2, 2))
        let n = Transform.normalMatrix(from: model)
        #expect(approxEqual(n.columns.0, model.columns.0.xyz))
        #expect(approxEqual(n.columns.1, model.columns.1.xyz))
        #expect(approxEqual(n.columns.2, model.columns.2.xyz))
    }

    // MARK: - rotationMatrix

    @Test("rotationMatrix normalizes a non-unit axis")
    func rotationNormalizesAxis() {
        let a = Transform.rotationMatrix(radians: .pi / 3, axis: SIMD3<Float>(0, 2, 0))
        let b = Transform.rotationMatrix(radians: .pi / 3, axis: SIMD3<Float>(0, 1, 0))
        #expect(approxEqual(a, b))
    }

    @Test("rotating a vector 90° around Z maps +X to +Y (left-handed)")
    func rotationZ() {
        let r = Transform.rotationMatrix(radians: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
        let v = r * SIMD4<Float>(1, 0, 0, 0)
        #expect(approxEqual(v.xyz, SIMD3<Float>(0, 1, 0)))
    }

    // MARK: - projections

    @Test("orthographicProjection maps the view volume corners into NDC")
    func orthoCorners() {
        let m = Transform.orthographicProjection(-1, 1, -1, 1, 0, 10)
        let nearCenter = m * SIMD4<Float>(0, 0, 0, 1)
        let farCenter  = m * SIMD4<Float>(0, 0, 10, 1)
        #expect(approxEqual(nearCenter.z, 0))
        #expect(approxEqual(farCenter.z,  1))
    }

    @Test("perspectiveProjection places near plane at z=0 in NDC")
    func perspNearPlane() {
        let m = Transform.perspectiveProjection(Float(60).toRadians, 1.0, 0.1, 100)
        let pt = m * SIMD4<Float>(0, 0, 0.1, 1)
        #expect(approxEqual(pt.z / pt.w, 0, tolerance: 1e-3))
    }

    // MARK: - look

    @Test("look-at with eye behind origin, looking forward, transforms target to +Z")
    func lookForward() {
        let view = Transform.look(eye:    SIMD3<Float>(0, 0, -1),
                                  target: SIMD3<Float>(0, 0,  0),
                                  up:     SIMD3<Float>(0, 1,  0))
        let t = view * SIMD4<Float>(0, 0, 0, 1)
        #expect(approxEqual(t.xyz, SIMD3<Float>(0, 0, 1)))
    }

    // MARK: - decomposeToEulers

    @Test("decomposeToEulers recovers a small rotation about Y")
    func decomposeEulersY() {
        let angle: Float = 0.3
        let r = Transform.rotationMatrix(radians: angle, axis: SIMD3<Float>(0, 1, 0))
        let eulers = Transform.decomposeToEulers(r)
        // Left-handed decomposition: a +angle rotation about +Y returns +angle on .y,
        // and zeros on .x and .z.
        #expect(approxEqual(eulers.y, angle, tolerance: 1e-3))
        #expect(approxEqual(eulers.x, 0, tolerance: 1e-3))
        #expect(approxEqual(eulers.z, 0, tolerance: 1e-3))
    }

    @Test("decomposeToEulers handles gimbal-lock singularity without NaN")
    func decomposeEulersSingularity() {
        let r = Transform.rotationMatrix(radians: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let eulers = Transform.decomposeToEulers(r)
        #expect(eulers.x.isFinite)
        #expect(eulers.y.isFinite)
        #expect(eulers.z.isFinite)
    }

    // MARK: - Coordinate swap matrices

    @Test("transform presets are orthonormal (determinant ±1)",
          arguments: [
            Transform.transformZXYToXYZ,
            Transform.transformXZYToXYZ,
            Transform.transformXYMinusZToXYZ,
            Transform.transformXMinusZYToXYZ,
            Transform.transformYMinusZXToXYZ,
          ])
    func presetsOrthonormal(m: float4x4) {
        let det = m.determinant
        #expect(approxEqual(abs(det), 1.0))
    }

    // MARK: - decomposeTRS / matrixFromTR

    @Test("decomposeTRS round-trips T * R * S")
    func decomposeTRSRoundTrip() {
        let t = SIMD3<Float>(1, 2, 3)
        let r = Transform.rotationMatrix(radians: 0.7, axis: SIMD3<Float>(0, 1, 0))
        let s = SIMD3<Float>(2, 3, 4)
        let composed = Transform.translationMatrix(t) * r * Transform.scaleMatrix(s)

        let (tt, rr, ss) = Transform.decomposeTRS(composed)
        #expect(approxEqual(tt, t))
        #expect(approxEqual(ss, s))
        #expect(approxEqual(rr, r))
    }

    @Test("matrixFromTR places translation into column 3 when given identity rotation")
    func matrixFromTRIdentityRotation() {
        let m = Transform.matrixFromTR(translation: SIMD3<Float>(1, 2, 3),
                                       rotation: .identity)
        #expect(m.columns.3 == SIMD4<Float>(1, 2, 3, 1))
    }

    // MARK: - float4x4.identity

    @Test("float4x4.identity equals matrix_identity_float4x4")
    func identity() {
        #expect(float4x4.identity == matrix_identity_float4x4)
    }
}
