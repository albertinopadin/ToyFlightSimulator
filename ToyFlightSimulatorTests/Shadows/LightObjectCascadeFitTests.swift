//
//  LightObjectCascadeFitTests.swift
//  ToyFlightSimulatorTests
//
//  LightObject.shadowCameraSnapshot(of:) and fitShadowCascades(to:): the shadow cascade fit
//  with the camera passed in as a value. GameScene.update() calls the pair after the scene
//  traversal. Before, LightObject.update() fitted in the middle of the traversal and read
//  CameraManager.CurrentCamera itself.
//
//  A LightObject and a Camera are GameObjects, so they need a Model and a Metal device:
//  these run app-hosted. No light or camera here is added to LightManager, CameraManager or
//  the running scene, and nothing reads CameraManager.CurrentCamera, so the tests do not
//  depend on what the host app is doing.
//
//  Not covered here: the call in GameScene.update() itself (it reads the live managers),
//  and the snap phases across a floating-origin shift through a fitted light.
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("LightObject: fitting the shadow cascades to a camera snapshot", .tags(.gameObjects))
struct LightObjectCascadeFitTests {

    // Cascade settings given to every sun below through the setters. They differ from
    // LightObject's defaults on purpose, so a fit that ignored a setting would not match.
    private let cascadeCount = 3
    private let cascadeLambda: Float = 0.7
    private let shadowMapResolution = 2048
    private let shadowMaxDistance_m: Float = 300
    private let cascadeZPadding_m: Float = 50

    /// A sun with an explicit direction (so its position plays no part) and the settings above.
    private func makeSun() -> Sun {
        let sun = Sun(modelType: .Sphere)
        sun.setPosition(0, 200, 4)
        sun.setLightDirection([0.2, 1, 0.3])
        sun.setCascadeCount(cascadeCount)
        sun.setCascadeLambda(cascadeLambda)
        sun.setShadowMapResolution(shadowMapResolution)
        sun.setShadowMaxDistance(shadowMaxDistance_m)
        sun.setCascadeZPad(cascadeZPadding_m)
        return sun
    }

    /// A camera snapshot built without a Camera object: at `position`, turned 0.7 rad about
    /// world Y and then -0.15 rad about its own X axis. The world matrix is built first
    /// because that is what the scene graph stores; the view matrix is its inverse.
    private func makeCameraSnapshot(position: float3) -> ShadowCascadeFitting.CameraSnapshot {
        let cameraWorldMatrix = Transform.translationMatrix(position)
                              * Transform.rotationMatrix(radians: 0.7, axis: [0, 1, 0])
                              * Transform.rotationMatrix(radians: -0.15, axis: [1, 0, 0])
        return ShadowCascadeFitting.CameraSnapshot(viewMatrix: cameraWorldMatrix.inverse,
                                                   near: 0.1, far: 1_000_000, fovY: 1.309, aspect: 1.78)
    }

    /// The fit `fitShadowCascades(to:)` should reproduce: the pure function, called with the
    /// same settings and no snap phases (no floating-origin shift has happened).
    private func expectedFit(for sun: Sun,
                             cameraSnapshot: ShadowCascadeFitting.CameraSnapshot) -> ShadowCascadeFitting.CascadeFit {
        ShadowCascadeFitting.fitCascades(camera: cameraSnapshot,
                                         lightDirection: sun.direction,
                                         shadowMapResolution: shadowMapResolution,
                                         cascadeCount: cascadeCount,
                                         lambda: cascadeLambda,
                                         shadowMaxDistance: shadowMaxDistance_m,
                                         zPaddingWorldUnits: cascadeZPadding_m)
    }

    // LightData's C arrays arrive in Swift as four-element tuples; these read them as arrays.
    private func cascadeViewProjectionMatrices(of light: LightObject) -> [float4x4] {
        let matrices = light.lightData.cascadeViewProjectionMatrices
        return [matrices.0, matrices.1, matrices.2, matrices.3]
    }

    private func cascadeSplitDepths(of light: LightObject) -> [Float] {
        let depths = light.lightData.cascadeSplitDepths
        return [depths.0, depths.1, depths.2, depths.3]
    }

    private func cascadeDepthRanges(of light: LightObject) -> [Float] {
        let ranges = light.lightData.cascadeDepthRanges
        return [ranges.0, ranges.1, ranges.2, ranges.3]
    }

    // MARK: - update() no longer fits

    @Test("update() copies type, position and direction into lightData and fits no cascade")
    func updateAloneDoesNotFit() {
        let sun = makeSun()
        sun.update()

        // 0 cascades is the shader's "no shadows" value, and what LightData starts with.
        #expect(sun.lightData.cascadeCount == 0, "update() fitted the cascades; that is GameScene.update()'s job now")
        #expect(sun.lightData.type == Directional)
        #expect(sun.lightData.position == float3(0, 200, 4))
        #expect(sun.lightData.direction == sun.direction)
    }

    // MARK: - fitShadowCascades(to:)

    @Test("fitShadowCascades writes the fit for the given snapshot and the light's settings into lightData")
    func fitWritesTheCascadesIntoLightData() {
        let sun = makeSun()
        let cameraSnapshot = makeCameraSnapshot(position: [640.37, 310.12, -720.59])
        sun.fitShadowCascades(to: cameraSnapshot)

        let expected = expectedFit(for: sun, cameraSnapshot: cameraSnapshot)
        let matrices = cascadeViewProjectionMatrices(of: sun)
        let splitDepths = cascadeSplitDepths(of: sun)
        let depthRanges = cascadeDepthRanges(of: sun)

        #expect(sun.lightData.cascadeCount == UInt32(cascadeCount))
        for cascadeIndex in 0..<cascadeCount {
            #expect(matrices[cascadeIndex] == expected.cascades[cascadeIndex].viewProjectionMatrix,
                    "cascade \(cascadeIndex)")
            #expect(depthRanges[cascadeIndex] == expected.cascades[cascadeIndex].depthRange,
                    "cascade \(cascadeIndex)")
            // The split depths are multiplied by the camera's scale, read off the inverse view
            // matrix. This camera has no scale, so the factor is 1 up to Float rounding.
            let expectedSplitDepth = expected.splitFars[cascadeIndex]
            #expect(abs(splitDepths[cascadeIndex] - expectedSplitDepth) <= 1e-5 * expectedSplitDepth,
                    "cascade \(cascadeIndex)")
        }
        // Split depths grow with the cascade index and end at the shadow distance.
        #expect(splitDepths[0] < splitDepths[1] && splitDepths[1] < splitDepths[2])
        #expect(approxEqual(splitDepths[cascadeCount - 1], shadowMaxDistance_m, tolerance: 1e-2))
    }

    @Test("a point light is not fitted")
    func pointLightIsNotFitted() {
        let pointLight = PointLightObject()
        pointLight.fitShadowCascades(to: makeCameraSnapshot(position: [640.37, 310.12, -720.59]))
        #expect(pointLight.lightData.cascadeCount == 0)
    }

    @Test("the fit depends on the snapshot it is handed and on nothing else")
    func fitFollowsTheSnapshot() {
        let cameraSnapshotAtStart = makeCameraSnapshot(position: [640.37, 310.12, -720.59])
        let cameraSnapshotAfterFlying = makeCameraSnapshot(position: [640.37, 310.12, -470.59])   // 250 m on
        let firstSun = makeSun()
        let secondSun = makeSun()

        firstSun.fitShadowCascades(to: cameraSnapshotAtStart)
        secondSun.fitShadowCascades(to: cameraSnapshotAfterFlying)
        #expect(cascadeViewProjectionMatrices(of: firstSun)[0] != cascadeViewProjectionMatrices(of: secondSun)[0],
                "two cameras 250 m apart got the same cascade")

        // Fitting the second sun to the first snapshot gives the first sun's result exactly:
        // the earlier fit left nothing behind that changes the next one.
        secondSun.fitShadowCascades(to: cameraSnapshotAtStart)
        #expect(cascadeViewProjectionMatrices(of: secondSun) == cascadeViewProjectionMatrices(of: firstSun))
        #expect(cascadeSplitDepths(of: secondSun) == cascadeSplitDepths(of: firstSun))
        #expect(cascadeDepthRanges(of: secondSun) == cascadeDepthRanges(of: firstSun))
    }

    // MARK: - shadowCameraSnapshot(of:)

    @Test("shadowCameraSnapshot copies the camera's view matrix, near, far, vertical FOV in radians and aspect")
    func snapshotCopiesTheCamera() {
        let camera = Camera(name: "TestCamera", cameraType: .Attached, aspectRatio: 1.78,
                            fieldOfView: 75, near: 0.01, far: 1_000_000)
        camera.setPosition(3, 110, -20)

        let cameraSnapshot = LightObject.shadowCameraSnapshot(of: camera)
        #expect(cameraSnapshot.viewMatrix == camera.viewMatrix)
        #expect(cameraSnapshot.near == 0.01)
        #expect(cameraSnapshot.far == 1_000_000)
        #expect(approxEqual(cameraSnapshot.fovY, 75 * Float.pi / 180))     // fieldOfView is stored in degrees
        #expect(approxEqual(cameraSnapshot.aspect, 1.78, tolerance: 1e-4))

        // The aspect is read off the projection matrix, so it follows a window resize.
        camera.setAspectRatio(2.0)
        #expect(approxEqual(LightObject.shadowCameraSnapshot(of: camera).aspect, 2.0, tolerance: 1e-4))
    }

    @Test("a parented camera's snapshot is current only after its parent has updated")
    func snapshotOfParentedCameraIsCurrentAfterTheTraversal() {
        // Why GameScene.update() takes the snapshot after super.update(), and why
        // LightObject.update() must not: a sun that comes before the aircraft in the scene's
        // direct children updates before the aircraft does.
        let scene = Node(name: "scene")
        let aircraft = Node(name: "aircraft")
        let chaseCamera = Camera(name: "ChaseCamera", cameraType: .Attached, aspectRatio: 1.78)
        chaseCamera.setPosition(0, 10, -20)
        aircraft.setPosition(0, 100, 0)
        aircraft.addChild(chaseCamera)
        scene.addChild(aircraft)
        scene.update()

        func cameraWorldPosition(in cameraSnapshot: ShadowCascadeFitting.CameraSnapshot) -> float3 {
            cameraSnapshot.viewMatrix.inverse.columns.3.xyz
        }

        // The next tick moves the aircraft, here by a whole second of flight at 250 m/s.
        aircraft.setPosition(0, 100, 250)

        // Before the aircraft's update() the camera still has the matrix its parent handed it
        // last tick. This is what a fit in the middle of the traversal used to read. (If this
        // expectation ever fails because Node hands a child its parent's matrix on read, a
        // mid-traversal fit would be safe again; the expectation after update() is the one
        // the engine relies on.)
        let snapshotBeforeTheAircraftUpdates = LightObject.shadowCameraSnapshot(of: chaseCamera)
        #expect(approxEqual(cameraWorldPosition(in: snapshotBeforeTheAircraftUpdates), [0, 110, -20], tolerance: 1e-3))

        scene.update()
        let snapshotAfterTheTraversal = LightObject.shadowCameraSnapshot(of: chaseCamera)
        #expect(approxEqual(cameraWorldPosition(in: snapshotAfterTheTraversal), [0, 110, 230], tolerance: 1e-3))
    }
}
