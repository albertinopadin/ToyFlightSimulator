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
    
    let engineThrust: Float = 70  // 70,000 lbs of thrust
    
    override var cameraOffset: float3 {
        [0, 55, -150]
    }
    
    override var rigidBody: RigidBody? {
        didSet {
            rigidBody?.restitution = 0.1
            rigidBody?.mass = 30
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
        if let rigidBody, shouldUpdateOnPlayerInput && hasFocus {
            applyEngineAndLiftForces(rigidBody: rigidBody)

            let deltaTurn = Float(GameTime.DeltaTime) * _turnSpeed
            let deltaMove = Float(GameTime.DeltaTime) * _moveSpeed
            applyPlayerAttitudeInput(deltaTurn: deltaTurn)
            applyPlayerSideMove(deltaMove: deltaMove)
            handleGearToggle()

            animator?.update(deltaTime: Float(GameTime.DeltaTime))
        } else {
            super.doUpdate()
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

    private func applyEngineAndLiftForces(rigidBody: RigidBody) {
        let fwd = getFwdVector()
        let engineForce = fwd * engineThrust * InputManager.ContinuousCommand(.MoveFwd) * 10.0
        let lift = max(0, dot(rigidBody.velocity, fwd)) * 100.0
        rigidBody.force += engineForce + getUpVector() * lift
    }
}
