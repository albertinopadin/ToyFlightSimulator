//
//  ValueCurveTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import Foundation
@testable import ToyFlightSimulator

@Suite("ValueCurve", .tags(.utils))
struct ValueCurveTests {

    // MARK: - Single-key curves

    @Test("single-key linear curve returns that key's output everywhere")
    func singleKeyLinear() {
        let c = ValueCurve.linear([(input: 5, output: 42)])
        #expect(approxEqual(c.evaluate(at: -1000), 42))
        #expect(approxEqual(c.evaluate(at: 5), 42))
        #expect(approxEqual(c.evaluate(at: 1000), 42))
    }

    @Test("single-key smooth curve returns that key's output everywhere")
    func singleKeySmooth() {
        let c = ValueCurve.smooth([(input: 5, output: 42)])
        #expect(approxEqual(c.evaluate(at: -1000), 42))
        #expect(approxEqual(c.evaluate(at: 5), 42))
        #expect(approxEqual(c.evaluate(at: 1000), 42))
    }

    // MARK: - Endpoint clamping

    @Test("evaluate below first key clamps to first output")
    func clampBelowFirstKey() {
        let c = ValueCurve.linear([
            (input: 0, output: 1),
            (input: 10, output: 5)
        ])
        #expect(approxEqual(c.evaluate(at: -100), 1))
    }

    @Test("evaluate above last key clamps to last output")
    func clampAboveLastKey() {
        let c = ValueCurve.linear([
            (input: 0, output: 1),
            (input: 10, output: 5)
        ])
        #expect(approxEqual(c.evaluate(at: 1000), 5))
    }

    @Test("evaluate at first input returns first output exactly")
    func atFirstKey() {
        let c = ValueCurve.linear([
            (input: -3, output: -1.5),
            (input: 7, output: 4.2)
        ])
        #expect(approxEqual(c.evaluate(at: -3), -1.5))
    }

    @Test("evaluate at last input returns last output exactly")
    func atLastKey() {
        let c = ValueCurve.linear([
            (input: -3, output: -1.5),
            (input: 7, output: 4.2)
        ])
        #expect(approxEqual(c.evaluate(at: 7), 4.2))
    }

    // MARK: - Linear properties

    @Test("two-key linear == midpoint lerp")
    func linearMidpoint() {
        let c = ValueCurve.linear([
            (input: 0, output: 0),
            (input: 10, output: 100)
        ])
        #expect(approxEqual(c.evaluate(at: 5), 50))
    }

    @Test("linear interpolation is exact at arbitrary interior points")
    func linearArbitraryPoints() {
        let c = ValueCurve.linear([
            (input: 0, output: 0),
            (input: 10, output: 100)
        ])
        for u in stride(from: Float(0), through: 1, by: 0.1) {
            let x = 10 * u
            let expected: Float = 100 * u
            #expect(approxEqual(c.evaluate(at: x), expected, tolerance: 1e-3),
                    "u=\(u) x=\(x): got \(c.evaluate(at: x)), expected \(expected)")
        }
    }

    @Test("multi-segment linear is exact in each segment")
    func linearMultiSegment() {
        // V-shaped curve: -10 -> 5 -> 10 with outputs 1 -> 0 -> 2
        let c = ValueCurve.linear([
            (input: -10, output: 1),
            (input: 5, output: 0),
            (input: 10, output: 2)
        ])
        // Midpoint of first segment: x = -2.5, output should be 0.5
        #expect(approxEqual(c.evaluate(at: -2.5), 0.5, tolerance: 1e-3))
        // Midpoint of second segment: x = 7.5, output should be 1.0
        #expect(approxEqual(c.evaluate(at: 7.5), 1.0, tolerance: 1e-3))
        // Exact at the elbow
        #expect(approxEqual(c.evaluate(at: 5), 0))
    }

    @Test("constant linear curve returns the constant everywhere")
    func linearConstant() {
        let c = ValueCurve.linear([
            (input: 0, output: 3),
            (input: 10, output: 3),
            (input: 20, output: 3)
        ])
        for x in stride(from: Float(-10), through: 30, by: 1) {
            #expect(approxEqual(c.evaluate(at: x), 3))
        }
    }

    // MARK: - Smooth properties

    @Test("smooth() for 2 points equals linear() for 2 points")
    func smoothEqualsLinearForTwoPoints() {
        let points: [(input: Float, output: Float)] = [
            (input: -5, output: -2),
            (input: 5, output: 8)
        ]
        let lin = ValueCurve.linear(points)
        let smo = ValueCurve.smooth(points)
        for x in stride(from: Float(-10), through: 10, by: 0.5) {
            #expect(approxEqual(lin.evaluate(at: x), smo.evaluate(at: x), tolerance: 1e-4),
                    "diverged at \(x)")
        }
    }

    @Test("smooth curve passes through every keyframe exactly")
    func smoothPassesThroughKeys() {
        let points: [(input: Float, output: Float)] = [
            (input: -30, output: -1.0),
            (input: 0, output: 0.2),
            (input: 30, output: 1.2)
        ]
        let c = ValueCurve.smooth(points)
        for p in points {
            #expect(approxEqual(c.evaluate(at: p.input), p.output, tolerance: 1e-4),
                    "miss at \(p.input): got \(c.evaluate(at: p.input)), expected \(p.output)")
        }
    }

    @Test("F22 liftCoefficientCurve hits the documented control points")
    func f22LiftCurveControlPoints() {
        // Mirrors the curve used in F22.swift
        let c = ValueCurve.smooth([
            (input: -30, output: -1.0),
            (input:   0, output:  0.2),
            (input:  30, output:  1.2)
        ])
        #expect(approxEqual(c.evaluate(at: -30), -1.0))
        #expect(approxEqual(c.evaluate(at: 0), 0.2))
        #expect(approxEqual(c.evaluate(at: 30), 1.2))
    }

    @Test("smooth curve monotonically increases for monotone-up control points")
    func smoothMonotonicUp() {
        let c = ValueCurve.smooth([
            (input: -30, output: -1.0),
            (input: 0, output: 0.2),
            (input: 30, output: 1.2)
        ])
        var prev: Float = -.greatestFiniteMagnitude
        for x in stride(from: Float(-30), through: 30, by: 1) {
            let v = c.evaluate(at: x)
            #expect(v >= prev - defaultTolerance,
                    "non-monotone at \(x): \(prev) -> \(v)")
            prev = v
        }
    }

    // MARK: - Non-uniform spacing

    @Test("smooth curve handles non-uniform keyframe spacing")
    func smoothNonUniformSpacing() {
        // Drag-vs-Mach-style: tight clustering near transonic, wider elsewhere
        let points: [(input: Float, output: Float)] = [
            (input: 0.0, output: 0.02),
            (input: 0.8, output: 0.025),
            (input: 0.95, output: 0.18),
            (input: 1.2, output: 0.12),
            (input: 3.0, output: 0.08)
        ]
        let c = ValueCurve.smooth(points)
        for p in points {
            #expect(approxEqual(c.evaluate(at: p.input), p.output, tolerance: 1e-4))
        }
        // Interior sample (not validated against a reference, just non-NaN, in range)
        let v = c.evaluate(at: 0.9)
        #expect(v.isFinite)
        #expect(v >= 0.02 && v <= 0.20)
    }

    // MARK: - Direct keyframe construction

    @Test("direct keyframe init with zero tangents matches the key values")
    func directInitHitsKeys() {
        let c = ValueCurve(keys: [
            ValueCurve.Key(input: -10, output: -2),
            ValueCurve.Key(input: 0, output: 0),
            ValueCurve.Key(input: 10, output: 2)
        ])
        #expect(approxEqual(c.evaluate(at: -10), -2))
        #expect(approxEqual(c.evaluate(at: 0), 0))
        #expect(approxEqual(c.evaluate(at: 10), 2))
    }

    @Test("Key default tangents are zero")
    func keyDefaultTangents() {
        let k = ValueCurve.Key(input: 1, output: 2)
        #expect(k.inTangent == 0)
        #expect(k.outTangent == 0)
    }
}
