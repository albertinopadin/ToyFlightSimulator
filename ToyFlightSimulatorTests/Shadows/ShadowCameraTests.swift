//
//  ShadowCameraTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("ShadowCamera", .tags(.math))
struct ShadowCameraTests {

    // MARK: - Legacy sun-follow initializer

    @Test("legacy init: depthRange is 2*lift - 1")
    func legacyDepthRange() {
        let cam = ShadowCamera(direction: simd_normalize(SIMD3<Float>(0.3, 1, 0.2)),
                               focus: SIMD3<Float>(10, 5, -8),
                               radius: 50, lift: 200)
        #expect(approxEqual(cam.depthRange, 399, tolerance: 1e-2))
    }

    @Test("legacy init: focus projects to the center of the shadow frustum")
    func legacyFocusCentered() {
        let cam = ShadowCamera(direction: simd_normalize(SIMD3<Float>(0.3, 1, 0.2)),
                               focus: SIMD3<Float>(10, 5, -8),
                               radius: 50, lift: 200)
        let clip = cam.viewProjectionMatrix * SIMD4<Float>(10, 5, -8, 1)
        let ndc = clip.xyz / clip.w
        #expect(approxEqual(ndc.x, 0, tolerance: 1e-3))
        #expect(approxEqual(ndc.y, 0, tolerance: 1e-3))
        #expect(ndc.z > 0 && ndc.z < 1)   // forward-Z, focus mid-frustum
        #expect(allFinite(cam.viewProjectionMatrix))
    }

    // MARK: - Cascade-fit initializer

    @Test("cascade-fit init: depthRange is farZ - nearZ")
    func cascadeFitDepthRange() {
        let cam = ShadowCamera(lightView: matrix_identity_float4x4,
                               orthoMinX: -10, orthoMaxX: 10,
                               orthoMinY: -10, orthoMaxY: 10,
                               orthoNearZ: -100, orthoFarZ: 300)
        #expect(approxEqual(cam.depthRange, 400, tolerance: 1e-3))
    }

    @Test("cascade-fit init: forward-Z ortho maps nearZ->0, farZ->1")
    func cascadeFitForwardZ() {
        let cam = ShadowCamera(lightView: matrix_identity_float4x4,
                               orthoMinX: -10, orthoMaxX: 10,
                               orthoMinY: -10, orthoMaxY: 10,
                               orthoNearZ: 0, orthoFarZ: 100)
        let p = cam.projectionMatrix
        let near = (p * SIMD4<Float>(0, 0, 0,   1))
        let mid  = (p * SIMD4<Float>(0, 0, 50,  1))
        let far  = (p * SIMD4<Float>(0, 0, 100, 1))
        #expect(approxEqual(near.z / near.w, 0,   tolerance: 1e-4))
        #expect(approxEqual(mid.z  / mid.w,  0.5, tolerance: 1e-4))
        #expect(approxEqual(far.z  / far.w,  1,   tolerance: 1e-4))
    }

    @Test("cascade-fit init: box center projects to NDC center")
    func cascadeFitCentered() {
        let cam = ShadowCamera(lightView: matrix_identity_float4x4,
                               orthoMinX: -10, orthoMaxX: 10,
                               orthoMinY: -10, orthoMaxY: 10,
                               orthoNearZ: 0, orthoFarZ: 100)
        let clip = cam.viewProjectionMatrix * SIMD4<Float>(0, 0, 50, 1)
        #expect(approxEqual(clip.x / clip.w, 0, tolerance: 1e-4))
        #expect(approxEqual(clip.y / clip.w, 0, tolerance: 1e-4))
    }
}

@Suite("LightData defaults", .tags(.math))
struct LightDataTests {

    @Test("default LightData has no active cascades")
    func defaultCascadeCountZero() {
        #expect(LightData().cascadeCount == 0)
    }

    @Test("default cascade split depths are zero")
    func defaultSplitDepthsZero() {
        let s = LightData().cascadeSplitDepths
        #expect(s.0 == 0 && s.1 == 0 && s.2 == 0 && s.3 == 0)
    }

    @Test("default cascade depth ranges are non-zero (epsilon divisor safe)")
    func defaultDepthRangesNonZero() {
        let r = LightData().cascadeDepthRanges
        #expect(r.0 == 1 && r.1 == 1 && r.2 == 1 && r.3 == 1)
    }

    @Test("default cascade VP matrices are identity (finite)")
    func defaultCascadeMatricesIdentity() {
        let m = LightData().cascadeViewProjectionMatrices
        #expect(approxEqual(m.0, matrix_identity_float4x4))
        #expect(approxEqual(m.3, matrix_identity_float4x4))
    }
}
