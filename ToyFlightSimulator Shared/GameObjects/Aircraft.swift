//
//  Aircraft.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 2/11/23.
//

import MetalKit

class Aircraft: GameObject {
//    public var containerNode: ContainerNode?
    public var shouldUpdateOnPlayerInput: Bool
    
    private var _moveSpeed: Float = 25.0
    private var _turnSpeed: Float = 4.0
    
    internal var gearDown: Bool = true
    
    public var cameraOffset: float3 {
        [0, 10, 20]
    }
    
    init(name: String, modelType: ModelType, scale: Float = 1.0, shouldUpdateOnPlayerInput: Bool = true) {
        self.shouldUpdateOnPlayerInput = shouldUpdateOnPlayerInput
        super.init(name: name, modelType: modelType)
        self.setScale(scale)
        print("[Aircraft init] name: \(name), scale: \(scale)")
        self.hasFocus = true  // TODO: This doesn't look right...
    }
    
    override func doUpdate() {
        super.doUpdate()
        
        if shouldUpdateOnPlayerInput && hasFocus {
            let deltaMove = Float(GameTime.DeltaTime) * _moveSpeed
            let deltaTurn = Float(GameTime.DeltaTime) * _turnSpeed
            
            self.rotateZ(deltaTurn * InputManager.ContinuousCommand(.Roll))
            self.rotateX(deltaTurn * InputManager.ContinuousCommand(.Pitch))
            self.rotateY(deltaTurn * InputManager.ContinuousCommand(.Yaw))
            
            self.moveAlongVector(getFwdVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveFwd))
            self.moveAlongVector(getRightVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveSide))
            
//            if let containerNode {
//                containerNode.rotateZ(deltaTurn * InputManager.ContinuousCommand(.Roll))
//                containerNode.rotateX(deltaTurn * InputManager.ContinuousCommand(.Pitch))
//                containerNode.rotateY(deltaTurn * InputManager.ContinuousCommand(.Yaw))
//                
//                containerNode.moveAlongVector(containerNode.getFwdVector(), 
//                                              distance: deltaMove * InputManager.ContinuousCommand(.MoveFwd))
//                containerNode.moveAlongVector(containerNode.getRightVector(), 
//                                              distance: deltaMove * InputManager.ContinuousCommand(.MoveSide))
//            } else {
//                self.rotateZ(deltaTurn * InputManager.ContinuousCommand(.Roll))
//                self.rotateX(deltaTurn * InputManager.ContinuousCommand(.Pitch))
//                self.rotateY(deltaTurn * InputManager.ContinuousCommand(.Yaw))
//                
//                self.moveAlongVector(getFwdVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveFwd))
//                self.moveAlongVector(getRightVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveSide))
//            }
        }
    }
}

