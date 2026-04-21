//
//  MathUtilsTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("MathUtils", .tags(.math))
struct MathUtilsTests {

    // MARK: - align / gcd / lcm / mipmapLevelCount

    @Test("align rounds up to alignment boundary", arguments: [
        (value: 0,   alignment: 16, expected: 0),
        (value: 1,   alignment: 16, expected: 16),
        (value: 16,  alignment: 16, expected: 16),
        (value: 17,  alignment: 16, expected: 32),
        (value: 255, alignment: 64, expected: 256),
    ])
    func alignCases(_ args: (value: Int, alignment: Int, expected: Int)) {
        #expect(align(args.value, upTo: args.alignment) == args.expected)
    }

    @Test("gcd of common pairs", arguments: [
        (m: 12,  n: 18, expected: 6),
        (m: 17,  n: 13, expected: 1),
        (m: 100, n: 10, expected: 10),
        (m: 0,   n: 5,  expected: 5),   // documents current behavior: gcd(0, n) == n
    ])
    func gcdCases(_ args: (m: Int, n: Int, expected: Int)) {
        #expect(gcd(args.m, args.n) == args.expected)
    }

    @Test("lcm of common pairs", arguments: [
        (m: 4, n: 6, expected: 12),
        (m: 3, n: 5, expected: 15),
        (m: 7, n: 1, expected: 7),
    ])
    func lcmCases(_ args: (m: Int, n: Int, expected: Int)) {
        #expect(lcm(args.m, args.n) == args.expected)
    }

    @Test("mipmapLevelCount handles size 0 and common texture sizes", arguments: [
        (size: 0,    expected: 1),
        (size: 1,    expected: 1),
        (size: 2,    expected: 2),
        (size: 256,  expected: 9),
        (size: 1024, expected: 11),
        (size: 4096, expected: 13),
    ])
    func mipmapCases(_ args: (size: Int, expected: Int)) {
        #expect(mipmapLevelCount(for: args.size) == args.expected)
    }

    // MARK: - SIMD4.xyz

    @Test("SIMD4.xyz drops the w component")
    func simd4xyz() {
        let v = SIMD4<Float>(1, 2, 3, 4)
        #expect(v.xyz == SIMD3<Float>(1, 2, 3))
    }

    // MARK: - float4x4 convenience initializers

    @Test("init(scale:) places scale on the diagonal")
    func initScale() {
        let m = float4x4(scale: SIMD3<Float>(2, 3, 4))
        #expect(m.columns.0.x == 2)
        #expect(m.columns.1.y == 3)
        #expect(m.columns.2.z == 4)
    }

    @Test("init(translate:) places translation in column 3")
    func initTranslate() {
        let m = float4x4(translate: SIMD3<Float>(5, 6, 7))
        #expect(m.columns.3 == SIMD4<Float>(5, 6, 7, 1))
    }

    @Test("init(rotateAbout:byAngle:) does NOT normalize its axis (documents current behavior)")
    func rotateAboutDoesNotNormalize() {
        // Passing a non-unit axis produces a non-rotation matrix;
        // this guards against accidental behavior change.
        let m = float4x4(rotateAbout: SIMD3<Float>(0, 2, 0), byAngle: .pi / 2)
        let v = m * SIMD4<Float>(1, 0, 0, 0)
        // A correct rotation would give (0, 0, ±1); with a scale-2 axis it will not.
        #expect(!approxEqual(v.xyz, SIMD3<Float>(0, 0, -1)))
        #expect(!approxEqual(v.xyz, SIMD3<Float>(0, 0,  1)))
    }

    @Test("init(rotateAbout:byAngle:) with a unit axis rotates correctly")
    func rotateAboutUnitAxis() {
        let m = float4x4(rotateAbout: SIMD3<Float>(0, 1, 0), byAngle: .pi / 2)
        let v = m * SIMD4<Float>(1, 0, 0, 0)
        // The MathUtils init uses a column-major formulation that maps +X → +Z when rotating +90° about +Y.
        #expect(approxEqual(v.xyz, SIMD3<Float>(0, 0, 1)))
    }

    @Test("init(lookAt:from:up:) places +Z column pointing from `from` toward `at`")
    func initLookAt() {
        let m = float4x4(lookAt: SIMD3<Float>(0, 0,  10),
                         from:   SIMD3<Float>(0, 0, -10),
                         up:     SIMD3<Float>(0, 1,  0))
        // Column 2 encodes the forward direction (at - from, normalized): +Z.
        #expect(approxEqual(m.columns.2.xyz, SIMD3<Float>(0, 0, 1)))
        // Column 3 encodes the camera's world position.
        #expect(approxEqual(m.columns.3.xyz, SIMD3<Float>(0, 0, -10)))
    }

    @Test("upperLeft3x3 discards translation column")
    func upperLeft3x3() {
        let r = Transform.rotationMatrix(radians: 0.4, axis: SIMD3<Float>(0, 1, 0))
        let m = Transform.translationMatrix(SIMD3<Float>(7, 8, 9)) * r
        let up = m.upperLeft3x3
        #expect(approxEqual(up, r.upperLeft3x3))
    }

    // MARK: - simd_quatf.rotate

    @Test("quaternion rotate agrees with equivalent rotation matrix")
    func quatRotate() {
        let angle: Float = 0.6
        let axis = SIMD3<Float>(0, 1, 0)
        let q = simd_quatf(angle: angle, axis: axis)
        let v = SIMD3<Float>(1, 0, 0)
        let rotatedQuat = q.rotate(v)
        let rotatedMat  = (Transform.rotationMatrix(radians: angle, axis: axis)
                           * SIMD4<Float>(v, 0)).xyz
        #expect(approxEqual(rotatedQuat, rotatedMat, tolerance: 1e-5))
    }
}
