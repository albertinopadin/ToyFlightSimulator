//
//  ShadowCascadeFittingTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("ShadowCascadeFitting", .tags(.math))
struct ShadowCascadeFittingTests {

    // MARK: - computeSplits

    @Test("computeSplits returns one far per cascade, last == far")
    func splitCountAndLast() {
        let splits = ShadowCascadeFitting.computeSplits(near: 0.1, far: 500,
                                                        cascadeCount: 4, lambda: 0.5)
        #expect(splits.count == 4)
        #expect(approxEqual(splits.last!, 500, tolerance: 1e-2))
    }

    @Test("computeSplits is strictly increasing")
    func splitsMonotonic() {
        let splits = ShadowCascadeFitting.computeSplits(near: 0.1, far: 500,
                                                        cascadeCount: 4, lambda: 0.5)
        for i in 1..<splits.count {
            #expect(splits[i] > splits[i - 1])
        }
    }

    @Test("lambda=0 gives uniform splits")
    func uniformSplits() {
        let near: Float = 1, far: Float = 101
        let splits = ShadowCascadeFitting.computeSplits(near: near, far: far,
                                                        cascadeCount: 4, lambda: 0)
        // uniform_i = near + (far-near)*(i+1)/N → 26, 51, 76, 101
        #expect(approxEqual(splits[0], 26, tolerance: 1e-2))
        #expect(approxEqual(splits[1], 51, tolerance: 1e-2))
        #expect(approxEqual(splits[2], 76, tolerance: 1e-2))
        #expect(approxEqual(splits[3], 101, tolerance: 1e-2))
    }

    @Test("lambda=1 gives logarithmic splits")
    func logarithmicSplits() {
        let near: Float = 1, far: Float = 16
        let splits = ShadowCascadeFitting.computeSplits(near: near, far: far,
                                                        cascadeCount: 4, lambda: 1)
        // log_i = near * (far/near)^((i+1)/N) = 16^(0.25 .. 1.0) → 2, 4, 8, 16
        #expect(approxEqual(splits[0], 2, tolerance: 1e-2))
        #expect(approxEqual(splits[1], 4, tolerance: 1e-2))
        #expect(approxEqual(splits[2], 8, tolerance: 1e-2))
        #expect(approxEqual(splits[3], 16, tolerance: 1e-2))
    }

    // MARK: - boundingSphereForSlice

    /// The load-bearing property of the sphere fit: radius is invariant under
    /// camera rotation. Without this, texel snap can't hold a stable shadow edge.
    @Test("bounding sphere radius is rotation-invariant")
    func radiusRotationInvariant() {
        let fovY: Float = 75.0 * .pi / 180
        let aspect: Float = 16.0 / 9.0
        let near: Float = 10, far: Float = 60

        func cameraInverse(yaw: Float, pitch: Float) -> float4x4 {
            let t = Transform.translationMatrix(SIMD3<Float>(123, 45, -678))
            let ry = Transform.rotationMatrix(radians: yaw, axis: SIMD3<Float>(0, 1, 0))
            let rx = Transform.rotationMatrix(radians: pitch, axis: SIMD3<Float>(1, 0, 0))
            return t * ry * rx
        }

        let a = ShadowCascadeFitting.boundingSphereForSlice(
            cameraInverse: cameraInverse(yaw: 0, pitch: 0),
            fovYRadians: fovY, aspect: aspect, sliceNear: near, sliceFar: far)
        let b = ShadowCascadeFitting.boundingSphereForSlice(
            cameraInverse: cameraInverse(yaw: 1.1, pitch: -0.4),
            fovYRadians: fovY, aspect: aspect, sliceNear: near, sliceFar: far)

        #expect(approxEqual(a.radius, b.radius, tolerance: 1e-2))
    }

    @Test("bounding sphere radius scales with camera world scale")
    func radiusScalesWithCameraScale() {
        let fovY: Float = 60.0 * .pi / 180
        let aspect: Float = 1.0
        let near: Float = 5, far: Float = 25

        let unit = Transform.scaleMatrix(SIMD3<Float>(1, 1, 1))
        let scaled = Transform.scaleMatrix(SIMD3<Float>(3, 3, 3))

        let r1 = ShadowCascadeFitting.boundingSphereForSlice(
            cameraInverse: unit, fovYRadians: fovY, aspect: aspect,
            sliceNear: near, sliceFar: far).radius
        let r3 = ShadowCascadeFitting.boundingSphereForSlice(
            cameraInverse: scaled, fovYRadians: fovY, aspect: aspect,
            sliceNear: near, sliceFar: far).radius

        #expect(approxEqual(r3, r1 * 3, tolerance: 1e-2))
    }

    @Test("bounding sphere center lies at the slice midpoint along forward")
    func sphereCenterAtMidpoint() {
        // Identity camera inverse: world == view, forward is +Z.
        let identity = matrix_identity_float4x4
        let near: Float = 10, far: Float = 30
        let result = ShadowCascadeFitting.boundingSphereForSlice(
            cameraInverse: identity, fovYRadians: 1.0, aspect: 1.0,
            sliceNear: near, sliceFar: far)
        // midZ = 20, along +Z.
        #expect(approxEqual(result.centerWorld, SIMD3<Float>(0, 0, 20), tolerance: 1e-3))
    }

    // MARK: - fitCascades

    @Test("fitCascades produces the requested number of cascades")
    func fitCascadeCount() {
        let snap = ShadowCascadeFitting.CameraSnapshot(
            viewMatrix: matrix_identity_float4x4,
            near: 0.1, far: 1_000_000, fovY: 1.3, aspect: 1.78)
        let fit = ShadowCascadeFitting.fitCascades(
            camera: snap,
            lightDirection: simd_normalize(SIMD3<Float>(0.2, 1, 0.3)),
            shadowMapResolution: 4096,
            cascadeCount: 4, lambda: 0.5,
            shadowMaxDistance: 500, zPaddingWorldUnits: 100)
        #expect(fit.cascades.count == 4)
        #expect(fit.splitFars.count == 4)
    }

    @Test("fitCascades caps the far split at shadowMaxDistance, not camera far")
    func fitCascadeFarCap() {
        let snap = ShadowCascadeFitting.CameraSnapshot(
            viewMatrix: matrix_identity_float4x4,
            near: 0.1, far: 1_000_000, fovY: 1.3, aspect: 1.78)
        let fit = ShadowCascadeFitting.fitCascades(
            camera: snap,
            lightDirection: simd_normalize(SIMD3<Float>(0.2, 1, 0.3)),
            shadowMapResolution: 4096,
            cascadeCount: 4, lambda: 0.5,
            shadowMaxDistance: 500, zPaddingWorldUnits: 100)
        // Last split far must be ~500 (the cap), not ~1,000,000.
        #expect(fit.splitFars.last! <= 500.5)
        #expect(fit.splitFars.last! >= 499.5)
    }

    /// Texel snap means a sub-texel camera translation should produce an
    /// identical (snapped) cascade-0 view-projection matrix.
    @Test("fitCascades snaps cascade VP to texel grid under tiny translation")
    func texelSnapStability() {
        let light = simd_normalize(SIMD3<Float>(0.2, 1, 0.3))

        func fitAt(_ x: Float) -> float4x4 {
            // World transform of the camera (inverse view). viewMatrix = inverse.
            let world = Transform.translationMatrix(SIMD3<Float>(x, 50, 0))
            let snap = ShadowCascadeFitting.CameraSnapshot(
                viewMatrix: world.inverse,
                near: 0.1, far: 1_000_000, fovY: 1.3, aspect: 1.78)
            let fit = ShadowCascadeFitting.fitCascades(
                camera: snap, lightDirection: light,
                shadowMapResolution: 4096, cascadeCount: 4, lambda: 0.5,
                shadowMaxDistance: 500, zPaddingWorldUnits: 100)
            return fit.cascades[0].viewProjectionMatrix
        }

        // A translation far smaller than one cascade-0 texel should snap away.
        let m0 = fitAt(0)
        let mTiny = fitAt(1e-5)
        #expect(approxEqual(m0, mTiny, tolerance: 1e-2))
    }

    // MARK: - Edge cases / robustness

    @Test("computeSplits with a single cascade returns just the far plane")
    func singleCascadeSplit() {
        let splits = ShadowCascadeFitting.computeSplits(near: 0.1, far: 400,
                                                        cascadeCount: 1, lambda: 0.5)
        #expect(splits.count == 1)
        #expect(approxEqual(splits[0], 400, tolerance: 1e-2))
    }

    @Test("computeSplits stays strictly within (near, far]")
    func splitsWithinRange() {
        let near: Float = 0.05, far: Float = 750
        for lambda: Float in [0, 0.25, 0.5, 0.75, 1] {
            let splits = ShadowCascadeFitting.computeSplits(near: near, far: far,
                                                            cascadeCount: 4, lambda: lambda)
            for s in splits {
                #expect(s > near)
                #expect(s <= far + 1e-2)
            }
        }
    }

    @Test("fitCascades supports a single cascade")
    func fitSingleCascade() {
        let snap = ShadowCascadeFitting.CameraSnapshot(
            viewMatrix: matrix_identity_float4x4,
            near: 0.1, far: 1000, fovY: 1.2, aspect: 1.5)
        let fit = ShadowCascadeFitting.fitCascades(
            camera: snap,
            lightDirection: simd_normalize(SIMD3<Float>(0.3, 1, 0.2)),
            shadowMapResolution: 2048, cascadeCount: 1, lambda: 0.5,
            shadowMaxDistance: 400, zPaddingWorldUnits: 50)
        #expect(fit.cascades.count == 1)
        #expect(fit.splitFars.count == 1)
    }

    /// A sun pointing straight down makes cross(Y_AXIS, lightDir) collapse; the
    /// fitter must fall back to a world +X basis rather than emit NaNs.
    @Test("fitCascades handles a straight-overhead light without NaNs")
    func overheadLightNoNaN() {
        let snap = ShadowCascadeFitting.CameraSnapshot(
            viewMatrix: matrix_identity_float4x4,
            near: 0.1, far: 1_000_000, fovY: 1.309, aspect: 1.78)
        let fit = ShadowCascadeFitting.fitCascades(
            camera: snap,
            lightDirection: SIMD3<Float>(0, 1, 0),   // straight up — degenerate basis
            shadowMapResolution: 4096, cascadeCount: 4, lambda: 0.5,
            shadowMaxDistance: 500, zPaddingWorldUnits: 100)
        for cascade in fit.cascades {
            #expect(allFinite(cascade.viewProjectionMatrix))
        }
    }

    @Test("fitCascades produces finite matrices and positive depth ranges")
    func fitFiniteAndPositiveRanges() {
        let snap = ShadowCascadeFitting.CameraSnapshot(
            viewMatrix: Transform.translationMatrix(SIMD3<Float>(8000, 200, -12000)).inverse,
            near: 0.1, far: 1_000_000, fovY: 1.309, aspect: 1.78)
        let fit = ShadowCascadeFitting.fitCascades(
            camera: snap,
            lightDirection: simd_normalize(SIMD3<Float>(0.2, 1, 0.3)),
            shadowMapResolution: 4096, cascadeCount: 4, lambda: 0.5,
            shadowMaxDistance: 500, zPaddingWorldUnits: 100)
        for cascade in fit.cascades {
            #expect(allFinite(cascade.viewProjectionMatrix))
            #expect(cascade.depthRange > 0)
        }
    }
}
