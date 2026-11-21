//
//  KinematicFloorTests.swift
//  ToyFlightSimulatorTests
//
//  The kinematic floor: an aircraft without flight physics may not take its origin below
//  `kinematicFloorHeightInOriginalFrame`, a height in the scene's original frame. The first
//  suite runs the pure clamp (no Metal). The second builds a bare Aircraft (modelType .None,
//  so it reaches Assets.Models and is app-hosted, as in CockpitCameraTests) and runs its
//  doUpdate, so it fails if the clamp is not called on the kinematic path.
//

import Testing
@testable import ToyFlightSimulator

@Suite("Kinematic floor", .tags(.gameObjects))
struct KinematicFloorTests {

    /// One case: the stored height (current frame), the floor (original frame), the
    /// floating-origin offset y (where the current origin sits in the original frame), and
    /// the height the clamp should return (current frame).
    struct FloorCase: CustomTestStringConvertible, Sendable {
        let heightInCurrentFrame: Float
        let floorHeightInOriginalFrame: Float
        let floatingOriginOffsetY: Double
        let expectedHeightInCurrentFrame: Float

        var testDescription: String {
            "height \(heightInCurrentFrame), floor \(floorHeightInOriginalFrame), offset y \(floatingOriginOffsetY)"
        }
    }

    // Every value is a multiple of 0.5 below 2^24, so every result is exact.
    @Test("the height is raised to the floor, never lowered", arguments: [
        // No shift yet: the two frames agree.
        FloorCase(heightInCurrentFrame: 5, floorHeightInOriginalFrame: 0,
                  floatingOriginOffsetY: 0, expectedHeightInCurrentFrame: 5),
        FloorCase(heightInCurrentFrame: -3, floorHeightInOriginalFrame: 0,
                  floatingOriginOffsetY: 0, expectedHeightInCurrentFrame: 0),
        // Origin 310 m above the original one: the floor is at -310 in the current frame.
        // -305 is 5 m above it (kept); -320 is 10 m below it (raised).
        FloorCase(heightInCurrentFrame: -305, floorHeightInOriginalFrame: 0,
                  floatingOriginOffsetY: 310, expectedHeightInCurrentFrame: -305),
        FloorCase(heightInCurrentFrame: -320, floorHeightInOriginalFrame: 0,
                  floatingOriginOffsetY: 310, expectedHeightInCurrentFrame: -310),
        // A floor that is not 0: 12.5 - 310 = -297.5 in the current frame.
        FloorCase(heightInCurrentFrame: -300, floorHeightInOriginalFrame: 12.5,
                  floatingOriginOffsetY: 310, expectedHeightInCurrentFrame: -297.5),
        FloorCase(heightInCurrentFrame: -290, floorHeightInOriginalFrame: 12.5,
                  floatingOriginOffsetY: 310, expectedHeightInCurrentFrame: -290),
        // Origin 2 km below the original one: a stored -3 is 2,003 m below the floor.
        FloorCase(heightInCurrentFrame: -3, floorHeightInOriginalFrame: 0,
                  floatingOriginOffsetY: -2_000, expectedHeightInCurrentFrame: 2_000),
    ])
    func heightIsRaisedToTheFloor(_ floorCase: FloorCase) {
        let height = Aircraft.heightAtOrAboveKinematicFloor(
            heightInCurrentFrame: floorCase.heightInCurrentFrame,
            floorHeightInOriginalFrame: floorCase.floorHeightInOriginalFrame,
            floatingOriginOffsetY: floorCase.floatingOriginOffsetY)
        #expect(height == floorCase.expectedHeightInCurrentFrame)
    }
}

@Suite("Kinematic floor in Aircraft.doUpdate", .tags(.gameObjects))
struct KinematicFloorUpdateTests {
    // doUpdate reads live engine state: InputManager, GameTime.DeltaTime and
    // SceneManager.floatingOriginOffset, all owned by the host app. The aircraft starts
    // 50 m below the floor so that no input can matter: on the first tick the throttle moves
    // it along its forward vector and A/D along its right vector, both level, and the stick
    // turns it only after that move. The checks are made in the original frame with the
    // offset read here, which is required not to change during the tick.

    @Test("an aircraft below its floor ends the tick on it")
    func aircraftBelowItsFloorEndsOnIt() throws {
        let aircraft = Aircraft(name: "floor test jet", modelType: .None)
        aircraft.kinematicFloorHeightInOriginalFrame = 0
        let offsetYBefore = SceneManager.floatingOriginOffset.y
        aircraft.setPosition(0, Float(-50 - offsetYBefore), 0)  // 50 m below the floor

        aircraft.doUpdate()

        let offsetYAfter = SceneManager.floatingOriginOffset.y
        try #require(offsetYBefore == offsetYAfter, "the host app shifted the origin mid-test")
        #expect(Double(aircraft.getPositionY()) + offsetYAfter == 0)
    }

    @Test("an aircraft with no floor stays below where the floor would be")
    func aircraftWithNoFloorIsNotClamped() {
        let aircraft = Aircraft(name: "no-floor test jet", modelType: .None)
        #expect(aircraft.kinematicFloorHeightInOriginalFrame == nil)
        let offsetY = SceneManager.floatingOriginOffset.y
        aircraft.setPosition(0, Float(-50 - offsetY), 0)

        aircraft.doUpdate()

        #expect(Double(aircraft.getPositionY()) + offsetY < -40)
    }
}
