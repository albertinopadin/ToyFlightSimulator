//
//  FloatingOriginTests.swift
//  ToyFlightSimulatorTests
//
//  The two FloatingOrigin functions, run on plain Nodes. No Metal, and none of the
//  live engine state (SceneManager, CameraManager, LightManager) that
//  SceneManager.updateFloatingOrigin reads in the running app: every list is passed in.
//
//  Every coordinate below is a multiple of 0.25 m, so the Float subtractions are exact
//  and the stored positions can be compared with ==.
//

import Testing
import simd
@testable import ToyFlightSimulator

/// A node that opts out of the shift, the way SkyBox, SkySphere and a position-aimed
/// sun do. Those need Metal to construct; this stands in for them.
private final class NodeThatStaysPut: Node {
    override var shiftsWithFloatingOrigin: Bool { false }
}

@Suite("FloatingOrigin: when to shift, and what a shift moves", .tags(.scenes))
struct FloatingOriginTests {

    /// The offset every applyOffset test subtracts: a camera position 1,012.7 m from the
    /// origin, in whole meters.
    private let offset = float3(640, 310, -721)

    // MARK: - getOffset

    @Test("no shift is due at exactly the threshold distance")
    func noOffsetAtThreshold() {
        // 600² + 800² = 1 000 000, so the length is exactly 1000 m in Float.
        #expect(FloatingOrigin.getOffset(cameraWorldPosition: [600, 0, 800]) == nil)
        #expect(FloatingOrigin.getOffset(cameraWorldPosition: .zero) == nil)
    }

    @Test("a shift is due just past the threshold distance")
    func offsetPastThreshold() {
        #expect(FloatingOrigin.getOffset(cameraWorldPosition: [600, 0, 800.01]) != nil)
    }

    @Test("the threshold distance is a parameter; its default is 1 km")
    func thresholdParameter() {
        #expect(FloatingOrigin.ORIGIN_OFFSET_MAX_DISTANCE == 1_000)
        #expect(FloatingOrigin.getOffset(cameraWorldPosition: [0, 0, 51], thresholdDistance: 50) != nil)
        #expect(FloatingOrigin.getOffset(cameraWorldPosition: [0, 0, 50], thresholdDistance: 50) == nil)
    }

    @Test("the offset is the camera's world position")
    func offsetIsCameraWorldPosition() {
        // Today's rule. Plan step 4 (whole-meter offsets) rounds each component; the
        // expected value here then becomes (640, 310, -721).
        let cameraWorldPosition = float3(640.37, 310.12, -720.59)
        #expect(FloatingOrigin.getOffset(cameraWorldPosition: cameraWorldPosition) == cameraWorldPosition)
    }

    // MARK: - applyOffset

    @Test("direct children of the scene move by the offset; a grandchild follows its parent")
    func directChildrenMoveAndGrandchildFollows() {
        let scene = Node(name: "scene")
        let wall = Node(name: "wall")
        let aircraft = Node(name: "aircraft")
        let pylon = Node(name: "pylon")     // child of the aircraft, so a grandchild of the scene
        wall.setPosition(90, 6, 321.5)
        aircraft.setPosition(640.25, 305.5, -700.75)
        pylon.setPosition(6.5, 0, -1)
        scene.addChild(wall)
        scene.addChild(aircraft)
        aircraft.addChild(pylon)
        scene.update()
        let pylonRelativeToWallBeforeShift = pylon.getWorldPosition() - wall.getWorldPosition()

        FloatingOrigin.applyOffset(offset,
                                   directChildrenOfScene: scene.children,
                                   cameras: [],
                                   directionalLights: [])

        #expect(wall.getPosition() == float3(-550, -304, 1042.5))
        #expect(aircraft.getPosition() == float3(0.25, -4.5, 20.25))
        #expect(pylon.getPosition() == float3(6.5, 0, -1), "a grandchild's stored (local) position must not change")

        // The grandchild's world position is only right if the shift marked the aircraft
        // dirty, so that the next update hands the pylon its parent's new matrix.
        scene.update()
        #expect(approxEqual(pylon.getWorldPosition(), [6.75, -4.5, 19.25]))
        #expect(approxEqual(pylon.getWorldPosition() - wall.getWorldPosition(), pylonRelativeToWallBeforeShift),
                "a shift must not change where two objects are relative to each other")
    }

    @Test("a node whose shiftsWithFloatingOrigin is false keeps its stored position")
    func optedOutNodeStaysPut() {
        let sky = NodeThatStaysPut(name: "sky")
        let wall = Node(name: "wall")
        sky.setPosition(0, 100, 4)
        wall.setPosition(90, 6, 321.5)

        FloatingOrigin.applyOffset(offset,
                                   directChildrenOfScene: [sky, wall],
                                   cameras: [],
                                   directionalLights: [])

        #expect(sky.getPosition() == float3(0, 100, 4))
        #expect(wall.getPosition() == float3(-550, -304, 1042.5))
    }

    @Test("a plain Node shifts by default")
    func plainNodeShiftsByDefault() {
        #expect(Node(name: "plain").shiftsWithFloatingOrigin)
    }

    @Test("an unparented camera moves by the offset; a camera parented to the aircraft keeps its local position")
    func camerasUnparentedAndParented() {
        let scene = Node(name: "scene")
        let aircraft = Node(name: "aircraft")
        let chaseCamera = Node(name: "chaseCamera")     // parented, like AttachedCamera
        let debugCamera = Node(name: "debugCamera")     // unparented, like DebugCamera
        aircraft.setPosition(640.25, 305.5, -700.75)
        chaseCamera.setPosition(0, 10, -20)
        debugCamera.setPosition(0, 5, -40)
        scene.addChild(aircraft)
        aircraft.addChild(chaseCamera)

        FloatingOrigin.applyOffset(offset,
                                   directChildrenOfScene: scene.children,
                                   cameras: [chaseCamera, debugCamera],
                                   directionalLights: [])

        #expect(debugCamera.getPosition() == float3(-640, -305, 681))
        #expect(chaseCamera.getPosition() == float3(0, 10, -20))
        scene.update()
        #expect(approxEqual(chaseCamera.getWorldPosition(), [0.25, 5.5, 0.25]))
    }

    @Test("a camera that is a direct child of the scene moves once, not twice")
    func cameraUnderSceneMovesOnce() {
        // It is in both lists. The first loop moves it; the camera loop must skip it,
        // because its parent (the scene) is not nil.
        let scene = Node(name: "scene")
        let fixedCamera = Node(name: "fixedCamera")
        fixedCamera.setPosition(0, 5, -40)
        scene.addChild(fixedCamera)

        FloatingOrigin.applyOffset(offset,
                                   directChildrenOfScene: scene.children,
                                   cameras: [fixedCamera],
                                   directionalLights: [])

        #expect(fixedCamera.getPosition() == float3(-640, -305, 681))
    }

    // MARK: - getOffset and applyOffset together

    @Test("after the shift the camera is back near the origin and no further shift is due")
    func noSecondShiftAfterApplying() throws {
        // One tick of SceneManager.updateFloatingOrigin, with a chase camera 20 m behind
        // an aircraft that has flown past 1 km.
        let scene = Node(name: "scene")
        let aircraft = Node(name: "aircraft")
        let chaseCamera = Node(name: "chaseCamera")
        aircraft.setPosition(640.25, 305.5, -700.75)
        chaseCamera.setPosition(0, 10, -20)
        scene.addChild(aircraft)
        aircraft.addChild(chaseCamera)
        scene.update()

        let offsetForThisTick = try #require(FloatingOrigin.getOffset(cameraWorldPosition: chaseCamera.getWorldPosition()))
        FloatingOrigin.applyOffset(offsetForThisTick,
                                   directChildrenOfScene: scene.children,
                                   cameras: [chaseCamera],
                                   directionalLights: [])
        scene.update()

        // Within 1 m, not exactly zero, so this also holds once the offset is rounded
        // to whole meters (plan step 4).
        #expect(chaseCamera.getWorldPosition().magnitude < 1)
        #expect(FloatingOrigin.getOffset(cameraWorldPosition: chaseCamera.getWorldPosition()) == nil)
    }
}
