//
//  CockpitCameraTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import Foundation
import simd
@testable import ToyFlightSimulator

/// Head-look math of the first-person camera (Milestone 2 of
/// plans/claude/f22_cockpit_first_person_view_2026-09-25.md). The static helpers are pure,
/// so no camera is built. Numbers reproduced with the scratch script `cockpit_test_numbers.swift`.
@Suite("CockpitCamera head look", .tags(.math))
struct CockpitCameraHeadLookTests {
    /// One 60 Hz tick of a hard mouse drag: 50 px × 1/60 s × turnSpeed 1 = 0.83 rad.
    private let hardDragPerTick: Float = 50.0 / 60.0

    @Test("10 s of hard mouse look stops at the head limits")
    func headAnglesClamp() {
        var head: (yaw: Float, pitch: Float) = (0, 0)
        for _ in 0..<600 {
            head = CockpitCamera.turnedHead(yaw: head.yaw, pitch: head.pitch,
                                            yawDelta: hardDragPerTick, pitchDelta: hardDragPerTick)
        }
        #expect(head.yaw == CockpitCamera.maxHeadYaw)
        #expect(approxEqual(head.yaw, Float(150).toRadians))
        #expect(head.pitch == CockpitCamera.maxHeadPitchUp)
        #expect(approxEqual(head.pitch, Float(70).toRadians))

        for _ in 0..<600 {
            head = CockpitCamera.turnedHead(yaw: head.yaw, pitch: head.pitch,
                                            yawDelta: -hardDragPerTick, pitchDelta: -hardDragPerTick)
        }
        #expect(head.yaw == -CockpitCamera.maxHeadYaw)
        #expect(head.pitch == -CockpitCamera.maxHeadPitchDown)
        #expect(approxEqual(head.pitch, Float(-80).toRadians))
    }

    @Test("a turn inside the limits is not clamped")
    func smallTurnPassesThrough() {
        let head = CockpitCamera.turnedHead(yaw: 0.1, pitch: -0.2, yawDelta: 0.3, pitchDelta: 0.5)
        #expect(approxEqual(head.yaw, 0.4))
        #expect(approxEqual(head.pitch, 0.3))
    }

    @Test("positive yaw looks right, positive pitch looks up")
    func headRotationDirections() {
        let forward: float3 = [0, 0, 1]  // +Z is the nose in the engine's left-handed axes
        let lookRight = CockpitCamera.headRotation(yaw: Float(90).toRadians, pitch: 0).act(forward)
        #expect(approxEqual(lookRight, [1, 0, 0]))
        let lookUp = CockpitCamera.headRotation(yaw: 0, pitch: Float(30).toRadians).act(forward)
        #expect(approxEqual(lookUp, [0, 0.5, 0.8660254]))
    }

    @Test("yaw then pitch never rolls the head")
    func combinedTurnKeepsTheHorizonLevel() {
        let headRotation = CockpitCamera.headRotation(yaw: Float(90).toRadians, pitch: Float(30).toRadians)
        // Looking right and 30° up...
        #expect(approxEqual(headRotation.act([0, 0, 1]), [0.8660254, 0.5, 0]))
        // ...with the head's right axis still level. Pitching first, then yawing about the
        // body's up axis would tilt it (the view would roll).
        #expect(approxEqual(headRotation.act([1, 0, 0]).y, 0))
    }

    @Test("zero head angles are the identity rotation")
    func centredHeadIsIdentity() {
        let rotation = float4x4(CockpitCamera.headRotation(yaw: 0, pitch: 0))
        #expect(approxEqual(rotation, matrix_identity_float4x4))
    }
}

/// App-hosted: building a camera or an aircraft reaches Assets.Models[.None], which needs the
/// Metal device. The aircraft here are bare `Aircraft` nodes with the empty model standing in
/// for the cockpit (attach only needs the node). Nothing touches CameraManager, so the running
/// scene's camera is left alone.
@Suite("CockpitCamera attach and head state", .tags(.gameObjects))
struct CockpitCameraAttachTests {
    private func makeAircraft(cockpitEyePoint: float3?) -> Aircraft {
        let aircraft = Aircraft(name: "test jet", modelType: .None)
        if let cockpitEyePoint {
            aircraft.attachCockpit(named: "test cockpit", modelType: .None, eyePointInBodyFrame: cockpitEyePoint)
        }
        return aircraft
    }

    @Test("head look rotates the camera but never moves it off the eye point")
    func positionNeverMoves() {
        let camera = CockpitCamera()
        for step in 0..<200 {
            camera.turnHead(yawDelta: sin(Float(step)) * 0.3, pitchDelta: cos(Float(step) * 0.7) * 0.2)
            #expect(camera.getPosition() == .zero)
        }
        let expectedRotation = float4x4(CockpitCamera.headRotation(yaw: camera.headYaw, pitch: camera.headPitch))
        #expect(approxEqual(camera.getRotationMatrix(), expectedRotation))

        camera.recenterHead()
        #expect(camera.headYaw == 0)
        #expect(camera.headPitch == 0)
        #expect(approxEqual(camera.getRotationMatrix(), matrix_identity_float4x4))
        #expect(camera.getPosition() == .zero)
    }

    @Test("attach parents the camera to the cockpit node at zero offset and recentres the head")
    func attachParentsToTheCockpit() throws {
        let aircraft = makeAircraft(cockpitEyePoint: [0, 1.12, 7.00])
        let camera = CockpitCamera()
        camera.turnHead(yawDelta: 1, pitchDelta: 0.5)

        #expect(camera.attach(to: aircraft))
        let cockpit = try #require(aircraft.cockpit)
        #expect(camera.parent === cockpit)
        #expect(aircraft.cockpitCamera === camera)
        #expect(camera.getPosition() == .zero)
        #expect(cockpit.getPosition() == [0, 1.12, 7.00])
        #expect(camera.headYaw == 0)
        #expect(camera.headPitch == 0)
    }

    @Test("re-attaching moves the camera out of the old cockpit into the new one")
    func reattachMovesToTheNewCockpit() throws {
        let oldJet = makeAircraft(cockpitEyePoint: [0, 1.12, 7.00])
        let newJet = makeAircraft(cockpitEyePoint: [0, 1.08, 5.50])
        let camera = CockpitCamera()
        camera.attach(to: oldJet)
        camera.attach(to: newJet)

        let oldCockpit = try #require(oldJet.cockpit)
        let newCockpit = try #require(newJet.cockpit)
        #expect(camera.parent === newCockpit)
        #expect(!oldCockpit.children.contains { $0 === camera })
        #expect(newCockpit.children.filter { $0 === camera }.count == 1)
    }

    @Test("an aircraft without a cockpit leaves the camera unparented")
    func attachWithoutACockpitDetaches() throws {
        let jetWithCockpit = makeAircraft(cockpitEyePoint: [0, 1.12, 7.00])
        let jetWithoutCockpit = makeAircraft(cockpitEyePoint: nil)
        let camera = CockpitCamera()
        camera.attach(to: jetWithCockpit)

        #expect(!camera.attach(to: jetWithoutCockpit))
        #expect(camera.parent == nil)
        #expect(jetWithoutCockpit.cockpitCamera == nil)
        let oldCockpit = try #require(jetWithCockpit.cockpit)
        #expect(!oldCockpit.children.contains { $0 === camera })
    }
}
