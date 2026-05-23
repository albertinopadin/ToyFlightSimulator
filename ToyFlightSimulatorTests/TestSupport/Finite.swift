//
//  Finite.swift
//  ToyFlightSimulatorTests
//

import simd

func allFinite(_ v: SIMD4<Float>) -> Bool {
    v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite
}

func allFinite(_ m: simd_float4x4) -> Bool {
    allFinite(m.columns.0) && allFinite(m.columns.1) &&
    allFinite(m.columns.2) && allFinite(m.columns.3)
}
