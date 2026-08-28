//
//  SeededRandom.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/28/26.
//

/// SplitMix64 (Steele/Lea/Flood — the java.util.SplittableRandom mixer).
/// Tiny, seedable, and written out in full HERE so goldens never depend on
/// stdlib RNG internals.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension SplitMix64 {
    /// Uniform in [0, 1): top 24 bits → Float. Bypasses Float.random(in:using:),
    /// whose u64→Float mapping is a stdlib implementation detail — the parity
    /// goldens outlive toolchains, so the harness owns the mapping.
    mutating func unitFloat() -> Float {
        Float(next() >> 40) * 0x1p-24
    }

    mutating func float(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + (range.upperBound - range.lowerBound) * unitFloat()
    }
}
