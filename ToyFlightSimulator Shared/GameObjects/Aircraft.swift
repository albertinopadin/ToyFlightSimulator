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
    
    internal var gearDown: Bool = true
    
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
        
        self.rotateZ(deltaTurn * InputManager.ContinuousCommand(.Roll))
        
        self.rotateX(deltaTurn * InputManager.ContinuousCommand(.Pitch))
        
        self.rotateY(deltaTurn * InputManager.ContinuousCommand(.Yaw))
        
        moveAlongVector(getFwdVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveFwd))
        
        moveAlongVector(getRightVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveSide))
    }
}

