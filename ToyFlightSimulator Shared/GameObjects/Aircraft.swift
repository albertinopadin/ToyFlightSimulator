//
//  Aircraft.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 2/11/23.
//

import MetalKit

class Aircraft: GameObject {
    private var _camera: AttachedCamera?
    private static let _defaultCameraPositionOffset = float3(0, 2, 4)
    
    private var _X: float3!
    private var _Y: float3!
    private var _Z: float3!
    
    private var _lastFwdVector: float3 = float3(0, 0, 0)
    
    private var _moveSpeed: Float = 25.0
    private var _turnSpeed: Float = 4.0
    
    override init(name: String, meshType: MeshType, renderPipelineStateType: RenderPipelineStateType = .OpaqueMaterial) {
        super.init(name: name, meshType: meshType, renderPipelineStateType: renderPipelineStateType)
    }
    
    init(name: String,
         meshType: MeshType,
         renderPipelineStateType: RenderPipelineStateType,
         camera: AttachedCamera,
         cameraOffset: float3 = _defaultCameraPositionOffset,
         scale: Float = 1.0) {
        _camera = camera
        _camera?.setPosition(cameraOffset)
        _camera?.positionOffset = cameraOffset
        _camera?.setRotationX(Float(-15).toRadians)
        _camera?.setScale(1/scale)  // Set the inverse of parent scale to preserve view matrix
        super.init(name: name, meshType: meshType, renderPipelineStateType: renderPipelineStateType)
        print("[Aircraft init] name: \(name), scale: \(scale)")
        addChild(camera)
    }
    
    override func doUpdate() {
        let deltaMove = GameTime.DeltaTime * _moveSpeed
        let deltaTurn = GameTime.DeltaTime * _turnSpeed
        
//        if InputManager.HasCommand(.RollLeft) {
//            self.rotateZ(-deltaTurn)
//        }
//
//        if InputManager.HasCommand(.RollRight) {
//            self.rotateZ(deltaTurn)
//        }
        
        self.rotateZ(deltaTurn * InputManager.ContinuousCommand(.Roll))
        
//        if InputManager.HasCommand(.PitchUp) {
//            self.rotateX(-deltaTurn)
//        }
//
//        if InputManager.HasCommand(.PitchDown) {
//            self.rotateX(deltaTurn)
//        }
        
        self.rotateX(deltaTurn * InputManager.ContinuousCommand(.Pitch))
        
//        if InputManager.HasCommand(.YawLeft) {
//            self.rotateY(deltaTurn)
//        }
//
//        if InputManager.HasCommand(.YawRight) {
//            self.rotateY(-deltaTurn)
//        }
        
        self.rotateY(deltaTurn * InputManager.ContinuousCommand(.Yaw))
        
//        if InputManager.HasCommand(.MoveLeft) {
//            moveAlongVector(getRightVector(), distance: -deltaMove)
//        }
//
//        if InputManager.HasCommand(.MoveRight) {
//            moveAlongVector(getRightVector(), distance: deltaMove)
//        }
        
//        if InputManager.HasCommand(.MoveForward) {
//            moveAlongVector(getFwdVector(), distance: deltaMove)
//        }
//
//        if InputManager.HasCommand(.MoveRearward) {
//            moveAlongVector(getFwdVector(), distance: -deltaMove)
//        }
        
        moveAlongVector(getFwdVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveFwd))
        
        moveAlongVector(getRightVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveSide))
    }
}

