//
//  Float3+Extensions.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/15/26.
//

extension float3 {
    static let up = Y_AXIS
    static let right = X_AXIS
    
    var magnitude: Float {
        sqrt(x * x + y * y + z * z)
    }
    
    func normalize() -> float3 {
        let m = magnitude
        return m > 0 ? self / magnitude : .zero
    }
}
