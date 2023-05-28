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
        
        if Keyboard.IsKeyPressed(.leftArrow) {
            self.rotateZ(-deltaTurn)
        }
        
        if Keyboard.IsKeyPressed(.rightArrow) {
            self.rotateZ(deltaTurn)
        }
        
        if Keyboard.IsKeyPressed(.upArrow) {
            self.rotateX(-deltaTurn)
        }
        
        if Keyboard.IsKeyPressed(.downArrow) {
            self.rotateX(deltaTurn)
        }
        
        if Keyboard.IsKeyPressed(.q) {
            self.rotateY(deltaTurn)
        }
        
        if Keyboard.IsKeyPressed(.e) {
            self.rotateY(-deltaTurn)
        }
        
        if Keyboard.IsKeyPressed(.a) {
            moveAlongVector(getRightVector(), distance: -deltaMove)
        }
        
        if Keyboard.IsKeyPressed(.d) {
            moveAlongVector(getRightVector(), distance: deltaMove)
        }
        
        if Keyboard.IsKeyPressed(.w) {
            moveAlongVector(getFwdVector(), distance: deltaMove)
        }
        
        if Keyboard.IsKeyPressed(.s) {
            moveAlongVector(getFwdVector(), distance: -deltaMove)
        }
    }
}

