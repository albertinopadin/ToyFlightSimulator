//
//  FloatingOrigin.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 11/20/26.
//

/// The floating origin keeps stored positions small by moving the world instead of the viewer:
/// when the camera is far from the origin, the same offset is subtracted from everything that
/// stores a position, so the camera ends near (0, 0, 0) again.
///
/// The two functions here are the part of that with no engine state: one decides whether a shift
/// is due, the other applies it to the objects it is handed. `SceneManager.updateFloatingOrigin`
/// supplies the live scene, cameras and lights, and owns the running total
/// (`SceneManager.floatingOriginOffset`). A test can call both with plain `Node`s.
enum FloatingOrigin {
    /// Distance of the camera from the origin, in meters, beyond which a shift is due.
    static let ORIGIN_OFFSET_MAX_DISTANCE: Float = 1_000  // 1 km

    /// The offset to subtract from every stored position, or nil when no shift is due.
    /// A shift is due when the camera is farther than `thresholdDistance` (meters) from the
    /// origin; a camera exactly at the threshold does not shift. The offset is the camera's
    /// world position, so the shift puts the camera back at the origin.
    static func getOffset(cameraWorldPosition: float3, thresholdDistance: Float = ORIGIN_OFFSET_MAX_DISTANCE) -> float3? {
        guard cameraWorldPosition.magnitude > thresholdDistance else { return nil }
        return cameraWorldPosition
    }

    /// Subtracts `offset` from everything that stores a position in the current frame, so all
    /// of it moves together. Update thread only. The caller adds the same `offset` to
    /// `SceneManager.floatingOriginOffset`.
    ///
    /// - Parameters:
    ///   - offset: meters, in the current frame; the value `getOffset` returned.
    ///   - directChildrenOfScene: the scene's direct children. Deeper nodes follow their parent.
    ///     A node whose `shiftsWithFloatingOrigin` is false is skipped.
    ///   - cameras: every registered camera. Only the unparented ones are moved here.
    ///   - directionalLights: the lights whose shadow cascades must follow the shift.
    static func applyOffset(_ offset: float3,
                            directChildrenOfScene: [Node],
                            cameras: [Node],
                            directionalLights: [LightObject]) {
        // setPosition (not a direct write) so each node's dirty flags reach its children.
        for node in directChildrenOfScene where node.shiftsWithFloatingOrigin {
            node.setPosition(node.getPosition() - offset)
        }

        // Unparented cameras (DebugCamera) hold a world position but are
        // not in the scene's children, so the loop above misses them.
        // A parented camera stores a position relative to its parent and follows it.
        for camera in cameras where camera.parent == nil {
            camera.setPosition(camera.getPosition() - offset)
        }

        // The texel grid of each shadow cascade is a position in the world too; without this
        // every static shadow edge jumps by up to half a texel on the shift.
        for light in directionalLights {
            light.shiftShadowSnapPhases(by: offset)
        }
    }
}
