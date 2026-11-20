//
//  LightObjectSnapPhaseTests.swift
//  ToyFlightSimulatorTests
//
//  The shadow snap phase across a floating-origin shift, through the real objects: a Sun
//  fitted with fitShadowCascades(to:), a Camera read with shadowCameraSnapshot(of:), and
//  the phase update reached through shiftShadowSnapPhases(by:) or FloatingOrigin.applyOffset.
//  ShadowCascadeFittingTests checks the same property on the pure functions; these tests
//  check that LightObject stores and carries the phases, and that one applyOffset call
//  gives the nodes, the camera and the light the same offset.
//
//  What is measured: a static object's shadow edge stays still only while the object keeps
//  the same position inside a shadow-map texel. A shift subtracts an offset that is not a
//  whole number of texels, so a grid that stayed tied to the origin would land somewhere
//  else under the object. Each test reads where one static point lands in every cascade
//  before and after (shadowMapTexelCoordinate) and compares the two after removing whole
//  texels (subTexelDistance: 0 = same place inside a texel, 0.5 = as far apart as possible).
//
//  A Sun and a Camera are GameObjects, so these run app-hosted. Nothing here is added to
//  LightManager, CameraManager or the running scene, and nothing reads
//  CameraManager.CurrentCamera.
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("LightObject: the shadow snap phase across a floating-origin shift", .tags(.gameObjects))
struct LightObjectSnapPhaseTests {

    // Shared with ShadowCascadeFittingTests.oneShiftKeepsSubTexelPosition, which tests the
    // pure functions: camera position, lens, light direction, static point, offset and
    // cascade settings.
    private let cameraPositionBeforeShift = float3(640.37, 310.12, -720.59)    // 1,012.7 m from the origin
    private let staticPointBeforeShift = float3(652, 0, -695)                  // on the ground ahead of the camera
    /// What FloatingOrigin.getOffset returns for that camera position.
    private let shiftOffset = float3(640, 310, -721)

    // Cascade settings, given to every sun through the setters. They are LightObject's
    // defaults today; setting them here keeps the texel sizes, and with them the controls
    // and the measured values below, the same if a default is tuned later. The resolution
    // is also what the texel helper is handed.
    private let cascadeCount = 4
    private let shadowMapResolution = 4096
    private let cascadeLambda: Float = 0.5
    private let shadowMaxDistance_m: Float = 500
    private let cascadeZPadding_m: Float = 100

    private func makeSun() -> Sun {
        let sun = Sun(modelType: .Sphere)
        sun.setPosition(0, 200, 4)
        sun.setLightDirection([0.2, 1, 0.3])     // explicit, so the sun node may shift like any node
        sun.setCascadeCount(cascadeCount)
        sun.setShadowMapResolution(shadowMapResolution)
        sun.setCascadeLambda(cascadeLambda)
        sun.setShadowMaxDistance(shadowMaxDistance_m)
        sun.setCascadeZPad(cascadeZPadding_m)
        return sun
    }

    /// An unparented camera (like DebugCamera) at `cameraPositionBeforeShift`, turned away
    /// from the world axes (no expectation depends on the exact turn). The lens is that of
    /// the pure test's camera (its 1.309 rad field of view is 75 degrees). The texel sizes
    /// follow from the lens and the cascade settings, and the controls below depend on
    /// them: measure every cascade again before changing any of these values.
    private func makeCamera() -> Camera {
        let camera = Camera(name: "TestCamera", cameraType: .Debug, aspectRatio: 1.78,
                            fieldOfView: 75, near: 0.1, far: 1_000_000)
        camera.setPosition(cameraPositionBeforeShift)
        camera.rotateY(0.7)
        camera.rotateX(-0.15)
        return camera
    }

    /// Where `pointWorld` lands in each of the sun's cascades, in texels, with the matrices
    /// the sun's last fit wrote into lightData (the ones the renderer would draw with).
    private func texelCoordinates(of pointWorld: float3, in sun: LightObject) -> [SIMD2<Double>] {
        cascadeViewProjectionMatrices(of: sun).prefix(cascadeCount).map { viewProjectionMatrix in
            shadowMapTexelCoordinate(of: pointWorld.toDouble3(),
                                     viewProjectionMatrix: viewProjectionMatrix,
                                     shadowMapResolution: shadowMapResolution)
        }
    }

    /// Per cascade: how far the point moved inside its texel between two fits (0 ... 0.5).
    private func subTexelMoves(from texelsBefore: [SIMD2<Double>], to texelsAfter: [SIMD2<Double>]) -> [Double] {
        zip(texelsBefore, texelsAfter).map { subTexelDistance($0, $1) }
    }

    // MARK: - The light alone

    @Test("one shift: a sun whose phases are shifted keeps a static point on the same sub-texel position")
    func shiftedPhasesKeepSubTexelPosition() {
        let camera = makeCamera()
        let sunWithPhaseShift = makeSun()
        let sunWithoutPhaseShift = makeSun()     // the control: everything but the phase update

        let cameraSnapshotBeforeShift = LightObject.shadowCameraSnapshot(of: camera)
        sunWithPhaseShift.fitShadowCascades(to: cameraSnapshotBeforeShift)
        sunWithoutPhaseShift.fitShadowCascades(to: cameraSnapshotBeforeShift)
        let texelsBeforeShift = texelCoordinates(of: staticPointBeforeShift, in: sunWithPhaseShift)
        #expect(texelCoordinates(of: staticPointBeforeShift, in: sunWithoutPhaseShift) == texelsBeforeShift,
                "two suns with the same settings and the same camera did not get the same fit")

        // The shift, done by hand: the same offset comes off the camera, the point and the phases.
        sunWithPhaseShift.shiftShadowSnapPhases(by: shiftOffset)
        camera.setPosition(cameraPositionBeforeShift - shiftOffset)
        let staticPointAfterShift = staticPointBeforeShift - shiftOffset

        let cameraSnapshotAfterShift = LightObject.shadowCameraSnapshot(of: camera)
        sunWithPhaseShift.fitShadowCascades(to: cameraSnapshotAfterShift)
        sunWithoutPhaseShift.fitShadowCascades(to: cameraSnapshotAfterShift)

        let movesWithPhaseShift = subTexelMoves(from: texelsBeforeShift,
                                                to: texelCoordinates(of: staticPointAfterShift, in: sunWithPhaseShift))
        let movesWithoutPhaseShift = subTexelMoves(from: texelsBeforeShift,
                                                   to: texelCoordinates(of: staticPointAfterShift, in: sunWithoutPhaseShift))
        // Measured in this suite: with the phase update the point moves at most 0.0009 texel;
        // without it, 0.14 to 0.46 texel depending on the cascade.
        for cascadeIndex in 0..<cascadeCount {
            #expect(movesWithPhaseShift[cascadeIndex] < 0.02, "cascade \(cascadeIndex)")
            // Control: this offset is not a whole number of texels in any cascade, so the
            // expectation above is not passing for free.
            #expect(movesWithoutPhaseShift[cascadeIndex] > 0.05, "cascade \(cascadeIndex)")
        }
    }

    @Test("a phase shift before the first fit changes nothing")
    func shiftBeforeAnyFitChangesNothing() {
        // Before the first fit there is no grid to keep in place: the phases are empty,
        // which fitCascades reads as a grid through the current origin. This pins that
        // behaviour. It does not test the guard in shiftShadowSnapPhases on its own: with
        // no texel sizes recorded, the phase function returns an empty list anyway.
        let cameraSnapshot = LightObject.shadowCameraSnapshot(of: makeCamera())
        let sunShiftedBeforeFit = makeSun()
        let freshSun = makeSun()

        sunShiftedBeforeFit.shiftShadowSnapPhases(by: shiftOffset)
        sunShiftedBeforeFit.fitShadowCascades(to: cameraSnapshot)
        freshSun.fitShadowCascades(to: cameraSnapshot)

        #expect(cascadeViewProjectionMatrices(of: sunShiftedBeforeFit) == cascadeViewProjectionMatrices(of: freshSun))
    }

    @Test("two shifts in a row: the second phase update builds on the first")
    func twoShiftsCarryThePhasesForward() throws {
        // LightObject's own bookkeeping: shiftShadowSnapPhases must start from the phases
        // the previous shift left, not from zero. The control sun skips the first phase
        // update and does the second, which is what starting from zero would amount to.
        let camera = makeCamera()
        let sunCarryingBothShifts = makeSun()
        let sunMissingFirstShift = makeSun()

        let firstCameraSnapshot = LightObject.shadowCameraSnapshot(of: camera)
        sunCarryingBothShifts.fitShadowCascades(to: firstCameraSnapshot)
        sunMissingFirstShift.fitShadowCascades(to: firstCameraSnapshot)
        let texelsBeforeAnyShift = texelCoordinates(of: staticPointBeforeShift, in: sunCarryingBothShifts)

        // First shift.
        sunCarryingBothShifts.shiftShadowSnapPhases(by: shiftOffset)
        camera.setPosition(camera.getPosition() - shiftOffset)
        var staticPoint = staticPointBeforeShift - shiftOffset

        // The camera flies on to a place just past 1 km from the new origin, in another
        // direction, and the engine fits on every tick on the way; one fit stands for those.
        camera.setPosition(-551.21, 204.66, 812.48)      // 1,002.9 m from the origin
        let cameraSnapshotBeforeSecondShift = LightObject.shadowCameraSnapshot(of: camera)
        sunCarryingBothShifts.fitShadowCascades(to: cameraSnapshotBeforeSecondShift)
        sunMissingFirstShift.fitShadowCascades(to: cameraSnapshotBeforeSecondShift)

        // Second shift.
        let secondShiftOffset = try #require(FloatingOrigin.getOffset(cameraWorldPosition: camera.getWorldPosition()))
        #expect(secondShiftOffset == float3(-551, 205, 812))
        sunCarryingBothShifts.shiftShadowSnapPhases(by: secondShiftOffset)
        sunMissingFirstShift.shiftShadowSnapPhases(by: secondShiftOffset)
        camera.setPosition(camera.getPosition() - secondShiftOffset)
        staticPoint -= secondShiftOffset

        let cameraSnapshotAfterSecondShift = LightObject.shadowCameraSnapshot(of: camera)
        sunCarryingBothShifts.fitShadowCascades(to: cameraSnapshotAfterSecondShift)
        sunMissingFirstShift.fitShadowCascades(to: cameraSnapshotAfterSecondShift)

        // Against the very first fit: two shifts and 1 km of camera travel later, the point
        // is still on the same place inside its texel.
        let movesCarryingBothShifts = subTexelMoves(from: texelsBeforeAnyShift,
                                                    to: texelCoordinates(of: staticPoint, in: sunCarryingBothShifts))
        let movesMissingFirstShift = subTexelMoves(from: texelsBeforeAnyShift,
                                                   to: texelCoordinates(of: staticPoint, in: sunMissingFirstShift))
        // Measured in this suite: carrying both, at most 0.0011 texel; missing the first,
        // 0.14 to 0.46 texel (the first shift's phase, which that sun never stored).
        for cascadeIndex in 0..<cascadeCount {
            #expect(movesCarryingBothShifts[cascadeIndex] < 0.02, "cascade \(cascadeIndex)")
            #expect(movesMissingFirstShift[cascadeIndex] > 0.05, "cascade \(cascadeIndex)")
        }
    }

    // MARK: - Through FloatingOrigin.applyOffset

    /// One tick of SceneManager.updateFloatingOrigin with the test's own lists: fit, take the
    /// offset from the camera, apply it, fit again. Returns, per cascade, how far the static
    /// point moved inside its texel. With `sunIsInTheLightList` false the nodes and the
    /// camera still get the offset and the sun's phases do not.
    private func subTexelMovesOverOneAppliedShift(sunIsInTheLightList: Bool) throws -> [Double] {
        let camera = makeCamera()
        let sun = makeSun()
        let staticPoint = Node(name: "staticPoint")
        staticPoint.setPosition(staticPointBeforeShift)

        sun.fitShadowCascades(to: LightObject.shadowCameraSnapshot(of: camera))
        let texelsBeforeShift = texelCoordinates(of: staticPoint.getPosition(), in: sun)

        let offset = try #require(FloatingOrigin.getOffset(cameraWorldPosition: camera.getWorldPosition()))
        #expect(offset == shiftOffset)
        FloatingOrigin.applyOffset(offset,
                                   directChildrenOfScene: [staticPoint, sun],    // a scene's addLight adds the sun as a child
                                   cameras: [camera],
                                   directionalLights: sunIsInTheLightList ? [sun] : [])

        // All three position holders moved by the offset.
        #expect(staticPoint.getPosition() == float3(12, -310, 26))
        #expect(sun.getPosition() == float3(-640, -110, 725))
        #expect(approxEqual(camera.getPosition(), cameraPositionBeforeShift - shiftOffset))

        sun.fitShadowCascades(to: LightObject.shadowCameraSnapshot(of: camera))
        return subTexelMoves(from: texelsBeforeShift,
                             to: texelCoordinates(of: staticPoint.getPosition(), in: sun))
    }

    @Test("applyOffset gives the nodes, the camera and the sun's snap phases the same offset")
    func applyOffsetKeepsSubTexelPosition() throws {
        // Measured in this suite: at most 0.0009 texel, the same as the shift done by hand above.
        let moves = try subTexelMovesOverOneAppliedShift(sunIsInTheLightList: true)
        for cascadeIndex in 0..<cascadeCount {
            #expect(moves[cascadeIndex] < 0.02, "cascade \(cascadeIndex)")
        }
    }

    @Test("control: when the sun's phases are left out of the shift, the static point moves inside its texel")
    func applyOffsetWithoutTheLightMovesThePoint() throws {
        // What the test above guards against: the nodes shifted by one offset and the
        // light's texel grid by another (here, by none). Measured in this suite: 0.14 to
        // 0.46 texel depending on the cascade.
        let moves = try subTexelMovesOverOneAppliedShift(sunIsInTheLightList: false)
        for cascadeIndex in 0..<cascadeCount {
            #expect(moves[cascadeIndex] > 0.05, "cascade \(cascadeIndex)")
        }
    }
}
