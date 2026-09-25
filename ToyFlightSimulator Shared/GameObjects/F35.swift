//
//  F35.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/21/23.
//

class F35: Aircraft {
    static let NAME: String = "F-35"

    /// Center of mass in the import frame (meters, engine axes, origin as authored), baked
    /// out of the vertices by `ModelLibrary`'s `.Sketchfab_F35` registration so it becomes
    /// the rotation pivot. Height: the nose→nozzle line at the authored station (the file's
    /// origin sits on the ground, 1.0 m below it). Station unchanged: the skinned gear is
    /// measured in its bind pose, which is not a gear-down tricycle.
    /// Re-measure with `swift scripts/measure_center_of_mass.swift --model f35`.
    static let centerOfMassInImportFrame: float3 = [0, 1.003, 0]

    // Authored against the file's origin; re-expressed in the body frame (old − c).
    override var cameraOffset: float3 {
        [0, 6, -18] - F35.centerOfMassInImportFrame
    }

    init(scale: Float = 1.0, shouldUpdateOnPlayerInput: Bool = true) {
        super.init(name: Self.NAME,
                   aircraftType: .f35,
                   modelType: .Sketchfab_F35,
                   scale: scale,
                   shouldUpdateOnPlayerInput: shouldUpdateOnPlayerInput)
        setupAnimator(F35Animator.init)
    }
}
