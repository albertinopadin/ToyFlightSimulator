//
//  F22.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/20/24.
//

import MetalKit

class F22: Aircraft {
    static let NAME: String = "F-22"
    
    let afterburnerLeft = Afterburner(name: "F-22 Left Afterburner")
    let afterburnerRight = Afterburner(name: "F-22 Right Afterburner")
    
    override var cameraOffset: float3 {
        [0, 55, -150]
    }
    
    override var rigidBody: RigidBody? {
        didSet {
            rigidBody?.restitution = 0.1
        }
    }
    
    init(scale: Float = 1.0, shouldUpdateOnPlayerInput: Bool = true) {
        super.init(name: Self.NAME,
                   modelType: .Sketchfab_F22,
                   scale: scale,
                   shouldUpdateOnPlayerInput: shouldUpdateOnPlayerInput)
        
        afterburnerLeft.off()
        afterburnerLeft.setPosition(-7, 1, -30)
        addChild(afterburnerLeft)

        afterburnerRight.off()
        afterburnerRight.setPosition(7, 1, -30)
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
