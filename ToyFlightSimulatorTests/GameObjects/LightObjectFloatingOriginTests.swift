//
//  LightObjectFloatingOriginTests.swift
//  ToyFlightSimulatorTests
//
//  Which lights move with the floating origin (LightObject.shiftsWithFloatingOrigin),
//  and what a shift does to a sun node and to the marker drawn at its position
//  (the sun node itself is never drawn: lights are GameObjectType.none).
//
//  A LightObject is a GameObject, so it needs a Model and a Metal device: these run
//  app-hosted, like the tests that build Sphere() and AttachedCamera(). No light here
//  is added to LightManager or to the running scene, and update() is never called on
//  one, so no cascade fit runs and CameraManager.CurrentCamera is never read.
//

import Testing
import simd
@testable import ToyFlightSimulator

@Suite("LightObject and the floating origin", .tags(.gameObjects))
struct LightObjectFloatingOriginTests {

    private let offset = float3(640, 310, -721)
    private let sunPosition = float3(0, 200, 4)

    /// A sun aimed the old way: its direction is its position, normalized.
    private func makePositionAimedSun() -> Sun {
        let sun = Sun(modelType: .Sphere)
        sun.setPosition(sunPosition)
        return sun
    }

    /// A sun set up the way the three Flightbox scenes do it: position, then an explicit
    /// direction read from that position.
    private func makeExplicitDirectionSun() -> Sun {
        let sun = makePositionAimedSun()
        sun.setLightDirection(sun.getPosition())
        return sun
    }

    // MARK: - The rule

    @Test("a sun aimed by its position does not shift")
    func positionAimedSunDoesNotShift() {
        #expect(!makePositionAimedSun().shiftsWithFloatingOrigin)
    }

    @Test("a sun with an explicit direction shifts")
    func explicitDirectionSunShifts() {
        #expect(makeExplicitDirectionSun().shiftsWithFloatingOrigin)
    }

    @Test("a point light shifts, with or without an explicit direction")
    func pointLightShifts() {
        let pointLight = PointLightObject()
        #expect(pointLight.shiftsWithFloatingOrigin)
        pointLight.setLightDirection([0, 1, 0])
        #expect(pointLight.shiftsWithFloatingOrigin)
    }

    @Test("setLightDirection(getPosition()) leaves the light aimed where it was")
    func explicitDirectionMatchesPositionDerivedDirection() {
        // The scenes' one-line change must not turn the sun before any shift happens.
        #expect(approxEqual(makeExplicitDirectionSun().direction,
                            makePositionAimedSun().direction,
                            tolerance: 1e-6))
    }

    // MARK: - One shift

    @Test("a shift moves an explicit-direction sun with its marker and does not turn it")
    func explicitDirectionSunStaysWithItsMarker() {
        let sun = makeExplicitDirectionSun()
        let sunBall = Node(name: "sunBall")     // the red marker the Flightbox scenes put at the sun
        sunBall.setPosition(sun.getPosition())
        let directionBeforeShift = sun.direction

        FloatingOrigin.applyOffset(offset,
                                   directChildrenOfScene: [sun, sunBall],
                                   cameras: [],
                                   directionalLights: [sun])

        #expect(sun.getPosition() == float3(-640, -110, 725))
        #expect(sun.getPosition() == sunBall.getPosition(), "the sun node and its marker no longer store the same position")
        #expect(sun.direction == directionBeforeShift, "a shift must not turn the sun")
    }

    @Test("a shift leaves a position-aimed sun where it is, so it is not turned either")
    func positionAimedSunKeepsPositionAndDirection() {
        let sun = makePositionAimedSun()
        let directionBeforeShift = sun.direction

        FloatingOrigin.applyOffset(offset,
                                   directChildrenOfScene: [sun],
                                   cameras: [],
                                   directionalLights: [sun])

        #expect(sun.getPosition() == sunPosition)
        #expect(sun.direction == directionBeforeShift)
    }
}
