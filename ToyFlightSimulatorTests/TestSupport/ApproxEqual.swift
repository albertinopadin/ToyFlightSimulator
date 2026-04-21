//
//  ApproxEqual.swift
//  ToyFlightSimulatorTests
//

import simd

let defaultTolerance: Float = 1e-4

func approxEqual(_ a: Float, _ b: Float, tolerance: Float = defaultTolerance) -> Bool {
    abs(a - b) <= tolerance
}

func approxEqual(_ a: SIMD3<Float>, _ b: SIMD3<Float>, tolerance: Float = defaultTolerance) -> Bool {
    approxEqual(a.x, b.x, tolerance: tolerance) &&
    approxEqual(a.y, b.y, tolerance: tolerance) &&
    approxEqual(a.z, b.z, tolerance: tolerance)
}

func approxEqual(_ a: SIMD4<Float>, _ b: SIMD4<Float>, tolerance: Float = defaultTolerance) -> Bool {
    approxEqual(a.x, b.x, tolerance: tolerance) &&
    approxEqual(a.y, b.y, tolerance: tolerance) &&
    approxEqual(a.z, b.z, tolerance: tolerance) &&
    approxEqual(a.w, b.w, tolerance: tolerance)
}

func approxEqual(_ a: simd_float4x4, _ b: simd_float4x4, tolerance: Float = defaultTolerance) -> Bool {
    approxEqual(a.columns.0, b.columns.0, tolerance: tolerance) &&
    approxEqual(a.columns.1, b.columns.1, tolerance: tolerance) &&
    approxEqual(a.columns.2, b.columns.2, tolerance: tolerance) &&
    approxEqual(a.columns.3, b.columns.3, tolerance: tolerance)
}

func approxEqual(_ a: simd_float3x3, _ b: simd_float3x3, tolerance: Float = defaultTolerance) -> Bool {
    approxEqual(a.columns.0, b.columns.0, tolerance: tolerance) &&
    approxEqual(a.columns.1, b.columns.1, tolerance: tolerance) &&
    approxEqual(a.columns.2, b.columns.2, tolerance: tolerance)
}
