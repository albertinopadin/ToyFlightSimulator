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

    // MARK: - lightBasis
    //
    // The texel grid of a cascade is laid out along the light's X and Y axes.
    // `fitCascades` snaps along them and `snapPhasesAfterOriginShift` measures
    // the shift offset along them, so both must use the same three axes.

    @Test("lightBasis returns unit, perpendicular axes with Z opposite the light direction",
          arguments: [simd_normalize(SIMD3<Float>(0.2, 1, 0.3)),   // tilted sun
                      SIMD3<Float>(0, 1, 0),                       // straight overhead: the fallback branch
                      simd_normalize(SIMD3<Float>(-0.7, 0.1, 0.4))]) // low sun
    func lightBasisIsOrthonormal(lightDirection: SIMD3<Float>) {
        let basis = ShadowCascadeFitting.lightBasis(lightDirection: lightDirection)
        #expect(allFinite(basis.xWorld) && allFinite(basis.yWorld) && allFinite(basis.zWorld))
        #expect(approxEqual(simd_length(basis.xWorld), 1, tolerance: 1e-5))
        #expect(approxEqual(simd_length(basis.yWorld), 1, tolerance: 1e-5))
        #expect(approxEqual(simd_dot(basis.xWorld, basis.yWorld), 0, tolerance: 1e-5))
        #expect(approxEqual(simd_dot(basis.xWorld, basis.zWorld), 0, tolerance: 1e-5))
        #expect(approxEqual(simd_dot(basis.yWorld, basis.zWorld), 0, tolerance: 1e-5))
        #expect(approxEqual(basis.zWorld, -lightDirection, tolerance: 1e-6))
    }

    /// Row k of the upper-left 3x3 of a view matrix is the k-th view axis in
    /// world coordinates. If `fitCascades` ever builds its light view from other
    /// axes than `lightBasis`, a phase measured along `lightBasis` is wrong.
    @Test("fitCascades builds every cascade's light view from lightBasis")
    func lightViewRowsAreTheLightBasis() {
        let basis = ShadowCascadeFitting.lightBasis(lightDirection: snapPhaseTestLight)
        let fit = fitForSnapPhaseTest(camera: snapPhaseTestCamera(position: [640.37, 310.12, -720.59],
                                                                  yaw: 0.7, pitch: -0.15),
                                      cascadeSnapPhases: [])
        for cascade in fit.cascades {
            let view = cascade.viewMatrix
            let rowX = SIMD3<Float>(view.columns.0.x, view.columns.1.x, view.columns.2.x)
            let rowY = SIMD3<Float>(view.columns.0.y, view.columns.1.y, view.columns.2.y)
            let rowZ = SIMD3<Float>(view.columns.0.z, view.columns.1.z, view.columns.2.z)
            #expect(approxEqual(rowX, basis.xWorld, tolerance: 1e-6))
            #expect(approxEqual(rowY, basis.yWorld, tolerance: 1e-6))
            #expect(approxEqual(rowZ, basis.zWorld, tolerance: 1e-6))
        }
    }

    // MARK: - positiveRemainder

    /// `truncatingRemainder` keeps the sign of the value (-7.25 rem 2 = -1.25).
    /// A phase has to be a position inside one texel, so a negative remainder
    /// gets one modulus added: -1.25 + 2 = 0.75.
    @Test("positiveRemainder wraps values of either sign into 0 ..< modulus")
    func positiveRemainderWrapsBothSigns() {
        // Every number here is exact in binary, so the results are compared exactly.
        #expect(ShadowCascadeFitting.positiveRemainder(value:  7.25, modulus: 2) == 1.25)
        #expect(ShadowCascadeFitting.positiveRemainder(value: -7.25, modulus: 2) == 0.75)
        #expect(ShadowCascadeFitting.positiveRemainder(value:  1.5,  modulus: 2) == 1.5)
        #expect(ShadowCascadeFitting.positiveRemainder(value: -0.5,  modulus: 2) == 1.5)
        #expect(ShadowCascadeFitting.positiveRemainder(value:  0,    modulus: 2) == 0)
        #expect(ShadowCascadeFitting.positiveRemainder(value:  4,    modulus: 2) == 0)
        #expect(ShadowCascadeFitting.positiveRemainder(value: -4,    modulus: 2) == 0)
    }

    // MARK: - snapPhasesAfterOriginShift
    //
    // A cascade's snap phase is where its texel grid sits along the light's X
    // and Y axes, in meters, in the current floating-origin frame. When the
    // origin moves by `shiftOffset`, every stored position loses that offset,
    // so the grid must lose it too:
    //     newPhase = positiveRemainder(oldPhase - dot(lightAxis, shiftOffset), texelSize)

    /// Small enough to check by hand. A straight-overhead light has
    /// xWorld = (0, 0, -1) and yWorld = (1, 0, 0), so for the offset
    /// (0.03, 0, 0.02) m the offset along light X is -0.02 m and along light Y
    /// is 0.03 m. With a 0.05 m texel and an old phase of (0.01, 0.02) m:
    ///     x: 0.01 - (-0.02) =  0.03            -> 0.03 m
    ///     y: 0.02 -   0.03  = -0.01, plus 0.05 -> 0.04 m
    @Test("snapPhasesAfterOriginShift: hand-checked example with an overhead light")
    func snapPhaseWorkedExample() {
        let newPhases = ShadowCascadeFitting.snapPhasesAfterOriginShift(
            cascadeSnapPhases: [SIMD2<Double>(0.01, 0.02)],
            texelSizes: [0.05],
            lightDirection: SIMD3<Float>(0, 1, 0),
            shiftOffset: SIMD3<Float>(0.03, 0, 0.02))
        #expect(newPhases.count == 1)
        // 1e-6 m: the inputs 0.05, 0.03 and 0.02 are Floats, off from the decimal by about 1e-9.
        #expect(abs(newPhases[0].x - 0.03) < 1e-6)
        #expect(abs(newPhases[0].y - 0.04) < 1e-6)
    }

    /// A light that has not been through a shift yet has no stored phases. The
    /// fit treats a missing phase as (0, 0), so the phase update must as well.
    @Test("snapPhasesAfterOriginShift returns one phase per texel size and reads a missing phase as zero")
    func snapPhaseCountAndMissingPhases() {
        let offset = SIMD3<Float>(12.5, -3.25, 800.125)
        let onlyFirstPhase = ShadowCascadeFitting.snapPhasesAfterOriginShift(
            cascadeSnapPhases: [SIMD2<Double>(0.011, 0.042)],
            texelSizes: snapPhaseTestTexelSizes,
            lightDirection: snapPhaseTestLight, shiftOffset: offset)
        let explicitZeros = ShadowCascadeFitting.snapPhasesAfterOriginShift(
            cascadeSnapPhases: [SIMD2<Double>(0.011, 0.042), .zero, .zero, .zero],
            texelSizes: snapPhaseTestTexelSizes,
            lightDirection: snapPhaseTestLight, shiftOffset: offset)
        let noPhases = ShadowCascadeFitting.snapPhasesAfterOriginShift(
            cascadeSnapPhases: [],
            texelSizes: snapPhaseTestTexelSizes,
            lightDirection: snapPhaseTestLight, shiftOffset: offset)

        #expect(onlyFirstPhase.count == snapPhaseTestTexelSizes.count)
        #expect(noPhases.count == snapPhaseTestTexelSizes.count)
        #expect(onlyFirstPhase == explicitZeros)
        for (phase, texelSize) in zip(noPhases, snapPhaseTestTexelSizes) {
            #expect(phase.x >= 0 && phase.x <= Double(texelSize))
            #expect(phase.y >= 0 && phase.y <= Double(texelSize))
        }
    }

    /// Three offsets that must leave the grid where it was, and one that must not.
    /// Distances are in texels, measured after removing whole texels (0 = same
    /// place, 0.5 = as far off as a grid can be).
    @Test("snapPhasesAfterOriginShift only reacts to the part of the offset that is across the light, modulo one texel")
    func snapPhaseIgnoresWhatCannotMoveTheGrid() {
        let basis = ShadowCascadeFitting.lightBasis(lightDirection: snapPhaseTestLight)
        let oldPhases: [SIMD2<Double>] = [SIMD2(0.011, 0.042), SIMD2(0.07, 0.003),
                                          SIMD2(0.1, 0.15), SIMD2(0.2, 0.38)]

        /// Largest move of any cascade's grid, in texels of that cascade.
        func largestGridMove_texels(shiftOffset: SIMD3<Float>, texelSizes: [Float]) -> Double {
            let newPhases = ShadowCascadeFitting.snapPhasesAfterOriginShift(
                cascadeSnapPhases: oldPhases, texelSizes: texelSizes,
                lightDirection: snapPhaseTestLight, shiftOffset: shiftOffset)
            var largest = 0.0
            for cascadeIndex in 0..<texelSizes.count {
                let texelSize = Double(texelSizes[cascadeIndex])
                largest = max(largest, subTexelDistance(newPhases[cascadeIndex] / texelSize,
                                                        oldPhases[cascadeIndex] / texelSize))
            }
            return largest
        }

        // No shift at all: exactly unchanged.
        #expect(largestGridMove_texels(shiftOffset: .zero, texelSizes: snapPhaseTestTexelSizes) == 0)

        // Along the light direction: the grid lies across the light, so moving
        // along it changes nothing. Scratch run: 0.0004 texel (the Float basis is
        // perpendicular to the direction only to about 3e-8).
        #expect(largestGridMove_texels(shiftOffset: snapPhaseTestLight * 873.6,
                                       texelSizes: snapPhaseTestTexelSizes) < 0.01)

        // A whole number of texels across the light (1000 along X, 400 along Y,
        // one cascade): the grid lands on itself. Scratch run: 0.0001 texel.
        let texelSize: Float = 0.05
        #expect(largestGridMove_texels(shiftOffset: basis.xWorld * (texelSize * 1000) + basis.yWorld * (texelSize * 400),
                                       texelSizes: [texelSize]) < 0.01)

        // 1000.5 texels along light X: the grid ends up half a texel away, which
        // is what a shift does to the old snap that carried no phase.
        #expect(largestGridMove_texels(shiftOffset: basis.xWorld * (texelSize * 1000.5),
                                       texelSizes: [texelSize]) > 0.49)
    }

    /// Why the phase is stored in Double. 1,000 shifts of about 1 km each are a
    /// flight of over 1,000 km. Updating the phase once per shift must give the
    /// same grid as one update by the whole distance (summed in Double). Scratch
    /// run: they differ by 1.3e-9 texel. In Float, the offset along a light axis
    /// (up to 1,000 m) could only be held to 0.06 mm, the gap between
    /// neighbouring Floats there, which is about a thousandth of a cascade-0
    /// texel of rounding on every shift.
    @Test("snapPhasesAfterOriginShift: 1,000 shifts in a row equal one shift by their Double total")
    func snapPhaseChainEqualsOneShiftByTheTotal() {
        let basis = ShadowCascadeFitting.lightBasis(lightDirection: snapPhaseTestLight)
        var generator = SplitMix64(seed: 42)
        var chainedPhases: [SIMD2<Double>] = []
        var totalOffset = SIMD3<Double>(0, 0, 0)

        for _ in 0..<1_000 {
            let shiftOffset = SIMD3<Float>(generator.float(in: 700...1000),
                                           generator.float(in: -40...40),
                                           generator.float(in: 650...950))
            chainedPhases = ShadowCascadeFitting.snapPhasesAfterOriginShift(
                cascadeSnapPhases: chainedPhases, texelSizes: snapPhaseTestTexelSizes,
                lightDirection: snapPhaseTestLight, shiftOffset: shiftOffset)
            totalOffset += shiftOffset.toDouble3()
        }
        #expect(simd_length(totalOffset) > 1_000_000)   // meters: the flight really is that long

        for cascadeIndex in 0..<snapPhaseTestTexelSizes.count {
            let texelSize = Double(snapPhaseTestTexelSizes[cascadeIndex])
            let phaseFromTotal = SIMD2<Double>(
                ShadowCascadeFitting.positiveRemainder(value: -simd_dot(basis.xWorld.toDouble3(), totalOffset),
                                                       modulus: texelSize),
                ShadowCascadeFitting.positiveRemainder(value: -simd_dot(basis.yWorld.toDouble3(), totalOffset),
                                                       modulus: texelSize))
            #expect(subTexelDistance(chainedPhases[cascadeIndex] / texelSize, phaseFromTotal / texelSize) < 1e-6,
                    "cascade \(cascadeIndex)")
        }
    }

    // MARK: - fitCascades with snap phases

    /// A shadow map of `resolution` texels covers the cascade's ortho width, so
    /// texel size = ortho width / resolution. `orthographicProjection` stores
    /// 2 / width in columns.0.x. The phase update wraps by these sizes, so they
    /// must be the sizes the shadow map is really drawn with.
    @Test("fitCascades returns one texel size per cascade, equal to ortho width / resolution")
    func texelSizesMatchTheOrthoProjection() {
        let fit = fitForSnapPhaseTest(camera: snapPhaseTestCamera(position: [640.37, 310.12, -720.59],
                                                                  yaw: 0.7, pitch: -0.15),
                                      cascadeSnapPhases: [])
        #expect(fit.texelSizes.count == snapPhaseTestCascadeCount)
        for cascadeIndex in 0..<fit.texelSizes.count {
            let orthoWidth_m = 2 / fit.cascades[cascadeIndex].projectionMatrix.columns.0.x
            let expectedTexelSize_m = orthoWidth_m / Float(snapPhaseTestShadowMapResolution)
            #expect(fit.texelSizes[cascadeIndex] > 0)
            #expect(abs(fit.texelSizes[cascadeIndex] - expectedTexelSize_m) <= 1e-5 * expectedTexelSize_m,
                    "cascade \(cascadeIndex)")
        }
        // A nearer cascade covers less ground with the same texel count.
        for cascadeIndex in 1..<fit.texelSizes.count {
            #expect(fit.texelSizes[cascadeIndex] > fit.texelSizes[cascadeIndex - 1])
        }
    }

    /// Before any shift the phases are empty, and callers that never pass them
    /// (the default argument) must get the grid through the current origin that
    /// `fitCascades` always produced.
    @Test("fitCascades with no phases is identical to fitCascades with zero phases")
    func emptyPhasesEqualZeroPhases() {
        let camera = snapPhaseTestCamera(position: [640.37, 310.12, -720.59], yaw: 0.7, pitch: -0.15)
        let defaulted = ShadowCascadeFitting.fitCascades(
            camera: camera, lightDirection: snapPhaseTestLight,
            shadowMapResolution: snapPhaseTestShadowMapResolution,
            cascadeCount: snapPhaseTestCascadeCount, lambda: 0.5,
            shadowMaxDistance: 500, zPaddingWorldUnits: 100)
        let empty = fitForSnapPhaseTest(camera: camera, cascadeSnapPhases: [])
        let zeros = fitForSnapPhaseTest(camera: camera,
                                        cascadeSnapPhases: [SIMD2<Double>](repeating: .zero,
                                                                           count: snapPhaseTestCascadeCount))
        for cascadeIndex in 0..<snapPhaseTestCascadeCount {
            #expect(defaulted.cascades[cascadeIndex].viewProjectionMatrix == zeros.cascades[cascadeIndex].viewProjectionMatrix)
            #expect(empty.cascades[cascadeIndex].viewProjectionMatrix == zeros.cascades[cascadeIndex].viewProjectionMatrix)
        }
    }

    /// Two properties of the snap, for any phase:
    /// 1. The snapped cascade centre lies on the grid `phase + k * texelSize`
    ///    (k a whole number) along both light axes.
    /// 2. The snap moves the centre back by less than one texel, so the shadow
    ///    map still covers the slice's bounding sphere.
    /// The third set of phases is far outside 0 ..< texelSize on purpose: the fit
    /// does not rely on the caller keeping phases in range.
    ///
    /// How the snapped centre is read back: the light view's translation column
    /// is -dot(axis, eye) with eye = snappedCentre + lightDirection * radius, and
    /// the light's X and Y axes are perpendicular to its direction, so
    /// -columns.3.x and -columns.3.y are the snapped centre along X and Y.
    @Test("fitCascades puts each cascade centre on the grid its phase names, less than one texel behind the slice centre",
          arguments: [[SIMD2<Double>](),
                      [SIMD2<Double>(0.011, 0.042), SIMD2<Double>(0.07, 0.003),
                       SIMD2<Double>(0.1, 0.15), SIMD2<Double>(0.2, 0.38)],
                      [SIMD2<Double>(-3.7, 1234.56), SIMD2<Double>(55.5, -0.001),
                       SIMD2<Double>(1e4, -1e4), SIMD2<Double>(0.389, 0.389)]])
    func cascadeCentreSitsOnThePhasedGrid(cascadeSnapPhases: [SIMD2<Double>]) {
        let camera = snapPhaseTestCamera(position: [640.37, 310.12, -720.59], yaw: 0.7, pitch: -0.15)
        let fit = fitForSnapPhaseTest(camera: camera, cascadeSnapPhases: cascadeSnapPhases)
        let basis = ShadowCascadeFitting.lightBasis(lightDirection: snapPhaseTestLight)

        var sliceNear = camera.near
        for cascadeIndex in 0..<snapPhaseTestCascadeCount {
            let texelSize = Double(fit.texelSizes[cascadeIndex])
            let phase = cascadeIndex < cascadeSnapPhases.count ? cascadeSnapPhases[cascadeIndex] : .zero
            let lightView = fit.cascades[cascadeIndex].viewMatrix
            let snappedCentreAlongLight = SIMD2<Double>(Double(-lightView.columns.3.x),
                                                        Double(-lightView.columns.3.y))

            // 1. On the grid. Scratch run: at most 0.0025 texel off (Float
            //    positions near 1 km are only exact to about 0.06 mm).
            let gridCells = (snappedCentreAlongLight - phase) / texelSize
            let distanceOffGrid = gridCells - gridCells.rounded(.toNearestOrEven)
            #expect(abs(distanceOffGrid.x) < 0.02, "cascade \(cascadeIndex), light X")
            #expect(abs(distanceOffGrid.y) < 0.02, "cascade \(cascadeIndex), light Y")

            // 2. floor() snaps downward, so the slice centre is 0 ..< 1 texel
            //    past the snapped centre. Scratch run: 0.05 to 0.98.
            let sphere = ShadowCascadeFitting.boundingSphereForSlice(
                cameraInverse: camera.viewMatrix.inverse,
                fovYRadians: camera.fovY, aspect: camera.aspect,
                sliceNear: sliceNear, sliceFar: fit.splitFars[cascadeIndex])
            sliceNear = fit.splitFars[cascadeIndex]
            let sliceCentreAlongLight = SIMD2<Double>(Double(simd_dot(basis.xWorld, sphere.centerWorld)),
                                                      Double(simd_dot(basis.yWorld, sphere.centerWorld)))
            let texelsPastSnappedCentre = (sliceCentreAlongLight - snappedCentreAlongLight) / texelSize
            #expect(texelsPastSnappedCentre.x > -0.01 && texelsPastSnappedCentre.x < 1.01, "cascade \(cascadeIndex), light X")
            #expect(texelsPastSnappedCentre.y > -0.01 && texelsPastSnappedCentre.y < 1.01, "cascade \(cascadeIndex), light Y")
        }
    }

    // MARK: - Floating-origin shift, end to end
    //
    // What the phase is for. A static object's shadow edge stays still only
    // while the object keeps the same position inside a shadow-map texel. A
    // floating-origin shift subtracts an offset from every stored position; the
    // offset is not a whole number of texels, so a grid that stays tied to the
    // origin lands somewhere else under the object and every shadow edge moves
    // for one frame. Carrying the phase moves the grid by the same offset.
    //
    // Each test models one shift the way SceneManager.updateFloatingOrigin does
    // it: fit (old frame, old phases), update the phases, subtract the offset
    // from the camera and from one static point, fit again (new frame, new
    // phases). The camera does not move through the world in between, so the
    // point must keep its sub-texel position in every cascade.

    /// One shift, with three kinds of offset: the raw camera position (what
    /// `updateFloatingOrigin` subtracted before `FloatingOrigin.getOffset`
    /// rounded it), the same rounded to whole meters (what it subtracts now),
    /// and a vector unrelated to the camera.
    /// Scratch run: phases carried, the point moves at most 0.0027 texel;
    /// phases not carried, it moves 0.14 to 0.49 texel.
    @Test("an origin shift leaves a static point on the same sub-texel position when the phases are carried",
          arguments: [SIMD3<Float>(640.37, 310.12, -720.59),
                      SIMD3<Float>(640, 310, -721),
                      SIMD3<Float>(-123.456, 78.9, 1011.12)])
    func oneShiftKeepsSubTexelPosition(shiftOffset: SIMD3<Float>) {
        let cameraPositionBefore = SIMD3<Float>(640.37, 310.12, -720.59)   // 1012.7 m from the origin
        let staticPointBefore = SIMD3<Double>(652.0, 0.0, -695.0)          // on the ground ahead of the camera
        let yaw: Float = 0.7, pitch: Float = -0.15

        let fitBefore = fitForSnapPhaseTest(camera: snapPhaseTestCamera(position: cameraPositionBefore,
                                                                        yaw: yaw, pitch: pitch),
                                            cascadeSnapPhases: [])
        let phasesAfter = ShadowCascadeFitting.snapPhasesAfterOriginShift(
            cascadeSnapPhases: [], texelSizes: fitBefore.texelSizes,
            lightDirection: snapPhaseTestLight, shiftOffset: shiftOffset)

        let cameraAfter = snapPhaseTestCamera(position: cameraPositionBefore - shiftOffset, yaw: yaw, pitch: pitch)
        let staticPointAfter = staticPointBefore - shiftOffset.toDouble3()
        let fitWithCarriedPhases = fitForSnapPhaseTest(camera: cameraAfter, cascadeSnapPhases: phasesAfter)
        let fitWithoutCarriedPhases = fitForSnapPhaseTest(camera: cameraAfter, cascadeSnapPhases: [])

        for cascadeIndex in 0..<snapPhaseTestCascadeCount {
            let texelBefore = shadowMapTexelCoordinate(of: staticPointBefore, in: fitBefore.cascades[cascadeIndex])
            let moveWithCarriedPhases = subTexelDistance(
                shadowMapTexelCoordinate(of: staticPointAfter, in: fitWithCarriedPhases.cascades[cascadeIndex]),
                texelBefore)
            let moveWithoutCarriedPhases = subTexelDistance(
                shadowMapTexelCoordinate(of: staticPointAfter, in: fitWithoutCarriedPhases.cascades[cascadeIndex]),
                texelBefore)
            #expect(moveWithCarriedPhases < 0.02, "cascade \(cascadeIndex)")
            // Control: shows that these offsets are not whole texels by luck, so
            // the expectation above is not passing for free.
            #expect(moveWithoutCarriedPhases > 0.05, "cascade \(cascadeIndex)")
        }
    }

    /// 200 shifts in a row (about 194 km), each fired where a real one fires:
    /// with the camera just past 1 km from the current origin, at a new heading
    /// and pitch. The phases go from one shift into the next, so an error in
    /// the update would build up. Even shifts subtract the raw camera position;
    /// odd shifts subtract it rounded to whole meters, which leaves the camera a
    /// fraction of a meter from the origin.
    /// Scratch run over 8 seeds: phases carried, at most 0.004 texel in any
    /// cascade; phases one shift old, 0.33 texel on average (the value for a
    /// grid that lands at random: the mean of the larger of two uniform 0 ... 0.5
    /// distances is 1/3).
    @Test("200 origin shifts in a row keep a static point on the same sub-texel position")
    func manyShiftsKeepSubTexelPosition() {
        var generator = SplitMix64(seed: 20261118)
        var cascadeSnapPhases: [SIMD2<Double>] = []
        var totalOffset = SIMD3<Double>(0, 0, 0)
        var largestMoveWithCarriedPhases = [Double](repeating: 0, count: snapPhaseTestCascadeCount)
        var meanMoveWithStalePhases = [Double](repeating: 0, count: snapPhaseTestCascadeCount)
        let shiftCount = 200

        for shiftIndex in 0..<shiftCount {
            // Mostly +X and +Z so the flight goes somewhere instead of circling.
            let directionFromOrigin = simd_normalize(SIMD3<Float>(generator.float(in: 0.3...1.0),
                                                                  generator.float(in: -0.2...0.2),
                                                                  generator.float(in: 0.3...1.0)))
            // 250 m/s at 60 Hz is 4.2 m per tick, so a shift fires 0 to 4.2 m past 1 km.
            let cameraPositionBefore = directionFromOrigin * generator.float(in: 1000.5...1004.5)
            let yaw = generator.float(in: -Float.pi...Float.pi)
            let pitch = generator.float(in: -0.4...0.4)
            let staticPointBefore = cameraPositionBefore.toDouble3() + SIMD3<Double>(3.25, -20.5, 30.75)

            let fitBefore = fitForSnapPhaseTest(camera: snapPhaseTestCamera(position: cameraPositionBefore,
                                                                            yaw: yaw, pitch: pitch),
                                                cascadeSnapPhases: cascadeSnapPhases)

            let shiftOffset = shiftIndex % 2 == 0 ? cameraPositionBefore
                                                  : cameraPositionBefore.rounded(.toNearestOrEven)
            let stalePhases = cascadeSnapPhases
            cascadeSnapPhases = ShadowCascadeFitting.snapPhasesAfterOriginShift(
                cascadeSnapPhases: cascadeSnapPhases, texelSizes: fitBefore.texelSizes,
                lightDirection: snapPhaseTestLight, shiftOffset: shiftOffset)
            totalOffset += shiftOffset.toDouble3()

            for (phase, texelSize) in zip(cascadeSnapPhases, fitBefore.texelSizes) {
                #expect(phase.x >= 0 && phase.x <= Double(texelSize))
                #expect(phase.y >= 0 && phase.y <= Double(texelSize))
            }

            let cameraAfter = snapPhaseTestCamera(position: cameraPositionBefore - shiftOffset, yaw: yaw, pitch: pitch)
            let staticPointAfter = staticPointBefore - shiftOffset.toDouble3()
            let fitAfter = fitForSnapPhaseTest(camera: cameraAfter, cascadeSnapPhases: cascadeSnapPhases)
            let fitWithStalePhases = fitForSnapPhaseTest(camera: cameraAfter, cascadeSnapPhases: stalePhases)

            for cascadeIndex in 0..<snapPhaseTestCascadeCount {
                let texelBefore = shadowMapTexelCoordinate(of: staticPointBefore, in: fitBefore.cascades[cascadeIndex])
                largestMoveWithCarriedPhases[cascadeIndex] = max(
                    largestMoveWithCarriedPhases[cascadeIndex],
                    subTexelDistance(shadowMapTexelCoordinate(of: staticPointAfter, in: fitAfter.cascades[cascadeIndex]),
                                     texelBefore))
                meanMoveWithStalePhases[cascadeIndex] += subTexelDistance(
                    shadowMapTexelCoordinate(of: staticPointAfter, in: fitWithStalePhases.cascades[cascadeIndex]),
                    texelBefore) / Double(shiftCount)
            }
        }

        #expect(simd_length(totalOffset) > 150_000)   // meters
        for cascadeIndex in 0..<snapPhaseTestCascadeCount {
            #expect(largestMoveWithCarriedPhases[cascadeIndex] < 0.02, "cascade \(cascadeIndex)")
            // Control: the same flight with each shift's phase update left out.
            #expect(meanMoveWithStalePhases[cascadeIndex] > 0.25, "cascade \(cascadeIndex)")
        }
    }
}

// MARK: - Helpers for the snap-phase tests

private let snapPhaseTestLight = simd_normalize(SIMD3<Float>(0.2, 1, 0.3))
private let snapPhaseTestShadowMapResolution = 4096
private let snapPhaseTestCascadeCount = 4
/// Texel sizes in meters, close to what the app's four cascades use.
private let snapPhaseTestTexelSizes: [Float] = [0.05, 0.098, 0.157, 0.389]

/// A camera at `position`, turned by `yaw` about world Y and then by `pitch`
/// about its own X axis (radians). The world matrix is built first because that
/// is what the scene graph stores; the view matrix is its inverse.
private func snapPhaseTestCamera(position: SIMD3<Float>, yaw: Float, pitch: Float)
    -> ShadowCascadeFitting.CameraSnapshot {
    let cameraWorldMatrix = Transform.translationMatrix(position)
                          * Transform.rotationMatrix(radians: yaw, axis: SIMD3<Float>(0, 1, 0))
                          * Transform.rotationMatrix(radians: pitch, axis: SIMD3<Float>(1, 0, 0))
    return ShadowCascadeFitting.CameraSnapshot(viewMatrix: cameraWorldMatrix.inverse,
                                               near: 0.1, far: 1_000_000, fovY: 1.309, aspect: 1.78)
}

private func fitForSnapPhaseTest(camera: ShadowCascadeFitting.CameraSnapshot,
                                 cascadeSnapPhases: [SIMD2<Double>]) -> ShadowCascadeFitting.CascadeFit {
    ShadowCascadeFitting.fitCascades(camera: camera,
                                     lightDirection: snapPhaseTestLight,
                                     shadowMapResolution: snapPhaseTestShadowMapResolution,
                                     cascadeCount: snapPhaseTestCascadeCount,
                                     lambda: 0.5,
                                     shadowMaxDistance: 500,
                                     zPaddingWorldUnits: 100,
                                     cascadeSnapPhases: cascadeSnapPhases)
}

/// Where a world point lands in one of the snap-phase test cascades, in texels.
/// The math, and `subTexelDistance`, are in TestSupport/ShadowTexelSupport.swift,
/// shared with LightObjectSnapPhaseTests.
private func shadowMapTexelCoordinate(of pointWorld: SIMD3<Double>, in cascade: ShadowCamera) -> SIMD2<Double> {
    shadowMapTexelCoordinate(of: pointWorld,
                             viewProjectionMatrix: cascade.viewProjectionMatrix,
                             shadowMapResolution: snapPhaseTestShadowMapResolution)
}
