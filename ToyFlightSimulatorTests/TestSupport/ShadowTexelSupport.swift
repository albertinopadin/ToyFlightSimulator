//
//  ShadowTexelSupport.swift
//  ToyFlightSimulatorTests
//
//  Helpers for tests that ask where a world point lands inside a shadow-map texel.
//  A static object's shadow edge stays still only while the object keeps the same
//  position inside a texel, so "did the point move inside its texel" is the question
//  the snap-phase tests ask (ShadowCascadeFittingTests on the pure functions,
//  LightObjectSnapPhaseTests through a fitted LightObject).
//

import simd
@testable import ToyFlightSimulator

/// Where a world point lands in a cascade's shadow map, in texels.
/// The view-projection matrix gives normalized device coordinates in -1 ... 1;
/// `* 0.5 + 0.5` maps them to 0 ... 1 across the map and the resolution turns
/// that into texels. The matrix is the Float one the renderer uses, but the
/// multiply runs in Double: a Float multiply near 1 km from the origin would add
/// a few thousandths of a cascade-0 texel of noise, which is the size of the
/// effect under test.
func shadowMapTexelCoordinate(of pointWorld: SIMD3<Double>,
                              viewProjectionMatrix: float4x4,
                              shadowMapResolution: Int) -> SIMD2<Double> {
    let viewProjection = simd_double4x4(SIMD4<Double>(viewProjectionMatrix.columns.0),
                                        SIMD4<Double>(viewProjectionMatrix.columns.1),
                                        SIMD4<Double>(viewProjectionMatrix.columns.2),
                                        SIMD4<Double>(viewProjectionMatrix.columns.3))
    let clip = viewProjection * SIMD4<Double>(pointWorld.x, pointWorld.y, pointWorld.z, 1)
    let normalizedDeviceXY = SIMD2<Double>(clip.x, clip.y) / clip.w
    return (normalizedDeviceXY * 0.5 + 0.5) * Double(shadowMapResolution)
}

/// Distance between two positions on a texel grid after removing whole texels,
/// as the larger of the two axes. 0 = same place inside a texel, 0.5 = the
/// farthest apart two such positions can be. Subtracting the rounded difference
/// makes 0.999 and 0.001 come out 0.002 apart, not 0.998.
func subTexelDistance(_ first: SIMD2<Double>, _ second: SIMD2<Double>) -> Double {
    var difference = first - second
    difference = difference - difference.rounded(.toNearestOrEven)
    return max(abs(difference.x), abs(difference.y))
}

/// The cascade view-projection matrices a light's last fit wrote into its `lightData`.
/// LightData's C array arrives in Swift as a four-element tuple; this reads it as an
/// array. Entries past the light's cascade count hold whatever LightData started with.
func cascadeViewProjectionMatrices(of light: LightObject) -> [float4x4] {
    let matrices = light.lightData.cascadeViewProjectionMatrices
    return [matrices.0, matrices.1, matrices.2, matrices.3]
}
