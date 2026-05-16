//
//  ValueCurve.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/15/26.
//
//  ===========================================================================
//  API Summary
//  ===========================================================================
//
//  Three ways to construct:
//
//  1. Direct — full control over every key's tangents:
//
//         let curve = ValueCurve(keys: [
//             .init(input: -15, output: -1.0, inTangent: 0,    outTangent: 0.15),
//             .init(input:   0, output:  0.2, inTangent: 0.08, outTangent: 0.08),
//             .init(input:  15, output:  1.2, inTangent: 0.05, outTangent: 0)
//         ])
//
//  2. Piecewise linear (true linear lerp between adjacent points, corners at keys):
//
//         let dragTable = ValueCurve.linear([
//             (input: 0,    output: 0.02),
//             (input: 0.8,  output: 0.025),
//             (input: 0.95, output: 0.18),    // transonic drag rise
//             (input: 1.2,  output: 0.12),
//             (input: 3.0,  output: 0.08)
//         ])
//
//  3. Auto-smoothed (Catmull-Rom, C1 continuous, generalized for non-uniform spacing):
//
//         let liftCurve = ValueCurve.smooth([
//             (input: -15, output: -1.0),
//             (input:   0, output:  0.2),
//             (input:  15, output:  1.2)
//         ])
//
//  Sampling:
//
//         let cd = dragTable.evaluate(at: machNumber)
//
//  ===========================================================================
//  Notes on the math
//  ===========================================================================
//
//  - Hermite formula uses tangents in output-per-input units (e.g., dCl/dα).
//    The `dx` factor inside `evaluate(at:)` rescales them for the local [0, 1]
//    parameter — the formula needs raw tangents, not pre-scaled.
//
//  - `linear()` is exact: with chord-slope tangents on both ends of each
//    segment, the Hermite expression algebraically reduces to (1-u)*p0 + u*p1.
//
//  - `smooth()` for 2 points == `linear()` for 2 points. For 3+ points it
//    produces a continuously differentiable curve.
//
//  - Binary search is O(log n) per sample. Practical for any reasonable
//    keyframe count (the cubic eval is the dominant cost regardless).
//
//  - Validation: precondition asserts keys are strictly increasing — catches
//    duplicate-input bugs early.
//

import Foundation

/// Sampleable keyframe curve with cubic Hermite interpolation and binary-search lookup.
/// Out-of-range inputs clamp to the endpoint outputs.
struct ValueCurve {
    struct Key {
        var input: Float
        var output: Float
        var inTangent: Float
        var outTangent: Float

        init(input: Float, output: Float, inTangent: Float = 0, outTangent: Float = 0) {
            self.input = input
            self.output = output
            self.inTangent = inTangent
            self.outTangent = outTangent
        }
    }

    let keys: [Key]

    init(keys: [Key]) {
        precondition(!keys.isEmpty, "ValueCurve requires at least one key")
        precondition(zip(keys, keys.dropFirst()).allSatisfy { $0.input < $1.input },
                     "ValueCurve keys must be strictly increasing in input")
        self.keys = keys
    }

    /// Piecewise linear: chord slopes at each key (C0 with corners at keys).
    static func linear(_ points: [(input: Float, output: Float)]) -> ValueCurve {
        precondition(!points.isEmpty)
        if points.count == 1 {
            return ValueCurve(keys: [Key(input: points[0].input, output: points[0].output)])
        }
        var built: [Key] = []
        built.reserveCapacity(points.count)
        for i in 0..<points.count {
            let inSlope: Float, outSlope: Float
            if i == 0 {
                let s = (points[1].output - points[0].output) / (points[1].input - points[0].input)
                inSlope = s; outSlope = s
            } else if i == points.count - 1 {
                let s = (points[i].output - points[i-1].output) / (points[i].input - points[i-1].input)
                inSlope = s; outSlope = s
            } else {
                inSlope  = (points[i].output - points[i-1].output) / (points[i].input - points[i-1].input)
                outSlope = (points[i+1].output - points[i].output) / (points[i+1].input - points[i].input)
            }
            built.append(Key(input: points[i].input, output: points[i].output,
                             inTangent: inSlope, outTangent: outSlope))
        }
        return ValueCurve(keys: built)
    }

    /// Catmull-Rom auto-smoothing (C1), generalized for non-uniform spacing.
    /// Endpoints use one-sided differences.
    static func smooth(_ points: [(input: Float, output: Float)]) -> ValueCurve {
        precondition(!points.isEmpty)
        if points.count == 1 {
            return ValueCurve(keys: [Key(input: points[0].input, output: points[0].output)])
        }
        var built: [Key] = []
        built.reserveCapacity(points.count)
        for i in 0..<points.count {
            let tangent: Float
            if i == 0 {
                tangent = (points[1].output - points[0].output) / (points[1].input - points[0].input)
            } else if i == points.count - 1 {
                tangent = (points[i].output - points[i-1].output) / (points[i].input - points[i-1].input)
            } else {
                tangent = (points[i+1].output - points[i-1].output) / (points[i+1].input - points[i-1].input)
            }
            built.append(Key(input: points[i].input, output: points[i].output,
                             inTangent: tangent, outTangent: tangent))
        }
        return ValueCurve(keys: built)
    }

    func evaluate(at value: Float) -> Float {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if value <= first.input { return first.output }
        if value >= last.input { return last.output }

        var lo = 0
        var hi = keys.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if keys[mid].input <= value {
                lo = mid
            } else {
                hi = mid
            }
        }

        let a = keys[lo], b = keys[hi]
        let dx = b.input - a.input
        let u = (value - a.input) / dx
        let u2 = u * u
        let u3 = u2 * u
        let h00 =  2*u3 - 3*u2 + 1
        let h10 =    u3 - 2*u2 + u
        let h01 = -2*u3 + 3*u2
        let h11 =    u3 -   u2
        return h00 * a.output
             + h10 * dx * a.outTangent
             + h01 * b.output
             + h11 * dx * b.inTangent
    }
}
