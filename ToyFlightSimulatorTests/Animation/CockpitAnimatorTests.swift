//
//  CockpitAnimatorTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

/// The F-22 cockpit animator on the real asset (Milestone 4 of
/// plans/claude/f22_cockpit_first_person_view_2026-09-25.md). App-hosted: loading a USD model and
/// its skin palette buffers needs the Metal device. Nothing here touches Engine.renderer.
///
/// Every test builds a fresh model instead of using Assets.Models[.F22_Cockpit]: the host app's
/// scene shares that instance, and its player aircraft's animator would fight the test for the pose.
@Suite("F-22 cockpit animator", .tags(.animation))
struct CockpitAnimatorTests {
    static func makeCockpit() -> (model: UsdModel, animator: F22CockpitAnimator) {
        let model = UsdModel("F22_Cockpit", fileExtension: .USDZ, basisTransform: Transform.transformXZYToXYZ)
        return (model, F22CockpitAnimator(model: model))
    }

    /// Longer than any channel's full travel (the slowest, 3 per second, needs 0.67 s for 2
    /// units), so one update lands every channel on its target.
    static let settleTime_s: Float = 1.0

    @Test("the four layers register five channels over the seven moving joints")
    func registersSevenJointConfigs() throws {
        let (model, animator) = Self.makeCockpit()
        let layerSystem = try #require(animator.layerSystem)
        #expect(layerSystem.channelCount == 5)
        for layerID: AnimationLayerID in [.cockpitStick, .cockpitThrottle, .cockpitRudderPedals, .cockpitGearHandle] {
            #expect(layerSystem.layer(layerID.rawValue) != nil, "layer \(layerID.rawValue)")
        }

        // The animator found every channel by its ID.
        let channels = [animator.sideStickRollChannel, animator.sideStickPitchChannel, animator.throttleChannel,
                        animator.rudderPedalsChannel, animator.gearHandleChannel].compactMap { $0 }
        #expect(channels.count == 5)

        // Every rig joint except the root is driven exactly once, and each path is the skeleton's own.
        let drivenJointPaths = channels.flatMap { $0.jointConfigs.map(\.jointPath) }
        #expect(drivenJointPaths.count == 7)
        #expect(Set(drivenJointPaths) == CockpitModelTests.rigJointPaths.subtracting(["CockpitRoot"]))
        let skeleton = try #require(model.skeletons.values.first)
        #expect(Set(drivenJointPaths).isSubset(of: Set(skeleton.jointPaths)))
    }

    // MARK: - Directions, read back from the skin palette the GPU uses

    /// Where the palette of `meshName`'s skin moves a point `offsetNative_m` away from the joint's
    /// pivot, returned as a displacement from the pivot in the cockpit's engine frame (+X right,
    /// +Y up, +Z forward, meters). The palette entry is the joint's world pose × inverse bind,
    /// conjugated into the engine's axes: a rotation about the pivot.
    /// Pivots and offsets are native (Blender: +X right, +Y forward, +Z up), from `bc_controls.py`.
    static func posedOffset(model: UsdModel, meshName: String, jointName: String,
                            pivotNative_m: float3, offsetNative_m: float3) throws -> float3 {
        let mesh = try #require(model.meshes.first { $0.name == meshName }, "mesh \(meshName)")
        let skin = try #require(mesh.skin, "skin of \(meshName)")
        let jointIndex = try #require(skin.jointPaths.firstIndex { $0.split(separator: "/").last == Substring(jointName) },
                                      "joint \(jointName) in \(meshName)'s skin")
        let palette = skin.jointMatrixPaletteBuffer.contents()
            .bindMemory(to: float4x4.self, capacity: skin.jointPaths.count)
        // cockpitNativeToBody with a zero eye point is the import basis alone: (x, y, z) -> (x, z, y).
        let pivot = Aircraft.cockpitNativeToBody(nativePoint: pivotNative_m, eyePointInBodyFrame: .zero)
        let point = Aircraft.cockpitNativeToBody(nativePoint: pivotNative_m + offsetNative_m, eyePointInBodyFrame: .zero)
        let posed = palette[jointIndex] * SIMD4<Float>(point, 1)
        return SIMD3<Float>(posed.x, posed.y, posed.z) - pivot
    }

    // Joint pivots, native, from the joint table in the plan.
    static let stickPivot: float3 = [0.3635, 0.2330, -0.5810]
    static let throttleLeftPivot: float3 = [-0.3951, 0.1190, -0.7710]
    static let throttleRightPivot: float3 = [-0.3579, 0.1190, -0.7710]
    static let gearHandlePivot: float3 = [-0.3605, 0.4140, -0.5621]
    static let pedalLeftHinge: float3 = [-0.160, 0.960, -0.790]
    static let pedalRightHinge: float3 = [0.160, 0.960, -0.790]

    // Expected displacements below reproduced with the scratch script cockpit_m4_directions.swift
    // (the engine's rotateAbout matrix, the import basis, and the pivots above).

    @Test("pulling the stick (+ pitch, the down arrow) tips it aft by 12 degrees")
    func stickPitchPullsAft() throws {
        let (model, animator) = Self.makeCockpit()
        animator.setSideStick(pitch: 1, roll: 0)
        animator.update(deltaTime: Self.settleTime_s)
        // A point 0.15 m up the stick: 0.15·cos 12° up, 0.15·sin 12° aft.
        let stickTop = try Self.posedOffset(model: model, meshName: "Stick", jointName: "StickPitch",
                                            pivotNative_m: Self.stickPivot, offsetNative_m: [0, 0, 0.15])
        #expect(approxEqual(stickTop, [0, 0.14672, -0.03119]))
    }

    @Test("rolling right (+ roll, the right arrow) tips the stick right by 12 degrees")
    func stickRollGoesRight() throws {
        let (model, animator) = Self.makeCockpit()
        animator.setSideStick(pitch: 0, roll: 1)
        animator.update(deltaTime: Self.settleTime_s)
        // The Stick mesh is bound to StickPitch, the child of StickRoll, so it carries the roll.
        let stickTop = try Self.posedOffset(model: model, meshName: "Stick", jointName: "StickPitch",
                                            pivotNative_m: Self.stickPivot, offsetNative_m: [0, 0, 0.15])
        #expect(approxEqual(stickTop, [0.03119, 0.14672, 0]))
    }

    @Test("full throttle puts both grips on the AB detent, 0.06 m forward of the slot centre")
    func fullThrottleReachesAfterburnerDetent() throws {
        let (model, animator) = Self.makeCockpit()
        animator.setThrottles(input: 1)
        animator.update(deltaTime: Self.settleTime_s)
        // A point 0.20 m above the lever's pivot sits at the console top: the printed detents.
        for (meshName, jointName, pivot) in [("Throttle_Left", "ThrottleLeft", Self.throttleLeftPivot),
                                             ("Throttle_Right", "ThrottleRight", Self.throttleRightPivot)] {
            let grip = try Self.posedOffset(model: model, meshName: meshName, jointName: jointName,
                                            pivotNative_m: pivot, offsetNative_m: [0, 0, 0.20])
            #expect(approxEqual(grip, [0, 0.19079, 0.06000]), "\(meshName)")
        }
    }

    @Test("zero throttle puts both grips on the IDLE detent, 0.02 m aft of the slot centre")
    func zeroThrottleSitsAtIdleDetent() throws {
        let (model, animator) = Self.makeCockpit()
        animator.setThrottles(input: 0)
        animator.update(deltaTime: Self.settleTime_s)
        for (meshName, jointName, pivot) in [("Throttle_Left", "ThrottleLeft", Self.throttleLeftPivot),
                                             ("Throttle_Right", "ThrottleRight", Self.throttleRightPivot)] {
            let grip = try Self.posedOffset(model: model, meshName: meshName, jointName: jointName,
                                            pivotNative_m: pivot, offsetNative_m: [0, 0, 0.20])
            #expect(approxEqual(grip, [0, 0.19900, -0.02000]), "\(meshName)")
        }
    }

    @Test("+ yaw (Q, nose left) pushes the left pedal forward and the right pedal aft by 10 degrees")
    func leftYawPushesLeftPedal() throws {
        let (model, animator) = Self.makeCockpit()
        animator.setRudderPedals(input: 1)
        animator.update(deltaTime: Self.settleTime_s)
        // Each pedal hangs from a hinge at its top; a point 0.15 m below the hinge is on the foot.
        let leftFoot = try Self.posedOffset(model: model, meshName: "Pedal_Left", jointName: "PedalLeft",
                                            pivotNative_m: Self.pedalLeftHinge, offsetNative_m: [0, 0, -0.15])
        let rightFoot = try Self.posedOffset(model: model, meshName: "Pedal_Right", jointName: "PedalRight",
                                             pivotNative_m: Self.pedalRightHinge, offsetNative_m: [0, 0, -0.15])
        #expect(approxEqual(leftFoot, [0, -0.14772, 0.02605]))
        #expect(approxEqual(rightFoot, [0, -0.14772, -0.02605]))
    }

    @Test("gear UP swings the knob from 0.030 m below the slot centre to 0.030 m above it")
    func gearHandleUpRaisesTheKnob() throws {
        let (model, animator) = Self.makeCockpit()
        // The knob, on the panel face: 0.10 m aft of the pivot, 0.030 m below the slot centre.
        let knobOffsetNative_m: float3 = [0, -0.10, -0.030]
        let knobAtRest = try Self.posedOffset(model: model, meshName: "GearHandle", jointName: "GearHandle",
                                              pivotNative_m: Self.gearHandlePivot, offsetNative_m: knobOffsetNative_m)
        #expect(approxEqual(knobAtRest, [0, -0.030, -0.10]))

        animator.setGearHandle(gearDown: false)
        animator.update(deltaTime: Self.settleTime_s)
        let knobUp = try Self.posedOffset(model: model, meshName: "GearHandle", jointName: "GearHandle",
                                          pivotNative_m: Self.gearHandlePivot, offsetNative_m: knobOffsetNative_m)
        #expect(approxEqual(knobUp, [0, 0.030, -0.10]))
    }
}
