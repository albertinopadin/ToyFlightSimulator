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
    
    init(scale: Float = 1.0, shouldUpdate: Bool = true) {
        super.init(name: Self.NAME,
                   meshType: .Sketchfab_F22,
                   renderPipelineStateType: .OpaqueMaterial,
                   scale: scale,
                   shouldUpdate: shouldUpdate)
        rotateX(Float(90).toRadians)
        rotateZ(Float(90).toRadians)
        
        afterburnerLeft.off()
        afterburnerLeft.rotate(deltaAngle: Float(-90).toRadians, axis: Y_AXIS)
        afterburnerLeft.setPosition(-23, -7, 1)
        addChild(afterburnerLeft)
        
        afterburnerRight.off()
        afterburnerRight.rotate(deltaAngle: Float(-90).toRadians, axis: Y_AXIS)
        afterburnerRight.setPosition(-23, 7, 1)
        addChild(afterburnerRight)
    }
    
    override func doUpdate() {
        super.doUpdate()
        
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
