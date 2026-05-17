//
//  Float3+Extensions.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/15/26.
//

import simd

extension float3 {
    /// World-frame Y axis. Mirrors Unity's `Vector3.up` — always world up,
    /// never the aircraft's body-up. For the body-frame up vector of a Node,
    /// use `getUpVector()` (the model matrix's column 1).
    static let up = Y_AXIS

    /// World-frame X axis. Mirrors Unity's `Vector3.right` — always world
    /// right, never the aircraft's body-right. For the body-frame right
    /// vector of a Node, use `getRightVector()` (the model matrix's column 0).
    static let right = X_AXIS

    var magnitude: Float {
        sqrt(x * x + y * y + z * z)
    }

    func normalize() -> float3 {
        let m = magnitude
        return m > 0 ? self / m : .zero
    }
}
