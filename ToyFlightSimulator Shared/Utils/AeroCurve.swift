//
//  AeroCurve.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/15/26.
//

import Foundation

/// Sigmoid-like curve defined by three control points (min, zero, max) with sine-shaped
/// interpolation between them. Clamps outside `[minInput, maxInput]`.
struct AeroCurve {
    let minInput, zeroInput, maxInput: Float
    let minOutput, zeroOutput, maxOutput: Float

    init(min: (input: Float, output: Float),
         zero: (input: Float, output: Float),
         max: (input: Float, output: Float)) {
        precondition(min.input < zero.input && zero.input < max.input,
                     "AeroCurve inputs must satisfy min.input < zero.input < max.input")
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
