//
//  FloatingOriginTests.swift
//  ToyFlightSimulatorTests
//
//  The two FloatingOrigin functions, run on plain Nodes. No Metal, and none of the
//  live engine state (SceneManager, CameraManager, LightManager) that
//  SceneManager.updateFloatingOrigin reads in the running app: every list is passed in.
//
//  In the applyOffset tests every coordinate is a multiple of 0.25 m, so the Float
//  subtractions are exact and the stored positions can be compared with ==. The tests
//  under "Many shifts" use a fractional coordinate on purpose and say what it may lose.
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

    @Test("the offset is the camera's world position rounded to whole meters")
    func offsetIsCameraWorldPositionInWholeMeters() {
        #expect(FloatingOrigin.getOffset(cameraWorldPosition: [640.37, 310.12, -720.59]) == float3(640, 310, -721))
    }

    @Test("every offset is in whole meters and within half a meter of the camera on each axis")
    func offsetIsWholeAndWithinHalfAMeterOfTheCamera() throws {
        // The last two have components exactly halfway between two whole numbers. The very
        // last one is the worst case: half a meter is left over on all three axes.
        let cameraWorldPositions: [float3] = [[640.37, 310.12, -720.59],
                                              [-999.99, 45.5, 3.49],
                                              [0.2, -1000.5, 0.25],
                                              [1001.5, -0.5, 2.5]]
        for cameraWorldPosition in cameraWorldPositions {
            let offset = try #require(FloatingOrigin.getOffset(cameraWorldPosition: cameraWorldPosition))
            #expect(offset == offset.rounded(.towardZero), "\(offset) has a fractional part")

            // What the shift leaves of the camera's position. Half a meter on each axis is
            // sqrt(3)/2 = 0.866 m in length, so the camera ends within 0.87 m of the origin.
            let cameraPositionAfterShift = cameraWorldPosition - offset
            #expect(simd_reduce_max(simd_abs(cameraPositionAfterShift)) <= 0.5, "camera at \(cameraWorldPosition)")
            #expect(cameraPositionAfterShift.magnitude <= 0.87, "camera at \(cameraWorldPosition)")
        }
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

        // Not exactly zero: the offset is in whole meters, so up to half a meter is left
        // on each axis. Here the camera was at (640.25, 315.5, -720.75), the offset is
        // (640, 316, -721) and the camera ends at (0.25, -0.5, 0.25).
        #expect(offsetForThisTick == float3(640, 316, -721))
        #expect(approxEqual(chaseCamera.getWorldPosition(), [0.25, -0.5, 0.25]))
        #expect(FloatingOrigin.getOffset(cameraWorldPosition: chaseCamera.getWorldPosition()) == nil)
    }

    // MARK: - Many shifts

    /// Camera world position on the tick the outbound shift number `shiftIndex` fires: just
    /// past 1 km from the origin (1,000.77 m at the least), with a different fractional part
    /// from one shift to the next.
    private func outboundCameraWorldPosition(shiftIndex: Int) -> float3 {
        float3(600.37 + 0.61 * Float(shiftIndex % 97),
               12.25 - 0.53 * Float(shiftIndex % 41),
               800.59 + 0.47 * Float(shiftIndex % 89))
    }

    private struct OutAndBackResult {
        /// SceneManager.floatingOriginOffset as it would stand after the 1,000 outbound shifts.
        var floatingOriginOffsetAtTheTurn = double3(repeating: 0)
        /// The same total after the 1,000 return shifts.
        var floatingOriginOffsetAtTheEnd = double3(repeating: 0)
        /// Stored position + total - start, at the turn: how far the wall is from where the
        /// scene put it, in the scene's original frame. Meters, per axis.
        var hangarWallErrorAtTheTurn = double3(repeating: 0)
        var hangarWallStoredPositionAtTheEnd = float3(repeating: 0)
        /// Stored position + total - start, at the end, for the node at a fractional coordinate.
        var settledBodyErrorAtTheEnd = double3(repeating: 0)
        /// Per axis, the largest absolute coordinate the settled body ever stored.
        var farthestSettledBodyCoordinate = float3(repeating: 0)
    }

    private let hangarWallStart = float3(90, 6, 321.5)          // authored: whole and half meters
    private let settledBodyStart = float3(12.34, 0.57, -7.91)   // wherever physics left it

    /// Flies 1,000 shifts away from the scene's starting point and the same 1,000 back (the
    /// return leg replays the outbound camera positions in reverse order with the sign
    /// flipped), and tracks two static nodes. `offsetForCameraAt` turns a camera position
    /// into the offset to subtract: `FloatingOrigin.getOffset`, or a stand-in for the control.
    private func flyOutAndBack(offsetForCameraAt: (float3) -> float3?) throws -> OutAndBackResult {
        let hangarWall = Node(name: "hangarWall")
        let settledBody = Node(name: "settledBody")
        hangarWall.setPosition(hangarWallStart)
        settledBody.setPosition(settledBodyStart)

        var result = OutAndBackResult()
        var floatingOriginOffset = double3(repeating: 0)    // the Double total SceneManager keeps
        for shiftIndex in 0..<2000 {
            let cameraWorldPosition = shiftIndex < 1000
                ? outboundCameraWorldPosition(shiftIndex: shiftIndex)
                : -outboundCameraWorldPosition(shiftIndex: 1999 - shiftIndex)
            let offset = try #require(offsetForCameraAt(cameraWorldPosition), "no shift was due at shift \(shiftIndex)")
            FloatingOrigin.applyOffset(offset,
                                       directChildrenOfScene: [hangarWall, settledBody],
                                       cameras: [],
                                       directionalLights: [])
            floatingOriginOffset += offset.toDouble3()
            result.farthestSettledBodyCoordinate = simd_max(result.farthestSettledBodyCoordinate,
                                                            simd_abs(settledBody.getPosition()))
            if shiftIndex == 999 {
                result.floatingOriginOffsetAtTheTurn = floatingOriginOffset
                result.hangarWallErrorAtTheTurn = hangarWall.getPosition().toDouble3() + floatingOriginOffset
                                                - hangarWallStart.toDouble3()
            }
        }
        result.floatingOriginOffsetAtTheEnd = floatingOriginOffset
        result.hangarWallStoredPositionAtTheEnd = hangarWall.getPosition()
        result.settledBodyErrorAtTheEnd = settledBody.getPosition().toDouble3() + floatingOriginOffset
                                        - settledBodyStart.toDouble3()
        return result
    }

    @Test("1,000 shifts out and back: a whole-meter coordinate comes back exact, a fractional one loses under one float gap")
    func outAndBackWithWholeMeterOffsets() throws {
        let result = try flyOutAndBack { FloatingOrigin.getOffset(cameraWorldPosition: $0) }

        // The flight is real: the turn is about 1,034 km from the start (629 km in x, 821 km in z).
        #expect(simd_length(result.floatingOriginOffsetAtTheTurn) > 1_000_000)

        // Whole numbers add exactly in Double, and the return leg mirrors the outbound one.
        #expect(result.floatingOriginOffsetAtTheEnd == double3(repeating: 0))

        // The wall's coordinates are multiples of 0.5 m, and the float gap is never larger
        // than 0.0625 m on this flight, so no subtraction ever rounds it.
        #expect(result.hangarWallErrorAtTheTurn == double3(repeating: 0))
        #expect(result.hangarWallStoredPositionAtTheEnd == hangarWallStart)

        // The settled body is rounded when a shift carries it into a larger float gap, and at
        // no other time. Each such rounding is at most half the new gap, and the gaps double
        // on the way out, so the total stays under one gap at the farthest point reached
        // (0.5 + 0.25 + 0.125 + ... < 1). On the way back nothing more is lost.
        // Measured in the scratch run: 0.035 m in x and in z, 0.00007 m in y.
        let farthest = result.farthestSettledBodyCoordinate
        #expect(farthest.x.ulp == 0.0625 && farthest.z.ulp == 0.0625, "x and z reach the 524 km to 1,049 km range")
        #expect(abs(result.settledBodyErrorAtTheEnd.x) < Double(farthest.x.ulp))
        #expect(abs(result.settledBodyErrorAtTheEnd.y) < Double(farthest.y.ulp))
        #expect(abs(result.settledBodyErrorAtTheEnd.z) < Double(farthest.z.ulp))
    }

    @Test("control: the same flight with the raw camera position as the offset moves the wall")
    func outAndBackWithRawOffsetsDrifts() throws {
        // What getOffset returned before it rounded: the camera position itself. Only the
        // rounding is left out, so this shows the test above can tell the difference.
        let result = try flyOutAndBack { cameraWorldPosition in cameraWorldPosition }

        // Measured in the scratch run: the wall is 0.20 m off at the turn and 0.018 m off
        // back home (the mirrored return leg cancels part of the error).
        #expect(simd_length(result.hangarWallErrorAtTheTurn) > 0.1)
        #expect(result.hangarWallStoredPositionAtTheEnd != hangarWallStart)
    }
}
