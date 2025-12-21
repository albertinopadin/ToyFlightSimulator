//
//  NoseGearAssembly.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 12/20/24.
//

import simd

/// Represents the nose landing gear assembly with hierarchical animation
final class NoseGearAssembly {
    // Main strut that rotates backward to retract
    let strut: SubMeshGameObject

    // Wheels attached to the bottom of the strut
    let wheels: SubMeshGameObject

    // Gear doors that open/close during deployment
    let doorLeft: SubMeshGameObject
    let doorRight: SubMeshGameObject

    // Rotation axis for the main strut (rotates backward around X axis)
    let strutRotationAxis = float3(1, 0, 0)

    // Rotation axes for doors (rotate outward around Z axis)
    let leftDoorRotationAxis = float3(0, 0, 1)
    let rightDoorRotationAxis = float3(0, 0, -1)

    // Pivot points (relative to each mesh's center)
    // These may need tuning based on actual mesh geometry
    let strutPivot = float3(0, 0, 0.8)
    let doorPivot = float3(0, 0, 0.2)

    init() {
        // Create SubMeshGameObjects for each part
        strut = SubMeshGameObject(
            name: "NoseGear_Strut",
            modelType: .F18_NoseGear_Strut,
            meshType: .F18_NoseGear_Strut
        )

        wheels = SubMeshGameObject(
            name: "NoseGear_Wheels",
            modelType: .F18_NoseGear_Wheels,
            meshType: .F18_NoseGear_Wheels
        )

        doorLeft = SubMeshGameObject(
            name: "NoseGear_DoorLeft",
            modelType: .F18_NoseGear_DoorLeft,
            meshType: .F18_NoseGear_DoorLeft
        )

        doorRight = SubMeshGameObject(
            name: "NoseGear_DoorRight",
            modelType: .F18_NoseGear_DoorRight,
            meshType: .F18_NoseGear_DoorRight
        )

        setupPivotPoints()
    }

    private func setupPivotPoints() {
        // Set pivot points for rotation
        strut.setSubmeshOrigin(strutPivot)
        doorLeft.setSubmeshOrigin(doorPivot)
        doorRight.setSubmeshOrigin(doorPivot)
    }

    /// Attach the gear assembly to the parent aircraft
    func attachTo(aircraft: Node) {
        // Position strut relative to aircraft
        let strutMetadata = strut.getSubmeshVertexMetadata()
        let strutPosition = strutMetadata.initialPositionInParentMesh - strutPivot
        strut.setPosition(strutPosition)
        aircraft.addChild(strut)

        // Position wheels as child of strut (they move with strut)
        let wheelsMetadata = wheels.getSubmeshVertexMetadata()
        let wheelsRelativeToStrut = wheelsMetadata.initialPositionInParentMesh - strutMetadata.initialPositionInParentMesh
        wheels.setPosition(wheelsRelativeToStrut)
        strut.addChild(wheels)

        // Position doors relative to aircraft
        let leftDoorMetadata = doorLeft.getSubmeshVertexMetadata()
        let leftDoorPosition = leftDoorMetadata.initialPositionInParentMesh - doorPivot
        doorLeft.setPosition(leftDoorPosition)
        aircraft.addChild(doorLeft)

        let rightDoorMetadata = doorRight.getSubmeshVertexMetadata()
        let rightDoorPosition = rightDoorMetadata.initialPositionInParentMesh - doorPivot
        doorRight.setPosition(rightDoorPosition)
        aircraft.addChild(doorRight)
    }

    /// Update animation based on animator state
    func animate(with animator: LandingGearAnimator) {
        // Strut rotates backward during retraction
        let strutAngle = animator.sequencedStrutAngleRadians
        strut.setRotation(angle: strutAngle, axis: strutRotationAxis)

        // Doors rotate outward to open
        let doorAngle = animator.doorAngleRadians
        doorLeft.setRotation(angle: doorAngle, axis: leftDoorRotationAxis)
        doorRight.setRotation(angle: doorAngle, axis: rightDoorRotationAxis)
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
        doorLeft.setRotation(angle: doorAngle, axis: leftDoorRotationAxis)
        doorRight.setRotation(angle: doorAngle, axis: rightDoorRotationAxis)
    }
}
