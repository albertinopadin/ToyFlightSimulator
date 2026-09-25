//
//  F22.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/20/24.
//

import MetalKit

class F22: Aircraft {
    static let NAME: String = "F-22"
    /// Center of mass in the import frame (meters, engine axes, origin as authored), baked
    /// out of the vertices by `ModelLibrary`'s `.Sketchfab_F22` registration so it becomes
    /// the rotation pivot. The authored origin is already on the nose→nozzle line (−0.018)
    /// but sits 1.785 m BEHIND the main wheels, so the station moves forward to where the
    /// nose wheel would carry 12 % of the weight (Raymer: 8–15 %): z = 2.512.
    /// Re-measure with `swift scripts/measure_center_of_mass.swift --model "f22 sketchfab"`.
    static let centerOfMassInImportFrame: float3 = [0, -0.018, 2.512]

    let afterburnerLeft = Afterburner(name: "F-22 Left Afterburner")
    let afterburnerRight = Afterburner(name: "F-22 Right Afterburner")

    // Authored against the file's origin; re-expressed in the body frame (old − c).
    override var cameraOffset: float3 {
        [0, 7, -20] - F22.centerOfMassInImportFrame
    }
    
    override var rigidBody: RigidBody? {
        didSet {
            rigidBody?.restitution = 0.1
        }
    }
    
    init(scale: Float = 1.0, shouldUpdateOnPlayerInput: Bool = true) {
        super.init(name: Self.NAME,
                   aircraftType: .f22,
                   modelType: .Sketchfab_F22,
                   scale: scale,
                   shouldUpdateOnPlayerInput: shouldUpdateOnPlayerInput)
        
        // Mechanical ×s rescale (s = 0.09960, the draw-space meterization factor) of the
        // old native-unit offsets — same model-relative placement as before.
        // TODO(meterization): eyeball against the actual nozzles in meters.
        // Authored against the file's origin, so re-expressed in the body frame (old − c):
        // without it the plumes start 2.5 m ahead of the nozzles, inside the fuselage.
        afterburnerLeft.off()
        afterburnerLeft.setPosition(float3(-0.600, 0.098, -4) - F22.centerOfMassInImportFrame)
        addChild(afterburnerLeft)

        afterburnerRight.off()
        afterburnerRight.setPosition(float3(0.600, 0.098, -4) - F22.centerOfMassInImportFrame)
        addChild(afterburnerRight)
    }
    
    override func doUpdate() {
        super.doUpdate()
        
        // TODO(flight-model): replace with proper ground-plane collision response.
        // Without zeroing downward velocity, the position resets every frame but
        // the downward velocity keeps accumulating, so the clamp pins harder and
        // harder each step.
        if getPositionY() < 0 {
            setPositionY(0.0)
            if let rigidBody, rigidBody.velocity.y < 0 {
                rigidBody.velocity.y = 0
            }
        }
        
        if hasFocus {
            let fwdValue = InputManager.ContinuousCommand(.MoveFwd)
            
            if fwdValue > 0.8 {
                afterburnerLeft.on()
                afterburnerRight.on()
            } else {
                afterburnerLeft.off()
                afterburnerRight.off()
            }
        }
    }
}
