//
//  MathTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Math.swift", .tags(.math))
struct MathTests {

    // MARK: - Axis constants

    @Test("Axis constants are unit vectors along their respective axes")
    func axisConstants() {
        #expect(X_AXIS == SIMD3<Float>(1, 0, 0))
        #expect(Y_AXIS == SIMD3<Float>(0, 1, 0))
        #expect(Z_AXIS == SIMD3<Float>(0, 0, 1))
    }

    // MARK: - Float radian/degree conversion

    @Test("toRadians converts common angles", arguments: [
        (degrees: Float(0),    expected: Float(0)),
        (degrees: Float(90),   expected: Float.pi / 2),
        (degrees: Float(180),  expected: Float.pi),
        (degrees: Float(360),  expected: 2 * Float.pi),
        (degrees: Float(-90),  expected: -Float.pi / 2),
    ])
    func toRadiansCases(_ pair: (degrees: Float, expected: Float)) {
        #expect(approxEqual(pair.degrees.toRadians, pair.expected))
    }

    @Test("toDegrees is the inverse of toRadians")
    func roundTrip() {
        for deg in stride(from: Float(-360), through: 360, by: 45) {
            #expect(approxEqual(deg.toRadians.toDegrees, deg, tolerance: 1e-3))
        }
    }

    // MARK: - matrix_float4x4 mutating ops

    @Test("translate mutates an identity matrix into a pure translation")
    func translateFromIdentity() {
        var m = matrix_identity_float4x4
        m.translate(direction: SIMD3<Float>(2, 3, 4))
        let expected = Transform.translationMatrix(SIMD3<Float>(2, 3, 4))
        #expect(approxEqual(m, expected))
    }

    @Test("scale mutates an identity matrix into a pure scale")
    func scaleFromIdentity() {
        var m = matrix_identity_float4x4
        m.scale(axis: SIMD3<Float>(2, 3, 4))
        let expected = Transform.scaleMatrix(SIMD3<Float>(2, 3, 4))
        #expect(approxEqual(m, expected))
    }

    @Test("rotate by 90° around Y maps +X to -Z")
    func rotateAroundY() {
        var m = matrix_identity_float4x4
        m.rotate(angle: .pi / 2, axis: Y_AXIS)
        let rotatedX = m * SIMD4<Float>(1, 0, 0, 0)
        #expect(approxEqual(rotatedX.xyz, SIMD3<Float>(0, 0, -1)))
    }

    // MARK: - Static perspective

    @Test("perspective produces a finite matrix for typical camera params")
    func perspectiveIsFinite() {
        let m = matrix_float4x4.perspective(degreesFov: 65,
                                            aspectRatio: 16.0 / 9.0,
                                            near: 0.1,
                                            far: 1000)
        #expect(m.columns.0.x.isFinite)
        #expect(m.columns.1.y.isFinite)
        #expect(m.columns.2.z.isFinite)
        // Left-handed Metal convention: w column encodes -near*far/(far-near)
        #expect(m.columns.3.z < 0)
        #expect(m.columns.2.w == 1)
    }

    @Test("perspective matches Transform.perspectiveProjection when given equivalent inputs")
    func perspectiveMatchesTransform() {
        let fovDeg: Float = 60
        let aspect: Float = 1.5
        let near: Float = 0.1
        let far: Float = 100
        let a = matrix_float4x4.perspective(degreesFov: fovDeg,
                                            aspectRatio: aspect,
                                            near: near,
                                            far: far)
        let b = Transform.perspectiveProjection(fovDeg.toRadians, aspect, near, far)
        #expect(approxEqual(a, b))
    }
}
