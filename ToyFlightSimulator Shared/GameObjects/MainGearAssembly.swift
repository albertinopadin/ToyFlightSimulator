//
//  MainGearAssembly.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/20/24.
//

import simd

/// Represents a main (wing) landing gear assembly with hierarchical animation
final class MainGearAssembly {
    enum Side {
        case left
        case right
    }

    let side: Side

    // Main strut that rotates forward/inward to retract
    let strut: SubMeshGameObject

    // Wheel attached to the bottom of the strut
    let wheel: SubMeshGameObject

    // Gear door that opens/closes during deployment
    let door: SubMeshGameObject

    // Rotation axis for the main strut (rotates forward and inward)
    var strutRotationAxis: float3 {
        // Main gear rotates inward (toward fuselage) and forward
        switch side {
        case .left:
            return float3(0.2, 0, 1)  // Rotate inward-forward
        case .right:
            return float3(-0.2, 0, 1)  // Rotate inward-forward (mirrored)
        }
    }

    // Rotation axis for door (rotates down/outward to open)
    var doorRotationAxis: float3 {
        switch side {
        case .left:
            return float3(0, 0, 1)
        case .right:
            return float3(0, 0, -1)
        }
    }

    // Pivot points (relative to each mesh's center)
    // These may need tuning based on actual mesh geometry
    let strutPivot = float3(0, 0, 0.5)
    let doorPivot = float3(0, 0, 0.3)

    init(side: Side) {
        self.side = side

        // Create SubMeshGameObjects for each part based on side
        switch side {
        case .left:
            strut = SubMeshGameObject(
                name: "MainGearL_Strut",
                modelType: .F18_MainGearL_Strut,
                meshType: .F18_MainGearL_Strut
            )

            wheel = SubMeshGameObject(
                name: "MainGearL_Wheel",
                modelType: .F18_MainGearL_Wheel,
                meshType: .F18_MainGearL_Wheel
            )

            door = SubMeshGameObject(
                name: "MainGearL_Door",
                modelType: .F18_MainGearL_Door,
                meshType: .F18_MainGearL_Door
            )

        case .right:
            strut = SubMeshGameObject(
                name: "MainGearR_Strut",
                modelType: .F18_MainGearR_Strut,
                meshType: .F18_MainGearR_Strut
            )

            wheel = SubMeshGameObject(
                name: "MainGearR_Wheel",
                modelType: .F18_MainGearR_Wheel,
                meshType: .F18_MainGearR_Wheel
            )

            door = SubMeshGameObject(
                name: "MainGearR_Door",
                modelType: .F18_MainGearR_Door,
                meshType: .F18_MainGearR_Door
            )
        }

        setupPivotPoints()
    }

    private func setupPivotPoints() {
        // Set pivot points for rotation
        strut.setSubmeshOrigin(strutPivot)
        door.setSubmeshOrigin(doorPivot)
    }

    /// Attach the gear assembly to the parent aircraft
    func attachTo(aircraft: Node) {
        // Position strut relative to aircraft
        let strutMetadata = strut.getSubmeshVertexMetadata()
        let strutPosition = strutMetadata.initialPositionInParentMesh - strutPivot
        strut.setPosition(strutPosition)
        aircraft.addChild(strut)

        // Position wheel as child of strut (moves with strut)
        let wheelMetadata = wheel.getSubmeshVertexMetadata()
        let wheelRelativeToStrut = wheelMetadata.initialPositionInParentMesh - strutMetadata.initialPositionInParentMesh
        wheel.setPosition(wheelRelativeToStrut)
        strut.addChild(wheel)

        // Position door relative to aircraft
        let doorMetadata = door.getSubmeshVertexMetadata()
        let doorPosition = doorMetadata.initialPositionInParentMesh - doorPivot
        door.setPosition(doorPosition)
        aircraft.addChild(door)
    }

    /// Update animation based on animator state
    func animate(with animator: LandingGearAnimator) {
        // Strut rotates inward during retraction
        let strutAngle = animator.sequencedStrutAngleRadians
        strut.setRotation(angle: strutAngle, axis: strutRotationAxis)

        // Door rotates outward to open
        let doorAngle = animator.doorAngleRadians
        door.setRotation(angle: doorAngle, axis: doorRotationAxis)
    }

    /// Update animation based on raw progress value (0 = deployed, 1 = retracted)
    func animate(progress: Float) {
        // Simple linear animation without sequencing
        let strutAngle = (progress * 90.0).toRadians
        strut.setRotation(angle: strutAngle, axis: strutRotationAxis)

        // Door animation with open/close sequence
        let doorProgress: Float
        if progress < 0.3 {
            doorProgress = progress / 0.3
        } else if progress < 0.7 {
            doorProgress = 1.0
        } else {
            doorProgress = 1.0 - ((progress - 0.7) / 0.3)
        }

        let doorAngle = (doorProgress * 90.0).toRadians
        door.setRotation(angle: doorAngle, axis: doorRotationAxis)
    }
}
