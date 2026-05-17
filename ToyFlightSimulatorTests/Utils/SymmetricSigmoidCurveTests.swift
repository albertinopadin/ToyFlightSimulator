//
//  SymmetricSigmoidCurveTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import Foundation
@testable import ToyFlightSimulator

@Suite("SymmetricSigmoidCurve", .tags(.utils))
struct SymmetricSigmoidCurveTests {

    // MARK: - Endpoint clamping

    @Test("evaluate at minInput returns minOutput")
    func clampLow() {
        let c = SymmetricSigmoidCurve(min: (-10, -1), zero: (0, 0.2), max: (10, 1))
        #expect(approxEqual(c.evaluate(at: -10), -1))
    }

    @Test("evaluate below minInput clamps to minOutput")
    func clampBelowMin() {
        let c = SymmetricSigmoidCurve(min: (-10, -1), zero: (0, 0.2), max: (10, 1))
        #expect(approxEqual(c.evaluate(at: -1000), -1))
    }

    @Test("evaluate at maxInput returns maxOutput")
    func clampHigh() {
        let c = SymmetricSigmoidCurve(min: (-10, -1), zero: (0, 0.2), max: (10, 1))
        #expect(approxEqual(c.evaluate(at: 10), 1))
    }

    @Test("evaluate above maxInput clamps to maxOutput")
    func clampAboveMax() {
        let c = SymmetricSigmoidCurve(min: (-10, -1), zero: (0, 0.2), max: (10, 1))
        #expect(approxEqual(c.evaluate(at: 1000), 1))
    }

    // MARK: - Centerpoint

    @Test("evaluate at zeroInput returns zeroOutput")
    func centerpoint() {
        let c = SymmetricSigmoidCurve(min: (-30, -1.0), zero: (0, 0.2), max: (30, 1.2))
        #expect(approxEqual(c.evaluate(at: 0), 0.2))
    }

    @Test("evaluate at non-symmetric centerpoint returns zeroOutput")
    func centerpointAsymmetric() {
        // zero input is at +5, output 0.3
        let c = SymmetricSigmoidCurve(min: (-10, -1), zero: (5, 0.3), max: (20, 1))
        #expect(approxEqual(c.evaluate(at: 5), 0.3))
    }

    // MARK: - Monotonicity

    @Test("monotonically non-decreasing for monotone-up control points")
    func monotonicUp() {
        let c = SymmetricSigmoidCurve(min: (-30, -1.0), zero: (0, 0.0), max: (30, 1.0))
        var prev: Float = -.greatestFiniteMagnitude
        for step in stride(from: Float(-30), through: 30, by: 0.5) {
            let v = c.evaluate(at: step)
            #expect(v >= prev - defaultTolerance,
                    "non-monotone at \(step): \(prev) -> \(v)")
            prev = v
        }
    }

    // MARK: - Sine-shape interior sample

    @Test("midpoint of right side is approximately sin(π/4) above zeroOutput")
    func rightSideMidpoint() {
        // Curve: zeroOutput + (maxOutput - zeroOutput) * sin(π/2 * (v - zero) / (max - zero))
        // At v = (max + zero) / 2 = 5:  u = π/4, sin(π/4) ≈ 0.7071
        // Expected: 0 + (1 - 0) * sin(π/4) ≈ 0.7071
        let c = SymmetricSigmoidCurve(min: (-10, 0), zero: (0, 0), max: (10, 1))
        let v = c.evaluate(at: 5)
        #expect(approxEqual(v, sin(.pi / 4), tolerance: 1e-4))
    }

    @Test("midpoint of left side mirrors right side for symmetric curve")
    func leftSideMidpoint() {
        // Symmetric curve: f(-x) == -f(x) when zeroOutput == 0 and outputs are antisymmetric
        let c = SymmetricSigmoidCurve(min: (-10, -1), zero: (0, 0), max: (10, 1))
        let right = c.evaluate(at: 5)
        let left = c.evaluate(at: -5)
        #expect(approxEqual(left, -right))
    }

    // MARK: - Asymmetric output handling

    @Test("positive and negative sides scale independently")
    func asymmetricSides() {
        // Negative side has output range [zeroOut - minOut] = [0.2 - (-1.0)] = 1.2
        // Positive side has output range [maxOut - zeroOut] = [1.2 - 0.2] = 1.0
        let c = SymmetricSigmoidCurve(min: (-30, -1.0), zero: (0, 0.2), max: (30, 1.2))

        // At v = -15 (midpoint of left side): u = -π/4, sin(-π/4) ≈ -0.7071
        // Expected: 0.2 + (0.2 - (-1.0)) * sin(-π/4) = 0.2 + 1.2 * (-0.7071) ≈ -0.6485
        let leftMid = c.evaluate(at: -15)
        let expectedLeft: Float = 0.2 + 1.2 * sin(-.pi / 4)
        #expect(approxEqual(leftMid, expectedLeft, tolerance: 1e-4))

        // At v = 15 (midpoint of right side): u = π/4
        // Expected: 0.2 + (1.2 - 0.2) * sin(π/4) = 0.2 + 1.0 * 0.7071 ≈ 0.9071
        let rightMid = c.evaluate(at: 15)
        let expectedRight: Float = 0.2 + 1.0 * sin(.pi / 4)
        #expect(approxEqual(rightMid, expectedRight, tolerance: 1e-4))
    }

    // MARK: - Realistic induced-drag config from F22

    @Test("F22 inducedDragCurve ramps 0→1 across 0..5 m/s and clamps above")
    func inducedDragCurveShape() {
        let curve = SymmetricSigmoidCurve(min: (-1, 0), zero: (0, 0), max: (5, 1))
        #expect(approxEqual(curve.evaluate(at: 0), 0))      // taxi/stationary
        #expect(approxEqual(curve.evaluate(at: 5), 1))      // ramp endpoint
        #expect(approxEqual(curve.evaluate(at: 50), 1))     // flight speed clamps to 1
        #expect(approxEqual(curve.evaluate(at: 300), 1))    // high cruise clamps to 1
        // ramp interior: at 2.5 m/s, u = π/4 -> sin(π/4) ≈ 0.7071
        #expect(approxEqual(curve.evaluate(at: 2.5), sin(.pi / 4), tolerance: 1e-4))
    }
}
