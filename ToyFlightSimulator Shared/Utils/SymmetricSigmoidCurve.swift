//
//  SymmetricSigmoidCurve.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/15/26.
//

import Foundation

/// Three-point sine-shaped sigmoid: a single zero-crossing with sine-eased
/// transitions on each side. Tangents are horizontal at all three control
/// points, so the curve saturates smoothly at the extremes.
///
/// **Scope:** specifically a sigmoid with one zero crossing. Suitable for
/// symmetric aero responses (Cl-vs-α before stall, Cm-vs-α, similar). For
/// arbitrary keyframe curves (drag-vs-Mach with multiple inflections,
/// polynomial-ish responses, etc.), use `ValueCurve` instead.
///
/// **Clamping:** inputs outside `[minInput, maxInput]` return the endpoint
/// output, so out-of-range AoA / airspeed never extrapolates.
///
/// **Asymmetry:** the two sides scale independently, so unequal stall
/// behavior on positive vs negative input works naturally.
struct SymmetricSigmoidCurve {
    let minInput, zeroInput, maxInput: Float
    let minOutput, zeroOutput, maxOutput: Float

    init(min: (input: Float, output: Float),
         zero: (input: Float, output: Float),
         max: (input: Float, output: Float)) {
        precondition(min.input < zero.input && zero.input < max.input,
                     "SymmetricSigmoidCurve inputs must satisfy min.input < zero.input < max.input")
        self.minInput = min.input
        self.zeroInput = zero.input
        self.maxInput = max.input
        self.minOutput = min.output
        self.zeroOutput = zero.output
        self.maxOutput = max.output
    }

    func evaluate(at value: Float) -> Float {
        if value <= minInput { return minOutput }
        if value >= maxInput { return maxOutput }
        if value < zeroInput {
            let u = Float.pi / 2 * (value - zeroInput) / (zeroInput - minInput)
            return zeroOutput + (zeroOutput - minOutput) * sin(u)
        } else {
            let u = Float.pi / 2 * (value - zeroInput) / (maxInput - zeroInput)
            return zeroOutput + (maxOutput - zeroOutput) * sin(u)
        }
    }
}
