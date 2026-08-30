//
//  SeededRandom.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/28/26.
//

/// SplitMix64 (Steele/Lea/Flood — the java.util.SplittableRandom mixer).
/// Tiny, seedable, and written out in full HERE so goldens (the committed
/// known-good trajectory recordings in Physics/Baselines/*.json that
/// PhysicsParityTests diffs fresh runs against) never depend on stdlib RNG
/// internals.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    /// One output, two independent halves:
    ///
    /// 1. `state &+= 0x9E37…`: the state is just a counter (a Weyl sequence)
    ///    advancing by a fixed odd increment — ⌊2⁶⁴/φ⌋, the golden ratio.
    ///    Odd ⇒ coprime with 2⁶⁴ ⇒ the state visits all 2⁶⁴ values before
    ///    repeating (full period). The wrapping ops (&+, &*) ARE the
    ///    algorithm — everything is arithmetic mod 2⁶⁴, not ignored overflow.
    /// 2. The xorshift-multiply rounds are an avalanche finalizer (David
    ///    Stafford's "Mix13" variant of MurmurHash3's 64-bit finalizer):
    ///    each shift-xor + odd-constant multiply diffuses every state bit
    ///    into every output bit, so consecutive — heavily correlated —
    ///    counter values come out statistically independent.
    ///
    /// Reference C implementation (Vigna): https://prng.di.unimi.it/splitmix64.c
    /// Paper: Steele, Lea & Flood, "Fast Splittable Pseudorandom Number
    /// Generators" (OOPSLA 2014): https://gee.cs.oswego.edu/dl/papers/oopsla14.pdf
    /// Mix13 constants: https://zimbry.blogspot.com/2011/09/better-bit-mixing-improving-on.html
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
